// Destapa, lógica pura: un pulso marca el compás y hay que tocar justo encima. Perfecto y bueno avanzan el destape del
// inodoro; tocar fuera de tiempo, de más o dejar pasar el pulso es un fallo. Con [fallosMaximos] fallos se acaba.
// Cada inodoro está más tapado (pide más) y el compás se acelera un poco. El reloj lo mueve [avanzar].

import 'dart:math';

enum Golpe { perfecto, bueno, fallo }

class JuegoDestapa {
  JuegoDestapa();

  static const int fallosMaximos = 3;

  /// Ventanas de acierto, en segundos desde el pulso.
  static const double ventanaPerfecta = 0.07;
  static const double ventanaBuena = 0.16;

  /// Primer pulso (da tiempo a ver el compás) y compás inicial y mínimo, en segundos.
  static const double entrada = 1.4;
  static const double compasInicial = 0.72;
  static const double compasMinimo = 0.46;
  static const double compasMenosPorInodoro = 0.03;

  static const int puntosPerfecto = 3;
  static const int puntosBueno = 1;
  static const int puntosInodoro = 3;

  double _tiempo = 0;
  double _pulso = entrada;
  // Si el pulso actual ya se resolvió (tocaron o se dejó pasar).
  bool _resuelto = false;
  int _puntos = 0;
  int _fallos = 0;
  int _inodoro = 0;
  int _avance = 0;
  int _perfectos = 0;
  int _buenos = 0;
  int _racha = 0;
  int _mejorRacha = 0;
  Golpe? _ultimo;

  int get puntos => _puntos;
  int get fallos => _fallos;
  bool get terminado => _fallos >= fallosMaximos;
  double get tiempo => _tiempo;

  /// Inodoros destapados.
  int get inodoros => _inodoro;
  int get perfectos => _perfectos;
  int get buenos => _buenos;
  int get mejorRacha => _mejorRacha;

  /// Último resultado, para el destello. Se queda hasta el siguiente.
  Golpe? get ultimo => _ultimo;

  /// Unidades de destape que pide el inodoro actual: cada uno está más tapado que el anterior.
  int get requiere => 3 + 2 * _inodoro;
  int get avance => _avance;

  /// Compás actual en segundos.
  double get compas => max(compasMinimo, compasInicial - compasMenosPorInodoro * _inodoro);

  /// Segundos que faltan para el pulso que viene.
  double get paraPulso => _pulso - _tiempo;

  /// 0 recién pasado el pulso, 1 justo en el pulso: para dibujar el anillo que se cierra.
  double get fase => (1 - (paraPulso / compas)).clamp(0.0, 1.0);

  void avanzar(double dt) {
    if (terminado || dt <= 0) return;
    _tiempo += dt;
    // Un pulso que nadie tocó y ya pasó la ventana buena es un fallo; se pasa al siguiente.
    while (!terminado && _tiempo - _pulso > ventanaBuena) {
      if (!_resuelto) _fallar();
      _pulso += compas;
      _resuelto = false;
    }
  }

  /// Un toque. Devuelve cómo salió.
  Golpe toque() {
    if (terminado) return Golpe.fallo;
    final d = (_tiempo - _pulso).abs();
    // Toque suelto entre pulsos, o un segundo toque sobre el mismo pulso: fallo.
    if (d > ventanaBuena || _resuelto) {
      _fallar();
      return Golpe.fallo;
    }
    _resuelto = true;
    final g = d <= ventanaPerfecta ? Golpe.perfecto : Golpe.bueno;
    _ultimo = g;
    _racha++;
    _mejorRacha = max(_mejorRacha, _racha);
    if (g == Golpe.perfecto) {
      _perfectos++;
      _puntos += puntosPerfecto;
      _avance += 2;
    } else {
      _buenos++;
      _puntos += puntosBueno;
      _avance += 1;
    }
    if (_avance >= requiere) {
      _inodoro++;
      _avance = 0;
      _puntos += puntosInodoro;
    }
    return g;
  }

  void _fallar() {
    _fallos++;
    _racha = 0;
    _ultimo = Golpe.fallo;
  }
}
