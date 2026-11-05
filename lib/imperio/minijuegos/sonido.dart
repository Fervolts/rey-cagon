// Sonido de los minijuegos: efectos cortos y un loop de música por juego.
// Los archivos salen de scripts/sonidos.py (efectos) y scripts/musica_cagar.py (músicas), síntesis propia, y viven en assets/sonidos/.
// Nunca lanza: en tests o sin audio no suena y ya. El silencio se guarda en el teléfono.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Efectos que existen en `assets/sonidos/NOMBRE.wav`.
const efectosMinijuegos = <String>[
  'plop', 'chapuzon', 'descarga', 'pujo', 'pujo_largo', 'destapador', 'glug', 'burbuja', 'rollo', 'dorado',
  'combo', 'fusion1', 'fusion2', 'fusion3', 'fusion4', 'cucaracha', 'fallo', 'perdiste', 'gana', 'boton', 'alerta', 'viento',
];

/// Músicas en `assets/sonidos/NOMBRE.m4a` (loops sin corte; la de Fusión dura 96 s).
const musicasMinijuegos = <String>['musica_tuberia', 'musica_destapa', 'musica_fusion'];

class Sonido {
  Sonido._();

  /// Apagado a la fuerza. En `flutter test` arranca apagado para no tocar el plugin.
  static bool apagado = Platform.environment.containsKey('FLUTTER_TEST');

  /// Lo que eligió la persona con el botón de la bocina.
  static final silencio = ValueNotifier<bool>(false);
  static const _clave = 'minijuegos_silencio';
  static bool _leido = false;

  static final _pools = <String, AudioPool>{};
  static final _cargando = <String, Future<AudioPool?>>{};
  static AudioPlayer? _musica;
  static String? _musicaActual;
  static AppLifecycleListener? _ciclo;
  static Future<void>? _contexto;

  // Sin pedir el foco de audio: si no, cada efecto pausa la música del juego (y la de otras apps).
  static Future<void> _mezclar() => _contexto ??= () async {
        try {
          await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
        } catch (_) {}
      }();

  static Future<void> leerPreferencia() async {
    if (_leido) return;
    _leido = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      silencio.value = prefs.getBool(_clave) ?? false;
    } catch (_) {}
  }

  static Future<void> alternarSilencio() async {
    silencio.value = !silencio.value;
    // Pausa en vez de parar: al quitar el silencio sigue el loop del juego que está abierto.
    try {
      if (silencio.value) {
        await _musica?.pause();
      } else if (_musicaActual != null && !apagado) {
        await _musica?.resume();
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clave, silencio.value);
    } catch (_) {}
  }

  static bool get _mudo => apagado || silencio.value;

  static Future<AudioPool?> _pool(String nombre) {
    final ya = _pools[nombre];
    if (ya != null) return Future.value(ya);
    return _cargando[nombre] ??= () async {
      try {
        await _mezclar();
        final p = await AudioPool.createFromAsset(path: 'sonidos/$nombre.wav', maxPlayers: 4);
        _pools[nombre] = p;
        return p;
      } catch (_) {
        return null;
      } finally {
        _cargando.remove(nombre);
      }
    }();
  }

  /// Carga de antemano los efectos de un juego para que el primero no llegue tarde.
  static Future<void> precargar(Iterable<String> nombres) async {
    if (apagado) return;
    await leerPreferencia();
    await Future.wait(nombres.map(_pool));
  }

  /// Toca un efecto. [volumen] de 0 a 1.
  static void tocar(String nombre, {double volumen = 1}) {
    if (_mudo) return;
    unawaited(() async {
      try {
        final p = await _pool(nombre);
        await p?.start(volume: volumen.clamp(0.0, 1.0));
      } catch (_) {}
    }());
  }

  /// Arranca el loop de un juego (si ya suena ese, no hace nada).
  static Future<void> musica(String nombre, {double volumen = 0.45}) async {
    if (_mudo) return;
    if (_musicaActual == nombre && _musica?.state == PlayerState.playing) return;
    try {
      _ciclo ??= AppLifecycleListener(
        onHide: () => _musica?.pause(),
        onShow: () {
          if (_musicaActual != null && !_mudo) _musica?.resume();
        },
      );
      await _mezclar();
      final m = _musica ??= AudioPlayer();
      _musicaActual = nombre;
      await m.stop();
      await m.setReleaseMode(ReleaseMode.loop);
      await m.setVolume(volumen);
      await m.play(AssetSource('sonidos/$nombre.m4a'));
    } catch (_) {}
  }

  static Future<void> pararMusica() async {
    _musicaActual = null;
    try {
      await _musica?.stop();
    } catch (_) {}
  }
}
