import 'dart:async';
import 'dart:math';

import 'emoji.dart';
import 'genero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'actualizar.dart';
import 'amigos.dart';
import 'animaciones.dart';
import 'avisos.dart';
import 'cagadon.dart';
import 'calendario.dart';
import 'chat.dart';
import 'comunidad.dart';
import 'idioma.dart';
import 'inodoro.dart';
import 'invitar_play.dart';
import 'config.dart';
import 'onboarding.dart';
import 'parte.dart';
import 'perfil.dart';
import 'periodos.dart';
import 'placer.dart';
import 'racha.dart';
import 'push.dart';
import 'recuperar.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'secreto.dart';
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
  await iniciarIdioma();
  await iniciarTema();
  await iniciarMovimiento();
  await cargarGenero();
  await elegirNombreSala();
  // Al cambiar de idioma en Perfil: otro nombre de sala y los avisos en el idioma nuevo.
  idioma.addListener(() {
    elegirNombreSala();
    registrarTelefono().catchError((_) {});
  });
  runApp(const ReyCagonApp());
}

final db = Supabase.instance.client;

var _canales = 0;

/// Llama [onCambio] (agrupado en 400ms) cuando alguien registra o borra una cagada o un follow,
/// y cuando la app vuelve a primer plano. Devuelve con qué soltarlo en dispose().
/// Errores de red: el teléfono cortó la conexión (pantalla apagada, app en segundo plano, cambio
/// de wifi a datos). No son fallas de verdad: se reintenta y no se le muestra nada feo a nadie.
bool esDeRed(Object e) {
  if (e is ParallelWaitError) {
    final errores = e.errors;
    if (errores is Iterable) return errores.whereType<Object>().any((x) => esDeRed(x is AsyncError ? x.error : x));
  }
  final t = e.toString();
  return e is TimeoutException ||
      t.contains('ClientException') ||
      t.contains('SocketException') ||
      t.contains('connection abort') ||
      t.contains('Connection reset') ||
      t.contains('Connection closed') ||
      t.contains('Failed host lookup');
}

/// Mensaje para la gente: nada de trazas técnicas.
String textoError(Object e) {
  if (esDeRed(e)) return tr('Sin conexión. Revisa tu internet e intenta de nuevo.', 'No connection. Check your internet and try again.');
  if (e is PostgrestException) return trServidor(e.message);
  if (e is ParallelWaitError) {
    final errores = e.errors;
    if (errores is Iterable) {
      final pg = errores.whereType<Object>().map((x) => x is AsyncError ? x.error : x).whereType<PostgrestException>().firstOrNull;
      if (pg != null) return trServidor(pg.message);
    }
  }
  return tr('Algo falló. Intenta de nuevo.', 'Something broke. Try again.');
}

/// Corre la consulta y, si la red se cayó un momento, la repite hasta 2 veces.
Future<T> conReintento<T>(Future<T> Function() consulta) async {
  for (var intento = 0;; intento++) {
    try {
      return await consulta();
    } catch (e) {
      if (!esDeRed(e) || intento >= 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 700 * (intento + 1)));
    }
  }
}

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
    return ListenableBuilder(
      listenable: Listenable.merge([idioma, temaElegido]),
      builder: (context, _) => MaterialApp(
        // Cambiar de idioma rearma toda la app con los textos nuevos.
        key: ValueKey(idioma.value),
        title: tr('Rey Cagón', 'King of the Throne'),
        debugShowCheckedModeBanner: false,
        theme: tema(Brightness.light),
        darkTheme: tema(Brightness.dark),
        themeMode: temaElegido.value,
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (context, _) =>
              db.auth.currentSession == null ? const PantallaEntrar() : const PantallaInicio(),
        ),
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
      _mensaje(trServidor(e.message));
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
            Text(tr('REY\nCAGÓN', 'KING OF\nTHE THRONE'), style: texto.headlineLarge?.copyWith(fontSize: 52, height: 0.95)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Container(height: 4, width: 56, color: acento)),
            const SizedBox(height: 12),
            Text(tr('Compite con tus amigos por la corona.', 'Battle your friends for the crown.'), style: texto.bodyLarge?.copyWith(color: p.textoSuave)),
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
            Rotulo(tr('Contraseña', 'Password')),
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
              child: Text(_esRegistro ? tr('CREAR CUENTA', 'CREATE ACCOUNT') : tr('ENTRAR', 'LOG IN')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _esRegistro = !_esRegistro),
              child: Text(_esRegistro ? tr('YA TENGO CUENTA', 'I HAVE AN ACCOUNT') : tr('CREAR CUENTA NUEVA', 'CREATE NEW ACCOUNT')),
            ),
            if (!_esRegistro)
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PantallaRecuperar(correo: _correo.text.trim()))),
                child: Text(tr('¿OLVIDASTE TU CONTRASEÑA?', 'FORGOT YOUR PASSWORD?')),
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
  static const _tabBano = 2;
  int _tab = 0;

  // Puntito en la pestaña del baño: hay mensajes de otros desde la última vez que entraste.
  final _subs = <StreamSubscription>[];
  // La general y la de tu idioma; los ids son de una sola secuencia, así que se comparan directo.
  int _ultimoGeneral = 0, _ultimoIdioma = 0, _vistoBano = 0, _ultimoSoporte = 0, _vistoSoporte = 0;

  int get _ultimoBano => max(_ultimoGeneral, _ultimoIdioma);

  late final VoidCallback _soltarAvisos;

  String get _yo => db.auth.currentUser!.id;
  bool get _hayNuevo => _ultimoBano > _vistoBano || _ultimoSoporte > _vistoSoporte;

  @override
  void initState() {
    super.initState();
    _soltarAvisos = escucharAvisos(onAnuncio: () {
      if (mounted) mostrarAnuncioNuevo(context);
    });
    irA.addListener(_irA);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _irA();
      if (mounted) mostrarAnuncioNuevo(context);
    });
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _vistoBano = prefs.getInt('bano_visto') ?? 0;
        _vistoSoporte = prefs.getInt('soporte_visto') ?? 0;
      });
      _subs
        ..add(_escucharUltimo('sala', 'global', (id) => _ultimoGeneral = id))
        ..add(_escucharUltimo('sala', idioma.value, (id) => _ultimoIdioma = id))
        ..add(_escucharUltimo('hilo', _yo, (id) => _ultimoSoporte = id));
    });
  }

  // El último mensaje de otra persona en esa sala; los propios cuentan como vistos.
  StreamSubscription _escucharUltimo(String columna, String valor, void Function(int) poner) => db
      .from('mensajes')
      .stream(primaryKey: ['id'])
      .eq(columna, valor)
      .order('id')
      .limit(1)
      .listen((filas) {
        if (filas.isEmpty || !mounted) return;
        final m = filas.first;
        setState(() => poner(m['id'] as int));
        if (m['user_id'] == _yo || _tab == _tabBano) _marcarVisto();
      }, onError: (_) {});

  // Un toque en un push o en un aviso: cambiar de pestaña (el baño elige después su sub-pestaña).
  void _irA() {
    final destino = irA.value;
    if (destino == null || destino.inicio || !mounted) return;
    destino.inicio = true;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _tab = destino.a == 'inicio' || destino.a == 'avisos' ? 0 : _tabBano);
    if (_tab == _tabBano) _marcarVisto();
    if (destino.a == 'avisos') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaAvisos()));
    }
  }

  Future<void> _marcarVisto() async {
    setState(() {
      _vistoBano = _ultimoBano;
      _vistoSoporte = _ultimoSoporte;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bano_visto', _vistoBano);
    await prefs.setInt('soporte_visto', _vistoSoporte);
  }

  @override
  void dispose() {
    _soltarAvisos();
    irA.removeListener(_irA);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yo = _yo;
    final mq = MediaQuery.of(context);
    // Cuatro pestañas en cualquier ancho: la letra se achica para que "CALENDARIO" no salte de línea,
    // y la barra ignora el tamaño de letra del sistema por encima de 1.0.
    final tam = ((mq.size.width / 4 - 10) / 7.2).clamp(8.0, 11.0);
    Widget icono(IconData i) => Badge(
          isLabelVisible: _hayNuevo,
          smallSize: 9,
          backgroundColor: const Color(0xFFE5484D),
          child: Icon(i),
        );
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const PantallaRanking(),
          PantallaCalendario(usuarioId: yo, nombre: tr('mí', 'me')),
          const PantallaChat(),
          PantallaPerfil(usuarioId: yo),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: paleta(context).borde))),
        child: MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.0)),
          child: NavigationBarTheme(
            data: NavigationBarTheme.of(context).copyWith(
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: tam, fontWeight: FontWeight.w700, letterSpacing: tam < 10 ? 0.2 : 0.6),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                if (i == _tabBano) _marcarVisto();
              },
              destinations: [
                NavigationDestination(icon: const Icon(Icons.emoji_events_outlined), selectedIcon: const Icon(Icons.emoji_events), label: tr('RANKING', 'LEADERBOARD')),
                NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month), label: tr('CALENDARIO', 'CALENDAR')),
                NavigationDestination(icon: icono(Icons.wc_outlined), selectedIcon: const Icon(Icons.wc), label: nombreCorto),
                NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('YO', 'ME')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  // Total histórico propio, para el número del parte y los hitos.
  int _misCagadas = 0;
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
    _ciclo = AppLifecycleListener(onResume: () {
      revisarActualizacion(context);
      // La conexión pudo morir en segundo plano: se recarga en silencio.
      Future<void>.delayed(const Duration(milliseconds: 600), () => _cargar(spinner: false));
    });
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
      if (mounted) await ofrecerComunidad(context);
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
          title: Text(tr('Antes de empezar 👑', 'Before we start 👑')),
          content: Text(disclaimer),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Entendido, a cagar', "Got it, let's poop")),
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
      final (data, hoy, yo, prefs) = await conReintento(() => (
            db.rpc('leaderboard', params: {'period': _periodo, 'solo_siguiendo': _soloSiguiendo}),
            // El aviso del día compara solo contra la gente que sigues.
            db.rpc('leaderboard', params: {'period': 'day', 'solo_siguiendo': true}),
            db.from('profiles').select('placer_desbloqueado, genero, cagadas').eq('id', _yo).maybeSingle(),
            SharedPreferences.getInstance(),
          ).wait);
      if (!mounted) return;
      setState(() {
        _filas = List<Map<String, dynamic>>.from(data);
        _hoy = List<Map<String, dynamic>>.from(hoy);
        _secretoAbierto = yo?['placer_desbloqueado'] == true;
        _misCagadas = (yo?['cagadas'] as num?)?.toInt() ?? _misCagadas;
        if (yo != null && yo['genero'] != miGenero) guardarGenero(yo['genero']);
        _yaDeslizo = prefs.getBool('placer_deslizo') ?? false;
        _version++;
      });
      _asomar();
      reprogramarRecordatorio(yaCagoHoy: _miHoy > 0).catchError((_) {});
      reprogramarCierres().catchError((_) {});
      actualizarWidget(_miHoy).catchError((_) {});
      refrescarRanking(db).catchError((_) {});
    } catch (e) {
      // Si fue la red, se queda lo que ya había y se recarga al volver a la app.
      if (spinner || !esDeRed(e)) _mensaje(textoError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  int get _miHoy => (_miFilaHoy?['total'] ?? 0) as int;

  Map<String, dynamic>? get _miFilaHoy => _hoy.where((r) => r['user_id'] == _yo).firstOrNull;

  int get _miPuesto => _filas.indexWhere((r) => r['user_id'] == _yo);

  /// "#2 de la semana" para la imagen de la racha, según lo que está viendo.
  String? get _miLugar {
    final i = _miPuesto;
    if (i < 0) return null;
    final cual = switch (_periodo) {
      'week' => tr('de la semana', 'this week'),
      'month' => tr('del mes', 'this month'),
      _ => tr('del año', 'this year'),
    };
    return _soloSiguiendo ? tr('#${i + 1} $cual entre amigos', '#${i + 1} $cual among friends') : '#${i + 1} $cual';
  }

  /// [animacion] es la del botón: la racha y las preguntas salen cuando el mojón ya cayó.
  Future<void> _cague(Future<void> animacion) async {
    HapticFeedback.mediumImpact();
    try {
      final nueva = await db.from('cagadas').insert({}).select('id').single();
      _mensaje(tr('Registrado 💩', 'Logged 💩'));
      await _cargar(spinner: false);
      await animacion;
      if (!mounted) return;
      await mostrarRacha(context, _miHoy, perfil: _miFilaHoy, lugar: _miLugar);
      if (!mounted) return;
      final parte = await pedirParte(context, numero: _misCagadas, secreto: _secretoAbierto);
      if (parte != null) {
        final secreta = _secretoAbierto && (parte.placer != null || parte.etiquetas.isNotEmpty);
        final cambios = {
          'tipo': ?parte.tipo,
          'peso': ?parte.peso,
          if (secreta) ...{'placer': parte.placer, 'etiquetas': parte.etiquetas.toList()},
        };
        if (cambios.isNotEmpty) await db.from('cagadas').update(cambios).eq('id', nueva['id']);
      }
      // Llegó a un hito o desbloqueó algo: ofrece presumirlo en el chat.
      if (mounted) await ofrecerPresumir(context, _misCagadas);
    } on PostgrestException catch (e) {
      // El trigger limitar_cagadas devuelve el mensaje listo para mostrar.
      _mensaje(e.hint == 'limite_hora' ? trServidor(e.message) : 'Error: ${trServidor(e.message)}');
    } catch (e) {
      _mensaje(textoError(e));
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
      if (ultima == null) return _mensaje(tr('No hay nada que deshacer', 'Nothing to undo'));
      await db.from('cagadas').delete().eq('id', ultima['id']);
      _mensaje(tr('Deshecho', 'Undone'));
      await _cargar(spinner: false);
    } catch (e) {
      _mensaje(textoError(e));
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
    if (_hoy.length == 1) return tr('Sigue a tus amigos para competir', 'Follow your friends to compete');
    if (n == 0) return tr('Nadie ha cagado hoy. Sé el primero 💩', "Nobody has pooped today. Be the first 💩");
    if (lider['user_id'] == _yo || mio == n) return tr('Vas ganando hoy 👑', "You're winning today 👑");
    return tr(
      '${lider['username']} cagó $n ${n == 1 ? 'vez' : 'veces'} hoy... vas perdiendo',
      "${lider['username']} pooped $n ${n == 1 ? 'time' : 'times'} today... you're losing",
    );
  }

  void _abrir(Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla)).then((_) => _cargar(spinner: false));

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final p = paleta(context);
    final aviso = _avisoDelDia;
    final perdiendo = aviso?.endsWith(tr('vas perdiendo', "you're losing")) ?? false;
    final maximo = _filas.isEmpty ? 0 : _filas.first['total'] as int;
    // Fuera del podio, su puesto queda fijo abajo con cuánto le falta para el de arriba.
    final puesto = _cargando ? -1 : _miPuesto;
    final barra = puesto >= 3;

    final lista = RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: conBordeAbajo(context, EdgeInsets.fromLTRB(16, 12, 16, barra ? 96 : 32)),
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('Rey Cagón', 'King of the Throne'), style: texto.headlineSmall)),
              IconButton.outlined(
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: tr('Buscar amigos', 'Find friends'),
                onPressed: () => _abrir(const PantallaBuscarAmigos()),
              ),
              const SizedBox(width: 8),
              const BotonAvisos(),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 8),
          Center(child: _BotonCague(onTap: _cague)),
          Center(
            child: TextButton.icon(
              onPressed: _deshacer,
              icon: const Icon(Icons.undo, size: 18),
              label: Text(tr('DESHACER LA ÚLTIMA', 'UNDO THE LAST ONE')),
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
                            Rotulo(tr('Hoy · llevas $_miHoy', 'Today · you have $_miHoy')),
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
          const SizedBox(height: 12),
          const RetosDeHoy(),
          const SizedBox(height: 16),
          if (_secretoAbierto && !_yaDeslizo) ...[
            const PistaSecreta(),
            const SizedBox(height: 12),
          ],
          Rotulo(tr('Ranking', 'Leaderboard')),
          const SizedBox(height: 8),
          _periodos(),
          const SizedBox(height: 8),
          _alcance(),
          const SizedBox(height: 10),
          ContadorCierre(periodo: _periodo),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _Podio(
              filas: _filas.take(3).toList(),
              yo: _yo,
              onTap: (id) => _abrir(PantallaPerfil(usuarioId: id)),
            ),
            if (_filas.length > 3)
              _Tabla(
                filas: _filas.skip(3).toList(),
                desde: 4,
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
                      Text(tr('Estás cagando solo. Sigue a tus amigos para competir.',
                          "You're pooping alone. Follow your friends to compete."), textAlign: TextAlign.center),
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
    final normal = barra
        ? Stack(
            children: [
              lista,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BarraTu(puesto: puesto + 1, fila: _filas[puesto], arriba: _filas[puesto - 1]),
              ),
            ],
          )
        : lista;

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
          // Que el psst no quede tapado por la barra TÚ.
          Padding(padding: EdgeInsets.only(bottom: barra ? 64 : 0), child: _secreto),
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

  Widget _periodos() => SegmentedButton<String>(
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
      );

  /// SOLO MIS AMIGOS o TODOS.
  Widget _alcance() {
    Widget chip(bool solo, String texto) => ChoiceChip(
          label: Text(texto),
          labelStyle: TextStyle(color: _soloSiguiendo == solo ? acentoTexto : null, fontWeight: FontWeight.w800, letterSpacing: 1),
          selected: _soloSiguiendo == solo,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) {
            if (_soloSiguiendo == solo) return;
            setState(() => _soloSiguiendo = solo);
            _cargar();
          },
        );
    return Row(
      children: [
        chip(true, tr('SOLO MIS AMIGOS', 'FRIENDS ONLY')),
        const SizedBox(width: 8),
        chip(false, tr('TODOS', 'EVERYONE')),
      ],
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
              padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 12, 16, 48)),
              children: [
                // Mismas medidas que el lado normal: fila de 48, botón, deshacer y una tarjeta.
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const Icon(Icons.lock_open, color: acento),
                      const SizedBox(width: 8),
                      Expanded(child: Text(tr('El lado secreto', 'The secret side'), style: texto.headlineSmall)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(child: _BotonCague(onTap: _cague, secreto: true)),
                Center(
                  child: TextButton.icon(
                    onPressed: _deshacer,
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(tr('DESHACER LA ÚLTIMA', 'UNDO THE LAST ONE')),
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
                                Rotulo(tr('Solo para los que saben', 'Only for those in the know')),
                                const SizedBox(height: 4),
                                Text(tr('Aquí cada cagada se califica', 'Here every poop gets a grade'),
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
                Rotulo(tr('Ranking secreto', 'Secret leaderboard')),
                const SizedBox(height: 8),
                _periodos(),
                const SizedBox(height: 8),
                _alcance(),
                const SizedBox(height: 10),
                ContadorCierre(periodo: _periodo),
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

/// Botón redondo principal; al apretarlo se encoge y cambia de color. Según el teléfono el
/// mojón vuela a un inodoro, da un brinco dentro del botón o no se mueve (ver animaciones.dart).
class _BotonCague extends StatefulWidget {
  const _BotonCague({required this.onTap, this.secreto = false});

  /// Recibe la animación para esperarla antes de abrir lo que sigue.
  final void Function(Future<void> animacion) onTap;
  // En el lado secreto: negro con aro dorado que brilla y el mojón con alas.
  final bool secreto;

  @override
  State<_BotonCague> createState() => _BotonCagueState();
}

class _BotonCagueState extends State<_BotonCague> with SingleTickerProviderStateMixin {
  bool _apretado = false;
  // Completo: el mojón se esconde mientras vuela y vuelve con rebote. Simple: brinca en su sitio.
  bool _volando = false;
  bool _vuelve = false;
  late final _brinco = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void dispose() {
    _brinco.dispose();
    super.dispose();
  }

  Future<void> _rebotar() => _brinco.forward(from: 0).orCancel.catchError((_) {});

  void _tocar() {
    final caja = context.findRenderObject() as RenderBox?;
    final nivel = movimiento(context);
    final Future<void> animacion;
    if (nivel == Movimiento.nada) {
      animacion = Future.value();
    } else if (nivel == Movimiento.completo && caja != null && caja.hasSize && !_volando) {
      animacion = _alInodoro(caja.localToGlobal(Offset.zero) & caja.size);
    } else {
      _vuelve = false;
      animacion = _rebotar();
    }
    widget.onTap(animacion);
  }

  Future<void> _alInodoro(Rect boton) async {
    setState(() => _volando = true);
    await tirarAlInodoro(context, boton: boton, secreto: widget.secreto, alSalpicar: () {
      if (!mounted) return;
      setState(() {
        _volando = false;
        _vuelve = true;
      });
      _rebotar();
    });
  }

  /// El mojón del botón con lo que le toque: escondido, volviendo o brincando.
  Widget _mojon(Widget mojon) {
    if (_volando) return Opacity(opacity: 0, child: mojon);
    return AnimatedBuilder(
      animation: _brinco,
      child: mojon,
      builder: (context, child) {
        final t = _brinco.value;
        if (_vuelve) return Transform.scale(scale: Curves.elasticOut.transform(t), child: child);
        final arco = sin(pi * t);
        // Sube, se estira en el aire y se aplasta un poco al caer.
        return Transform.translate(
          offset: Offset(0, -34 * arco),
          child: Transform.scale(scaleX: 1 - .08 * arco, scaleY: 1 + .1 * arco, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Semantics(
      button: true,
      label: tr('Cagué', 'I pooped'),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _apretado = true),
        onTapUp: (_) => setState(() => _apretado = false),
        onTapCancel: () => setState(() => _apretado = false),
        onTap: _tocar,
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
                _mojon(widget.secreto
                    ? Image.asset('assets/img/mojon_angel.png', width: 104, height: 104)
                    : const Emoji('💩', tamano: 88)),
                Text(tr('CAGUÉ', 'I POOPED'),
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

/// Ranking como tabla, del 4 para abajo. Cada fila tiene una barra relativa al líder.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.filas, this.desde = 1, required this.yo, required this.maximo, required this.onTap});

  final List<Map<String, dynamic>> filas;
  // Puesto de la primera fila: las de arriba van en el podio.
  final int desde;
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
              children: [
                const SizedBox(width: 44, child: Rotulo('#')),
                Expanded(child: Rotulo(tr('Amigo', 'Friend'))),
                const Rotulo('Total'),
              ],
            ),
          ),
          for (final (i, f) in filas.indexed) ...[
            Divider(color: i == 0 ? p.bordeFuerte : p.borde),
            _Entrada(
              key: ValueKey(f['user_id']),
              orden: i,
              child: _FilaTabla(puesto: desde + i, fila: f, esMio: f['user_id'] == yo, maximo: maximo, onTap: () => onTap(f['user_id'])),
            ),
          ],
        ],
      ),
    );
  }
}

/// Los tres primeros en escalones: el 2 a la izquierda, el 1 en el medio y el 3 a la derecha.
class _Podio extends StatelessWidget {
  const _Podio({required this.filas, required this.yo, required this.onTap});

  // Hasta tres, en orden.
  final List<Map<String, dynamic>> filas;
  final String yo;
  final void Function(String usuarioId) onTap;

  static const _alturas = [150.0, 116.0, 88.0];

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final quieto = movimiento(context) == Movimiento.nada;
    Widget columna(int i) {
      if (i >= filas.length) return const Expanded(child: SizedBox());
      final f = filas[i];
      final uno = i == 0;
      final mio = f['user_id'] == yo;
      final colorTexto = uno ? acentoTexto : p.texto;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(f['user_id']),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(f, tamano: uno ? 64 : 50),
              const SizedBox(height: 6),
              Text(
                mio ? tr('TÚ', 'YOU') : f['username'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.texto),
              ),
              const SizedBox(height: 6),
              // El escalón crece desde el piso.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _alturas[i]),
                duration: quieto ? Duration.zero : Duration(milliseconds: 500 + 120 * (2 - i)),
                curve: Curves.easeOutCubic,
                builder: (context, alto, child) => Container(
                  height: alto,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: uno ? acento : p.tarjeta,
                    border: Border(
                      top: BorderSide(color: p.bordeFuerte, width: uno ? 2 : 1),
                      left: BorderSide(color: p.bordeFuerte),
                      right: BorderSide(color: p.bordeFuerte),
                    ),
                  ),
                  child: child,
                ),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('#${i + 1}', style: numeros(context, tamano: 13, weight: FontWeight.w900, color: uno ? acentoTexto : p.textoSuave)),
                        Text('${f['total']}', style: numeros(context, tamano: 30, weight: FontWeight.w900, color: colorTexto)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.bordeFuerte, width: 2))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [columna(1), const SizedBox(width: 8), columna(0), const SizedBox(width: 8), columna(2)],
        ),
      ),
    );
  }
}

/// Barra amarilla fija abajo con el puesto propio, cuando no está en el podio.
class _BarraTu extends StatelessWidget {
  const _BarraTu({required this.puesto, required this.fila, required this.arriba});

  final int puesto;
  final Map<String, dynamic> fila;
  final Map<String, dynamic> arriba;

  @override
  Widget build(BuildContext context) {
    final falta = (arriba['total'] as int) - (fila['total'] as int);
    final quien = arriba['username'];
    return Container(
      decoration: const BoxDecoration(
        color: acento,
        border: Border(top: BorderSide(color: acentoTexto, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(puesto.toString().padLeft(2, '0'), style: numeros(context, tamano: 16, weight: FontWeight.w900, color: acentoTexto)),
          ),
          const SizedBox(width: 6),
          Avatar(fila, tamano: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tr('TÚ', 'YOU')} · ${fila['username']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, fontSize: 15)),
                Text(
                  falta == 0 ? tr('Empatado con $quien', 'Tied with $quien') : tr('A $falta de $quien', '$falta behind $quien'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${fila['total']}', style: numeros(context, tamano: 20, weight: FontWeight.w900, color: acentoTexto)),
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
                        // La barra crece desde cero y se estira o encoge al cambiar de periodo.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: maximo == 0 ? 0 : c.maxWidth * total / maximo),
                          duration: movimiento(context) == Movimiento.nada ? Duration.zero : const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, ancho, _) => Container(height: 3, width: ancho, color: lider ? acento : p.texto),
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

/// Con animaciones completas, las filas del ranking entran deslizándose una tras otra.
class _Entrada extends StatefulWidget {
  const _Entrada({super.key, required this.orden, required this.child});

  final int orden;
  final Widget child;

  @override
  State<_Entrada> createState() => _EntradaState();
}

class _EntradaState extends State<_Entrada> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _espera;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _espera != null) return;
    if (movimiento(context) != Movimiento.completo) {
      _c.value = 1;
      return;
    }
    // Las primeras diez escalonadas; las de abajo ya no se ven al abrir.
    _espera = Timer(Duration(milliseconds: 45 * min(widget.orden, 10)), () => _c.forward());
  }

  @override
  void dispose() {
    _espera?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(position: Tween(begin: const Offset(.08, 0), end: Offset.zero).animate(_t), child: widget.child),
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
