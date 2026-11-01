// Motor del Imperio Cagón, fase 1. Dart puro (sin Flutter) para poder probarlo.
// Todo lo que depende del tiempo recibe `ahora` (ms epoch del reloj corregido con el servidor) y el azar viene inyectado.
// La pantalla llama `tick()` ~1 vez por segundo, `pujar()` en cada toque y guarda `toJson()` en la nube.

import 'dart:math';

import 'catalogo.dart';
import 'esteticas.dart';
import 'estado.dart';
import 'racha_imperio.dart';

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
// La probabilidad y el valor del pujo épico salen de los ajustes (`epicoBase`, `epicoPorDedo`, `epicoTope`, `epicoTipo1`, `epicoMultiplicador`).
const double multiplicadorFiebre = 7, multiplicadorPujoLoco = 777;

/// Pujos por segundo que se suponen al calcular el ritmo que se manda al guardar. Generoso a propósito: el antitrampa
/// del servidor no debe rechazar a nadie que puje rápido.
const double pujosPorSegundoRitmo = 15;

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
/// Efectos que se quedan al jalar la cadena: vienen de cagadas reales o Ciruelas, no de MJ.
const Set<String> efectosQueSobrevivenJalada = {'cagada_fresca', 'fiebre_trono'};

/// Rollos de Oro que dan `mj` MJ históricos: piso((mj / divisor) ^ exponente). El 1e-9 tapa el error de coma flotante
/// (que 8e9 / 1e9 elevado a 1/3 dé 1,9999999 en vez de 2).
int rollosPorMj(double mj, Ajustes a) {
  if (mj <= 0 || a.cadenaDivisor <= 0) return 0;
  final r = pow(mj / a.cadenaDivisor, a.cadenaExponente).toDouble();
  if (!r.isFinite) return 1 << 52;
  return min((r + 1e-9).floor(), 1 << 52);
}

/// MJ históricos para tener `rollos` rollos: divisor × rollos ^ (1 / exponente).
double mjParaRollos(int rollos, Ajustes a) => a.cadenaDivisor * pow(rollos, 1 / a.cadenaExponente).toDouble();

class Imperio {
  final Partida partida;

  /// Cagadas reales históricas (de `profiles.cagadas`). La pone el controlador.
  int cagadas;

  /// Fichas de cagada (las cuenta el servidor). La pone el controlador.
  int fichas;

  /// Ciruelas 🫐, la moneda premium (las cuenta el servidor). La pone el controlador.
  int ciruelas;

  /// Estéticas premium compradas (ids de `esteticas`; las guarda el servidor). Solo suben la suerte de las Ciruelas.
  Set<String> esteticas;

  /// Números que vienen de los flags remotos (por defecto, los de siempre).
  final Ajustes ajustes;
  final Random _azar;

  Imperio({Partida? partida, this.cagadas = 0, this.fichas = 0, this.ciruelas = 0, Set<String>? esteticas, Random? azar,
      this.ajustes = Ajustes.porDefecto})
      : partida = partida ?? Partida(),
        esteticas = esteticas ?? {},
        _azar = azar ?? Random();

  /// Arranca desde lo guardado en la nube.
  factory Imperio.desdeJson(Map<String, dynamic>? json,
          {int cagadas = 0, int fichas = 0, int ciruelas = 0, Set<String>? esteticas, Random? azar, Ajustes ajustes = Ajustes.porDefecto}) =>
      Imperio(
          partida: Partida.desdeJson(json), cagadas: cagadas, fichas: fichas, ciruelas: ciruelas, esteticas: esteticas, azar: azar, ajustes: ajustes);

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

  /// +2% por cagada hasta 150 (x4), luego +0,5% cada una (el 2% sale de los ajustes).
  double get multiplicadorCagadas => multiplicadorPorCagadas(cagadas, ajustes.cagadaBonoPct);

  /// +1% por logro (+1,5% con Incienso de lavanda).
  double get multiplicadorLogros {
    final n = _p.logros.where((id) => logroPorId(id) != null).length;
    return 1 + n * (mejoraComprada('lavanda') ? 0.015 : 0.01);
  }

  /// +`ajustes.rolloPct` por cada Rollo de Oro (jalar la cadena). No se pierde nunca.
  double get multiplicadorRollos => 1 + _p.rollos * ajustes.rolloPct;

  /// Comodidad del baño: 1 + la suma de lo que da cada adorno comprado (hasta x1,28).
  double get multiplicadorComodidad {
    var s = 1.0;
    comodidadAdornos.forEach((id, pct) {
      if (mejoraComprada(id)) s += pct;
    });
    return s;
  }

  /// Cagadas x logros x rollos x comodidad: lo que no se acaba.
  double get multiplicadorPermanente => multiplicadorCagadas * multiplicadorLogros * multiplicadorRollos * multiplicadorComodidad;

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
    if (e == null || n <= 0) return 0;
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

  /// MJ/s total con todos los efectos (lo que se suma en cada tick). No incluye al Dedo: él suma por pujo.
  double mps(int ahora) {
    var s = 0.0;
    for (final e in edificios) {
      s += mpsEdificio(e.id, ahora);
    }
    return s;
  }

  /// MJ/s sin efectos temporales (sin Fiebre, objetos ni tipo). Es la base de precios de objetos, Descarga, Lluvia y offline.
  /// Con `contarAtasco: false` el edificio atascado cuenta como si produjera.
  double mpsSinEfectos({bool contarAtasco = true}) {
    var s = 0.0;
    for (final e in edificios) {
      if (contarAtasco && _p.atasco?.edificio == e.id) continue;
      s += _produccionCruda(e.id);
    }
    return s * multiplicadorPermanente;
  }

  /// x2 por cada mejora de clic x2 comprada (Guantes, Faja, Dedo de acero).
  double get _multiplicadorClic {
    var x = 1.0;
    for (final id in mejorasClicX2) {
      if (mejoraComprada(id)) x *= 2;
    }
    return x;
  }

  /// MJ que suman los Dedos a cada pujo, sin x2 de clic ni efectos: dedos × `ajustes.dedoPujo` × 2 por cada mejora de nivel del Dedo.
  double get aporteDedos {
    final n = cantidad('dedo');
    if (n <= 0) return 0;
    var x = 1.0;
    for (final (nivel, _) in nivelesMejoraEdificio) {
      if (mejoraComprada(idMejoraEdificio('dedo', nivel))) x *= 2;
    }
    return n * ajustes.dedoPujo * x;
  }

  /// Parte del MJ/s que suman al pujo las mejoras de % compradas; con `edificio`, solo las de ese edificio.
  double _pctPujo([String? edificio]) {
    var s = 0.0;
    for (final MapEntry(key: id, value: pct) in mejorasClicPct.entries) {
      if (!mejoraComprada(id)) continue;
      if (edificio == null || mejoraPorId(id)?.edificio == edificio) s += pct;
    }
    return s;
  }

  double _conEfectosPujo(double v, int ahora) {
    final t = v * multiplicadorPujoTemporal(ahora);
    return _activo('pujo_loco', ahora) ? t * multiplicadorPujoLoco : t;
  }

  /// MJ de un pujo normal (sin épico): ((1 + aporteDedos) × 2^x2 de clic × rollos + % × MJ/s) × efectos temporales, x777 en
  /// Pujo loco. El % de MJ/s ya trae los rollos dentro, por eso solo la parte del clic se multiplica por `multiplicadorRollos`.
  double valorPujo(int ahora) =>
      _conEfectosPujo((1 + aporteDedos) * _multiplicadorClic * multiplicadorRollos + _pctPujo() * mps(ahora), ahora);

  /// Lo que un edificio suma a cada pujo, con los mismos efectos que `valorPujo` (para el "+N /pujo" de su fila).
  /// Dedo: sus dedos (con los x2 de clic) y Respiración/Mano de Dios. Baño, camión, planta: sus mejoras de %. La suma de
  /// todas las filas más el pujo base (1 × 2^x2) da `valorPujo`.
  double pujoEdificio(String id, int ahora) {
    var v = _pctPujo(id) * mps(ahora);
    if (id == 'dedo') v += aporteDedos * _multiplicadorClic * multiplicadorRollos;
    return v == 0 ? 0 : _conEfectosPujo(v, ahora);
  }

  /// Probabilidad de que un pujo sea épico: base + un poco por Dedo, con tope. El buff tipo 1 la multiplica (x3) y dobla el tope.
  double probabilidadEpicoActual(int ahora) {
    final a = ajustes;
    final p = a.epicoBase + a.epicoPorDedo * max(0, cantidad('dedo'));
    if (tipoActivo(ahora) == 1) return min(p * a.epicoTipo1, a.epicoTope * 2);
    return min(p, a.epicoTope);
  }

  /// Ritmo que se manda al guardar (`p_mps`, lo usa el servidor para el antitrampa): lo mayor entre el MJ/s sin efectos y
  /// 15 pujos por segundo sin efectos. Así quien vive del Dedo no queda con un ritmo de 0 que le rechace el guardado.
  double ritmoEfectivo() {
    final m = mpsSinEfectos();
    final pujo = (1 + aporteDedos) * _multiplicadorClic * multiplicadorRollos + _pctPujo() * m;
    return max(m, pujo * pujosPorSegundoRitmo);
  }

  /// Un toque al Mojón. Puede salir épico (`probabilidadEpicoActual`), que vale `ajustes.epicoMultiplicador` (x10).
  ResultadoPujo pujar(int ahora) {
    final epico = _azar.nextDouble() < probabilidadEpicoActual(ahora);
    final ganado = valorPujo(ahora) * (epico ? ajustes.epicoMultiplicador : 1);
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

  /// Se puede comprar: su candado de cagadas está abierto y tienes los Rollos de Oro que pide (0 en la fase 1).
  bool edificioAbierto(String id) {
    final e = edificioPorId(id);
    return e != null && cagadas >= e.candado && _p.rollos >= e.rollos;
  }

  /// Sale en la lista: los de la fase 1 siempre (abiertos o con su candado); los de la fase 2 cuando ya tienes sus rollos.
  bool edificioVisible(String id) {
    final e = edificioPorId(id);
    return e != null && (e.fase1 || _p.rollos >= e.rollos);
  }

  /// Se muestra como "???": no tienes ninguno y no has ganado la mitad de su precio base.
  bool edificioMisterioso(String id) {
    final e = edificioPorId(id);
    return e != null && cantidad(id) == 0 && _p.mjTotal < e.precioBase / 2;
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
      s += (e.precioBase * pow(ajustes.precioCrecimiento, tiene + k) * f).ceilToDouble();
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
      final p = (e.precioBase * pow(ajustes.precioCrecimiento, cantidad(id) + n) * f).ceilToDouble();
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
  List<Mejora> mejorasDisponibles() => _ordenadas(mejoras.where(_mejoraPuedeSalir));

  List<Mejora> _ordenadas(Iterable<Mejora> ms) => ms.toList()..sort((a, b) => precioMejora(a).compareTo(precioMejora(b)));

  /// Mejoras comprables de un edificio (las del Dedo incluyen las de clic), de la más barata a la más cara.
  List<Mejora> mejorasDeEdificio(String id) => _ordenadas(mejoras.where((m) => m.edificio == id && _mejoraPuedeSalir(m)));

  /// Mejoras comprables que no son de ningún edificio (tanques, válvulas, imán, brillo, lavanda), de la más barata a la más cara.
  List<Mejora> mejorasPoceta() => _ordenadas(mejoras.where((m) => m.edificio == null && _mejoraPuedeSalir(m)));

  /// La próxima mejora de un edificio que todavía no se puede comprar (la más barata no comprada que aún no sale), o null.
  Mejora? siguienteMejora(String id) {
    final r = _ordenadas(mejoras.where((m) => m.edificio == id && !mejoraComprada(m.id) && !_mejoraPuedeSalir(m)));
    return r.isEmpty ? null : r.first;
  }

  /// Precio de una mejora: el del catálogo, salvo Guantes y Faja que salen de los ajustes.
  double precioMejora(Mejora m) => switch (m.id) {
        'guantes' => ajustes.precioGuantes,
        'faja' => ajustes.precioFaja,
        _ => m.precio,
      };

  bool comprarMejora(String id) {
    final m = mejoraPorId(id);
    if (m == null || !_mejoraPuedeSalir(m) || precioMejora(m) > _p.saldo) return false;
    _p.saldo -= precioMejora(m);
    _p.mejoras.add(id);
    return true;
  }

  // ---------- Objetos ----------

  /// Su candado está abierto. El Robot además pide haber visto el primer Atasco.
  bool objetoAbierto(String id) {
    final o = objetoPorId(id);
    return o != null && cagadas >= o.candado && (!o.pideAtasco || _p.vioPrimerAtasco);
  }

  /// Precio en MJ: minutos x MJ/s sin efectos x 60, mínimo 100. La Cagada fresca da 0 (no se compra con MJ: viene con cada cagada real).
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
  /// Con [conCiruelas] ya se pagó en el servidor: no cobra MJ.
  bool comprarObjeto(String id, int ahora, {bool conCiruelas = false}) {
    if (conCiruelas ? !_cabeObjeto(id, ahora) : !puedeComprarObjeto(id, ahora)) return false;
    final o = objetoPorId(id)!;
    final precio = conCiruelas ? 0.0 : precioObjeto(id, ahora);
    if (o.tipo == TipoObjeto.consumible) {
      if (enInventario(id) >= o.maxInventario) return false;
      _p.inventario[id] = enInventario(id) + 1;
    } else {
      final dur = o.duracion!.inMilliseconds;
      if (robotActivo(ahora)) {
        _p.robotHasta = min(_p.robotHasta + dur, ahora + topeAlquiler.inMilliseconds);
      } else {
        _p.robotHasta = ahora + dur;
        if (o.espera != null) _p.esperas[id] = ahora + o.espera!.inMilliseconds;
      }
    }
    _p.saldo -= precio;
    return true;
  }

  /// Se puede comprar [id] ahora: abierto, con saldo (MJ, o Ciruelas si [conCiruelas]), sin inventario lleno ni espera.
  bool puedeComprarObjeto(String id, int ahora, {bool conCiruelas = false}) {
    final o = objetoPorId(id);
    if (o == null || !_cabeObjeto(id, ahora)) return false;
    return conCiruelas ? o.ciruelas > 0 && ciruelas >= o.ciruelas : precioObjeto(id, ahora) <= _p.saldo;
  }

  /// [id] se puede recibir ahora (sin mirar el precio).
  bool _cabeObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo == TipoObjeto.ficha || !objetoAbierto(id)) return false;
    if (o.tipo == TipoObjeto.consumible) return enInventario(id) < o.maxInventario;
    if (robotActivo(ahora)) return min(_p.robotHasta + o.duracion!.inMilliseconds, ahora + topeAlquiler.inMilliseconds) > _p.robotHasta;
    return esperaRestante(id, ahora) == null;
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

  /// Cagada fresca: producción x2 por 1 h (si ya estaba, suma 1 h). La da la tienda de Ciruelas.
  void activarCagadaFresca(int ahora) {
    final dur = objetoPorId('cagada_fresca')!.duracion!.inMilliseconds;
    _p.efectos['cagada_fresca'] = max(_p.efectos['cagada_fresca'] ?? 0, ahora) + dur;
  }

  /// La Cagada fresca de la última cagada real (x2 hasta [finMs]). Si ya dura más, se queda como está.
  /// Devuelve si cambió.
  bool aplicarFrescaHasta(int finMs) {
    if (finMs <= (_p.efectos['cagada_fresca'] ?? 0)) return false;
    _p.efectos['cagada_fresca'] = finMs;
    return true;
  }

  /// Se borró la cagada real que daba la Cagada fresca hasta [finViejoMs]: se quita esa parte del bono
  /// (lo que se compró con Ciruelas encima se queda). [finNuevoMs] = el de la cagada anterior, 0 si no hay.
  bool recortarFresca(int finViejoMs, int finNuevoMs, int ahora) {
    final fin = _p.efectos['cagada_fresca'] ?? 0;
    final quita = finViejoMs - max(finNuevoMs, ahora);
    if (fin <= ahora || quita <= 1000) return false;
    final nuevo = fin - quita;
    if (nuevo <= ahora) {
      _p.efectos.remove('cagada_fresca');
    } else {
      _p.efectos['cagada_fresca'] = nuevo.toInt();
    }
    return true;
  }

  // ---------- Ciruelas y racha ----------

  /// Suerte de las estéticas compradas (0.04 = +4%).
  double get bonoSuerte => bonoSuerteDe(esteticas);

  /// Tira la suerte de una Ciruela por pujo (~1/1500 con el bono). El servidor decide si la acepta.
  bool tirarCiruela() => _azar.nextDouble() < probConBono(probCiruelaPujoBase, esteticas);

  /// Pone el efecto de una oferta de la tienda de Ciruelas (el servidor ya descontó). Devuelve los MJ ganados.
  double aplicarOfertaCiruela(String id, int ahora) {
    switch (id) {
      case 'cagada_fresca':
        activarCagadaFresca(ahora);
        return 0;
      case 'produccion_2h':
        final mj = 2 * 3600 * mpsSinEfectos(contarAtasco: false);
        _ganar(mj);
        return mj;
      case 'robot_24h':
        _p.robotHasta = max(_p.robotHasta, ahora) + const Duration(hours: 24).inMilliseconds;
        return 0;
    }
    // Objeto pagado con Ciruelas: 'obj_<id>'.
    if (id.startsWith('obj_')) comprarObjeto(id.substring(4), ahora, conCiruelas: true);
    return 0;
  }

  /// Pone lo de la app del premio de la racha (producción, objetos, logro). Las Ciruelas y Fichas las da el servidor.
  /// Devuelve los MJ ganados.
  double aplicarPremioRacha(int dia, int ahora) {
    final p = premioDia(dia);
    final mj = p.minutos * 60 * mpsSinEfectos(contarAtasco: false);
    _ganar(mj);
    for (final MapEntry(key: id, value: n) in p.objetos.entries) {
      final o = objetoPorId(id);
      if (o == null || n <= 0) continue;
      if (o.tipo == TipoObjeto.alquilable) {
        _p.robotHasta = max(_p.robotHasta, ahora) + o.duracion!.inMilliseconds * n;
      } else {
        _p.inventario[id] = enInventario(id) + n;
      }
    }
    if (p.logro != null && logroPorId(p.logro!) != null && !_p.logros.contains(p.logro)) _p.logros.add(p.logro!);
    return mj;
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
    _p.segPartida += s;

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
      // El Dedo no produce MJ/s: atascarlo no haría nada.
      final candidatos = [for (final e in edificios) if (e.mpsBase > 0 && cantidad(e.id) >= minimoParaAtasco) e.id];
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
    final a = ajustes.doradoMinMin * 60, b = ajustes.doradoMaxMin * 60;
    _p.segHastaDorado = (a + (b - a) * _azar.nextDouble()) / (rapido ? 2 : 1);
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

  /// Tope offline: 2 h (la base de los ajustes), 4 h o 8 h según los tanques. Nunca menos que la base.
  Duration get topeOffline {
    final h = mejoraComprada('tanque_8') ? 8.0 : (mejoraComprada('tanque_4') ? 4.0 : 0.0);
    return Duration(seconds: (max(h, ajustes.offlineTopeH) * 3600).round());
  }

  /// Qué parte cuenta offline: 25% (la base de los ajustes), 50% o 75% según las válvulas. Nunca menos que la base.
  double get porcentajeOffline =>
      max(mejoraComprada('valvula_75') ? 0.75 : (mejoraComprada('valvula_50') ? 0.5 : 0.0), ajustes.offlinePorcentaje).toDouble();

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

  // ---------- Jalar la cadena ----------

  /// Rollos de Oro que da todo lo ganado en la historia: piso((mjTotal / divisor) ^ exponente).
  int get rollosTotales => rollosPorMj(_p.mjTotal, ajustes);

  /// Rollos que da jalar ahora: los totales menos los que ya tienes. Nunca negativo.
  int get rollosPorGanar => max(0, rollosTotales - _p.rollos);

  /// MJ (históricos) que faltan para que jalar dé un rollo más que ahora.
  double get mjParaSiguienteRollo {
    final meta = mjParaRollos(max(rollosTotales, _p.rollos) + 1, ajustes);
    return max(0, meta - _p.mjTotal);
  }

  /// Ya compraste La cadena del trono o ya jalaste alguna vez: el botón JALAR se ve para siempre.
  bool get cadenaDesbloqueada => mejoraComprada('cadena_trono') || _p.rollos > 0 || _p.jaladas > 0;

  /// Se puede jalar: botón desbloqueado, bastantes cagadas reales desde la última jalada y al menos 1 rollo por ganar.
  bool puedeJalar(int cagadasDesde, int necesarias) =>
      cadenaDesbloqueada && cagadasDesde >= necesarias && rollosPorGanar >= 1;

  /// Jala la cadena: suma los rollos y la jalada, y la corrida vuelve a empezar. Devuelve los rollos ganados.
  /// Se va: saldo, edificios, mejoras, objetos (inventario, esperas, robot), efectos comprados con MJ, atasco, mojón
  /// dorado y los contadores de la corrida (pujos recientes, segPartida). Se queda: mjTotal, logros, rollos, jaladas,
  /// estadísticas históricas, el buff del tipo, el bono offline y los efectos que vienen de cagadas reales o
  /// Ciruelas (Cagada fresca, Fiebre de Trono). No mira las cagadas: eso lo valida el servidor en `imperio_jalar`.
  int jalar() {
    final ganados = rollosPorGanar;
    _p
      ..rollos += ganados
      ..jaladas += 1
      ..saldo = 0
      ..edificios = {}
      ..mejoras = {}
      ..inventario = {}
      ..esperas = {}
      ..robotHasta = 0
      ..atasco = null
      ..dorado = null
      ..segHastaDorado = -1
      ..papelDoble = false
      ..pujosRecientes = []
      ..segPartida = 0;
    _p.efectos.removeWhere((id, _) => !efectosQueSobrevivenJalada.contains(id));
    revisarLogros();
    return ganados;
  }

  // ---------- Veteranos ----------

  /// Lo que trae un veterano: cagadas, multiplicador, Fichas y candados abiertos.
  ResumenBienvenida bienvenida() => ResumenBienvenida(cagadas, multiplicadorCagadas, fichas, candadosAbiertos(cagadas));
}
