// Destapa: medio tiempo en el baño del estadio. Lógica pura (sin Flutter): una fila de inodoros que se tapan al azar,
// el agua sube y si llega al borde se desborda (3 desbordes = fin). Cada atasco se destapa distinto: el mojón con
// toques, el gordo con muchos toques seguidos, el patito deslizando hacia arriba, el celular manteniendo y la
// cucaracha tocándola antes de que se escape. Medio tiempo de 90 s; después viene la prórroga, cada vez más rápida.
// Todo lo aleatorio sale de una semilla y el tiempo de avanzar(dt): con dt fijo es reproducible.

import 'dart:math' as m;

enum TipoAtasco { normal, gordo, patito, celular, cucaracha }

enum Suceso {
  /// Sale un atasco nuevo en [Evento.inodoro] ([Evento.tipo], [Evento.dorado]).
  atasco,

  /// El destapador bajó sobre un atasco. [Evento.valor] = toques que faltan.
  golpe,

  /// El destapador bajó sin efecto (inodoro limpio o patito, que se ríe del destapador).
  golpeVacio,

  /// El mojón gordo se recuperó un toque porque lo dejaste en paz.
  recupera,

  /// El agua sube y burbujea (con enfriamiento por inodoro). [Evento.valor] = agua en %.
  glug,

  /// El agua pasó el 80 %: está a punto de desbordarse.
  alerta,

  /// Descarga. [Evento.valor] = puntos que sumó (ya multiplicados).
  destapado,

  /// Se desbordó. [Evento.valor] = desbordes en total.
  desborde,

  /// Tocaste el celular a lo loco y se hundió más.
  hundido,

  /// La cucaracha saltó fuera del inodoro: se pierde el combo.
  escapa,

  /// Subió el multiplicador. [Evento.valor] = el nuevo.
  combo,

  /// Se perdió un combo de x2 o más.
  comboRoto,

  /// Se suma un inodoro a la fila. [Evento.valor] = cuántos hay ahora.
  nuevoInodoro,

  /// Se acabó el medio tiempo sin perder: empieza la prórroga.
  prorroga,

  /// Fin de la partida.
  fin,
}

class Evento {
  const Evento(this.suceso, {this.inodoro = -1, this.valor = 0, this.tipo, this.dorado = false});
  final Suceso suceso;
  final int inodoro;
  final int valor;
  final TipoAtasco? tipo;
  final bool dorado;

  @override
  String toString() => 'Evento($suceso, $inodoro, $valor, $tipo${dorado ? ', dorado' : ''})';
}

/// Un inodoro de la fila. Lo cambia solo [JuegoDestapa]; la vista lo lee para dibujar.
class Inodoro {
  Inodoro(this.indice, this.espera);
  final int indice;

  /// Nivel del agua: 0 vacío, 1 el borde (se desborda).
  double agua = JuegoDestapa.aguaReposo;
  TipoAtasco? atasco;
  bool dorado = false;

  /// Toques dados al atasco y los que pide (mojón y gordo).
  int golpes = 0;
  int requiere = 0;

  /// Segundos desde que salió el atasco.
  double edad = 0;

  /// Segundos sin tocar el gordo (pasado 1 s se recupera).
  double sinTocar = 0;
  double _recupera = 0;

  /// Agua por segundo que sube con este atasco.
  double subida = 0;

  /// Dedos apretando este inodoro ahora y cuánto lleva el apretón.
  int dedos = 0;
  double apretado = 0;

  /// Celular: segundos sostenidos del celular.
  double sostenido = 0;

  /// Cucaracha: recorrido por el borde (0 sale del agua, 1 salta fuera) y su vida en segundos.
  double cucaracha = 0;
  double vidaCucaracha = 2;

  /// Segundos hasta que se vuelva a tapar (si está limpio).
  double espera;

  /// Charcos que dejó en el piso (uno por desborde).
  int charcos = 0;

  bool alertado = false;
  double _glug = 0;

  /// Es la primera vez que sale este tipo de atasco (la vista muestra la pista más grande).
  bool primeraVez = false;

  bool get tapado => atasco != null;

  /// Avance del destape de 0 a 1 (lo que muestra la barrita).
  double get progreso => switch (atasco) {
        TipoAtasco.normal || TipoAtasco.gordo => requiere == 0 ? 0 : golpes / requiere,
        TipoAtasco.celular => (sostenido / JuegoDestapa.sostenerCelular).clamp(0.0, 1.0),
        TipoAtasco.cucaracha => cucaracha.clamp(0.0, 1.0),
        _ => 0,
      };

  void _limpiar() {
    atasco = null;
    dorado = false;
    golpes = 0;
    requiere = 0;
    edad = 0;
    sinTocar = 0;
    _recupera = 0;
    sostenido = 0;
    cucaracha = 0;
    alertado = false;
    primeraVez = false;
  }
}

class JuegoDestapa {
  JuegoDestapa({int? semilla, this.calentar = true}) : _r = m.Random(semilla) {
    inodoros
      ..add(Inodoro(0, 1.2))
      ..add(Inodoro(1, 3.2));
  }

  final m.Random _r;

  /// Los primeros [calentamiento] s el agua sube lento y no llega al borde. En tests se puede quitar.
  final bool calentar;

  // Contrato del servidor (flags en vivo): puntos ≤ (segundos+1)·14, tope 8000, duración 1.5 s a 1200 s.
  static const puntosPorSegundo = 14;
  static const topePuntos = 8000;

  static const vidas = 3;
  static const medioTiempo = 90.0;
  static const calentamiento = 8.0;

  /// Pitazo final: aunque nadie pierda, la partida termina aquí (muy por debajo de los 1200 s del servidor).
  static const duracionMaxima = 600.0;

  static const aguaReposo = 0.12;
  static const aguaInicio = 0.3;
  static const golpesNormal = 5;
  static const golpesGordo = 12;
  static const sostenerCelular = 0.8;

  /// Un apretón más corto que esto sobre el celular es "a lo loco": lo hunde.
  static const toqueLoco = 0.18;

  /// Cuándo se suma cada inodoro y cuándo aparece cada atasco nuevo (la primera vez sale seguro).
  static const tercerInodoro = 15.0, cuartoInodoro = 38.0;
  static const desdeGordo = 10.0, desdePatito = 20.0, desdeCelular = 30.0, desdeCucaracha = 45.0;
  static const cadaDorado = 30.0;

  /// Puntos base de cada destape (el dorado vale [puntosDorado] sea lo que sea).
  static int puntosBase(TipoAtasco t) => switch (t) {
        TipoAtasco.normal => 1,
        TipoAtasco.gordo => 3,
        TipoAtasco.patito || TipoAtasco.celular || TipoAtasco.cucaracha => 2,
      };
  static const puntosDorado = 5;

  /// Nivel del agua en rojo: avisa y corta la racha.
  static const alertaAgua = 0.8;

  /// Destapes seguidos para x2 y x3.
  static const rachaX2 = 15, rachaX3 = 35;

  double tiempo = 0;
  int puntos = 0;
  int desbordes = 0;
  int racha = 0;
  int mejorRacha = 0;
  int destapados = 0;
  bool terminado = false;
  bool prorroga = false;

  /// Terminó por el pitazo final (no por desbordes).
  bool pitazoFinal = false;

  /// Último inodoro que se desbordó (para explicar por qué perdiste).
  int ultimoDesborde = -1;
  TipoAtasco? tipoUltimoDesborde;

  final inodoros = <Inodoro>[];
  final _eventos = <Evento>[];
  double _proxDorado = cadaDorado;
  final _vistos = <TipoAtasco>{TipoAtasco.normal};

  bool get calentando => calentar && tiempo < calentamiento;
  int get vidasQuedan => m.max(0, vidas - desbordes);
  int get multiplicador => racha >= rachaX3 ? 3 : (racha >= rachaX2 ? 2 : 1);

  /// Barra del combo: avance hacia el siguiente multiplicador (llena en x3).
  double get progresoCombo => racha >= rachaX3 ? 1 : (racha >= rachaX2 ? (racha - rachaX2) / (rachaX3 - rachaX2) : racha / rachaX2);

  /// Segundos que quedan del medio tiempo (0 en la prórroga).
  double get quedaMedio => m.max(0, medioTiempo - tiempo);

  List<Evento> tomarEventos() {
    final l = List<Evento>.of(_eventos);
    _eventos.clear();
    return l;
  }

  void _evento(Suceso s, {int inodoro = -1, int valor = 0, TipoAtasco? tipo, bool dorado = false}) =>
      _eventos.add(Evento(s, inodoro: inodoro, valor: valor, tipo: tipo, dorado: dorado));

  // Ritmo que se aprieta solo, en curva: 1 al empezar, ~0.74 a los 30 s, ~0.55 a los 60 s, ~0.4 al medio tiempo.
  double _ritmo() => m.pow(0.99, tiempo).toDouble();

  // Segundos que tarda el agua en ir del inicio al borde: 6.4 al empezar, ~2.6 al medio tiempo, ~1.9 a los 2 min, tope 1.2.
  double _llenado() => m.max(1.2, 6.4 * _ritmo());

  // Cuánto tarda un inodoro limpio en volver a taparse: 1.5 a 4 s al empezar, ~1 s en la prórroga.
  double _espera() => (1.8 + _r.nextDouble() * 2.7) * m.max(0.25, _ritmo());

  List<TipoAtasco> _disponibles() => [
        TipoAtasco.normal,
        if (tiempo >= desdeGordo) TipoAtasco.gordo,
        if (tiempo >= desdePatito) TipoAtasco.patito,
        if (tiempo >= desdeCelular) TipoAtasco.celular,
        if (tiempo >= desdeCucaracha) TipoAtasco.cucaracha,
      ];

  TipoAtasco _sortear() {
    final d = _disponibles();
    // Lo nuevo sale una vez seguro, para conocerlo.
    for (final t in d) {
      if (!_vistos.contains(t)) return t;
    }
    double peso(TipoAtasco t) => switch (t) {
          TipoAtasco.normal => 5,
          TipoAtasco.gordo => 1.6,
          TipoAtasco.patito => 1.4,
          TipoAtasco.celular => 1.4,
          TipoAtasco.cucaracha => 1.1,
        };
    final total = d.fold<double>(0, (a, t) => a + peso(t));
    var x = _r.nextDouble() * total;
    for (final t in d) {
      x -= peso(t);
      if (x <= 0) return t;
    }
    return TipoAtasco.normal;
  }

  void _tapar(Inodoro i, TipoAtasco t, {bool dorado = false}) {
    // La primera vez de cada atasco sube más lento: hay tiempo de entender qué pide.
    final nuevo = _vistos.add(t) && t != TipoAtasco.normal;
    i.primeraVez = nuevo;
    i._limpiar();
    i.atasco = t;
    i.dorado = dorado;
    i.requiere = t == TipoAtasco.gordo ? golpesGordo : golpesNormal;
    if (t == TipoAtasco.cucaracha) {
      i.vidaCucaracha = nuevo ? 3.2 : m.max(1.3, 2.5 - tiempo * 0.008);
    } else {
      i.agua = m.max(i.agua, aguaInicio);
      final mult = dorado
          ? 1.6
          : switch (t) {
              TipoAtasco.gordo => 0.62,
              TipoAtasco.celular => 0.9,
              _ => 1.0,
            };
      i.subida = (1 - aguaInicio) / _llenado() * mult * (nuevo ? 0.55 : 1);
    }
    i._glug = 0.6;
    _evento(Suceso.atasco, inodoro: i.indice, tipo: t, dorado: dorado);
  }

  void _sumar(int p) {
    final techo = m.min(topePuntos, (tiempo.floor() + 1) * puntosPorSegundo);
    puntos = m.max(0, m.min(techo, puntos + p));
  }

  void _destapar(Inodoro i) {
    final t = i.atasco!;
    final dorado = i.dorado;
    final antes = multiplicador;
    racha++;
    mejorRacha = m.max(mejorRacha, racha);
    destapados++;
    if (multiplicador > antes) _evento(Suceso.combo, valor: multiplicador);
    final pts = (dorado ? puntosDorado : puntosBase(t)) * multiplicador;
    final previo = puntos;
    _sumar(pts);
    _evento(Suceso.destapado, inodoro: i.indice, valor: puntos - previo, tipo: t, dorado: dorado);
    i._limpiar();
    i.espera = _espera();
  }

  void _romperCombo() {
    if (multiplicador > 1) _evento(Suceso.comboRoto);
    racha = 0;
  }

  void _desbordar(Inodoro i) {
    desbordes++;
    i.charcos++;
    ultimoDesborde = i.indice;
    tipoUltimoDesborde = i.atasco;
    _evento(Suceso.desborde, inodoro: i.indice, valor: desbordes, tipo: i.atasco, dorado: i.dorado);
    _romperCombo();
    i._limpiar();
    i.agua = 0.55;
    i.espera = 2.0 + _r.nextDouble();
    if (desbordes >= vidas) _terminar();
  }

  void _terminar() {
    if (terminado) return;
    terminado = true;
    for (final i in inodoros) {
      i.dedos = 0;
    }
    _evento(Suceso.fin, valor: puntos);
  }

  void avanzar(double dt) {
    if (terminado || dt <= 0) return;
    final antes = tiempo;
    tiempo += dt;
    if (antes < tercerInodoro && tiempo >= tercerInodoro) _sumarInodoro();
    if (antes < cuartoInodoro && tiempo >= cuartoInodoro) _sumarInodoro();
    if (antes < medioTiempo && tiempo >= medioTiempo) {
      prorroga = true;
      _evento(Suceso.prorroga);
    }
    if (tiempo >= _proxDorado) {
      final libres = inodoros.where((i) => !i.tapado).toList();
      if (libres.isNotEmpty) {
        _tapar(libres[_r.nextInt(libres.length)], TipoAtasco.normal, dorado: true);
        _proxDorado += cadaDorado;
      }
    }
    for (final i in inodoros) {
      _avanzarInodoro(i, dt);
      if (terminado) return;
    }
    if (tiempo >= duracionMaxima) {
      pitazoFinal = true;
      _terminar();
    }
  }

  void _sumarInodoro() {
    inodoros.add(Inodoro(inodoros.length, 1.4));
    _evento(Suceso.nuevoInodoro, valor: inodoros.length);
  }

  void _avanzarInodoro(Inodoro i, double dt) {
    if (i.dedos > 0) i.apretado += dt;
    final t = i.atasco;
    if (t == null) {
      i.agua += (aguaReposo - i.agua) * m.min(1, dt * 2.5);
      i.espera -= dt;
      if (i.espera <= 0) _tapar(i, _sortear());
      return;
    }
    i.edad += dt;
    if (t == TipoAtasco.cucaracha) {
      i.agua += (aguaReposo - i.agua) * m.min(1, dt * 2.5);
      i.cucaracha += dt / i.vidaCucaracha;
      if (i.cucaracha >= 1) {
        _evento(Suceso.escapa, inodoro: i.indice);
        _romperCombo();
        i._limpiar();
        i.espera = _espera();
      }
      return;
    }
    i.agua += i.subida * dt * (calentando ? 0.55 : 1);
    if (calentando) i.agua = m.min(i.agua, 0.9);
    if (t == TipoAtasco.gordo) {
      i.sinTocar += dt;
      if (i.sinTocar > 1.0 && i.golpes > 0) {
        i._recupera += dt;
        if (i._recupera >= 0.45) {
          i._recupera = 0;
          i.golpes--;
          _evento(Suceso.recupera, inodoro: i.indice, valor: i.requiere - i.golpes);
        }
      }
    }
    if (t == TipoAtasco.celular) {
      if (i.dedos > 0) {
        i.sostenido += dt;
        if (i.sostenido >= sostenerCelular) {
          _destapar(i);
          return;
        }
      } else {
        i.sostenido = m.max(0, i.sostenido - dt * 1.2);
      }
    }
    i._glug -= dt;
    if (i._glug <= 0 && i.agua > 0.35) {
      _evento(Suceso.glug, inodoro: i.indice, valor: (i.agua * 100).round());
      i._glug = 1.5 - i.agua * 0.9;
    }
    if (!i.alertado && i.agua >= alertaAgua) {
      i.alertado = true;
      _evento(Suceso.alerta, inodoro: i.indice);
      // Dejarlo llegar a rojo corta la racha (no en el calentamiento).
      if (!calentando) _romperCombo();
    }
    if (i.agua >= 1) _desbordar(i);
  }

  /// Tapa el inodoro [i] con un atasco elegido (para pruebas y capturas; el juego sortea solo).
  void tapar(int i, TipoAtasco t, {bool dorado = false}) {
    if (terminado || i < 0 || i >= inodoros.length) return;
    _tapar(inodoros[i], t, dorado: dorado);
  }

  Inodoro? _inodoro(int i) => terminado || i < 0 || i >= inodoros.length ? null : inodoros[i];

  /// Un dedo baja sobre el inodoro [i]: un golpe de destapador (o empieza a sostener el celular).
  void bajar(int i) {
    final ino = _inodoro(i);
    if (ino == null) return;
    ino.dedos++;
    ino.apretado = 0;
    switch (ino.atasco) {
      case null:
        _evento(Suceso.golpeVacio, inodoro: i);
      case TipoAtasco.normal || TipoAtasco.gordo:
        ino.golpes++;
        ino.sinTocar = 0;
        ino._recupera = 0;
        ino.agua = m.max(aguaInicio * 0.7, ino.agua - (ino.atasco == TipoAtasco.gordo ? 0.03 : 0.06));
        _evento(Suceso.golpe, inodoro: i, valor: ino.requiere - ino.golpes, tipo: ino.atasco, dorado: ino.dorado);
        if (ino.golpes >= ino.requiere) _destapar(ino);
      case TipoAtasco.patito:
        _evento(Suceso.golpeVacio, inodoro: i, tipo: TipoAtasco.patito);
      case TipoAtasco.celular:
        break;
      case TipoAtasco.cucaracha:
        _destapar(ino);
    }
  }

  /// El dedo se levanta del inodoro [i]. Un apretón cortito sobre el celular lo hunde.
  void soltar(int i) {
    final ino = _inodoro(i);
    if (ino == null) return;
    ino.dedos = m.max(0, ino.dedos - 1);
    if (ino.atasco == TipoAtasco.celular && ino.dedos == 0 && ino.apretado < toqueLoco) {
      ino.sostenido = 0;
      ino.agua = m.min(0.99, ino.agua + 0.07);
      _evento(Suceso.hundido, inodoro: i);
    }
  }

  /// Deslizar hacia arriba sobre el inodoro [i]: saca el patito.
  void deslizar(int i) {
    final ino = _inodoro(i);
    if (ino == null || ino.atasco != TipoAtasco.patito) return;
    _destapar(ino);
  }
}
