import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../main.dart' show db;
import 'motor.dart';
import 'nube.dart';

// ---------- Partes puras (se prueban sin Supabase) ----------

/// Al cargar, ¿manda la copia local? Solo si existe y lleva más MJ totales que la del servidor,
/// o si el servidor todavía no tiene partida. Empate: gana el servidor.
bool usarCopiaLocal({required double? mjLocal, required double mjServidor, required bool servidorVacio}) {
  if (mjLocal == null) return false;
  if (servidorVacio) return true;
  return mjLocal > mjServidor;
}

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

// ---------- Controlador ----------

/// Dueño de la partida del Imperio: carga y mezcla, reloj del servidor, bucle a 10 Hz y guardados.
class ControlImperio extends ChangeNotifier with WidgetsBindingObserver {
  ControlImperio({NubeImperio? nube}) : nube = nube ?? NubeImperio();

  final NubeImperio nube;
  Imperio imperio = Imperio();

  bool cargando = true;
  bool sinConexion = false;
  bool fundador = false;

  /// Avisos para la pantalla, en orden: bienvenida de veterano, tiempo fuera y Descarga. Los consume la pantalla.
  bool bienvenidaPendiente = false;
  ResultadoOffline? offlinePendiente;
  ResultadoCagadas? descargaPendiente;

  /// Logros nuevos para el aviso de arriba.
  final List<Logro> logrosNuevos = [];

  int _desfase = 0; // reloj del servidor menos reloj del teléfono, en ms
  int get ahora => DateTime.now().millisecondsSinceEpoch + _desfase;

  bool _cargado = false, _ocupadoNube = false, _guardandoNube = false, _cerrado = false;
  bool _visible = false, _enPrimerPlano = true;
  Timer? _bucle;
  final Stopwatch _reloj = Stopwatch();
  int _ultimoAviso = 0;
  double _desdeLocal = 0, _desdeNube = 0;

  String get _userId => db.auth.currentUser?.id ?? 'sin_sesion';

  // ---------- Carga ----------

  Future<void> iniciar() async {
    WidgetsBinding.instance.addObserver(this);
    final local = await nube.cargarLocal(_userId);
    final estadoLocal = local?['estado'] is Map ? Map<String, dynamic>.from(local!['estado'] as Map) : null;
    final mjLocal = estadoLocal == null ? null : (local!['mjTotal'] as num?)?.toDouble();
    final ultimaLocal = (estadoLocal?['ultima_vez'] as num?)?.toInt();
    _ocupadoNube = true;
    try {
      final carga = await nube.cargar();
      _desfase = carga.ahora.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
      final vacio = carga.nuevo || carga.estado.isEmpty;
      final local1 = usarCopiaLocal(mjLocal: mjLocal, mjServidor: carga.mjTotal, servidorVacio: vacio);
      imperio = Imperio.desdeJson(local1 ? estadoLocal : carga.estado, cagadas: carga.cagadasTotal, fichas: carga.fichas);
      if (!local1 && !vacio) aceptarRecorte(imperio.partida, carga.mjTotal);
      fundador = carga.fundador;
      final desde = inicioOffline([ultimaLocal, carga.guardado.millisecondsSinceEpoch, imperio.partida.ultimaVez], ahora);
      if (desde != null) _guardarAviso(imperio.aplicarOffline(desde, ahora));
      _aplicarNuevas(carga.nuevas);
      bienvenidaPendiente = carga.nuevo && carga.cagadasTotal > 0;
    } catch (_) {
      // Sin red: se juega con la copia local (o una partida nueva) y se reintenta la nube al guardar.
      sinConexion = true;
      imperio = Imperio.desdeJson(
        estadoLocal,
        cagadas: (estadoLocal?['_cagadas'] as num?)?.toInt() ?? 0,
        fichas: (estadoLocal?['_fichas'] as num?)?.toInt() ?? 0,
      );
      final desde = inicioOffline([ultimaLocal], ahora);
      if (desde != null) _guardarAviso(imperio.aplicarOffline(desde, ahora));
    } finally {
      _ocupadoNube = false;
    }
    if (_cerrado) return;
    logrosNuevos.addAll(imperio.revisarLogros());
    _cargado = true;
    cargando = false;
    unawaited(_guardarLocal());
    _actualizarBucle();
    notifyListeners();
  }

  void _guardarAviso(ResultadoOffline r) {
    if (r.ganado > 0) offlinePendiente = r;
  }

  void _aplicarNuevas(List<CagadaNueva> nuevas) {
    if (nuevas.isEmpty) return;
    final r = imperio.aplicarCagadas([for (final c in nuevas) CagadaReal(tipo: c.tipo, peso: c.peso, creada: c.creada)], ahora);
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
      _aplicarNuevas(carga.nuevas);
      logrosNuevos.addAll(imperio.revisarLogros());
      notifyListeners();
    } catch (_) {
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
    _actualizarBucle();
    if (v) unawaited(recargarCagadas());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final antes = _enPrimerPlano;
    _enPrimerPlano = state == AppLifecycleState.resumed;
    _actualizarBucle();
    if (!_enPrimerPlano && antes && _cargado) unawaited(guardarTodo());
    if (_enPrimerPlano && !antes && _visible) unawaited(recargarCagadas());
  }

  void _actualizarBucle() {
    final debe = _cargado && _visible && _enPrimerPlano && !_cerrado;
    if (debe && _bucle == null) {
      // Si estuvo parado un rato (otra pestaña o la app en segundo plano), se cobra como tiempo fuera.
      final t = ahora;
      if (t - imperio.partida.ultimaVez >= minimoOffline.inMilliseconds) _guardarAviso(imperio.aplicarOffline(imperio.partida.ultimaVez, t));
      _reloj
        ..reset()
        ..start();
      _bucle = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    } else if (!debe && _bucle != null) {
      _bucle!.cancel();
      _bucle = null;
      _reloj.stop();
    }
  }

  void _tick() {
    final dt = _reloj.elapsedMicroseconds / 1e6;
    _reloj
      ..reset()
      ..start();
    logrosNuevos.addAll(imperio.tick(ahora, dt));
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
    _avisar();
    return r;
  }

  bool comprarEdificio(String id, int n) => _hecho(imperio.comprarEdificioVarios(id, n, ahora));
  bool comprarMejora(String id) => _hecho(imperio.comprarMejora(id));
  bool comprarObjeto(String id) => _hecho(imperio.comprarObjeto(id, ahora));
  bool usarObjeto(String id) => _hecho(imperio.usarObjeto(id, ahora));

  ResultadoDorado? tocarDorado() {
    final r = imperio.tocarDorado(ahora);
    _avisar();
    return r;
  }

  ResultadoDestape? tocarAtasco() {
    final r = imperio.tocarAtasco(ahora);
    _avisar();
    return r;
  }

  bool _hecho(bool ok) {
    if (ok) {
      logrosNuevos.addAll(imperio.revisarLogros());
      _avisar();
    }
    return ok;
  }

  /// Gasta una Ficha en el servidor y activa la Cagada fresca. false si no quedaban. Lanza el error de red.
  Future<bool> usarCagadaFresca() async {
    final r = await nube.usarFicha();
    if (r < 0) {
      imperio.fichas = 0;
      notifyListeners();
      return false;
    }
    imperio.activarCagadaFresca(ahora);
    imperio.fichas = r;
    notifyListeners();
    unawaited(_guardarLocal());
    return true;
  }

  // ---------- Guardado ----------

  Future<void> _guardarLocal() async {
    _desdeLocal = 0;
    final estado = {...imperio.toJson(), '_cagadas': imperio.cagadas, '_fichas': imperio.fichas};
    try {
      await nube.guardarLocal(_userId, estado, imperio.mjTotal, imperio.mpsSinEfectos());
    } catch (_) {}
  }

  Future<void> _guardarNube() async {
    _desdeNube = 0;
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
      final r = await nube.guardar(imperio.toJson(), imperio.mjTotal, imperio.mpsSinEfectos());
      if (r.recortado) aceptarRecorte(imperio.partida, r.mjTotal);
    } catch (_) {
      sinConexion = true;
      if (!_cerrado) notifyListeners();
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
    _bucle?.cancel();
    _bucle = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(guardarTodo());
    super.dispose();
  }
}
