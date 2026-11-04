// Destapa, lógica pura. La música va por frases de 4 tiempos con patrones que cambian: toques, dobles (medio tiempo),
// pausas, síncopas y notas de MANTENER. Cada nota es un anillo que se cierra sobre el inodoro; hay que tocar cuando llega.
// Perfecto y bueno empujan el destapador; tocar sin nota, dejar pasar una o soltar antes una de mantener es un fallo.
// Con [fallosMaximos] fallos el agua se desborda y se acaba. La racha sube el multiplicador (x2, x3). Cada [cadaJefe]
// inodoros viene un atasco gordo: pide más, trae los patrones pesados y al vencerlo baja el agua (devuelve un fallo).
// El tiempo se acelera por inodoro. El turno se acaba solo a los [tiempoMaximo] s: ni una partida perfecta pasa del
// tope del servidor (8000 puntos, 14 puntos por segundo, 20 min). El reloj lo mueve [avanzar].
// Calentamiento: la primera frase de la partida (una sola vez) no suma fallos. Se ve el fallo y corta la racha, pero el
// agua no sube; los aciertos valen lo mismo, así que el máximo posible no cambia.

import 'dart:math';

enum Golpe { perfecto, bueno, fallo }

enum EstadoNota { pendiente, manteniendo, hecha, fallada }

/// Una nota: un toque en [t], o mantener de [t] a [fin].
class Nota {
  Nota(this.t, {this.fin, this.calentamiento = false});
  final double t;
  final double? fin;

  /// Es de la frase de calentamiento: fallarla no suma.
  final bool calentamiento;
  EstadoNota estado = EstadoNota.pendiente;
  Golpe? golpe;
  bool get mantener => fin != null;
}

/// Un patrón de una frase: (tiempo dentro de la frase, tiempos de mantener; 0 = toque). Sale desde el inodoro [desde].
class Patron {
  const Patron(this.nombre, this.notas, this.desde);
  final String nombre;
  final List<(double, double)> notas;
  final int desde;

  /// Los que van en un atasco gordo: muchas notas o mantener.
  bool get pesado => notas.length >= 5 || notas.any((n) => n.$2 > 0);
}

const patronesDestapa = <Patron>[
  Patron('negras', [(0, 0), (1, 0), (2, 0), (3, 0)], 0),
  Patron('pausa', [(0, 0), (1, 0), (2, 0)], 0),
  Patron('respiro', [(0, 0), (2, 0), (3, 0)], 1),
  Patron('dobles', [(0, 0), (1, 0), (1.5, 0), (2, 0), (3, 0)], 2),
  Patron('mantener', [(0, 2), (3, 0)], 3),
  Patron('galope', [(0, 0), (0.5, 0), (1, 0), (2, 0), (2.5, 0), (3, 0)], 5),
  Patron('sincopa', [(0, 0), (1.5, 0), (2, 0), (3, 0)], 6),
  Patron('mantener_corto', [(0, 0), (1, 1.5), (3, 0)], 7),
  Patron('rafaga', [(0, 0), (0.5, 0), (1, 0), (1.5, 0), (2, 0), (3, 0)], 9),
];

enum Suceso { golpe, fallo, mantenido, destapado, jefe, jefeVencido, masRapido, multiplicador, finTurno }

/// Lo que pasó en el último paso, para que la vista lo celebre (o lo llore).
class EventoDestapa {
  const EventoDestapa(this.suceso, {this.golpe, this.valor = 0});
  final Suceso suceso;
  final Golpe? golpe;
  final int valor;
}

class JuegoDestapa {
  /// [calentamiento] en false arranca sin calentamiento (para las pruebas de los fallos).
  JuegoDestapa({int? semilla, bool calentamiento = true})
      : _azar = Random(semilla),
        _conCalentamiento = calentamiento {
    _generar();
  }

  static const int fallosMaximos = 3;

  /// Ventanas de acierto, en segundos desde la nota (ya restada la [compensacion]).
  static const double ventanaPerfecta = 0.06;
  static const double ventanaBuena = 0.13;

  /// El toque llega tarde al código (pantalla + táctil): se le resta esto antes de juzgar.
  static const double compensacion = 0.03;

  /// Primera nota (da tiempo a ver los anillos) y tiempo inicial y mínimo, en segundos.
  static const double entrada = 1.4;
  static const double compasInicial = 0.72;
  static const double compasMinimo = 0.48;
  static const double compasMenosPorInodoro = 0.024;

  /// Cuánto antes de su hora se ve venir una nota.
  static const double verAntes = 1.3;

  /// Fin del turno. Con esto una partida perfecta queda lejos de los 8000 del servidor.
  static const double tiempoMaximo = 480;

  /// Puntos de un acierto: bueno vale el multiplicador, perfecto uno más.
  static const int puntosPerfecto = 2;
  static const int puntosBueno = 1;
  static const int puntosJefe = 25;
  static const int rachaX2 = 10;
  static const int rachaX3 = 30;
  static const int cadaJefe = 4;

  final Random _azar;
  final bool _conCalentamiento;

  /// Hora de juicio hasta la que dura el calentamiento (última nota de la primera frase + ventana buena).
  double _finCalentamiento = -1;
  final _notas = <Nota>[];
  final _eventos = <EventoDestapa>[];
  final _vistos = <String>{};
  double _tiempo = 0;
  double _proxima = entrada;
  double _beatAnterior = compasInicial;
  int _frases = 0;
  bool _descanso = false;
  bool _finTurno = false;
  Patron? _ultimoPatron;
  Nota? _mantenida;
  int _puntos = 0;
  int _fallos = 0;
  int _inodoro = 0;
  int _avance = 0;
  int _perfectos = 0;
  int _buenos = 0;
  int _racha = 0;
  int _mejorRacha = 0;
  int _jefes = 0;
  Golpe? _ultimo;

  int get puntos => _puntos;
  int get fallos => _fallos;
  bool get terminado => _fallos >= fallosMaximos || _tiempo >= tiempoMaximo;

  /// Sigue la frase de calentamiento: los fallos de ahora no suben el agua.
  bool get calentando => !terminado && _tiempo - compensacion <= _finCalentamiento;

  /// Acabó por tiempo sin desbordarse.
  bool get turnoCompleto => _finTurno && _fallos < fallosMaximos;
  double get tiempo => _tiempo;

  /// Inodoros destapados.
  int get inodoros => _inodoro;
  int get perfectos => _perfectos;
  int get buenos => _buenos;
  int get racha => _racha;
  int get mejorRacha => _mejorRacha;
  int get jefesVencidos => _jefes;
  int get multiplicador => _racha >= rachaX3 ? 3 : (_racha >= rachaX2 ? 2 : 1);

  /// Último resultado, para el destello. Se queda hasta el siguiente.
  Golpe? get ultimo => _ultimo;

  /// El inodoro actual es un atasco gordo.
  bool get esJefe => (_inodoro + 1) % cadaJefe == 0;

  /// Unidades de destape que pide el inodoro actual: cada uno está más tapado; el atasco gordo, la mitad más.
  int get requiere {
    final base = min(28, 6 + 2 * _inodoro);
    return esJefe ? (base * 1.5).round() : base;
  }

  int get avance => _avance;

  /// Duración de un tiempo (pulso) del inodoro actual, en segundos.
  double get compas => max(compasMinimo, compasInicial - compasMenosPorInodoro * _inodoro);

  /// Las notas que quedan en juego (ordenadas por hora). La vista dibuja las cercanas.
  List<Nota> get notas => _notas;

  /// La nota de mantener que está apretada ahora, si hay.
  Nota? get mantenida => _mantenida;

  /// Primera nota sin tocar.
  Nota? get proxima {
    for (final n in _notas) {
      if (n.estado == EstadoNota.pendiente) return n;
    }
    return null;
  }

  /// Lo que pasó desde la última vez que se preguntó.
  List<EventoDestapa> tomarEventos() {
    if (_eventos.isEmpty) return const [];
    final r = List<EventoDestapa>.of(_eventos);
    _eventos.clear();
    return r;
  }

  void avanzar(double dt) {
    if (terminado || dt <= 0) return;
    _tiempo += dt;
    final tj = _tiempo - compensacion;
    final h = _mantenida;
    if (h != null && tj >= h.fin!) _completar(h);
    // Una nota que nadie tocó y ya pasó la ventana buena es un fallo.
    for (final n in _notas) {
      if (terminado || n.t > tj) break;
      if (n.estado == EstadoNota.pendiente && tj - n.t > ventanaBuena) {
        n.estado = EstadoNota.fallada;
        _fallar(gratis: n.calentamiento);
      }
    }
    _notas.removeWhere((n) => (n.estado == EstadoNota.hecha || n.estado == EstadoNota.fallada) && (n.fin ?? n.t) < _tiempo - 0.6);
    if (_tiempo >= tiempoMaximo && !_finTurno) {
      _finTurno = true;
      _evento(const EventoDestapa(Suceso.finTurno));
    }
    if (!terminado) _generar();
  }

  /// Un dedo baja. [desfase]: segundos desde el último cuadro, para no juzgar con el reloj atrasado.
  Golpe toque({double desfase = 0}) {
    if (terminado) return Golpe.fallo;
    final tj = _tiempo + desfase - compensacion;
    Nota? n;
    for (final x in _notas) {
      if (x.t - tj > ventanaBuena) break;
      if (x.estado == EstadoNota.pendiente && (x.t - tj).abs() <= ventanaBuena) {
        n = x;
        break;
      }
    }
    // Toque suelto entre notas, o de más: fallo.
    if (n == null) {
      _fallar(gratis: tj <= _finCalentamiento);
      return Golpe.fallo;
    }
    final g = (n.t - tj).abs() <= ventanaPerfecta ? Golpe.perfecto : Golpe.bueno;
    n.golpe = g;
    if (n.mantener) {
      n.estado = EstadoNota.manteniendo;
      _mantenida = n;
    } else {
      n.estado = EstadoNota.hecha;
    }
    _acertar(g);
    return g;
  }

  /// Se levantan todos los dedos. Soltar una de mantener antes de tiempo es fallo.
  void suelta({double desfase = 0}) {
    final h = _mantenida;
    if (h == null || terminado) return;
    final tj = _tiempo + desfase - compensacion;
    if (tj >= h.fin! - ventanaBuena) {
      _completar(h);
    } else {
      h.estado = EstadoNota.fallada;
      _mantenida = null;
      _fallar(gratis: h.calentamiento);
    }
  }

  void _completar(Nota h) {
    h.estado = EstadoNota.hecha;
    _mantenida = null;
    _puntos += puntosBueno * multiplicador;
    _evento(EventoDestapa(Suceso.mantenido, valor: puntosBueno * multiplicador));
    _empujar(1);
  }

  void _acertar(Golpe g) {
    final mAntes = multiplicador;
    _racha++;
    _mejorRacha = max(_mejorRacha, _racha);
    _ultimo = g;
    final m = multiplicador;
    if (m != mAntes) _evento(EventoDestapa(Suceso.multiplicador, valor: m));
    final perfecto = g == Golpe.perfecto;
    final pts = puntosBueno * m + (perfecto ? puntosPerfecto - puntosBueno : 0);
    _puntos += pts;
    if (perfecto) {
      _perfectos++;
    } else {
      _buenos++;
    }
    _evento(EventoDestapa(Suceso.golpe, golpe: g, valor: pts));
    _empujar(perfecto ? 2 : 1);
  }

  void _empujar(int d) {
    _avance += d;
    if (_avance < requiere) return;
    final jefe = esJefe;
    _puntos += jefe ? puntosJefe : min(15, 4 + _inodoro);
    _inodoro++;
    _avance = 0;
    _descanso = true;
    if (jefe) {
      _jefes++;
      final baja = _fallos > 0;
      if (baja) _fallos--;
      _evento(EventoDestapa(Suceso.jefeVencido, valor: baja ? 1 : 0));
    } else {
      _evento(EventoDestapa(Suceso.destapado, valor: _inodoro));
    }
    if (esJefe) _evento(const EventoDestapa(Suceso.jefe));
  }

  /// [gratis]: fallo del calentamiento; se ve y corta la racha, pero no suma.
  void _fallar({bool gratis = false}) {
    if (_fallos >= fallosMaximos) return;
    if (!gratis) _fallos++;
    _racha = 0;
    _ultimo = Golpe.fallo;
    _evento(EventoDestapa(Suceso.fallo, valor: _fallos));
  }

  void _evento(EventoDestapa e) {
    _eventos.add(e);
    if (_eventos.length > 64) _eventos.removeAt(0);
  }

  // Genera frases hasta que la última empieza más allá de lo que se ve.
  void _generar() {
    while (_proxima - _tiempo < verAntes + 0.4) {
      final b = compas;
      if (_frases > 0 && b < _beatAnterior - 1e-6) _evento(const EventoDestapa(Suceso.masRapido));
      _beatAnterior = b;
      // Después de destapar, medio compás de respiro para la descarga.
      if (_descanso) {
        _descanso = false;
        _proxima += 2 * b;
        continue;
      }
      final p = _elegir();
      final calienta = _frases == 0 && _conCalentamiento;
      for (final (o, d) in p.notas) {
        final n = Nota(_proxima + o * b, fin: d > 0 ? _proxima + (o + d) * b : null, calentamiento: calienta);
        _notas.add(n);
        if (calienta) _finCalentamiento = max(_finCalentamiento, (n.fin ?? n.t) + ventanaBuena);
      }
      _proxima += 4 * b;
      _frases++;
    }
  }

  Patron _elegir() {
    if (_frases == 0) return patronesDestapa.first;
    final jefe = esJefe;
    // Un patrón nuevo se presenta solo, la primera vez, para aprenderlo (en el atasco gordo no: ahí se mezclan).
    if (!jefe) {
      for (final p in patronesDestapa) {
        if (p.desde > 0 && p.desde <= _inodoro && _vistos.add(p.nombre)) return _ultimoPatron = p;
      }
    }
    final pool = [
      for (final p in patronesDestapa)
        if (p.desde <= _inodoro + (jefe ? 2 : 0) && (!jefe || p.pesado)) p,
    ];
    var p = pool[_azar.nextInt(pool.length)];
    if (identical(p, _ultimoPatron) && pool.length > 1) p = pool[_azar.nextInt(pool.length)];
    return _ultimoPatron = p;
  }
}
