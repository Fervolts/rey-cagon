// Eventos del Imperio para estudiar cómo se juega. Cola en memoria + SharedPreferences, se manda en lotes por RPC.
// Nunca lanza al que llama: si no hay red, los eventos esperan al próximo vaciar().

import 'dart:convert';
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

/// Manda un lote al servidor y devuelve cuántos guardó. Si lanza, el lote se queda en la cola.
typedef EnviarEventos = Future<int> Function(List<Map<String, Object?>> lote);

Future<int> _enviarPorRpc(List<Map<String, Object?>> lote) async {
  final r = await conReintento(() => db.rpc('imperio_registrar', params: {'p_eventos': lote}));
  return r is num ? r.toInt() : 0;
}

/// Telemetría del Imperio. Usar `Telemetria.instancia`; en las pruebas se crea una con `enviar` falso.
///
/// CATÁLOGO DE EVENTOS (nombre {campos de datos}). Lo emite el controlador; `seg_partida` = segundos de juego activo de
/// la partida guardada (el motor todavía no lo cuenta: hay que agregarlo a `Partida` y sumarlo en `tick`).
///
/// - `sesion_inicio` {cagadas, mj_total, mps, offline_s, variantes} (variantes = `FlagsImperio.variantes`, clave→variante)
/// - `sesion_fin` {segundos, pujos, mj_ganados, compras}
/// - `edificio` {id, cantidad, precio, seg_partida} (cantidad = cuántos tiene después de comprar)
/// - `mejora` {id, precio, seg_partida}
/// - `objeto_compra` {id}
/// - `objeto_uso` {id}
/// - `dorado_aparece` {}
/// - `dorado_toca` {efecto} (nombre de `EfectoDorado`)
/// - `dorado_pierde` {}
/// - `atasco_aparece` {edificio}
/// - `atasco_destapa` {ms, perfecto, robot}
/// - `atasco_pierde` {}
/// - `logro` {id}
/// - `offline` {segundos, tope_lleno, ganado}
/// - `descarga` {cagadas, ganado}
/// - `bienvenida` {cagadas, fichas, fundador}
/// - `ficha_usa` {}
/// - `sala_abre` {}
/// - `minijuego_toca` {id} (los "próximamente")
/// - `pestana_abre` {}
/// - `error` {donde}
///
/// Nombres: `[a-z0-9_]`, hasta 40. Datos: JSON plano, hasta ~3,5 KB (si no, se manda `{recortado: true}`).
class Telemetria {
  static const int maxCola = 500;
  static const int tamanoLote = 100;
  static const int maxBytesDatos = 3500;
  static const String clavePrefs = 'imperio_telemetria_cola';
  static final RegExp _nombreValido = RegExp(r'^[a-z0-9_]{1,40}$');

  /// La de la app. El controlador llama `vaciar()` cada 60 s y al pausar.
  static final Telemetria instancia = Telemetria();

  final EnviarEventos _enviar;
  final int Function() _reloj;

  /// Id de esta sesión de la app (formato uuid v4, nuevo en cada arranque).
  final String sesion;

  /// Versión de la app (`1.14.2+50`). Se llena con `leerVersion()` o a mano.
  String version;

  final List<Map<String, Object?>> _cola = [];
  Future<void>? _carga;
  bool _guardadoPendiente = false;
  bool _vaciando = false;

  Telemetria({EnviarEventos? enviar, int Function()? reloj, Random? azar, this.version = ''})
      : _enviar = enviar ?? _enviarPorRpc,
        _reloj = reloj ?? (() => DateTime.now().millisecondsSinceEpoch),
        sesion = idSesion(azar ?? Random.secure());

  /// 128 bits al azar con forma de uuid v4 (la columna `sesion` es uuid).
  static String idSesion(Random azar) {
    final b = List<int>.generate(16, (_) => azar.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Eventos esperando envío (los de disco cuentan después de la primera carga).
  int get pendientes => _cola.length;

  /// Copia de la cola, el más viejo primero (para pruebas).
  List<Map<String, Object?>> get cola => List.unmodifiable(_cola);

  Future<void> leerVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      version = '${i.version}+${i.buildNumber}';
    } catch (_) {}
  }

  /// Anota un evento. No espera nada ni lanza.
  void registrar(String evento, [Map<String, Object?> datos = const {}]) {
    if (!_nombreValido.hasMatch(evento)) return;
    var d = _limpiarMapa(datos, 0);
    try {
      if (utf8.encode(jsonEncode(d)).length > maxBytesDatos) d = {'recortado': true};
    } catch (_) {
      d = {'recortado': true};
    }
    _cola.add({'evento': evento, 'datos': d, 'sesion': sesion, 'version': version, 'ms': _reloj()});
    _recortar();
    _cargar();
    _programarGuardado();
  }

  /// Manda la cola en lotes de 100 y quita lo enviado. Si un lote falla, para y lo deja para la próxima.
  Future<void> vaciar() async {
    if (_vaciando) return;
    _vaciando = true;
    try {
      await _cargar();
      while (_cola.isNotEmpty) {
        final lote = _cola.take(tamanoLote).toList();
        try {
          await _enviar(lote);
        } catch (_) {
          break;
        }
        final enviados = Set<Map<String, Object?>>.identity()..addAll(lote);
        _cola.removeWhere(enviados.contains);
      }
      await guardar();
    } catch (_) {
    } finally {
      _vaciando = false;
    }
  }

  /// Escribe la cola en disco ya (al pausar).
  Future<void> guardar() async {
    try {
      await _cargar();
      final p = await SharedPreferences.getInstance();
      await p.setString(clavePrefs, jsonEncode(_cola));
    } catch (_) {}
  }

  void _programarGuardado() {
    if (_guardadoPendiente) return;
    _guardadoPendiente = true;
    Future<void>(() async {
      _guardadoPendiente = false;
      await guardar();
    });
  }

  /// Trae una sola vez lo que quedó en disco de sesiones anteriores y lo pone delante.
  Future<void> _cargar() => _carga ??= () async {
        try {
          final p = await SharedPreferences.getInstance();
          final s = p.getString(clavePrefs);
          if (s == null) return;
          final j = jsonDecode(s);
          if (j is! List) return;
          final viejos = [for (final e in j) if (e is Map && e['evento'] is String) Map<String, Object?>.from(e)];
          _cola.insertAll(0, viejos);
          _recortar();
        } catch (_) {}
      }();

  void _recortar() {
    if (_cola.length > maxCola) _cola.removeRange(0, _cola.length - maxCola);
  }

  // JSON seguro: sin NaN/infinito (jsonEncode los rechaza), textos cortos, poca profundidad.
  static Object? _limpiar(Object? v, int nivel) {
    if (v == null || v is bool || v is int) return v;
    if (v is num) return v.isFinite ? v : null;
    if (v is String) return v.length > 200 ? v.substring(0, 200) : v;
    if (v is Enum) return v.name;
    if (nivel >= 3) return '$v';
    if (v is Map) return _limpiarMapa(v, nivel + 1);
    if (v is Iterable) return [for (final x in v.take(50)) _limpiar(x, nivel + 1)];
    return '$v';
  }

  static Map<String, Object?> _limpiarMapa(Map<dynamic, dynamic> m, int nivel) => {
        for (final e in m.entries.take(40)) '${e.key}': _limpiar(e.value, nivel),
      };
}
