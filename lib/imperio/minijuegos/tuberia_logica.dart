// Tubería Express: surf de una mano por la cloaca. Lógica pura (sin Flutter), se prueba con dt fijo.
//
// Vista lateral. El mojón se desliza a la derecha por una ladera de lodo con lomas y valles (nudos alternos pico/valle
// unidos con coseno, como una ola). Un solo control: mantener el dedo = pesado (más gravedad, se pega a la ladera);
// soltar = liviano. Bajar pesado acelera; soltar en el fondo del valle deja subir liviano y la cresta lo lanza al aire
// (despega cuando la curva de la loma se le escapa más rápido que la gravedad). Aterrizar alineado con una bajada es
// limpio (+velocidad, sube el combo); aterrizar contra la parte baja de una subida es un plaf (pierde velocidad, combo a
// cero). Arriba de la loma (desde [alturaSuave] de la subida) se cae suave: conserva casi toda la velocidad. Cada
// [cadaRampa] m hay una rampa que lanza alto, con una fila de rollos en el vuelo, y su aterrizaje nunca es plaf.
// Detrás viene el Atasco, una pared de lodo que acelera por tramos. Si te alcanza, fin.
//
// Puntos = metros + bonus. El servidor exige puntos <= (segundos + 1) * 16: la velocidad máxima es 12.8 m/s y además
// los puntos se recortan a un techo por tiempo (con margen), así que el contrato se cumple por construcción.

import 'dart:math';

enum TipoSuceso {
  despegue,
  limpio,
  aterrizaje,
  plaf,
  combo,
  rollo,
  dorado,
  fiebre,
  finFiebre,
  aplasta,
  choqueCucaracha,
  zona,
  rampa,
  atascoCerca,
  atascoAcelera,
  record,
  atrapado,
}

/// Algo que pasó en el último paso. [x], [y] en metros del mundo; [fuerza] de 0 a ~1.
class SucesoTuberia {
  const SucesoTuberia(this.tipo, {this.x = 0, this.y = 0, this.puntos = 0, this.valor = 0, this.fuerza = 0});
  final TipoSuceso tipo;
  final double x, y, fuerza;
  final int puntos, valor;
}

class RolloTuberia {
  RolloTuberia(this.x, this.y, this.arco);
  final double x, y;
  final int arco;
  bool dorado = false;
  bool agarrado = false;
}

class CucarachaTuberia {
  CucarachaTuberia(this.x, this.fase);
  double x;
  final double fase;
  bool viva = true;

  /// Si murió: true = aplastada (pesado), false = pateada (liviano).
  bool aplastada = false;
  double muerte = 0;
}

class RampaTuberia {
  RampaTuberia(this.x);

  /// Donde termina el labio (lanza desde [x] - [JuegoTuberia.largoRampa]).
  final double x;
  bool usada = false, decorada = false;
}

class _Nudo {
  const _Nudo(this.x, this.y, this.pico);
  final double x, y;
  final bool pico;
}

class JuegoTuberia {
  JuegoTuberia({Random? azar, int? semilla, this.record = 0, double separacion = separacionInicial})
      : _azar = azar ?? Random(semilla ?? DateTime.now().microsecondsSinceEpoch),
        _xa = -separacion {
    _nudos.add(const _Nudo(-120, 1.2, true));
    _nudos.add(const _Nudo(0, 1.2, true));
    _generarHasta(_x + adelante);
  }

  // Contrato del servidor.
  static const pps = 16;
  static const tope = 16000;
  static const _margen = 0.97;

  // Física (metros, segundos).
  static const gravedad = 7.0;
  static const factorPesado = 3.2;
  static const velocidadMaxima = 12.8;
  static const velocidadMinima = 2.6;
  static const velocidadInicial = 5.0;
  static const _rozSuelo = 0.25;
  static const _arrastreSuelo = 0.004;
  static const _arrastreAire = 0.004;
  static const _subPaso = 1 / 240;

  // Aterrizajes.
  static const anguloLimpio = 0.40; // rad entre la velocidad y la ladera
  static const anguloPlaf = 0.80;
  static const _aireMinimoLimpio = 0.30;

  /// Fracción de la subida desde la que caer ya no es plaf (0 = fondo del valle, 1 = la cresta).
  static const alturaSuave = 0.45;

  // Rampas.
  static const cadaRampa = 200.0;
  static const largoRampa = 2.4;
  static const velocidadRampa = 11.5;
  static const anguloRampa = 0.62;

  // Atasco.
  static const separacionInicial = 26.0;
  static const separacionMaxima = 38.0;
  static const tramoAtasco = 50.0; // s entre acelerones
  static const metrosZona = 400.0;
  static const zonas = 5;
  static const comboMaximo = 10;
  static const duracionFiebre = 5.0;
  static const cadaDorado = 25.0;
  static const adelante = 120.0;
  static const tiempoMaximo = 1150.0; // s; el servidor acepta hasta 1200

  /// Metros desde donde los rollos van en arco (antes, en el piso) y desde donde hay arcos altos.
  static const desdeArcos = 140.0, desdeArcosAltos = 300.0;

  // Radios de choque.
  static const radioRollo = 1.15;
  static const centroMojon = 0.55;
  static const radioCucaracha = 0.75;

  final Random _azar;
  final int record;
  final _nudos = <_Nudo>[];
  final rollos = <RolloTuberia>[];
  final cucarachas = <CucarachaTuberia>[];
  final rampas = <RampaTuberia>[];
  final _sucesos = <SucesoTuberia>[];

  double _x = 0, _y = 1.2, _vx = velocidadInicial, _vy = 0, _s = velocidadInicial;
  bool _suelo = true;
  double _xa;
  double _t = 0;
  double _aire = 0; // segundos en el aire del vuelo actual
  double _alturaMax = 0; // del vuelo actual, sobre el suelo
  double _sinLimpio = 0;
  int _combo = 0;
  int _bonus = 0;
  double _fiebre = 0;
  double _proxDorado = cadaDorado;
  RolloTuberia? _doradoPuesto;
  int _zona = 0;
  int _tramo = 0;
  int _arcos = 0;
  bool _cerca = false;
  bool _recordAvisado = false;
  bool _terminado = false;
  bool _pesado = false;
  bool _deRampa = false; // el vuelo actual salió de una rampa: no hay plaf al caer
  double _proxRampa = cadaRampa;
  int _limpios = 0, _plafs = 0, _rollosAgarrados = 0, _aplastadas = 0;

  // ---------------------------------------------------------------- lo que se lee desde fuera

  double get x => _x;
  double get y => _y;
  double get vx => _suelo ? _s * _cos(_x) : _vx;
  double get vy => _suelo ? _s * _sin(_x) : _vy;
  double get velocidad => _suelo ? _s : sqrt(_vx * _vx + _vy * _vy);
  bool get enSuelo => _suelo;
  bool get pesado => _pesado;
  double get tiempo => _t;
  double get distancia => max(0, _x);
  double get aire => _aire;
  double get alturaSobreSuelo => _y - altura(_x);
  int get combo => _combo;
  int get bonus => _bonus;
  double get fiebre => _fiebre;
  bool get enFiebre => _fiebre > 0;
  double get atascoX => _xa;
  double get separacion => _x - _xa;
  double get velocidadAtasco => velocidadAtascoEn(_t);
  int get zona => _zona;
  int get tramo => _tramo;
  bool get terminado => _terminado;
  bool get vivo => !_terminado;
  int get limpios => _limpios;
  int get plafs => _plafs;
  bool get vueloDeRampa => _deRampa && !_suelo;
  int get rollosAgarrados => _rollosAgarrados;
  int get aplastadas => _aplastadas;

  /// Ángulo del mojón: la ladera en el suelo, la dirección del vuelo en el aire.
  double get angulo => _suelo ? atan(pendiente(_x)) : atan2(_vy, max(0.1, _vx));

  /// Metros + bonus, con el techo del servidor por tiempo y el tope.
  int get puntos {
    final crudo = max(0, _x).floor() + _bonus;
    final techo = ((_t + 1) * pps * _margen).floor();
    return min(min(crudo, techo), tope);
  }

  /// Zona de un punto del mundo (sin el módulo: la 5 vuelve a verse como la 0).
  static int zonaEn(double x) => max(0, (x / metrosZona).floor());

  /// El Atasco: arranca suave y acelera un poco más cada [tramoAtasco] s.
  static double velocidadAtascoEn(double t) {
    final n = (t / tramoAtasco).floor();
    return 3.4 + 3.8 * (1 - exp(-t / 25)) + 0.005 * t + 0.2 * n;
  }

  List<SucesoTuberia> tomarSucesos() {
    if (_sucesos.isEmpty) return const [];
    final l = List<SucesoTuberia>.of(_sucesos);
    _sucesos.clear();
    return l;
  }

  /// Corta la partida desde afuera (la vista lo usa si el reloj real llega al tope). Suceso atrapado con valor 1.
  void cortar() {
    if (_terminado) return;
    _terminado = true;
    _sucesos.add(SucesoTuberia(TipoSuceso.atrapado, x: _x, y: _y, valor: 1));
  }

  void apretar() => _pesado = true;
  void soltar() => _pesado = false;
  set presionado(bool v) => _pesado = v;

  // ---------------------------------------------------------------- terreno

  int _segmento(double x) {
    var lo = 0, hi = _nudos.length - 2;
    if (x <= _nudos[0].x) return 0;
    while (lo < hi) {
      final m = (lo + hi + 1) >> 1;
      if (_nudos[m].x <= x) {
        lo = m;
      } else {
        hi = m - 1;
      }
    }
    return lo;
  }

  void _asegurar(double x) {
    if (x > _nudos.last.x - 1) _generarHasta(x + 40);
  }

  /// Altura del lodo en [x] (metros, arriba positivo).
  double altura(double x) {
    _asegurar(x);
    if (x <= _nudos.first.x) return _nudos.first.y;
    final i = _segmento(x);
    final a = _nudos[i], b = _nudos[i + 1];
    final t = ((x - a.x) / (b.x - a.x)).clamp(0.0, 1.0);
    return a.y + (b.y - a.y) * (1 - cos(pi * t)) / 2;
  }

  /// dy/dx del lodo en [x].
  double pendiente(double x) {
    _asegurar(x);
    if (x <= _nudos.first.x) return 0;
    final i = _segmento(x);
    final a = _nudos[i], b = _nudos[i + 1];
    final dx = b.x - a.x;
    final t = ((x - a.x) / dx).clamp(0.0, 1.0);
    return (b.y - a.y) * pi / 2 * sin(pi * t) / dx;
  }

  double _segunda(double x) {
    if (x <= _nudos.first.x) return 0;
    final i = _segmento(x);
    final a = _nudos[i], b = _nudos[i + 1];
    final dx = b.x - a.x;
    final t = ((x - a.x) / dx).clamp(0.0, 1.0);
    return (b.y - a.y) * pi * pi / 2 * cos(pi * t) / (dx * dx);
  }

  double _cos(double x) {
    final d = pendiente(x);
    return 1 / sqrt(1 + d * d);
  }

  double _sin(double x) {
    final d = pendiente(x);
    return d / sqrt(1 + d * d);
  }

  /// Picos (true) y valles por delante de [desde] hasta [hasta]; para la vista y los bots.
  Iterable<(double, double, bool)> nudosEntre(double desde, double hasta) sync* {
    _asegurar(hasta);
    for (final n in _nudos) {
      if (n.x >= desde && n.x <= hasta) yield (n.x, n.y, n.pico);
    }
  }

  double _entre(double a, double b) => a + (b - a) * _azar.nextDouble();

  void _generarHasta(double hasta) {
    while (_nudos.last.x < hasta) {
      final ult = _nudos.last;
      final z = zonaEn(ult.x) % zonas;
      final d = (ult.x / 2600).clamp(0.0, 1.0);
      final (dx0, dx1, a0, a1) = switch (z) {
        0 => (7.5, 9.5, 1.1, 1.6), // baño: lomas largas y bajitas
        1 => (6.0, 7.5, 1.2, 1.9), // desagüe: cortas
        2 => (6.5, 8.5, 1.6, 2.4), // cloaca: altas
        3 => (8.5, 11.0, 2.0, 2.8), // río: olas grandes
        _ => (5.5, 10.0, 1.4, 2.8), // planta: de todo
      };
      // Al empezar todo es más suave (los primeros ~150 m son para aprender).
      final suave = (0.55 + ult.x / 330).clamp(0.55, 1.0);
      final dx = _entre(dx0, dx1) * (1 - 0.15 * d);
      final a = _entre(a0, a1) * (1 + 0.5 * d) * suave;
      final pico = !ult.pico;
      // Tope de inclinación: el desnivel no pasa de ~0.45 del ancho (unos 35°).
      final yy = pico ? a : -a * _entre(0.75, 1.0);
      final y = ult.y + (yy - ult.y).clamp(-0.45 * dx, 0.45 * dx);
      final n = _Nudo(ult.x + dx, y, pico);
      _nudos.add(n);
      // Rampa en el fondo del primer valle pasada cada marca (se llega bajando, con velocidad).
      if (!pico && n.x >= _proxRampa) {
        rampas.add(RampaTuberia(n.x + 0.4));
        _proxRampa += cadaRampa;
      }
      _decorar(ult, n);
    }
  }

  // Cuando se cierra un tramo nuevo: rollos en arco sobre el valle que se acaba de completar y cucarachas en la ladera.
  void _decorar(_Nudo a, _Nudo b) {
    if (b.x < 12) return;
    final k = _nudos.length;
    // Rollos al cerrar el pico que sigue a un valle (pico - valle - pico). Al principio, sin velocidad todavía, van
    // pegados al piso del valle (se agarran solo bajando); los arcos en el aire llegan después.
    if (b.pico && k >= 3 && _nudos[k - 3].x < desdeArcos) {
      final p1 = _nudos[k - 3];
      final ancho = b.x - p1.x;
      if (p1.x >= 25 && _azar.nextDouble() < 0.7) {
        final arco = _arcos++;
        final medio = _nudos[k - 2].x;
        for (var i = 0; i < 3; i++) {
          final rx = medio + ancho * 0.08 * (i - 1);
          rollos.add(RolloTuberia(rx, altura(rx) + 0.9, arco));
        }
      }
    } else if (b.pico && k >= 3) {
      final p1 = _nudos[k - 3];
      final ancho = b.x - p1.x;
      if (_azar.nextDouble() < 0.62) {
        final alto = p1.x >= desdeArcosAltos && _azar.nextDouble() < 0.3; // arco alto: solo con un buen salto
        final cuantos = 3 + _azar.nextInt(3);
        final x0 = p1.x + ancho * (alto ? 0.25 : 0.12);
        final x1 = p1.x + ancho * (alto ? 0.75 : 0.55);
        final base = p1.y + (alto ? 2.2 : 0.7);
        final sube = alto ? 1.6 : 0.8;
        final baja = alto ? 0.6 : 1.4;
        final arco = _arcos++;
        for (var i = 0; i < cuantos; i++) {
          final u = cuantos == 1 ? 0.5 : i / (cuantos - 1);
          final rx = x0 + (x1 - x0) * u;
          final ry = max(base + sube * sin(pi * u) - baja * u, altura(rx) + 0.9);
          rollos.add(RolloTuberia(rx, ry, arco));
        }
      }
    }
    // Cucarachas: desde los ~150 m, cada vez más.
    if (a.x > 150) {
      final p = ((a.x - 150) / 2500).clamp(0.0, 0.32) + 0.10;
      if (_azar.nextDouble() < p) {
        cucarachas.add(CucarachaTuberia(a.x + (b.x - a.x) * _entre(0.3, 0.7), _azar.nextDouble() * 6.28));
      }
    }
  }

  void _podar() {
    final corte = min(_x, _xa) - 90;
    while (_nudos.length > 4 && _nudos[1].x < corte) {
      _nudos.removeAt(0);
    }
    rollos.removeWhere((r) => r.x < _x - 30);
    cucarachas.removeWhere((c) => c.x < _x - 30);
    rampas.removeWhere((r) => r.x < _x - 30);
  }

  // ---------------------------------------------------------------- paso

  void avanzar(double dt) {
    if (_terminado || dt <= 0) return;
    final n = max(1, (dt / _subPaso).ceil());
    final h = dt / n;
    for (var i = 0; i < n && !_terminado; i++) {
      _paso(h);
    }
  }

  void _paso(double h) {
    _t += h;
    final g = gravedad * (_pesado ? factorPesado : 1);
    final antes = _x;
    if (_suelo) {
      final d1 = pendiente(_x);
      final c = 1 / sqrt(1 + d1 * d1), sn = d1 * c;
      var s = _s;
      s -= g * sn * h;
      s -= (_rozSuelo + _arrastreSuelo * s * s) * h;
      s = s.clamp(velocidadMinima, velocidadMaxima);
      final k = _segunda(_x) * c * c * c; // curvatura
      if (s > 4 && g * c + s * s * k < 0) {
        _suelo = false;
        _vx = s * c;
        _vy = s * sn;
        _aire = 0;
        _alturaMax = 0;
      } else {
        _s = s;
        _x += s * c * h;
        _y = altura(_x);
      }
    }
    if (!_suelo) {
      if (_aire < 0.15 && _aire + h >= 0.15) {
        _sucesos.add(SucesoTuberia(TipoSuceso.despegue, x: _x, y: _y, fuerza: (velocidad / velocidadMaxima).clamp(0.0, 1.0)));
      }
      _aire += h;
      _vy -= g * h;
      final v = sqrt(_vx * _vx + _vy * _vy);
      final f = 1 - _arrastreAire * v * h;
      _vx *= f;
      _vy *= f;
      if (v > velocidadMaxima) {
        final r = velocidadMaxima / v;
        _vx *= r;
        _vy *= r;
      }
      _vx = max(0.5, _vx);
      _x += _vx * h;
      _y += _vy * h;
      final suelo = altura(_x);
      _alturaMax = max(_alturaMax, _y - suelo);
      if (_y <= suelo) {
        _y = suelo;
        _aterrizar();
      }
    }
    if (_x > antes) {
      _tocarCosas();
      _rampas(antes);
    }
    _reglas(h);
  }

  void _rampas(double antes) {
    for (final r in rampas) {
      if (r.usada) continue;
      final xs = r.x - largoRampa;
      if (xs > _x) break; // van ordenadas por x
      if (antes > xs) continue;
      r.usada = true;
      if (_y - altura(xs) > 1.2) continue; // pasó volando por encima
      final s = max(velocidadRampa, min(velocidadMaxima, velocidad));
      _suelo = false;
      _vx = s * cos(anguloRampa);
      _vy = s * sin(anguloRampa);
      _y = max(_y, altura(_x));
      _aire = 0;
      _alturaMax = 0;
      _deRampa = true;
      _sucesos.add(SucesoTuberia(TipoSuceso.rampa, x: xs, y: altura(xs), fuerza: 1));
    }
  }

  /// Fila de rollos sobre el vuelo liviano de una rampa (a velocidad de rampa), puesta antes de que se vea.
  void _decorarRampa(RampaTuberia r) {
    r.decorada = true;
    final xs = r.x - largoRampa;
    var x = xs, y = altura(xs), vx = velocidadRampa * cos(anguloRampa), vy = velocidadRampa * sin(anguloRampa);
    const h = 1 / 120;
    final arco = _arcos++;
    var puestos = 0;
    for (var i = 1; i <= 240 && puestos < 7; i++) {
      vy -= gravedad * h;
      final v = sqrt(vx * vx + vy * vy);
      final f = 1 - _arrastreAire * v * h;
      vx *= f;
      vy *= f;
      x += vx * h;
      y += vy * h;
      if (y <= altura(x)) break;
      if (i >= 30 && i % 18 == 0) {
        rollos.add(RolloTuberia(x, max(y + 0.35, altura(x) + 0.9), arco));
        puestos++;
      }
    }
    rollos.sort((a, b) => a.x.compareTo(b.x));
  }

  /// Plaf: chocar de frente contra la parte baja de una subida. Arriba de la loma, o saliendo de una rampa, se cae suave.
  bool _esPlaf(double x, double y, double ang, double d1) {
    if (ang <= anguloPlaf || _deRampa || d1 <= 0.08) return false;
    final i = _segmento(x);
    final a = _nudos[i], b = _nudos[i + 1];
    if (b.y <= a.y) return false;
    return (y - a.y) / (b.y - a.y) < alturaSuave;
  }

  /// Dónde caería si sigue en el aire con el dedo [pesado], sin tocar el estado (para el tutorial). Null en el suelo.
  /// Si se pasa [camino], lo llena con pares x, y de la trayectoria.
  ({double x, double y, bool limpio, bool plaf})? caida({required bool pesado, List<double>? camino}) {
    if (_suelo || _terminado) return null;
    camino?.clear();
    var x = _x, y = _y, vx = _vx, vy = _vy, aire = _aire;
    const h = 1 / 60;
    final g = gravedad * (pesado ? factorPesado : 1);
    for (var i = 0; i < 300; i++) {
      aire += h;
      vy -= g * h;
      final v = sqrt(vx * vx + vy * vy);
      final f = 1 - _arrastreAire * v * h;
      vx *= f;
      vy *= f;
      if (v > velocidadMaxima) {
        final r = velocidadMaxima / v;
        vx *= r;
        vy *= r;
      }
      vx = max(0.5, vx);
      x += vx * h;
      y += vy * h;
      if (camino != null && i % 5 == 0) camino.addAll([x, y]);
      final suelo = altura(x);
      if (y <= suelo) {
        final d1 = pendiente(x);
        final c = 1 / sqrt(1 + d1 * d1), sn = d1 * c;
        final vt = vx * c + vy * sn;
        final vn = -(-vx * sn + vy * c);
        final ang = atan2(vn.abs(), max(vt, 0.01));
        return (x: x, y: suelo, limpio: aire >= _aireMinimoLimpio && ang < anguloLimpio && d1 < -0.08, plaf: _esPlaf(x, suelo, ang, d1));
      }
    }
    return null;
  }

  void _aterrizar() {
    final d1 = pendiente(_x);
    final c = 1 / sqrt(1 + d1 * d1), sn = d1 * c;
    final vt = _vx * c + _vy * sn; // a lo largo de la ladera
    final vn = -(-_vx * sn + _vy * c); // contra el suelo (positivo = hacia adentro)
    final ang = atan2(vn.abs(), max(vt, 0.01));
    final aire = _aire;
    final plaf = _esPlaf(_x, _y, ang, d1);
    final v = sqrt(_vx * _vx + _vy * _vy);
    _suelo = true;
    _aire = 0;
    _deRampa = false;
    if (aire < 0.12) {
      // Un saltito: sin evento.
      _s = max(velocidadMinima, vt);
      return;
    }
    final fuerza = (vn / 9).clamp(0.0, 1.0);
    if (ang < anguloLimpio && d1 < -0.08 && aire >= _aireMinimoLimpio) {
      _s = min(velocidadMaxima, vt * 1.06 + 1.2);
      _limpios++;
      _sinLimpio = 0;
      final antes = _combo;
      _combo = min(comboMaximo, _combo + 1);
      final pts = (1 + _combo ~/ 2) * (enFiebre ? 2 : 1);
      _bonus += pts;
      _sucesos.add(SucesoTuberia(TipoSuceso.limpio, x: _x, y: _y, puntos: pts, valor: _combo, fuerza: fuerza));
      if (_combo > antes && _combo >= 2) _sucesos.add(SucesoTuberia(TipoSuceso.combo, x: _x, y: _y, valor: _combo));
    } else if (plaf) {
      _s = max(velocidadMinima, vt * 0.45);
      _plafs++;
      final perdio = _combo;
      if (!enFiebre) _combo = 0;
      _sucesos.add(SucesoTuberia(TipoSuceso.plaf, x: _x, y: _y, valor: perdio, fuerza: max(fuerza, 0.6)));
    } else {
      // Caída suave: conserva casi toda la velocidad aunque caiga torcido. valor 1 = habría sido plaf más abajo.
      _s = min(velocidadMaxima, max(velocidadMinima, max(vt, v * 0.8)));
      _sucesos.add(SucesoTuberia(TipoSuceso.aterrizaje, x: _x, y: _y, fuerza: fuerza, valor: ang > anguloPlaf ? 1 : 0));
    }
  }

  void _tocarCosas() {
    final cy = _y + centroMojon;
    for (final r in rollos) {
      if (r.agarrado) continue;
      final dx = r.x - _x;
      if (dx > radioRollo) break; // van ordenados por x
      if (dx < -radioRollo) continue;
      final dy = r.y - cy;
      if (dx * dx + dy * dy > radioRollo * radioRollo) continue;
      r.agarrado = true;
      _rollosAgarrados++;
      if (r.dorado) {
        _doradoPuesto = null;
        _proxDorado = _t + cadaDorado;
        _fiebre = duracionFiebre;
        const pts = 20;
        _bonus += pts;
        _sucesos.add(SucesoTuberia(TipoSuceso.dorado, x: r.x, y: r.y, puntos: pts));
        _sucesos.add(SucesoTuberia(TipoSuceso.fiebre, x: r.x, y: r.y));
      } else {
        final pts = (1 + _combo ~/ 4) * (enFiebre ? 2 : 1);
        _bonus += pts;
        _sucesos.add(SucesoTuberia(TipoSuceso.rollo, x: r.x, y: r.y, puntos: pts, valor: _combo));
      }
    }
    for (final c in cucarachas) {
      if (!c.viva) continue;
      final dx = c.x - _x;
      if (dx.abs() > radioCucaracha) continue;
      if (_y - altura(c.x) > 0.9) continue;
      c.viva = false;
      c.muerte = _t;
      if (_pesado) {
        c.aplastada = true;
        _aplastadas++;
        final pts = 4 + _combo ~/ 2;
        _bonus += pts;
        _sucesos.add(SucesoTuberia(TipoSuceso.aplasta, x: c.x, y: altura(c.x), puntos: pts));
      } else {
        final perdio = _combo;
        if (!enFiebre) _combo = 0;
        if (_suelo) {
          _s = max(velocidadMinima, _s * 0.72);
        } else {
          _vx *= 0.72;
        }
        _sucesos.add(SucesoTuberia(TipoSuceso.choqueCucaracha, x: c.x, y: altura(c.x), valor: perdio, fuerza: 0.7));
      }
    }
  }

  void _reglas(double h) {
    // Fiebre.
    if (_fiebre > 0) {
      _fiebre -= h;
      if (_fiebre <= 0) {
        _fiebre = 0;
        _sucesos.add(SucesoTuberia(TipoSuceso.finFiebre, x: _x, y: _y));
      }
    }
    // El combo se enfría si pasa mucho sin un aterrizaje limpio.
    _sinLimpio += h;
    if (_sinLimpio > 6 && _combo > 0 && !enFiebre) {
      _combo--;
      _sinLimpio = 3;
    }
    // Rollo dorado cada ~25 s: se pone en el próximo arco que todavía no se ve.
    final puesto = _doradoPuesto;
    if (puesto != null && !puesto.agarrado && puesto.x < _x - 2) {
      puesto.dorado = false;
      _doradoPuesto = null;
      _proxDorado = _t + 6;
    }
    if (_doradoPuesto == null && _t >= _proxDorado) {
      final arcos = <int>{};
      for (final r in rollos) {
        if (r.x > _x + 26 && !r.agarrado) arcos.add(r.arco);
      }
      if (arcos.isNotEmpty) {
        final arco = arcos.reduce(min);
        final delArco = rollos.where((r) => r.arco == arco).toList();
        final r = delArco[delArco.length ~/ 2];
        r.dorado = true;
        _doradoPuesto = r;
      }
    }
    for (final r in rampas) {
      if (!r.decorada && r.x - _x < 70) _decorarRampa(r);
    }
    // Zonas.
    final z = zonaEn(_x);
    if (z > _zona) {
      _zona = z;
      _sucesos.add(SucesoTuberia(TipoSuceso.zona, x: _x, y: _y, valor: z));
    }
    // Atasco.
    final n = (_t / tramoAtasco).floor();
    if (n > _tramo) {
      _tramo = n;
      _sucesos.add(SucesoTuberia(TipoSuceso.atascoAcelera, x: _xa, valor: n));
    }
    _xa += velocidadAtascoEn(_t) * h;
    if (_x - _xa > separacionMaxima) _xa = _x - separacionMaxima;
    final cerca = _x - _xa < 9;
    if (cerca && !_cerca) _sucesos.add(SucesoTuberia(TipoSuceso.atascoCerca, x: _xa));
    _cerca = cerca;
    // Récord.
    if (!_recordAvisado && record > 0 && puntos > record) {
      _recordAvisado = true;
      _sucesos.add(SucesoTuberia(TipoSuceso.record, x: _x, y: _y));
    }
    if (_x - _xa <= 0.3 || _t >= tiempoMaximo) {
      _terminado = true;
      _sucesos.add(SucesoTuberia(TipoSuceso.atrapado, x: _x, y: _y, valor: _t >= tiempoMaximo ? 1 : 0));
    }
    if ((_t * 4).floor() != ((_t - h) * 4).floor()) _podar();
  }
}
