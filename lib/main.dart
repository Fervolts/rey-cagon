import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendario.dart';
import 'perfil.dart';
import 'push.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'tipos.dart';

const supabaseUrl = 'https://TU-PROYECTO.supabase.co';
const supabaseKey = 'sb_publishable_...';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  try {
    await initRecordatorio();
    await initPush();
  } catch (_) {
    // Sin notificaciones la app igual sirve.
  }
  runApp(const ReyCagonApp());
}

final db = Supabase.instance.client;

var _canales = 0;

/// Llama [onCambio] (agrupado en 400ms) cuando alguien registra o borra una cagada o un follow,
/// y cuando la app vuelve a primer plano. Devuelve con qué soltarlo en dispose().
VoidCallback escucharCagadas(String nombre, VoidCallback onCambio) {
  Timer? espera;
  void avisar() {
    espera?.cancel();
    espera = Timer(const Duration(milliseconds: 400), onCambio);
  }

  final canal = db
      // Nombre único: puede haber dos pantallas iguales apiladas (perfil → buscar → perfil).
      .channel('$nombre-${_canales++}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'cagadas',
        callback: (_) => avisar(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'follows',
        callback: (_) => avisar(),
      )
      .subscribe();
  final ciclo = AppLifecycleListener(onResume: avisar);
  return () {
    espera?.cancel();
    ciclo.dispose();
    db.removeChannel(canal);
  };
}

class ReyCagonApp extends StatelessWidget {
  const ReyCagonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rey Cagón',
      debugShowCheckedModeBanner: false,
      theme: tema(Brightness.light),
      darkTheme: tema(Brightness.dark),
      home: StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, _) =>
            db.auth.currentSession == null ? const AuthScreen() : const Inicio(),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _signUp = false;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_signUp) {
        await db.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'username': _username.text.trim()},
        );
      } else {
        await db.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            children: [
              const Center(child: Text('💩', style: TextStyle(fontSize: 88))),
              const SizedBox(height: 8),
              Text('Rey Cagón',
                  textAlign: TextAlign.center,
                  style: texto.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
              Text('Compite con tus panas por la corona 👑',
                  textAlign: TextAlign.center,
                  style: texto.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 32),
              if (_signUp) ...[
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(hintText: 'Username', prefixIcon: Icon(Icons.alternate_email)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_signUp ? 'Crear cuenta' : 'Entrar'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => setState(() => _signUp = !_signUp),
                child: Text(_signUp ? 'Ya tengo cuenta' : '¿Nuevo? Crea tu cuenta'),
              ),
              const SizedBox(height: 24),
              Text(disclaimer,
                  textAlign: TextAlign.center,
                  style: texto.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pestañas de abajo: ranking, mi calendario, mi perfil.
class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = db.auth.currentUser!.id;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const HomeScreen(),
          CalendarioScreen(userId: me, username: 'mí'),
          PerfilScreen(userId: me),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Ranking'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendario'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

const periods = {
  'week': 'Semana',
  'month': 'Mes',
  'quarter': 'Trimestre',
  'year': 'Año',
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _period = 'week';
  bool _soloSiguiendo = true;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _hoy = [];
  bool _loading = true;
  late final VoidCallback _soltar;

  String get _me => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _soltar = escucharCagadas('home', () => _load(spinner: false));
    _avisoPrimeraVez();
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _avisoPrimeraVez() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('disclaimer_ok') ?? false) {
      await pedirPermisoNotificaciones().catchError((_) {});
      await registrarTelefono().catchError((_) {});
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Antes de empezar 👑'),
        content: const Text(disclaimer),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido, a cagar'),
          ),
        ],
      ),
    );
    await prefs.setBool('disclaimer_ok', true);
    await pedirPermisoNotificaciones().catchError((_) {});
    await registrarTelefono().catchError((_) {});
  }

  Future<void> _load({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) setState(() => _loading = true);
    try {
      final (data, hoy) = await (
        db.rpc('leaderboard', params: {'period': _period, 'solo_siguiendo': _soloSiguiendo}),
        // El aviso del día compara solo contra la gente que sigues.
        db.rpc('leaderboard', params: {'period': 'day', 'solo_siguiendo': true}),
      ).wait;
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data);
        _hoy = List<Map<String, dynamic>>.from(hoy);
      });
      reprogramarRecordatorio(yaCagoHoy: _miHoy > 0).catchError((_) {});
    } catch (e) {
      _toast('Error cargando ranking: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _miHoy => (_hoy.where((r) => r['user_id'] == _me).firstOrNull?['total'] ?? 0) as int;

  Future<void> _cague() async {
    HapticFeedback.mediumImpact();
    try {
      final nueva = await db.from('cagadas').insert({}).select('id').single();
      _toast('Registrado 💩');
      await _load(spinner: false);
      if (!mounted) return;
      final tipo = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('¿Qué salió?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: [
                for (final t in tipos.entries)
                  _Opcion(emoji: t.value.$1, texto: t.value.$2, onTap: () => Navigator.pop(context, t.key)),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prefiero no decir')),
          ],
        ),
      );
      if (tipo != null) await db.from('cagadas').update({'tipo': tipo}).eq('id', nueva['id']);
    } on PostgrestException catch (e) {
      // El trigger limitar_cagadas manda el texto listo para mostrar ("solo una por hora...").
      _toast(e.hint == 'limite_hora' ? e.message : 'Error: ${e.message}');
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _deshacer() async {
    try {
      final last = await db
          .from('cagadas')
          .select('id')
          .eq('user_id', _me)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (last == null) return _toast('No hay nada que deshacer');
      await db.from('cagadas').delete().eq('id', last['id']);
      _toast('Deshecho');
      await _load(spinner: false);
    } catch (e) {
      _toast('Error: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// "Fulanito cagó 3 veces hoy... vas perdiendo"
  String? get _avisoDelDia {
    if (_hoy.isEmpty) return null;
    final lider = _hoy.first;
    final mio = _miHoy;
    final n = lider['total'] as int;
    if (_hoy.length == 1) return 'Sigue a tus panas para competir';
    if (n == 0) return 'Nadie ha cagado hoy. Sé el primero 💩';
    if (lider['user_id'] == _me || mio == n) return 'Vas ganando hoy 👑';
    return '${lider['username']} cagó $n ${n == 1 ? 'vez' : 'veces'} hoy... vas perdiendo';
  }

  void _abrir(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla)).then((_) => _load(spinner: false));

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final yo = _rows.where((r) => r['user_id'] == _me).firstOrNull;
    final aviso = _avisoDelDia;
    final maximo = _rows.isEmpty ? 0 : _rows.first['total'] as int;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(yo == null ? 'Rey Cagón' : 'Hola, ${yo['username']} ${yo['avatar']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: texto.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      if (aviso != null)
                        Text(aviso, style: texto.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Buscar panas',
                  onPressed: () => _abrir(const BuscarScreen()),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(child: _BotonCague(onTap: _cague)),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _miHoy == 0 ? 'Hoy no has cagado' : 'Hoy llevas $_miHoy 💩',
                style: texto.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: _deshacer,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Deshacer la última'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Ranking', style: texto.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const Spacer(),
                FilterChip(
                  label: const Text('Solo mis panas'),
                  selected: _soloSiguiendo,
                  onSelected: (v) {
                    setState(() => _soloSiguiendo = v);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                for (final p in periods.entries)
                  ButtonSegment(value: p.key, label: _UnaLinea(p.value)),
              ],
              selected: {_period},
              showSelectedIcon: false,
              style: _compacto,
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _load();
              },
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_rows.isNotEmpty) _Podio(top: _rows.take(3).toList(), me: _me, onTap: (id) => _abrir(PerfilScreen(userId: id))),
              const SizedBox(height: 12),
              for (final (i, r) in _rows.indexed.skip(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Fila(
                    puesto: i + 1,
                    fila: r,
                    maximo: maximo,
                    esMio: r['user_id'] == _me,
                    onTap: () => _abrir(PerfilScreen(userId: r['user_id'])),
                  ),
                ),
              if (_soloSiguiendo && _rows.length <= 1)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('🚽', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 8),
                        const Text('Estás cagando solo. Sigue a tus panas para competir.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => _abrir(const BuscarScreen()),
                          child: const Text('Buscar panas'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 28),
            Text(disclaimer,
                textAlign: TextAlign.center,
                style: texto.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Botón redondo grande con rebote al tocarlo.
class _BotonCague extends StatefulWidget {
  const _BotonCague({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BotonCague> createState() => _BotonCagueState();
}

class _BotonCagueState extends State<_BotonCague> {
  bool _apretado = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _apretado = true),
      onTapUp: (_) => setState(() => _apretado = false),
      onTapCancel: () => setState(() => _apretado = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _apretado ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Semantics(
          button: true,
          label: 'Cagué',
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFA0673F), Color(0xFF5E3519)],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('💩', style: TextStyle(fontSize: 72)),
                Text('CAGUÉ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.emoji, required this.texto, required this.onTap});

  final String emoji;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 4),
                Text(texto,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      );
}

/// Los 3 primeros en escalones: 2º, 1º, 3º.
class _Podio extends StatelessWidget {
  const _Podio({required this.top, required this.me, required this.onTap});

  final List<Map<String, dynamic>> top;
  final String me;
  final void Function(String userId) onTap;

  @override
  Widget build(BuildContext context) {
    const alturas = [110.0, 80.0, 60.0];
    const colores = [oro, plata, bronce];
    const medallas = ['👑', '🥈', '🥉'];
    final orden = [1, 0, 2].where((i) => i < top.length);
    final texto = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in orden)
          Expanded(
            child: GestureDetector(
              onTap: () => onTap(top[i]['user_id']),
              child: Column(
                children: [
                  Text(medallas[i], style: TextStyle(fontSize: i == 0 ? 30 : 22)),
                  CircleAvatar(
                    radius: i == 0 ? 34 : 28,
                    backgroundColor: colores[i].withValues(alpha: 0.25),
                    child: Text(top[i]['avatar'], style: TextStyle(fontSize: i == 0 ? 34 : 26)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    top[i]['username'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texto.titleSmall?.copyWith(
                      fontWeight: top[i]['user_id'] == me ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: alturas[i],
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: colores[i].withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    alignment: Alignment.center,
                    child: Text('${top[i]['total']}',
                        style: texto.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: Colors.black87)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.puesto, required this.fila, required this.maximo, required this.esMio, required this.onTap});

  final int puesto;
  final Map<String, dynamic> fila;
  final int maximo;
  final bool esMio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final total = fila['total'] as int;
    return Card(
      color: esMio ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('$puesto', style: texto.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(fila['avatar'], style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fila['username'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texto.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maximo == 0 ? 0 : total / maximo,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('$total', style: texto.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

final _compacto = SegmentedButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 4),
);

/// Etiqueta que nunca parte en dos líneas: si no cabe (pantallas angostas o letra grande) se encoge.
class _UnaLinea extends StatelessWidget {
  const _UnaLinea(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(texto, maxLines: 1, softWrap: false),
      );
}
