// Diagnóstico de la app: errores, datos del teléfono, por qué se cerró la vez anterior, partidas cortadas y memoria.
// Todo sale por `Telemetria.instancia` (eventos en su dartdoc). Nunca lanza: si algo falla, la app sigue igual.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, ProcessInfo;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'imperio/minijuegos/sonido.dart';
import 'imperio/telemetria.dart';
import 'main.dart' show esDeRed;

const _canal = MethodChannel('rey_cagon/equipo');
const _clavePartida = 'diag_partida';
const _claveSalida = 'diag_ultima_salida';

/// Teléfono con poca memoria (Android Go o menos de 3 GB): sonido, música y caché de imágenes van en modo liviano.
bool telefonoLiviano = false;

/// Android Go o poca RAM. [ramMb] null = no se sabe (cuenta solo [ramBaja]).
bool esLiviano({required bool ramBaja, int? ramMb}) => ramBaja || (ramMb != null && ramMb > 0 && ramMb < 3000);

/// Las líneas útiles de una pila: las primeras [arriba] y después las de la app que falten, hasta [maximo].
/// Las pilas sin símbolos (build con --split-debug-info) se guardan tal cual, con su cabecera, para simbolizarlas después.
List<String> resumirPila(String? pila, {int arriba = 6, int maximo = 14, int largo = 160}) {
  if (pila == null) return const [];
  final lineas = [for (final l in const LineSplitter().convert(pila)) if (l.trim().isNotEmpty) l.trim()];
  if (lineas.isEmpty) return const [];
  String corta(String l) => l.length <= largo ? l : l.substring(0, largo);
  if (lineas.first.startsWith('***') || lineas.any((l) => l.contains(' abs ') && l.contains(' virt '))) {
    return [for (final l in lineas.take(maximo)) corta(l.replaceAll(RegExp(r'\s+'), ' '))];
  }
  final elegidas = <int>{};
  for (var i = 0; i < lineas.length && elegidas.length < arriba; i++) {
    elegidas.add(i);
  }
  for (var i = 0; i < lineas.length && elegidas.length < maximo; i++) {
    if (lineas[i].contains('package:rey_cagon/')) elegidas.add(i);
  }
  return [for (final i in elegidas.toList()..sort()) corta(lineas[i].replaceFirst(RegExp(r'^#\d+\s+'), '').replaceAll(RegExp(r'\s+'), ' '))];
}

/// Las salidas que no se habían contado: más nuevas que [ultima] (ms), las más nuevas primero, hasta [maximo].
List<Map<String, Object?>> salidasNuevas(List<Map<String, Object?>> salidas, int ultima, {int maximo = 5}) {
  final nuevas = [for (final s in salidas) if ((s['cuando'] as num?) != null && (s['cuando'] as num) > ultima) s];
  nuevas.sort((a, b) => (b['cuando'] as num).compareTo(a['cuando'] as num));
  return nuevas.take(maximo).toList();
}

/// Evento `minijuego_cortado` de una partida que quedó abierta: con la salida que la cerró, si hay una después de empezar.
Map<String, Object?> partidaCortada(Map<String, Object?> partida, List<Map<String, Object?>> salidas, int ahora) {
  final inicio = (partida['ms'] as num?)?.toInt() ?? ahora;
  final datos = <String, Object?>{
    'juego': partida['juego'],
    'hace_s': ((ahora - inicio) / 1000).round(),
    'ultima_foto': partida['foto'],
  };
  Map<String, Object?>? salida;
  for (final s in salidas) {
    final c = (s['cuando'] as num?)?.toInt();
    if (c != null && c >= inicio && (salida == null || c < (salida['cuando'] as num))) salida = s;
  }
  if (salida != null) {
    datos['razon'] = salida['razon'];
    datos['segundos'] = (((salida['cuando'] as num).toInt() - inicio) / 1000).round();
    datos['pss_mb'] = salida['pss_mb'];
    datos['rss_mb'] = salida['rss_mb'];
  }
  return datos;
}

/// Errores distintos por sesión (tipo + primera línea de la pila) y tope total, para no llenar la cola con el mismo.
class FiltroErrores {
  FiltroErrores({this.tope = 15});
  final int tope;
  final _vistos = <String, int>{};

  /// true = es nuevo y hay cupo.
  bool deja(String tipo, List<String> pila) {
    final clave = '$tipo|${pila.isEmpty ? '' : pila.first}';
    final n = _vistos[clave];
    if (n != null) {
      _vistos[clave] = n + 1;
      return false;
    }
    if (_vistos.length >= tope) return false;
    _vistos[clave] = 1;
    return true;
  }
}

class Diagnostico with WidgetsBindingObserver {
  Diagnostico._();
  static final instancia = Diagnostico._();

  /// En `flutter test` no toma fotos ni programa envíos (los timers pendientes rompen las pruebas de widgets).
  static bool apagado = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  final _filtro = FiltroErrores();
  Timer? _envio;
  Timer? _fotos;
  DateTime? _ultimaPresion;
  String? _juego;
  int _inicioJuego = 0;
  bool _iniciado = false;

  Telemetria get _tele => Telemetria.instancia;

  /// En main(), antes de runApp: engancha errores, lee el teléfono y manda lo que quedó de la vez anterior.
  Future<void> iniciar() async {
    if (_iniciado) return;
    _iniciado = true;
    _engancharErrores();
    try {
      await _tele.leerVersion().timeout(const Duration(seconds: 2));
    } catch (_) {}
    final info = await _info();
    telefonoLiviano = esLiviano(ramBaja: info['ram_baja'] == true, ramMb: (info['ram_mb'] as num?)?.toInt());
    if (telefonoLiviano) {
      Sonido.liviano = true;
      // La caché de imágenes por defecto es de 100 MB: en un Android Go eso es casi toda la memoria de la app.
      PaintingBinding.instance.imageCache
        ..maximumSizeBytes = 24 << 20
        ..maximumSize = 200;
    }
    _tele.registrar('equipo', {...info, 'liviano': telefonoLiviano, ..._memoriaDart()});
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loDeAntes());
  }

  void _engancharErrores() {
    final antes = FlutterError.onError;
    FlutterError.onError = (d) {
      reportar(d.exception, d.stack, donde: 'flutter', contexto: d.context?.toDescription());
      antes?.call(d);
    };
    final antesP = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, s) {
      reportar(e, s, donde: 'plataforma');
      return antesP?.call(e, s) ?? false;
    };
  }

  /// Anota un error (`error_app`). Lo usan los ganchos de arriba; se puede llamar a mano desde un catch.
  void reportar(Object error, StackTrace? pila, {required String donde, String? contexto}) {
    try {
      final tipo = error.runtimeType.toString();
      final lineas = resumirPila(pila?.toString());
      if (!_filtro.deja(tipo, lineas)) return;
      _tele.registrar('error_app', {
        'donde': donde,
        'tipo': tipo,
        'mensaje': error.toString(),
        'contexto': contexto,
        'red': esDeRed(error),
        'juego': _juego,
        'pila': lineas,
        ..._memoriaDart(),
      });
      _enviarPronto();
    } catch (_) {}
  }

  void _enviarPronto() {
    if (apagado) return;
    _envio?.cancel();
    _envio = Timer(const Duration(seconds: 3), () => unawaited(_tele.vaciar()));
  }

  Future<Map<String, Object?>> _info() async {
    if (kIsWeb || !Platform.isAndroid) return {};
    try {
      final m = await _canal.invokeMapMethod<String, Object?>('info').timeout(const Duration(seconds: 2));
      return m ?? {};
    } catch (_) {
      return {};
    }
  }

  static Map<String, Object?> _memoriaDart() {
    try {
      return {
        'rss_mb': ProcessInfo.currentRss >> 20,
        'rss_max_mb': ProcessInfo.maxRss >> 20,
        'imagenes_mb': PaintingBinding.instance.imageCache.currentSizeBytes >> 20,
      };
    } catch (_) {
      return {};
    }
  }

  // Por qué se cerró la app las veces anteriores (Android 11+) y si quedó una partida abierta.
  Future<void> _loDeAntes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var salidas = <Map<String, Object?>>[];
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final l = await _canal.invokeListMethod<Object?>('salidas').timeout(const Duration(seconds: 3));
          salidas = [for (final s in l ?? const []) if (s is Map) Map<String, Object?>.from(s)];
        } catch (_) {}
      }
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final ultima = prefs.getInt(_claveSalida) ?? 0;
      final nuevas = salidasNuevas(salidas, ultima);
      for (final s in nuevas) {
        _tele.registrar('app_salida', {...s, 'hace_s': ((ahora - (s['cuando'] as num)) / 1000).round()});
      }
      if (nuevas.isNotEmpty) await prefs.setInt(_claveSalida, (nuevas.first['cuando'] as num).toInt());
      final p = prefs.getString(_clavePartida);
      if (p != null) {
        await prefs.remove(_clavePartida);
        final j = jsonDecode(p);
        if (j is Map) _tele.registrar('minijuego_cortado', partidaCortada(Map<String, Object?>.from(j), salidas, ahora));
      }
    } catch (_) {}
    // Que llegue aunque no se abra el Imperio (el controlador vacía la cola cada 60 s solo con el Imperio abierto).
    Timer(const Duration(seconds: 8), () => unawaited(_tele.vaciar()));
  }

  /// Empieza una partida de minijuego: deja la marca (si la app muere, el próximo arranque manda `minijuego_cortado`)
  /// y toma una foto de la memoria cada 20 s mientras dura.
  void partidaEmpieza(String juego) {
    if (apagado) return;
    _juego = juego;
    _inicioJuego = DateTime.now().millisecondsSinceEpoch;
    _fotos?.cancel();
    unawaited(_foto('inicio'));
    _fotos = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_foto('partida')));
  }

  /// La partida terminó o se salió del juego: quita la marca.
  void partidaTermina() {
    if (apagado) return;
    _fotos?.cancel();
    _fotos = null;
    _juego = null;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_clavePartida);
      } catch (_) {}
    }());
  }

  Future<void> _foto(String motivo) async {
    final juego = _juego;
    if (juego == null) return;
    final info = await _info();
    if (_juego != juego) return;
    final foto = <String, Object?>{
      'libre_mb': info['libre_mb'],
      'memoria_baja': info['memoria_baja'],
      'java_usada_mb': info['java_usada_mb'],
      'nativa_mb': info['nativa_mb'],
      ..._memoriaDart(),
      'seg': ((DateTime.now().millisecondsSinceEpoch - _inicioJuego) / 1000).round(),
    };
    _tele.registrar('memoria_foto', {'motivo': motivo, 'juego': juego, ...foto});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clavePartida, jsonEncode({'juego': juego, 'ms': _inicioJuego, 'foto': foto}));
    } catch (_) {}
    // Con la marca escrita, lo anotado hasta ahora sale ya: si la app muere a mitad de partida, igual llega.
    if (motivo == 'inicio') _enviarPronto();
  }

  @override
  void didHaveMemoryPressure() {
    final ahora = DateTime.now();
    final antes = _ultimaPresion;
    // Suelta lo que se puede rehacer: imágenes en caché y efectos de sonido que no están sonando.
    try {
      PaintingBinding.instance.imageCache.clear();
    } catch (_) {}
    unawaited(Sonido.liberar());
    if (antes != null && ahora.difference(antes) < const Duration(seconds: 30)) return;
    _ultimaPresion = ahora;
    _tele.registrar('memoria_baja', {'juego': _juego, 'liviano': telefonoLiviano, ..._memoriaDart()});
    _enviarPronto();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_tele.vaciar());
  }
}
