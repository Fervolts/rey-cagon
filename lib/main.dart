import 'dart:async';

import 'emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'actualizar.dart';
import 'calendario.dart';
import 'invitar_play.dart';
import 'config.dart';
import 'onboarding.dart';
import 'perfil.dart';
import 'placer.dart';
import 'push.dart';
import 'recuperar.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'secreto.dart';
import 'tips.dart';
import 'tipos.dart';
import 'widget.dart';

export 'config.dart' show supabaseKey, supabaseUrl;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registrarLicencias();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  try {
    await iniciarRecordatorio();
    await iniciarPush();
    await iniciarWidget();
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
      // Cambios de avatar, accesorios o username.
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'profiles',
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
            db.auth.currentSession == null ? const PantallaEntrar() : const PantallaInicio(),
      ),
    );
  }
}

class PantallaEntrar extends StatefulWidget {
  const PantallaEntrar({super.key});

  @override
  State<PantallaEntrar> createState() => _PantallaEntrarState();
}

class _PantallaEntrarState extends State<PantallaEntrar> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _usuario = TextEditingController();
  bool _esRegistro = false;
  bool _ocupado = false;

  Future<void> _enviar() async {
    setState(() => _ocupado = true);
    try {
      if (_esRegistro) {
        await db.auth.signUp(
          email: _correo.text.trim(),
          password: _clave.text,
          data: {'username': _usuario.text.trim()},
        );
      } else {
        await db.auth.signInWithPassword(
          email: _correo.text.trim(),
          password: _clave.text,
        );
      }
    } on AuthException catch (e) {
      _mensaje(e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _mensaje(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final p = paleta(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            const Emoji('💩', tamano: 76),
            const SizedBox(height: 16),
            Text('REY\nCAGÓN', style: texto.headlineLarge?.copyWith(fontSize: 52, height: 0.95)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Container(height: 4, width: 56, color: acento)),
            const SizedBox(height: 12),
            Text('Compite con tus amigos por la corona.', style: texto.bodyLarge?.copyWith(color: p.textoSuave)),
            const SizedBox(height: 36),
            if (_esRegistro) ...[
              const Rotulo('Username'),
              const SizedBox(height: 6),
              TextField(controller: _usuario),
              const SizedBox(height: 16),
            ],
            const Rotulo('Email'),
            const SizedBox(height: 6),
            TextField(controller: _correo, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            const Rotulo('Contraseña'),
            const SizedBox(height: 6),
            TextField(
              controller: _clave,
              obscureText: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _ocupado ? null : _enviar(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _ocupado ? null : _enviar,
              child: Text(_esRegistro ? 'CREAR CUENTA' : 'ENTRAR'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _esRegistro = !_esRegistro),
              child: Text(_esRegistro ? 'YA TENGO CUENTA' : 'CREAR CUENTA NUEVA'),
            ),
            if (!_esRegistro)
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PantallaRecuperar(correo: _correo.text.trim()))),
                child: const Text('¿OLVIDASTE TU CONTRASEÑA?'),
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
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final yo = db.auth.currentUser!.id;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const PantallaRanking(),
          PantallaCalendario(usuarioId: yo, nombre: 'mí'),
          const PantallaTips(),
          PantallaPerfil(usuarioId: yo),
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
          NavigationDestination(icon: Icon(Icons.lightbulb_outline), selectedIcon: Icon(Icons.lightbulb), label: 'TIPS'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'PERFIL'),
        ],
        ),
      ),
    );
  }
}

const periodos = {
  'week': 'Semana',
  'month': 'Mes',
  'quarter': 'Trimestre',
  'year': 'Año',
};

class PantallaRanking extends StatefulWidget {
  const PantallaRanking({super.key});

  @override
  State<PantallaRanking> createState() => _PantallaRankingState();
}

class _PantallaRankingState extends State<PantallaRanking> {
  String _periodo = 'week';
  bool _soloSiguiendo = true;
  List<Map<String, dynamic>> _filas = [];
  List<Map<String, dynamic>> _hoy = [];
  bool _cargando = true;
  // Ranking secreto: si ya encontró la hoja de Tips, si lo está viendo y si ya aprendió a deslizar.
  bool _secretoAbierto = false;
  bool _yaDeslizo = true;
  // Con el secreto abierto la pantalla es un PageView: 0 normal, 1 el lado secreto.
  final _paginas = PageController();
  bool _asomado = false;
  // Sube con cada recarga para que el ranking secreto también se refresque.
  int _version = 0;
  late final VoidCallback _soltar;
  late final AppLifecycleListener _ciclo;
  // Se decide una vez por apertura de la app: aparece o no, y en qué esquina.
  final _secreto = Secreto();

  String get _yo => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _cargar();
    _soltar = escucharCagadas('home', () => _cargar(spinner: false));
    // Al volver de Ajustes (permiso de instalar) o de otra app, se vuelve a ofrecer la actualización.
    _ciclo = AppLifecycleListener(onResume: () => revisarActualizacion(context));
    _avisoPrimeraVez();
  }

  @override
  void dispose() {
    _paginas.dispose();
    _ciclo.dispose();
    _soltar();
    super.dispose();
  }

  Future<void> _avisoPrimeraVez() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('disclaimer_ok') ?? false) {
      await pedirPermisoNotificaciones().catchError((_) {});
      await registrarTelefono().catchError((_) {});
      if (mounted) await revisarActualizacion(context);
      if (mounted) await invitarAPlay(context);
      return;
    }
    // Cuenta nueva (sin cagadas): bienvenida completa. Si ya cagaba (reinstaló), solo el aviso.
    final yo = await db.from('profiles').select('cagadas').eq('id', _yo).maybeSingle().catchError((_) => null);
    if (!mounted) return;
    if (((yo?['cagadas'] as int?) ?? 0) == 0) {
      await Navigator.push(
        context,
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PantallaBienvenida()),
      );
      _cargar(spinner: false);
    } else {
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
    }
    await prefs.setBool('disclaimer_ok', true);
    await pedirPermisoNotificaciones().catchError((_) {});
    await registrarTelefono().catchError((_) {});
    if (mounted) await revisarActualizacion(context);
  }

  Future<void> _cargar({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) setState(() => _cargando = true);
    try {
      final (data, hoy, yo, prefs) = await (
        db.rpc('leaderboard', params: {'period': _periodo, 'solo_siguiendo': _soloSiguiendo}),
        // El aviso del día compara solo contra la gente que sigues.
        db.rpc('leaderboard', params: {'period': 'day', 'solo_siguiendo': true}),
        db.from('profiles').select('placer_desbloqueado').eq('id', _yo).maybeSingle(),
        SharedPreferences.getInstance(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _filas = List<Map<String, dynamic>>.from(data);
        _hoy = List<Map<String, dynamic>>.from(hoy);
        _secretoAbierto = yo?['placer_desbloqueado'] == true;
        _yaDeslizo = prefs.getBool('placer_deslizo') ?? false;
        _version++;
      });
      _asomar();
      reprogramarRecordatorio(yaCagoHoy: _miHoy > 0).catchError((_) {});
      actualizarWidget(_miHoy).catchError((_) {});
      refrescarRanking(db).catchError((_) {});
    } catch (e) {
      _mensaje('Error cargando ranking: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  int get _miHoy => (_hoy.where((r) => r['user_id'] == _yo).firstOrNull?['total'] ?? 0) as int;

  Future<void> _cague() async {
    HapticFeedback.mediumImpact();
    try {
      final nueva = await db.from('cagadas').insert({}).select('id').single();
      _mensaje('Registrado 💩');
      await _cargar(spinner: false);
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
      if (!_secretoAbierto || !mounted) return;
      final nota = await preguntarPlacer(context);
      if (nota != null) {
        await db.from('cagadas').update({'placer': nota.placer, 'etiquetas': nota.etiquetas.toList()}).eq('id', nueva['id']);
      }
    } on PostgrestException catch (e) {
      // El trigger limitar_cagadas devuelve el mensaje listo para mostrar.
      _mensaje(e.hint == 'limite_hora' ? e.message : 'Error: ${e.message}');
    } catch (e) {
      _mensaje('Error: $e');
    }
  }

  Future<void> _deshacer() async {
    try {
      final ultima = await db
          .from('cagadas')
          .select('id')
          .eq('user_id', _yo)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (ultima == null) return _mensaje('No hay nada que deshacer');
      await db.from('cagadas').delete().eq('id', ultima['id']);
      _mensaje('Deshecho');
      await _cargar(spinner: false);
    } catch (e) {
      _mensaje('Error: $e');
    }
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Texto del aviso del día comparado con la gente que sigues.
  String? get _avisoDelDia {
    if (_hoy.isEmpty) return null;
    final lider = _hoy.first;
    final mio = _miHoy;
    final n = lider['total'] as int;
    if (_hoy.length == 1) return 'Sigue a tus amigos para competir';
    if (n == 0) return 'Nadie ha cagado hoy. Sé el primero 💩';
    if (lider['user_id'] == _yo || mio == n) return 'Vas ganando hoy 👑';
    return '${lider['username']} cagó $n ${n == 1 ? 'vez' : 'veces'} hoy... vas perdiendo';
  }

  void _abrir(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla)).then((_) => _cargar(spinner: false));

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final p = paleta(context);
    final aviso = _avisoDelDia;
    final perdiendo = aviso?.endsWith('vas perdiendo') ?? false;
    final maximo = _filas.isEmpty ? 0 : _filas.first['total'] as int;

    final normal = RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              Expanded(child: Text('Rey Cagón', style: texto.headlineSmall)),
              IconButton.outlined(
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Buscar amigos',
                onPressed: () => _abrir(const PantallaBuscar()),
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
          if (_secretoAbierto && !_yaDeslizo) ...[
            const PistaSecreta(),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const Rotulo('Ranking'),
              const Spacer(),
              FilterChip(
                label: const Text('SOLO MIS AMIGOS'),
                labelStyle: TextStyle(color: _soloSiguiendo ? acentoTexto : null),
                selected: _soloSiguiendo,
                visualDensity: VisualDensity.compact,
                onSelected: (v) {
                  setState(() => _soloSiguiendo = v);
                  _cargar();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final e in periodos.entries)
                ButtonSegment(value: e.key, label: _UnaLinea(e.value.toUpperCase())),
            ],
            selected: {_periodo},
            showSelectedIcon: false,
            style: _compacto,
            onSelectionChanged: (s) {
              setState(() => _periodo = s.first);
              _cargar();
            },
          ),
          const SizedBox(height: 12),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _Tabla(
              filas: _filas,
              yo: _yo,
              maximo: maximo,
              onTap: (id) => _abrir(PantallaPerfil(usuarioId: id)),
            ),
            if (_soloSiguiendo && _filas.length <= 1) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: Emoji('🚽', tamano: 64)),
                      const SizedBox(height: 8),
                      const Text('Estás cagando solo. Sigue a tus amigos para competir.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _abrir(const PantallaBuscar()),
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
    );

    return SafeArea(
      child: Stack(
        children: [
          if (_secretoAbierto)
            PageView(
              controller: _paginas,
              onPageChanged: _alCambiarPagina,
              children: [normal, _ladoSecreto()],
            )
          else
            normal,
          _secreto,
          if (_secretoAbierto)
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: IgnorePointer(child: _Puntos(paginas: _paginas)),
            ),
        ],
      ),
    );
  }

  Future<void> _alCambiarPagina(int pagina) async {
    if (pagina == 1 && !_yaDeslizo) {
      setState(() => _yaDeslizo = true);
      (await SharedPreferences.getInstance()).setBool('placer_deslizo', true);
    }
  }

  /// La primera vez que se abre con el secreto desbloqueado, la página se asoma un poco
  /// hacia la izquierda para que se note que hay algo al lado.
  Future<void> _asomar() async {
    if (_asomado || _yaDeslizo || !_secretoAbierto) return;
    _asomado = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || !_paginas.hasClients) return;
    await _paginas.animateTo(90, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    if (!mounted || !_paginas.hasClients) return;
    await _paginas.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.bounceOut);
  }

  /// El lado secreto: otra pantalla, en oscuro y dorado, con su propio botón y el ranking
  /// de placenteras contra destructivas.
  Widget _ladoSecreto() => Theme(
        data: tema(Brightness.dark),
        child: Builder(builder: (context) {
          final texto = Theme.of(context).textTheme;
          final p = paleta(context);
          return ColoredBox(
            color: p.fondo,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                // Mismas medidas que el lado normal: fila de 48, botón, deshacer y una tarjeta.
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const Icon(Icons.lock_open, color: acento),
                      const SizedBox(width: 8),
                      Expanded(child: Text('El lado secreto', style: texto.headlineSmall)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(child: _BotonCague(onTap: _cague, secreto: true)),
                Center(
                  child: TextButton.icon(
                    onPressed: _deshacer,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('DESHACER LA ÚLTIMA'),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde)),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 4, color: acento),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Rotulo('Solo para los que saben'),
                                const SizedBox(height: 4),
                                Text('Aquí cada cagada se califica',
                                    style: texto.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: p.texto)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Rotulo('Ranking secreto'),
                    const Spacer(),
                    FilterChip(
                      label: const Text('SOLO MIS AMIGOS'),
                      labelStyle: TextStyle(color: _soloSiguiendo ? acentoTexto : null),
                      selected: _soloSiguiendo,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) {
                        setState(() => _soloSiguiendo = v);
                        _cargar();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final e in periodos.entries)
                      ButtonSegment(value: e.key, label: _UnaLinea(e.value.toUpperCase())),
                  ],
                  selected: {_periodo},
                  showSelectedIcon: false,
                  style: _compacto,
                  onSelectionChanged: (s) {
                    setState(() => _periodo = s.first);
                    _cargar();
                  },
                ),
                const SizedBox(height: 12),
                TablaPlacer(
                  version: _version,
                  periodo: _periodo,
                  soloSiguiendo: _soloSiguiendo,
                  onTap: (id) => _abrir(PantallaPerfil(usuarioId: id)),
                ),
              ],
            ),
          );
        }),
      );
}

/// Dos cuadritos arriba que siguen el dedo entre la página normal y la secreta.
class _Puntos extends StatelessWidget {
  const _Puntos({required this.paginas});

  final PageController paginas;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: paginas,
        builder: (context, _) {
          final pos = paginas.hasClients && paginas.position.haveDimensions ? (paginas.page ?? 0) : 0.0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 2; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8 + 14 * (1 - (pos - i).abs()).clamp(0.0, 1.0),
                  height: 8,
                  color: i == 1 ? acento : paleta(context).texto,
                ),
            ],
          );
        },
      );
}

/// Botón redondo principal; al apretarlo se encoge y cambia de color.
class _BotonCague extends StatefulWidget {
  const _BotonCague({required this.onTap, this.secreto = false});

  final VoidCallback onTap;
  // En el lado secreto: negro con aro dorado que brilla y el mojón con alas.
  final bool secreto;

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
            // Al apretar: en claro pasa de negro a amarillo; en oscuro, de amarillo a blanco.
            decoration: widget.secreto
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: _apretado ? acento : const Color(0xFF1B1407),
                    border: Border.all(color: acento, width: 4),
                    boxShadow: [BoxShadow(color: acento.withValues(alpha: _apretado ? .9 : .5), blurRadius: 36, spreadRadius: 2)],
                  )
                : BoxDecoration(
                    shape: BoxShape.circle,
                    color: _apretado ? (p.primario == acento ? p.texto : acento) : p.primario,
                  ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.secreto)
                  Image.asset('assets/img/mojon_angel.png', width: 104, height: 104)
                else
                  const Emoji('💩', tamano: 88),
                Text('CAGUÉ',
                    style: TextStyle(
                      color: _apretado ? acentoTexto : (widget.secreto ? acento : p.sobrePrimario),
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
              Emoji(emoji, tamano: 38),
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

/// Ranking como tabla. El líder va resaltado y cada fila tiene una barra relativa al líder.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.filas, required this.yo, required this.maximo, required this.onTap});

  final List<Map<String, dynamic>> filas;
  final String yo;
  final int maximo;
  final void Function(String usuarioId) onTap;

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
            _FilaTabla(puesto: i + 1, fila: f, esMio: f['user_id'] == yo, maximo: maximo, onTap: () => onTap(f['user_id'])),
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
                    style: numeros(context, tamano: 13, weight: FontWeight.w800, color: lider ? acentoTexto : p.textoSuave)),
              ),
              const SizedBox(width: 12),
              Avatar(fila, tamano: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fila['username'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: esMio ? FontWeight.w800 : FontWeight.w600, color: p.texto),
                          ),
                        ),
                        if (lider) ...[const SizedBox(width: 6), const Emoji('👑', tamano: 18)],
                      ],
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
              Text('$total', style: numeros(context, tamano: 20, weight: FontWeight.w800)),
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

/// Etiqueta de una sola línea que se encoge si no cabe.
class _UnaLinea extends StatelessWidget {
  const _UnaLinea(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(texto, maxLines: 1, softWrap: false),
      );
}
