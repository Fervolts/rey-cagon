// Casas de la Mudanza 🏠: la capa de reinicio por encima de la cadena. Cada mudanza te lleva a una casa más grande,
// con más producción, más Rollos por jalada y sus propios nombres para los edificios (los emojis y los chistes no cambian).
// Sin widgets ni red: lo usan el motor, la tienda, los avisos y las pruebas.

import 'dart:math';

import '../idioma.dart';
import 'catalogo.dart';

class Casa {
  final String emoji;
  final String nombreEs, nombreEn;
  final String fraseEs, fraseEn;

  /// Multiplicador de producción de esta casa (Rancho x1).
  final double produccion;
  const Casa(this.emoji, this.nombreEs, this.nombreEn, this.fraseEs, this.fraseEn, this.produccion);
}

/// Las 5 casas. Después del Palacio la mudanza se repite (Palacio II, III...) con x3 de producción cada vez.
const List<Casa> casas = [
  Casa('🛖', 'Rancho', 'Shack', 'Donde empezó todo: una poceta y mucha fe', 'Where it all began: one toilet and a lot of faith', 1),
  Casa('🏠', 'Casa', 'House', 'Paredes de bloque y baño con puerta', 'Block walls and a bathroom with a door', 3),
  Casa('🏡', 'Quinta', 'Villa', 'Jardín, perro y dos baños de visita', 'A garden, a dog and two guest bathrooms', 10),
  Casa('🏛️', 'Mansión', 'Mansion', 'Mármol hasta en el bidet', 'Marble all the way to the bidet', 40),
  Casa('🏰', 'Palacio', 'Palace', 'Un trono de verdad, por fin', 'A real throne, at last', 200),
];

/// Producción extra de cada Palacio después del primero.
const double produccionPalacioExtra = 3;

/// Casa en la que estás después de [mudanzas] mudanzas (0 = Rancho). Del Palacio en adelante es la misma.
Casa casaDe(int mudanzas) => casas[mudanzas.clamp(0, casas.length - 1)];

/// Multiplicador de producción de la casa: x1, x3, x10, x40, x200 y x3 más por cada Palacio extra.
double multiplicadorCasa(int mudanzas) {
  if (mudanzas < casas.length) return casaDe(mudanzas).produccion;
  return casas.last.produccion * pow(produccionPalacioExtra, mudanzas - casas.length + 1);
}

/// Rollos por jalada de la casa: 1 + mudanzas. El servidor usa la misma cuenta en su tope.
int factorRollosCasa(int mudanzas) => 1 + max(0, mudanzas);

const List<String> _romanos = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];

String _romano(int n) => n < _romanos.length ? _romanos[n] : '$n';

/// Nombre de la casa ("Palacio II" desde la quinta mudanza).
String nombreCasa(int mudanzas) {
  final c = casaDe(mudanzas);
  final extra = mudanzas - casas.length + 2;
  final sufijo = mudanzas >= casas.length ? ' ${_romano(extra)}' : '';
  return '${tr(c.nombreEs, c.nombreEn)}$sufijo';
}

/// Emoji y nombre: "🏡 Quinta".
String casaConEmoji(int mudanzas) => '${casaDe(mudanzas).emoji} ${nombreCasa(mudanzas)}';

/// Nombres de los edificios en Casa, Quinta, Mansión y Palacio (es, en). En el Rancho son los del catálogo.
const Map<String, List<(String, String)>> _nombresPorCasa = {
  'dedo': [
    ('Dedo con uña pintada', 'Painted-nail finger'),
    ('Dedo con guante de jardín', 'Garden-glove finger'),
    ('Dedo de mayordomo', "Butler's finger"),
    ('Dedo real', 'Royal finger'),
  ],
  'ciruela': [
    ('Jugo de ciruela', 'Prune juice'),
    ('Té de sen', 'Senna tea'),
    ('Laxante importado', 'Imported laxative'),
    ('Elixir real', 'Royal elixir'),
  ],
  'cafe': [
    ('Guayoyo', 'Guayoyo'),
    ('Café de hacienda', 'Estate coffee'),
    ('Espresso de cápsula', 'Capsule espresso'),
    ('Café de oro', 'Golden coffee'),
  ],
  'arepa': [
    ('Pabellón criollo', 'Pabellón criollo'),
    ('Hallaca de diciembre', 'December hallaca'),
    ('Tequeños de fiesta', 'Party tequeños'),
    ('Banquete real', 'Royal banquet'),
  ],
  'inodoro': [
    ('Bidet de agua tibia', 'Warm-water bidet'),
    ('Poceta con calefacción', 'Heated toilet'),
    ('Inodoro japonés', 'Japanese toilet'),
    ('Trono de oro', 'Golden throne'),
  ],
  'bano': [
    ('Baño con cortina de patitos', 'Duck-curtain bathroom'),
    ('Baño con vista al jardín', 'Garden-view bathroom'),
    ('Baño de mármol', 'Marble bathroom'),
    ('Baño real', 'Royal bathroom'),
  ],
  'camion': [
    ('Camión cisterna', 'Tanker truck'),
    ('Flota de vacuums', 'Vacuum fleet'),
    ('Helicóptero vacuum', 'Vacuum helicopter'),
    ('Flota imperial', 'Imperial fleet'),
  ],
  'planta': [
    ('Planta de biogás', 'Biogas plant'),
    ('Refinería de abono', 'Fertilizer refinery'),
    ('Planta nuclear de mojones', 'Poop nuclear plant'),
    ('Fábrica de lingotes', 'Bullion factory'),
  ],
  'cloaca': [
    ('Alcantarilla del condominio', 'Condo sewer'),
    ('Pozo séptico olímpico', 'Olympic septic tank'),
    ('Red de cloacas privada', 'Private sewer network'),
    ('Cloaca imperial', 'Imperial sewer'),
  ],
  'granja': [
    ('Granja de cucarachas', 'Roach farm'),
    ('Establo de moscas', 'Fly stable'),
    ('Hacienda de moscas', 'Fly ranch'),
    ('Imperio de moscas', 'Fly empire'),
  ],
  'mina': [
    ('Pozo de gas del vecino', "Neighbor's gas well"),
    ('Yacimiento de metano', 'Methane field'),
    ('Plataforma de gas', 'Gas rig'),
    ('Planeta de metano', 'Methane planet'),
  ],
  'templo': [
    ('Iglesia del Santo Trono', 'Church of the Holy Throne'),
    ('Catedral del Trono', 'Throne cathedral'),
    ('Pirámide del Trono', 'Throne pyramid'),
    ('Templo del universo', 'Temple of the universe'),
  ],
  'volcan': [
    ('Géiser de diarrea', 'Diarrhea geyser'),
    ('Cordillera digestiva', 'Digestive range'),
    ('Volcán en el patio', 'Backyard volcano'),
    ('Sol digestivo', 'Digestive sun'),
  ],
  'laxante_tiempo': [
    ('Ciruela del tiempo', 'Time prune'),
    ('Reloj de arena laxante', 'Laxative hourglass'),
    ('Máquina del tiempo intestinal', 'Gut time machine'),
    ('Laxante de la eternidad', 'Laxative of eternity'),
  ],
  'agujero': [
    ('Agujero de gusano intestinal', 'Intestinal wormhole'),
    ('Supernova de fibra', 'Fiber supernova'),
    ('Galaxia de mojones', 'Poop galaxy'),
    ('Big Bang intestinal', 'Intestinal Big Bang'),
  ],
};

/// Nombre (es, en) del edificio [id] en la casa de [mudanzas]. Rancho = el del catálogo; del Palacio en adelante, el del Palacio.
(String, String) nombresEdificio(String id, int mudanzas) {
  final lista = _nombresPorCasa[id];
  if (mudanzas <= 0 || lista == null) {
    final e = edificioPorId(id);
    return e == null ? (id, id) : (e.nombreEs, e.nombreEn);
  }
  return lista[min(mudanzas, lista.length) - 1];
}

/// Nombre del edificio [id] en la casa de [mudanzas], en el idioma del jugador.
String nombreEdificio(String id, int mudanzas) {
  final (es, en) = nombresEdificio(id, mudanzas);
  return tr(es, en);
}
