// Catálogo del Imperio Cagón, fase 1. Solo datos: los números salen de la nota "Imperio Cagón (catálogo)".
// Dart puro (sin Flutter) para poder probarlo. Los textos vienen en pares es/en; la pantalla escoge con tr().

import 'dart:math';

import 'estado.dart';
import 'temporadas.dart';

export 'temporadas.dart';

/// Edificio que produce MJ por segundo (o, como el Dedo, MJ por pujo).
class Edificio {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String chisteEs, chisteEn;
  final double precioBase;
  final double mpsBase;

  /// MJ que cada unidad suma a cada pujo (solo el Dedo; el motor lo toma de `Ajustes.dedoPujo`). 0 = no puja.
  final double pujoBase;

  /// Cagadas reales que pide para poder comprarlo.
  final int candado;

  /// false = fase 2: solo sale cuando tienes `rollos` Rollos de Oro (se ganan jalando la cadena).
  final bool fase1;

  /// Rollos de Oro que pide, además del candado de cagadas. 0 en la fase 1.
  final int rollos;

  const Edificio(this.id, this.emoji, this.nombreEs, this.nombreEn, this.chisteEs, this.chisteEn, this.precioBase, this.mpsBase, this.candado,
      {this.fase1 = true, this.pujoBase = 0, this.rollos = 0});
}

const List<Edificio> edificios = [
  // El Dedo no produce MJ/s: suma MJ a cada pujo.
  Edificio('dedo', '👆', 'Dedo que puja', 'Pushing finger', 'Puja contigo: +1 por pujo', 'Pushes with you: +1 per push', 15, 0, 0, pujoBase: 1),
  Edificio('ciruela', '🥛', 'Leche de magnesia', 'Milk of magnesia', 'El remedio de la abuela', "Grandma's remedy", 100, 1, 0),
  Edificio('cafe', '☕', 'Café negro', 'Black coffee', 'El de las 7 am', 'The 7 a.m. one', 1100, 8, 0),
  Edificio('arepa', '🫓', 'Arepa con caraotas', 'Arepa with beans', 'Combustible nacional', 'National fuel', 12000, 47, 0),
  Edificio('inodoro', '💦', 'Bidet', 'Bidet', 'Agua a presión, cero papel', 'Water pressure, zero paper', 130000, 260, 3),
  Edificio('bano', '🛁', 'Baño clase media', 'Middle-class bathroom', 'Con toallas de visita', 'Guest towels included', 1.4e6, 1400, 5),
  Edificio('camion', '🚛', 'Camión vacuum', 'Vacuum truck', 'Recolección a domicilio', 'Home pickup service', 20e6, 7800, 10),
  Edificio('planta', '🏭', 'Planta de tratamiento', 'Treatment plant', 'Industria seria', 'Serious industry', 330e6, 44000, 10),
  Edificio('cloaca', '🕳️', 'Cloaca municipal', 'City sewer', 'Todo el pueblo trabaja para ti', 'The whole town works for you', 5.1e9, 260000, 30,
      fase1: false, rollos: 100),
  Edificio('granja', '🪰', 'Criadero de moscas', 'Fly farm', 'Ganadería de altura', 'Livestock, sort of', 75e9, 1.6e6, 30, fase1: false, rollos: 300),
  Edificio('mina', '⛏️', 'Mina de metano', 'Methane mine', 'Energía del futuro', 'Energy of the future', 1e12, 10e6, 30, fase1: false, rollos: 1000),
  Edificio('templo', '🛕', 'Templo del Trono', 'Throne temple', 'Culto al Rey', 'All hail the King', 14e12, 65e6, 60, fase1: false, rollos: 10000),
  Edificio('volcan', '🌋', 'Volcán digestivo', 'Digestive volcano', 'La Tierra también caga', 'Earth poops too', 170e12, 430e6, 60, fase1: false, rollos: 30000),
  Edificio('laxante_tiempo', '⏳', 'Laxante del tiempo', 'Time laxative', 'Cagas ayer y mañana', 'Poop yesterday and tomorrow', 2.1e15, 2.9e9, 100,
      fase1: false, rollos: 300000),
  Edificio('agujero', '🌌', 'Agujero negro intestinal', 'Intestinal black hole', 'Nada escapa', 'Nothing escapes', 26e15, 21e9, 150, fase1: false, rollos: 3000000),
];

/// Los 8 edificios de la fase 1, en orden. Los de la fase 2 (`fase1: false`) se abren con Rollos de Oro.
final List<Edificio> edificiosFase1 = [for (final e in edificios) if (e.fase1) e];

final Map<String, Edificio> _edificioPorId = {for (final e in edificios) e.id: e};

/// Edificio por id, o null si no existe.
Edificio? edificioPorId(String id) => _edificioPorId[id];

/// Familias de mejoras (pestaña MEJORAS).
enum FamiliaMejora { clic, edificio, idle, dorado, incienso, adorno }

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

/// Niveles de las mejoras por edificio y cuántas veces el precio base cuestan. Cada una da x2 a ese edificio
/// (al Dedo: x2 a lo que suma por pujo). Los ids no cambian (hay partidas guardadas con 1, 5 y 25); los precios
/// subieron: x5 o x10 por nivel hasta el 25, x100 al 50 y x1000 desde ahí. Los niveles de `rollosNivelMejora` piden Rollos de Oro.
const List<(int, double)> nivelesMejoraEdificio = [(1, 10), (5, 50), (10, 500), (25, 5e3), (50, 5e5), (100, 5e8), (150, 5e11), (200, 5e14)];

/// Rollos de Oro que piden los niveles altos de las mejoras por edificio (nivel → rollos). Solo se llega jalando la cadena.
const Map<int, int> rollosNivelMejora = {100: 10, 150: 100, 200: 1000};

// Nombres de las 8 mejoras de cada edificio, en el orden de `nivelesMejoraEdificio` (1, 5, 10, 25, 50, 100, 150, 200).
const Map<String, List<(String, String)>> _nombresMejoraEdificio = {
  'dedo': [
    ('Uña larga', 'Long nail'), ('Dedo enguantado', 'Gloved finger'), ('Dedo con anillo', 'Ringed finger'),
    ('Dedos ambidiestros', 'Ambidextrous fingers'), ('Dedo del pie', 'Big toe helps too'), ('Dedo biónico', 'Bionic finger'),
    ('Mano entera', 'The whole hand'), ('Dedo de Rey', "The King's finger"),
  ],
  'ciruela': [
    ('Cucharada colmada', 'Heaping spoonful'), ('Sabor a menta', 'Mint flavor'), ('Botella familiar', 'Family-size bottle'),
    ('Receta de la abuela', "Grandma's recipe"), ('Dosis de caballo', 'Horse dose'), ('Pipote de magnesia', 'Magnesia barrel'),
    ('Magnesia fosforescente', 'Glow-in-the-dark magnesia'), ('Magnesia nuclear', 'Nuclear magnesia'),
  ],
  'cafe': [
    ('Doble carga', 'Double shot'), ('Café de bodega', 'Corner store coffee'), ('Café con leche de magnesia', 'Milk of magnesia latte'),
    ('Guayoyo', 'Watery joe'), ('Cafetera industrial', 'Industrial coffee maker'), ('Café en vena', 'Coffee IV drip'),
    ('Hacienda cafetalera', 'Coffee plantation'), ('Expreso del infierno', 'Espresso from hell'),
  ],
  'arepa': [
    ('Arepa con queso', 'Cheese arepa'), ('Arepa rellena', 'Stuffed arepa'), ('Arepa con picante', 'Spicy arepa'),
    ('Arepera 24 horas', '24-hour arepa joint'), ('Budare gigante', 'Giant griddle'), ('Reina pepiada XL', 'XL reina pepiada'),
    ('Arepa de cuatro pisos', 'Four-story arepa'), ('Arepa cósmica', 'Cosmic arepa'),
  ],
  'inodoro': [
    ('Tapa acolchada', 'Padded lid'), ('Asiento caliente', 'Heated seat'), ('Descarga doble', 'Dual flush'),
    ('Chorro a presión', 'Power spray'), ('Inodoro con wifi', 'Wi-Fi toilet'), ('Trono de mármol', 'Marble throne'),
    ('Inodoro japonés', 'Japanese smart toilet'), ('Inodoro de oro', 'Solid gold toilet'),
  ],
  'bano': [
    ('Toallas dobladitas', 'Neatly folded towels'), ('Mueble bajo el lavamanos', 'Vanity cabinet'), ('Cuadro de la abuela', "Grandma's painting"),
    ('Calentador de agua', 'Water heater'), ('Ducha de lluvia', 'Rain shower'), ('Jabones de visita', 'Guest soaps'),
    ('Jacuzzi', 'Jacuzzi'), ('Bañera con patas de oro', 'Gold clawfoot tub'),
  ],
  'camion': [
    ('Pintura de la alcaldía', 'City paint job'), ('Pito de retroceso', 'Backup beeper'), ('Camión grande', 'Bigger truck'),
    ('Bocina de barco', 'Ship horn'), ('Camión cisterna doble', 'Double tanker'), ('Gandola del mojón', 'Poop semi truck'),
    ('Gandola con llamas', 'Flame-painted rig'), ('Camión volador', 'Flying truck'),
  ],
  'planta': [
    ('Segundo anillo', 'Second ring'), ('Luces de emergencia', 'Warning lights'), ('Chimenea', 'Smokestack'),
    ('Tercer anillo', 'Third ring'), ('Núcleo verde', 'Green core'), ('Reactor con ISO 9001', 'ISO 9001 reactor'),
    ('Reactor que vibra', 'Humming reactor'), ('Reactor en órbita', 'Reactor in orbit'),
  ],
};

/// Id de la mejora de un edificio para un nivel de `nivelesMejoraEdificio`: 'dedo_1', 'cafe_25', 'planta_200'.
String idMejoraEdificio(String edificio, int nivel) => '${edificio}_$nivel';

List<Mejora> _mejorasDeEdificios() => [
      for (final e in edificiosFase1)
        for (var i = 0; i < nivelesMejoraEdificio.length; i++)
          Mejora(
            idMejoraEdificio(e.id, nivelesMejoraEdificio[i].$1),
            e.emoji,
            _nombresMejoraEdificio[e.id]![i].$1,
            _nombresMejoraEdificio[e.id]![i].$2,
            e.pujoBase > 0 ? '${e.nombreEs}: pujo x2' : '${e.nombreEs} produce x2',
            e.pujoBase > 0 ? '${e.nombreEn}: push x2' : '${e.nombreEn} makes x2',
            e.precioBase * nivelesMejoraEdificio[i].$2,
            FamiliaMejora.edificio,
            (p) => _n(p, e.id) >= nivelesMejoraEdificio[i].$1 && p.rollosGanados >= (rollosNivelMejora[nivelesMejoraEdificio[i].$1] ?? 0),
            edificio: e.id,
          ),
    ];

/// Mejoras de clic de los edificios millonarios: (edificio, nivel, %, precio en veces el precio base, emoji, nombres).
/// Cada una convierte ese % de tu MJ/s en MJ por pujo.
const List<(String, int, int, double, String, String, String)> _mejorasPujoMillonarias = [
  ('bano', 5, 1, 50, '📣', 'Pujo en coro', 'Choir push'),
  ('bano', 25, 2, 1e4, '📣', 'Eco del cubículo', 'Stall echo'),
  ('camion', 5, 1, 50, '📯', 'Bocina al pujar', 'Push horn'),
  ('camion', 25, 2, 1e4, '📯', 'Succión al pujo', 'Push-powered suction'),
  ('planta', 5, 1, 50, '⚡', 'Turbina de pujo', 'Push turbine'),
  ('planta', 25, 2, 1e4, '⚡', 'Reactor de pujo', 'Push reactor'),
];

/// Id de una mejora de pujo de un edificio millonario: 'bano_pujo_1' (+1%), 'bano_pujo_2' (+2%).
String idMejoraPujo(String edificio, int pct) => '${edificio}_pujo_$pct';

List<Mejora> _mejorasPujo() => [
      for (final (id, nivel, pct, veces, emoji, es, en) in _mejorasPujoMillonarias)
        Mejora(idMejoraPujo(id, pct), emoji, es, en, 'Cada pujo suma $pct% de tu MJ/s', 'Each push adds $pct% of your MJ/s',
            edificioPorId(id)!.precioBase * veces, FamiliaMejora.clic, (p) => _n(p, id) >= nivel, edificio: id),
    ];

/// Edificio de la mejora que desbloquea jalar la cadena, y cuántos pide.
const String edificioCadena = 'bano';
const int unidadesCadena = 10;

/// Las 91 mejoras de la fase 1 (82 + La cadena del trono + 8 adornos del baño).
final List<Mejora> mejoras = [
  // Clic (5 del Dedo + 6 de los millonarios)
  Mejora('guantes', '🧤', 'Guantes de látex', 'Latex gloves', 'Pujo x2', 'Push x2', 100, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 1, edificio: 'dedo'),
  Mejora('faja', '🩲', 'Faja de pujo', 'Pushing belt', 'Pujo x2', 'Push x2', 500, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 1, edificio: 'dedo'),
  Mejora('dedo_acero', '🦾', 'Dedo de acero', 'Steel finger', 'Pujo x2', 'Push x2', 10000, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 10,
      edificio: 'dedo'),
  Mejora('respiracion', '🫁', 'Pujo con respiración', 'Breathing technique', 'Cada pujo suma además 1% de tu MJ/s', 'Each push also adds 1% of your MJ/s',
      100000, FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 25, edificio: 'dedo'),
  Mejora('mano_dios', '🙌', 'Mano de dios', 'Hand of god', 'Cada pujo suma otro 1% de tu MJ/s', 'Each push adds another 1% of your MJ/s', 10e6,
      FamiliaMejora.clic, (p) => _n(p, 'dedo') >= 50, edificio: 'dedo'),
  ..._mejorasPujo(),
  // Por edificio (64 + la cadena)
  ..._mejorasDeEdificios(),
  // Sale una sola vez: después de la primera jalada el botón JALAR ya no se esconde.
  Mejora('cadena_trono', '🚽', 'La cadena del trono', 'The throne chain', 'Desbloquea jalar la cadena', 'Unlocks pulling the chain', 1.4e6 * 500,
      FamiliaMejora.edificio, (p) => p.jaladas == 0 && p.rollos == 0 && _n(p, edificioCadena) >= unidadesCadena,
      edificio: edificioCadena),
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
  // Adornos del baño (8): sin edificio, salen en TU BAÑO; cada uno suma comodidad (+% de MJ/s permanente).
  Mejora('adorno_bombillo', '💡', 'Bombillo nuevo', 'New light bulb', 'Comodidad +2%', 'Comfort +2%', 500, FamiliaMejora.adorno, (p) => _n(p, 'ciruela') >= 1),
  Mejora('adorno_papel', '🧻', 'Rollo en su porta', 'Roll on a holder', 'Comodidad +2%', 'Comfort +2%', 4000, FamiliaMejora.adorno, (p) => _n(p, 'cafe') >= 1),
  Mejora('adorno_forro', '🧶', 'Forro de peluche para la tapa', 'Fuzzy lid cover', 'Comodidad +3%', 'Comfort +3%', 30000, FamiliaMejora.adorno,
      (p) => _n(p, 'arepa') >= 1),
  Mejora('adorno_alfombra', '🟫', 'Alfombrita en U', 'U-shaped bath mat', 'Comodidad +3%', 'Comfort +3%', 250000, FamiliaMejora.adorno,
      (p) => _n(p, 'arepa') >= 10),
  Mejora('adorno_cortina', '🌸', 'Cortina de flores', 'Flowery shower curtain', 'Comodidad +4%', 'Comfort +4%', 2e6, FamiliaMejora.adorno,
      (p) => _n(p, 'inodoro') >= 1),
  Mejora('adorno_matica', '🪴', 'Matica', 'Little plant', 'Comodidad +4%', 'Comfort +4%', 15e6, FamiliaMejora.adorno, (p) => _n(p, 'bano') >= 1),
  Mejora('adorno_ceramica', '🧱', 'Cerámica nueva', 'New tiles', 'Comodidad +5%', 'Comfort +5%', 120e6, FamiliaMejora.adorno,
      (p) => _n(p, 'camion') >= 1),
  Mejora('adorno_pintura', '🎨', 'Mano de pintura', 'Fresh paint', 'Comodidad +5%', 'Comfort +5%', 1e9, FamiliaMejora.adorno, (p) => _n(p, 'planta') >= 1),
];

/// Comodidad que da cada adorno del baño: id → parte (0,02 = +2% de MJ/s).
const Map<String, double> comodidadAdornos = {
  'adorno_bombillo': 0.02,
  'adorno_papel': 0.02,
  'adorno_forro': 0.03,
  'adorno_alfombra': 0.03,
  'adorno_cortina': 0.04,
  'adorno_matica': 0.04,
  'adorno_ceramica': 0.05,
  'adorno_pintura': 0.05,
};

final Map<String, Mejora> _mejoraPorId = {for (final m in mejoras) m.id: m};

/// Mejora por id, o null si no existe.
Mejora? mejoraPorId(String id) => _mejoraPorId[id];

/// Mejoras de clic que duplican el pujo base.
const Set<String> mejorasClicX2 = {'guantes', 'faja', 'dedo_acero'};

/// Mejoras de clic que suman un % del MJ/s a cada pujo: id → parte (0,01 = 1%).
final Map<String, double> mejorasClicPct = {
  'respiracion': 0.01,
  'mano_dios': 0.01,
  for (final (id, _, pct, _, _, _, _) in _mejorasPujoMillonarias) idMejoraPujo(id, pct): pct / 100,
};

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

  /// Precio en minutos de producción (mínimo 100 MJ). 0 = no se compra con MJ (Cagada fresca: viene con cada cagada real).
  final double minutosPrecio;

  /// Espera entre usos (solo consumibles). null = sin espera. Los alquilables no esperan: los frena el calor
  /// ([Ajustes.calorFactor]).
  final Duration? espera;
  final int candado;

  /// Máximo en el inventario (solo consumibles).
  final int maxInventario;

  /// Pide haber visto el primer Atasco (Robot destapador).
  final bool pideAtasco;

  /// Precio en Ciruelas (0 = no se vende con Ciruelas). El mismo que `obj_<id>` en `imperio_gastar_ciruelas`.
  final int ciruelas;

  const Objeto(this.id, this.emoji, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.tipo,
      {this.duracion, this.minutosPrecio = 0, this.espera, this.candado = 0, this.maxInventario = 0, this.pideAtasco = false, this.ciruelas = 0});
}

/// Largos que se pueden pagar de una vez (veces la duración del alquilable). Pagado por adelantado, el alquiler
/// nunca pasa de [vecesAlquilerMax] veces su duración desde ahora. Aparte está el modo Indefinido (se renueva solo).
const List<int> opcionesAlquiler = [1, 2, 5, 10];
const int vecesAlquilerMax = 10;

const List<Objeto> objetos = [
  Objeto('cagada_fresca', '💩', 'Cagada fresca', 'Fresh dump', 'Producción x2', 'Production x2', TipoObjeto.ficha,
      duracion: Duration(hours: 1), candado: 1),
  Objeto('ambientador', '🧴', 'Ambientador criollo', 'Homemade air freshener', 'Producción +25%', 'Production +25%', TipoObjeto.consumible,
      duracion: Duration(minutes: 20), minutosPrecio: 10, espera: Duration(hours: 1), candado: 5, maxInventario: 5, ciruelas: 2),
  Objeto('laxante', '💊', 'Laxante express', 'Express laxative', 'Pujos x2', 'Pushes x2', TipoObjeto.consumible,
      duracion: Duration(minutes: 5), minutosPrecio: 3, espera: Duration(minutes: 30), candado: 5, maxInventario: 5, ciruelas: 1),
  Objeto('papel', '🧻', 'Papel doble hoja', 'Two-ply paper', 'El próximo mojón dorado da el doble', 'Your next golden poop gives double',
      TipoObjeto.consumible, minutosPrecio: 5, espera: Duration(hours: 1), candado: 5, maxInventario: 5, ciruelas: 2),
  Objeto('robot', '🤖', 'Robot destapador', 'Plunger bot', 'Destapa solo cada Atasco', 'Unclogs every Clog by itself', TipoObjeto.alquilable,
      duracion: Duration(minutes: 30), minutosPrecio: 20, candado: 4, pideAtasco: true, ciruelas: 3),
  // Fase 2: alquilables (candado 15 y 30).
  Objeto('robot_turbo', '🦾', 'Robot destapador Turbo', 'Turbo plunger bot', 'Destapa solo y el Atasco no frena la producción',
      'Unclogs by itself and Clogs don\'t slow production', TipoObjeto.alquilable,
      duracion: Duration(hours: 2), minutosPrecio: 90, candado: 30, pideAtasco: true, ciruelas: 6),
  Objeto('plomero_horas', '🧰', 'Plomero por horas', 'Hourly plumber', 'Cada Atasco que destapes: producción x3 por 1 min',
      'Every Clog you clear: production x3 for 1 min', TipoObjeto.alquilable,
      duracion: Duration(hours: 1), minutosPrecio: 30, candado: 15),
  Objeto('primo', '👦', 'Primo pujador', 'Pushing cousin', 'Cada primo puja 10 veces por segundo con la app abierta. Con más MJ/s vienen más primos',
      'Each cousin pushes 10 times a second while the app is open. More MJ/s brings more cousins', TipoObjeto.alquilable,
      duracion: Duration(minutes: 15), minutosPrecio: 10, candado: 15, ciruelas: 3),
  Objeto('cuadrilla', '👷', 'Cuadrilla del barrio', 'Neighborhood crew', 'Cada minuto compra el cagador más barato si te alcanza',
      'Every minute buys the cheapest pooper if you can afford it', TipoObjeto.alquilable,
      duracion: Duration(minutes: 10), minutosPrecio: 7, candado: 15),
  // Sin duración: dura hasta que vuelves a abrir la app (se gasta en el offline).
  Objeto('guardia', '🔦', 'Guardia nocturno', 'Night watchman', 'Tu próximo offline cuenta al 100% y hasta 8 h',
      'Your next offline counts 100% and up to 8 h', TipoObjeto.alquilable,
      minutosPrecio: 60, candado: 30, ciruelas: 4),
  // Fase 2: consumibles (candado 15).
  Objeto('pino', '🌲', 'Ambientador de pino', 'Pine air freshener', 'Producción +50%, mojones dorados la mitad de seguido',
      'Production +50%, golden poops half as often', TipoObjeto.consumible,
      duracion: Duration(minutes: 15), minutosPrecio: 15, espera: Duration(hours: 3), candado: 15, maxInventario: 5, ciruelas: 3),
  Objeto('abuela', '🍵', 'Laxante de la abuela', 'Grandma\'s laxative', 'Producción x3; al terminar sale un Atasco seguro',
      'Production x3; a Clog is sure to follow', TipoObjeto.consumible,
      duracion: Duration(minutes: 3), minutosPrecio: 8, espera: Duration(hours: 2), candado: 15, maxInventario: 5),
  Objeto('greca', '☕', 'Guayoyo de greca', 'Stovetop coffee', 'El reloj de los cagadores corre al doble',
      'Poopers run on double time', TipoObjeto.consumible,
      duracion: Duration(minutes: 10), minutosPrecio: 20, espera: Duration(hours: 4), candado: 15, maxInventario: 5, ciruelas: 3),
  Objeto('reina_pepiada', '🫓', 'Arepa reina pepiada', 'Chicken avocado arepa', 'Producción +50%; su reloj solo corre con la app abierta',
      'Production +50%; its clock only runs with the app open', TipoObjeto.consumible,
      duracion: Duration(minutes: 30), minutosPrecio: 12, espera: Duration(hours: 6), candado: 15, maxInventario: 5, ciruelas: 2),
  // Sin duración: es al instante.
  Objeto('destapacanos', '🧪', 'Destapacaños químico', 'Drain cleaner', 'Destapa todos los Atascos al instante', 'Clears every Clog instantly',
      TipoObjeto.consumible, minutosPrecio: 5, espera: Duration(hours: 1), candado: 15, maxInventario: 5, ciruelas: 1),
  // Sin duración: dura hasta jalar la cadena. Se usa eligiendo un edificio (Imperio.usarPintura).
  Objeto('pintura', '🎨', 'Pintura marrón', 'Brown paint', 'Eliges un cagador: +10% hasta jalar la cadena (1 por cagador)',
      'Pick a pooper: +10% until you pull the chain (1 per pooper)', TipoObjeto.consumible,
      minutosPrecio: 45, candado: 15, maxInventario: 5),
];

/// Producción extra de la Pintura marrón para su edificio (0,1 = +10%).
const double bonoPintura = 0.1;

/// Maná de Tripa 🌀: sale con este candado, se llena 0 → [manaMax] en [llenadoMana] (también offline).
const int candadoMana = 15;
const double manaMax = 100;
const Duration llenadoMana = Duration(hours: 1);

/// Habilidad que se paga con Maná de Tripa. Su espera vive en `esperas['hab_<id>']`.
class Habilidad {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String descEs, descEn;
  final int mana;

  /// null = es al instante.
  final Duration? duracion;
  final Duration espera;
  const Habilidad(this.id, this.emoji, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.mana, this.duracion, this.espera);
}

const List<Habilidad> habilidades = [
  Habilidad('jalon_doble', '🚽', 'Jalón doble', 'Double flush', 'Producción x2 por 60 s', 'Production x2 for 60 s', 20, Duration(seconds: 60),
      Duration(hours: 1)),
  Habilidad('corre_corre', '🏃', 'Corre corre', 'Run run', 'Destapa todos los Atascos', 'Clears every Clog', 15, null, Duration(hours: 2)),
  Habilidad('pujo_sagrado', '🙌', 'Pujo sagrado', 'Holy push', 'Pujos x10 por 20 s', 'Pushes x10 for 20 s', 30, Duration(seconds: 20),
      Duration(hours: 1)),
  Habilidad('chorro', '🚿', 'Chorro a presión', 'Pressure jet', '15 min de producción al instante; 15% falla y pierdes 5 min',
      '15 min of production at once; 15% misfire and you lose 5 min', 40, null, Duration(hours: 4)),
  Habilidad('aguanta', '⏰', 'Aguanta', 'Hold it', 'Alarga 10% lo que les queda a tus efectos y alquilados',
      'Adds 10% to what\'s left on your effects and rentals', 25, null, Duration(hours: 2)),
];

final Map<String, Habilidad> _habilidadPorId = {for (final h in habilidades) h.id: h};

/// Habilidad por id, o null si no existe.
Habilidad? habilidadPorId(String id) => _habilidadPorId[id];

/// Nodo de la Plomería 🔧: se paga con Rollos de Oro (sale después de la primera jalada). Sobrevive a las jaladas y se
/// pierde al mudarse (el Camión de mudanza del Llavero se lleva una parte). Se guarda en `objetosRollos` (id → nivel).
class ObjetoRollos {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String descEs, descEn;

  /// Precio del primer nivel, en Rollos.
  final int costo;

  /// Nivel máximo (la Cadena de reserva: 1 pendiente, 1 por semana).
  final int limite;

  /// Cada nivel cuesta esto por el anterior (1 = precio fijo).
  final double crecimiento;
  const ObjetoRollos(this.id, this.emoji, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.costo, this.limite,
      {this.crecimiento = 1});

  /// Precio en Rollos del nivel siguiente cuando ya tienes [nivel].
  double precio(int nivel) => costo * pow(crecimiento, nivel).toDouble();
}

/// La Plomería. Ningún nodo sube los Rollos por jalada: el servidor no puede validar niveles que manda el cliente.
const List<ObjetoRollos> objetosRollos = [
  ObjetoRollos('super_plomero', '🦸', 'Súper Plomero', 'Super Plumber', 'Hasta la mudanza: destapa solo y 1 vez al día suelta 1 h de producción',
      'Until you move: unclogs by itself and drops 1 h of production once a day', 5, 1),
  ObjetoRollos('cadena_reserva', '⛓️', 'Cadena de reserva', 'Spare chain', 'Tu próxima jalada te devuelve 1 cagador de cada tipo que tenías',
      'Your next pull gives you back 1 of each pooper you had', 2, 1),
  ObjetoRollos('tanque_lujo', '🛁', 'Tanque de lujo', 'Luxury tank', '+1 h al tope offline hasta la mudanza (hasta +6 h)',
      '+1 h to your offline cap until you move (up to +6 h)', 5, 6),
  ObjetoRollos('tuberia_ancha', '🚰', 'Tubería ancha', 'Wide pipe', 'Producción x1,5 por nivel', 'Production x1.5 per level', 3, 30,
      crecimiento: 8),
  ObjetoRollos('llave_paso', '🔧', 'Llave de paso', 'Shutoff valve', 'Pujos x3 por nivel', 'Pushes x3 per level', 2, 20, crecimiento: 6),
  ObjetoRollos('tuberia_lista', '🏗️', 'Tubería lista', 'Pre-laid pipes', 'Cada corrida empieza con +10 de cada cagador de la fase 1 por nivel',
      'Each run starts with +10 of every phase 1 pooper per level', 5, 10, crecimiento: 10),
  ObjetoRollos('destapador_fino', '🪠', 'Destapador fino', 'Fine plunger', 'Atascos 25% menos seguido por nivel', 'Clogs 25% less often per level', 2, 3,
      crecimiento: 5),
  ObjetoRollos('iman_dorado', '🧲', 'Imán dorado', 'Golden magnet', 'Mojón dorado 10% más seguido y +2 s en pantalla por nivel',
      'Golden poop 10% more often and +2 s on screen per level', 20, 5, crecimiento: 10),
  ObjetoRollos('rebaja', '💸', 'Rebaja de ferretería', 'Hardware store sale', 'Cagadores 2% más baratos por nivel', 'Poopers 2% cheaper per level', 50, 10,
      crecimiento: 10),
  ObjetoRollos('tanque_hondo', '🛢️', 'Tanque hondo', 'Deep tank', 'Producción offline +10 puntos por nivel (hasta 75%)',
      'Offline production +10 points per level (up to 75%)', 10, 5, crecimiento: 8),
];

final Map<String, ObjetoRollos> _objetoRollosPorId = {for (final o in objetosRollos) o.id: o};

/// Objeto de Rollos por id, o null si no existe.
ObjetoRollos? objetoRollosPorId(String id) => _objetoRollosPorId[id];

/// Una Cadena de reserva por semana.
const Duration esperaCadenaReserva = Duration(days: 7);

/// Mejora del Llavero 🔑: se paga con Llaves (salen de mudarse). Sobrevive a las mudanzas; una capa más arriba la podría
/// reiniciar, por eso los textos dicen "entre mudanzas" y no "para siempre".
class MejoraLlavero {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String descEs, descEn;

  /// Precio de cada nivel en Llaves (el último se repite si [limite] es mayor que la lista).
  final List<int> precios;

  /// Lo que sube el precio por nivel después de la lista ([precios] de un solo número + [subida] = 1, 2, 3...).
  final int subida;
  final int limite;
  const MejoraLlavero(this.id, this.emoji, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.precios, this.limite, {this.subida = 0});

  /// Llaves que cuesta el nivel siguiente cuando ya tienes [nivel].
  int precio(int nivel) {
    if (nivel < precios.length) return precios[nivel];
    return precios.last + subida * (nivel - precios.length + 1);
  }
}

const List<MejoraLlavero> mejorasLlavero = [
  MejoraLlavero('cimientos', '🧱', 'Cimientos', 'Foundations', 'Producción x2 por nivel, entre mudanzas', 'Production x2 per level, across moves',
      [1], 20, subida: 1),
  MejoraLlavero('mayordomo', '🤵', 'Mayordomo', 'Butler', 'Compra solo el cagador que se paga más rápido: cada 10 s, 3 s y 1 s. Se puede apagar',
      'Buys the pooper that pays off fastest by himself: every 10 s, 3 s and 1 s. You can switch him off', [3, 5, 8], 3),
  MejoraLlavero('camion_mudanza', '🚚', 'Camión de mudanza', 'Moving truck', 'Al mudarte te llevas el 10% de cada nodo de la Plomería por nivel',
      'When you move you keep 10% of every Plumbing node per level', [2], 5, subida: 2),
  MejoraLlavero('ahorros', '💰', 'Ahorros', 'Savings', 'Cada corrida y cada casa empieza con plata: 1 millón de MJ, x1.000 por nivel',
      'Every run and every house starts with cash: 1 million MJ, x1,000 per level', [1], 10, subida: 1),
  MejoraLlavero('primo_extra', '👦', 'Primo extra', 'Extra cousin', '+1 primo alquilado a la vez', '+1 rented cousin at a time', [4, 8], 2),
  MejoraLlavero('alquiler_barato', '🎟️', 'Alquiler barato', 'Cheap rentals', 'Alquileres 10% más baratos por nivel', 'Rentals 10% cheaper per level',
      [2], 5, subida: 1),
];

final Map<String, MejoraLlavero> _mejoraLlaveroPorId = {for (final m in mejorasLlavero) m.id: m};

/// Llaves que costó todo el [llavero] (id → nivel). Ids que no existen no cuestan; niveles de más se cortan al máximo.
/// El servidor hace la misma cuenta (imperio_llavero_costo) para no aceptar Llaves inventadas.
int costoLlavero(Map<String, int> llavero) {
  var total = 0;
  llavero.forEach((id, n) {
    final m = _mejoraLlaveroPorId[id];
    if (m == null) return;
    for (var i = 0; i < min(n, m.limite); i++) {
      total += m.precio(i);
    }
  });
  return total;
}

/// Mejora del Llavero por id, o null si no existe.
MejoraLlavero? mejoraLlaveroPorId(String id) => _mejoraLlaveroPorId[id];

/// Cada cuánto compra el Mayordomo según su nivel (1, 2, 3).
const List<double> segundosMayordomo = [10, 3, 1];

/// Mejora de La Corte 👑: misma forma que el Llavero, pero se paga con Coronas (salen de abdicar) y sobrevive a las
/// abdicaciones. Los textos dicen "entre abdicaciones" y no "para siempre": puede venir otra capa.
typedef MejoraCorte = MejoraLlavero;

/// Heraldo, tesorero, maestro de obras y mayordomo real los aplica el servidor (imperio_abdicar, imperio_mudar,
/// imperio_guardar); bufón y catador son de producción y duración, del cliente.
const List<MejoraCorte> mejorasCorte = [
  MejoraCorte('bufon', '🤡', 'Bufón', 'Jester', 'Producción x3 por nivel, entre abdicaciones', 'Production x3 per level, across abdications',
      [1], 20, subida: 1),
  MejoraCorte('heraldo', '📯', 'Heraldo', 'Herald', 'Al abdicar arrancas más arriba: nivel 1 la Casa, 2 la Quinta y 3 la Mansión',
      'When you abdicate you start higher up: level 1 the House, 2 the Villa and 3 the Mansion', [4, 8, 16], 3),
  MejoraCorte('tesorero', '💰', 'Tesorero', 'Treasurer', 'Al abdicar te quedas el 10% de las Llaves ganadas por nivel (el Llavero sí se vacía)',
      'When you abdicate you keep 10% of the Keys you earned per level (the Keyring still empties)', [2], 5, subida: 2),
  MejoraCorte('maestro_obras', '👷', 'Maestro de obras', 'Master builder', 'Cada mudanza pide 10% menos Rollos por nivel',
      'Each move asks for 10% fewer Rolls per level', [2], 5, subida: 2),
  MejoraCorte('catador', '🍷', 'Catador', 'Taster', 'El buff de cada cagada dura 30 min más por nivel',
      'The buff from each poop lasts 30 min longer per level', [1], 4, subida: 1),
  MejoraCorte('mayordomo_real', '🤵', 'Mayordomo real', 'Royal butler', 'Cada reinado arranca con el Mayordomo del Llavero en nivel 1 gratis',
      'Every reign starts with the Keyring Butler at level 1 for free', [6], 1),
];

final Map<String, MejoraCorte> _mejoraCortePorId = {for (final m in mejorasCorte) m.id: m};

/// Coronas que costó toda [corte] (id → nivel). Ids que no existen no cuestan; niveles de más se cortan al máximo.
/// El servidor hace la misma cuenta (imperio_corte_costo) para no aceptar Coronas inventadas.
int costoCorte(Map<String, int> corte) {
  var total = 0;
  corte.forEach((id, n) {
    final m = _mejoraCortePorId[id];
    if (m == null) return;
    for (var i = 0; i < min(n, m.limite); i++) {
      total += m.precio(i);
    }
  });
  return total;
}

/// Mejora de La Corte por id, o null si no existe.
MejoraCorte? mejoraCortePorId(String id) => _mejoraCortePorId[id];

/// Lo que el Mayordomo real le descuenta al Llavero: su nivel 1 (3 Llaves) no se cobra si lo tienes en La Corte.
int descuentoLlaveroCorte(Map<String, int> corte, Map<String, int> llavero) =>
    (corte['mayordomo_real'] ?? 0) >= 1 && (llavero['mayordomo'] ?? 0) >= 1 ? _mejoraLlaveroPorId['mayordomo']!.precio(0) : 0;

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

  /// Escondido: en la vitrina no sale (ni nombre ni cómo se gana) hasta ganarlo; solo cuenta en "+N secretos".
  final bool oculto;

  const Logro(this.id, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.condicion, {this.oculto = false});
}

/// Veces que se tocó una cosa del baño ([Partida.toques]).
int _toques(Partida p, String id) => p.toques[id] ?? 0;

/// Niveles de Plomería que tienes (sin la Cadena de reserva, que se gasta).
int nivelesPlomeria(Partida p) => p.objetosRollos.entries.where((e) => e.key != 'cadena_reserva').fold(0, (a, e) => a + e.value);

/// Los 68 logros: 20 de la fase 1, 4 de la cadena, el de la racha, 15 de la fase 2, 8 escondidos del baño, 1 de temporada,
/// 3 del Cagadón con apuesta, 3 de regalos, 7 de la mudanza (1 escondido) y 6 de abdicar (1 escondido).
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
  Logro('segundo_trono', 'Culito lavado', 'Squeaky clean', '1 Bidet', '1 Bidet', (p, _) => _n(p, 'inodoro') >= 1),
  Logro('primer_oro', 'Primer oro', 'First gold', '1 mojón dorado', '1 golden poop', (p, _) => p.dorados >= 1),
  Logro('buscador_oro', 'Buscador de oro', 'Gold digger', '7 mojones dorados', '7 golden poops', (p, _) => p.dorados >= 7),
  Logro('plomero', 'Plomero', 'Plumber', '100 destapes', '100 unclogs', (p, _) => p.destapes >= 100),
  Logro('descarga', 'Descarga', 'Big flush', 'Primera Descarga', 'First Big flush', (p, _) => p.descargas >= 1),
  Logro('cagar_fiebre', 'Cagar en Fiebre', 'Fever dump', 'Abrir una Descarga con la Fiebre de un mojón dorado activa',
      'Open a Big flush while a golden poop Fever is on', (p, _) => p.enFiebre >= 1),
  // Cadena
  Logro('primera_jalada', 'Jalé y salí corriendo', 'Flush and run', 'Jalar la cadena por primera vez', 'Pull the chain for the first time',
      (p, _) => p.jaladas >= 1),
  Logro('diez_jaladas', 'Cadena oxidada', 'Rusty chain', 'Jalar la cadena 10 veces', 'Pull the chain 10 times', (p, _) => p.jaladas >= 10),
  Logro('primer_rollo', 'Papel de oro', 'Golden paper', '1 Rollo de Oro', '1 Golden Roll', (p, _) => p.rollosGanados >= 1),
  Logro('cien_rollos', 'Rey del papel', 'Toilet paper king', '100 Rollos de Oro', '100 Golden Rolls', (p, _) => p.rollosGanados >= 100),
  // Ocultos de la cadena, para el que juega mucho.
  Logro('cadena_25', 'Plomero de guardia', 'On-call plumber', 'Jalar la cadena 25 veces', 'Pull the chain 25 times', (p, _) => p.jaladas >= 25,
      oculto: true),
  Logro('mil_rollos', 'Papel moneda', 'Paper money', '1.000 Rollos de Oro', '1,000 Golden Rolls', (p, _) => p.rollosGanados >= 1000, oculto: true),
  Logro('candado_comprado', 'Cagada comprada', 'Bought poop', 'Abrir un candado pagando con mojonólares', 'Open a lock paying with Poopbucks',
      (p, _) => p.cagadasPagadas >= 1, oculto: true),
  // Lo da el día 30 de la racha (Imperio.aplicarPremioRacha), no una condición. En pantalla va con segun() (nombreLogro).
  Logro('constancia', 'Rey de la constancia', 'King of consistency', '30 días seguidos de racha', '30-day streak', (p, m) => false),
  // Fase 2: Maná, objetos nuevos, Rollos, racha (cofres, semanas, congeladores) y edificios grandes.
  Logro('primer_mana', 'Se me revolvió la tripa', 'Gut rumble', 'Usar una habilidad de Maná', 'Use a Mana skill', (p, _) => p.habilidades >= 1),
  Logro('brujo_tripa', 'Brujo de la tripa', 'Gut wizard', '50 habilidades de Maná', '50 Mana skills', (p, _) => p.habilidades >= 50),
  Logro('chorro_fallido', 'Se me salió por los lados', 'Backfire', 'Que te falle el Chorro a presión', 'Have the Pressure jet misfire',
      (p, _) => p.chorrosFallidos >= 1),
  Logro('cliente_fijo', 'Cliente fijo del alquiler', 'Regular renter', 'Alquilar uno de cada alquilable', 'Rent one of every rental',
      (p, _) => _alquilables.every(p.alquiladosUsados.contains)),
  Logro('bodeguero', 'Cliente de la bodega', 'Corner store regular', '10 consumibles usados', '10 consumables used', (p, _) => p.consumiblesUsados >= 10),
  Logro('brocha_gorda', 'Pintor de brocha gorda', 'House painter', 'Pintura marrón en 5 cagadores', 'Brown paint on 5 poopers',
      (p, _) => p.pintura.length >= 5),
  Logro('plomero_confianza', 'Plomero de confianza', 'Trusty plumber', 'Contratar al Súper Plomero', 'Hire the Super Plumber',
      (p, _) => (p.objetosRollos['super_plomero'] ?? 0) >= 1),
  Logro('papel_al_poceto', 'Botaste el papel', 'Money down the drain', 'Gastar un Rollo de Oro', 'Spend a Golden Roll', (p, _) => p.rollosGastados >= 1),
  Logro('primer_cofre', 'Ese cofre es mío', 'Finders keepers', 'Abrir un Cofre del Trono', 'Open a Throne chest', (p, _) => p.cofres >= 1),
  Logro('mes_de_hierro', 'Tripa de hierro', 'Iron gut', '4 semanas seguidas de racha', '4 weeks in a row', (p, _) => p.semanasRacha >= 4),
  Logro('congelado', 'Lo dejé en el congelador', 'Saved it for later', 'Salvar la racha con un Congelador', 'Save your streak with a Freezer',
      (p, _) => p.congeladosUsados >= 1),
  Logro('minero', 'Minero de peos', 'Gas miner', '1 Mina de metano', '1 Methane mine', (p, _) => _n(p, 'mina') >= 1),
  Logro('rey_templo', 'Rey del templo', 'Temple king', '1 Templo del Trono', '1 Throne temple', (p, _) => _n(p, 'templo') >= 1),
  Logro('erupcion', 'Erupción mañanera', 'Morning eruption', '1 Volcán digestivo', '1 Digestive volcano', (p, _) => _n(p, 'volcan') >= 1),
  Logro('se_lo_trago', 'Se lo tragó todo', 'Swallowed it all', '1 Agujero negro intestinal', '1 Intestinal black hole',
      (p, _) => _n(p, 'agujero') >= 1),
  // Escondidos: salen de tocar las cosas del baño (Poceta.alTocarObjeto). No se anuncian hasta ganarlos.
  Logro('cucaracha_cazador', 'Cazacucarachas', 'Roach hunter', 'Espantar a la cucaracha 10 veces', 'Scare the roach away 10 times',
      (p, _) => _toques(p, 'cucaracha') >= 10, oculto: true),
  Logro('bidet_en_la_cara', 'Me mojó la cara', 'Right in the face', 'Que el bidet te eche el chorro en la cara', 'Get squirted in the face by the bidet',
      (p, _) => _toques(p, 'bidet') >= 5, oculto: true),
  Logro('bombillo_quemado', 'Se fue la luz', 'Power outage', 'Tocar el bombillo 20 veces', 'Tap the light bulb 20 times',
      (p, _) => _toques(p, 'bombillo') >= 20, oculto: true),
  Logro('corneta_camion', 'Pi pi, camionero', 'Honk honk', 'Tocarle la corneta al camión 5 veces', "Honk the truck's horn 5 times",
      (p, _) => _toques(p, 'camion') >= 5, oculto: true),
  Logro('arepa_voladora', 'Arepa voladora', 'Flying arepa', 'Voltear la arepa 12 veces', 'Flip the arepa 12 times',
      (p, _) => _toques(p, 'arepa') >= 12, oculto: true),
  Logro('agua_fria', 'Agua helada', 'Ice-cold shower', 'Abrir la ducha 7 veces', 'Turn on the shower 7 times',
      (p, _) => _toques(p, 'ducha') >= 7, oculto: true),
  Logro('cuadro_torcido', 'Lo dejaste torcido', 'Hung it crooked', 'Enderezar el cuadro 8 veces', 'Straighten the picture 8 times',
      (p, _) => _toques(p, 'cuadro') >= 8, oculto: true),
  Logro('metiche', 'Metiche', 'Nosy', 'Tocar 6 cosas distintas del baño', 'Touch 6 different things in the bathroom',
      (p, _) => p.toques.length >= 6, oculto: true),
  // Mudanza 🏠, Plomería y Llavero.
  Logro('primera_mudanza', 'Me mudé', 'Moving day', 'Mudarte por primera vez', 'Move house for the first time', (p, _) => p.mudanzas >= 1),
  Logro('en_la_quinta', 'Vida de quinta', 'Villa life', 'Llegar a la Quinta', 'Reach the Villa', (p, _) => p.mudanzas >= 2),
  Logro('en_la_mansion', 'Mármol en el bidet', 'Marble bidet', 'Llegar a la Mansión', 'Reach the Mansion', (p, _) => p.mudanzas >= 3),
  Logro('en_el_palacio', 'Trono de verdad', 'A real throne', 'Llegar al Palacio', 'Reach the Palace', (p, _) => p.mudanzas >= 4),
  Logro('con_mayordomo', 'El señor está en el baño', 'The master is in the bathroom', 'Contratar al Mayordomo', 'Hire the Butler',
      (p, _) => (p.llavero['mayordomo'] ?? 0) >= 1),
  Logro('plomero_mayor', 'Plomero mayor', 'Master plumber', '50 niveles de Plomería en una casa', '50 Plumbing levels in one house',
      (p, _) => nivelesPlomeria(p) >= 50),
  Logro('mudanza_limpia', 'Ni un rollo', 'Not a single roll', 'Mudarte sin gastar un solo Rollo en esa casa', 'Move without spending a single Roll in that house',
      (p, _) => p.mudanzasLimpias >= 1, oculto: true),
  // Abdicar 👑 y La Corte.
  Logro('primera_abdicacion', 'Abdico', 'I abdicate', 'Abdicar por primera vez', 'Abdicate for the first time', (p, _) => p.abdicaciones >= 1),
  Logro('dinastia_iii', 'Dinastía III', 'Dynasty III', 'Llegar a la Dinastía III', 'Reach Dynasty III', (p, _) => p.abdicaciones >= 2),
  Logro('dinastia_v', 'Dinastía V', 'Dynasty V', 'Llegar a la Dinastía V', 'Reach Dynasty V', (p, _) => p.abdicaciones >= 4),
  Logro('corte_20', 'Corte llena', 'Full court', '20 niveles en La Corte', '20 levels in the Court',
      (p, _) => p.corte.values.fold(0, (a, n) => a + n) >= 20),
  Logro('heraldo_max', 'Que suenen las trompetas', 'Sound the trumpets', 'Heraldo al máximo', 'Herald maxed out',
      (p, _) => (p.corte['heraldo'] ?? 0) >= 3),
  Logro('abdicar_avaro', 'Rey avaro', 'Miser king', 'Abdicar sin haber gastado una Llave en ese reinado',
      'Abdicate without spending a single Key that reign', (p, _) => p.abdicacionesAvaras >= 1, oculto: true),
  // Exclusivo de temporada: solo se gana jugando mientras el servidor tenga encendido el Día Mundial del Retrete.
  Logro('dia_retrete', 'Día Mundial del Retrete', 'World Toilet Day', 'Jugar el Imperio el Día Mundial del Retrete (19 nov)',
      'Play the Imperio on World Toilet Day (Nov 19)', (p, _) => p.temporadas.contains(temporadaDiaRetrete)),
  // Cagadón con apuesta (lib/imperio/apuesta.dart): los da el controlador al cobrar un premio que validó el servidor.
  Logro('apuesta_ganada', 'Apostador', 'Gambler', 'Cobrar una apuesta del Cagadón', 'Collect a Poop-Off bet', (p, _) => false),
  Logro('apuestas_5', 'Tahúr del trono', 'Throne shark', 'Ganar 5 apuestas del Cagadón', 'Win 5 Poop-Off bets', (p, _) => false),
  Logro('apuesta_60', 'Todo o nada', 'All or nothing', 'Ganar una apuesta de 60 minutos', 'Win a 60-minute bet', (p, _) => false),
  // Regalos: los da Imperio.logrosDeRegalos con lo que cuenta el servidor (imperio_regalar / imperio_regalo_abrir), nunca la condición.
  Logro('regalo_primero', 'Rollo con lazo', 'Roll with a bow', 'Regalarle un Rollo a un amigo', 'Gift a Roll to a friend', (p, _) => false),
  Logro('regalo_diez', 'Santa del papel', 'Paper Santa', 'Regalar 10 Rollos', 'Gift 10 Rolls', (p, _) => false),
  Logro('regalo_mutuo', 'Hoy por ti, mañana por mí', 'You scratch my back', 'Abrir el Rollo de un amigo al que también le regalaste',
      'Open a Roll from a friend you also gifted', (p, _) => false, oculto: true),
];

/// Las cosas del baño que cuentan para [Partida.toques] (lo demás que llegue se ignora).
const Set<String> objetosTocables = {
  'bidet', 'tobo', 'bombillo', 'espejo', 'lavamanos', 'reactor', 'ventana', 'matica', 'arepa', 'banera', 'papel', 'cucaracha', 'camion', 'ducha', 'cuadro',
};

/// Ids de los alquilables (logro Cliente fijo).
final List<String> _alquilables = [for (final o in objetos) if (o.tipo == TipoObjeto.alquilable) o.id];

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

/// Lo que alarga el buff del tipo cada nivel del Catador de La Corte.
const Duration catadorPorNivel = Duration(minutes: 30);

/// Repetir el mismo tipo dentro de esta ventana (desde la última cagada con tipo) cansa su buff.
const Duration ventanaRachaTipo = Duration(hours: 24);

const Map<int, BuffTipo> buffsTipo = {
  1: BuffTipo(1, '🪨', 'Piedritas de conejo', 'Rabbit pellets', 'Pujos épicos x3 de seguido', 'Epic pushes x3 as often'),
  2: BuffTipo(2, '🧱', 'Ladrillo', 'Brick', 'Pujos x2', 'Pushes x2'),
  3: BuffTipo(3, '🌽', 'Mazorca', 'Corn cob', 'Cagadores 10% más baratos', 'Poopers 10% cheaper'),
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
  Candado(3, 'Bidet', 'Bidet'),
  Candado(5, 'Baño público y los consumibles', 'Public restroom and consumables'),
  Candado(4, 'Robot destapador', 'Plunger bot'),
  Candado(10, 'Camión vacuum y Planta de tratamiento', 'Vacuum truck and Treatment plant'),
  Candado(15, 'Maná de Tripa y la segunda tanda de objetos', 'Gut Mana and the second batch of items'),
  Candado(30, 'Robot Turbo y Guardia nocturno', 'Turbo bot and Night watchman'),
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

  /// Atasco offline: al salir de la app se sortea cuándo se atasca un edificio, en minutos desde la salida:
  /// [atascoOfflineMinimoMin] + exponencial de media ([atascoOfflineMediaMin] - mínimo). Media total ~45 min.
  final double atascoOfflineMediaMin, atascoOfflineMinimoMin;

  /// Atascos abiertos a la vez como máximo (uno por edificio) y segundos de juego activo por Atasco, en promedio.
  final int atascosMax;
  final double atascoSeg;

  /// Cada unidad de un edificio cuesta esto por la anterior.
  final double precioCrecimiento;
  final double precioGuantes, precioFaja;

  /// Producción extra por cagada real hasta 150, en % (2 = +2%).
  final double cagadaBonoPct;

  /// MJ que suma cada Dedo a cada pujo (antes de sus mejoras de nivel).
  final double dedoPujo;

  /// Pujo épico: probabilidad base, cuánto suma cada Dedo, tope; el buff tipo 1 la multiplica (con tope x2); y lo que vale (x10).
  final double epicoBase, epicoPorDedo, epicoTope, epicoTipo1, epicoMultiplicador;

  /// Cadena: cagadas reales que pide cada jalada (el servidor manda la cuenta buena).
  final int cadenaCagadas;

  /// Candados: horas de producción (MJ/s sin efectos) que cuesta la primera cagada pagada con MJ; cada una más sube
  /// [candadoSubida] de ese precio (la n-ésima cuesta horas x (1 + subida x n)).
  final double candadoHoras, candadoSubida;

  /// Rollos de Oro totales = piso((MJ ganados en total / divisor) ^ exponente).
  final double cadenaDivisor, cadenaExponente;

  /// Producción extra por cada Rollo de Oro sin gastar (0,01 = +1%), hasta la mudanza: MJ/s y pujo.
  final double rolloPct;

  /// Alquileres. Con todo en indefinido al tope (Turbo, Plomero, Primo, Cuadrilla) cuesta 10 x 2,6 minutos de producción
  /// por minuto alquilado x el descuento: de 5,5 a 2,4 veces la producción en la semana 1, ~16% desde el día 30 de la simulación
  /// larga (test/imperio_cadena_ritmo_test.dart imprime la tabla). Descuento por etapa: el precio base se multiplica por (max(MJ/s, 10) / 10) ^ -[alquilerDescuento].
  /// Calor: cada periodo alquilado multiplica el precio del siguiente por [calorFactor], hasta [calorTope]; el calor
  /// acumulado (en periodos) baja a la mitad cada [calorVidaMediaH] horas reales. Primos: hasta [maxPrimos].
  final double alquilerDescuento, calorFactor, calorTope, calorVidaMediaH;
  final int maxPrimos;

  /// Pujos de la mano que cuentan por segundo (ventana deslizante de 1 s); los de más no dan nada. Los Primos no
  /// pasan por aquí. También es el ritmo de pujos que se manda al guardar ([Imperio.ritmoEfectivo]).
  final int topePujosSeg;

  /// Mudanza: Rollos ganados en la casa que pide el Rancho ([mudanzaRollos]) y cuánto sube por casa ([mudanzaRollosSubida]);
  /// jaladas en la casa ([mudanzaJaladas]) y cagadas reales desde que llegaste ([mudanzaCagadas], máx 3 por día; el servidor
  /// manda la cuenta buena). Llaves = piso((rollos de la casa / requisito) ^ [mudanzaLlavesExponente] x [mudanzaLlavesFactor]).
  /// Cada Llave sin gastar: +[llavePct] de producción. Los mismos defaults están en la migración (imperio_mudar).
  /// [mudanzaDivisorX]: en cada casa los MJ rinden menos Rollos (MJ / divisor ^ mudanzas), para que los Rollos no se
  /// disparen con la producción de la casa nueva ni lleguen al tope. El servidor usa la misma cuenta (imperio_rollos_casa).
  final double mudanzaRollos, mudanzaRollosSubida, mudanzaLlavesExponente, mudanzaLlavesFactor, llavePct, mudanzaDivisorX;
  final int mudanzaJaladas, mudanzaCagadas;

  /// El botón MUDANZA aparece con [mudanzaDescubreJaladas] jaladas en la casa y cuando la próxima jalada da menos que
  /// [mudanzaDescubrePct] de los Rollos ya ganados en ella tras [mudanzaDescubreMin] minutos de corrida (o si ya te
  /// mudaste o ya lo viste). Solo es pantalla.
  final int mudanzaDescubreJaladas;
  final double mudanzaDescubrePct, mudanzaDescubreMin;

  /// Abdicar: [abdicarMudanzas] mudanzas en la dinastía, [abdicarLlaves] Llaves ganadas y [abdicarCagadas] cagadas
  /// reales desde la última abdicación (máx 3 por día; el servidor manda la cuenta buena). Coronas =
  /// piso((Llaves ganadas / [abdicarLlaves]) ^ [abdicarCoronasExponente] x [abdicarCoronasFactor]). Cada Corona sin
  /// gastar: +[coronaPct] de producción. Los mismos defaults están en la migración (imperio_abdicar).
  final int abdicarMudanzas, abdicarCagadas;
  final double abdicarLlaves, abdicarCoronasExponente, abdicarCoronasFactor, coronaPct;

  /// El botón ABDICAR aparece cuando ya no rinde mudarse: con [abdicarMudanzas] mudanzas, la mudanza siguiente da menos
  /// que [abdicarDescubrePct] de las Llaves ya ganadas y llevas [abdicarDescubreDias] días en la casa (o si ya
  /// abdicaste o ya lo viste). Solo es pantalla.
  final double abdicarDescubrePct, abdicarDescubreDias;

  const Ajustes({
    this.doradoMinMin = 5,
    this.doradoMaxMin = 15,
    this.offlinePorcentaje = 0.25,
    this.offlineTopeH = 2,
    this.atascoOfflineMediaMin = 45,
    this.atascoOfflineMinimoMin = 10,
    this.atascosMax = 3,
    this.atascoSeg = 240,
    this.precioCrecimiento = 1.15,
    this.precioGuantes = 100,
    this.precioFaja = 500,
    this.cagadaBonoPct = 2,
    this.dedoPujo = 1,
    this.epicoBase = 0.005,
    this.epicoPorDedo = 0.0003,
    this.epicoTope = 0.03,
    this.epicoTipo1 = 3,
    this.epicoMultiplicador = 10,
    this.cadenaCagadas = 5,
    this.candadoHoras = 2,
    this.candadoSubida = 0.1,
    this.cadenaDivisor = 1e10,
    this.cadenaExponente = 0.5,
    this.rolloPct = 0.04,
    this.alquilerDescuento = 0.22,
    this.calorFactor = 1.5,
    this.calorTope = 10,
    this.calorVidaMediaH = 6,
    this.maxPrimos = 4,
    this.topePujosSeg = 20,
    this.mudanzaRollos = 1e8,
    this.mudanzaRollosSubida = 30,
    this.mudanzaJaladas = 9,
    this.mudanzaCagadas = 30,
    this.mudanzaLlavesExponente = 1 / 3,
    this.mudanzaLlavesFactor = 3,
    this.llavePct = 0.25,
    this.mudanzaDivisorX = 15,
    this.mudanzaDescubreJaladas = 4,
    this.mudanzaDescubrePct = 0.25,
    this.mudanzaDescubreMin = 30,
    this.abdicarMudanzas = 4,
    this.abdicarLlaves = 87,
    this.abdicarCagadas = 60,
    this.abdicarCoronasExponente = 0.5,
    this.abdicarCoronasFactor = 3,
    this.coronaPct = 0.5,
    this.abdicarDescubrePct = 0.25,
    this.abdicarDescubreDias = 3,
    this.escalaEdificios = 1,
    this.escalaMejoras = 1,
    this.temporadas = const [],
  });

  /// Cuántas veces el precio del catálogo cuestan los edificios y las mejoras de MJ (Guantes, Faja y la cadena del
  /// trono tienen su precio aparte). Aquí van en 1 (las pruebas del motor usan los precios del catálogo); el juego usa
  /// los de [FlagsImperio], que es donde está el balance.
  final double escalaEdificios, escalaMejoras;

  /// Temporadas que mandó el servidor (flag `temporadas`). Cada una vale solo dentro de su rango ([Temporada.activa]).
  final List<Temporada> temporadas;

  static const Ajustes porDefecto = Ajustes();
}
