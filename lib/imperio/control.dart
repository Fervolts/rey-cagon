import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../actualizar.dart' show buildInstalado;
import '../cloaca.dart' show NubeCloacas, cloacaCambio;
import '../fresca.dart' show frescaHasta;
import '../main.dart' show db, esDeRed;
import '../recordatorio.dart' show cancelarAvisoImperio, programarAvisoAtasco, programarAvisoImperio;
import 'apuesta.dart';
import 'apuesta_local.dart';
import 'casas.dart';
import 'estilos.dart';
import 'estilos_mios.dart';
import 'flags.dart';
import 'minijuegos/datos.dart';
import 'motor.dart';
import 'nube.dart';
import 'racha_imperio.dart';
import 'regalos_datos.dart';
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
/// [mjCasaServidor]: los MJ de la casa que dejó el servidor (después de mudarse o abdicar se recortan aparte).
void aceptarRecorte(Partida p, double mjServidor, {double? mjCasaServidor}) {
  if (mjCasaServidor != null && (p.mudanzas > 0 || p.abdicaciones > 0) && mjCasaServidor < p.mjEnCasa) {
    p.mjEnCasa = max(0.0, mjCasaServidor);
  }
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
  ControlImperio({NubeImperio? nube, Telemetria? telemetria, this.pedirFlags, this.leerBuild})
      : nube = nube ?? NubeImperio(),
        _tele = telemetria ?? Telemetria.instancia;

  final NubeImperio nube;
  final Telemetria _tele;
  /// Para pruebas: de dónde salen los flags (por defecto, el RPC).
  final PedirFlags? pedirFlags;

  /// Para pruebas: de dónde sale el build instalado (por defecto, [buildInstalado]).
  final Future<int?> Function()? leerBuild;

  /// Build instalado (null hasta que se lee o si no se puede leer). Se manda en cada guardado (p_version).
  int? build;

  /// El servidor respondió `version_vieja` a un guardado: el flag `version_minima` subió con la app abierta.
  bool _servidorVersionVieja = false;
  Imperio imperio = Imperio(ajustes: FlagsImperio.porDefecto.ajustes);

  /// Flags remotos de esta carga (defaults hasta que lleguen).
  FlagsImperio flags = FlagsImperio.porDefecto;

  /// Flag `imperio_activo` apagado: la pantalla muestra el aviso de mantenimiento y no se juega ni se guarda.
  bool get apagado => !flags.activo;

  /// Build menor que `version_minima`: la pantalla pide actualizar y no se carga ni se juega (los guardados de
  /// esta versión el servidor ya los ignora, así que lo que se jugara se perdería).
  bool get versionVieja => _servidorVersionVieja || flags.bloqueaVersion(build);

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

  /// Alquileres Indefinidos que se cortaron (id, precio del periodo, saldo que había) y la pantalla todavía no avisó.
  /// Si pasó con la app cerrada, el primer tick al volver los deja aquí y salen al abrir el Imperio.
  final List<(String, double, double)> alquileresCortadosPendientes = [];

  /// El servidor dio el empujón (x2 por 30 min) y la pantalla todavía no lo avisó.
  bool empujonPendiente = false;

  /// La cadena del servidor iba adelantada y se jaló aquí para alcanzarla (guardado perdido): la pantalla lo avisa.
  bool cadenaSincronizadaPendiente = false;
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

  /// Regalos 🎁 por abrir y topes de hoy (RPC `imperio_regalos_pendientes`). null mientras no llega o sin la migración.
  EstadoRegalos? regalos;

  /// Las llamadas de los regalos (en las pruebas, una falsa).
  NubeRegalos nubeRegalos = const NubeRegalos();

  /// Las llamadas de la Cloaca 🚽 (bono de hoy y premios de la liga; en las pruebas, una falsa).
  NubeCloacas nubeCloaca = const NubeCloacas();

  /// Sala de juegos: topes, lo ganado hoy y récords (RPC `imperio_minijuegos_resumen`). null mientras no llega o sin la migración.
  ResumenMinijuegos? minijuegos;

  /// Las llamadas de los minijuegos (en las pruebas, una falsa).
  NubeMinijuegos nubeMinijuegos = const NubeMinijuegos();

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
  /// Atascos abiertos ya vistos (por identidad) y los ya anotados como perdidos (`atasco_pierde`, uno por Atasco).
  List<Atasco> _atascosVistos = [];
  final Set<Atasco> _atascosPerdidos = Set.identity();
  final Map<String, int> _errores = {};

  String get _userId => db.auth.currentUser?.id ?? 'sin_sesion';

  // ---------- Carga ----------

  Future<void> iniciar() async {
    WidgetsBinding.instance.addObserver(this);
    if (_tele.version.isEmpty) unawaited(_tele.leerVersion());
    // Nunca lanza: si no hay red usa la caché y si no, los defaults.
    final flagsF = FlagsImperio.cargar(usuario: db.auth.currentUser?.id, pedir: pedirFlags);
    final buildF = (leerBuild ?? buildInstalado)();
    final local = await nube.cargarLocal(_userId);
    final estadoLocal = local?['estado'] is Map ? Map<String, dynamic>.from(local!['estado'] as Map) : null;
    final mjLocal = estadoLocal == null ? null : (local!['mjTotal'] as num?)?.toDouble();
    final ultimaLocal = (estadoLocal?['ultima_vez'] as num?)?.toInt();
    // Flags antes que la nube: imperio_cargar consume las cagadas nuevas en el servidor y, apagado, se perderían.
    flags = await flagsF;
    build = await buildF;
    if (apagado || versionVieja) return _apagar();
    // Volvió (también tras matar la app): los avisos de la app cerrada ya no hacen falta.
    unawaited(cancelarAvisoImperio().catchError((_) {}));
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
    _marcarCasaEn();
    _sumarLogros(imperio.revisarLogros());
    _mirarCambios(anotar: false);
    _cargado = true;
    vivo = this;
    unawaited(aplicarApuestas());
    cargando = false;
    frescaHasta.addListener(_ponerFresca);
    _ponerFresca();
    unawaited(_guardarLocal());
    _actualizarBucle();
    notifyListeners();
    if (!sinConexion) unawaited(_cargarCadena(estadoServidor: estadoNube));
    if (!sinConexion) unawaited(_cargarProgreso());
    if (!sinConexion) unawaited(cargarCofre());
    if (!sinConexion) unawaited(cargarRegalos());
    if (!sinConexion) unawaited(cargarCloaca());
    cloacaCambio
      ..removeListener(_cloacaCambio)
      ..addListener(_cloacaCambio);
    if (!sinConexion) unawaited(cargarMinijuegos());
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
        _marcarCasaEn();
        _mirarCambios(anotar: false);
        unawaited(_guardarLocal());
      } else if (c.abdicaciones != null && c.abdicaciones! > p.abdicaciones) {
        // La abdicación quedó marcada en el servidor pero el guardado se perdió: se abdica aquí con los datos del servidor
        // (va antes que la mudanza: abdicar baja las mudanzas).
        _anotar('abdicar_sincroniza', {'abdicaciones_servidor': c.abdicaciones, 'abdicaciones_partida': p.abdicaciones});
        imperio.abdicar(
            coronasServidor: max(0, (c.coronasGanadas ?? p.coronasGanadas) - p.coronasGanadas),
            mudanzasServidor: c.mudanzas,
            llavesServidor: c.llavesGanadas,
            mjBaseServidor: c.mjBase,
            ahora: ahora);
        p
          ..abdicaciones = c.abdicaciones!
          ..jaladas = max(p.jaladas, c.jaladas)
          ..jaladasBase = p.jaladas;
        if (c.coronasGanadas != null) p.coronasGanadas = c.coronasGanadas!;
        _mirarCambios(anotar: false);
        unawaited(guardarTodo());
      } else if (c.mudanzas != null && c.mudanzas! > p.mudanzas) {
        // La mudanza quedó marcada en el servidor pero el guardado se perdió: se muda aquí con los datos del servidor.
        _anotar('mudanza_sincroniza', {'mudanzas_servidor': c.mudanzas, 'mudanzas_partida': p.mudanzas});
        imperio.mudarse(llavesServidor: max(0, (c.llavesGanadas ?? p.llavesGanadas) - p.llavesGanadas), mjBaseServidor: c.mjBase, ahora: ahora);
        p
          ..mudanzas = c.mudanzas!
          ..jaladas = max(p.jaladas, c.jaladas)
          ..jaladasBase = p.jaladas;
        if (c.llavesGanadas != null) p.llavesGanadas = c.llavesGanadas!;
        _mirarCambios(anotar: false);
        unawaited(guardarTodo());
      } else if (arreglo == ArregloCadena.jalar) {
        _anotar('cadena_sincroniza', {'jaladas_servidor': c.jaladas, 'jaladas_partida': p.jaladas, 'mj_total': imperio.mjTotal});
        imperio.jalar();
        p.jaladas = c.jaladas;
        cadenaSincronizadaPendiente = true;
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

  /// Trae los regalos por abrir. Nunca lanza: sin RPC o sin red el chip no sale. Da los logros de regalar que falten.
  Future<void> cargarRegalos() async {
    try {
      final r = await nubeRegalos.pendientes();
      if (_cerrado) return;
      regalos = r;
      if (_cargado) _sumarLogros(imperio.logrosDeRegalos(dados: r.dados));
      notifyListeners();
    } catch (e) {
      _error('regalos', e);
    }
  }

  /// La Cloaca 🚽: trae el bono de producción de hoy (lo calcula el servidor) y cobra los Rollos de Oro de las ligas
  /// ganadas. Nunca lanza: sin RPC o sin red el bono queda como estaba y los premios esperan a la próxima vez.
  Future<void> cargarCloaca() async {
    try {
      final bono = await nubeCloaca.bono();
      if (_cerrado) return;
      if (bono != imperio.bonoCloaca) {
        imperio.bonoCloaca = bono;
        notifyListeners();
      }
      if (!_cargado) return;
      final estado = await nubeCloaca.mia();
      for (final p in estado.premios) {
        if (_cerrado) return;
        final r = await nubeCloaca.cobrar(p.id);
        // Ya cobrado en el servidor: se suma aunque la pantalla se haya cerrado, para no perderlo.
        if (!r.ok || r.rollos <= 0) continue;
        imperio.partida.rollos += r.rollos;
        _anotar('cloaca_premio_cobra', {'rollos': r.rollos, 'semana': p.semana});
        if (_cerrado) {
          unawaited(_guardarLocal());
          unawaited(_guardarNube());
        } else {
          _fichasHechas();
        }
      }
    } catch (e) {
      _error('cloaca', e);
    }
  }

  void _cloacaCambio() {
    if (!_cerrado && !sinConexion) unawaited(cargarCloaca());
  }

  /// Abre un Rollo de regalo: el servidor dice cuántos minutos; aquí se cobran de la producción propia. Devuelve lo que
  /// dijo el servidor y los MJ (0 si no se abrió). Lanza el error de red sin tocar la partida.
  Future<(ResultadoRegalo, double)> abrirRegalo(Regalo g) async {
    final ResultadoRegalo r;
    try {
      r = await nubeRegalos.abrir(g.id);
    } catch (e) {
      _error('regalo_abrir', e);
      rethrow;
    }
    if (_cerrado) return (r, 0.0);
    final antes = regalos;
    // ya_abierto, vencido y no_existe tampoco se pueden abrir de nuevo: se quitan de la lista.
    if (antes != null && (r.ok || r.motivo == 'ya_abierto' || r.motivo == 'vencido' || r.motivo == 'no_existe')) {
      regalos = r.ok ? antes.trasAbrir(g.id) : antes.sinRegalo(g.id);
    }
    if (!r.ok) {
      notifyListeners();
      return (r, 0.0);
    }
    final mj = imperio.abrirRegalo(r.minutos);
    _sumarLogros(imperio.logrosDeRegalos(mutuo: r.mutuo));
    _anotar('imperio_regalo_abre', {'minutos': r.minutos, 'mj': mj, 'mutuo': r.mutuo, 'quedan': regalos?.regalos.length ?? 0});
    _fichasHechas();
    return (r, mj);
  }

  /// Trae el resumen de la Sala de juegos. Nunca lanza: sin RPC o sin red las tarjetas salen sin la línea de "hoy".
  Future<void> cargarMinijuegos() async {
    try {
      final r = await nubeMinijuegos.resumen();
      if (_cerrado) return;
      minijuegos = r;
      r.alGlobal();
      if (_cargado) _sumarLogros(imperio.revisarLogros());
      notifyListeners();
    } catch (e) {
      _error('minijuegos', e);
    }
  }

  /// Guarda una partida de la Sala: el servidor decide los minutos de producción propia y aquí se cobran como un regalo.
  /// Devuelve lo que dijo el servidor y los MJ (0 si no hubo premio). Sin red devuelve un resultado sin premio, nunca lanza.
  Future<(ResultadoMinijuego, double)> terminarMinijuego(String juego, int puntos, int duracionMs) async {
    final ResultadoMinijuego r;
    try {
      r = await nubeMinijuegos.guardar(juego, puntos, duracionMs);
    } catch (e) {
      _error('minijuego', e);
      return (ResultadoMinijuego.sinRed(puntos), 0.0);
    }
    if (_cerrado) return (r, 0.0);
    if (r.motivo == 'apagado' || r.motivo == 'juego' || (!r.ok && r.motivo == 'invalida')) {
      _anotar('minijuego_rechazo', {'juego': juego, 'puntos': puntos, 'motivo': r.motivo});
      return (r, 0.0);
    }
    final antes = minijuegos ?? const ResumenMinijuegos();
    minijuegos = antes.trasPartida(juego, r);
    minijuegos!.alGlobal();
    var mj = 0.0;
    if (r.ok && r.minutos > 0) mj = imperio.abrirRegalo(r.minutos);
    _sumarLogros(imperio.revisarLogros());
    _anotar('minijuego_fin', {'juego': juego, 'puntos': puntos, 'ms': duracionMs, 'minutos': r.minutos, 'mj': mj, 'record': r.nuevoRecord});
    _fichasHechas();
    return (r, mj);
  }

  /// Se regaló un Rollo desde el Imperio (ranking de amigos): pone los topes al día y da los logros de regalar.
  void regaloHecho(String para, ResultadoRegalo r) {
    if (!r.ok || _cerrado) return;
    final antes = regalos;
    if (antes != null) regalos = antes.trasRegalar(para, r.dados);
    if (_cargado) _sumarLogros(imperio.logrosDeRegalos(dados: r.dados));
    notifyListeners();
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
    final atascado = r.atascoEdificio;
    if (atascado != null) {
      _anotar('atasco_offline', {
        'edificio': atascado,
        'edificios': [for (final a in r.atascos) a.edificio],
        'minutos': ((r.atascoEn - (imperio.partida.ultimaVez - r.segundosAusente * 1000)) / 60000).round(),
        'mj_perdidos': r.mjPerdidos,
        'robot': r.atascoCubierto,
      });
    }
    if (r.ganado > 0 || r.atascosTapados > 0) offlinePendiente = r;
  }

  void _aplicarNuevas(List<CagadaNueva> nuevas) {
    if (nuevas.isEmpty) return;
    final r = imperio.aplicarCagadas([for (final c in nuevas) CagadaReal(tipo: c.tipo, peso: c.peso, creada: c.creada)], ahora);
    _anotar('descarga', {'cagadas': r.cantidad, 'ganado': r.ganado});
    final previa = descargaPendiente;
    descargaPendiente = previa == null
        ? r
        : ResultadoCagadas(previa.cantidad + r.cantidad, [...previa.descargas, ...r.descargas], r.tipoBuff ?? previa.tipoBuff,
            previa.enFiebre || r.enFiebre, fuerza: r.tipoBuff != null ? r.fuerza : previa.fuerza);
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
      unawaited(cargarRegalos());
      unawaited(cargarCloaca());
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
    // Antes de guardar: el Atasco offline sorteado queda en la partida.
    if (!_enPrimerPlano && antes && _cargado) _programarAtascoOffline();
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

  /// Al salir de la app: sortea los Atascos offline ([Imperio.programarAtascoOffline]) y deja UN aviso local, a la hora
  /// del primero que nada destapa solo (`atasco_offline_aviso`).
  void _programarAtascoOffline() {
    final AtascoOffline? a;
    try {
      imperio.programarAtascoOffline(ahora);
      a = imperio.atascosOfflineProgramados.where((x) => !x.cubierto).firstOrNull;
    } catch (_) {
      return;
    }
    if (a == null) return;
    final e = edificioPorId(a.edificio);
    if (e == null) return;
    final minutos = (a.en - ahora) / 60000;
    final (nEs, nEn) = nombresEdificio(e.id, imperio.partida.mudanzas);
    unawaited(() async {
      try {
        final ok = await programarAvisoAtasco(Duration(milliseconds: max(0, a!.en - ahora)), edificioEs: nEs, edificioEn: nEn);
        if (ok) _anotar('atasco_offline_aviso', {'edificio': e.id, 'minutos': minutos.round()});
      } catch (_) {
        // Sin permiso de notificaciones o en pruebas: no pasa nada.
      }
    }());
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
    _temporadasVistas.clear();
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
    // El motor no vence los atascos: cada uno que sigue tapado al cerrar la sesión cuenta como perdido (una vez por atasco).
    for (final a in imperio.partida.atascos) {
      if (_atascosPerdidos.add(a)) _anotar('atasco_pierde');
    }
    _anotar('sesion_fin', s.fin(imperio.mjTotal));
  }

  /// Compara dorado y atasco con lo visto antes (por identidad) y anota lo que apareció o se fue solo.
  void _mirarCambios({bool anotar = true}) {
    final p = imperio.partida;
    final d = p.dorado;
    if (!identical(d, _doradoVisto)) {
      if (anotar && _doradoVisto != null) _anotar('dorado_pierde');
      if (anotar && d != null) _anotar('dorado_aparece');
      _doradoVisto = d;
    }
    final abiertos = p.atascos;
    var cambio = abiertos.length != _atascosVistos.length;
    for (var k = 0; !cambio && k < abiertos.length; k++) {
      cambio = !identical(abiertos[k], _atascosVistos[k]);
    }
    if (cambio) {
      // Solo el robot (u otro que destapa todo) los quita en el tick; el destape a mano los saca de la lista en tocarAtasco.
      for (final antes in _atascosVistos) {
        if (anotar && !abiertos.any((a) => identical(a, antes))) {
          _anotar('atasco_destapa', {'ms': max(0, ahora - antes.desde), 'perfecto': false, 'robot': true});
        }
      }
      for (final a in abiertos) {
        if (anotar && !_atascosVistos.any((v) => identical(v, a))) _anotar('atasco_aparece', {'edificio': a.edificio, 'abiertos': abiertos.length});
      }
      _atascosVistos = List.of(abiertos);
    }
  }

  /// Temporadas ya anotadas (`temporada_ve`) en esta sesión de juego.
  final Set<String> _temporadasVistas = {};

  void _mirarTemporadas(int t) {
    for (final x in temporadasActivas(imperio.ajustes.temporadas, t)) {
      if (_temporadasVistas.add(x.id)) _anotar('temporada_ve', {'id': x.id});
    }
  }

  void _tick() {
    final dt = _reloj.elapsedMicroseconds / 1e6;
    _reloj
      ..reset()
      ..start();
    _sumarLogros(imperio.tick(ahora, dt));
    for (final (id, precio) in imperio.tomarIndefinidosCortados()) {
      _anotar('alquiler_cortado', {'id': id, 'precio': precio, 'saldo': imperio.saldo});
      alquileresCortadosPendientes.add((id, precio, imperio.saldo));
    }
    _mirarCambios();
    if (_sesion != null) _mirarTemporadas(ahora);
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
    if (!r.contado) return r; // pasó del tope de pujos por segundo: no cuenta para nada
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

  /// Compra o alquila [id] con MJ. Alquilable: [veces] periodos seguidos (x1, x2, x5, x10) o [indefinido].
  bool comprarObjeto(String id, {int veces = 1, bool indefinido = false}) {
    final t = ahora;
    final o = objetoPorId(id);
    final alquilable = o?.tipo == TipoObjeto.alquilable;
    final yaActivo = alquilable && imperio.alquiladoActivo(id, t);
    final calor = alquilable ? imperio.multiplicadorCalor(id, t) : 1.0;
    final saldo = imperio.saldo;
    final ok = imperio.comprarObjeto(id, t, veces: veces, indefinido: indefinido);
    if (ok) {
      _compra('objeto_compra', {'id': id});
      if (alquilable) {
        _anotar('alquilar', {
          'id': id,
          'precio': saldo - imperio.saldo,
          'hasta': imperio.partida.alquilados[id],
          'veces': indefinido && yaActivo ? 0 : (indefinido ? 1 : veces),
          'indefinido': indefinido,
          'calor': (calor * 100).round() / 100,
        });
      }
    }
    return _hecho(ok);
  }

  /// Pausa a mano un alquiler de solo app abierta: su tiempo deja de correr.
  bool pausarAlquiler(String id) {
    final ok = imperio.pausarAlquiler(id, ahora);
    if (ok) _anotar('alquiler_pausa', {'id': id, 'queda': imperio.partida.pausados[id]});
    return _hecho(ok);
  }

  /// Sigue un alquiler pausado con lo que le quedaba.
  bool reanudarAlquiler(String id) {
    final ok = imperio.reanudarAlquiler(id, ahora);
    if (ok) _anotar('alquiler_sigue', {'id': id, 'hasta': imperio.partida.alquilados[id]});
    return _hecho(ok);
  }

  /// Apaga el Indefinido de [id]: sigue hasta su fin y no se renueva.
  bool apagarIndefinido(String id) {
    final ok = imperio.apagarIndefinido(id);
    if (ok) _anotar('alquiler_apagar', {'id': id, 'hasta': imperio.partida.alquilados[id]});
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

  /// Compra un nivel de la Plomería con Rollos de Oro (gasta Rollos: baja el +% por rollo).
  bool comprarObjetoRollos(String id) {
    final p = imperio.precioObjetoRollos(id);
    final costo = p.isFinite ? p.toInt() : 0;
    final ok = imperio.comprarObjetoRollos(id, ahora);
    if (ok) {
      final nivel = imperio.tieneObjetoRollos(id);
      _anotar('rollos_gastar', {'id': id, 'costo': costo, 'quedan': imperio.partida.rollos, 'tiene': nivel});
      _anotar('imperio_plomeria', {'id': id, 'nivel': nivel});
    }
    return _hecho(ok);
  }

  /// Compra un nivel del Llavero con Llaves.
  bool comprarLlavero(String id) {
    final ok = imperio.comprarLlavero(id);
    if (ok) _anotar('imperio_llavero', {'id': id, 'nivel': imperio.nivelLlavero(id)});
    return _hecho(ok);
  }

  /// Prende o apaga el Mayordomo del Llavero.
  void cambiarMayordomo() {
    imperio.cambiarMayordomo();
    _hecho(true);
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
      _atascosVistos.removeWhere((v) => identical(v, a));
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

  /// `alquiler_guia` {id, accion}: la guía de los alquileres (ficha, entendido, ir, empujon).
  void anotarGuia(String id, String accion) => _anotar('alquiler_guia', {'id': id, 'accion': accion});

  /// Marca [clave] como vista en la guía de los alquileres ([Partida.guiaVista]) y guarda en el teléfono.
  void marcarGuia(String clave) {
    if (!imperio.partida.guiaVista.add(clave)) return;
    if (_cargado) unawaited(_guardarLocal());
    notifyListeners();
  }

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
      // El servidor revisa contra su mj_total si ya toca un Rollo: primero se le sube lo jugado.
      await _guardarNube();
      final int n;
      try {
        n = await nube.jalar();
      } catch (e) {
        _error('jalar', e);
        rethrow;
      }
      final ganados = imperio.jalar();
      imperio.partida.jaladas = n;
      final c0 = cadena;
      // Jalar no cambia la mudanza ni la abdicación: se conservan sus datos para que los botones no se apaguen.
      cadena = EstadoCadena(cagadas: 0, necesarias: c0?.necesarias ?? imperio.ajustes.cadenaCagadas, jaladas: n, mudanzas: c0?.mudanzas,
          cagadasCasa: c0?.cagadasCasa, llavesGanadas: c0?.llavesGanadas, mjBase: c0?.mjBase, abdicaciones: c0?.abdicaciones,
          coronasGanadas: c0?.coronasGanadas, cagadasReinado: c0?.cagadasReinado);
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

  // ---------- Mudanza ----------

  /// Se está pidiendo la mudanza al servidor (el botón espera).
  bool mudando = false;

  /// Cagadas reales que cuentan para la mudanza (desde la llegada a la casa, máx 3 por día). 0 sin el dato del servidor.
  int get cagadasCasa => cadena?.cagadasCasa ?? 0;

  /// El servidor ya conoce la mudanza (migración aplicada).
  bool get mudanzaDisponible => cadena?.mudanzas != null;

  /// Se muda: sube lo jugado, el servidor revisa los requisitos y cuenta las Llaves, aquí se reinicia y se guarda.
  /// Devuelve el resultado del servidor (con [ResultadoMudanza.motivo] si dijo que no). Lanza el error de red sin tocar
  /// la partida.
  Future<ResultadoMudanza> mudarse() async {
    if (mudando || jalando) throw StateError('Ya se está mudando');
    mudando = true;
    try {
      await _guardarNube();
      final ResultadoMudanza r;
      try {
        r = await nube.mudar();
      } catch (e) {
        _error('mudar', e);
        rethrow;
      }
      if (!r.ok) {
        _anotar('mudanza_rechazada', {'motivo': r.motivo});
        return r;
      }
      final p = imperio.partida;
      final llavesAntes = p.llavesGanadas;
      imperio.mudarse(llavesServidor: r.llaves, mjBaseServidor: r.mjBase, ahora: ahora);
      p.mudanzas = max(p.mudanzas, r.mudanzas);
      p.llavesGanadas = max(p.llavesGanadas, llavesAntes + r.llaves);
      final c = cadena;
      if (c != null) {
        cadena = EstadoCadena(cagadas: c.cagadas, necesarias: c.necesarias, jaladas: c.jaladas, mudanzas: p.mudanzas, cagadasCasa: 0,
            llavesGanadas: p.llavesGanadas, mjBase: p.mjBase, abdicaciones: c.abdicaciones, coronasGanadas: c.coronasGanadas,
            cagadasReinado: c.cagadasReinado);
      }
      final dia = p.primerDia > 0 ? ((ahora - p.primerDia) / Duration.millisecondsPerDay).floor() + 1 : 1;
      _anotar('imperio_mudanza', {'mudanzas': p.mudanzas, 'llaves': r.llaves, 'dia': dia});
      _mirarCambios(anotar: false);
      notifyListeners();
      await _guardarLocal();
      await _guardarNube();
      return r;
    } finally {
      mudando = false;
    }
  }

  /// Partidas de antes de abdicar no sabían cuándo llegaste a la casa: se cuenta desde ahora.
  void _marcarCasaEn() {
    final p = imperio.partida;
    if (p.casaEn <= 0 && (p.mudanzas > 0 || p.abdicaciones > 0)) p.casaEn = ahora;
  }

  // ---------- Abdicar 👑 ----------

  /// Se está pidiendo la abdicación al servidor (el botón espera).
  bool abdicando = false;

  /// Cagadas reales que cuentan para abdicar (desde la última abdicación, máx 3 por día). 0 sin el dato del servidor.
  int get cagadasReinado => cadena?.cagadasReinado ?? 0;

  /// El servidor ya conoce la abdicación (migración aplicada).
  bool get abdicarDisponible => cadena?.abdicaciones != null;

  /// Abdica: sube lo jugado, el servidor revisa los requisitos, cuenta las Coronas y aplica lo suyo de La Corte; aquí se
  /// reinicia y se guarda. Devuelve el resultado del servidor (con [ResultadoAbdicar.motivo] si dijo que no). Lanza el
  /// error de red sin tocar la partida.
  Future<ResultadoAbdicar> abdicar() async {
    if (abdicando || mudando || jalando) throw StateError('Ya se está abdicando');
    abdicando = true;
    try {
      await _guardarNube();
      final ResultadoAbdicar r;
      try {
        r = await nube.abdicar();
      } catch (e) {
        _error('abdicar', e);
        rethrow;
      }
      if (!r.ok) {
        _anotar('abdicar_rechazada', {'motivo': r.motivo});
        return r;
      }
      final p = imperio.partida;
      final dia = p.primerDia > 0 ? ((ahora - p.primerDia) / Duration.millisecondsPerDay).floor() + 1 : 1;
      final antes = p.abdicaciones;
      imperio.abdicar(
          coronasServidor: r.coronas, mudanzasServidor: r.mudanzas, llavesServidor: r.llavesGanadas, mjBaseServidor: r.mjBase, ahora: ahora);
      p.abdicaciones = max(p.abdicaciones, max(antes + 1, r.abdicaciones));
      final c = cadena;
      if (c != null) {
        cadena = EstadoCadena(cagadas: c.cagadas, necesarias: c.necesarias, jaladas: c.jaladas, mudanzas: p.mudanzas, cagadasCasa: 0,
            llavesGanadas: p.llavesGanadas, mjBase: p.mjBase, abdicaciones: p.abdicaciones, coronasGanadas: p.coronasGanadas,
            cagadasReinado: 0);
      }
      _anotar('imperio_abdicar', {'abdicaciones': p.abdicaciones, 'coronas': r.coronas, 'dia': dia});
      _mirarCambios(anotar: false);
      notifyListeners();
      await _guardarLocal();
      await _guardarNube();
      return r;
    } finally {
      abdicando = false;
    }
  }

  /// Compra el nivel siguiente de [id] en La Corte con Coronas y guarda.
  bool comprarCorte(String id) {
    if (!imperio.comprarCorte(id)) return false;
    _anotar('imperio_corte', {'id': id, 'nivel': imperio.nivelCorte(id)});
    _mirarCambios(anotar: false);
    notifyListeners();
    unawaited(guardarTodo());
    return true;
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
      final r = await nube.guardar(estado, imperio.mjTotal, imperio.ritmoEfectivo(ahora), version: build);
      if (r.versionVieja && !_servidorVersionVieja) {
        _servidorVersionVieja = true;
        _anotar('version_vieja', {'build': build});
        if (!_cerrado) notifyListeners();
      }
      if (r.recortado) {
        // Para cazar trampas (supabase/consultas/exploits.sql): cuánto dijo la app y cuánto aceptó el servidor.
        _anotar('guardado_recortado', {'mj_app': imperio.mjTotal, 'mj_servidor': r.mjTotal});
        aceptarRecorte(imperio.partida, r.mjTotal, mjCasaServidor: r.mjCasa);
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
    if (identical(vivo, this)) vivo = null;
    frescaHasta.removeListener(_ponerFresca);
    cloacaCambio.removeListener(_cloacaCambio);
    _bucle?.cancel();
    _bucle = null;
    _cerrarSesion();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cargado ? guardarTodo() : _vaciarTelemetria());
    super.dispose();
  }

  // ---------- Cagadón con apuesta (apuesta.dart, apuesta_local.dart) ----------

  /// El controlador cargado, si hay uno: lo que se apuesta o cobra en el chat se aplica al momento en vez de esperar a
  /// que se abra el Imperio.
  static ControlImperio? vivo;

  bool _aplicandoApuestas = false;

  bool get apuestaCargada => _cargado && !_cerrado;

  /// Para apostar con la partida abierta: null si el Imperio está apagado, la versión bloqueada, las apuestas apagadas o
  /// todavía no hay producción.
  ResumenApuesta? get resumenApuesta {
    if (!apuestaCargada || apagado || versionVieja || flags.apuestaMaxMin <= 0 || imperio.mjTotal <= 0) return null;
    final mps = imperio.mpsSinEfectos(contarAtasco: false);
    return mps > 0 && mps.isFinite ? ResumenApuesta(saldo: imperio.saldo, mps: mps, tope: flags.apuestaMaxMin) : null;
  }

  /// Aplica la cola de la apuesta (descuentos, premios y devoluciones) con la producción de ahora. Apagado o con la
  /// versión bloqueada, la cola espera. Los premios dan sus logros (el servidor ya validó el ganador y el cobro único).
  Future<void> aplicarApuestas() async {
    if (!apuestaCargada || apagado || versionVieja || _aplicandoApuestas) return;
    _aplicandoApuestas = true;
    try {
      final cola = await sacarApuntes(_userId);
      if (cola.isEmpty) return;
      if (_cerrado) return await devolverApuntes(_userId, cola);
      final mps = imperio.mpsSinEfectos(contarAtasco: false);
      final p = imperio.partida;
      final nuevos = <Logro>[];
      for (final a in cola) {
        aplicarApunte(p, a, mps);
        for (final id in logrosDeApunte(a)) {
          final l = logroPorId(id);
          if (l != null && p.logros.add(id)) nuevos.add(l);
        }
      }
      _sumarLogros(nuevos);
      _fichasHechas();
    } finally {
      _aplicandoApuestas = false;
    }
  }
}
