import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../fresca.dart' show frescaHasta;
import '../main.dart' show db, esDeRed;
import '../recordatorio.dart' show cancelarAvisoImperio, programarAvisoImperio;
import 'estilos.dart';
import 'estilos_mios.dart';
import 'flags.dart';
import 'motor.dart';
import 'nube.dart';
import 'racha_imperio.dart';
import 'telemetria.dart';

// ---------- Partes puras (se prueban sin Supabase) ----------

/// Al cargar, ¿manda la copia local? Solo si existe y lleva más MJ totales que la del servidor,
/// o si el servidor todavía no tiene partida. Empate: gana el servidor.
/// Jalar la cadena no sube los MJ totales, así que primero manda la copia que jaló más veces.
bool usarCopiaLocal({
  required double? mjLocal,
  required double mjServidor,
  required bool servidorVacio,
  int jaladasLocal = 0,
  int jaladasServidor = 0,
}) {
  if (mjLocal == null) return false;
  if (servidorVacio) return true;
  if (jaladasLocal != jaladasServidor) return jaladasLocal > jaladasServidor;
  return mjLocal > mjServidor;
}

/// Qué hacer cuando el servidor tiene más jaladas ([jaladasCadena]) que la partida ([jaladasPartida]).
/// Si el estado guardado en el servidor ya lleva esas jaladas ([jaladasEstadoServidor]), la partida del servidor es la
/// buena (un reinicio o un guardado de otro teléfono): se adopta. Si no, la jalada se marcó pero el guardado se perdió:
/// se jala aquí. Jalar con la partida vieja después de un reinicio regalaría Rollos con MJ que ya no existen.
enum ArregloCadena { nada, jalar, adoptar }

ArregloCadena arregloCadena({required int jaladasCadena, required int jaladasPartida, int? jaladasEstadoServidor}) {
  if (jaladasCadena <= jaladasPartida) return ArregloCadena.nada;
  if (jaladasEstadoServidor != null && jaladasEstadoServidor >= jaladasCadena) return ArregloCadena.adoptar;
  return ArregloCadena.jalar;
}

int _jaladasDe(Map<String, dynamic>? estado) => (estado?['jaladas'] as num?)?.toInt() ?? 0;

/// Desde cuándo se cobra el tiempo fuera: la marca más reciente (ms, reloj del servidor) entre las que haya.
/// null si no hay ninguna válida (partida nueva). Una marca del futuro se recorta a [ahora].
int? inicioOffline(Iterable<int?> marcas, int ahora) {
  int? mejor;
  for (final m in marcas) {
    if (m == null || m <= 0) continue;
    if (mejor == null || m > mejor) mejor = m;
  }
  return mejor == null ? null : min(mejor, ahora);
}

/// Si el servidor recortó los MJ totales (antitrampa), la partida los acepta y el saldo no puede pasarlos.
void aceptarRecorte(Partida p, double mjServidor) {
  if (mjServidor >= p.mjTotal) return;
  p.mjTotal = mjServidor;
  if (p.saldo > mjServidor) p.saldo = mjServidor;
}

/// Lo que se cuenta en una sesión de juego (bucle corriendo) para `sesion_fin`. Los pujos van solo aquí, no como eventos.
class ContadorSesion {
  ContadorSesion(this.mjInicio);

  /// MJ totales al empezar la sesión (después de cobrar el tiempo fuera).
  final double mjInicio;
  double segundos = 0;
  int pujos = 0, compras = 0;

  void sumarTiempo(double dt) {
    if (dt.isFinite && dt > 0) segundos += dt;
  }

  /// Datos de `sesion_fin`. Si el servidor recortó MJ, lo ganado no baja de 0.
  Map<String, Object?> fin(double mjTotal) =>
      {'segundos': segundos.round(), 'pujos': pujos, 'mj_ganados': max(0.0, mjTotal - mjInicio), 'compras': compras};
}

// ---------- Controlador ----------

/// Dueño de la partida del Imperio: carga y mezcla, reloj del servidor, bucle a 10 Hz y guardados.
class ControlImperio extends ChangeNotifier with WidgetsBindingObserver {
  ControlImperio({NubeImperio? nube, Telemetria? telemetria, this.pedirFlags})
      : nube = nube ?? NubeImperio(),
        _tele = telemetria ?? Telemetria.instancia;

  final NubeImperio nube;
  final Telemetria _tele;
  /// Para pruebas: de dónde salen los flags (por defecto, el RPC).
  final PedirFlags? pedirFlags;
  Imperio imperio = Imperio(ajustes: FlagsImperio.porDefecto.ajustes);

  /// Flags remotos de esta carga (defaults hasta que lleguen).
  FlagsImperio flags = FlagsImperio.porDefecto;

  /// Flag `imperio_activo` apagado: la pantalla muestra el aviso de mantenimiento y no se juega ni se guarda.
  bool get apagado => !flags.activo;

  bool cargando = true;
  bool sinConexion = false;
  bool fundador = false;

  /// Cagadas reales desde la última jalada y cuántas pide la cadena (RPC `imperio_cadena`).
  /// null mientras no llega, si el RPC no existe todavía o sin red: el botón dice PRONTO.
  EstadoCadena? cadena;

  /// Hay una jalada en curso (RPC + reinicio + guardado).
  bool jalando = false;

  /// Avisos para la pantalla, en orden: bienvenida de veterano, tiempo fuera y Descarga. Los consume la pantalla.
  bool bienvenidaPendiente = false;
  ResultadoOffline? offlinePendiente;

  /// El servidor dio el empujón (x2 por 30 min) y la pantalla todavía no lo avisó.
  bool empujonPendiente = false;
  ResultadoCagadas? descargaPendiente;

  /// Logros nuevos para el aviso de arriba.
  final List<Logro> logrosNuevos = [];

  /// Racha del Imperio: último día reclamado y su fecha (del servidor). null = sin datos (sin red o no cargó).
  int? _rachaDia;
  DateTime? _rachaFecha;

  /// La pantalla abre la hoja de racha si hay premio de hoy sin reclamar. La consume la pantalla.
  bool rachaPendiente = false;

  /// Estado de la racha para hoy (fecha local). null sin datos del servidor.
  EstadoRacha? get racha =>
      _rachaDia == null ? null : estadoRacha(_rachaDia!, _rachaFecha, fechaLocal(DateTime.now()), congeladores: congeladores);

  /// Congeladores 🧊 guardados (0 a 2, del servidor), si ya gastó el Tanque extra y los días de la racha salvados con 🧊.
  int congeladores = 0;
  bool tanqueExtra = false;
  List<int> rachaSalvados = const [];

  /// Cofre del Trono de esta semana (RPC `imperio_cofre`). null mientras no llega o sin la migración.
  EstadoCofre? cofre;

  /// Producción que dio el último Cofre abierto (para mostrarla en la hoja del Cofre).
  double premioCofreMj = 0;

  /// Sube cada vez que cae una Ciruela 🫐 (pujo o cagada): la pantalla la hace volar al chip.
  final ValueNotifier<int> ciruelaCae = ValueNotifier(0);

  int _desfase = 0; // reloj del servidor menos reloj del teléfono, en ms
  int get ahora => DateTime.now().millisecondsSinceEpoch + _desfase;

  bool _cargado = false, _ocupadoNube = false, _guardandoNube = false, _cerrado = false;
  bool _visible = false, _enPrimerPlano = true;
  Timer? _bucle;
  final Stopwatch _reloj = Stopwatch();
  int _ultimoAviso = 0;
  double _desdeLocal = 0, _desdeNube = 0;

  /// Un guardado en la nube falló con la app en el fondo: se repite al volver.
  bool _pendienteNube = false;

  // Telemetría: sesión abierta, último tiempo fuera, lo visto en el tick anterior y errores ya anotados.
  ContadorSesion? _sesion;
  double _offlineS = 0;
  DoradoVisible? _doradoVisto;
  Atasco? _atascoVisto, _atascoPerdido;
  final Map<String, int> _errores = {};

  String get _userId => db.auth.currentUser?.id ?? 'sin_sesion';

  // ---------- Carga ----------

  Future<void> iniciar() async {
    WidgetsBinding.instance.addObserver(this);
    if (_tele.version.isEmpty) unawaited(_tele.leerVersion());
    // Nunca lanza: si no hay red usa la caché y si no, los defaults.
    final flagsF = FlagsImperio.cargar(usuario: db.auth.currentUser?.id, pedir: pedirFlags);
    final local = await nube.cargarLocal(_userId);
    final estadoLocal = local?['estado'] is Map ? Map<String, dynamic>.from(local!['estado'] as Map) : null;
    final mjLocal = estadoLocal == null ? null : (local!['mjTotal'] as num?)?.toDouble();
    final ultimaLocal = (estadoLocal?['ultima_vez'] as num?)?.toInt();
    // Flags antes que la nube: imperio_cargar consume las cagadas nuevas en el servidor y, apagado, se perderían.
    flags = await flagsF;
    if (apagado) return _apagar();
    Map<String, dynamic>? estadoNube;
    _ocupadoNube = true;
    try {
      final carga = await nube.cargar();
      estadoNube = carga.estado;
      _desfase = carga.ahora.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
      final vacio = carga.nuevo || carga.estado.isEmpty;
      final local1 = usarCopiaLocal(mjLocal: mjLocal, mjServidor: carga.mjTotal, servidorVacio: vacio,
          jaladasLocal: _jaladasDe(estadoLocal), jaladasServidor: _jaladasDe(carga.estado));
      imperio = Imperio.desdeJson(local1 ? estadoLocal : carga.estado,
          cagadas: carga.cagadasTotal, fichas: carga.fichas, ciruelas: carga.ciruelas, esteticas: carga.esteticas, ajustes: flags.ajustes,
          cagadasCandado: (estadoLocal?['_cagadas_candado'] as num?)?.toInt() ?? -1, pases: (estadoLocal?['_pases'] as num?)?.toInt() ?? 0);
      _leerRacha(carga);
      _ciruelasDeCagadas(carga.ciruelasCagadas);
      if (!local1 && !vacio) aceptarRecorte(imperio.partida, carga.mjTotal);
      fundador = carga.fundador;
      final desde = inicioOffline([ultimaLocal, carga.guardado.millisecondsSinceEpoch, imperio.partida.ultimaVez], ahora);
      if (desde != null) _guardarAviso(imperio.aplicarOffline(desde, ahora));
      _aplicarNuevas(carga.nuevas);
      bienvenidaPendiente = carga.nuevo && carga.cagadasTotal > 0;
      if (bienvenidaPendiente) {
        _anotar('bienvenida', {'cagadas': carga.cagadasTotal, 'fichas': carga.fichas, 'fundador': carga.fundador});
      }
    } catch (_) {
      // Sin red: se juega con la copia local (o una partida nueva) y se reintenta la nube al guardar.
      _error('cargar');
      sinConexion = true;
      imperio = Imperio.desdeJson(
        estadoLocal,
        cagadas: (estadoLocal?['_cagadas'] as num?)?.toInt() ?? 0,
        fichas: (estadoLocal?['_fichas'] as num?)?.toInt() ?? 0,
        ciruelas: (estadoLocal?['_ciruelas'] as num?)?.toInt() ?? 0,
        esteticas: {...?(estadoLocal?['_esteticas'] as List?)?.map((e) => '$e')},
        ajustes: flags.ajustes,
        cagadasCandado: (estadoLocal?['_cagadas_candado'] as num?)?.toInt() ?? -1,
        pases: (estadoLocal?['_pases'] as num?)?.toInt() ?? 0,
      );
      final desde = inicioOffline([ultimaLocal], ahora);
      if (desde != null) _guardarAviso(imperio.aplicarOffline(desde, ahora));
    } finally {
      _ocupadoNube = false;
    }
    if (_cerrado) return;
    _sumarLogros(imperio.revisarLogros());
    _mirarCambios(anotar: false);
    _cargado = true;
    cargando = false;
    frescaHasta.addListener(_ponerFresca);
    _ponerFresca();
    unawaited(_guardarLocal());
    _actualizarBucle();
    notifyListeners();
    if (!sinConexion) unawaited(_cargarCadena(estadoServidor: estadoNube));
    if (!sinConexion) unawaited(_cargarProgreso());
    if (!sinConexion) unawaited(cargarCofre());
    if (!sinConexion) unawaited(_cargarEstilos());
  }

  /// Lo comprado en la tienda de estilo (queda en una copia local para arrancar sin red).
  Future<void> _cargarEstilos() async {
    try {
      await cargarEstilosMios();
      if (!_cerrado) notifyListeners();
    } catch (e) {
      if (!esDeRed(e)) _error('estilos_cargar', e);
    }
  }

  /// Cagadas que cuentan para candados (tope por día), pases de la racha y el empujón si el servidor lo dio.
  Future<void> _cargarProgreso() async {
    try {
      final r = await nube.progreso();
      if (_cerrado) return;
      imperio.cagadasCandado = r.cagadasCandado;
      imperio.pases = r.pases;
      if (r.empujon) {
        imperio.darEmpujon(ahora);
        empujonPendiente = true;
        _anotar('empujon', {'mj_total': imperio.mjTotal});
      }
      _sumarLogros(imperio.revisarLogros());
      notifyListeners();
      unawaited(_guardarLocal());
    } catch (_) {
      // Sin el RPC (migración sin aplicar) o sin red: los candados cuentan las cagadas como antes.
      _error('progreso');
    }
  }

  /// Trae el estado de la cadena. Si el servidor tiene más jaladas que la partida, mira [estadoServidor] (el de la
  /// última carga) con [arregloCadena]: o adopta la partida del servidor (reinicio) o jala aquí (guardado perdido).
  Future<void> _cargarCadena({Map<String, dynamic>? estadoServidor}) async {
    try {
      final c = await nube.cadena();
      if (_cerrado) return;
      cadena = c;
      final p = imperio.partida;
      final arreglo = arregloCadena(jaladasCadena: c.jaladas, jaladasPartida: p.jaladas,
          jaladasEstadoServidor: estadoServidor == null ? null : _jaladasDe(estadoServidor));
      if (arreglo == ArregloCadena.adoptar) {
        final viejo = imperio;
        imperio = Imperio.desdeJson(estadoServidor,
            cagadas: viejo.cagadas, fichas: viejo.fichas, ciruelas: viejo.ciruelas, esteticas: viejo.esteticas, ajustes: viejo.ajustes,
            cagadasCandado: viejo.cagadasCandado, pases: viejo.pases);
        _anotar('partida_adoptada', {'jaladas': c.jaladas});
        _mirarCambios(anotar: false);
        unawaited(_guardarLocal());
      } else if (arreglo == ArregloCadena.jalar) {
        imperio.jalar();
        p.jaladas = c.jaladas;
        _mirarCambios(anotar: false);
        unawaited(guardarTodo());
      }
      notifyListeners();
    } catch (_) {
      // Sin el RPC (migración sin aplicar) o sin red: el botón dice PRONTO hasta la próxima recarga.
      _error('cadena');
    }
  }

  void _leerRacha(CargaImperio carga) {
    _rachaDia = carga.rachaDia;
    _rachaFecha = leerFecha(carga.rachaFecha);
    congeladores = carga.congeladores;
    tanqueExtra = carga.tanqueExtra;
    rachaSalvados = carga.rachaSalvados;
    if (tanqueExtra) imperio.partida.horasExtraTanque = 1;
    rachaPendiente = racha?.reclamado == false;
  }

  /// Trae el Cofre del Trono de la semana. Nunca lanza: sin RPC o sin red el chip no sale.
  Future<void> cargarCofre() async {
    try {
      final c = await nube.cofre();
      if (_cerrado) return;
      cofre = c;
      notifyListeners();
    } catch (e) {
      _error('cofre', e);
    }
  }

  /// Ciruelas que el servidor sacó con las cagadas reales nuevas (5% cada una): vuelan y se anotan.
  void _ciruelasDeCagadas(int n) {
    if (n <= 0) return;
    ciruelaCae.value += n;
    _anotar('ciruela_suerte', {'origen': 'cagada', 'cantidad': n, 'saldo': imperio.ciruelas});
  }

  /// Cagada fresca de la última cagada real ([frescaHasta], hora local) en el reloj del servidor.
  /// Si la cagada se borra (calendario), el fin baja y se recorta lo que ya se había dado.
  void _ponerFresca() {
    final h = frescaHasta.value;
    if (!_cargado || _cerrado) return;
    final fin = h == null ? 0 : h.millisecondsSinceEpoch + _desfase;
    final antes = _finFresca;
    _finFresca = fin;
    if (antes != null && fin < antes) {
      if (imperio.recortarFresca(antes, fin, ahora)) _avisar();
      return;
    }
    if (h != null && imperio.aplicarFrescaHasta(fin)) _avisar();
  }

  int? _finFresca; // último fin de Cagada fresca real que se aplicó (reloj del servidor)

  /// Apagado por flag: sin partida, sin bucle y sin guardar (no se pisa lo guardado).
  void _apagar() {
    cargando = false;
    if (!_cerrado) notifyListeners();
  }

  void _guardarAviso(ResultadoOffline r) {
    if (r.segundosAusente >= minimoOffline.inSeconds) {
      _offlineS = r.segundosAusente;
      _anotar('offline', {'segundos': r.segundosAusente.round(), 'tope_lleno': r.tanqueLleno, 'ganado': r.ganado});
    }
    if (r.ganado > 0) offlinePendiente = r;
  }

  void _aplicarNuevas(List<CagadaNueva> nuevas) {
    if (nuevas.isEmpty) return;
    final r = imperio.aplicarCagadas([for (final c in nuevas) CagadaReal(tipo: c.tipo, peso: c.peso, creada: c.creada)], ahora);
    _anotar('descarga', {'cagadas': r.cantidad, 'ganado': r.ganado});
    final previa = descargaPendiente;
    descargaPendiente = previa == null
        ? r
        : ResultadoCagadas(previa.cantidad + r.cantidad, [...previa.descargas, ...r.descargas], r.tipoBuff ?? previa.tipoBuff,
            previa.enFiebre || r.enFiebre);
  }

  /// Al volver a la pestaña o a la app: trae cagadas nuevas, Fichas y el total. No pisa la partida local.
  Future<void> recargarCagadas() async {
    if (!_cargado || _ocupadoNube || _cerrado) return;
    _ocupadoNube = true;
    try {
      final carga = await nube.cargar();
      if (sinConexion) _desfase = carga.ahora.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
      sinConexion = false;
      fundador = carga.fundador;
      imperio.cagadas = carga.cagadasTotal;
      imperio.fichas = carga.fichas;
      imperio.ciruelas = carga.ciruelas;
      imperio.esteticas = {...carga.esteticas};
      _leerRacha(carga);
      _ciruelasDeCagadas(carga.ciruelasCagadas);
      _aplicarNuevas(carga.nuevas);
      _ponerFresca();
      _sumarLogros(imperio.revisarLogros());
      notifyListeners();
      await _cargarCadena(estadoServidor: carga.estado);
      unawaited(_cargarProgreso());
      unawaited(cargarCofre());
    } catch (e) {
      _error('recargar', e);
      if (!sinConexion) {
        sinConexion = true;
        notifyListeners();
      }
    } finally {
      _ocupadoNube = false;
    }
  }

  // ---------- Bucle ----------

  /// La pantalla avisa si la pestaña IMPERIO se ve.
  set visible(bool v) {
    if (v == _visible) return;
    _visible = v;
    if (v) _anotar('pestana_abre');
    _actualizarBucle();
    if (v) unawaited(recargarCagadas());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final antes = _enPrimerPlano;
    _enPrimerPlano = state == AppLifecycleState.resumed;
    _actualizarBucle();
    if (!_enPrimerPlano && antes) unawaited(_cargado ? guardarTodo() : _vaciarTelemetria());
    if (!_enPrimerPlano && antes && _cargado) unawaited(_programarAvisoCerrado());
    if (_enPrimerPlano && !antes) unawaited(cancelarAvisoImperio().catchError((_) {}));
    if (_enPrimerPlano && !antes && _visible) unawaited(recargarCagadas());
    if (_enPrimerPlano && !antes && _pendienteNube) {
      _pendienteNube = false;
      unawaited(_guardarNube());
    }
  }

  /// Al salir de la app: un aviso local para cuando ya alcance algo o se llene la poceta.
  Future<void> _programarAvisoCerrado() async {
    try {
      final a = imperio.avisoAlCerrar(ahora);
      if (a == null) return;
      await programarAvisoImperio(Duration(seconds: a.segundos.ceil()), nombreEs: a.nombreEs, nombreEn: a.nombreEn);
    } catch (_) {
      // Sin permiso de notificaciones o en pruebas: no pasa nada.
    }
  }

  void _actualizarBucle() {
    final debe = _cargado && _visible && _enPrimerPlano && !_cerrado;
    if (debe && _bucle == null) {
      // Si estuvo parado un rato (otra pestaña o la app en segundo plano), se cobra como tiempo fuera.
      final t = ahora;
      if (t - imperio.partida.ultimaVez >= minimoOffline.inMilliseconds) _guardarAviso(imperio.aplicarOffline(imperio.partida.ultimaVez, t));
      _mirarCambios();
      _abrirSesion();
      _reloj
        ..reset()
        ..start();
      _bucle = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    } else if (!debe && _bucle != null) {
      _bucle!.cancel();
      _bucle = null;
      _reloj.stop();
      _cerrarSesion();
    }
  }

  void _abrirSesion() {
    _sesion = ContadorSesion(imperio.mjTotal);
    _anotar('sesion_inicio', {
      'cagadas': imperio.cagadas,
      'mj_total': imperio.mjTotal,
      'mps': imperio.mpsSinEfectos(),
      'offline_s': _offlineS.round(),
      'variantes': flags.variantes,
    });
    _offlineS = 0;
  }

  void _cerrarSesion() {
    final s = _sesion;
    if (s == null) return;
    _sesion = null;
    // El motor no vence los atascos: el que sigue tapado al cerrar la sesión cuenta como perdido (una vez por atasco).
    final a = imperio.partida.atasco;
    if (a != null && !identical(a, _atascoPerdido)) {
      _atascoPerdido = a;
      _anotar('atasco_pierde');
    }
    _anotar('sesion_fin', s.fin(imperio.mjTotal));
  }

  /// Compara dorado y atasco con lo visto antes (por identidad) y anota lo que apareció o se fue solo.
  void _mirarCambios({bool anotar = true}) {
    final p = imperio.partida;
    final d = p.dorado, a = p.atasco;
    if (!identical(d, _doradoVisto)) {
      if (anotar && _doradoVisto != null) _anotar('dorado_pierde');
      if (anotar && d != null) _anotar('dorado_aparece');
      _doradoVisto = d;
    }
    if (!identical(a, _atascoVisto)) {
      final antes = _atascoVisto;
      // Solo el robot lo quita en el tick; el destape a mano limpia _atascoVisto en tocarAtasco.
      if (anotar && antes != null) _anotar('atasco_destapa', {'ms': max(0, ahora - antes.desde), 'perfecto': false, 'robot': true});
      if (anotar && a != null) _anotar('atasco_aparece', {'edificio': a.edificio});
      _atascoVisto = a;
    }
  }

  void _tick() {
    final dt = _reloj.elapsedMicroseconds / 1e6;
    _reloj
      ..reset()
      ..start();
    _sumarLogros(imperio.tick(ahora, dt));
    _mirarCambios();
    _sesion?.sumarTiempo(dt);
    _desdeLocal += dt;
    _desdeNube += dt;
    if (_desdeLocal >= 10) unawaited(_guardarLocal());
    if (_desdeNube >= 60) unawaited(_guardarNube());
    _ultimoAviso = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Avisa a la pantalla como mucho 10 veces por segundo; si el bucle corre, él avisa en el próximo tick.
  void _avisar() {
    final t = DateTime.now().millisecondsSinceEpoch;
    if (_bucle != null && t - _ultimoAviso < 100) return;
    _ultimoAviso = t;
    notifyListeners();
  }

  // ---------- Acciones ----------

  ResultadoPujo pujar() {
    final r = imperio.pujar(ahora);
    _sesion?.pujos++;
    if (!sinConexion && imperio.tirarCiruela()) unawaited(_pedirCiruela());
    _avisar();
    return r;
  }

  /// Se tocó una cosa del baño (además del pujo, que ya contó [pujar]): suma el toque y avisa si salió un logro escondido.
  void tocarObjeto(String id) {
    final nuevos = imperio.tocarObjeto(id);
    if (nuevos.isEmpty) return;
    _sumarLogros(nuevos);
    _avisar();
  }

  bool _pidiendoCiruela = false;

  /// La suerte salió en el pujo: el servidor acredita 1 🫐 si no pasó el tope del día. Nunca lanza.
  Future<void> _pedirCiruela() async {
    if (_pidiendoCiruela) return;
    _pidiendoCiruela = true;
    try {
      final r = await nube.ciruelaSuerte();
      if (_cerrado || r < 0) return;
      imperio.ciruelas = r;
      ciruelaCae.value++;
      _anotar('ciruela_suerte', {'origen': 'pujo', 'cantidad': 1, 'saldo': r});
      notifyListeners();
      unawaited(_guardarLocal());
    } catch (e) {
      _error('ciruela', e);
    } finally {
      _pidiendoCiruela = false;
    }
  }

  /// Compra una oferta de la tienda de Ciruelas: el servidor descuenta y aquí se pone el efecto.
  /// false si no alcanzaba. Lanza el error de red sin tocar la partida.
  Future<bool> gastarCiruelas(String id) async {
    final int r;
    try {
      r = await nube.gastarCiruelas(id);
    } catch (e) {
      _error('ciruelas_gastar', e);
      rethrow;
    }
    if (_cerrado) return false;
    if (r < 0) {
      notifyListeners();
      return false;
    }
    final antes = imperio.ciruelas;
    imperio.ciruelas = r;
    if (id == 'congelador') congeladores = min(2, congeladores + 1);
    final mj = imperio.aplicarOfertaCiruela(id, ahora);
    _anotar('ciruelas_gastar', {'id': id, 'precio': antes - r, 'saldo': r, 'mj': mj});
    _hecho(true);
    notifyListeners();
    unawaited(_guardarLocal());
    unawaited(_guardarNube());
    return true;
  }

  /// Compra una estética (solo da suerte). false si no alcanzaba o ya la tenía. Lanza el error de red.
  Future<bool> comprarEstetica(String id) async {
    final int r;
    try {
      r = await nube.comprarEstetica(id);
    } catch (e) {
      _error('estetica_compra', e);
      rethrow;
    }
    if (_cerrado) return false;
    if (r == -2) imperio.esteticas = {...imperio.esteticas, id};
    if (r < 0) {
      notifyListeners();
      return false;
    }
    imperio.ciruelas = r;
    imperio.esteticas = {...imperio.esteticas, id};
    _anotar('estetica_compra', {'id': id, 'saldo': r, 'bono': imperio.bonoSuerte});
    notifyListeners();
    unawaited(_guardarLocal());
    return true;
  }

  /// Precio en MJ de un estilo con el flag `estilo_precio_mult`.
  double precioEstilo(Estilo e) => e.mj * flags.estiloPrecioMult;

  /// Qué falta para comprar un estilo con lo que hay en el teléfono, o null si alcanza.
  String? faltaParaEstilo(Estilo e, int cagadas) {
    if (imperio.saldo < precioEstilo(e)) return 'mj';
    if (imperio.partida.rollos < e.rollos) return 'rollos';
    if (cagadas < e.cagadas) return 'cagadas';
    return null;
  }

  /// Compra un estilo: la base lo anota (y revisa por encima) y aquí se descuentan los MJ y los Rollos, que viven en
  /// el teléfono. Los Rollos gastados suben rollosGastados como los objetos de Rollos. Lanza el error de red o del
  /// servidor sin tocar la partida.
  Future<void> comprarEstilo(Estilo e) async {
    if (tengoEstilo(e.id)) return;
    final precio = precioEstilo(e);
    if (imperio.saldo < precio || imperio.partida.rollos < e.rollos) throw StateError('falta');
    // El servidor mira lo último guardado: primero se sube la partida.
    await _guardarNube();
    try {
      await comprarEstiloEnBase(e.id);
    } catch (err) {
      if (!esDeRed(err)) _error('estilo_compra', err);
      rethrow;
    }
    if (_cerrado) return;
    imperio.partida
      ..saldo = max(0, imperio.partida.saldo - precio)
      ..rollos = max(0, imperio.partida.rollos - e.rollos)
      ..rollosGastados += e.rollos;
    _anotar('estilo_compra', {'id': e.id, 'mj': precio, 'rollos': e.rollos});
    notifyListeners();
    unawaited(_guardarLocal());
    unawaited(_guardarNube());
  }

  /// Reclama el día de hoy de la racha. El servidor da Ciruelas y Fichas; aquí, producción, objetos y logro.
  /// Lanza el error de red sin tocar la partida.
  Future<ReclamoRacha> reclamarRacha() async {
    final ReclamoRacha r;
    try {
      r = await nube.reclamarRacha(fechaTexto(fechaLocal(DateTime.now())));
    } catch (e) {
      _error('racha', e);
      rethrow;
    }
    rachaPendiente = false;
    if (_cerrado) return r;
    imperio.ciruelas = r.ciruelas;
    imperio.fichas = r.fichas;
    _rachaDia = r.dia;
    _rachaFecha = fechaLocal(DateTime.now());
    if (r.congeladores != null) congeladores = r.congeladores!;
    if (r.rachaSalvados != null) rachaSalvados = r.rachaSalvados!;
    if (!r.ya && r.congelados > 0) {
      imperio.partida.congeladosUsados += r.congelados;
      _anotar('congelador_usar', {'cantidad': r.congelados, 'dia': r.dia, 'quedan': congeladores});
      _sumarLogros(imperio.revisarLogros());
    }
    if (!r.ya) {
      final logro = premioDia(r.dia).logro;
      final yaLoTenia = logro != null && imperio.partida.logros.contains(logro);
      final mj = imperio.aplicarPremioRacha(r.dia, ahora);
      final l = logro == null || yaLoTenia ? null : logroPorId(logro);
      if (l != null && imperio.partida.logros.contains(l.id)) _sumarLogros([l]);
      _anotar('racha_reclamar', {'dia': r.dia, 'ciruelas': r.ciruelasGanadas, 'ficha': r.ficha, 'mj': mj});
      _hecho(true);
      if (r.pases != null) imperio.pases = r.pases!;
      unawaited(_guardarLocal());
      unawaited(_guardarNube());
    }
    notifyListeners();
    return r;
  }

  /// Ficha 🎟️ por la Cagada fresca (x2 por 1 h). false si no le quedaban. Lanza el error de red.
  Future<bool> usarFichaFresca() async {
    final int r;
    try {
      r = await nube.usarFicha();
    } catch (e) {
      _error('fichas_usar', e);
      rethrow;
    }
    if (_cerrado) return false;
    if (r < 0) {
      notifyListeners();
      return false;
    }
    imperio.fichas = r;
    imperio.activarCagadaFresca(ahora);
    _anotar('fichas_usar', {'que': 'cagada_fresca', 'precio': 1, 'saldo': r});
    return _fichasHechas();
  }

  /// Gasta Fichas en 'sin_espera' (borra la espera de [espera]), 'tanque_extra' (+1 h de tope offline, una vez)
  /// o 'congelador' (+1 🧊, hasta 2). El servidor valida y descuenta. false si no alcanzaba o no cabe. Lanza el error de red.
  Future<bool> usarFichas(String que, {String? espera}) async {
    if (que == 'sin_espera' && (espera == null || imperio.esperaRestante(espera, ahora) == null)) return false;
    final int r;
    try {
      r = await nube.usarFichas(que);
    } catch (e) {
      _error('fichas_usar', e);
      rethrow;
    }
    if (_cerrado) return false;
    if (r == -2 && que == 'congelador') congeladores = 2;
    if (r == -2 && que == 'tanque_extra') {
      tanqueExtra = true;
      imperio.partida.horasExtraTanque = 1;
    }
    if (r < 0) {
      notifyListeners();
      return false;
    }
    final antes = imperio.fichas;
    imperio.fichas = r;
    switch (que) {
      case 'sin_espera':
        imperio.quitarEspera(espera!, ahora);
      case 'tanque_extra':
        tanqueExtra = true;
        imperio.partida.horasExtraTanque = 1;
      case 'congelador':
        congeladores = min(2, congeladores + 1);
    }
    _anotar('fichas_usar', {'que': que, 'precio': antes - r, 'saldo': r, 'espera': ?espera});
    return _fichasHechas();
  }

  bool _fichasHechas() {
    _hecho(true);
    notifyListeners();
    unawaited(_guardarLocal());
    unawaited(_guardarNube());
    return true;
  }

  /// Abre el Cofre del Trono: el servidor da Fichas (o Ciruelas si no caben); aquí, 1 h de producción.
  /// null si no estaba listo. Lanza el error de red sin tocar la partida.
  Future<EstadoCofre?> reclamarCofre() async {
    final EstadoCofre c;
    try {
      c = await nube.cofre(reclamar: true);
    } catch (e) {
      _error('cofre_reclamar', e);
      rethrow;
    }
    if (_cerrado) return null;
    cofre = c;
    if (!c.reclamadoAhora) {
      notifyListeners();
      return null;
    }
    imperio.fichas = c.fichas;
    imperio.ciruelas = c.ciruelas;
    final p = imperio.partida;
    p.cofres += 1;
    p.semanasRacha = c.semanasRacha;
    final mj = imperio.aplicarPremioCofre(ahora);
    premioCofreMj = mj;
    _sumarLogros(imperio.revisarLogros());
    _anotar('cofre_reclamar', {'dias': c.dias, 'fichas': c.fichasGanadas, 'ciruelas': c.ciruelasGanadas, 'semanas': c.semanasRacha, 'mj': mj});
    _fichasHechas();
    return c;
  }

  bool comprarEdificio(String id, int n) {
    final t = ahora;
    final precio = imperio.precioEdificioVarios(id, n, t);
    final ok = imperio.comprarEdificioVarios(id, n, t);
    if (ok) _compra('edificio', {'id': id, 'cantidad': imperio.cantidad(id), 'precio': precio, 'seg_partida': _segPartida});
    return _hecho(ok);
  }

  /// Abre con MJ lo que le falta a un candado (hasta la mitad de lo que pide).
  bool pagarCandado(int pide) {
    final precio = imperio.precioCandado(pide);
    final faltan = imperio.faltanCandado(pide);
    final ok = imperio.pagarCandado(pide);
    if (ok) _compra('candado', {'pide': pide, 'cagadas': faltan, 'precio': precio, 'seg_partida': _segPartida});
    return _hecho(ok);
  }

  bool comprarMejora(String id) {
    final m = mejoraPorId(id);
    final precio = m == null ? 0.0 : imperio.precioMejora(m);
    final ok = imperio.comprarMejora(id);
    if (ok) _compra('mejora', {'id': id, 'precio': precio, 'seg_partida': _segPartida});
    return _hecho(ok);
  }

  bool comprarObjeto(String id) {
    final t = ahora;
    final o = objetoPorId(id);
    final precio = imperio.precioObjeto(id, t);
    final ok = imperio.comprarObjeto(id, t);
    if (ok) {
      _compra('objeto_compra', {'id': id});
      if (o?.tipo == TipoObjeto.alquilable) _anotar('alquilar', {'id': id, 'precio': precio, 'hasta': imperio.partida.alquilados[id]});
    }
    return _hecho(ok);
  }

  bool usarObjeto(String id) {
    final ok = imperio.usarObjeto(id, ahora);
    if (ok) {
      _anotar('objeto_uso', {'id': id});
      _anotar('consumible_usar', {'id': id, 'quedan': imperio.enInventario(id)});
    }
    return _hecho(ok);
  }

  /// Pone Pintura marrón en [edificio].
  bool usarPintura(String edificio) {
    final ok = imperio.usarPintura(edificio, ahora);
    if (ok) _anotar('consumible_usar', {'id': 'pintura', 'edificio': edificio, 'quedan': imperio.enInventario('pintura')});
    return _hecho(ok);
  }

  /// Usa una habilidad de Maná. null si no se pudo.
  ResultadoHabilidad? usarHabilidad(String id) {
    final t = ahora;
    final r = imperio.usarHabilidad(id, t);
    if (r != null) _anotar('mana_usar', {'id': id, 'mana': imperio.mana(t).round(), 'mj': r.mj, 'fallo': r.fallo});
    _hecho(r != null);
    return r;
  }

  /// Compra un objeto de Rollos de Oro (gasta Rollos: baja el +% por rollo).
  bool comprarObjetoRollos(String id) {
    final costo = objetoRollosPorId(id)?.costo ?? 0;
    final ok = imperio.comprarObjetoRollos(id, ahora);
    if (ok) _anotar('rollos_gastar', {'id': id, 'costo': costo, 'quedan': imperio.partida.rollos, 'tiene': imperio.tieneObjetoRollos(id)});
    return _hecho(ok);
  }

  ResultadoDorado? tocarDorado() {
    final r = imperio.tocarDorado(ahora);
    if (r != null) {
      _doradoVisto = imperio.partida.dorado;
      _anotar('dorado_toca', {'efecto': r.efecto.name});
    }
    _avisar();
    return r;
  }

  ResultadoDestape? tocarAtasco() {
    final a = imperio.partida.atasco;
    final t = ahora;
    final r = imperio.tocarAtasco(t);
    if (a != null && r != null && r.destapado) {
      _atascoVisto = imperio.partida.atasco;
      _anotar('atasco_destapa', {'ms': max(0, t - a.desde), 'perfecto': r.perfecto, 'robot': false});
    }
    _avisar();
    return r;
  }

  bool _hecho(bool ok) {
    if (ok) {
      _sumarLogros(imperio.revisarLogros());
      _mirarCambios();
      _avisar();
    }
    return ok;
  }

  int get _segPartida => imperio.partida.segPartida.round();

  void _compra(String evento, Map<String, Object?> datos) {
    _sesion?.compras++;
    _anotar(evento, datos);
  }

  void _sumarLogros(List<Logro> nuevos) {
    for (final l in nuevos) {
      _anotar('logro', {'id': l.id});
    }
    logrosNuevos.addAll(nuevos);
  }

  // ---------- Telemetría ----------

  /// Para la pantalla (sala_abre). Igual que el resto: nunca lanza.
  void anotar(String evento, [Map<String, Object?> datos = const {}]) => _anotar(evento, datos);

  void _anotar(String evento, [Map<String, Object?> datos = const {}]) {
    try {
      _tele.registrar(evento, datos);
    } catch (_) {}
  }

  /// `error` {donde}, como mucho uno cada 10 min por sitio (sin red, recargar falla en cada vuelta).
  /// `error` {donde, tipo, red}: el tipo es la clase de la excepción (sin el mensaje, que puede traer datos).
  void _error(String donde, [Object? e]) {
    final t = DateTime.now().millisecondsSinceEpoch;
    final antes = _errores[donde];
    if (antes != null && t - antes < 600000) return;
    _errores[donde] = t;
    _anotar('error', {'donde': donde, if (e != null) 'tipo': '${e.runtimeType}', if (e != null) 'red': esDeRed(e)});
  }

  Future<void> _vaciarTelemetria() async {
    try {
      await _tele.vaciar();
    } catch (_) {}
  }

  // ---------- Jalar la cadena ----------

  /// Abre el diálogo de la cadena (`cadena_abre`). [puede]: el botón estaba encendido.
  void abrirCadena(bool puede) => _anotar('cadena_abre', {'puede': puede});

  /// Jala la cadena: el servidor revisa las cagadas y marca la jalada, aquí se reinicia la corrida y se guarda
  /// (local y nube). Devuelve los rollos ganados. Lanza el error del servidor o de red sin tocar la partida.
  Future<int> jalarCadena() async {
    if (jalando) throw StateError('Ya se está jalando');
    jalando = true;
    try {
      final int n;
      try {
        n = await nube.jalar();
      } catch (e) {
        _error('jalar', e);
        rethrow;
      }
      final ganados = imperio.jalar();
      imperio.partida.jaladas = n;
      cadena = EstadoCadena(cagadas: 0, necesarias: cadena?.necesarias ?? imperio.ajustes.cadenaCagadas, jaladas: n);
      _mirarCambios(anotar: false);
      _anotar('cadena_jala', {'rollos': ganados, 'jaladas': n});
      notifyListeners();
      await _guardarLocal();
      await _guardarNube();
      return ganados;
    } finally {
      jalando = false;
    }
  }

  // ---------- Cartera ----------

  /// Antes de presumir la cartera en el chat: el servidor arma la tarjeta con lo guardado, así que se guarda primero.
  Future<void> guardarParaCartera() => guardarTodo();

  /// `cartera_comparte` {destino: chat | fuera}.
  void compartioCartera(String destino) => _anotar('cartera_comparte', {'destino': destino});

  // ---------- Guardado ----------

  Future<void> _guardarLocal() async {
    _desdeLocal = 0;
    final estado = {
      ...imperio.toJson(),
      '_cagadas': imperio.cagadas,
      '_fichas': imperio.fichas,
      '_ciruelas': imperio.ciruelas,
      '_esteticas': imperio.esteticas.toList(),
      '_cagadas_candado': imperio.cagadasCandado,
      '_pases': imperio.pases,
    };
    try {
      await nube.guardarLocal(_userId, estado, imperio.mjTotal, imperio.mpsSinEfectos());
    } catch (e) {
      _error('guardar_local', e);
    }
  }

  Future<void> _guardarNube() async {
    _desdeNube = 0;
    unawaited(_vaciarTelemetria());
    if (_guardandoNube || _ocupadoNube) return;
    _guardandoNube = true;
    try {
      // Sin conexión desde el arranque: primero cargar (crea la fila y trae cagadas), luego guardar.
      if (sinConexion) {
        _guardandoNube = false;
        await recargarCagadas();
        if (sinConexion) return;
        _guardandoNube = true;
      }
      // Ritmo efectivo (MJ/s o pujos del Dedo, lo mayor): el antitrampa del servidor lo usa como techo.
      // _mps_edificios y _pujo: los lee la tarjeta de cartera del chat (el servidor no confía en los números del cliente).
      final estado = {...imperio.toJson(), '_mps_edificios': imperio.mpsSinEfectos(), '_pujo': imperio.valorPujo(ahora)};
      final r = await nube.guardar(estado, imperio.mjTotal, imperio.ritmoEfectivo(ahora));
      if (r.recortado) {
        // Para cazar trampas (supabase/consultas/exploits.sql): cuánto dijo la app y cuánto aceptó el servidor.
        _anotar('guardado_recortado', {'mj_app': imperio.mjTotal, 'mj_servidor': r.mjTotal});
        aceptarRecorte(imperio.partida, r.mjTotal);
      }
    } catch (e) {
      // Android corta la red unos segundos después de mandar la app al fondo: ese guardado se repite al volver
      // (lo local ya quedó). No es error ni "sin conexión".
      if (!_enPrimerPlano) {
        _pendienteNube = true;
      } else {
        _error('guardar_nube', e);
        sinConexion = true;
        if (!_cerrado) notifyListeners();
      }
    } finally {
      _guardandoNube = false;
    }
  }

  /// Guarda local y en la nube (al pausar o salir).
  Future<void> guardarTodo() async {
    if (!_cargado) return;
    await _guardarLocal();
    await _guardarNube();
  }

  @override
  void dispose() {
    _cerrado = true;
    frescaHasta.removeListener(_ponerFresca);
    _bucle?.cancel();
    _bucle = null;
    _cerrarSesion();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cargado ? guardarTodo() : _vaciarTelemetria());
    super.dispose();
  }
}
