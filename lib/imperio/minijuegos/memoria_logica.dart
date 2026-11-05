// Fusión real, lógica pura (sin Flutter): se sueltan mojones en la poceta y dos iguales que se tocan se fusionan en el
// siguiente nivel, hasta el Rey. Física propia de círculos (Verlet con subpasos y restricciones), paso fijo de 1/60 s,
// así una partida con la misma semilla y los mismos toques sale idéntica.
//
// Mundo: x a la derecha, y hacia abajo. El borde de la poceta está en y = 0, el interior va de x = -50 a 50. Paredes
// rectas hasta y = 40 y luego media elipse (radios 50 y 80) que toca fondo en y = 120. Es convexa, así que cada tramo
// es un semiplano y un círculo está dentro si cumple todos. Arriba no hay tapa.
//
// Puntos: crear un nivel da puntosPorNivel, que crece más rápido que el tamaño (los grandes valen mucho más). Fusiones
// encadenadas (una fusión que provoca otra en menos de 0.5 s) multiplican hasta x4, y la presión multiplica todo: x2
// desde el segundo 60 y x4 desde el 120, así que aguantar sin desbordar es lo que más paga. Dos Reyes juntos hacen la
// descarga gigante (y cada descarga real de la partida paga más que la anterior). Con dos Reyes vivos se atraen y la
// poceta crece (todo se achica con una animación) para que se puedan juntar; tras la descarga vuelve a su tamaño. No hay
// reloj ni tope práctico: se juega hasta que la poceta se desborda. La partida puede arrancar con unos mojones ya adentro
// (niveles distintos al azar): esa es la perilla de dificultad. Lo que se reporta nunca pasa de topePuntosFusion (el
// límite de la columna en el servidor) ni de (segundos + 1) * puntosPorSegundoFusion.

import 'dart:math';

/// Niveles de mojón: 1 bolita, 2 frijolito, 3 mojoncito, 4 mojón, 5 lentes, 6 bigote, 7 gordo, 8 dorado, 9 Rey.
const int nivelMaximo = 9;

/// Solo se sueltan estos niveles (los demás salen de fusiones).
const int nivelMaximoSoltar = 4;

/// Radio por nivel (índice = nivel - 1).
const List<double> radiosNivel = [5.3, 7.0, 9.1, 11.3, 13.9, 16.7, 19.7, 23.0, 26.6];

/// Puntos por crear cada nivel (índice = nivel). Ni el 0 ni el 1 se crean por fusión.
const List<int> puntosPorNivel = [0, 0, 1, 1, 2, 3, 8, 19, 49, 124];

/// Dos Reyes juntos: se descarga todo y da esto.
const int bonusDescargaReal = 140;

const int multiplicadorMaximoFusion = 4;
const double ventanaCombo = 0.5;

/// Contrato del servidor (flags `minijuego_*_memoria`). El tope es el de la columna: en la práctica no se llega.
const int topePuntosFusion = 1000000;
const int puntosPorSegundoFusion = 400;
const int minMsFusion = 3000;
const int maxMsFusion = 3600000;

/// La poceta crece (las piezas se achican a esta fracción) cada vez que hay dos Reyes vivos, hasta [crecidasMaximas].
const double escalaPorCrecida = 0.85;
const int crecidasMaximas = 3;

/// Tirón entre Reyes vivos y, durante el evento imán, entre iguales cercanos (unidades/s²).
const double atraccionReyes = 300;
const double atraccionIman = 170;
const double alcanceIman = 34;
const double duracionIman = 5;

/// Mojones que ya están en la poceta al empezar (flag `fusion_piezas_inicio`), cada uno de un nivel distinto.
const int piezasInicioDefecto = 4;
const int piezasInicioMaximo = 6;

/// Niveles que pueden salir en el arranque (del 1 a este).
const int nivelMaximoInicio = 6;

/// Después de los eventos fijos, uno cada tantos segundos en rueda.
const double cadaEventoRueda = 25;
const List<String> _rueda = ['temblor', 'iman', 'frijoles', 'lluvia'];

/// Paso fijo y subpasos de la física.
const double pasoFijo = 1 / 60;
const int subpasos = 4;
const int iteraciones = 3;

const double gravedad = 420;
const double velocidadMaxima = 420;
const double velocidadSubida = 160;

const double mitadAncho = 50;
const double yRecto = 40;
const double radioElipseX = 50;
const double radioElipseY = 80;
const double yFondo = yRecto + radioElipseY;

/// Si algo se queda por encima de esta línea más de [segundosDesborde], se acaba.
const double lineaDesborde = 6;
const double segundosDesborde = 2;

/// Altura a la que cuelga la pieza de la pinza.
const double yColgado = -26;

/// Tiempo mínimo entre dos piezas soltadas.
const double esperaSoltar = 0.45;

/// Fusiones que llenan la palanca de descarga.
const int cargaPalanca = 10;

double radioDe(int nivel) => radiosNivel[nivel - 1];

/// Puntos que de verdad se pueden reportar con [ms] jugados.
int puntosReportables(int puntos, int ms) {
  final porTiempo = ((ms / 1000 + 1) * puntosPorSegundoFusion).floor();
  return min(min(puntos, topePuntosFusion), porTiempo).clamp(0, topePuntosFusion);
}

class Mojon {
  Mojon(this.id, this.nivel, this.x, this.y, {double escala = 1})
      : px = x,
        py = y,
        r = radioDe(nivel) * escala,
        rObjetivo = radioDe(nivel) * escala;
  final int id;
  final int nivel;
  double x, y, px, py;

  /// Radio actual: al nacer de una fusión crece desde el de sus padres hasta [rObjetivo]; cuando la poceta crece se
  /// achica despacio hasta el nuevo.
  double r;
  double rObjetivo;
  double edad = 0;

  /// Aplastón de 0 a 1 (al caer o al nacer); se apaga solo.
  double golpe = 0;

  /// Peso que tiene encima, en "masas propias" (para aplastarlo un poco).
  double carga = 0;

  /// Ya tocó algo después de soltarlo.
  bool tocado = false;
  bool deFusion = false;
  int cadena = 0;
  bool vivo = true;

  /// Velocidad aproximada en unidades por segundo.
  double get vx => (x - px) / (pasoFijo / subpasos);
  double get vy => (y - py) / (pasoFijo / subpasos);
  double get masa => rObjetivo * rObjetivo;
}

enum TipoSuceso {
  /// Un mojón cae sobre algo. [SucesoFusion.fuerza] de 0 a 1.
  plop,
  fusion,

  /// Se creó un dorado (nivel 8).
  dorado,

  /// Se creó un Rey (nivel 9).
  rey,

  /// Dos Reyes: se va todo por el desagüe. [SucesoFusion.cadena] = número de descarga real en la partida.
  descargaReal,

  /// Hay dos Reyes: la poceta crece. [SucesoFusion.nivel] = cuántas veces lleva.
  crece,

  /// Palanca: se tragó los chiquitos. Va seguido de un [tragado] por pieza.
  palanca,
  tragado,

  /// La cuenta de desborde empezó.
  alerta,
  desborde,

  /// Evento de la partida (ver [SucesoFusion.clave]).
  aviso,

  /// Llegó a topePuntosFusion: se acaba ganando.
  maximo,
}

class SucesoFusion {
  const SucesoFusion(this.tipo, {this.x = 0, this.y = 0, this.nivel = 0, this.puntos = 0, this.cadena = 0, this.fuerza = 0, this.clave = ''});
  final TipoSuceso tipo;
  final double x, y;
  final int nivel, puntos, cadena;
  final double fuerza;
  final String clave;
}

enum FaseFusion { jugando, desbordado, maximo, terminado }

/// Eventos de la partida, uno cada ~15 s. Los primeros 12 s solo salen bolitas y frijolitos.
class _Evento {
  const _Evento(this.t, this.clave);
  final double t;
  final String clave;
}

const List<_Evento> _eventos = [
  _Evento(12, 'nivel3'),
  _Evento(25, 'nivel4'),
  _Evento(40, 'temblor'),
  _Evento(55, 'frijoles'),
  _Evento(60, 'presion2'),
  _Evento(75, 'lluvia'),
  _Evento(95, 'temblor'),
  _Evento(110, 'frijoles'),
  _Evento(120, 'presion4'),
  _Evento(135, 'lluvia'),
  _Evento(150, 'temblor'),
];

const double duracionTemblor = 1.4;

/// Segundos que el remolino de la palanca chupa la pila hacia abajo.
const double duracionSuccion = 1.0;

class _Lado {
  const _Lado(this.ax, this.ay, this.nx, this.ny);
  final double ax, ay, nx, ny;
}

/// Semiplanos de la poceta (normales hacia dentro).
final List<_Lado> _lados = () {
  final l = <_Lado>[
    const _Lado(-mitadAncho, 0, 1, 0),
    const _Lado(mitadAncho, 0, -1, 0),
  ];
  const n = 18;
  for (var i = 0; i < n; i++) {
    final a0 = pi * i / n, a1 = pi * (i + 1) / n;
    final x0 = radioElipseX * cos(a0), y0 = yRecto + radioElipseY * sin(a0);
    final x1 = radioElipseX * cos(a1), y1 = yRecto + radioElipseY * sin(a1);
    // Recorrido de derecha a izquierda por abajo: la normal hacia dentro es (-dy, dx).
    final dx = x1 - x0, dy = y1 - y0;
    final len = sqrt(dx * dx + dy * dy);
    l.add(_Lado(x0, y0, -dy / len, dx / len));
  }
  return l;
}();

/// Puntos del contorno interior de la poceta, de arriba a la izquierda a arriba a la derecha, para dibujarla.
List<(double, double)> contornoPoceta({int tramos = 36}) => [
      (-mitadAncho, 0.0),
      for (var i = tramos; i >= 0; i--) (radioElipseX * cos(pi * i / tramos), yRecto + radioElipseY * sin(pi * i / tramos)),
      (mitadAncho, 0.0),
    ];

class JuegoFusion {
  JuegoFusion({int semilla = 7, int piezasInicio = 0}) : _rng = Random(semilla) {
    _sembrar(piezasInicio.clamp(0, piezasInicioMaximo));
    actual = _sorteo();
    siguiente = _sorteo();
  }

  final Random _rng;
  final List<Mojon> mojones = [];
  final List<SucesoFusion> _sucesos = [];
  int _ids = 0;

  FaseFusion fase = FaseFusion.jugando;

  /// Segundos de juego (solo corre en pasos fijos).
  double t = 0;
  double _acumulado = 0;

  /// Puntos sin tope (lo que se muestra y reporta pasa por [puntosVisibles] y [puntosReportables]).
  int puntosCrudos = 0;
  int fusiones = 0;
  int nivelMasAlto = 1;
  int reyes = 0;
  int descargas = 0;

  /// Tamaño de las piezas respecto al normal (baja cuando la poceta crece) y veces que creció.
  double escala = 1;
  int crecidas = 0;
  int crecidasTotal = 0;
  double desdeCrecida = 99;
  double imanHasta = -1;

  /// Pieza en la pinza y la que viene.
  late int actual;
  late int siguiente;

  /// Dónde apunta la pinza (centro de la pieza).
  double apunte = 0;
  double _espera = 0;

  /// La última que se soltó, mientras no toque nada (para que los ojos la sigan).
  Mojon? cayendo;

  int carga = 0;
  bool get palancaLista => carga >= cargaPalanca;
  double get cargaPalancaFraccion => (carga / cargaPalanca).clamp(0.0, 1.0);

  /// Segundos desde que se jaló la palanca (para el remolino); grande si nunca.
  double desdePalanca = 99;

  /// Segundos desde la descarga real.
  double desdeDescargaReal = 99;

  /// Segundos que lleva algo por encima de la línea.
  double cuentaDesborde = 0;
  bool _alertado = false;
  double _tFase = 0;

  /// Niveles con los que arrancó la poceta.
  final List<int> inicio = [];

  int _proximoEvento = 0;
  double temblorHasta = -1;
  int _frijoles = 0;
  final List<(double, double, int)> _lluvia = [];

  bool get terminado => fase == FaseFusion.terminado;
  bool get desbordo => motivoDesborde;
  bool motivoDesborde = false;
  /// La poceta se calienta: desde el segundo 60 todo vale x2 y desde el 120 x4.
  int get presion => t >= 120 ? 4 : (t >= 60 ? 2 : 1);
  bool get temblando => t < temblorHasta;
  bool get imanActivo => t < imanHasta;

  /// Radio de una pieza nueva de [nivel] con el tamaño actual de la poceta.
  double radio(int nivel) => radioDe(nivel) * escala;
  bool get llegoAlMaximo => fase == FaseFusion.maximo || (fase == FaseFusion.terminado && !motivoDesborde);
  bool get puedeSoltar => fase == FaseFusion.jugando && _espera <= 0;
  double get esperaFraccion => (_espera / esperaSoltar).clamp(0.0, 1.0);
  int get puntosVisibles => min(puntosCrudos, topePuntosFusion);

  /// Peligro de 0 a 1: cuánto falta para que la pila pase la línea (1 = ya pasó).
  double get peligro {
    var tope = double.infinity;
    for (final m in mojones) {
      if (m.edad > 1.0 && m != cayendo) tope = min(tope, m.y - m.r);
    }
    if (tope == double.infinity) return 0;
    return (1 - (tope - lineaDesborde) / 30).clamp(0.0, 1.0);
  }

  List<SucesoFusion> tomarSucesos() {
    final l = List<SucesoFusion>.of(_sucesos);
    _sucesos.clear();
    return l;
  }

  int _sorteo() {
    if (_frijoles > 0) {
      _frijoles--;
      return 1;
    }
    final tope = t < 12 ? 2 : (t < 25 ? 3 : nivelMaximoSoltar);
    const pesos = [4, 4, 3, 2];
    var total = 0;
    for (var i = 0; i < tope; i++) {
      total += pesos[i];
    }
    var r = _rng.nextInt(total);
    for (var i = 0; i < tope; i++) {
      if (r < pesos[i]) return i + 1;
      r -= pesos[i];
    }
    return 1;
  }

  void apuntar(double x) => apunte = x.clamp(-mitadAncho + radio(actual), mitadAncho - radio(actual));

  /// Suelta la pieza de la pinza en [apunte]. Devuelve si se pudo.
  bool soltar() {
    if (!puedeSoltar) return false;
    apuntar(apunte);
    final m = _crear(actual, apunte, yColgado);
    cayendo = m;
    actual = siguiente;
    siguiente = _sorteo();
    _espera = esperaSoltar;
    apuntar(apunte);
    return true;
  }

  /// Mete [n] mojones de niveles distintos al azar, cada uno donde caería, y deja que la pila se asiente sin puntos.
  void _sembrar(int n) {
    if (n <= 0) return;
    final niveles = [for (var i = 1; i <= nivelMaximoInicio; i++) i]..shuffle(_rng);
    for (final nivel in niveles.take(n)) {
      final r = radioDe(nivel);
      final x = -mitadAncho + r + _rng.nextDouble() * (2 * (mitadAncho - r));
      final y = alturaDeCaida(x, r);
      _crear(nivel, x, y.isFinite ? y : yFondo - r);
      inicio.add(nivel);
    }
    final h = pasoFijo / subpasos;
    for (var paso = 0; paso < 240; paso++) {
      for (var s = 0; s < subpasos; s++) {
        _integrar(h);
        for (var it = 0; it < iteraciones; it++) {
          _restricciones(it == iteraciones - 1, h);
        }
      }
    }
    for (final m in mojones) {
      m
        ..px = m.x
        ..py = m.y
        ..tocado = true
        ..golpe = 0
        ..edad = 2;
    }
    _sucesos.clear();
  }

  Mojon _crear(int nivel, double x, double y) {
    final m = Mojon(_ids++, nivel, x, y, escala: escala);
    mojones.add(m);
    return m;
  }

  /// Jala la palanca si está llena: se traga todos los niveles 1 y 2 (sin puntos) y durante [duracionSuccion] s el
  /// remolino chupa la pila hacia el fondo, así baja aunque no haya chiquitos. [SucesoFusion.cadena] = cuántos se tragó.
  bool jalarPalanca() {
    if (!palancaLista || fase != FaseFusion.jugando) return false;
    carga = 0;
    desdePalanca = 0;
    final tragados = mojones.where((m) => m.nivel <= 2).length;
    _sucesos.add(SucesoFusion(TipoSuceso.palanca, y: yFondo, cadena: tragados));
    for (final m in mojones) {
      if (m.nivel <= 2) {
        m.vivo = false;
        _sucesos.add(SucesoFusion(TipoSuceso.tragado, x: m.x, y: m.y, nivel: m.nivel));
      }
    }
    mojones.removeWhere((m) => !m.vivo);
    if (cayendo != null && !cayendo!.vivo) cayendo = null;
    return true;
  }

  /// Avanza [dt] segundos de reloj real en pasos fijos.
  void avanzar(double dt) {
    _acumulado += dt;
    var n = 0;
    while (_acumulado >= pasoFijo && n < 6) {
      _acumulado -= pasoFijo;
      _paso();
      n++;
    }
    if (n == 6) _acumulado = 0;
  }

  void _paso() {
    if (fase == FaseFusion.terminado) return;
    const dt = pasoFijo;
    if (fase == FaseFusion.jugando) t += dt;
    _tFase += dt;
    desdePalanca += dt;
    desdeDescargaReal += dt;
    desdeCrecida += dt;
    if (_espera > 0) _espera -= dt;

    if (fase == FaseFusion.jugando) {
      _eventosDelTurno();
      _llover();
      _vigilarReyes();
    }
    if (temblando) _sacudir();

    final h = dt / subpasos;
    for (var s = 0; s < subpasos; s++) {
      _integrar(h);
      for (var it = 0; it < iteraciones; it++) {
        _restricciones(it == iteraciones - 1, h);
      }
      _fusionar();
    }
    for (final m in mojones) {
      m.edad += dt;
      if (m.golpe > 0) m.golpe = max(0, m.golpe - dt * 3.5);
    }
    if (cayendo != null && (cayendo!.tocado || !cayendo!.vivo)) cayendo = null;

    switch (fase) {
      case FaseFusion.jugando:
        _vigilarDesborde(dt);
        if (fase == FaseFusion.jugando && puntosCrudos >= topePuntosFusion && t > 3.5) {
          fase = FaseFusion.maximo;
          _tFase = 0;
          cayendo = null;
          _sucesos.add(const SucesoFusion(TipoSuceso.maximo));
        }
      case FaseFusion.desbordado:
      case FaseFusion.maximo:
        if (_tFase >= 1.8) fase = FaseFusion.terminado;
      case FaseFusion.terminado:
        break;
    }
  }

  /// Clave del evento número [i]: primero la lista fija y después la rueda cada [cadaEventoRueda] s.
  (double, String) _evento(int i) {
    if (i < _eventos.length) return (_eventos[i].t, _eventos[i].clave);
    final k = i - _eventos.length;
    return (_eventos.last.t + (k + 1) * cadaEventoRueda, _rueda[k % _rueda.length]);
  }

  void _eventosDelTurno() {
    while (t >= _evento(_proximoEvento).$1) {
      final clave = _evento(_proximoEvento++).$2;
      switch (clave) {
        case 'temblor':
          temblorHasta = t + duracionTemblor;
        case 'frijoles':
          _frijoles = 6;
          // La pieza que viene ya es frijol.
          siguiente = _sorteo();
        case 'iman':
          imanHasta = t + duracionIman;
        case 'lluvia':
          for (var i = 0; i < 5; i++) {
            _lluvia.add((t + 0.6 + i * 0.35, -40 + _rng.nextDouble() * 80, 1 + _rng.nextInt(2)));
          }
      }
      _sucesos.add(SucesoFusion(TipoSuceso.aviso, clave: clave));
    }
  }

  void _llover() {
    while (_lluvia.isNotEmpty && t >= _lluvia.first.$1) {
      final (_, x, nivel) = _lluvia.removeAt(0);
      final r = radio(nivel);
      _crear(nivel, x.clamp(-mitadAncho + r, mitadAncho - r), yColgado - 14);
    }
  }

  void _sacudir() {
    // El vecino jala la cadena: cada 0.2 s un empujón pequeño a todos.
    final antes = t - pasoFijo;
    if ((t / 0.2).floor() == (antes / 0.2).floor()) return;
    final h = pasoFijo / subpasos;
    for (final m in mojones) {
      m.px -= (_rng.nextDouble() - 0.5) * 50 * h;
      m.py += _rng.nextDouble() * 18 * h;
    }
  }

  void _integrar(double h) {
    final vmax = velocidadMaxima * h;
    final vsubir = velocidadSubida * h;
    // Succión de la palanca: más gravedad y un tirón hacia el centro que se apaga solo.
    final succion = fase == FaseFusion.jugando && desdePalanca < duracionSuccion ? 1 - desdePalanca / duracionSuccion : 0.0;
    final g = gravedad * (1 + 1.6 * succion) * h * h;
    _atraer(h);
    for (final m in mojones) {
      var vx = m.x - m.px, vy = m.y - m.py;
      final v2 = vx * vx + vy * vy;
      if (v2 > vmax * vmax) {
        final k = vmax / sqrt(v2);
        vx *= k;
        vy *= k;
      }
      // Una fusión que crece puede apretar a un vecino contra la pared: que no salga disparado hacia arriba.
      if (vy < -vsubir) vy = -vsubir;
      vx *= 0.999;
      vy *= 0.999;
      m.px = m.x;
      m.py = m.y;
      m.x += vx - m.x * succion * 0.9 * h * h * 60;
      m.y += vy + g;
      if (m.r < m.rObjetivo) {
        m.r = min(m.rObjetivo, m.r + (m.rObjetivo - m.r) * 0.08 + 0.02);
      } else if (m.r > m.rObjetivo) {
        // La poceta creció: se achica en ~1 s para que se vea.
        m.r = max(m.rObjetivo, m.r - (m.r - m.rObjetivo) * 0.012 - 0.0005);
      }
      m.carga = 0;
    }
  }

  void _contacto(Mojon m, double fuerza) {
    if (m.tocado) return;
    m.tocado = true;
    final f = (fuerza / 260).clamp(0.0, 1.0);
    if (f > 0.08) {
      m.golpe = max(m.golpe, 0.15 + 0.45 * f);
      _sucesos.add(SucesoFusion(TipoSuceso.plop, x: m.x, y: m.y + m.r, nivel: m.nivel, fuerza: f));
    }
  }

  void _restricciones(bool ultima, double h) {
    final n = mojones.length;
    for (var i = 0; i < n; i++) {
      final a = mojones[i];
      for (var j = i + 1; j < n; j++) {
        final b = mojones[j];
        final dx = b.x - a.x, dy = b.y - a.y;
        final minD = a.r + b.r;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minD * minD) continue;
        final d = sqrt(d2);
        final nx = d > 1e-6 ? dx / d : 0.0, ny = d > 1e-6 ? dy / d : 1.0;
        final solape = minD - d;
        final ma = a.masa, mb = b.masa;
        final wa = mb / (ma + mb), wb = ma / (ma + mb);
        if (ultima) {
          if (!a.tocado || !b.tocado) {
            final rv = ((b.x - b.px) - (a.x - a.px)) * nx + ((b.y - b.py) - (a.y - a.py)) * ny;
            final f = rv.abs() / h;
            _contacto(a, f);
            _contacto(b, f);
          }
          // Peso de encima: el de arriba carga sobre el de abajo.
          if (ny > 0.3) {
            b.carga += ma / mb * ny;
          } else if (ny < -0.3) {
            a.carga += mb / ma * -ny;
          }
        }
        a.x -= nx * solape * wa;
        a.y -= ny * solape * wa;
        b.x += nx * solape * wb;
        b.y += ny * solape * wb;
        if (ultima) {
          // Fricción tangencial entre los dos.
          final tx = -ny, ty = nx;
          // Coulomb: cuanto más se aprietan, más se frenan de lado.
          final rvt = ((b.x - b.px) - (a.x - a.px)) * tx + ((b.y - b.py) - (a.y - a.py)) * ty;
          final c = rvt.clamp(-solape * 0.5, solape * 0.5) * 0.5;
          a.px += tx * c * wa;
          a.py += ty * c * wa;
          b.px -= tx * c * wb;
          b.py -= ty * c * wb;
        }
      }
    }
    for (final m in mojones) {
      for (final l in _lados) {
        final s = (m.x - l.ax) * l.nx + (m.y - l.ay) * l.ny - m.r;
        if (s >= 0) continue;
        m.x -= s * l.nx;
        m.y -= s * l.ny;
        if (ultima) {
          if (!m.tocado) {
            final vn = ((m.x - m.px) * l.nx + (m.y - m.py) * l.ny).abs() / h;
            _contacto(m, vn);
          }
          final tx = -l.ny, ty = l.nx;
          final vt = (m.x - m.px) * tx + (m.y - m.py) * ty;
          final c = vt.clamp(s * 0.4, -s * 0.4);
          m.px += tx * c;
          m.py += ty * c;
        }
      }
    }
  }

  void _fusionar() {
    final n = mojones.length;
    var hubo = false;
    for (var i = 0; i < n; i++) {
      final a = mojones[i];
      if (!a.vivo) continue;
      for (var j = i + 1; j < n; j++) {
        final b = mojones[j];
        if (!b.vivo || b.nivel != a.nivel) continue;
        final dx = b.x - a.x, dy = b.y - a.y;
        final lim = a.r + b.r + 0.4;
        if (dx * dx + dy * dy > lim * lim) continue;
        a.vivo = false;
        b.vivo = false;
        hubo = true;
        _unir(a, b);
        break;
      }
    }
    if (hubo) mojones.removeWhere((m) => !m.vivo);
    if (cayendo != null && !cayendo!.vivo) cayendo = null;
  }

  int _cadenaDe(Mojon m) => m.deFusion && m.edad < ventanaCombo ? m.cadena : 0;

  void _unir(Mojon a, Mojon b) {
    final x = (a.x + b.x) / 2, y = (a.y + b.y) / 2;
    final cadena = max(_cadenaDe(a), _cadenaDe(b)) + 1;
    final mult = min<int>(cadena, multiplicadorMaximoFusion) * presion;
    fusiones++;
    if (fase == FaseFusion.jugando && carga < cargaPalanca) carga++;

    if (a.nivel == nivelMaximo) {
      // Dos Reyes: descarga real, se va todo. Cada una de la partida paga más que la anterior; la poceta vuelve a su tamaño.
      descargas++;
      final pts = bonusDescargaReal * descargas * min<int>(cadena, multiplicadorMaximoFusion) * presion;
      _sumar(pts);
      desdeDescargaReal = 0;
      escala = 1;
      crecidas = 0;
      _sucesos.add(SucesoFusion(TipoSuceso.descargaReal, x: x, y: y, nivel: nivelMaximo, puntos: pts, cadena: descargas));
      for (final m in mojones) {
        if (m.vivo) {
          m.vivo = false;
          _sucesos.add(SucesoFusion(TipoSuceso.tragado, x: m.x, y: m.y, nivel: m.nivel));
        }
      }
      cayendo = null;
      return;
    }

    final nivel = a.nivel + 1;
    final m = Mojon(_ids++, nivel, x, y, escala: escala)
      ..r = a.r * 1.02
      ..px = x - ((a.x - a.px) + (b.x - b.px)) / 2
      ..py = y - ((a.y - a.py) + (b.y - b.py)) / 2
      ..deFusion = true
      ..cadena = cadena
      ..tocado = true
      ..golpe = 0.7;
    mojones.add(m);
    final pts = puntosPorNivel[nivel] * mult;
    _sumar(pts);
    if (nivel > nivelMasAlto) nivelMasAlto = nivel;
    if (nivel == nivelMaximo) reyes++;
    _sucesos.add(SucesoFusion(TipoSuceso.fusion, x: x, y: y, nivel: nivel, puntos: pts, cadena: cadena));
    if (nivel == 8) _sucesos.add(SucesoFusion(TipoSuceso.dorado, x: x, y: y, nivel: nivel));
    if (nivel == nivelMaximo) _sucesos.add(SucesoFusion(TipoSuceso.rey, x: x, y: y, nivel: nivel));
  }

  void _sumar(int p) => puntosCrudos = min(puntosCrudos + p, topePuntosFusion);

  /// Con dos Reyes vivos la poceta crece (si le quedan crecidas y ya terminó la anterior).
  void _vigilarReyes() {
    if (crecidas >= crecidasMaximas || desdeCrecida < 1.5) return;
    var vivos = 0;
    for (final m in mojones) {
      if (m.vivo && m.nivel == nivelMaximo) vivos++;
    }
    if (vivos < 2) return;
    crecidas++;
    crecidasTotal++;
    escala *= escalaPorCrecida;
    desdeCrecida = 0;
    for (final m in mojones) {
      m.rObjetivo = radioDe(m.nivel) * escala;
    }
    _sucesos.add(SucesoFusion(TipoSuceso.crece, nivel: crecidas));
  }

  /// Los Reyes vivos se buscan siempre; durante el imán, cada pieza busca a la igual más cercana a su alcance.
  void _atraer(double h) {
    if (fase != FaseFusion.jugando) return;
    final iman = imanActivo;
    final h2 = h * h;
    for (final a in mojones) {
      if (a == cayendo || (a.nivel != nivelMaximo && !iman)) continue;
      Mojon? cerca;
      var mejor = double.infinity;
      for (final b in mojones) {
        if (identical(a, b) || b.nivel != a.nivel || b == cayendo) continue;
        final dx = b.x - a.x, dy = b.y - a.y;
        final d2 = dx * dx + dy * dy;
        if (d2 < mejor) {
          mejor = d2;
          cerca = b;
        }
      }
      if (cerca == null) continue;
      final rey = a.nivel == nivelMaximo;
      final d = sqrt(mejor);
      if (d < 1e-6 || (!rey && d > a.r + cerca.r + alcanceIman)) continue;
      final f = (rey ? atraccionReyes : atraccionIman) * h2 / d;
      a.x += (cerca.x - a.x) * f;
      a.y += (cerca.y - a.y) * f;
    }
  }

  void _vigilarDesborde(double dt) {
    var arriba = false;
    for (final m in mojones) {
      if (m.edad > 1.0 && m != cayendo && m.y - m.r < lineaDesborde && m.vy.abs() < 60) {
        arriba = true;
        break;
      }
    }
    if (arriba) {
      cuentaDesborde += dt;
      if (!_alertado) {
        _alertado = true;
        _sucesos.add(const SucesoFusion(TipoSuceso.alerta));
      }
    } else {
      cuentaDesborde = max(0, cuentaDesborde - dt * 2);
      if (cuentaDesborde == 0) _alertado = false;
    }
    // Antes de los 3.5 s no se puede perder (el servidor pide partidas de al menos 3 s).
    if (cuentaDesborde >= segundosDesborde && t > 3.5) {
      fase = FaseFusion.desbordado;
      motivoDesborde = true;
      _tFase = 0;
      cayendo = null;
      _sucesos.add(const SucesoFusion(TipoSuceso.desborde));
    }
  }

  /// Y del centro donde quedaría una pieza de radio [r] soltada en [x] (primer choque al bajar). Para la guía.
  double alturaDeCaida(double x, double r) {
    var y = double.infinity;
    for (final l in _lados) {
      if (l.ny >= -1e-6) continue;
      // (x - ax) nx + (y - ay) ny >= r  ->  y <= ay + (r - (x - ax) nx) / ny
      final lim = l.ay + (r - (x - l.ax) * l.nx) / l.ny;
      if (lim < y) y = lim;
    }
    for (final m in mojones) {
      if (m == cayendo) continue;
      final dx = (m.x - x).abs(), s = m.r + r;
      if (dx >= s) continue;
      final yc = m.y - sqrt(s * s - dx * dx);
      if (yc < y && yc > yColgado) y = yc;
    }
    return y;
  }
}
