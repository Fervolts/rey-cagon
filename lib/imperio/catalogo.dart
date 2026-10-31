// Catálogo del Imperio Cagón, fase 1. Solo datos: los números salen de la nota "Imperio Cagón (catálogo)".
// Dart puro (sin Flutter) para poder probarlo. Los textos vienen en pares es/en; la pantalla escoge con tr().

import 'estado.dart';

/// Edificio que produce MJ por segundo.
class Edificio {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String chisteEs, chisteEn;
  final double precioBase;
  final double mpsBase;

  /// Cagadas reales que pide para poder comprarlo.
  final int candado;

  /// false = llega después: nunca se ve ni se compra en la fase 1.
  final bool fase1;

  const Edificio(this.id, this.emoji, this.nombreEs, this.nombreEn, this.chisteEs, this.chisteEn, this.precioBase, this.mpsBase, this.candado,
      {this.fase1 = true});
}

const List<Edificio> edificios = [
  Edificio('dedo', '👆', 'Dedo que puja', 'Pushing finger', 'Puja por ti, cada 10 s', 'Pushes for you, every 10 s', 15, 0.1, 0),
  Edificio('ciruela', '🫐', 'Ciruela pasa', 'Prune', 'Lo natural', 'All natural', 100, 1, 0),
  Edificio('cafe', '☕', 'Café negro', 'Black coffee', 'El de las 7 am', 'The 7 a.m. one', 1100, 8, 0),
  Edificio('arepa', '🫓', 'Arepa con caraotas', 'Arepa with beans', 'Combustible nacional', 'National fuel', 12000, 47, 0),
  Edificio('inodoro', '🚽', 'Inodoro extra', 'Spare toilet', 'Ya no hay cola', 'No more waiting in line', 130000, 260, 3),
  Edificio('bano', '🚻', 'Baño público', 'Public restroom', 'Producción masiva', 'Mass production', 1.4e6, 1400, 5),
  Edificio('camion', '🚛', 'Camión vacuum', 'Vacuum truck', 'Recolección a domicilio', 'Home pickup service', 20e6, 7800, 10),
  Edificio('planta', '🏭', 'Planta de tratamiento', 'Treatment plant', 'Industria seria', 'Serious industry', 330e6, 44000, 10),
  Edificio('cloaca', '🕳️', 'Cloaca municipal', 'City sewer', 'Todo el pueblo trabaja para ti', 'The whole town works for you', 5.1e9, 260000, 30,
      fase1: false),
  Edificio('granja', '🌱', 'Granja de abono', 'Compost farm', 'Agro-mojón', 'Agro-poop', 75e9, 1.6e6, 30, fase1: false),
  Edificio('mina', '⛏️', 'Mina de metano', 'Methane mine', 'Energía del futuro', 'Energy of the future', 1e12, 10e6, 30, fase1: false),
  Edificio('templo', '🛕', 'Templo del Trono', 'Throne temple', 'Culto al Rey', 'All hail the King', 14e12, 65e6, 60, fase1: false),
  Edificio('volcan', '🌋', 'Volcán digestivo', 'Digestive volcano', 'La Tierra también caga', 'Earth poops too', 170e12, 430e6, 60, fase1: false),
  Edificio('laxante_tiempo', '⏳', 'Laxante del tiempo', 'Time laxative', 'Cagas ayer y mañana', 'Poop yesterday and tomorrow', 2.1e15, 2.9e9, 100,
      fase1: false),
  Edificio('agujero', '🌌', 'Agujero negro intestinal', 'Intestinal black hole', 'Nada escapa', 'Nothing escapes', 26e15, 21e9, 150, fase1: false),
];

/// Los 8 edificios de la fase 1, en orden.
final List<Edificio> edificiosFase1 = [for (final e in edificios) if (e.fase1) e];

final Map<String, Edificio> _edificioPorId = {for (final e in edificios) e.id: e};

/// Edificio por id, o null si no existe.
Edificio? edificioPorId(String id) => _edificioPorId[id];

/// Familias de mejoras (pestaña MEJORAS).
enum FamiliaMejora { clic, edificio, idle, dorado, incienso }

/// Mejora que se compra una vez y queda.
class Mejora {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String efectoEs, efectoEn;
  final double precio;
  final FamiliaMejora familia;

  /// Edificio al que pertenece (familia edificio) o del que depende (clic: Dedo). La mejora solo sale si ese edificio está abierto.
  final String? edificio;

  /// Cuándo aparece en la tienda.
  final bool Function(Partida p) condicion;

  const Mejora(this.id, this.emoji, this.nombreEs, this.nombreEn, this.efectoEs, this.efectoEn, this.precio, this.familia, this.condicion,
      {this.edificio});
}

int _n(Partida p, String id) => p.edificios[id] ?? 0;

/// Niveles de las mejoras por edificio y cuántas veces el precio base cuestan.
const List<(int, double)> nivelesMejoraEdificio = [(1, 10), (5, 50), (25, 500)];

// Nombres de las 3 mejoras de cada edificio (al tener 1, 5 y 25).
const Map<String, List<(String, String)>> _nombresMejoraEdificio = {
  'dedo': [('Uña larga', 'Long nail'), ('Dedo enguantado', 'Gloved finger'), ('Dedos ambidiestros', 'Ambidextrous fingers')],
  'ciruela': [('Ciruela remojada', 'Soaked prune'), ('Jugo de ciruela', 'Prune juice'), ('Ciruela de la abuela', "Grandma's prunes")],
  'cafe': [('Doble carga', 'Double shot'), ('Café de bodega', 'Corner store coffee'), ('Guayoyo', 'Watery joe')],
  'arepa': [('Arepa con queso', 'Cheese arepa'), ('Arepa rellena', 'Stuffed arepa'), ('Arepera 24 horas', '24-hour arepa joint')],
  'inodoro': [('Tapa acolchada', 'Padded lid'), ('Asiento caliente', 'Heated seat'), ('Bidet', 'Bidet')],
  'bano': [('Papel en todos los cubículos', 'Paper in every stall'), ('Señora de la limpieza', 'The cleaning lady'), ('Baño de terminal', 'Bus station restroom')],
  'camion': [('Manguera larga', 'Extra long hose'), ('Ruta nocturna', 'Night route'), ('Flota municipal', 'City fleet')],
  'planta': [('Filtro de arena', 'Sand filter'), ('Bacterias obreras', 'Worker bacteria'), ('Planta modelo', 'Model plant')],
};

/// Id de la mejora de un edificio para un nivel (1, 5 o 25): 'dedo_1', 'cafe_25'.
String idMejoraEdificio(String edificio, int nivel) => '${edificio}_$nivel';

List<Mejora> _mejorasDeEdificios() => [
      for (final e in edificiosFase1)
        for (var i = 0; i < nivelesMejoraEdificio.length; i++)
          Mejora(
            idMejoraEdificio(e.id, nivelesMejoraEdificio[i].$1),
            e.emoji,
            _nombresMejoraEdificio[e.id]![i].$1,
            _nombresMejoraEdificio[e.id]![i].$2,
            '${e.nombreEs} produce x2',
            '${e.nombreEn} makes x2',
            e.precioBase * nivelesMejoraEdificio[i].$2,
            FamiliaMejora.edificio,
            (p) => _n(p, e.id) >= nivelesMejoraEdificio[i].$1,
            edificio: e.id,
          ),
    ];

/// Las 36 mejoras de la fase 1.
final List<Mejora> mejoras = [
  // Clic (5)
  Mejora('guantes', '🧤', 'Guantes de látex', 'Latex gloves', 'Pujo x2', 'Push x2', 100, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 1, edificio: 'dedo'),
  Mejora('faja', '🩲', 'Faja de pujo', 'Pushing belt', 'Pujo x2', 'Push x2', 500, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 1, edificio: 'dedo'),
  Mejora('dedo_acero', '🦾', 'Dedo de acero', 'Steel finger', 'Pujo x2', 'Push x2', 10000, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 10,
      edificio: 'dedo'),
  Mejora('respiracion', '🫁', 'Pujo con respiración', 'Breathing technique', 'Cada pujo suma además 1% de tu MJ/s', 'Each push also adds 1% of your MJ/s',
      100000, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 25, edificio: 'dedo'),
  Mejora('mano_dios', '🙌', 'Mano de dios', 'Hand of god', 'Cada pujo suma otro 1% de tu MJ/s', 'Each push adds another 1% of your MJ/s', 10e6,
      FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 50, edificio: 'dedo'),
  // Por edificio (24)
  ..._mejorasDeEdificios(),
  // Idle (4)
  Mejora('tanque_4', '🛢️', 'Tanque de 4 horas', '4-hour tank', 'Tope offline 4 h', 'Offline cap 4 h', 50000, FamiliaMejora.idle, (p) => _n(p, 'cafe') >= 1),
  Mejora('tanque_8', '🛢️', 'Tanque de 8 horas', '8-hour tank', 'Tope offline 8 h', 'Offline cap 8 h', 50e6, FamiliaMejora.idle,
      (p) => p.mejoras.contains('tanque_4') && _n(p, 'bano') >= 1),
  Mejora('valvula_50', '🔧', 'Válvula de 50%', '50% valve', 'Offline al 50%', 'Offline at 50%', 200000, FamiliaMejora.idle, (p) => _n(p, 'arepa') >= 1),
  Mejora('valvula_75', '🔧', 'Válvula de 75%', '75% valve', 'Offline al 75%', 'Offline at 75%', 200e6, FamiliaMejora.idle,
      (p) => p.mejoras.contains('valvula_50') && _n(p, 'camion') >= 1),
  // Mojón dorado (2)
  Mejora('iman', '🧲', 'Imán de oro', 'Gold magnet', 'Salen el doble de seguido', 'Show up twice as often', 7.77e6, FamiliaMejora.dorado,
      (p) => p.dorados >= 7),
  Mejora('brillo', '✨', 'Brillo largo', 'Long shine', 'Duran el doble en pantalla', 'Stay twice as long on screen', 77.7e6, FamiliaMejora.dorado,
      (p) => p.dorados >= 27),
  // Incienso (1)
  Mejora('lavanda', '🪻', 'Incienso de lavanda', 'Lavender incense', 'Cada logro da +1,5% en vez de +1%', 'Each achievement gives +1.5% instead of +1%', 1e6,
      FamiliaMejora.incienso, (p) => p.logros.length >= 10),
];

final Map<String, Mejora> _mejoraPorId = {for (final m in mejoras) m.id: m};

/// Mejora por id, o null si no existe.
Mejora? mejoraPorId(String id) => _mejoraPorId[id];

/// Mejoras de clic que duplican el pujo base.
const Set<String> mejorasClicX2 = {'guantes', 'faja', 'dedo_acero'};

/// Mejoras de clic que suman 1% del MJ/s a cada pujo.
const Set<String> mejorasClicPct = {'respiracion', 'mano_dios'};

/// Cómo se consigue o usa un objeto.
enum TipoObjeto { ficha, consumible, alquilable }

/// Objeto de la tienda (sección 5.1).
class Objeto {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String descEs, descEn;
  final TipoObjeto tipo;

  /// null = dura hasta el próximo mojón dorado (Papel doble hoja).
  final Duration? duracion;

  /// Precio en minutos de producción (mínimo 100 MJ). 0 = se paga con una Ficha.
  final double minutosPrecio;

  /// Espera entre usos (consumible) o entre alquileres (alquilable). null = sin espera.
  final Duration? espera;
  final int candado;

  /// Máximo en el inventario (solo consumibles).
  final int maxInventario;

  /// Pide haber visto el primer Atasco (Robot destapador).
  final bool pideAtasco;

  const Objeto(this.id, this.emoji, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.tipo,
      {this.duracion, this.minutosPrecio = 0, this.espera, this.candado = 0, this.maxInventario = 0, this.pideAtasco = false});
}

/// Tiempo máximo acumulado al volver a alquilar el Robot.
const Duration topeAlquiler = Duration(hours: 1);

const List<Objeto> objetos = [
  Objeto('cagada_fresca', '💩', 'Cagada fresca', 'Fresh dump', 'Producción x2', 'Production x2', TipoObjeto.ficha,
      duracion: Duration(hours: 1), candado: 1),
  Objeto('ambientador', '🧴', 'Ambientador criollo', 'Homemade air freshener', 'Producción +25%', 'Production +25%', TipoObjeto.consumible,
      duracion: Duration(minutes: 20), minutosPrecio: 10, espera: Duration(hours: 1), candado: 5, maxInventario: 5),
  Objeto('laxante', '💊', 'Laxante express', 'Express laxative', 'Pujos x2', 'Pushes x2', TipoObjeto.consumible,
      duracion: Duration(minutes: 5), minutosPrecio: 3, espera: Duration(minutes: 30), candado: 5, maxInventario: 5),
  Objeto('papel', '🧻', 'Papel doble hoja', 'Two-ply paper', 'El próximo mojón dorado da el doble', 'Your next golden poop gives double',
      TipoObjeto.consumible, minutosPrecio: 5, espera: Duration(hours: 1), candado: 5, maxInventario: 5),
  Objeto('robot', '🤖', 'Robot destapador', 'Plunger bot', 'Destapa solo cada Atasco', 'Unclogs every Clog by itself', TipoObjeto.alquilable,
      duracion: Duration(minutes: 30), minutosPrecio: 20, espera: Duration(hours: 4), candado: 10, pideAtasco: true),
];

final Map<String, Objeto> _objetoPorId = {for (final o in objetos) o.id: o};

/// Objeto por id, o null si no existe.
Objeto? objetoPorId(String id) => _objetoPorId[id];

/// Logro: +1% de producción cada uno (+1,5% con Incienso de lavanda).
class Logro {
  final String id;
  final String nombreEs, nombreEn;
  final String descEs, descEn;

  /// Se cumple con el estado y el MJ/s sin efectos temporales.
  final bool Function(Partida p, double mps) condicion;

  const Logro(this.id, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.condicion);
}

/// Los 20 logros de la fase 1.
final List<Logro> logros = [
  Logro('primer_pujo', 'Primer pujo', 'First push', '1 pujo', '1 push', (p, _) => p.pujos >= 1),
  Logro('calentando', 'Calentando', 'Warming up', '100 pujos', '100 pushes', (p, _) => p.pujos >= 100),
  Logro('profesional', 'Pujador profesional', 'Pro pusher', '1.000 pujos', '1,000 pushes', (p, _) => p.pujos >= 1000),
  Logro('hemorroides', 'Hemorroides', 'Hemorrhoids', '10.000 pujos', '10,000 pushes', (p, _) => p.pujos >= 10000),
  Logro('nalgazo', 'Nalgazo', 'Butt slam', '100 pujos en 10 segundos', '100 pushes in 10 seconds', (p, _) => p.nalgazos >= 1),
  Logro('epico', 'Épico', 'Epic', 'Primer pujo épico', 'First epic push', (p, _) => p.epicos >= 1),
  Logro('gotea', 'Gotea', 'Drip', '1 MJ/s', '1 MJ/s', (_, m) => m >= 1),
  Logro('fluye', 'Fluye', 'Flow', '100 MJ/s', '100 MJ/s', (_, m) => m >= 100),
  Logro('corre', 'Corre', 'The runs', '10.000 MJ/s', '10,000 MJ/s', (_, m) => m >= 10000),
  Logro('mojonero', 'Mojonero', 'Poop saver', '1 K ganados en total', '1 K earned in total', (p, _) => p.mjTotal >= 1e3),
  Logro('mojonista', 'Mojonista', 'Poop tycoon', '1 M ganados en total', '1 M earned in total', (p, _) => p.mjTotal >= 1e6),
  Logro('mojonario', 'Mojonario', 'Poopillionaire', '1 B ganados en total', '1 B earned in total', (p, _) => p.mjTotal >= 1e9),
  Logro('primer_guayoyo', 'Primer guayoyo', 'First cup', '1 Café negro', '1 Black coffee', (p, _) => _n(p, 'cafe') >= 1),
  Logro('cafeina', 'Cafeína pura', 'Pure caffeine', '50 Cafés negros', '50 Black coffees', (p, _) => _n(p, 'cafe') >= 50),
  Logro('segundo_trono', 'Mi segundo trono', 'My second throne', '1 Inodoro extra', '1 Spare toilet', (p, _) => _n(p, 'inodoro') >= 1),
  Logro('primer_oro', 'Primer oro', 'First gold', '1 mojón dorado', '1 golden poop', (p, _) => p.dorados >= 1),
  Logro('buscador_oro', 'Buscador de oro', 'Gold digger', '7 mojones dorados', '7 golden poops', (p, _) => p.dorados >= 7),
  Logro('plomero', 'Plomero', 'Plumber', '100 destapes', '100 unclogs', (p, _) => p.destapes >= 100),
  Logro('descarga', 'Descarga', 'Big flush', 'Primera Descarga', 'First Big flush', (p, _) => p.descargas >= 1),
  Logro('cagar_fiebre', 'Cagar en Fiebre', 'Fever dump', 'Abrir una Descarga con la Fiebre de un mojón dorado activa',
      'Open a Big flush while a golden poop Fever is on', (p, _) => p.enFiebre >= 1),
];

final Map<String, Logro> _logroPorId = {for (final l in logros) l.id: l};

/// Logro por id, o null si no existe.
Logro? logroPorId(String id) => _logroPorId[id];

/// Buff de 1 hora según el tipo de la cagada real (nombres del parte de cagada).
class BuffTipo {
  final int tipo;
  final String emoji;
  final String nombreEs, nombreEn;
  final String efectoEs, efectoEn;
  const BuffTipo(this.tipo, this.emoji, this.nombreEs, this.nombreEn, this.efectoEs, this.efectoEn);
}

const Duration duracionBuffTipo = Duration(hours: 1);

const Map<int, BuffTipo> buffsTipo = {
  1: BuffTipo(1, '🪨', 'Piedritas de conejo', 'Rabbit pellets', 'Pujo épico 2% a 8%', 'Epic push 2% to 8%'),
  2: BuffTipo(2, '🧱', 'Ladrillo', 'Brick', 'Pujos x2', 'Pushes x2'),
  3: BuffTipo(3, '🌽', 'Mazorca', 'Corn cob', 'Edificios 10% más baratos', 'Buildings 10% cheaper'),
  4: BuffTipo(4, '🐍', 'Anaconda', 'Anaconda', 'Todo x2', 'Everything x2'),
  5: BuffTipo(5, '🍦', 'Helado suave', 'Soft serve', 'Mojones dorados el doble de seguido', 'Golden poops twice as often'),
  6: BuffTipo(6, '🌋', 'Volcán', 'Volcano', 'El próximo offline cuenta x1,5', 'Next offline counts x1.5'),
  7: BuffTipo(7, '💧', 'Manguera', 'Fire hose', 'Producción x3 y pujos a la mitad', 'Production x3, pushes halved'),
};

/// Un candado de cagadas reales de la fase 1 (sección 2).
class Candado {
  final int cagadas;
  final String queEs, queEn;
  const Candado(this.cagadas, this.queEs, this.queEn);
}

/// Candados que abre la fase 1, de menor a mayor.
const List<Candado> candadosFase1 = [
  Candado(1, 'Fichas de cagada y Cagada fresca', 'Poop tokens and Fresh dump'),
  Candado(3, 'Inodoro extra', 'Spare toilet'),
  Candado(5, 'Baño público y los consumibles', 'Public restroom and consumables'),
  Candado(10, 'Robot destapador, Camión vacuum y Planta de tratamiento', 'Plunger bot, Vacuum truck and Treatment plant'),
];

/// Cuántos candados de la fase 1 abre un total de cagadas.
int candadosAbiertos(int cagadas) => candadosFase1.where((c) => cagadas >= c.cagadas).length;

/// El próximo candado que falta, o null si ya abrió todos los de la fase 1.
Candado? siguienteCandado(int cagadas) {
  for (final c in candadosFase1) {
    if (cagadas < c.cagadas) return c;
  }
  return null;
}

/// Multiplicador permanente por cagadas reales: +[pct]% hasta 150 (x4 con 2%), luego +0,5% cada una.
double multiplicadorPorCagadas(int cagadas, [double pct = 2]) {
  final c = cagadas < 0 ? 0 : cagadas;
  return c <= 150 ? 1 + pct / 100 * c : 1 + pct * 1.5 + 0.005 * (c - 150);
}

/// Números del juego que se pueden mover desde el servidor (flags). Los defaults son los de siempre.
/// Dart puro: el controlador la arma desde `FlagsImperio.ajustes`.
class Ajustes {
  /// Minutos activos entre mojones dorados (sin Imán ni tipo 5).
  final double doradoMinMin, doradoMaxMin;

  /// Parte del MJ/s que cuenta offline sin válvulas, y tope offline sin tanques (horas).
  /// Las válvulas (50%, 75%) y los tanques (4 h, 8 h) siguen siendo esos valores, pero nunca menos que la base.
  final double offlinePorcentaje, offlineTopeH;

  /// Cada unidad de un edificio cuesta esto por la anterior.
  final double precioCrecimiento;
  final double precioGuantes, precioFaja;

  /// Producción extra por cagada real hasta 150, en % (2 = +2%).
  final double cagadaBonoPct;

  const Ajustes({
    this.doradoMinMin = 5,
    this.doradoMaxMin = 15,
    this.offlinePorcentaje = 0.25,
    this.offlineTopeH = 2,
    this.precioCrecimiento = 1.15,
    this.precioGuantes = 100,
    this.precioFaja = 500,
    this.cagadaBonoPct = 2,
  });

  static const Ajustes porDefecto = Ajustes();
}
