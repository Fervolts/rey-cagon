// Memoria del rollo, lógica pura: parejas de cartas con emojis de la app. Una partida son tres niveles seguidos
// (4x3, 4x4 y 5x4). Cada nivel da puntos por pareja, más un bonus si va rápido, menos por cada error.

import 'dart:math';

/// Emojis de las cartas. Todos tienen su PNG en assets/emoji (lo comprueba un test), así se ven igual en todos los teléfonos.
const List<String> emojisMemoria = ['🧻', '💩', '🚽', '🪠', '🪳', '🚿', '🫧', '🔥', '🍑', '👑', '🐸', '🦆', '🏆', '💎', '🪣', '🧴'];

class NivelMemoria {
  final int columnas, filas;
  const NivelMemoria(this.columnas, this.filas);
  int get cartas => columnas * filas;
  int get pares => cartas ~/ 2;
}

const List<NivelMemoria> nivelesMemoria = [NivelMemoria(4, 3), NivelMemoria(4, 4), NivelMemoria(5, 4)];

const int puntosPorPareja = 100;
const int bonusPorPareja = 50;
const int penalPorError = 25;

/// Segundos por pareja con los que el bonus de rapidez llega a cero.
const double segundosPorPareja = 4;

/// Puntos de un nivel: 100 por pareja, hasta 50 más por rapidez y 25 menos por error. Nunca baja de 0.
int puntajeNivel({required int pares, required double segundos, required int errores}) {
  final limite = pares * segundosPorPareja;
  final rapidez = (1 - segundos / limite).clamp(0.0, 1.0);
  final p = pares * puntosPorPareja + (pares * bonusPorPareja * rapidez).round() - errores * penalPorError;
  return max(0, p);
}

enum EstadoCarta { oculta, visible, hecha }

class Carta {
  final String emoji;
  EstadoCarta estado = EstadoCarta.oculta;
  Carta(this.emoji);
}

/// Un nivel suelto.
class JuegoMemoria {
  JuegoMemoria(this.nivel, {Random? azar}) {
    final r = azar ?? Random();
    final elegidos = [...emojisMemoria]..shuffle(r);
    final mazo = [for (final e in elegidos.take(nivel.pares)) ...[e, e]]..shuffle(r);
    cartas = [for (final e in mazo) Carta(e)];
  }

  final NivelMemoria nivel;
  late final List<Carta> cartas;

  /// Tiempo que se tarda en voltear la pareja equivocada de nuevo.
  static const double esperaFallo = 0.8;

  final List<int> _abiertas = [];
  double _espera = 0;
  double _segundos = 0;
  bool _empezo = false;
  int _errores = 0;
  int _parejas = 0;

  int get errores => _errores;
  int get parejas => _parejas;
  double get segundos => _segundos;
  bool get terminado => _parejas == nivel.pares;
  int get puntos => puntajeNivel(pares: nivel.pares, segundos: _segundos, errores: _errores);

  /// Hay dos cartas equivocadas a la vista: no se toca hasta que se voltean.
  bool get bloqueado => _espera > 0;

  /// Voltea la carta [i]. Devuelve false si no se pudo (ya a la vista, hecha, bloqueado o fuera de rango).
  bool toca(int i) {
    if (i < 0 || i >= cartas.length || bloqueado || terminado) return false;
    final c = cartas[i];
    if (c.estado != EstadoCarta.oculta) return false;
    _empezo = true;
    c.estado = EstadoCarta.visible;
    _abiertas.add(i);
    if (_abiertas.length == 2) {
      final a = cartas[_abiertas[0]], b = cartas[_abiertas[1]];
      if (a.emoji == b.emoji) {
        a.estado = b.estado = EstadoCarta.hecha;
        _parejas++;
        _abiertas.clear();
      } else {
        _errores++;
        _espera = esperaFallo;
      }
    }
    return true;
  }

  void avanzar(double dt) {
    if (dt <= 0 || terminado) return;
    if (_empezo) _segundos += dt;
    if (_espera > 0) {
      _espera -= dt;
      if (_espera <= 0) {
        _espera = 0;
        for (final i in _abiertas) {
          cartas[i].estado = EstadoCarta.oculta;
        }
        _abiertas.clear();
      }
    }
  }
}

/// Los tres niveles seguidos.
class PartidaMemoria {
  // ignore: prefer_initializing_formals
  PartidaMemoria({Random? azar}) : _azar = azar {
    juego = JuegoMemoria(nivelesMemoria[0], azar: _azar);
  }

  final Random? _azar;
  late JuegoMemoria juego;
  int _nivel = 0;
  int _acumulado = 0;
  int _erroresTotal = 0;

  int get nivel => _nivel;
  int get erroresTotal => _erroresTotal + juego.errores;

  /// Puntos de los niveles ya cerrados más el actual si ya acabó.
  int get puntos => _acumulado + (juego.terminado ? juego.puntos : 0);
  bool get nivelTerminado => juego.terminado;
  bool get terminada => _nivel == nivelesMemoria.length - 1 && juego.terminado;

  /// Cierra el nivel que acabó y arma el siguiente. No hace nada si no ha acabado o ya era el último.
  bool siguiente() {
    if (!juego.terminado || terminada) return false;
    _acumulado += juego.puntos;
    _erroresTotal += juego.errores;
    _nivel++;
    juego = JuegoMemoria(nivelesMemoria[_nivel], azar: _azar);
    return true;
  }
}
