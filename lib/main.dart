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
import 'widget.dart';

const supabaseUrl = 'https://TU-PROYECTO.supabase.co';
const supabaseKey = 'sb_publishable_...';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  try {
    await initRecordatorio();
    await initPush();
    await initWidget();
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
    final p = paleta(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            const Text('💩', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('REY\nCAGÓN', style: texto.headlineLarge?.copyWith(fontSize: 52, height: 0.95)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Container(height: 4, width: 56, color: acento)),
            const SizedBox(height: 12),
            Text('Compite con tus amigos por la corona.', style: texto.bodyLarge?.copyWith(color: p.textoSuave)),
            const SizedBox(height: 36),
            if (_signUp) ...[
              const Rotulo('Username'),
              const SizedBox(height: 6),
              TextField(controller: _username),
              const SizedBox(height: 16),
            ],
            const Rotulo('Email'),
            const SizedBox(height: 6),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            const Rotulo('Contraseña'),
            const SizedBox(height: 6),
            TextField(
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_signUp ? 'CREAR CUENTA' : 'ENTRAR'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _signUp = !_signUp),
              child: Text(_signUp ? 'YA TENGO CUENTA' : 'CREAR CUENTA NUEVA'),
            ),
            const SizedBox(height: 32),
            Text(disclaimer, style: texto.bodySmall?.copyWith(color: p.textoSuave)),
          ],
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
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: paleta(context).borde))),
        child: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'RANKING'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'CALENDARIO'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'PERFIL'),
        ],
        ),
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
      actualizarWidget(_miHoy).catchError((_) {});
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
            Text('¿QUÉ SALIÓ?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
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
    if (_hoy.length == 1) return 'Sigue a tus amigos para competir';
    if (n == 0) return 'Nadie ha cagado hoy. Sé el primero 💩';
    if (lider['user_id'] == _me || mio == n) return 'Vas ganando hoy 👑';
    return '${lider['username']} cagó $n ${n == 1 ? 'vez' : 'veces'} hoy... vas perdiendo';
  }

  void _abrir(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla)).then((_) => _load(spinner: false));

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final p = paleta(context);
    final aviso = _avisoDelDia;
    final perdiendo = aviso?.endsWith('vas perdiendo') ?? false;
    final maximo = _rows.isEmpty ? 0 : _rows.first['total'] as int;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(
              children: [
                Expanded(child: Text('Rey Cagón', style: texto.headlineSmall)),
                IconButton.outlined(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Buscar amigos',
                  onPressed: () => _abrir(const BuscarScreen()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 8),
            Center(child: _BotonCague(onTap: _cague)),
            Center(
              child: TextButton.icon(
                onPressed: _deshacer,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('DESHACER LA ÚLTIMA'),
              ),
            ),
            const SizedBox(height: 8),
            if (aviso != null) ...[
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: p.tarjeta,
                  border: Border.all(color: p.borde),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 4, color: perdiendo ? const Color(0xFFB3261E) : acento),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Rotulo('Hoy · llevas $_miHoy'),
                              const SizedBox(height: 4),
                              Text(aviso, style: texto.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                const Rotulo('Ranking'),
                const Spacer(),
                FilterChip(
                  label: const Text('SOLO MIS AMIGOS'),
                  selected: _soloSiguiendo,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) {
                    setState(() => _soloSiguiendo = v);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                for (final e in periods.entries)
                  ButtonSegment(value: e.key, label: _UnaLinea(e.value.toUpperCase())),
              ],
              selected: {_period},
              showSelectedIcon: false,
              style: _compacto,
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _Tabla(
                filas: _rows,
                me: _me,
                maximo: maximo,
                onTap: (id) => _abrir(PerfilScreen(userId: id)),
              ),
              if (_soloSiguiendo && _rows.length <= 1) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Estás cagando solo. Sigue a tus amigos para competir.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _abrir(const BuscarScreen()),
                          child: const Text('BUSCAR AMIGOS'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 28),
            Text(disclaimer, style: texto.bodySmall?.copyWith(color: p.textoSuave)),
          ],
        ),
      ),
    );
  }
}

/// Círculo negro grande; al apretarlo se encoge un poco y se pone amarillo corona.
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
    final p = paleta(context);
    return Semantics(
      button: true,
      label: 'Cagué',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _apretado = true),
        onTapUp: (_) => setState(() => _apretado = false),
        onTapCancel: () => setState(() => _apretado = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _apretado ? 0.94 : 1,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 200,
            height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _apretado ? acento : p.primario),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('💩', style: TextStyle(fontSize: 72)),
                Text('CAGUÉ',
                    style: TextStyle(
                      color: _apretado ? acentoTexto : p.sobrePrimario,
                      fontSize: 24,
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
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Material(
      color: p.tarjeta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radio),
        side: BorderSide(color: p.borde),
      ),
      child: InkWell(
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
}

/// Ranking como tabla: puesto en mono, el líder con fondo amarillo y una barra fina contra el líder.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.filas, required this.me, required this.maximo, required this.onTap});

  final List<Map<String, dynamic>> filas;
  final String me;
  final int maximo;
  final void Function(String userId) onTap;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: const [
                SizedBox(width: 44, child: Rotulo('#')),
                Expanded(child: Rotulo('Amigo')),
                Rotulo('Total'),
              ],
            ),
          ),
          for (final (i, f) in filas.indexed) ...[
            Divider(color: i == 0 ? p.bordeFuerte : p.borde),
            _FilaTabla(puesto: i + 1, fila: f, esMio: f['user_id'] == me, maximo: maximo, onTap: () => onTap(f['user_id'])),
          ],
        ],
      ),
    );
  }
}

class _FilaTabla extends StatelessWidget {
  const _FilaTabla({required this.puesto, required this.fila, required this.esMio, required this.maximo, required this.onTap});

  final int puesto;
  final Map<String, dynamic> fila;
  final bool esMio;
  final int maximo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final total = fila['total'] as int;
    final lider = puesto == 1 && total > 0;
    return Material(
      color: esMio ? p.suave : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                color: lider ? acento : null,
                child: Text(puesto.toString().padLeft(2, '0'),
                    style: numeros(context, size: 13, weight: FontWeight.w800, color: lider ? acentoTexto : p.textoSuave)),
              ),
              const SizedBox(width: 12),
              Text(fila['avatar'], style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${fila['username']}${lider ? '  👑' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: esMio ? FontWeight.w800 : FontWeight.w600, color: p.texto),
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 3,
                          width: maximo == 0 ? 0 : c.maxWidth * total / maximo,
                          color: lider ? acento : p.texto,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('$total', style: numeros(context, size: 20, weight: FontWeight.w800)),
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
