// Tubería Express, lógica pura (sin widgets): el mojón baja por un desagüe de dos carriles y cada toque lo pasa al otro
// carril. Vienen subiendo codos (chocar acaba la partida) y rollos de papel (agarrarlos seguidos sube el multiplicador).
// Pasar rozando un codo es un CASI y también suma. El desagüe va por tramos: normal, zigzag de codos, serpentina de rollos
// y DESCARGA (alguien jaló la cadena: más rápido y con rollos dorados). Todo en metros y segundos; la velocidad depende
// de los metros recorridos para que el generador sepa cuánto hueco dejar. Al llegar a la planta ([meta]) se gana.
// Los puntos son metros más los bonos, con un techo de [ppsSeguro] por segundo para no pasar nunca el anti-trampa del
// servidor (16 por segundo y 16000 por partida). El reloj lo mueve quien llama con [JuegoTuberia.avanzar].

import 'dart:math';

/// Un codo que tapa un carril a [distancia] metros desde la salida.
class Codo {
  Codo(this.carril, this.distancia);
  final int carril;
  final double distancia;

  /// Lo más cerca (de 0 a 1, en carriles) que pasó el mojón mientras lo tenía al lado. Menos de [JuegoTuberia.casiRoce] = CASI.
  double roce = 1;
  bool pasado = false;
}

/// Un rollo de papel en un carril. Los dorados (de las descargas) valen el doble.
class Rollo {
  Rollo(this.carril, this.distancia, {this.dorado = false});
  final int carril;
  final double distancia;
  final bool dorado;
  bool agarrado = false;
  bool resuelto = false;
}

enum TipoSuceso { rollo, casi, multiplicador, perdido, avisoDescarga, descarga, finDescarga, zona, record, choque, meta }

/// Algo que pasó en el último [JuegoTuberia.avanzar], para que la vista lo celebre (partículas, letreros, vibración).
class SucesoTuberia {
  const SucesoTuberia(this.tipo, {this.carril = 0, this.puntos = 0, this.valor = 0});
  final TipoSuceso tipo;
  final int carril, puntos, valor;
}

/// Lo que la vista enseña al empezar: tocar, esquivar y la racha de rollos.
enum PistaTuberia { toca, esquiva, racha }

enum _Tramo { normal, zigzag, rollos, descarga }

class _Zona {
  const _Zona(this.desde, this.hasta);
  final double desde, hasta;
  bool tiene(double d) => d >= desde && d < hasta;
}

class JuegoTuberia {
  JuegoTuberia({Random? azar, this.record = 0}) : _azar = azar ?? Random() {
    _intro();
    _generarHasta(horizonte);
  }

  /// Velocidad al arrancar, a los 300 m y de crucero (desde 1800 m), en m/s. La descarga empuja [empujeDescarga] veces.
  static const double velocidadInicial = 5;
  static const double velocidadTramo1 = 9.5;
  static const double velocidadCrucero = 10;
  static const double empujeDescarga = 1.25;
  static const double velocidadMaxima = velocidadCrucero * empujeDescarga;

  /// Lo que tarda el mojón en pasar de un carril al otro.
  static const double cambio = 0.14;

  /// Mitad de la zona donde un codo pega y donde se agarra un rollo, en metros.
  static const double radioCodo = 0.55;
  static const double radioRollo = 0.7;

  /// Un codo cuenta como CASI si el mojón seguía a menos de esto (en carriles) de su carril teniéndolo a [casiMetros] o menos.
  static const double casiRoce = 0.9;
  static const double casiMetros = 2.0;

  /// La planta de tratamiento: llegar ahí gana la partida.
  static const double meta = 4000;

  /// Dónde empieza cada zona (para el letrero y el color del tubo).
  static const List<double> zonas = [0, 300, 1000, 2000, 3000];

  /// Cuánto se genera por delante.
  static const double horizonte = 45;

  /// Techo de puntos por segundo de juego (el servidor rechaza más de 16 por segundo).
  static const double ppsSeguro = 14;

  static const int puntosRollo = 1;
  static const int puntosCasi = 2;
  static const int multiplicadorMaximo = 4;

  /// Rollos seguidos para subir un punto de multiplicador.
  static const int rachaPorNivel = 5;

  /// Récord de quien juega (para avisar al pasarlo). 0 = sin récord.
  final int record;

  final Random _azar;
  final List<Codo> _codos = [];
  final List<Rollo> _rollos = [];
  final List<_Zona> _descargas = [];
  List<SucesoTuberia> _sucesos = [];
  double _distancia = 0;
  double _tiempo = 0;
  // Carril al que va (0 o 1) y dónde está ahora entre los dos (0..1).
  int _carril = 0;
  double _pos = 0;
  bool _vivo = true;
  bool _llego = false;
  int _toques = 0;
  int _bonus = 0;
  int _racha = 0;
  int _rachaMaxima = 0;
  int _rollosAgarrados = 0;
  int _casis = 0;
  int _codosPasados = 0;
  int _zona = 0;
  bool _enDescarga = false;
  double _avisada = -1;
  bool _recordAvisado = false;

  bool get vivo => _vivo;
  bool get terminado => !_vivo;

  /// Llegó a la planta (ganó) en vez de chocar.
  bool get llego => _llego;

  /// Puntos: metros recorridos más bonos, con el techo de [ppsSeguro] por segundo.
  int get puntos => min(_distancia.floor() + _bonus, (ppsSeguro * (_tiempo + 1)).floor());
  double get distancia => _distancia;
  double get tiempo => _tiempo;
  int get toques => _toques;
  int get carril => _carril;
  int get racha => _racha;
  int get rachaMaxima => _rachaMaxima;
  int get rollosAgarrados => _rollosAgarrados;
  int get casis => _casis;
  int get zona => _zona;
  bool get enDescarga => _enDescarga;
  int get multiplicador => min(multiplicadorMaximo, 1 + _racha ~/ rachaPorNivel);

  /// Cuántos rollos faltan para el siguiente multiplicador (0 si ya está al máximo).
  int get faltanParaSubir => multiplicador >= multiplicadorMaximo ? 0 : rachaPorNivel - _racha % rachaPorNivel;

  /// Posición horizontal del mojón: 0 es el carril izquierdo, 1 el derecho.
  double get posicion => _pos;
  double get velocidad => _velEn(_distancia);

  /// De 0 (salida) a 1 (desde 2500 m): cuánto se aprieta el desagüe.
  static double dureza(double d) => min(1, d / 2500);

  /// Velocidad sin descarga a [d] metros.
  static double velocidadBase(double d) {
    if (d < 300) return velocidadInicial + (velocidadTramo1 - velocidadInicial) * d / 300;
    return min(velocidadCrucero, velocidadTramo1 + (velocidadCrucero - velocidadTramo1) * (d - 300) / 1500);
  }

  double _velEn(double d) => min(velocidadMaxima, velocidadBase(d) * (_descargas.any((z) => z.tiene(d)) ? empujeDescarga : 1));

  /// Metros hasta la próxima descarga (null si no hay una generada por delante).
  double? get descargaEn {
    for (final z in _descargas) {
      if (z.desde > _distancia) return z.desde - _distancia;
    }
    return null;
  }

  /// Codos y rollos de adelante y alrededor del mojón (para pintar y para chocar).
  List<Codo> get codos => List.unmodifiable(_codos);
  List<Rollo> get rollos => List.unmodifiable(_rollos);

  PistaTuberia? get pista {
    if (!_vivo) return null;
    if (_toques == 0) return PistaTuberia.toca;
    if (_codosPasados == 0 && _codos.any((c) => !c.pasado && c.carril == _carril && c.distancia - _distancia < 14)) return PistaTuberia.esquiva;
    if (_rollosAgarrados > 0 && _rollosAgarrados < 4 && _distancia < 110) return PistaTuberia.racha;
    return null;
  }

  /// Lo que pasó desde la última vez que se preguntó.
  List<SucesoTuberia> tomarSucesos() {
    if (_sucesos.isEmpty) return const [];
    final s = _sucesos;
    _sucesos = [];
    return s;
  }

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
    if (_distancia >= meta) {
      _distancia = meta;
      _vivo = false;
      _llego = true;
      _sucesos.add(const SucesoTuberia(TipoSuceso.meta));
      return; // sonido: llegada a la planta (fanfarria corta)
    }
    while (_zona + 1 < zonas.length && _distancia >= zonas[_zona + 1]) {
      _zona++;
      _sucesos.add(SucesoTuberia(TipoSuceso.zona, valor: _zona));
    }
    _descargaAlDia();
    for (final c in _codos) {
      final dd = c.distancia - _distancia;
      if (dd.abs() <= radioCodo && (c.carril - _pos).abs() < 0.6) {
        _vivo = false;
        _sucesos.add(SucesoTuberia(TipoSuceso.choque, carril: c.carril));
        return; // sonido: choque (splash grave)
      }
      if (c.pasado) continue;
      // Solo cuenta acercándose: salir del carril tarde es CASI; volver a él después del codo, no.
      if (dd > radioCodo && dd <= casiMetros) c.roce = min(c.roce, (c.carril - _pos).abs());
      if (dd < -radioCodo) {
        c.pasado = true;
        _codosPasados++;
        if (c.roce < casiRoce) _casi(c);
      }
    }
    for (final r in _rollos) {
      if (r.resuelto) continue;
      final dd = r.distancia - _distancia;
      if (dd.abs() <= radioRollo && (r.carril - _pos).abs() < 0.5) {
        _agarrar(r);
      } else if (dd < -radioRollo) {
        r.resuelto = true;
        if (_racha > 0) _sucesos.add(SucesoTuberia(TipoSuceso.perdido, carril: r.carril, valor: _racha));
        _racha = 0; // sonido: racha rota (pedo desinflado)
      }
    }
    if (!_recordAvisado && record > 0 && puntos > record) {
      _recordAvisado = true;
      _sucesos.add(const SucesoTuberia(TipoSuceso.record));
    }
    _codos.removeWhere((c) => c.distancia < _distancia - 4);
    _rollos.removeWhere((r) => r.resuelto && r.distancia < _distancia - 4);
    _descargas.removeWhere((z) => z.hasta < _distancia - 50);
    _generarHasta(_distancia + horizonte);
  }

  void _descargaAlDia() {
    final en = _descargas.any((z) => z.tiene(_distancia));
    if (en != _enDescarga) {
      _enDescarga = en;
      _sucesos.add(SucesoTuberia(en ? TipoSuceso.descarga : TipoSuceso.finDescarga));
    }
    final prox = descargaEn;
    if (prox != null && prox < 55 && _avisada < _distancia + prox - 1) {
      _avisada = _distancia + prox;
      _sucesos.add(const SucesoTuberia(TipoSuceso.avisoDescarga));
    }
  }

  void _sumar(int n) => _bonus += n;

  void _casi(Codo c) {
    _casis++;
    final antes = multiplicador;
    _racha++;
    _rachaMaxima = max(_rachaMaxima, _racha);
    final pts = puntosCasi * multiplicador;
    _sumar(pts);
    _sucesos.add(SucesoTuberia(TipoSuceso.casi, carril: c.carril, puntos: pts));
    if (multiplicador > antes) _sucesos.add(SucesoTuberia(TipoSuceso.multiplicador, valor: multiplicador));
  }

  void _agarrar(Rollo r) {
    r.agarrado = r.resuelto = true;
    _rollosAgarrados++;
    final antes = multiplicador;
    _racha++;
    _rachaMaxima = max(_rachaMaxima, _racha);
    final pts = puntosRollo * (r.dorado ? 2 : 1) * multiplicador;
    _sumar(pts);
    _sucesos.add(SucesoTuberia(TipoSuceso.rollo, carril: r.carril, puntos: pts, valor: r.dorado ? 1 : 0));
    // sonido: rollo (plop que sube de tono con la racha)
    if (multiplicador > antes) _sucesos.add(SucesoTuberia(TipoSuceso.multiplicador, valor: multiplicador));
  }

  // ---------------------------------------------------------------- generador
  // Cada cosa pide estar en un carril a cierta distancia (codo: el otro carril; rollo: el suyo). Entre dos pedidos de
  // carril distinto se deja tiempo de cambio + reacción a la velocidad de ese tramo, así siempre se puede pasar.

  double _gen = 0;
  double _ultD = 0;
  int _ultNecesita = 0;
  int _ultCodo = -1;
  _Tramo _tramo = _Tramo.normal;
  double _finTramo = 0;
  int _quedan = 0;
  int _serieCarril = 0;
  double _finDescarga = 0;

  void _intro() {
    // Enseña jugando: dos rollos del otro lado (toca), un codo en ese carril (esquiva) y la racha.
    _rollo(1, 12);
    _rollo(1, 15);
    _codo(1, 26);
    _rollo(0, 30);
    _rollo(0, 33);
    _codo(0, 42);
    _rollo(1, 46);
    _rollo(1, 49);
    _finTramo = 110;
  }

  void _codo(int carril, double d) {
    _codos.add(Codo(carril, d));
    _ultD = _gen = d;
    _ultNecesita = 1 - carril;
    _ultCodo = carril;
  }

  void _rollo(int carril, double d, {bool dorado = false}) {
    _rollos.add(Rollo(carril, d, dorado: dorado));
    _ultD = _gen = d;
    _ultNecesita = carril;
    _ultCodo = -1;
  }

  /// Metros desde el último pedido hasta uno nuevo que pide [carril].
  double _hueco(int carril, {double extra = 0, double apriete = 1}) {
    if (carril == _ultNecesita) return 2.6 + extra;
    final h = dureza(_ultD);
    final margen = (0.85 - 0.5 * h) * apriete;
    return _velEn(_ultD) * (cambio + margen) + radioCodo + radioRollo + extra;
  }

  void _generarHasta(double hasta) {
    while (_gen < hasta && _gen < meta - 20) {
      if (_gen >= _finTramo && _quedan <= 0) _nuevoTramo();
      switch (_tramo) {
        case _Tramo.normal:
          _normal();
        case _Tramo.zigzag:
          final c = _ultNecesita;
          _codo(c, _ultD + _hueco(1 - c, apriete: 0.8));
          if (--_quedan == 0) _rollo(_ultNecesita, _ultD + 2.6);
        case _Tramo.rollos:
          if (_quedan % 3 == 0) _serieCarril = 1 - _serieCarril;
          _rollo(_serieCarril, _ultD + _hueco(_serieCarril, extra: 0.4));
          _quedan--;
        case _Tramo.descarga:
          if (_azar.nextBool()) {
            final c = _azar.nextInt(2);
            _codo(c, _ultD + _hueco(1 - c, extra: 2 + _azar.nextDouble() * 3));
          } else {
            final c = _azar.nextInt(2);
            _rollo(c, _ultD + _hueco(c, extra: 1), dorado: true);
          }
          if (_gen >= _finDescarga) _quedan = 0;
      }
    }
  }

  void _normal() {
    final h = dureza(_ultD);
    if (_azar.nextDouble() < 0.3) {
      // Rollo; a veces justo detrás del codo, en su carril: agarrarlo pide un CASI.
      final trampa = _ultCodo >= 0 && _azar.nextDouble() < 0.45;
      final c = trampa ? _ultCodo : _azar.nextInt(2);
      _rollo(c, _ultD + _hueco(c, extra: trampa ? 0.2 : _azar.nextDouble() * 3));
    } else {
      final c = _azar.nextInt(2);
      _codo(c, _ultD + _hueco(1 - c, extra: 1.5 + _azar.nextDouble() * (6 - 3.5 * h)));
    }
  }

  void _nuevoTramo() {
    final h = dureza(_gen);
    final r = _azar.nextDouble();
    if (h > 0.15 && _gen - _finDescarga > 650 - 250 * h) {
      // Descarga: arranca 25 m más allá (para avisar) y dura 150 m.
      final desde = _gen + 25;
      _descargas.add(_Zona(desde, desde + 150));
      _finDescarga = desde + 150;
      _tramo = _Tramo.descarga;
      _quedan = 1;
      _ultD = _gen = desde - 6;
      _finTramo = _finDescarga;
    } else if (h > 0.06 && r < 0.4) {
      _tramo = _Tramo.zigzag;
      _quedan = 4 + _azar.nextInt(2 + (4 * h).round());
      _finTramo = _gen;
    } else if (r < 0.62) {
      _tramo = _Tramo.rollos;
      _quedan = 5 + _azar.nextInt(4);
      _serieCarril = _ultNecesita;
      _finTramo = _gen;
    } else {
      _tramo = _Tramo.normal;
      _quedan = 0;
      _finTramo = _gen + 50 + _azar.nextDouble() * 40 - 20 * h;
    }
  }
}
