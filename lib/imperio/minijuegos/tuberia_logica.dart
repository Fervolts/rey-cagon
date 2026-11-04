// Tubería Express, lógica pura (sin widgets): el mojón baja por un desagüe de dos carriles y cada toque lo pasa al otro
// carril. Los codos vienen subiendo; chocar con uno acaba la partida. La velocidad sube con el tiempo y los puntos son
// los metros recorridos. Todo en metros y segundos; el reloj lo mueve quien llama con [JuegoTuberia.avanzar].

import 'dart:math';

/// Un codo que tapa un carril a [distancia] metros desde la salida.
class Codo {
  final int carril;
  final double distancia;
  const Codo(this.carril, this.distancia);
}

class JuegoTuberia {
  JuegoTuberia({Random? azar}) : _azar = azar ?? Random() {
    _generarHasta(_distancia + horizonte);
  }

  /// Velocidad al arrancar y tope, en metros por segundo. Sube [aceleracion] cada segundo.
  static const double velocidadInicial = 4;
  static const double velocidadMaxima = 13;
  static const double aceleracion = 0.2;

  /// Lo que tarda el mojón en pasar de un carril al otro.
  static const double cambio = 0.14;

  /// Primer codo, y cuánto se genera por delante.
  static const double primerCodo = 18;
  static const double horizonte = 40;

  /// Mitad de la zona donde un codo pega, en metros. Un mojón con el carril a medio cambiar solo pega si está casi encima.
  static const double radioCodo = 0.55;

  final Random _azar;
  final List<Codo> _codos = [];
  double _distancia = 0;
  double _tiempo = 0;
  // Carril al que va (0 o 1) y dónde está ahora entre los dos (0..1).
  int _carril = 0;
  double _pos = 0;
  bool _vivo = true;
  int _toques = 0;
  double _siguienteGenerado = primerCodo;

  bool get vivo => _vivo;
  bool get terminado => !_vivo;

  /// Puntos: metros recorridos (enteros).
  int get puntos => _distancia.floor();
  double get distancia => _distancia;
  double get tiempo => _tiempo;
  int get toques => _toques;
  int get carril => _carril;

  /// Posición horizontal del mojón: 0 es el carril izquierdo, 1 el derecho.
  double get posicion => _pos;
  double get velocidad => min(velocidadMaxima, velocidadInicial + aceleracion * _tiempo);

  /// Codos de adelante y alrededor del mojón (para pintar y para chocar).
  List<Codo> get codos => List.unmodifiable(_codos);

  /// Un toque: pasa al otro carril. Después de terminar no hace nada.
  void toque() {
    if (!_vivo) return;
    _carril = 1 - _carril;
    _toques++;
  }

  void avanzar(double dt) {
    if (!_vivo || dt <= 0) return;
    // Pasos cortos para que un cuadro largo no atraviese un codo.
    var resto = dt;
    while (resto > 0 && _vivo) {
      final paso = min(resto, 0.016);
      resto -= paso;
      _paso(paso);
    }
  }

  void _paso(double dt) {
    _tiempo += dt;
    _distancia += velocidad * dt;
    final objetivo = _carril.toDouble();
    final mover = dt / cambio;
    if (_pos < objetivo) {
      _pos = min(objetivo, _pos + mover);
    } else if (_pos > objetivo) {
      _pos = max(objetivo, _pos - mover);
    }
    for (final c in _codos) {
      if ((c.distancia - _distancia).abs() <= radioCodo && (c.carril - _pos).abs() < 0.6) {
        _vivo = false;
        return;
      }
    }
    _codos.removeWhere((c) => c.distancia < _distancia - 3);
    _generarHasta(_distancia + horizonte);
  }

  void _generarHasta(double hasta) {
    while (_siguienteGenerado < hasta) {
      final v = min(velocidadMaxima, velocidadInicial + aceleracion * ((_siguienteGenerado) / 8));
      _codos.add(Codo(_azar.nextInt(2), _siguienteGenerado));
      // Hueco: tiempo de sobra para cambiar de carril (cambio + reacción) a la velocidad de ese tramo.
      _siguienteGenerado += max(5.0, v * (cambio + 0.45)) + _azar.nextDouble() * 5;
    }
  }
}
