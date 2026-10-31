// Motor del Imperio Cagón, fase 1. Dart puro (sin Flutter) para poder probarlo.
// Todo lo que depende del tiempo recibe `ahora` (ms epoch del reloj corregido con el servidor) y el azar viene inyectado.
// La pantalla llama `tick()` ~1 vez por segundo, `pujar()` en cada toque y guarda `toJson()` en la nube.

import 'dart:math';

import 'catalogo.dart';
import 'estado.dart';

export 'catalogo.dart';
export 'estado.dart';

/// Cagada real nueva (el controlador la arma desde `CagadaNueva` de nube.dart).
class CagadaReal {
  final int? tipo;
  final int? peso;
  final DateTime creada;
  const CagadaReal({this.tipo, this.peso, required this.creada});
}

class ResultadoPujo {
  final double ganado;
  final bool epico;
  const ResultadoPujo(this.ganado, this.epico);
}

/// Lo que puede dar un mojón dorado.
enum EfectoDorado { fiebre, lluvia, pujoLoco, constructor }

class ResultadoDorado {
  final EfectoDorado efecto;

  /// MJ que cayeron (solo Lluvia; 0 en los demás).
  final double cantidad;

  /// Cuánto dura (Duration.zero en Lluvia).
  final Duration duracion;

  /// true si lo dobló el Papel doble hoja.
  final bool doble;
  const ResultadoDorado(this.efecto, this.cantidad, this.duracion, this.doble);
}

class ResultadoDestape {
  final String edificio;
  final int toques;
  final int faltan;
  final bool destapado;
  final bool perfecto;

  /// MJ del "¡Destape perfecto!" (5 min de lo que produce ese edificio).
  final double premio;
  const ResultadoDestape(this.edificio, this.toques, this.faltan, this.destapado, this.perfecto, this.premio);
}

class ResultadoOffline {
  /// Tiempo real fuera.
  final double segundosAusente;

  /// Tiempo que contó (con el tope del tanque).
  final double segundosContados;
  final double ganado;

  /// Se llenó el tanque: estuvo fuera más que el tope.
  final bool tanqueLleno;

  /// Contó x1,5 por el buff del tipo 6.
  final bool conBonus;
  const ResultadoOffline(this.segundosAusente, this.segundosContados, this.ganado, this.tanqueLleno, this.conBonus);
}

class ResultadoCagadas {
  final int cantidad;

  /// MJ de cada Descarga, en el orden en que se cagaron.
  final List<double> descargas;

  /// Tipo del buff que quedó activo (el de la cagada más reciente con tipo), o null.
  final int? tipoBuff;

  /// Se abrió con la Fiebre de un mojón dorado activa.
  final bool enFiebre;
  const ResultadoCagadas(this.cantidad, this.descargas, this.tipoBuff, this.enFiebre);

  double get ganado => descargas.fold(0.0, (a, b) => a + b);
}

/// Datos para la pantalla de bienvenida de los veteranos.
class ResumenBienvenida {
  final int cagadas;
  final double multiplicador;
  final int fichas;
  final int candadosAbiertos;

  /// Tenía cagadas antes de abrir el Imperio.
  bool get veterano => cagadas > 0;
  const ResumenBienvenida(this.cagadas, this.multiplicador, this.fichas, this.candadosAbiertos);
}

/// Un efecto para la barra de buffs.
class EfectoActivo {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String efectoEs, efectoEn;

  /// Lo que le queda. null = hasta que se use (Papel doble hoja, offline x1,5).
  final Duration? restante;
  const EfectoActivo(this.id, this.emoji, this.nombreEs, this.nombreEn, this.efectoEs, this.efectoEn, this.restante);
}

// Números de la fase 1 (catálogo, secciones 5 a 7).
const Duration duracionFiebre = Duration(seconds: 77);
const Duration duracionPujoLoco = Duration(seconds: 13);
const Duration duracionConstructor = Duration(seconds: 30);
const Duration duracionDoradoVisible = Duration(seconds: 13);
const Duration duracionDescarga = Duration(minutes: 15);
const Duration premioDestape = Duration(minutes: 5);
const Duration tiempoDestapePerfecto = Duration(seconds: 3);
const int toquesAtasco = 10;
const int minimoParaAtasco = 25;

/// Segundos de juego activo por Atasco, en promedio.
const double segundosPorAtasco = 2 * 3600;
const double probabilidadEpico = 0.02, probabilidadEpicoTipo1 = 0.08;
const double multiplicadorEpico = 10, multiplicadorFiebre = 7, multiplicadorPujoLoco = 777;

/// Tope de la suma de efectos de objetos y del tipo de mojón.
const double topeEfectos = 4;

/// Pesos del mojón dorado: Fiebre, Lluvia, Pujo loco, Constructor (suman 100).
const List<int> pesosDorado = [40, 40, 10, 10];

/// Ausencia mínima para que cuente como offline (y gaste el x1,5 del tipo 6).
const Duration minimoOffline = Duration(minutes: 1);

const Map<String, (String, String, String, String, String)> _textosEfecto = {
  'fiebre_dorada': ('🔥', 'Fiebre', 'Fever', 'Producción x7', 'Production x7'),
  'fiebre_trono': ('💥', 'Fiebre de Trono', 'Throne fever', 'Producción x7', 'Production x7'),
  'pujo_loco': ('🍑', 'Pujo loco', 'Crazy push', 'Pujos x777', 'Pushes x777'),
  'constructor': ('🧱', 'Constructor', 'Builder', 'Edificios a mitad de precio', 'Buildings at half price'),
  'offline_bonus': ('🌋', 'Offline x1,5', 'Offline x1.5', 'El próximo offline cuenta x1,5', 'Next offline counts x1.5'),
};

/// El juego: una `Partida` más las cagadas totales y las Fichas que manda el servidor.
class Imperio {
  final Partida partida;

  /// Cagadas reales históricas (de `profiles.cagadas`). La pone el controlador.
  int cagadas;

  /// Fichas de cagada (las cuenta el servidor). La pone el controlador.
  int fichas;
  final Random _azar;

  Imperio({Partida? partida, this.cagadas = 0, this.fichas = 0, Random? azar})
      : partida = partida ?? Partida(),
        _azar = azar ?? Random();

  /// Arranca desde lo guardado en la nube.
  factory Imperio.desdeJson(Map<String, dynamic>? json, {int cagadas = 0, int fichas = 0, Random? azar}) =>
      Imperio(partida: Partida.desdeJson(json), cagadas: cagadas, fichas: fichas, azar: azar);

  /// Estado para guardar (`'v': 1`).
  Map<String, dynamic> toJson() => partida.toJson();

  Partida get _p => partida;
  double get saldo => _p.saldo;
  double get mjTotal => _p.mjTotal;

  /// Unidades que tienes de un edificio.
  int cantidad(String id) => _p.edificios[id] ?? 0;
  bool mejoraComprada(String id) => _p.mejoras.contains(id);
  bool tieneLogro(String id) => _p.logros.contains(id);

  /// Consumibles guardados de un objeto.
  int enInventario(String id) => _p.inventario[id] ?? 0;
  Atasco? get atasco => _p.atasco;

  void _ganar(double mj) {
    if (mj.isNaN || mj <= 0) return;
    _p.saldo += mj;
    _p.mjTotal += mj;
  }

  bool _activo(String id, int ahora) => (_p.efectos[id] ?? 0) > ahora;
  void _extender(String id, int ahora, Duration d) {
    final fin = ahora + d.inMilliseconds;
    if ((_p.efectos[id] ?? 0) < fin) _p.efectos[id] = fin;
  }

  /// Tipo de mojón con buff activo (1 a 7), o null.
  int? tipoActivo(int ahora) => _p.tipoBuff != null && _p.tipoBuffHasta > ahora ? _p.tipoBuff : null;
  bool robotActivo(int ahora) => _p.robotHasta > ahora;

  /// Hay Fiebre (de mojón dorado o de Trono): producción x7.
  bool enFiebre(int ahora) => _activo('fiebre_dorada', ahora) || _activo('fiebre_trono', ahora);

  // ---------- Multiplicadores ----------

  /// +2% por cagada hasta 150 (x4), luego +0,5% cada una.
  double get multiplicadorCagadas => multiplicadorPorCagadas(cagadas);

  /// +1% por logro (+1,5% con Incienso de lavanda).
  double get multiplicadorLogros {
    final n = _p.logros.where((id) => logroPorId(id) != null).length;
    return 1 + n * (mejoraComprada('lavanda') ? 0.015 : 0.01);
  }

  /// Cagadas x logros: lo que no se acaba.
  double get multiplicadorPermanente => multiplicadorCagadas * multiplicadorLogros;

  /// Suma de efectos temporales sobre la producción (objetos + tipo), tope x4. No incluye la Fiebre.
  double multiplicadorProduccionTemporal(int ahora) {
    var s = 1.0;
    if (_activo('cagada_fresca', ahora)) s += 1;
    if (_activo('ambientador', ahora)) s += 0.25;
    final t = tipoActivo(ahora);
    if (t == 4) s += 1;
    if (t == 7) s += 2;
    return s.clamp(0.5, topeEfectos).toDouble();
  }

  /// Suma de efectos temporales sobre el pujo (objetos + tipo), tope x4. No incluye el Pujo loco.
  double multiplicadorPujoTemporal(int ahora) {
    var s = 1.0;
    if (_activo('laxante', ahora)) s += 1;
    final t = tipoActivo(ahora);
    if (t == 2 || t == 4) s += 1;
    if (t == 7) s -= 0.5;
    return s.clamp(0.5, topeEfectos).toDouble();
  }

  // ---------- Producción ----------

  double _produccionCruda(String id) {
    final e = edificioPorId(id);
    final n = cantidad(id);
    if (e == null || !e.fase1 || n <= 0) return 0;
    var x = 1.0;
    for (final (nivel, _) in nivelesMejoraEdificio) {
      if (mejoraComprada(idMejoraEdificio(id, nivel))) x *= 2;
    }
    return n * e.mpsBase * x;
  }

  /// MJ/s de un edificio con todos los efectos. 0 si está atascado.
  double mpsEdificio(String id, int ahora) {
    if (_p.atasco?.edificio == id) return 0;
    return _produccionCruda(id) * multiplicadorPermanente * multiplicadorProduccionTemporal(ahora) * (enFiebre(ahora) ? multiplicadorFiebre : 1);
  }

  /// MJ/s total con todos los efectos (lo que se suma en cada tick).
  double mps(int ahora) {
    var s = 0.0;
    for (final e in edificiosFase1) {
      s += mpsEdificio(e.id, ahora);
    }
    return s;
  }

  /// MJ/s sin efectos temporales (sin Fiebre, objetos ni tipo). Es la base de precios de objetos, Descarga, Lluvia y offline.
  /// Con `contarAtasco: false` el edificio atascado cuenta como si produjera.
  double mpsSinEfectos({bool contarAtasco = true}) {
    var s = 0.0;
    for (final e in edificiosFase1) {
      if (contarAtasco && _p.atasco?.edificio == e.id) continue;
      s += _produccionCruda(e.id);
    }
    return s * multiplicadorPermanente;
  }

  /// MJ de un pujo normal (sin épico).
  double valorPujo(int ahora) {
    var base = 1.0;
    for (final id in mejorasClicX2) {
      if (mejoraComprada(id)) base *= 2;
    }
    final pct = 0.01 * mejorasClicPct.where(mejoraComprada).length;
    final v = (base + pct * mps(ahora)) * multiplicadorPujoTemporal(ahora);
    return _activo('pujo_loco', ahora) ? v * multiplicadorPujoLoco : v;
  }

  /// Un toque al Mojón. 2% de pujo épico (8% con buff tipo 1), que vale x10.
  ResultadoPujo pujar(int ahora) {
    final prob = tipoActivo(ahora) == 1 ? probabilidadEpicoTipo1 : probabilidadEpico;
    final epico = _azar.nextDouble() < prob;
    final ganado = valorPujo(ahora) * (epico ? multiplicadorEpico : 1);
    _ganar(ganado);
    _p.pujos++;
    if (epico) _p.epicos++;
    final r = _p.pujosRecientes..add(ahora);
    if (r.length > Partida.maxPujosRecientes) r.removeRange(0, r.length - Partida.maxPujosRecientes);
    if (r.length == Partida.maxPujosRecientes && ahora - r.first <= 10000) {
      _p.nalgazos++;
      r.clear();
    }
    return ResultadoPujo(ganado, epico);
  }

  // ---------- Edificios ----------

  /// Su candado de cagadas ya está abierto (y es de la fase 1).
  bool edificioAbierto(String id) {
    final e = edificioPorId(id);
    return e != null && e.fase1 && cagadas >= e.candado;
  }

  /// Sale en la lista: abierto o con su candado. Los de después de la fase 1 nunca.
  bool edificioVisible(String id) => edificioPorId(id)?.fase1 ?? false;

  /// Se muestra como "???": no tienes ninguno y no has ganado la mitad de su precio base.
  bool edificioMisterioso(String id) {
    final e = edificioPorId(id);
    return e != null && e.fase1 && cantidad(id) == 0 && _p.mjTotal < e.precioBase / 2;
  }

  /// Descuento de precio activo: tipo 3 (-10%) y Constructor (-50%).
  double factorPrecioEdificios(int ahora) => (tipoActivo(ahora) == 3 ? 0.9 : 1) * (_activo('constructor', ahora) ? 0.5 : 1);

  /// Precio de la siguiente unidad: base x 1,15^n con descuentos.
  double precioEdificio(String id, int ahora) => precioEdificioVarios(id, 1, ahora);

  /// Precio de las siguientes `n` unidades juntas. Infinito si el edificio no existe.
  double precioEdificioVarios(String id, int n, int ahora) {
    final e = edificioPorId(id);
    if (e == null || n <= 0) return n <= 0 ? 0 : double.infinity;
    final f = factorPrecioEdificios(ahora);
    final tiene = cantidad(id);
    var s = 0.0;
    for (var k = 0; k < n; k++) {
      s += (e.precioBase * pow(1.15, tiene + k) * f).ceilToDouble();
    }
    return s;
  }

  /// Cuántas unidades te alcanzan ahora (para el botón MAX).
  int maxComprable(String id, int ahora) {
    if (!edificioAbierto(id)) return 0;
    var n = 0;
    var s = 0.0;
    final e = edificioPorId(id)!;
    final f = factorPrecioEdificios(ahora);
    while (n < 10000) {
      final p = (e.precioBase * pow(1.15, cantidad(id) + n) * f).ceilToDouble();
      if (s + p > _p.saldo) break;
      s += p;
      n++;
    }
    return n;
  }

  bool comprarEdificio(String id, int ahora) => comprarEdificioVarios(id, 1, ahora);

  /// Compra `n` unidades si el candado está abierto y alcanza el saldo.
  bool comprarEdificioVarios(String id, int n, int ahora) {
    if (n <= 0 || !edificioAbierto(id)) return false;
    final precio = precioEdificioVarios(id, n, ahora);
    if (precio > _p.saldo) return false;
    _p.saldo -= precio;
    _p.edificios[id] = cantidad(id) + n;
    return true;
  }

  // ---------- Mejoras ----------

  bool _mejoraPuedeSalir(Mejora m) => !mejoraComprada(m.id) && (m.edificio == null || edificioAbierto(m.edificio!)) && m.condicion(_p);

  /// Mejoras que se pueden comprar (condición cumplida, no compradas, edificio abierto), de la más barata a la más cara.
  List<Mejora> mejorasDisponibles() => mejoras.where(_mejoraPuedeSalir).toList()..sort((a, b) => a.precio.compareTo(b.precio));

  bool comprarMejora(String id) {
    final m = mejoraPorId(id);
    if (m == null || !_mejoraPuedeSalir(m) || m.precio > _p.saldo) return false;
    _p.saldo -= m.precio;
    _p.mejoras.add(id);
    return true;
  }

  // ---------- Objetos ----------

  /// Su candado está abierto. El Robot además pide haber visto el primer Atasco.
  bool objetoAbierto(String id) {
    final o = objetoPorId(id);
    return o != null && cagadas >= o.candado && (!o.pideAtasco || _p.vioPrimerAtasco);
  }

  /// Precio en MJ: minutos x MJ/s sin efectos x 60, mínimo 100. La Cagada fresca da 0 (se paga con una Ficha).
  double precioObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null) return double.infinity;
    if (o.tipo == TipoObjeto.ficha) return 0;
    return max(100.0, (o.minutosPrecio * 60 * mpsSinEfectos()).ceilToDouble());
  }

  /// Lo que falta para poder usar (consumible) o alquilar (Robot) de nuevo. null = ya se puede.
  Duration? esperaRestante(String id, int ahora) {
    final fin = _p.esperas[id] ?? 0;
    return fin > ahora ? Duration(milliseconds: fin - ahora) : null;
  }

  /// Compra con MJ. Consumible: al inventario (hasta 5). Robot: se activa ya; si sigue activo suma 30 min, hasta 1 h en total.
  bool comprarObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo == TipoObjeto.ficha || !objetoAbierto(id)) return false;
    final precio = precioObjeto(id, ahora);
    if (precio > _p.saldo) return false;
    if (o.tipo == TipoObjeto.consumible) {
      if (enInventario(id) >= o.maxInventario) return false;
      _p.inventario[id] = enInventario(id) + 1;
    } else {
      final dur = o.duracion!.inMilliseconds;
      if (robotActivo(ahora)) {
        final fin = min(_p.robotHasta + dur, ahora + topeAlquiler.inMilliseconds);
        if (fin <= _p.robotHasta) return false;
        _p.robotHasta = fin;
      } else {
        if (esperaRestante(id, ahora) != null) return false;
        _p.robotHasta = ahora + dur;
        if (o.espera != null) _p.esperas[id] = ahora + o.espera!.inMilliseconds;
      }
    }
    _p.saldo -= precio;
    return true;
  }

  /// Usa un consumible del inventario si no hay espera. Papel doble hoja: deja pendiente el doble del próximo dorado.
  bool usarObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo != TipoObjeto.consumible || enInventario(id) <= 0 || esperaRestante(id, ahora) != null) return false;
    if (o.duracion == null) {
      if (_p.papelDoble) return false;
      _p.papelDoble = true;
    } else {
      _extender(id, ahora, o.duracion!);
    }
    _p.inventario[id] = enInventario(id) - 1;
    if (_p.inventario[id]! <= 0) _p.inventario.remove(id);
    if (o.espera != null) _p.esperas[id] = ahora + o.espera!.inMilliseconds;
    return true;
  }

  /// Cagada fresca: producción x2 por 1 h (si ya estaba, suma 1 h). El controlador ya gastó la Ficha en el servidor.
  void activarCagadaFresca(int ahora) {
    final dur = objetoPorId('cagada_fresca')!.duracion!.inMilliseconds;
    _p.efectos['cagada_fresca'] = max(_p.efectos['cagada_fresca'] ?? 0, ahora) + dur;
    if (fichas > 0) fichas--;
  }

  /// Efectos para la barra de buffs, del que menos le queda al que más.
  List<EfectoActivo> efectosActivos(int ahora) {
    final r = <EfectoActivo>[];
    Duration resta(int fin) => Duration(milliseconds: fin - ahora);
    for (final MapEntry(key: id, value: fin) in _p.efectos.entries) {
      if (fin <= ahora) continue;
      final t = _textosEfecto[id];
      if (t != null) {
        r.add(EfectoActivo(id, t.$1, t.$2, t.$3, t.$4, t.$5, resta(fin)));
      } else if (objetoPorId(id) case final o?) {
        r.add(EfectoActivo(id, o.emoji, o.nombreEs, o.nombreEn, o.descEs, o.descEn, resta(fin)));
      }
    }
    if (robotActivo(ahora)) {
      final o = objetoPorId('robot')!;
      r.add(EfectoActivo('robot', o.emoji, o.nombreEs, o.nombreEn, o.descEs, o.descEn, resta(_p.robotHasta)));
    }
    final t = tipoActivo(ahora);
    if (t != null && t != 6) {
      final b = buffsTipo[t]!;
      r.add(EfectoActivo('tipo_$t', b.emoji, b.nombreEs, b.nombreEn, b.efectoEs, b.efectoEn, resta(_p.tipoBuffHasta)));
    }
    r.sort((a, b) => a.restante!.compareTo(b.restante!));
    if (_p.papelDoble) {
      final o = objetoPorId('papel')!;
      r.add(EfectoActivo('papel', o.emoji, o.nombreEs, o.nombreEn, o.descEs, o.descEn, null));
    }
    if (_p.offlineBonus) {
      final x = _textosEfecto['offline_bonus']!;
      r.add(EfectoActivo('offline_bonus', x.$1, x.$2, x.$3, x.$4, x.$5, null));
    }
    return r;
  }

  // ---------- Tick ----------

  /// Avanza el juego. `segundos` = tiempo activo desde el último tick (se recorta a 1).
  /// Suma producción, vence efectos, saca mojones dorados y Atascos. Devuelve los logros nuevos (para los avisos).
  List<Logro> tick(int ahora, double segundos) {
    final s = segundos.isNaN ? 0.0 : segundos.clamp(0.0, 1.0).toDouble();
    if (s > 0) _ganar(mps(ahora) * s);

    _p.efectos.removeWhere((_, fin) => fin <= ahora);
    if (_p.tipoBuff != null && _p.tipoBuffHasta <= ahora) _p.tipoBuff = null;
    if (_p.dorado != null && _p.dorado!.hasta <= ahora) _p.dorado = null;

    // Mojón dorado: la cuenta regresiva corre solo con la app abierta y sin otro dorado en pantalla.
    if (_p.segHastaDorado < 0) {
      _programarDorado(ahora);
    } else if (_p.dorado == null) {
      _p.segHastaDorado -= s;
      if (_p.segHastaDorado <= 0) {
        final dur = duracionDoradoVisible.inMilliseconds * (mejoraComprada('brillo') ? 2 : 1);
        _p.dorado = DoradoVisible(ahora, ahora + dur, 0.1 + 0.8 * _azar.nextDouble(), 0.1 + 0.8 * _azar.nextDouble());
        _programarDorado(ahora);
      }
    }

    // Atascos: ~1 cada 2 h activas, uno a la vez, en un edificio con 25 o más.
    if (_p.atasco == null && s > 0) {
      final candidatos = [for (final e in edificiosFase1) if (cantidad(e.id) >= minimoParaAtasco) e.id];
      if (candidatos.isNotEmpty && _azar.nextDouble() < s / segundosPorAtasco) {
        _p.atasco = Atasco(candidatos[_azar.nextInt(candidatos.length)], ahora);
        _p.vioPrimerAtasco = true;
      }
    }
    if (_p.atasco != null && robotActivo(ahora)) {
      _p.atasco = null;
      _p.destapes++;
    }

    _p.ultimaVez = ahora;
    return revisarLogros();
  }

  void _programarDorado(int ahora) {
    final rapido = mejoraComprada('iman') || tipoActivo(ahora) == 5;
    _p.segHastaDorado = (300 + 600 * _azar.nextDouble()) / (rapido ? 2 : 1);
  }

  /// Marca los logros que se cumplen y devuelve los nuevos.
  List<Logro> revisarLogros() {
    final m = mpsSinEfectos();
    final nuevos = <Logro>[];
    for (final l in logros) {
      if (!_p.logros.contains(l.id) && l.condicion(_p, m)) {
        _p.logros.add(l.id);
        nuevos.add(l);
      }
    }
    return nuevos;
  }

  // ---------- Mojón dorado ----------

  /// El dorado en pantalla, o null.
  DoradoVisible? dorado(int ahora) {
    final d = _p.dorado;
    return d != null && ahora < d.hasta ? d : null;
  }

  /// Qué efecto toca para una tirada de 0 a 99 (pesos 40/40/10/10).
  static EfectoDorado efectoPorTirada(int tirada) {
    var acum = 0;
    for (var i = 0; i < pesosDorado.length; i++) {
      acum += pesosDorado[i];
      if (tirada < acum) return EfectoDorado.values[i];
    }
    return EfectoDorado.values.last;
  }

  /// Toca el dorado visible. null si no hay. El Papel doble hoja dobla la Lluvia y las duraciones.
  ResultadoDorado? tocarDorado(int ahora) {
    if (dorado(ahora) == null) return null;
    _p.dorado = null;
    _p.dorados++;
    final doble = _p.papelDoble;
    _p.papelDoble = false;
    final k = doble ? 2 : 1;
    final efecto = efectoPorTirada(_azar.nextInt(100));
    switch (efecto) {
      case EfectoDorado.fiebre:
        _extender('fiebre_dorada', ahora, duracionFiebre * k);
        return ResultadoDorado(efecto, 0, duracionFiebre * k, doble);
      case EfectoDorado.lluvia:
        final mj = (min(0.15 * _p.saldo, duracionDescarga.inSeconds * mpsSinEfectos()) + 13) * k;
        _ganar(mj);
        return ResultadoDorado(efecto, mj, Duration.zero, doble);
      case EfectoDorado.pujoLoco:
        _extender('pujo_loco', ahora, duracionPujoLoco * k);
        return ResultadoDorado(efecto, 0, duracionPujoLoco * k, doble);
      case EfectoDorado.constructor:
        _extender('constructor', ahora, duracionConstructor * k);
        return ResultadoDorado(efecto, 0, duracionConstructor * k, doble);
    }
  }

  // ---------- Atasco ----------

  /// Un toque al destapador. null si no hay Atasco. Al toque 10 se destapa; en menos de 3 s es perfecto (5 min de ese edificio).
  ResultadoDestape? tocarAtasco(int ahora) {
    final a = _p.atasco;
    if (a == null) return null;
    a.toques++;
    if (a.toques < toquesAtasco) return ResultadoDestape(a.edificio, a.toques, toquesAtasco - a.toques, false, false, 0);
    final perfecto = ahora - a.desde < tiempoDestapePerfecto.inMilliseconds;
    _p.atasco = null;
    _p.destapes++;
    var premio = 0.0;
    if (perfecto) {
      _p.destapesPerfectos++;
      premio = _produccionCruda(a.edificio) * multiplicadorPermanente * premioDestape.inSeconds;
      _ganar(premio);
    }
    return ResultadoDestape(a.edificio, a.toques, 0, true, perfecto, premio);
  }

  // ---------- Offline ----------

  /// Tope offline: 2 h, 4 h o 8 h según los tanques.
  Duration get topeOffline =>
      mejoraComprada('tanque_8') ? const Duration(hours: 8) : (mejoraComprada('tanque_4') ? const Duration(hours: 4) : const Duration(hours: 2));

  /// Qué parte cuenta offline: 25%, 50% o 75% según las válvulas.
  double get porcentajeOffline => mejoraComprada('valvula_75') ? 0.75 : (mejoraComprada('valvula_50') ? 0.5 : 0.25);

  /// Cobra el tiempo fuera (sin efectos temporales, sin Atascos ni dorados). x1,5 si quedó el buff del tipo 6 (y se gasta).
  ResultadoOffline aplicarOffline(int desdeMs, int ahoraMs) {
    final ausente = max(0, ahoraMs - desdeMs) / 1000.0;
    final tope = topeOffline.inSeconds.toDouble();
    _p.ultimaVez = ahoraMs;
    _p.dorado = null;
    _p.atasco?.desde = ahoraMs; // vuelve a verse ahora
    if (ausente < minimoOffline.inSeconds) return ResultadoOffline(ausente, 0, 0, false, false);
    final contados = min(ausente, tope);
    final bonus = _p.offlineBonus;
    _p.offlineBonus = false;
    final ganado = contados * mpsSinEfectos(contarAtasco: false) * porcentajeOffline * (bonus ? 1.5 : 1);
    _ganar(ganado);
    return ResultadoOffline(ausente, contados, ganado, ausente >= tope, bonus);
  }

  // ---------- Cagadas reales ----------

  /// Cobra cagadas reales nuevas: una Descarga por cada una (15 min x (1 + 0,1 x peso)), una sola Fiebre de Trono
  /// y el buff del tipo más reciente por 1 h. Las Fichas no cambian aquí (las da el servidor).
  ResultadoCagadas aplicarCagadas(List<CagadaReal> nuevas, int ahora) {
    if (nuevas.isEmpty) return const ResultadoCagadas(0, [], null, false);
    final orden = [...nuevas]..sort((a, b) => a.creada.compareTo(b.creada));
    final enFiebreDorada = _activo('fiebre_dorada', ahora);
    final base = duracionDescarga.inSeconds * mpsSinEfectos(contarAtasco: false);
    final descargas = <double>[];
    for (final c in orden) {
      final peso = (c.peso ?? 0).clamp(0, 5);
      final mj = base * (1 + 0.1 * peso);
      _ganar(mj);
      descargas.add(mj);
    }
    _p.descargas += orden.length;
    if (enFiebreDorada) _p.enFiebre++;
    _extender('fiebre_trono', ahora, duracionFiebre);
    int? tipo;
    for (final c in orden.reversed) {
      if (c.tipo != null && buffsTipo.containsKey(c.tipo)) {
        tipo = c.tipo;
        break;
      }
    }
    if (tipo != null) {
      _p.tipoBuff = tipo;
      _p.tipoBuffHasta = ahora + duracionBuffTipo.inMilliseconds;
      if (tipo == 6) _p.offlineBonus = true;
    }
    return ResultadoCagadas(orden.length, descargas, tipo, enFiebreDorada);
  }

  // ---------- Veteranos ----------

  /// Lo que trae un veterano: cagadas, multiplicador, Fichas y candados abiertos.
  ResumenBienvenida bienvenida() => ResumenBienvenida(cagadas, multiplicadorCagadas, fichas, candadosAbiertos(cagadas));
}
