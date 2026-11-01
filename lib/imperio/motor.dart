// Motor del Imperio Cagón (fase 1 y 2). Dart puro (sin Flutter) para poder probarlo.
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

  /// Contó al 100% por el Guardia nocturno (y se gastó).
  final bool conGuardia;
  const ResultadoOffline(this.segundosAusente, this.segundosContados, this.ganado, this.tanqueLleno, this.conBonus, {this.conGuardia = false});
}

/// Lo que hizo una habilidad de Maná.
class ResultadoHabilidad {
  final String id;

  /// MJ ganados (Chorro a presión); negativo si el Chorro falló.
  final double mj;

  /// El Chorro a presión falló.
  final bool fallo;
  const ResultadoHabilidad(this.id, this.mj, this.fallo);
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
  'jalon_doble': ('🚽', 'Jalón doble', 'Double flush', 'Producción x2', 'Production x2'),
  'pujo_sagrado': ('🙌', 'Pujo sagrado', 'Holy push', 'Pujos x10', 'Pushes x10'),
  'plomero_bono': ('🧰', 'Plomero', 'Plumber', 'Producción x3', 'Production x3'),
};

// Números de la fase 2 (Maná, alquilables, consumibles).
const double multiplicadorPujoSagrado = 10;
const double probFalloChorro = 0.15;
const Duration chorroGana = Duration(minutes: 15), chorroPierde = Duration(minutes: 5);
const double alargueAguanta = 0.1;

/// Pujos por segundo del Primo pujador.
const double pujosPrimo = 10;

/// Cada cuánto compra la Cuadrilla del barrio.
const Duration cicloCuadrilla = Duration(minutes: 1);
const Duration duracionBonoPlomero = Duration(minutes: 1);

/// Tope offline del Guardia nocturno.
const Duration topeGuardia = Duration(hours: 8);

/// Día real local (días desde epoch) de [ms]: el Súper Plomero regala 1 vez por día.
int diaLocal(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

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

  /// Segundos activos con la Cuadrilla desde su última compra (no se guarda).
  double _segCuadrilla = 0;

  /// MJ del regalo diario del Súper Plomero que la pantalla aún no anunció.
  double _regaloPlomero = 0;

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

  /// Alquiler activo. Con duración: hasta su fin. El Guardia (sin duración): desde que se alquila hasta el próximo offline.
  bool alquiladoActivo(String id, int ahora) {
    final fin = _p.alquilados[id];
    if (fin == null) return false;
    return objetoPorId(id)?.duracion == null || fin > ahora;
  }

  /// Algo destapa solo: Robot, Robot Turbo o Súper Plomero.
  bool _destapaSolo(int ahora) => robotActivo(ahora) || alquiladoActivo('robot_turbo', ahora) || tieneObjetoRollos('super_plomero') > 0;

  /// Cuenta un destape. Con el Plomero por horas alquilado: producción x3 por 1 min.
  void _destapado(int ahora) {
    _p.destapes++;
    if (alquiladoActivo('plomero_horas', ahora)) _extender('plomero_bono', ahora, duracionBonoPlomero);
  }

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
    if (_activo('pino', ahora)) s += 0.5;
    if (_activo('abuela', ahora)) s += 2;
    if (_activo('greca', ahora)) s += 1;
    if (_activo('reina_pepiada', ahora)) s += 0.5;
    if (_activo('jalon_doble', ahora)) s += 1;
    if (_activo('plomero_bono', ahora)) s += 2;
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
    if (_p.pintura.contains(id)) x *= 1 + bonoPintura;
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

  /// Efectos del pujo: los temporales (tope x4) y, por fuera del tope, Pujo loco x777 y Pujo sagrado x10.
  double _conEfectosPujo(double v, int ahora) {
    var t = v * multiplicadorPujoTemporal(ahora);
    if (_activo('pujo_sagrado', ahora)) t *= multiplicadorPujoSagrado;
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
  /// Con [ahora] y el Primo pujador alquilado, suma sus 10 pujos por segundo.
  double ritmoEfectivo([int? ahora]) {
    final m = mpsSinEfectos();
    final pujo = (1 + aporteDedos) * _multiplicadorClic * multiplicadorRollos + _pctPujo() * m;
    final primo = ahora != null && alquiladoActivo('primo', ahora) ? pujosPrimo : 0;
    return max(m, pujo * (pujosPorSegundoRitmo + primo));
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

  /// Se puede comprar: su candado de cagadas está abierto y ganaste los Rollos de Oro que pide (0 en la fase 1). Gastarlos no lo cierra.
  bool edificioAbierto(String id) {
    final e = edificioPorId(id);
    return e != null && cagadas >= e.candado && _p.rollosGanados >= e.rollos;
  }

  /// Sale en la lista: los de la fase 1 siempre (abiertos o con su candado); los de la fase 2 cuando ya tienes sus rollos.
  bool edificioVisible(String id) {
    final e = edificioPorId(id);
    return e != null && (e.fase1 || _p.rollosGanados >= e.rollos);
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

  /// Compra con MJ. Consumible: al inventario (hasta 5). Alquilable: se activa ya; si sigue activo suma su duración, hasta
  /// el doble desde ahora (Robot: 30 min, hasta 1 h). Con [conCiruelas] ya se pagó en el servidor: no cobra MJ.
  bool comprarObjeto(String id, int ahora, {bool conCiruelas = false}) {
    if (conCiruelas ? !_cabeObjeto(id, ahora) : !puedeComprarObjeto(id, ahora)) return false;
    final o = objetoPorId(id)!;
    final precio = conCiruelas ? 0.0 : precioObjeto(id, ahora);
    if (o.tipo == TipoObjeto.consumible) {
      if (enInventario(id) >= o.maxInventario) return false;
      _p.inventario[id] = enInventario(id) + 1;
    } else {
      _alquilar(o, ahora);
    }
    _p.saldo -= precio;
    return true;
  }

  /// Fin del alquiler si se vuelve a alquilar [o] ahora: suma su duración, hasta el doble desde ahora.
  int _finAlquiler(Objeto o, int ahora) {
    final d = o.duracion!.inMilliseconds;
    final fin = _p.alquilados[o.id] ?? 0;
    return fin > ahora ? min(fin + d, ahora + 2 * d) : ahora + d;
  }

  void _alquilar(Objeto o, int ahora) {
    final nuevo = !alquiladoActivo(o.id, ahora);
    _p.alquilados[o.id] = o.duracion == null ? ahora : _finAlquiler(o, ahora);
    if (nuevo && o.espera != null) _p.esperas[o.id] = ahora + o.espera!.inMilliseconds;
    _p.alquiladosUsados.add(o.id);
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
    if (alquiladoActivo(id, ahora)) return o.duracion != null && _finAlquiler(o, ahora) > _p.alquilados[id]!;
    return esperaRestante(id, ahora) == null;
  }

  /// Usa un consumible del inventario si no hay espera. Papel doble hoja: deja pendiente el doble del próximo dorado.
  /// Destapacaños: destapa (pide un Atasco). La Pintura marrón se usa con [usarPintura].
  bool usarObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo != TipoObjeto.consumible || enInventario(id) <= 0 || esperaRestante(id, ahora) != null) return false;
    if (id == 'pintura') return false;
    if (id == 'destapacanos') {
      if (_p.atasco == null) return false;
      _p.atasco = null;
      _destapado(ahora);
    } else if (o.duracion == null) {
      if (_p.papelDoble) return false;
      _p.papelDoble = true;
    } else {
      _extender(id, ahora, o.duracion!);
    }
    _gastarConsumible(o, ahora);
    return true;
  }

  void _gastarConsumible(Objeto o, int ahora) {
    _p.inventario[o.id] = enInventario(o.id) - 1;
    if (_p.inventario[o.id]! <= 0) _p.inventario.remove(o.id);
    if (o.espera != null) _p.esperas[o.id] = ahora + o.espera!.inMilliseconds;
    _p.consumiblesUsados++;
  }

  /// Edificios donde se puede poner Pintura marrón: abiertos, con unidades, que producen y sin pintura.
  List<String> edificiosParaPintura() =>
      [for (final e in edificios) if (e.mpsBase > 0 && cantidad(e.id) > 0 && !_p.pintura.contains(e.id)) e.id];

  /// Pinta [edificio] (+10% hasta jalar la cadena). 1 por edificio.
  bool usarPintura(String edificio, int ahora) {
    final o = objetoPorId('pintura')!;
    if (enInventario(o.id) <= 0 || !edificiosParaPintura().contains(edificio)) return false;
    _p.pintura.add(edificio);
    _gastarConsumible(o, ahora);
    return true;
  }

  /// Edificios con Pintura marrón.
  Set<String> get pintados => _p.pintura;

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
      case 'congelador':
        return 0; // vive en el servidor (racha)
    }
    // Objeto pagado con Ciruelas: 'obj_<id>'.
    if (id.startsWith('obj_')) comprarObjeto(id.substring(4), ahora, conCiruelas: true);
    return 0;
  }

  /// Cofre del Trono: 1 h de producción (las Fichas y Ciruelas las da el servidor). Devuelve los MJ ganados.
  double aplicarPremioCofre(int ahora) {
    final mj = 3600 * mpsSinEfectos(contarAtasco: false);
    _ganar(mj);
    return mj;
  }

  /// Esperas que siguen corriendo (id → ms que faltan), de la más larga a la más corta. Para la Ficha Sin espera.
  Map<String, int> esperasActivas(int ahora) {
    final r = [for (final MapEntry(key: id, value: fin) in _p.esperas.entries) if (fin > ahora) MapEntry(id, fin - ahora)]
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(r);
  }

  /// Ficha Sin espera: borra la espera de [id]. false si no tenía.
  bool quitarEspera(String id, int ahora) {
    if ((_p.esperas[id] ?? 0) <= ahora) return false;
    _p.esperas.remove(id);
    return true;
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
        _p.alquilados[id] = o.duracion == null ? ahora : max(_p.alquilados[id] ?? 0, ahora) + o.duracion!.inMilliseconds * n;
      } else {
        _p.inventario[id] = enInventario(id) + n;
      }
    }
    if (p.logro != null && logroPorId(p.logro!) != null && !_p.logros.contains(p.logro)) _p.logros.add(p.logro!);
    return mj;
  }

  // ---------- Maná de Tripa ----------

  /// El Maná ya salió (candado de 15 cagadas).
  bool get manaAbierto => cagadas >= candadoMana;

  /// Maná ahora: lo guardado más lo que se llenó desde entonces (100 por hora, también offline).
  double mana(int ahora) {
    final lleno = max(0, ahora - _p.manaEn) / llenadoMana.inMilliseconds * manaMax;
    return min(manaMax, _p.mana + lleno).toDouble();
  }

  void _fijarMana(double v, int ahora) {
    _p.mana = v.clamp(0, manaMax).toDouble();
    _p.manaEn = ahora;
  }

  /// Una cagada real llena el Maná entero.
  void llenarMana(int ahora) => _fijarMana(manaMax, ahora);

  /// Lo que falta para volver a usar la habilidad [id]. null = ya se puede.
  Duration? esperaHabilidad(String id, int ahora) => esperaRestante('hab_$id', ahora);

  /// Se puede usar [id] ahora: Maná abierto y suficiente, sin espera. Corre corre pide un Atasco.
  bool puedeUsarHabilidad(String id, int ahora) {
    final h = habilidadPorId(id);
    if (h == null || !manaAbierto || mana(ahora) < h.mana || esperaHabilidad(id, ahora) != null) return false;
    return id != 'corre_corre' || _p.atasco != null;
  }

  /// Usa la habilidad [id]: gasta su Maná y arranca su espera. null si no se puede.
  ResultadoHabilidad? usarHabilidad(String id, int ahora) {
    if (!puedeUsarHabilidad(id, ahora)) return null;
    final h = habilidadPorId(id)!;
    var mj = 0.0;
    var fallo = false;
    switch (id) {
      case 'corre_corre':
        _p.atasco = null;
        _destapado(ahora);
      case 'chorro':
        final m = mpsSinEfectos(contarAtasco: false);
        if (_azar.nextDouble() < probFalloChorro) {
          fallo = true;
          final pierde = min(_p.saldo, chorroPierde.inSeconds * m);
          _p.saldo -= pierde;
          _p.chorrosFallidos++;
          mj = -pierde;
        } else {
          mj = chorroGana.inSeconds * m;
          _ganar(mj);
        }
      case 'aguanta':
        int alarga(int fin) => fin + ((fin - ahora) * alargueAguanta).round();
        _p.efectos.updateAll((_, fin) => fin > ahora ? alarga(fin) : fin);
        _p.alquilados.updateAll((k, fin) => objetoPorId(k)?.duracion != null && fin > ahora ? alarga(fin) : fin);
      default:
        if (h.duracion != null) _extender(id, ahora, h.duracion!);
    }
    _fijarMana(mana(ahora) - h.mana, ahora);
    _p.esperas['hab_$id'] = ahora + h.espera.inMilliseconds;
    _p.habilidades++;
    return ResultadoHabilidad(id, mj, fallo);
  }

  // ---------- Objetos de Rollos de Oro ----------

  /// Salen después de la primera jalada.
  bool get objetosRollosAbiertos => _p.jaladas > 0;

  /// Cuántos tienes de un objeto de Rollos (la Cadena de reserva: 1 = pendiente para la próxima jalada).
  int tieneObjetoRollos(String id) => _p.objetosRollos[id] ?? 0;

  /// Lo que falta para otra Cadena de reserva (1 por semana). null = ya se puede.
  Duration? esperaCadena(int ahora) {
    if (_p.cadenaReservaEn <= 0) return null;
    final fin = _p.cadenaReservaEn + esperaCadenaReserva.inMilliseconds;
    return fin > ahora ? Duration(milliseconds: fin - ahora) : null;
  }

  /// Se puede comprar [id] con Rollos: abiertos, alcanzan los rollos, bajo su límite (y sin espera la Cadena).
  bool puedeComprarObjetoRollos(String id, int ahora) {
    final o = objetoRollosPorId(id);
    if (o == null || !objetosRollosAbiertos || _p.rollos < o.costo || tieneObjetoRollos(id) >= o.limite) return false;
    return id != 'cadena_reserva' || esperaCadena(ahora) == null;
  }

  /// Compra con Rollos de Oro. Los gastados bajan el +% por rollo, pero no cierran edificios ni mejoras.
  bool comprarObjetoRollos(String id, int ahora) {
    if (!puedeComprarObjetoRollos(id, ahora)) return false;
    final o = objetoRollosPorId(id)!;
    _p
      ..rollos -= o.costo
      ..rollosGastados += o.costo;
    _p.objetosRollos[id] = tieneObjetoRollos(id) + 1;
    if (id == 'cadena_reserva') _p.cadenaReservaEn = ahora;
    return true;
  }

  /// Súper Plomero: 1 h de producción la primera vez de cada día real. Lo guarda para [tomarRegaloPlomero].
  void _revisarSuperPlomero(int ahora) {
    if (tieneObjetoRollos('super_plomero') <= 0) return;
    final dia = diaLocal(ahora);
    if (_p.superPlomeroDia == dia) return;
    _p.superPlomeroDia = dia;
    final mj = 3600 * mpsSinEfectos(contarAtasco: false);
    _ganar(mj);
    _regaloPlomero += mj;
  }

  /// MJ del regalo del Súper Plomero sin anunciar (y lo marca como anunciado). 0 si no hay.
  double tomarRegaloPlomero() {
    final r = _regaloPlomero;
    _regaloPlomero = 0;
    return r;
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
    final sinFin = <EfectoActivo>[];
    for (final MapEntry(key: id, value: fin) in _p.alquilados.entries) {
      final o = objetoPorId(id);
      if (o == null || !alquiladoActivo(id, ahora)) continue;
      final e = EfectoActivo(id, o.emoji, o.nombreEs, o.nombreEn, o.descEs, o.descEn, o.duracion == null ? null : resta(fin));
      (o.duracion == null ? sinFin : r).add(e);
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
    r.addAll(sinFin);
    return r;
  }

  // ---------- Tick ----------

  /// Avanza el juego. `segundos` = tiempo activo desde el último tick (se recorta a 1).
  /// Suma producción, vence efectos, saca mojones dorados y Atascos. Devuelve los logros nuevos (para los avisos).
  List<Logro> tick(int ahora, double segundos) {
    final s = segundos.isNaN ? 0.0 : segundos.clamp(0.0, 1.0).toDouble();
    if (s > 0) _ganar(mps(ahora) * s);
    // Primo pujador: 10 pujos por segundo (sin épicos ni contadores de pujos).
    if (s > 0 && alquiladoActivo('primo', ahora)) _ganar(valorPujo(ahora) * pujosPrimo * s);
    _p.segPartida += s;
    _cuadrilla(ahora, s);
    _revisarSuperPlomero(ahora);

    // Laxante de la abuela: al terminar sale un Atasco seguro.
    final abuela = _p.efectos['abuela'];
    if (abuela != null && abuela <= ahora) _atascar(ahora, 1);
    _p.efectos.removeWhere((_, fin) => fin <= ahora);
    _p.alquilados.removeWhere((id, fin) => objetoPorId(id)?.duracion != null && fin <= ahora);
    if (_p.tipoBuff != null && _p.tipoBuffHasta <= ahora) _p.tipoBuff = null;
    if (_p.dorado != null && _p.dorado!.hasta <= ahora) _p.dorado = null;

    // Mojón dorado: la cuenta regresiva corre solo con la app abierta y sin otro dorado en pantalla.
    if (_p.segHastaDorado < 0) {
      _programarDorado(ahora);
    } else if (_p.dorado == null) {
      // Ambientador de pino: los dorados salen la mitad de seguido.
      _p.segHastaDorado -= _activo('pino', ahora) ? s / 2 : s;
      if (_p.segHastaDorado <= 0) {
        final dur = duracionDoradoVisible.inMilliseconds * (mejoraComprada('brillo') ? 2 : 1);
        _p.dorado = DoradoVisible(ahora, ahora + dur, 0.1 + 0.8 * _azar.nextDouble(), 0.1 + 0.8 * _azar.nextDouble());
        _programarDorado(ahora);
      }
    }

    // Atascos: ~1 cada 2 h activas, uno a la vez, en un edificio con 25 o más.
    if (_p.atasco == null && s > 0 && _azar.nextDouble() < s / segundosPorAtasco) _atascar(ahora, minimoParaAtasco);
    if (_p.atasco != null && _destapaSolo(ahora)) {
      _p.atasco = null;
      _destapado(ahora);
    }

    _p.ultimaVez = ahora;
    return revisarLogros();
  }

  /// Atasca un edificio al azar con [minimo] unidades o más (si no hay otro Atasco). El Dedo no produce MJ/s: no se atasca.
  void _atascar(int ahora, int minimo) {
    if (_p.atasco != null) return;
    final candidatos = [for (final e in edificios) if (e.mpsBase > 0 && cantidad(e.id) >= minimo) e.id];
    if (candidatos.isEmpty) return;
    _p.atasco = Atasco(candidatos[_azar.nextInt(candidatos.length)], ahora);
    _p.vioPrimerAtasco = true;
  }

  /// Cuadrilla del barrio: cada minuto activo compra el edificio abierto más barato, si alcanza.
  void _cuadrilla(int ahora, double s) {
    if (!alquiladoActivo('cuadrilla', ahora)) {
      _segCuadrilla = 0;
      return;
    }
    _segCuadrilla += s;
    if (_segCuadrilla < cicloCuadrilla.inSeconds) return;
    _segCuadrilla -= cicloCuadrilla.inSeconds;
    String? barato;
    for (final e in edificios) {
      if (e.mpsBase <= 0 || !edificioAbierto(e.id)) continue;
      if (barato == null || precioEdificio(e.id, ahora) < precioEdificio(barato, ahora)) barato = e.id;
    }
    if (barato != null) comprarEdificio(barato, ahora);
  }

  void _programarDorado(int ahora) {
    final rapido = mejoraComprada('iman') || tipoActivo(ahora) == 5;
    final a = ajustes.doradoMinMin * 60, b = ajustes.doradoMaxMin * 60;
    _p.segHastaDorado = (a + (b - a) * _azar.nextDouble()) / (rapido ? 2 : 1);
  }

  /// Se tocó una cosa del baño en la Poceta: la cuenta en [Partida.toques] (para los logros escondidos) y devuelve los logros nuevos.
  /// Un id que no está en [objetosTocables] no cuenta. Tope de 99999 por cosa para que el estado no crezca sin fin.
  List<Logro> tocarObjeto(String id) {
    if (!objetosTocables.contains(id)) return const [];
    _p.toques[id] = min((_p.toques[id] ?? 0) + 1, 99999);
    return revisarLogros();
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
    _destapado(ahora);
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
  /// Suma el Tanque extra (Fichas) y los Tanques de lujo (Rollos, +1 h c/u).
  Duration get topeOffline {
    final h = mejoraComprada('tanque_8') ? 8.0 : (mejoraComprada('tanque_4') ? 4.0 : 0.0);
    final extra = _p.horasExtraTanque + tieneObjetoRollos('tanque_lujo');
    return Duration(seconds: ((max(h, ajustes.offlineTopeH) + extra) * 3600).round());
  }

  /// Qué parte cuenta offline: 25% (la base de los ajustes), 50% o 75% según las válvulas. Nunca menos que la base.
  double get porcentajeOffline =>
      max(mejoraComprada('valvula_75') ? 0.75 : (mejoraComprada('valvula_50') ? 0.5 : 0.0), ajustes.offlinePorcentaje).toDouble();

  /// Cobra el tiempo fuera (sin efectos temporales, sin Atascos ni dorados). x1,5 si quedó el buff del tipo 6 (y se gasta).
  /// Guardia nocturno: cuenta al 100% con tope de 8 h (o el del tanque si es más) y se gasta.
  ResultadoOffline aplicarOffline(int desdeMs, int ahoraMs) {
    final ausente = max(0, ahoraMs - desdeMs) / 1000.0;
    _p.ultimaVez = ahoraMs;
    _p.dorado = null;
    _p.atasco?.desde = ahoraMs; // vuelve a verse ahora
    // La Arepa reina pepiada solo corre con la app abierta: se corre su fin lo que estuviste fuera.
    final arepa = _p.efectos['reina_pepiada'];
    if (arepa != null && arepa > desdeMs && ahoraMs > desdeMs) _p.efectos['reina_pepiada'] = arepa + (ahoraMs - desdeMs);
    if (ausente < minimoOffline.inSeconds) return ResultadoOffline(ausente, 0, 0, false, false);
    final guardia = _p.alquilados.remove('guardia') != null;
    final tope = guardia ? max(topeOffline.inSeconds, topeGuardia.inSeconds).toDouble() : topeOffline.inSeconds.toDouble();
    final contados = min(ausente, tope);
    final bonus = _p.offlineBonus;
    _p.offlineBonus = false;
    final ganado = contados * mpsSinEfectos(contarAtasco: false) * (guardia ? 1.0 : porcentajeOffline) * (bonus ? 1.5 : 1);
    _ganar(ganado);
    return ResultadoOffline(ausente, contados, ganado, ausente >= tope, bonus, conGuardia: guardia);
  }

  // ---------- Cagadas reales ----------

  /// Cobra cagadas reales nuevas: una Descarga por cada una (15 min x (1 + 0,1 x peso)), una sola Fiebre de Trono
  /// y el buff del tipo más reciente por 1 h. Llenan el Maná de Tripa. Las Fichas no cambian aquí (las da el servidor).
  ResultadoCagadas aplicarCagadas(List<CagadaReal> nuevas, int ahora) {
    if (nuevas.isEmpty) return const ResultadoCagadas(0, [], null, false);
    llenarMana(ahora);
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

  /// Rollos que da jalar ahora: los totales menos los que ya ganaste (los gastados cuentan). Nunca negativo.
  int get rollosPorGanar => max(0, rollosTotales - _p.rollosGanados);

  /// MJ (históricos) que faltan para que jalar dé un rollo más que ahora.
  double get mjParaSiguienteRollo {
    final meta = mjParaRollos(max(rollosTotales, _p.rollosGanados) + 1, ajustes);
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
  /// Fase 2: se van los alquilados y la Pintura; se quedan las esperas de habilidades (`hab_*`), el Maná y los objetos
  /// de Rollos. La Cadena de reserva pendiente se gasta: devuelve 1 edificio de cada tipo que tenías.
  int jalar() {
    final ganados = rollosPorGanar;
    final habilidadesEnEspera = {for (final e in _p.esperas.entries) if (e.key.startsWith('hab_')) e.key: e.value};
    final reserva = tieneObjetoRollos('cadena_reserva') > 0;
    final devueltos = {for (final MapEntry(key: id, value: n) in _p.edificios.entries) if (n > 0) id: 1};
    _p
      ..rollos += ganados
      ..jaladas += 1
      ..saldo = 0
      ..edificios = {}
      ..mejoras = {}
      ..inventario = {}
      ..esperas = habilidadesEnEspera
      ..alquilados = {}
      ..pintura = {}
      ..atasco = null
      ..dorado = null
      ..segHastaDorado = -1
      ..papelDoble = false
      ..pujosRecientes = []
      ..segPartida = 0;
    _p.efectos.removeWhere((id, _) => !efectosQueSobrevivenJalada.contains(id));
    if (reserva) {
      _p.edificios = devueltos;
      _p.objetosRollos.remove('cadena_reserva');
    }
    _segCuadrilla = 0;
    revisarLogros();
    return ganados;
  }

  // ---------- Veteranos ----------

  /// Lo que trae un veterano: cagadas, multiplicador, Fichas y candados abiertos.
  ResumenBienvenida bienvenida() => ResumenBienvenida(cagadas, multiplicadorCagadas, fichas, candadosAbiertos(cagadas));
}
