// Motor del Imperio Cagón (fase 1 y 2). Dart puro (sin Flutter) para poder probarlo.
// Todo lo que depende del tiempo recibe `ahora` (ms epoch del reloj corregido con el servidor) y el azar viene inyectado.
// La pantalla llama `tick()` ~1 vez por segundo, `pujar()` en cada toque y guarda `toJson()` en la nube.

import 'dart:collection';
import 'dart:math';

import 'casas.dart';
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

  /// false si el toque pasó del tope de pujos por segundo ([Ajustes.topePujosSeg]): no dio nada ni contó.
  final bool contado;
  const ResultadoPujo(this.ganado, this.epico, {this.contado = true});
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

  /// Contó x1,5 por el buff del tipo 6 (x1,25 si estaba cansado: [fuerzaBonus] 0,5).
  final bool conBonus;
  final double fuerzaBonus;

  /// Contó al 100% por el Guardia nocturno (y se gastó).
  final bool conGuardia;

  /// Regalo de vuelta (ya sumado en [ganado]): 4 h de producción si estuvo fuera 2 días o más. 0 = no hubo.
  final double regalo;

  /// Atascos offline que cayeron dentro del tiempo contado, en orden de hora (cada uno: edificio, cuándo y si lo
  /// destapó solo un Robot, Robot Turbo o Súper Plomero), y los MJ que se dejaron de ganar (ya descontados de [ganado]).
  final List<AtascoOffline> atascos;
  final double mjPerdidos;

  /// El primero de [atascos]: el edificio (null = no hubo), cuándo (ms epoch) y si estaba cubierto.
  String? get atascoEdificio => atascos.isEmpty ? null : atascos.first.edificio;
  int get atascoEn => atascos.isEmpty ? 0 : atascos.first.en;
  bool get atascoCubierto => atascos.isNotEmpty && atascos.first.cubierto;

  /// Atascos offline que quedaron tapados al volver (los no cubiertos).
  int get atascosTapados => atascos.where((a) => !a.cubierto).length;
  const ResultadoOffline(this.segundosAusente, this.segundosContados, this.ganado, this.tanqueLleno, this.conBonus,
      {this.conGuardia = false, this.regalo = 0, this.fuerzaBonus = 1, this.atascos = const [], this.mjPerdidos = 0});
}

/// Atasco offline programado al salir: en [en] (ms epoch) se atasca [edificio]. [cubierto] = un Robot, Robot Turbo o
/// Súper Plomero lo destapará solo (no hace falta avisar).
class AtascoOffline {
  final int en;
  final String edificio;
  final bool cubierto;
  const AtascoOffline(this.en, this.edificio, this.cubierto);
}

/// Aviso local con la app cerrada: en [segundos] alcanza para [nombreEs] / [nombreEn], o se llena la poceta (null).
class AvisoCerrado {
  final double segundos;
  final String? nombreEs, nombreEn;
  const AvisoCerrado(this.segundos, this.nombreEs, this.nombreEn);
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

  /// Fuerza del buff de [tipoBuff] por repetir tipo: 1 entero, 0,5 cansado, 0 sin efecto.
  final double fuerza;
  const ResultadoCagadas(this.cantidad, this.descargas, this.tipoBuff, this.enFiebre, {this.fuerza = 1});

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
const int minimoParaAtasco = 1;

/// Segundos de juego activo por Atasco, en promedio (el valor por defecto de [Ajustes.atascoSeg]). Es un freno del
/// juego: molesta desde el principio y en cualquier edificio (con 25 min y 10 unidades mínimo casi no salía y se
/// avanzaba demasiado rápido).
const double segundosPorAtasco = 4 * 60;

/// Azar de Atascos en juego (falso azar por presión): cada segundo activo suma `s / atascoSeg x novato x ritmo` y al
/// pasar el umbral (sorteado entre 0,75 y 1,25) sale uno. Así no hay rachas raras ni sequías largas.
/// Novato (menos de [segundosNovato] jugados en total): x0,6. Ritmo: hasta x1,5 pujando a [pujosRitmo] pujos/s o más.
const double segundosNovato = 600, presionNovato = 0.6, presionRitmoMax = 0.5, pujosRitmo = 10;

/// Presión que suma cada edificio comprado, con tope por compra (de varios a la vez).
const double presionPorCompra = 0.02, presionCompraTope = 0.2;

/// Ventana (ms) de los pujos que miden el ritmo.
const int ventanaRitmo = 10000;

/// El primer Atasco sale seguro a estos segundos de juego activo (en cualquier edificio que dé MJ/s): así se conoce
/// la mecánica y se abren el Robot y el Turbo.
const double segundosPrimerAtasco = 60;
// La probabilidad y el valor del pujo épico salen de los ajustes (`epicoBase`, `epicoPorDedo`, `epicoTope`, `epicoTipo1`, `epicoMultiplicador`).
const double multiplicadorFiebre = 7, multiplicadorPujoLoco = 777;


/// Tope de la suma de efectos de objetos y del tipo de mojón.
const double topeEfectos = 4;

/// Pesos del mojón dorado: Fiebre, Lluvia, Pujo loco, Constructor (suman 100).
const List<int> pesosDorado = [40, 40, 10, 10];

/// Ausencia mínima para que cuente como offline (y gaste el x1,5 del tipo 6).
const Duration minimoOffline = Duration(minutes: 1);

const Map<String, (String, String, String, String, String)> _textosEfecto = {
  'fiebre_dorada': ('🔥', 'Fiebre', 'Fever', 'Producción x7', 'Production x7'),
  'fiebre_trono': ('💥', 'Fiebre de Trono', 'Throne fever', 'Producción x7', 'Production x7'),
  'empujon': ('🎁', 'Empujón', 'Boost', 'Producción x2', 'Production x2'),
  'pujo_loco': ('🍑', 'Pujo loco', 'Crazy push', 'Pujos x777', 'Pushes x777'),
  'constructor': ('🧱', 'Constructor', 'Builder', 'Cagadores a mitad de precio', 'Poopers at half price'),
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

/// Pujos por segundo de cada Primo pujador (vienen [Imperio.primosActivos]).
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
const Set<String> efectosQueSobrevivenJalada = {'cagada_fresca', 'fiebre_trono', 'empujon'};

/// Regalo de vuelta: quien vuelve tras [ausenciaRegalo] o más se lleva [horasRegalo] de producción.
const Duration ausenciaRegalo = Duration(days: 2);
const double horasRegalo = 4;

/// Tope offline de quien juega poco: menos de [segundosPocoJuego] activos por día en promedio.
const double topeOfflinePocoJuegoH = 6;
const double segundosPocoJuego = 3600;

/// Empujón (x2) para quien se quedó atrás: lo decide el servidor, una vez por semana.
const Duration duracionEmpujon = Duration(minutes: 30);

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

  /// Cagadas reales que cuentan para los candados: como mucho 3 por día (las cuenta el servidor). -1 = el servidor
  /// no las mandó y valen todas ([cagadas]).
  int cagadasCandado;

  /// Días de racha reclamados (pases diarios, los cuenta el servidor): cada uno vale media cagada de candado.
  int pases;

  /// Estéticas premium compradas (ids de `esteticas`; las guarda el servidor). Solo suben la suerte de las Ciruelas.
  Set<String> esteticas;

  /// Números que vienen de los flags remotos (por defecto, los de siempre).
  final Ajustes ajustes;
  final Random _azar;

  /// Segundos activos con la Cuadrilla desde su última compra (no se guarda).
  double _segCuadrilla = 0;

  /// Compras de la Cuadrilla en esta sesión y la última que hizo (no se guardan): la pantalla las anima.
  int _comprasCuadrilla = 0;

  /// Segundos activos acumulados para la próxima compra del Mayordomo (no se guarda).
  double _segMayordomo = 0;
  int _comprasMayordomo = 0;
  String? _ultimaCuadrilla;
  int get comprasCuadrilla => _comprasCuadrilla;
  String? get ultimaCuadrilla => _ultimaCuadrilla;

  /// Momentos (ms) de los pujos de la mano que contaron en el último segundo, para el tope (no se guarda).
  final _toques = ListQueue<int>();

  /// Momentos (ms) de los pujos que contaron en los últimos 10 s, para el ritmo de los Atascos (no se guarda).
  final _pujosRitmo = ListQueue<int>();

  /// MJ del regalo diario del Súper Plomero que la pantalla aún no anunció.
  double _regaloPlomero = 0;

  /// Alquileres Indefinidos que se cortaron por falta de MJ (id, precio que no alcanzó) y la app aún no anotó.
  final List<(String, double)> _cortados = [];

  Imperio({Partida? partida, this.cagadas = 0, this.fichas = 0, this.ciruelas = 0, Set<String>? esteticas, Random? azar,
      this.ajustes = Ajustes.porDefecto, this.cagadasCandado = -1, this.pases = 0})
      : partida = partida ?? Partida(),
        esteticas = esteticas ?? {},
        _azar = azar ?? Random();

  /// Arranca desde lo guardado en la nube.
  factory Imperio.desdeJson(Map<String, dynamic>? json,
          {int cagadas = 0, int fichas = 0, int ciruelas = 0, Set<String>? esteticas, Random? azar, Ajustes ajustes = Ajustes.porDefecto,
          int cagadasCandado = -1, int pases = 0}) =>
      Imperio(
          partida: Partida.desdeJson(json), cagadas: cagadas, fichas: fichas, ciruelas: ciruelas, esteticas: esteticas, azar: azar, ajustes: ajustes,
          cagadasCandado: cagadasCandado, pases: pases);

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

  /// Atascos abiertos, en orden de llegada (el primero es el que se destapa a mano).
  List<Atasco> get atascos => _p.atascos;

  /// Ese edificio está atascado (produce 0).
  bool atascado(String id) => _p.atascos.any((a) => a.edificio == id);

  /// Atascos abiertos a la vez como máximo: el ajuste (1 a 10), nunca más que los edificios que dan MJ/s.
  int get topeAtascos {
    final productores = edificios.where((e) => e.mpsBase > 0 && cantidad(e.id) >= minimoParaAtasco).length;
    return min(ajustes.atascosMax.clamp(1, 10), productores);
  }

  void _ganar(double mj) {
    if (mj.isNaN || mj <= 0) return;
    _p.saldo += mj;
    _p.mjTotal += mj;
    if (_p.mudanzas > 0 || _p.abdicaciones > 0) _p.mjEnCasa += mj;
  }

  bool _activo(String id, int ahora) => (_p.efectos[id] ?? 0) > ahora;
  void _extender(String id, int ahora, Duration d) {
    final fin = ahora + d.inMilliseconds;
    if ((_p.efectos[id] ?? 0) < fin) _p.efectos[id] = fin;
  }

  /// Tipo de mojón con buff activo (1 a 7), o null.
  int? tipoActivo(int ahora) => _p.tipoBuff != null && _p.tipoBuffHasta > ahora ? _p.tipoBuff : null;

  /// Fuerza del buff de tipo activo (1 entero, 0,5 cansado). Cada bono m pasa a 1 + (m - 1) x fuerza.
  double get fuerzaTipo => _p.tipoBuffFuerza.clamp(0, 1).toDouble();

  /// Fuerza por cuántas veces seguidas se repitió el mismo tipo: 1 vez entero, 2 la mitad, 3 o más nada.
  static double fuerzaPorRacha(int veces) => veces <= 1 ? 1 : (veces == 2 ? 0.5 : 0);
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

  /// Destapa todos los Atascos abiertos (Robot, Robot Turbo, Súper Plomero, Destapacaños, Corre corre): cada uno cuenta.
  void _destaparTodos(int ahora) {
    for (var k = _p.atascos.length; k > 0; k--) {
      _destapado(ahora);
    }
    _p.atascos = [];
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

  /// Llaves sin gastar: las ganadas al mudarte menos lo que costó el Llavero (el Mayordomo real de La Corte regala el
  /// nivel 1 del Mayordomo).
  int get llaves => max(0, _p.llavesGanadas - costoLlavero(_p.llavero) + descuentoLlaveroCorte(_p.corte, _p.llavero));

  /// Nivel de [id] en el Llavero (cortado a su máximo).
  int nivelLlavero(String id) => min(_p.llavero[id] ?? 0, mejoraLlaveroPorId(id)?.limite ?? 0);

  /// Nivel de [id] en la Plomería (cortado a su máximo).
  int nivelPlomeria(String id) => min(tieneObjetoRollos(id), objetoRollosPorId(id)?.limite ?? 0);

  /// Lo que viene de la mudanza: la casa, +`ajustes.llavePct` por Llave sin gastar, Cimientos (x2 por nivel) y Tubería
  /// ancha (x1,5 por nivel). En el Rancho sin nada da x1.
  double get multiplicadorMudanza =>
      multiplicadorCasa(_p.mudanzas) *
      (1 + llaves * ajustes.llavePct) *
      pow(2, nivelLlavero('cimientos')) *
      pow(1.5, nivelPlomeria('tuberia_ancha'));

  /// Llave de paso: la parte del clic del pujo x3 por nivel.
  double get multiplicadorLlavePaso => pow(3, nivelPlomeria('llave_paso')).toDouble();

  /// Cagadas x logros x rollos x comodidad x mudanza x Corte: lo que no se acaba en la corrida.
  double get multiplicadorPermanente =>
      multiplicadorCagadas * multiplicadorLogros * multiplicadorRollos * multiplicadorComodidad * multiplicadorMudanza * multiplicadorCorte;

  /// Suma de efectos temporales sobre la producción (objetos + tipo), tope x4. No incluye la Fiebre.
  double multiplicadorProduccionTemporal(int ahora) {
    var s = 1.0;
    if (_activo('cagada_fresca', ahora)) s += 1;
    if (_activo('empujon', ahora)) s += 1;
    if (_activo('ambientador', ahora)) s += 0.25;
    if (_activo('pino', ahora)) s += 0.5;
    if (_activo('abuela', ahora)) s += 2;
    if (_activo('greca', ahora)) s += 1;
    if (_activo('reina_pepiada', ahora)) s += 0.5;
    if (_activo('jalon_doble', ahora)) s += 1;
    if (_activo('plomero_bono', ahora)) s += 2;
    final t = tipoActivo(ahora);
    if (t == 4) s += fuerzaTipo;
    if (t == 7) s += 2 * fuerzaTipo;
    return s.clamp(0.5, topeEfectos).toDouble();
  }

  /// Suma de efectos temporales sobre el pujo (objetos + tipo), tope x4. No incluye el Pujo loco.
  double multiplicadorPujoTemporal(int ahora) {
    var s = 1.0;
    if (_activo('laxante', ahora)) s += 1;
    final t = tipoActivo(ahora);
    if (t == 2 || t == 4) s += fuerzaTipo;
    if (t == 7) s -= 0.5 * fuerzaTipo;
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

  /// MJ/s de un edificio con todos los efectos (y el x de la temporada). 0 si está atascado.
  double mpsEdificio(String id, int ahora) {
    if (atascado(id)) return 0;
    return _produccionCruda(id) * multiplicadorPermanente * multiplicadorProduccionTemporal(ahora) * (enFiebre(ahora) ? multiplicadorFiebre : 1) *
        multiplicadorTemporadaAhora(ahora);
  }

  /// x de producción de las temporadas activas en [ahora] (Día Mundial del Retrete x3); 1 sin ninguna.
  double multiplicadorTemporadaAhora(int ahora) => multiplicadorTemporada(ajustes.temporadas, ahora);

  /// Si la temporada [id] (`temporadaDiaRetrete`, `temporadaNavidad`) está encendida por el servidor y en rango.
  bool enTemporada(String id, int ahora) => temporadaActiva(ajustes.temporadas, id, ahora);

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
      if (contarAtasco && atascado(e.id)) continue;
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

  /// MJ de un pujo normal (sin épico): ((1 + aporteDedos) × 2^x2 de clic × rollos × Llave de paso + % × MJ/s) × efectos
  /// temporales, x777 en Pujo loco. El % de MJ/s ya trae los rollos dentro, por eso solo la parte del clic se multiplica
  /// por `multiplicadorRollos` (y por la Llave de paso de la Plomería).
  double valorPujo(int ahora) => _conEfectosPujo(
      (1 + aporteDedos) * _multiplicadorClic * multiplicadorRollos * multiplicadorLlavePaso + _pctPujo() * mps(ahora), ahora);

  /// Lo que un edificio suma a cada pujo, con los mismos efectos que `valorPujo` (para el "+N /pujo" de su fila).
  /// Dedo: sus dedos (con los x2 de clic) y Respiración/Mano de Dios. Baño, camión, planta: sus mejoras de %. La suma de
  /// todas las filas más el pujo base (1 × 2^x2) da `valorPujo`.
  double pujoEdificio(String id, int ahora) {
    var v = _pctPujo(id) * mps(ahora);
    if (id == 'dedo') v += aporteDedos * _multiplicadorClic * multiplicadorRollos * multiplicadorLlavePaso;
    return v == 0 ? 0 : _conEfectosPujo(v, ahora);
  }

  /// Probabilidad de que un pujo sea épico: base + un poco por Dedo, con tope. El buff tipo 1 la multiplica (x3) y dobla el tope
  /// (cansado: x2 y tope x1,5).
  double probabilidadEpicoActual(int ahora) {
    final a = ajustes;
    final p = a.epicoBase + a.epicoPorDedo * max(0, cantidad('dedo'));
    if (tipoActivo(ahora) == 1) return min(p * (1 + (a.epicoTipo1 - 1) * fuerzaTipo), a.epicoTope * (1 + fuerzaTipo));
    return min(p, a.epicoTope);
  }

  /// Ritmo que se manda al guardar (`p_mps`, lo usa el servidor para el antitrampa): lo mayor entre el MJ/s sin efectos y
  /// [Ajustes.topePujosSeg] pujos por segundo (20) sin efectos. Así quien vive del Dedo no queda con un ritmo de 0 que le rechace el guardado.
  /// Con [ahora] y el Primo pujador alquilado, suma los 10 pujos por segundo de cada primo ([primosActivos]).
  double ritmoEfectivo([int? ahora]) {
    final m = mpsSinEfectos();
    final pujo = (1 + aporteDedos) * _multiplicadorClic * multiplicadorRollos + _pctPujo() * m;
    final primo = ahora != null && alquiladoActivo('primo', ahora) ? pujosPrimo * primosActivos() : 0;
    // Con el tope de pujos por segundo, nadie puede pujar más rápido que esto a mano: es el ritmo máximo legítimo.
    return max(m, pujo * (ajustes.topePujosSeg + primo));
  }

  /// Un toque al Mojón. Puede salir épico (`probabilidadEpicoActual`), que vale `ajustes.epicoMultiplicador` (x10).
  ResultadoPujo pujar(int ahora) {
    // Tope de pujos por segundo, en ventana deslizante. Un reloj que retrocede vacía la ventana.
    final tope = ajustes.topePujosSeg;
    if (tope > 0) {
      if (_toques.isNotEmpty && ahora < _toques.last) _toques.clear();
      while (_toques.isNotEmpty && ahora - _toques.first >= 1000) {
        _toques.removeFirst();
      }
      if (_toques.length >= tope) return const ResultadoPujo(0, false, contado: false);
      _toques.add(ahora);
    }
    // Ritmo para la presión de Atascos: solo los pujos que contaron.
    if (_pujosRitmo.isNotEmpty && ahora < _pujosRitmo.last) _pujosRitmo.clear();
    _pujosRitmo.add(ahora);
    _limpiarRitmo(ahora);
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

  // ---------- Candados ----------

  /// Lo que abre candados sin pagar: cagadas de candado (tope 3 por día) más media por cada pase diario.
  int get puntosCandado => (cagadasCandado < 0 ? cagadas : min(cagadasCandado, cagadas)) + pases ~/ 2;

  /// Cagadas de MJ que valen para un candado que pide `pide`: las pagadas, como mucho la mitad de lo que pide.
  int _pagadasPara(int pide) => min(_p.cagadasPagadas, pide ~/ 2);

  /// El candado que pide `pide` cagadas está abierto.
  bool candadoAbierto(int pide) => pide <= 0 || puntosCandado + _pagadasPara(pide) >= pide;

  /// Cagadas que le faltan al candado (0 = abierto).
  int faltanCandado(int pide) => max(0, pide - puntosCandado - _pagadasPara(pide));

  /// Se puede abrir pagando con MJ: lo que falta cabe en la mitad que se deja pagar.
  bool candadoPagable(int pide) {
    final f = faltanCandado(pide);
    return f > 0 && f <= pide ~/ 2 - _pagadasPara(pide);
  }

  /// MJ para pagar lo que le falta al candado: cada cagada cuesta [Ajustes.candadoHoras] de producción sin efectos y la
  /// n-ésima pagada sube [Ajustes.candadoSubida] x n. Mínimo 100 por cagada. 0 si no se puede pagar.
  double precioCandado(int pide) {
    if (!candadoPagable(pide)) return 0;
    final base = max(100.0, ajustes.candadoHoras * 3600 * mpsSinEfectos(contarAtasco: false));
    var mj = 0.0;
    for (var k = 0; k < faltanCandado(pide); k++) {
      mj += base * (1 + ajustes.candadoSubida * (_p.cagadasPagadas + k));
    }
    return mj.ceilToDouble();
  }

  /// Paga con MJ lo que le falta al candado. Las cagadas pagadas se quedan aunque jales la cadena.
  bool pagarCandado(int pide) {
    final precio = precioCandado(pide);
    if (precio <= 0 || _p.saldo < precio) return false;
    _p.cagadasPagadas += faltanCandado(pide);
    _p.saldo -= precio;
    return true;
  }

  // ---------- Edificios ----------

  /// Se puede comprar: su candado de cagadas está abierto y ganaste los Rollos de Oro que pide (0 en la fase 1). Gastarlos no lo cierra.
  bool edificioAbierto(String id) {
    final e = edificioPorId(id);
    return e != null && candadoAbierto(e.candado) && _p.rollosGanados >= e.rollos;
  }

  /// Sale en la lista: los de la fase 1 siempre (abiertos o con su candado); los de la fase 2 cuando ya tienes sus rollos.
  bool edificioVisible(String id) {
    final e = edificioPorId(id);
    return e != null && (e.fase1 || _p.rollosGanados >= e.rollos);
  }

  /// Se muestra como "???": no tienes ninguno y no has ganado la mitad de su precio base.
  bool edificioMisterioso(String id) {
    final e = edificioPorId(id);
    return e != null && cantidad(id) == 0 && _p.mjTotal < e.precioBase * ajustes.escalaEdificios / 2;
  }

  /// Descuento de precio activo: tipo 3 (-10%), Constructor (-50%) y Rebaja de la Plomería (-2% por nivel).
  double factorPrecioEdificios(int ahora) =>
      (tipoActivo(ahora) == 3 ? 1 - 0.1 * fuerzaTipo : 1) *
      (_activo('constructor', ahora) ? 0.5 : 1) *
      (1 - 0.02 * nivelPlomeria('rebaja'));

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
      s += (e.precioBase * ajustes.escalaEdificios * pow(ajustes.precioCrecimiento, tiene + k) * f).ceilToDouble();
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
      final p = (e.precioBase * ajustes.escalaEdificios * pow(ajustes.precioCrecimiento, cantidad(id) + n) * f).ceilToDouble();
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
    // Comprar acerca el próximo Atasco.
    _p.presionAtasco += min(presionCompraTope, presionPorCompra * n);
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
        'cadena_trono' => m.precio,
        _ => m.precio * ajustes.escalaMejoras,
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
    return o != null && candadoAbierto(o.candado) && (!o.pideAtasco || _p.vioPrimerAtasco);
  }

  /// Precio en MJ: minutos x MJ/s sin efectos x 60, mínimo 100. La Cagada fresca da 0 (no se compra con MJ: viene con cada
  /// cagada real). Alquilable: el precio del próximo periodo, con descuento por etapa y calor ([precioAlquiler]).
  double precioObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null) return double.infinity;
    if (o.tipo == TipoObjeto.ficha) return 0;
    if (o.tipo == TipoObjeto.alquilable) return precioAlquiler(id, ahora, 1);
    return max(100.0, (o.minutosPrecio * 60 * mpsSinEfectos()).ceilToDouble());
  }

  // ---------- Alquileres (2.13.1) ----------

  /// Precio base de un periodo de [o], sin calor: minutos x MJ/s sin efectos x 60 x (max(MJ/s, 10) / 10) ^ -k, mínimo 100.
  /// Con k = `ajustes.alquilerDescuento` (0.22): a más MJ/s, el alquiler pesa menos en la producción.
  double _baseAlquiler(Objeto o) {
    final m = mpsSinEfectos();
    final descuento = pow(max(m, 10.0) / 10, -ajustes.alquilerDescuento);
    final barato = 1 - 0.1 * nivelLlavero('alquiler_barato');
    return max(100.0, (o.minutosPrecio * 60 * m * descuento * barato).ceilToDouble());
  }

  /// Calor de [id] ahora: periodos alquilados con MJ, que bajan a la mitad cada `ajustes.calorVidaMediaH` horas reales.
  /// Cada alquilable lleva el suyo (alquilar el Primo no encarece el Robot).
  double calor(String id, int ahora) {
    final c = _p.calor[id] ?? 0;
    if (c <= 0) return 0;
    final horas = max(0, ahora - (_p.calorEn[id] ?? ahora)) / 3600000;
    return c * pow(0.5, horas / ajustes.calorVidaMediaH);
  }

  double _porCalor(double calor) => min(pow(ajustes.calorFactor, calor).toDouble(), ajustes.calorTope);

  /// Cuánto multiplica el calor el próximo periodo de [id]: factor ^ calor, hasta el tope (x1,5 por periodo, tope x10).
  double multiplicadorCalor(String id, int ahora) => _porCalor(calor(id, ahora));

  /// Calor por encima del que el precio ya está en el tope: guardar más solo alargaría la bajada.
  double get _calorMaximo =>
      ajustes.calorFactor > 1 ? log(ajustes.calorTope) / log(ajustes.calorFactor) : 0;

  void _calentar(String id, int ahora, int periodos) {
    _p.calor[id] = min(calor(id, ahora) + periodos, _calorMaximo);
    _p.calorEn[id] = ahora;
    if (_p.calor[id]! <= 0) _p.calor.remove(id);
  }

  /// MJ de alquilar [id] [veces] periodos seguidos ahora: la suma de los precios de cada periodo, que suben con el calor
  /// (el periodo i cuesta base x min(factor ^ (calor + i), tope)).
  double precioAlquiler(String id, int ahora, int veces) {
    final o = objetoPorId(id);
    if (o == null || o.tipo != TipoObjeto.alquilable || veces < 1) return double.infinity;
    final base = _baseAlquiler(o);
    final c = calor(id, ahora);
    var total = 0.0;
    for (var i = 0; i < veces; i++) {
      total += (base * _porCalor(c + i)).ceilToDouble();
    }
    return total;
  }

  /// Cuántos primos pujan con el Primo pujador: 1 + uno más por cada x1000 de MJ/s sin efectos (1e3: 2, 1e6: 3...),
  /// hasta `ajustes.maxPrimos` (4) más el Primo extra del Llavero.
  int primosActivos() {
    final m = max(mpsSinEfectos(), 1.0);
    return (1 + (log(m) / ln10 / 3 + 1e-9).floor()).clamp(1, ajustes.maxPrimos + nivelLlavero('primo_extra'));
  }

  /// [id] está en modo Indefinido (se renueva solo cada periodo mientras alcancen los MJ).
  bool alquilerIndefinido(String id) => _p.indefinidos.contains(id);

  /// Se puede poner [id] en Indefinido: alquilable con duración, abierto, no lo está ya, y sigue activo o alcanza para
  /// el primer periodo.
  bool puedeIndefinido(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo != TipoObjeto.alquilable || o.duracion == null || !objetoAbierto(id)) return false;
    if (alquilerIndefinido(id)) return false;
    return alquiladoActivo(id, ahora) || precioAlquiler(id, ahora, 1) <= _p.saldo;
  }

  /// Apaga el Indefinido de [id]: el alquiler sigue hasta su fin y no se renueva. false si no estaba.
  bool apagarIndefinido(String id) => _p.indefinidos.remove(id);

  /// Indefinidos cortados por falta de MJ que la app aún no anotó (id, precio que no alcanzó). Los entrega una vez.
  List<(String, double)> tomarIndefinidosCortados() {
    final r = List.of(_cortados);
    _cortados.clear();
    return r;
  }

  /// Renueva los Indefinidos que se vencieron: cobra el próximo periodo (con calor) y dura uno más desde ahora. Si no
  /// alcanza, se apaga y queda para [tomarIndefinidosCortados]. Tras un offline cobra una sola vez.
  void _renovarIndefinidos(int ahora) {
    for (final id in _p.indefinidos.toList()) {
      final o = objetoPorId(id);
      if (o == null || o.tipo != TipoObjeto.alquilable || o.duracion == null) {
        _p.indefinidos.remove(id);
        continue;
      }
      if ((_p.alquilados[id] ?? 0) > ahora) continue;
      final precio = precioAlquiler(id, ahora, 1);
      if (!objetoAbierto(id) || precio > _p.saldo) {
        _p.indefinidos.remove(id);
        _cortados.add((id, precio));
        continue;
      }
      _p.saldo -= precio;
      _p.alquilados[id] = ahora + o.duracion!.inMilliseconds;
      _calentar(id, ahora, 1);
      _p.alquiladosUsados.add(id);
    }
  }

  /// Lo que falta para poder usar un consumible de nuevo. null = ya se puede. Los alquilables no esperan (2.13.1):
  /// las esperas viejas que traiga una partida no cuentan.
  Duration? esperaRestante(String id, int ahora) {
    if (objetoPorId(id)?.tipo == TipoObjeto.alquilable) return null;
    final fin = _p.esperas[id] ?? 0;
    return fin > ahora ? Duration(milliseconds: fin - ahora) : null;
  }

  /// Compra con MJ. Consumible: al inventario (hasta 5). Alquilable: se activa ya por [veces] periodos (1, 2, 5 o 10;
  /// si sigue activo se suman a su fin, sin pasar de [vecesAlquilerMax] duraciones desde ahora) y paga la suma de esos
  /// periodos con calor. Con [indefinido] queda en modo Indefinido: si no estaba activo paga el primer periodo. Con
  /// [conCiruelas] ya se pagó en el servidor: no cobra MJ ni calienta (un periodo, sin Indefinido).
  bool comprarObjeto(String id, int ahora, {bool conCiruelas = false, int veces = 1, bool indefinido = false}) {
    final alquilable = objetoPorId(id);
    if (alquilable != null && alquilable.tipo == TipoObjeto.alquilable) {
      return _alquilar(alquilable, ahora, conCiruelas: conCiruelas, veces: veces, indefinido: indefinido);
    }
    if (conCiruelas ? !_cabeObjeto(id, ahora) : !puedeComprarObjeto(id, ahora)) return false;
    final o = objetoPorId(id)!;
    final precio = conCiruelas ? 0.0 : precioObjeto(id, ahora);
    if (enInventario(id) >= o.maxInventario) return false;
    _p.inventario[id] = enInventario(id) + 1;
    _p.saldo -= precio;
    return true;
  }

  bool _alquilar(Objeto o, int ahora, {required bool conCiruelas, required int veces, required bool indefinido}) {
    if (indefinido) {
      if (conCiruelas || !puedeIndefinido(o.id, ahora)) return false;
      _p.indefinidos.add(o.id);
      if (alquiladoActivo(o.id, ahora)) return true;
      veces = 1;
    } else if (conCiruelas ? veces != 1 || !_cabeObjeto(o.id, ahora) : !puedeComprarObjeto(o.id, ahora, veces: veces)) {
      return false;
    }
    if (!conCiruelas) _p.saldo -= precioAlquiler(o.id, ahora, veces);
    final d = o.duracion?.inMilliseconds;
    _p.alquilados[o.id] = d == null ? ahora : max(_p.alquilados[o.id] ?? 0, ahora) + d * veces;
    if (!conCiruelas) _calentar(o.id, ahora, veces);
    _p.alquiladosUsados.add(o.id);
    return true;
  }

  /// Cuántos periodos más caben ahora en el alquiler de [id] (fin hasta [vecesAlquilerMax] duraciones desde ahora).
  /// El Guardia (sin duración): 1 si no está activo, 0 si ya lo está.
  int periodosQueCaben(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo != TipoObjeto.alquilable) return 0;
    if (o.duracion == null) return alquiladoActivo(id, ahora) ? 0 : 1;
    final d = o.duracion!.inMilliseconds;
    final desde = max(_p.alquilados[id] ?? 0, ahora);
    return max(0, (ahora + vecesAlquilerMax * d - desde) ~/ d);
  }

  /// Se puede comprar [id] ahora: abierto, con saldo (MJ, o Ciruelas si [conCiruelas]), sin inventario lleno ni espera.
  /// Alquilable: con [veces] periodos que quepan (las Ciruelas pagan uno solo).
  bool puedeComprarObjeto(String id, int ahora, {bool conCiruelas = false, int veces = 1}) {
    final o = objetoPorId(id);
    if (o == null || !_cabeObjeto(id, ahora, veces: veces)) return false;
    if (conCiruelas) return veces == 1 && o.ciruelas > 0 && ciruelas >= o.ciruelas;
    final precio = o.tipo == TipoObjeto.alquilable ? precioAlquiler(id, ahora, veces) : precioObjeto(id, ahora);
    return precio <= _p.saldo;
  }

  /// [id] se puede recibir ahora (sin mirar el precio). Los alquilables no esperan: los frena el calor.
  bool _cabeObjeto(String id, int ahora, {int veces = 1}) {
    final o = objetoPorId(id);
    if (o == null || o.tipo == TipoObjeto.ficha || !objetoAbierto(id)) return false;
    if (o.tipo == TipoObjeto.consumible) return enInventario(id) < o.maxInventario;
    if (o.tipo == TipoObjeto.alquilable) return veces >= 1 && periodosQueCaben(id, ahora) >= veces;
    return esperaRestante(id, ahora) == null;
  }

  /// Usa un consumible del inventario si no hay espera. Papel doble hoja: deja pendiente el doble del próximo dorado.
  /// Destapacaños: destapa (pide un Atasco). La Pintura marrón se usa con [usarPintura].
  bool usarObjeto(String id, int ahora) {
    final o = objetoPorId(id);
    if (o == null || o.tipo != TipoObjeto.consumible || enInventario(id) <= 0 || esperaRestante(id, ahora) != null) return false;
    if (id == 'pintura') return false;
    if (id == 'destapacanos') {
      if (_p.atascos.isEmpty) return false;
      _destaparTodos(ahora);
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
    final r = [
      for (final MapEntry(key: id, value: fin) in _p.esperas.entries)
        if (fin > ahora && objetoPorId(id)?.tipo != TipoObjeto.alquilable) MapEntry(id, fin - ahora)
    ]..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(r);
  }

  /// Ficha Sin espera: borra la espera de [id]. false si no tenía.
  bool quitarEspera(String id, int ahora) {
    if ((_p.esperas[id] ?? 0) <= ahora || objetoPorId(id)?.tipo == TipoObjeto.alquilable) return false;
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
  bool get manaAbierto => candadoAbierto(candadoMana);

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
    return id != 'corre_corre' || _p.atascos.isNotEmpty;
  }

  /// Usa la habilidad [id]: gasta su Maná y arranca su espera. null si no se puede.
  ResultadoHabilidad? usarHabilidad(String id, int ahora) {
    if (!puedeUsarHabilidad(id, ahora)) return null;
    final h = habilidadPorId(id)!;
    var mj = 0.0;
    var fallo = false;
    switch (id) {
      case 'corre_corre':
        _destaparTodos(ahora);
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

  /// Rollos que cuesta el nivel siguiente de [id] (sube x`crecimiento` por nivel). Infinito si no existe.
  double precioObjetoRollos(String id) {
    final o = objetoRollosPorId(id);
    return o == null ? double.infinity : o.precio(tieneObjetoRollos(id)).ceilToDouble();
  }

  /// Se puede comprar [id] con Rollos: abiertos, alcanzan los rollos, bajo su límite (y sin espera la Cadena).
  bool puedeComprarObjetoRollos(String id, int ahora) {
    final o = objetoRollosPorId(id);
    if (o == null || !objetosRollosAbiertos || _p.rollos < precioObjetoRollos(id) || tieneObjetoRollos(id) >= o.limite) return false;
    return id != 'cadena_reserva' || esperaCadena(ahora) == null;
  }

  /// Compra con Rollos de Oro. Los gastados bajan el +% por rollo, pero no cierran edificios ni mejoras.
  bool comprarObjetoRollos(String id, int ahora) {
    if (!puedeComprarObjetoRollos(id, ahora)) return false;
    final precio = precioObjetoRollos(id).toInt();
    _p
      ..rollos -= precio
      ..rollosGastados += precio;
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
      final cansado = fuerzaTipo < 1;
      r.add(EfectoActivo('tipo_$t', b.emoji, b.nombreEs, b.nombreEn, cansado ? '${b.efectoEs} (cansado: mitad)' : b.efectoEs,
          cansado ? '${b.efectoEn} (tired: half)' : b.efectoEn, resta(_p.tipoBuffHasta)));
    }
    r.sort((a, b) => a.restante!.compareTo(b.restante!));
    if (_p.papelDoble) {
      final o = objetoPorId('papel')!;
      r.add(EfectoActivo('papel', o.emoji, o.nombreEs, o.nombreEn, o.descEs, o.descEn, null));
    }
    if (_p.offlineBonus) {
      final x = _textosEfecto['offline_bonus']!;
      if (_p.offlineBonusFuerza < 1) {
        r.add(EfectoActivo('offline_bonus', x.$1, 'Offline x1,25', 'Offline x1.25', 'El próximo offline cuenta x1,25 (cansado: mitad)',
            'Next offline counts x1.25 (tired: half)', null));
      } else {
        r.add(EfectoActivo('offline_bonus', x.$1, x.$2, x.$3, x.$4, x.$5, null));
      }
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
    // Temporadas jugadas con la app abierta (abren logros exclusivos como `dia_retrete`).
    if (s > 0) {
      for (final t in temporadasActivas(ajustes.temporadas, ahora)) {
        _p.temporadas.add(t.id);
      }
    }
    // Alquileres Indefinidos vencidos: se renuevan (o se cortan si no alcanza).
    _renovarIndefinidos(ahora);
    // Primo pujador: 10 pujos por segundo por primo (sin épicos ni contadores de pujos).
    if (s > 0 && alquiladoActivo('primo', ahora)) _ganar(valorPujo(ahora) * pujosPrimo * primosActivos() * s);
    _p.segPartida += s;
    _p.segHistoricos += s;
    if (_p.primerDia <= 0) _p.primerDia = ahora;
    _cuadrilla(ahora, s);
    _mayordomo(ahora, s);
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
        // Imán dorado de la Plomería: +2 s en pantalla por nivel.
        final dur = duracionDoradoVisible.inMilliseconds * (mejoraComprada('brillo') ? 2 : 1) + 2000 * nivelPlomeria('iman_dorado');
        _p.dorado = DoradoVisible(ahora, ahora + dur, 0.1 + 0.8 * _azar.nextDouble(), 0.1 + 0.8 * _azar.nextDouble());
        _programarDorado(ahora);
      }
    }

    // Atascos: el primero seguro al minuto activo; después por presión (~1 cada [Ajustes.atascoSeg] activos), varios a
    // la vez hasta [topeAtascos], uno por edificio.
    if (_p.atascos.isEmpty && s > 0 && !_p.vioPrimerAtasco && _p.segPartida >= segundosPrimerAtasco) _atascar(ahora, 1);
    if (s > 0) _presionarAtasco(ahora, s);
    if (_p.atascos.isNotEmpty && _destapaSolo(ahora)) _destaparTodos(ahora);
    // Con la app abierta ya no quedan Atascos offline pendientes (se sortean otros al salir).
    if (s > 0 && _p.atascosOffline.isNotEmpty) _borrarAtascoOffline();

    _p.ultimaVez = ahora;
    return revisarLogros();
  }

  void _limpiarRitmo(int ahora) {
    while (_pujosRitmo.isNotEmpty && ahora - _pujosRitmo.first > ventanaRitmo) {
      _pujosRitmo.removeFirst();
    }
  }

  /// Factor de la presión de Atascos en [ahora]: x0,6 de novato y hasta x1,5 por el ritmo de pujos de los últimos 10 s.
  double factorPresionAtasco(int ahora) {
    if (_pujosRitmo.isNotEmpty && ahora < _pujosRitmo.last) _pujosRitmo.clear();
    _limpiarRitmo(ahora);
    final porSeg = _pujosRitmo.length / (ventanaRitmo / 1000);
    final novato = _p.segHistoricos < segundosNovato ? presionNovato : 1.0;
    return novato * (1 + presionRitmoMax * min(1.0, porSeg / pujosRitmo));
  }

  /// Suma la presión de [s] segundos activos y, al pasar el umbral, atasca un edificio libre y sortea el umbral
  /// siguiente. Con el tope lleno la presión espera en el umbral.
  void _presionarAtasco(int ahora, double s) {
    if (_p.umbralAtasco <= 0) _p.umbralAtasco = _sortearUmbral();
    // Destapador fino de la Plomería: 25% menos seguido por nivel.
    _p.presionAtasco += s / max(1.0, ajustes.atascoSeg) * factorPresionAtasco(ahora) * pow(0.75, nivelPlomeria('destapador_fino'));
    if (_p.presionAtasco < _p.umbralAtasco) return;
    if (_atascar(ahora, minimoParaAtasco)) {
      _p.presionAtasco = max(0.0, _p.presionAtasco - _p.umbralAtasco);
      _p.umbralAtasco = _sortearUmbral();
    } else {
      _p.presionAtasco = _p.umbralAtasco;
    }
  }

  double _sortearUmbral() => 0.75 + 0.5 * _azar.nextDouble();

  /// Atasca un edificio libre al azar con [minimo] unidades o más, si cabe en [topeAtascos]. El Dedo no produce MJ/s:
  /// no se atasca. Pesa la raíz de lo que produce cada uno: el que más da se tapa más seguido, pero no siempre el mismo.
  /// Devuelve si atascó.
  bool _atascar(int ahora, int minimo) {
    if (_p.atascos.length >= topeAtascos) return false;
    final elegido = _elegirAtascado(minimo);
    if (elegido == null) return false;
    _p.atascos.add(Atasco(elegido, ahora));
    _p.vioPrimerAtasco = true;
    return true;
  }

  /// El edificio que se atasca (ver [_atascar]); null si no hay ninguno libre con [minimo] unidades que produzca.
  /// [sin] = edificios que tampoco valen (los ya programados offline).
  String? _elegirAtascado(int minimo, [Set<String> sin = const {}]) {
    final candidatos = [
      for (final e in edificios)
        if (e.mpsBase > 0 && cantidad(e.id) >= minimo && !atascado(e.id) && !sin.contains(e.id)) e.id
    ];
    if (candidatos.isEmpty) return null;
    final pesos = [for (final id in candidatos) sqrt(max(_produccionCruda(id), 1e-9))];
    var r = _azar.nextDouble() * pesos.fold(0.0, (a, b) => a + b);
    for (var k = 0; k < candidatos.length; k++) {
      r -= pesos[k];
      if (r < 0) return candidatos[k];
    }
    return candidatos.last;
  }

  /// Algo destapa solo en [t] con la app cerrada: Robot o Robot Turbo alquilados hasta después de [t] (o en Indefinido,
  /// que se renueva al volver) o el Súper Plomero.
  bool _cubreAtascoOffline(int t) =>
      _destapaSolo(t) || alquilerIndefinido('robot') || alquilerIndefinido('robot_turbo');

  /// Al salir de la app: sortea cuándo y dónde se atascan edificios con la app cerrada, hasta llenar [topeAtascos]
  /// junto con los que ya están abiertos (uno por edificio, como [_atascar]). El primero: con datos de ausencias
  /// ([Partida.ausenciaMediaMin]) cae entre el 35% y el 65% de la ausencia media (mínimo [Ajustes.atascoOfflineMinimoMin]);
  /// sin datos, mínimo + exponencial con media total [Ajustes.atascoOfflineMediaMin]. Cada siguiente,
  /// [Ajustes.atascoOfflineMediaMin] x 0,6 a 1,4 después del anterior. Queda guardado en la partida y se resuelve en
  /// [aplicarOffline]. Devuelve el primero; null si nunca vio el primer Atasco, si no hay edificios libres o si el tope
  /// ya está lleno. Si ya había programados para después de [ahora], los deja igual (no se vuelve a sortear).
  AtascoOffline? programarAtascoOffline(int ahora) {
    if (!_p.vioPrimerAtasco) return null;
    final vigentes = [
      for (final a in _p.atascosOffline)
        if (a.en > ahora && edificioPorId(a.edificio) != null && cantidad(a.edificio) > 0 && !atascado(a.edificio)) a
    ];
    if (vigentes.isNotEmpty) {
      _p.atascosOffline = vigentes;
      return atascosOfflineProgramados.first;
    }
    _borrarAtascoOffline();
    final minimo = max(0.0, ajustes.atascoOfflineMinimoMin);
    final media = max(minimo, ajustes.atascoOfflineMediaMin);
    final double primero;
    if (_p.ausenciaMediaMin > 0) {
      primero = max(minimo, _p.ausenciaMediaMin * (0.35 + 0.3 * _azar.nextDouble()));
    } else {
      primero = minimo - (media - minimo) * log(1 - _azar.nextDouble());
    }
    var minutos = primero;
    final elegidos = <String>{};
    for (var k = _p.atascos.length; k < topeAtascos; k++) {
      final elegido = _elegirAtascado(minimoParaAtasco, elegidos);
      if (elegido == null) break;
      elegidos.add(elegido);
      _p.atascosOffline.add(AtascoProgramado(ahora + (minutos * 60000).round(), elegido));
      minutos += media * (0.6 + 0.8 * _azar.nextDouble());
    }
    return _p.atascosOffline.isEmpty ? null : atascosOfflineProgramados.first;
  }

  /// Los Atascos offline programados, en orden de hora, con si algo los destapará solo.
  List<AtascoOffline> get atascosOfflineProgramados =>
      [for (final a in _p.atascosOffline) AtascoOffline(a.en, a.edificio, _cubreAtascoOffline(a.en))];

  void _borrarAtascoOffline() => _p.atascosOffline = [];

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
    if (barato != null && comprarEdificio(barato, ahora)) {
      _comprasCuadrilla++;
      _ultimaCuadrilla = barato;
    }
  }

  void _programarDorado(int ahora) {
    final rapido = max(mejoraComprada('iman') ? 2.0 : 1.0, tipoActivo(ahora) == 5 ? 1 + fuerzaTipo : 1.0);
    final a = ajustes.doradoMinMin * 60, b = ajustes.doradoMaxMin * 60;
    // Imán dorado de la Plomería: 10% más seguido por nivel.
    _p.segHastaDorado = (a + (b - a) * _azar.nextDouble()) / rapido / pow(1.1, nivelPlomeria('iman_dorado'));
  }

  /// El Mayordomo está trabajando: lo tienes en el Llavero y no lo apagaste.
  bool get mayordomoTrabajando => nivelLlavero('mayordomo') > 0 && !_p.mayordomoApagado;

  /// Prende o apaga el Mayordomo (se guarda en la partida).
  void cambiarMayordomo() => _p.mayordomoApagado = !_p.mayordomoApagado;

  /// Compras que hizo el Mayordomo en esta sesión (para el aviso).
  int get comprasMayordomo => _comprasMayordomo;

  /// Lo que entra por segundo contando un toque por segundo, como "¿Qué hago ahora?".
  double _ritmoMayordomo(int ahora) => mpsSinEfectos(contarAtasco: false) + valorPujo(ahora);

  /// El edificio que se paga más rápido (precio / lo que suma), con el criterio de "¿Qué hago ahora?". null si ninguno suma.
  String? edificioMasRentable(int ahora) {
    final base = _ritmoMayordomo(ahora);
    String? mejor;
    var mejorRetorno = double.infinity;
    for (final e in edificios) {
      if (!edificioVisible(e.id) || !edificioAbierto(e.id)) continue;
      final precio = precioEdificio(e.id, ahora);
      if (!precio.isFinite) continue;
      final antes = _p.edificios[e.id];
      _p.edificios[e.id] = (antes ?? 0) + 1;
      final double suma;
      try {
        suma = _ritmoMayordomo(ahora) - base;
      } finally {
        if (antes == null) {
          _p.edificios.remove(e.id);
        } else {
          _p.edificios[e.id] = antes;
        }
      }
      if (suma <= 0) continue;
      final r = precio / suma;
      if (r < mejorRetorno) {
        mejorRetorno = r;
        mejor = e.id;
      }
    }
    return mejor;
  }

  /// Mayordomo del Llavero: cada 10 s, 3 s o 1 s activos (según el nivel) compra el edificio más rentable si alcanza.
  /// Solo edificios y solo con la app abierta (offline no compra).
  void _mayordomo(int ahora, double s) {
    final n = nivelLlavero('mayordomo');
    if (n <= 0 || _p.mayordomoApagado) {
      _segMayordomo = 0;
      return;
    }
    _segMayordomo += s;
    final ciclo = segundosMayordomo[min(n, segundosMayordomo.length) - 1];
    if (_segMayordomo < ciclo) return;
    _segMayordomo -= ciclo;
    final id = edificioMasRentable(ahora);
    if (id != null && comprarEdificio(id, ahora)) _comprasMayordomo++;
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

  /// Un toque al destapador (va al primer Atasco). null si no hay Atasco. Al toque 10 se destapa y el siguiente pasa a
  /// ser el primero; en menos de 3 s desde que fue el primero es perfecto (5 min de ese edificio).
  ResultadoDestape? tocarAtasco(int ahora) {
    final a = _p.atasco;
    if (a == null) return null;
    a.toques++;
    if (a.toques < toquesAtasco) return ResultadoDestape(a.edificio, a.toques, toquesAtasco - a.toques, false, false, 0);
    final perfecto = ahora - a.desde < tiempoDestapePerfecto.inMilliseconds;
    _p.atascos.removeAt(0);
    _p.atasco?.desde = ahora; // el perfecto del siguiente cuenta desde que pasa adelante
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

  /// Juega poco: menos de 1 h activa por día en promedio desde su primer día (sin datos aún, no).
  bool get juegaPoco {
    if (_p.primerDia <= 0 || _p.ultimaVez <= _p.primerDia) return false;
    final dias = max(1.0, (_p.ultimaVez - _p.primerDia) / Duration.millisecondsPerDay);
    return _p.segHistoricos / dias < segundosPocoJuego;
  }

  /// Tope offline: 2 h (la base de los ajustes), 4 h o 8 h según los tanques; 6 h como mínimo si juega poco. Nunca
  /// menos que la base. Suma el Tanque extra (Fichas) y los Tanques de lujo (Rollos, +1 h c/u).
  Duration get topeOffline {
    final h = max(mejoraComprada('tanque_8') ? 8.0 : (mejoraComprada('tanque_4') ? 4.0 : 0.0), juegaPoco ? topeOfflinePocoJuegoH : 0.0);
    final extra = _p.horasExtraTanque + tieneObjetoRollos('tanque_lujo');
    return Duration(seconds: ((max(h, ajustes.offlineTopeH) + extra) * 3600).round());
  }

  /// Qué parte cuenta offline: 25% (la base de los ajustes), 50% o 75% según las válvulas. Nunca menos que la base, que
  /// sube 10 puntos por nivel del Tanque hondo de la Plomería (hasta 75%).
  double get porcentajeOffline {
    final base = max(ajustes.offlinePorcentaje, min(0.75, ajustes.offlinePorcentaje + 0.10 * nivelPlomeria('tanque_hondo')));
    return max(mejoraComprada('valvula_75') ? 0.75 : (mejoraComprada('valvula_50') ? 0.5 : 0.0), base).toDouble();
  }

  /// Cobra el tiempo fuera (sin efectos temporales ni dorados). El Atasco que quedó sigue tapado fuera: ese edificio no cuenta. x1,5 si quedó el buff del tipo 6 (y se gasta).
  /// Guardia nocturno: cuenta al 100% con tope de 8 h (o el del tanque si es más) y se gasta.
  /// Atascos offline ([programarAtascoOffline]): cada uno que cae dentro del tiempo contado y que nada destapa solo deja
  /// sin contar su edificio desde su hora y al volver queda atascado; los cubiertos no cuestan y suman un destape. Se
  /// borran siempre. La ausencia (de [minimoOffline] o más) entra en la media móvil [Partida.ausenciaMediaMin].
  ResultadoOffline aplicarOffline(int desdeMs, int ahoraMs) {
    final ausente = max(0, ahoraMs - desdeMs) / 1000.0;
    _p.ultimaVez = ahoraMs;
    _p.dorado = null;
    for (final a in _p.atascos) {
      a.desde = ahoraMs; // vuelven a verse ahora
    }
    if (ausente >= minimoOffline.inSeconds) {
      final minutos = (ausente / 60).clamp(1.0, 1440.0).toDouble();
      _p.ausenciaMediaMin = _p.ausenciaMediaMin > 0 ? 0.7 * _p.ausenciaMediaMin + 0.3 * minutos : minutos;
    }
    // La Arepa reina pepiada solo corre con la app abierta: se corre su fin lo que estuviste fuera.
    final arepa = _p.efectos['reina_pepiada'];
    if (arepa != null && arepa > desdeMs && ahoraMs > desdeMs) _p.efectos['reina_pepiada'] = arepa + (ahoraMs - desdeMs);
    final programados = List.of(_p.atascosOffline)..sort((a, b) => a.en.compareTo(b.en));
    _borrarAtascoOffline();
    if (ausente < minimoOffline.inSeconds) return ResultadoOffline(ausente, 0, 0, false, false);
    final guardia = _p.alquilados.remove('guardia') != null;
    final tope = guardia ? max(topeOffline.inSeconds, topeGuardia.inSeconds).toDouble() : topeOffline.inSeconds.toDouble();
    final contados = min(ausente, tope);
    final bonus = _p.offlineBonus;
    final fuerzaBonus = _p.offlineBonusFuerza.clamp(0, 1).toDouble();
    _p.offlineBonus = false;
    _p.offlineBonusFuerza = 1;
    // El x de temporada cuenta solo por la parte del tiempo contado que cayó dentro de ella.
    final xTemporada = multiplicadorEnRango(ajustes.temporadas, desdeMs, desdeMs + (contados * 1000).round());
    final factor = (guardia ? 1.0 : porcentajeOffline) * (bonus ? 1 + 0.5 * fuerzaBonus : 1) * xTemporada;
    final finContado = desdeMs + (contados * 1000).round();
    final base = mpsSinEfectos(); // antes de los Atascos offline: hasta su hora cada edificio producía
    final caidos = <AtascoOffline>[];
    var perdido = 0.0;
    for (final a in programados) {
      final id = a.edificio;
      if (a.en < desdeMs || a.en >= finContado || atascado(id) || edificioPorId(id) == null || cantidad(id) <= 0) continue;
      if (caidos.any((c) => c.edificio == id)) continue;
      final cubierto = _cubreAtascoOffline(a.en);
      if (!cubierto && _p.atascos.length >= topeAtascos) continue;
      caidos.add(AtascoOffline(a.en, id, cubierto));
      if (cubierto) {
        _p.destapes++;
      } else {
        // Por tramos: ese edificio deja de contar desde su hora hasta el fin del tiempo contado.
        perdido += (finContado - a.en) / 1000 * _produccionCruda(id) * multiplicadorPermanente * factor;
        _p.atascos.add(Atasco(id, ahoraMs)); // vuelve a verse ahora, como el que quedó al salir
      }
    }
    final ganado = max(0.0, contados * base * factor - perdido);
    final regalo = ausente >= ausenciaRegalo.inSeconds ? horasRegalo * 3600 * mpsSinEfectos(contarAtasco: false) : 0.0;
    _ganar(ganado + regalo);
    return ResultadoOffline(ausente, contados, ganado + regalo, ausente >= tope, bonus,
        conGuardia: guardia,
        regalo: regalo,
        fuerzaBonus: fuerzaBonus,
        atascos: caidos,
        mjPerdidos: perdido);
  }

  /// Qué avisar con la app cerrada y en cuánto: lo más barato que todavía no alcanza (mejora o edificio) si lo offline
  /// lo paga antes de llenar el tope; si no, cuándo se llena el tope ([AvisoCerrado.nombreEs] null). null = nada que avisar.
  AvisoCerrado? avisoAlCerrar(int ahora) {
    final ritmo = mpsSinEfectos(contarAtasco: false) * porcentajeOffline;
    if (ritmo <= 0) return null;
    final tope = topeOffline.inSeconds.toDouble();
    AvisoCerrado? mejor;
    void mirar(double precio, String es, String en) {
      if (precio <= _p.saldo) return;
      final seg = (precio - _p.saldo) / ritmo;
      if (seg <= tope && (mejor == null || seg < mejor!.segundos)) mejor = AvisoCerrado(seg, es, en);
    }

    for (final m in mejorasDisponibles()) {
      mirar(precioMejora(m), m.nombreEs, m.nombreEn);
    }
    for (final e in edificios) {
      if (edificioVisible(e.id) && edificioAbierto(e.id) && !edificioMisterioso(e.id)) {
        final (es, en) = nombresEdificio(e.id, _p.mudanzas);
        mirar(precioEdificio(e.id, ahora), es, en);
      }
    }
    return mejor ?? AvisoCerrado(tope, null, null);
  }

  /// Empujón del servidor para quien se quedó atrás: x2 por 30 min (se suma si ya había uno).
  void darEmpujon(int ahora) => _p.efectos['empujon'] = max(_p.efectos['empujon'] ?? 0, ahora) + duracionEmpujon.inMilliseconds;

  // ---------- Cagadas reales ----------

  /// Cobra cagadas reales nuevas: una Descarga por cada una (15 min x (1 + 0,1 x peso)), una sola Fiebre de Trono
  /// y el buff del tipo más reciente por 1 h. Llenan el Maná de Tripa. Las Fichas no cambian aquí (las da el servidor).
  /// Repetir el mismo tipo seguido cansa el buff ([fuerzaPorRacha]): la 2.a vez a la mitad, desde la 3.a no da buff (la
  /// Descarga y la Fiebre sí). Una cagada sin tipo no cuenta; más de 24 h desde la última con tipo reinicia la racha.
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
    for (final c in orden) {
      if (c.tipo == null || !buffsTipo.containsKey(c.tipo)) continue;
      final en = c.creada.millisecondsSinceEpoch;
      final seguido = c.tipo == _p.rachaTipo && en - _p.rachaTipoEn <= ventanaRachaTipo.inMilliseconds;
      _p.rachaTipoVeces = seguido ? _p.rachaTipoVeces + 1 : 1;
      _p.rachaTipo = c.tipo;
      _p.rachaTipoEn = en;
      tipo = c.tipo;
    }
    final fuerza = tipo == null ? 1.0 : fuerzaPorRacha(_p.rachaTipoVeces);
    // Con fuerza 0 no hay buff nuevo: el que estaba sigue hasta su fin, sin alargarse.
    if (tipo != null && fuerza > 0) {
      _p.tipoBuff = tipo;
      _p.tipoBuffHasta = ahora + duracionBuffTipo.inMilliseconds + nivelCorte('catador') * catadorPorNivel.inMilliseconds;
      _p.tipoBuffFuerza = fuerza;
      if (tipo == 6) {
        _p.offlineBonus = true;
        _p.offlineBonusFuerza = fuerza;
      }
    }
    return ResultadoCagadas(orden.length, descargas, tipo, enFiebreDorada, fuerza: fuerza);
  }

  // ---------- Jalar la cadena ----------

  /// Rollos de Oro que da todo lo ganado en esta casa: piso((MJ de la casa / divisor de la casa / divisor) ^ exponente)
  /// x (1 + mudanzas). En el Rancho (sin mudanzas) son los MJ de toda la historia, como antes.
  int get rollosTotales => rollosPorMj(_p.mjCasa / divisorRollosCasa, ajustes) * factorRollosCasa(_p.mudanzas);

  /// Cuántas veces menos Rollos rinden los MJ en esta casa: `mudanzaDivisorX` ^ mudanzas (Rancho = 1).
  double get divisorRollosCasa => pow(max(1.0, ajustes.mudanzaDivisorX), max(0, _p.mudanzas)).toDouble();

  /// Rollos que da jalar ahora: los totales menos los que ya ganaste en esta casa (los gastados cuentan). Nunca negativo.
  int get rollosPorGanar => max(0, rollosTotales - _p.rollosGanados);

  /// MJ que faltan para que jalar dé más rollos que ahora (en casas grandes salta de a 1 + mudanzas).
  double get mjParaSiguienteRollo {
    final f = factorRollosCasa(_p.mudanzas);
    final meta = mjParaRollos(max(rollosTotales, _p.rollosGanados) ~/ f + 1, ajustes) * divisorRollosCasa;
    return max(0, meta - _p.mjCasa);
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
  /// Fase 2: se van los alquilados (y sus Indefinidos; el calor se queda) y la Pintura; se quedan las esperas de habilidades (`hab_*`), el Maná y los objetos
  /// de Rollos. La Cadena de reserva pendiente se gasta: devuelve 1 edificio de cada tipo que tenías.
  int jalar() {
    final ganados = rollosPorGanar;
    final reserva = tieneObjetoRollos('cadena_reserva') > 0;
    final devueltos = {for (final MapEntry(key: id, value: n) in _p.edificios.entries) if (n > 0) id: 1};
    _p
      ..rollos += ganados
      ..jaladas += 1;
    _reiniciarCorrida();
    if (reserva) {
      _p.edificios = devueltos;
      _p.objetosRollos.remove('cadena_reserva');
    }
    _empezarCorrida();
    revisarLogros();
    return ganados;
  }

  /// Lo que se va al jalar y al mudarse: la corrida entera (ver [jalar]).
  void _reiniciarCorrida() {
    final habilidadesEnEspera = {for (final e in _p.esperas.entries) if (e.key.startsWith('hab_')) e.key: e.value};
    _p
      ..saldo = 0
      ..edificios = {}
      ..mejoras = {}
      ..inventario = {}
      ..esperas = habilidadesEnEspera
      ..alquilados = {}
      ..indefinidos = {}
      ..pintura = {}
      ..atascos = []
      ..atascosOffline = []
      ..presionAtasco = 0
      ..umbralAtasco = 0
      ..dorado = null
      ..segHastaDorado = -1
      ..papelDoble = false
      ..pujosRecientes = []
      ..segPartida = 0;
    _p.efectos.removeWhere((id, _) => !efectosQueSobrevivenJalada.contains(id));
    _segCuadrilla = 0;
    _segMayordomo = 0;
  }

  /// Lo que trae cada corrida nueva: Tubería lista (+10 por nivel de cada edificio de la fase 1) y Ahorros del Llavero
  /// (1e3 x 1000^nivel MJ de saldo; no suman a los MJ ganados, así no dan Rollos).
  void _empezarCorrida() {
    final lista = nivelPlomeria('tuberia_lista');
    if (lista > 0) {
      for (final e in edificiosFase1) {
        _p.edificios[e.id] = cantidad(e.id) + 10 * lista;
      }
    }
    final ahorros = nivelLlavero('ahorros');
    if (ahorros > 0) _p.saldo = max(_p.saldo, 1e3 * pow(1000, ahorros));
  }

  // ---------- Mudanza 🏠 ----------

  /// Rollos de la casa contra los que se cuentan las Llaves: `ajustes.mudanzaRollos` x `mudanzaRollosSubida` ^ mudanzas.
  double get rollosBaseMudanza => ajustes.mudanzaRollos * pow(ajustes.mudanzaRollosSubida, _p.mudanzas);

  /// Rollos ganados en esta casa que pide la mudanza: [rollosBaseMudanza] con el Maestro de obras de La Corte (10% menos
  /// por nivel, nunca menos de la mitad). El servidor hace lo mismo en `imperio_mudar`.
  double get rollosParaMudanza => rollosBaseMudanza * max(0.5, 1 - 0.1 * nivelCorte('maestro_obras'));

  /// Rollos ganados en esta casa (los gastados en la Plomería cuentan).
  int get rollosCasa => _p.rollosGanados;

  /// Llaves que daría mudarse ahora: piso((rollos de la casa / requisito) ^ exponente x factor). 0 sin llegar al requisito.
  int get llavesPorGanar {
    final r = rollosBaseMudanza;
    if (rollosCasa < rollosParaMudanza || r <= 0) return 0;
    return (pow(rollosCasa / r, ajustes.mudanzaLlavesExponente) * ajustes.mudanzaLlavesFactor + 1e-9).floor();
  }

  /// Se puede mudar: rollos de la casa, jaladas en la casa y [cagadasCasa] reales desde que llegaste (las cuenta el
  /// servidor, máx 3 por día). El servidor revisa lo mismo en `imperio_mudar`.
  bool puedeMudarse(int cagadasCasa) =>
      rollosCasa >= rollosParaMudanza && _p.jaladasCasa >= ajustes.mudanzaJaladas && cagadasCasa >= ajustes.mudanzaCagadas;

  /// Se muda a la casa siguiente y devuelve las Llaves ganadas ([llavesServidor] si las mandó el servidor).
  /// Se va: la corrida (como al jalar), los Rollos (saldo y ganados), la Plomería (el Camión de mudanza se lleva un
  /// 10% por nivel de cada nodo) y las jaladas de la casa. Se queda: logros, cosméticos, mjTotal, jaladas históricas,
  /// Llaves y Llavero. [mjBaseServidor]: los MJ con los que el servidor marcó la llegada (si no, los de aquí).
  /// [ahora]: cuándo llegaste a la casa nueva ([Partida.casaEn]).
  int mudarse({int? llavesServidor, double? mjBaseServidor, int? ahora}) {
    final ganadas = max(0, llavesServidor ?? llavesPorGanar);
    if (_p.rollosGastados == 0) _p.mudanzasLimpias += 1;
    final camion = nivelLlavero('camion_mudanza');
    final quedan = <String, int>{};
    if (camion > 0) {
      for (final MapEntry(key: id, value: n) in _p.objetosRollos.entries) {
        if (id == 'cadena_reserva') continue;
        final q = (n * 0.1 * camion + 1e-9).floor();
        if (q > 0) quedan[id] = q;
      }
    }
    _reiniciarCorrida();
    _p
      ..rollos = 0
      ..rollosGastados = 0
      ..objetosRollos = quedan
      ..cadenaReservaEn = 0
      ..mjBase = min(_p.mjTotal, max(0.0, mjBaseServidor ?? _p.mjTotal))
      ..mjEnCasa = 0
      ..jaladasBase = _p.jaladas
      ..mudanzas += 1
      ..llavesGanadas += ganadas
      ..casaEn = ahora ?? 0;
    _empezarCorrida();
    revisarLogros();
    return ganadas;
  }

  /// Se puede comprar el nivel siguiente de [id] en el Llavero.
  bool puedeComprarLlavero(String id) {
    final m = mejoraLlaveroPorId(id);
    if (m == null) return false;
    final n = nivelLlavero(id);
    return n < m.limite && llaves >= m.precio(n);
  }

  /// Compra el nivel siguiente de [id] con Llaves. El Mayordomo nuevo arranca prendido.
  bool comprarLlavero(String id) {
    if (!puedeComprarLlavero(id)) return false;
    _p.llavero[id] = nivelLlavero(id) + 1;
    if (id == 'mayordomo' && _p.llavero[id] == 1) _p.mayordomoApagado = false;
    revisarLogros();
    return true;
  }

  // ---------- Abdicar 👑 y La Corte ----------

  /// Coronas sin gastar: las ganadas abdicando menos lo que costó La Corte.
  int get coronas => max(0, _p.coronasGanadas - costoCorte(_p.corte));

  /// Nivel de [id] en La Corte (cortado a su máximo).
  int nivelCorte(String id) => min(_p.corte[id] ?? 0, mejoraCortePorId(id)?.limite ?? 0);

  /// Lo que viene de La Corte: Bufón (x3 por nivel) y +`ajustes.coronaPct` por Corona sin gastar. Sin abdicar da x1.
  double get multiplicadorCorte => pow(3, nivelCorte('bufon')) * (1 + coronas * ajustes.coronaPct);

  /// Coronas que daría abdicar ahora: piso((Llaves ganadas / requisito) ^ exponente x factor). 0 sin llegar al requisito.
  int get coronasPorGanar {
    final r = ajustes.abdicarLlaves;
    if (_p.llavesGanadas < r || r <= 0) return 0;
    return (pow(_p.llavesGanadas / r, ajustes.abdicarCoronasExponente) * ajustes.abdicarCoronasFactor + 1e-9).floor();
  }

  /// Se puede abdicar: mudanzas, Llaves ganadas en el reinado y [cagadasReinado] reales desde la última abdicación (las
  /// cuenta el servidor, máx 3 por día). El servidor revisa lo mismo en `imperio_abdicar`.
  bool puedeAbdicar(int cagadasReinado) =>
      _p.mudanzas >= ajustes.abdicarMudanzas && _p.llavesGanadas >= ajustes.abdicarLlaves && cagadasReinado >= ajustes.abdicarCagadas;

  /// Abdica y devuelve las Coronas ganadas ([coronasServidor] si las mandó el servidor).
  /// Se va: todo lo que se va al mudarse, las casas (vuelves al Rancho, o más arriba con el Heraldo), las Llaves (el
  /// Tesorero guarda un 10% por nivel de las ganadas) y el Llavero (el Mayordomo real deja el Mayordomo en nivel 1).
  /// Se queda: logros, cosméticos, mjTotal, jaladas históricas, Coronas y La Corte. Los datos del servidor
  /// ([mudanzasServidor], [llavesServidor], [mjBaseServidor]) mandan sobre la cuenta de aquí.
  int abdicar({int? coronasServidor, int? mudanzasServidor, int? llavesServidor, double? mjBaseServidor, int? ahora}) {
    final ganadas = max(0, coronasServidor ?? coronasPorGanar);
    if (costoLlavero(_p.llavero) - descuentoLlaveroCorte(_p.corte, _p.llavero) <= 0) _p.abdicacionesAvaras += 1;
    final casa = max(0, mudanzasServidor ?? nivelCorte('heraldo'));
    final llavesQuedan = max(0, llavesServidor ?? (_p.llavesGanadas * 0.1 * nivelCorte('tesorero') + 1e-9).floor());
    final mayordomo = nivelCorte('mayordomo_real') >= 1;
    _reiniciarCorrida();
    _p
      ..rollos = 0
      ..rollosGastados = 0
      ..objetosRollos = {}
      ..cadenaReservaEn = 0
      ..mjBase = min(_p.mjTotal, max(0.0, mjBaseServidor ?? _p.mjTotal))
      ..mjEnCasa = 0
      ..jaladasBase = _p.jaladas
      ..mudanzas = casa
      ..llavesGanadas = llavesQuedan
      ..llavero = {if (mayordomo) 'mayordomo': 1}
      ..abdicaciones += 1
      ..coronasGanadas += ganadas
      ..casaEn = ahora ?? 0;
    if (mayordomo) _p.mayordomoApagado = false;
    _empezarCorrida();
    revisarLogros();
    return ganadas;
  }

  /// Se puede comprar el nivel siguiente de [id] en La Corte.
  bool puedeComprarCorte(String id) {
    final m = mejoraCortePorId(id);
    if (m == null) return false;
    final n = nivelCorte(id);
    return n < m.limite && coronas >= m.precio(n);
  }

  /// Compra el nivel siguiente de [id] con Coronas. El Mayordomo real trae el Mayordomo del Llavero ya en este reinado.
  bool comprarCorte(String id) {
    if (!puedeComprarCorte(id)) return false;
    _p.corte[id] = nivelCorte(id) + 1;
    if (id == 'mayordomo_real' && nivelLlavero('mayordomo') == 0) {
      _p.llavero['mayordomo'] = 1;
      _p.mayordomoApagado = false;
    }
    revisarLogros();
    return true;
  }

  // ---------- Veteranos ----------

  /// Lo que trae un veterano: cagadas, multiplicador, Fichas y candados abiertos.
  ResumenBienvenida bienvenida() =>
      ResumenBienvenida(cagadas, multiplicadorCagadas, fichas, candadosFase1.where((c) => candadoAbierto(c.cagadas)).length);

  // ---------- Regalos (el servidor valida y cuenta; aquí solo se cobra) ----------

  /// MJ de un Rollo de regalo: [minutos] (1 a 60) de producción propia al MJ/s de ahora sin efectos, más 13 como la Lluvia.
  static double mjDeRegalo(int minutos, double mps) {
    final m = minutos.clamp(0, 60);
    if (m == 0) return 0;
    return m * 60 * (mps.isFinite && mps > 0 ? mps : 0) + 13;
  }

  /// Abre un Rollo de regalo que el servidor ya dio por bueno: suma la producción y devuelve los MJ. El atasco no resta.
  double abrirRegalo(int minutos) {
    final mj = mjDeRegalo(minutos, mpsSinEfectos(contarAtasco: false));
    _ganar(mj);
    return mj;
  }

  /// Logros de regalos con lo que contó el servidor: [dados] en total y [mutuo] (abriste uno de alguien a quien también le diste).
  List<Logro> logrosDeRegalos({int dados = 0, bool mutuo = false}) {
    final ids = {if (dados >= 1) 'regalo_primero', if (dados >= 10) 'regalo_diez', if (mutuo) 'regalo_mutuo'};
    final nuevos = <Logro>[];
    for (final l in logros) {
      if (ids.contains(l.id) && _p.logros.add(l.id)) nuevos.add(l);
    }
    return nuevos;
  }
}
