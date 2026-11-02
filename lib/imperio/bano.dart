// El baño del Imperio: la escena alrededor de la poceta.
//
// Arranca destartalado (cerámica partida, mancha de humedad, bombillo pelado, periódico en un clavo, tobo con agua)
// y cada adorno arregla algo que se ve. Los edificios ponen cosas que hacen algo (leche de magnesia, budare, el
// bidet de piso, el baño de clase media, el camión vacuum, el reactor, la cloaca de abajo, las moscas) y el
// edificio más alto cambia el ambiente (ventana, tinte; sobre todo fase 2). Las mejoras del bidet arreglan la poceta
// misma (tapa, botones, mármol, chorrito japonés, oro). Las estéticas premium cambian piezas por versiones de lujo.
// Personalizar (`vista` de la partida) oculta cosas, elige ambiente y cuántos dedos se ven: solo visual.
//
// [EstadoBano] es puro: sale de las mejoras y los edificios, y se compara por valor. [FondoBano] dibuja lo que no se
// mueve (un CustomPainter y unos pocos emojis quietos) y solo se repinta cuando cambia el estado, no en cada tick.
// Lo que se mueve (parpadeo, gota, café, dedos...) va en poceta.dart.

import 'dart:math';

import 'package:flutter/material.dart';

import '../emoji.dart';
import 'esteticas.dart';

/// El edificio más alto que tienes: cambia el ambiente del baño. `publico` es el baño de clase media (el nombre se
/// queda: se guarda en la vista de Personalizar). `camion`, `planta`, `cloaca` y `granja` ya no son ambientes (ni el
/// automático ni Personalizar los dan); se quedan solo para no romper nombres guardados.
enum AmbienteBano { casa, publico, camion, planta, cloaca, granja, mina, templo, volcan, laxante, agujero }

/// Color de los dedos: la mejor mejora comprada.
enum ColorDedo { piel, latex, acero, oro }

/// Forma de los dedos: ambidiestros (unos al revés), dedo del pie (uno sí, uno no), mano entera.
enum FormaDedo { normal, ambidiestro, pie, mano }

const _niveles = [1, 5, 10, 25, 50, 100, 150, 200];

// Edificio que pone cada ambiente, del más alto al más bajo. Solo escenas de verdad: el camión, la planta, la cloaca y
// el criadero de moscas son cosas dentro del baño, no un baño aparte, así que no entran (sus valores siguen en el enum
// porque la vista guardada los nombra; un 'camion' viejo se ignora y queda el automático).
const _ambientes = [
  ('agujero', AmbienteBano.agujero),
  ('laxante_tiempo', AmbienteBano.laxante),
  ('volcan', AmbienteBano.volcan),
  ('templo', AmbienteBano.templo),
  ('mina', AmbienteBano.mina),
  ('bano', AmbienteBano.publico),
];

/// Lo alquilado que está activo y se ve en el baño: cuántos primos pujan, la cuadrilla, el plomero por horas, el
/// robot (0 nada, 1 Robot, 2 Turbo) y el guardia. Es un record: se compara por valor.
typedef AlquilerBano = ({int primos, bool cuadrilla, bool plomero, int robot, bool guardia});

/// Nada alquilado.
const AlquilerBano sinAlquiler = (primos: 0, cuadrilla: false, plomero: false, robot: 0, guardia: false);

/// Qué hay en el baño. Puro: sin Flutter de por medio, se compara por valor.
@immutable
class EstadoBano {
  const EstadoBano({
    this.bombillo = false,
    this.papel = false,
    this.forro = false,
    this.alfombra = false,
    this.cortina = false,
    this.matica = false,
    this.ceramica = false,
    this.pintura = false,
    this.tanque = 0,
    this.valvula = 0,
    this.iman = false,
    this.brillo = false,
    this.lavanda = false,
    this.colorDedo = ColorDedo.piel,
    this.formaDedo = FormaDedo.normal,
    this.adornoDedo,
    this.leche = 0,
    this.lecheVerde = false,
    this.lecheNuclear = false,
    this.cafe = 0,
    this.arepa = 0,
    this.arepaBrillo = false,
    this.bidet = 0,
    this.tapaAcolchada = false,
    this.asientoCaliente = false,
    this.descargaDoble = false,
    this.wifi = false,
    this.marmol = false,
    this.japones = false,
    this.pocetaOro = false,
    this.ambiente = AmbienteBano.casa,
    this.claseMedia = 0,
    this.camion = 0,
    this.planta = 0,
    this.cloaca = 0,
    this.moscas = 0,
    this.lujos = '',
    this.alquiler = sinAlquiler,
  });

  /// Sale de lo comprado: [comprada] dice si una mejora está comprada y [cantidad] cuántos hay de un edificio.
  /// [esteticas] son las premium compradas y [vista] las preferencias de Personalizar (`Partida.vista`): lo oculto no
  /// se dibuja y el ambiente elegido manda si ya está desbloqueado.
  factory EstadoBano.desde(
      {required bool Function(String id) comprada,
      required int Function(String id) cantidad,
      Set<String> esteticas = const {},
      Map<String, dynamic>? vista,
      AlquilerBano alquiler = sinAlquiler}) {
    int nivel(String e) => _niveles.where((n) => comprada('${e}_$n')).length;
    final ocultos = {for (final x in (vista?['ocultos'] as List?) ?? const []) '$x'};
    bool ver(String id) => !ocultos.contains(id);
    bool tiene(String id, bool si) => si && ver(id);
    int cuanto(String id, int n) => ver(id) ? n : 0;
    final leches = cantidad('ciruela'), nLeche = nivel('ciruela');
    var ambiente = AmbienteBano.casa;
    for (final (id, a) in _ambientes) {
      if (cantidad(id) > 0) {
        ambiente = a;
        break;
      }
    }
    final elegido = vista?['ambiente'];
    for (final a in ambientesDesbloqueados(cantidad)) {
      if (a.name == elegido) ambiente = a;
    }
    final lujoPoceta = ver('lujos_poceta');
    int escalon(String id, List<int> desde) {
      final n = cantidad(id);
      return n == 0 ? 0 : 1 + desde.where((d) => n >= d).length;
    }

    return EstadoBano(
      bombillo: tiene('bombillo', comprada('adorno_bombillo')),
      papel: tiene('papel', comprada('adorno_papel')),
      forro: tiene('forro', comprada('adorno_forro')),
      alfombra: tiene('alfombra', comprada('adorno_alfombra')),
      cortina: tiene('cortina', comprada('adorno_cortina')),
      matica: tiene('matica', comprada('adorno_matica')),
      ceramica: tiene('ceramica', comprada('adorno_ceramica')),
      pintura: tiene('pintura', comprada('adorno_pintura')),
      tanque: cuanto('pipote', comprada('tanque_8') ? 2 : (comprada('tanque_4') ? 1 : 0)),
      valvula: comprada('valvula_75') ? 2 : (comprada('valvula_50') ? 1 : 0),
      iman: comprada('iman'),
      brillo: tiene('brillo', comprada('brillo')),
      lavanda: tiene('lavanda', comprada('lavanda')),
      colorDedo: comprada('dedo_200')
          ? ColorDedo.oro
          : (comprada('dedo_acero') || comprada('dedo_100'))
              ? ColorDedo.acero
              : (comprada('guantes') || comprada('dedo_5'))
                  ? ColorDedo.latex
                  : ColorDedo.piel,
      formaDedo: comprada('dedo_150')
          ? FormaDedo.mano
          : comprada('dedo_50')
              ? FormaDedo.pie
              : comprada('dedo_25')
                  ? FormaDedo.ambidiestro
                  : FormaDedo.normal,
      adornoDedo: comprada('dedo_200') ? '👑' : (comprada('dedo_10') ? '💍' : (comprada('faja') ? '🩲' : null)),
      // El edificio 'ciruela' es la leche de magnesia (el id no cambia).
      leche: cuanto('leche', leches == 0 ? 0 : 1 + (nLeche >= 3 ? 1 : 0) + (nLeche >= 5 ? 1 : 0)),
      lecheVerde: comprada('ciruela_150'),
      lecheNuclear: comprada('ciruela_200'),
      cafe: cuanto('cafe', cantidad('cafe') == 0 ? 0 : 1 + nivel('cafe')),
      arepa: cuanto('arepa', cantidad('arepa') == 0 ? 0 : 1 + (comprada('arepa_10') ? 1 : 0) + (comprada('arepa_50') ? 1 : 0)),
      arepaBrillo: comprada('arepa_200'),
      // El edificio 'inodoro' es el bidet (el id no cambia: las partidas guardadas lo usan).
      bidet: cuanto('bidet', cantidad('inodoro') == 0 ? 0 : (comprada('inodoro_25') ? 2 : 1)),
      tapaAcolchada: lujoPoceta && comprada('inodoro_1'),
      asientoCaliente: lujoPoceta && comprada('inodoro_5'),
      descargaDoble: lujoPoceta && comprada('inodoro_10'),
      wifi: lujoPoceta && comprada('inodoro_50'),
      marmol: lujoPoceta && comprada('inodoro_100'),
      japones: lujoPoceta && comprada('inodoro_150'),
      pocetaOro: lujoPoceta && comprada('inodoro_200'),
      ambiente: ambiente,
      // Los edificios de abajo no tienen mejoras (no son de fase 1): cambian con la cantidad.
      claseMedia: cuanto('clase_media', cantidad('bano') == 0 ? 0 : 1 + nivel('bano')),
      camion: cuanto('camion', cantidad('camion') == 0 ? 0 : 1 + nivel('camion')),
      planta: cuanto('planta', cantidad('planta') == 0 ? 0 : 1 + nivel('planta')),
      cloaca: cuanto('cloaca', escalon('cloaca', const [10, 25, 50])),
      moscas: cuanto('moscas', escalon('granja', const [10, 25, 50, 100])),
      lujos: (esteticas.where((x) => x.startsWith('est_') && ver(x)).toList()..sort()).join(','),
      alquiler: alquiler,
    );
  }

  /// Ambientes que ya se pueden elegir en Personalizar: la casa y los de cada edificio que tengas.
  static List<AmbienteBano> ambientesDesbloqueados(int Function(String id) cantidad) =>
      [AmbienteBano.casa, for (final (id, a) in _ambientes.reversed) if (cantidad(id) > 0) a];

  // Adornos: cada uno arregla algo.
  final bool bombillo, papel, forro, alfombra, cortina, matica, ceramica, pintura;

  /// Mejoras de la poceta: tanque (0 tobo, 1 pipote, 2 pipote grande), válvula (0 gotea, 1 cromada, 2 dorada).
  final int tanque, valvula;
  final bool iman, brillo, lavanda;

  final ColorDedo colorDedo;
  final FormaDedo formaDedo;

  /// Lo único que lleva puesto el dedo (🩲, 💍 o 👑), o nada.
  final String? adornoDedo;

  /// Leche de magnesia en la repisa: 0 nada, 1 botella, 2 botella familiar, 3 pipote.
  final int leche;
  final bool lecheVerde, lecheNuclear;

  /// Café: 0 nada; si no, 1 + mejoras compradas (el chorro engorda).
  final int cafe;

  /// Arepa: 0 nada, 1 una en el budare, 2 dos, 3 budare grande.
  final int arepa;
  final bool arepaBrillo;

  /// Bidet: 0 nada, 1 manguerita colgada junto a la poceta, 2 a presión (echa su chorro cada tanto).
  final int bidet;

  /// Mejoras del bidet, dibujadas sobre la poceta principal.
  final bool tapaAcolchada, asientoCaliente, descargaDoble, wifi, marmol, japones, pocetaOro;
  final AmbienteBano ambiente;

  /// Baño de clase media: 0 nada, 1 de base y uno más por cada mejora (hasta 9).
  final int claseMedia;

  /// Camión vacuum: 0 nada, 1 de base y uno más por cada mejora (hasta 9).
  final int camion;

  /// Reactor de la planta: 0 nada, 1 de base y uno más por cada mejora (hasta 9).
  final int planta;

  /// Cloaca de abajo: 0 nada, 1 a 4 según cuántas tengas (10, 25, 50).
  final int cloaca;

  /// Moscas: 0 nada, 1 unas pocas, 2 con casquito, 3 con reina, 4 enjambre, 5 de oro (10, 25, 50, 100).
  final int moscas;

  /// Estéticas premium visibles, ordenadas y unidas por coma (para comparar por valor).
  final String lujos;

  /// Lo alquilado activo (primos, cuadrilla, plomero, robot, guardia): lo dibuja la poceta (poceta.dart), junto con su tira "trabajando ahora".
  final AlquilerBano alquiler;

  bool lujo(String id) => lujos.split(',').contains(id);

  /// Lo que lleva la taza del chorro de café.
  String get objetoCafe => cafe >= 7 ? '💉' : (cafe >= 6 ? '🫖' : '☕');

  Object get _clave => (
        bombillo, papel, forro, alfombra, cortina, matica, ceramica, pintura, tanque, valvula, iman, brillo, lavanda,
        colorDedo, formaDedo, adornoDedo, leche, lecheVerde, lecheNuclear, cafe, arepa, arepaBrillo, bidet,
        tapaAcolchada, asientoCaliente, descargaDoble, wifi, marmol, japones, pocetaOro, ambiente,
        (claseMedia, camion, planta, cloaca, moscas, lujos, alquiler),
      );

  @override
  bool operator ==(Object other) => other is EstadoBano && other._clave == _clave;

  @override
  int get hashCode => _clave.hashCode;
}

/// Una cosa del baño que se puede ocultar en Personalizar. [tiene] mira el estado sin ocultar nada.
typedef OcultableBano = ({String id, String emoji, String es, String en, bool Function(EstadoBano e) tiene});

/// Lo que se puede ocultar (los ids los lee [EstadoBano.desde]). Las estéticas premium se ocultan por su id `est_*`.
final List<OcultableBano> ocultablesBano = [
  (id: 'clase_media', emoji: '🛁', es: 'Baño de clase media', en: 'Middle-class bathroom', tiene: (e) => e.claseMedia > 0),
  (id: 'camion', emoji: '🚛', es: 'Camión vacuum', en: 'Vacuum truck', tiene: (e) => e.camion > 0),
  (id: 'planta', emoji: '☢️', es: 'Reactor y su tubo', en: 'Reactor and its pipe', tiene: (e) => e.planta > 0),
  (id: 'cloaca', emoji: '🕳️', es: 'Cloaca de abajo', en: 'Sewer below', tiene: (e) => e.cloaca > 0),
  (id: 'moscas', emoji: '🪰', es: 'Moscas', en: 'Flies', tiene: (e) => e.moscas > 0),
  (id: 'leche', emoji: '🥛', es: 'Leche de magnesia', en: 'Milk of magnesia', tiene: (e) => e.leche > 0),
  (id: 'cafe', emoji: '☕', es: 'Chorro de café', en: 'Coffee stream', tiene: (e) => e.cafe > 0),
  (id: 'arepa', emoji: '🫓', es: 'Budare', en: 'Griddle', tiene: (e) => e.arepa > 0),
  (id: 'bidet', emoji: '🚿', es: 'Bidet', en: 'Bidet', tiene: (e) => e.bidet > 0),
  (
    id: 'lujos_poceta',
    emoji: '🚽',
    es: 'Lujos de la poceta',
    en: 'Toilet upgrades',
    tiene: (e) => e.tapaAcolchada || e.asientoCaliente || e.descargaDoble || e.wifi || e.marmol || e.japones || e.pocetaOro
  ),
  (id: 'pipote', emoji: '🛢️', es: 'Pipote de agua', en: 'Water drum', tiene: (e) => e.tanque > 0),
  (id: 'bombillo', emoji: '💡', es: 'Lámpara', en: 'Lamp', tiene: (e) => e.bombillo),
  (id: 'papel', emoji: '🧻', es: 'Papel', en: 'Toilet paper', tiene: (e) => e.papel),
  (id: 'forro', emoji: '🧶', es: 'Forro peludo', en: 'Fuzzy cover', tiene: (e) => e.forro),
  (id: 'alfombra', emoji: '🟫', es: 'Alfombra', en: 'Rug', tiene: (e) => e.alfombra),
  (id: 'cortina', emoji: '🌸', es: 'Cortina de flores', en: 'Flower curtain', tiene: (e) => e.cortina),
  (id: 'matica', emoji: '🪴', es: 'Matica', en: 'Little plant', tiene: (e) => e.matica),
  (id: 'lavanda', emoji: '🪻', es: 'Lavanda', en: 'Lavender', tiene: (e) => e.lavanda),
  (id: 'ceramica', emoji: '🧱', es: 'Cerámica nueva', en: 'New tiles', tiene: (e) => e.ceramica),
  (id: 'pintura', emoji: '🎨', es: 'Pintura nueva', en: 'Fresh paint', tiene: (e) => e.pintura),
  (id: 'brillo', emoji: '✨', es: 'Destellos', en: 'Sparkles', tiene: (e) => e.brillo),
  for (final s in esteticas) (id: s.id, emoji: s.emoji, es: s.nombreEs, en: s.nombreEn, tiene: (e) => e.lujo(s.id)),
];

/// Dónde va cada cosa del piso (x relativa al centro, y desde arriba). `cucaracha` y `camion` son la y de su carril.
/// `budareDelante`: el budare y las arepas van delante del camión (en el piso apretado el camión pasa por detrás).
typedef LugaresBano = ({Offset bidet, double escalaBidet, Offset tobo, double tamTobo, Offset matica, Offset budare, bool budareDelante, double cucaracha, double camion});

/// Medidas de la escena. Las x son relativas al centro (cx); las y, absolutas desde arriba.
abstract final class Bano {
  static const alto = 280.0;
  static const piso = 192.0; // donde la pared se junta con el piso
  static const banda = 60.0; // pintura arriba, cerámica abajo
  static const azulejo = 22.0;
  static const ventana = Rect.fromLTRB(40, 12, 118, 62);
  static const lavamanos = -145.0; // centro del lavamanos
  static const grifo = Offset(-137, 110); // donde gotea
  static const repisa = Rect.fromLTRB(-112, 72, -62, 76);
  static const frasco = Offset(-87, 54);
  static const bombillo = Offset(-28, 34);
  static const papel = Offset(74, 140);
  static const letrero = Offset(108, 100);
  static const letreroPlanta = Offset(89, 88); // con reactor el letrero se corre
  static const lavanda = Offset(-122, 104);
  static const destellos = [Offset(-130, 42), Offset(26, 72), Offset(-62, 182)];

  // Reactor de la planta (a la derecha) y su tubo desde el tanque.
  static const reactor = Rect.fromLTRB(88, 104, 136, 208);
  static const lucesReactor = [Offset(97, 117), Offset(127, 117)];
  static const orbita = Rect.fromLTRB(76, 128, 148, 164);
  static const nucleo = Rect.fromLTRB(102, 132, 122, 166);
  static const chimenea = Offset(125, 50);
  static const tuboPlanta = [Offset(52, 100), Offset(66, 100), Offset(66, 72), Offset(112, 72), Offset(112, 104)];

  // Cloaca: una franja de sótano debajo del piso.
  static const sotano = 44.0;

  /// Bañera de clase media (detrás de la matica) y la ducha de lluvia encima.
  static const banera = Rect.fromLTRB(146, 186, 236, 226);
  static const ducha = Offset(174, 18);
  static const cuadro = Offset(12, 36); // el cuadro de la clase media
  static const piloto = Offset(-54, 34); // la llamita del calentador

  /// Alto total de la escena (con cloaca hay sótano).
  static double altura(EstadoBano e) => alto + (e.cloaca > 0 ? sotano : 0);

  /// Desde cuánto piso de más (la escena llenando la pantalla, debajo de los 280) las cosas del piso se separan.
  static const sueloAmplio = 120.0;

  /// Las cosas del piso según cuánto piso de más hay. Sin él (tarjeta del chat, cloaca, pantallas bajitas) se quedan
  /// apretadas en la franja de piso de la escena; con él bajan y se reparten: bidet al lado de la poceta, tobo a la
  /// izquierda, budare a la derecha (lejos del camión, que entra y se para por la izquierda), matica en su esquina, la
  /// cucaracha y el camión por carriles propios. Apretadas, el budare se queda a la izquierda pero delante del camión.
  static LugaresBano lugares(EstadoBano e, double suelo) {
    if (suelo < sueloAmplio || e.cloaca > 0) {
      return (
        bidet: const Offset(100, 260),
        escalaBidet: .8,
        tobo: const Offset(-82, 252),
        tamTobo: 30.0,
        matica: const Offset(164, 250),
        budare: const Offset(-150, 266),
        budareDelante: true,
        cucaracha: 262.0,
        camion: 272.0,
      );
    }
    return (
      bidet: const Offset(100, 290),
      escalaBidet: 1.15,
      tobo: const Offset(-104, 294),
      tamTobo: 40.0,
      matica: Offset(164, alto + min(suelo * .25, 56)),
      budare: Offset(112, alto + suelo * .55),
      budareDelante: false,
      cucaracha: alto + suelo * .5,
      camion: min(alto + suelo * .82, alto + suelo - 10),
    );
  }

  /// Por donde sale el chorro del bidet (el centro de la taza).
  static Offset chorroBidet(LugaresBano l) => l.bidet + Offset(0, -41 * l.escalaBidet);

  /// Cuánto puede subir el chorro del bidet sin mojar el reactor (que queda justo encima a la derecha).
  static double altoChorro(LugaresBano l, EstadoBano e, double quiere) {
    if (e.planta == 0) return quiere;
    return min(quiere, max(10.0, chorroBidet(l).dy - reactor.bottom - 6));
  }

  /// Lo que ocupa el bidet (para tocarlo).
  static Rect cajaBidet(LugaresBano l) {
    final b = l.bidet, k = l.escalaBidet;
    return Rect.fromLTRB(b.dx - 26 * k, b.dy - 58 * k, b.dx + 26 * k, b.dy + 4);
  }

  /// Lo que ocupa el budare con sus arepas (para tocarlo).
  static Rect cajaArepa(LugaresBano l) => Rect.fromCenter(center: l.budare + const Offset(0, -6), width: 70, height: 34);

  /// Lo que ocupa el tobo o, con tanque, el pipote azul.
  static Rect cajaTobo(EstadoBano e, LugaresBano l) {
    if (e.tanque == 0) return Rect.fromCenter(center: l.tobo, width: l.tamTobo, height: l.tamTobo);
    final grande = e.tanque == 2;
    final c = l.tobo + Offset(grande ? 4 : 0, 0);
    final ancho = grande ? 42.0 : 32.0, alto = grande ? 58.0 : 44.0;
    return Rect.fromLTRB(c.dx - ancho / 2, c.dy + 16 - alto - 4, c.dx + ancho / 2, c.dy + 16);
  }

  /// Qué cosa quieta de la escena hay en [p] (x relativa al centro, y desde arriba de la escena), o null. La poceta
  /// misma no cuenta (ahí se puja nada más). La cucaracha y el camión se mueven: los busca poceta.dart.
  static String? objetoEn(EstadoBano e, Offset p, double suelo) {
    if (const Rect.fromLTRB(-56, 86, 56, 216).contains(p)) return null;
    final l = lugares(e, suelo);
    if (e.bidet > 0 && cajaBidet(l).contains(p)) return 'bidet';
    if (cajaTobo(e, l).contains(p)) return 'tobo';
    if (Rect.fromCenter(center: bombillo, width: 32, height: 44).contains(p)) return 'bombillo';
    if (const Rect.fromLTRB(-177, 26, -113, 92).contains(p)) return 'espejo';
    if (const Rect.fromLTRB(-177, 97, -113, 202).contains(p)) return 'lavamanos';
    if (e.planta > 0 && reactor.contains(p)) return 'reactor';
    if (e.claseMedia >= 6 && const Rect.fromLTRB(150, 0, 198, 60).contains(p)) return 'ducha';
    if (e.claseMedia >= 4 && Rect.fromCenter(center: cuadro, width: 38, height: 38).contains(p)) return 'cuadro';
    if (ventana.contains(p)) return 'ventana';
    if (e.matica && Rect.fromCenter(center: l.matica, width: 40, height: 44).contains(p)) return 'matica';
    if (e.arepa > 0 && cajaArepa(l).contains(p)) return 'arepa';
    if (e.claseMedia >= 8 && banera.contains(p)) return 'banera';
    if ((e.papel || e.lujo('est_papel')) && const Rect.fromLTRB(60, 122, 88, 158).contains(p)) return 'papel';
    return null;
  }

  /// Tubo que baja a la cloaca: del reactor si hay planta, si no del pie de la poceta.
  static List<Offset> tuboCloaca(EstadoBano e) => e.planta > 0
      ? const [Offset(130, 208), Offset(130, 280 + 14)]
      : const [Offset(-6, 212), Offset(-6, 280 + 14)];
}

/// Lo quieto de la escena: el fondo pintado y los emojis que no se mueven. Ponerlo dentro de un RepaintBoundary.
class FondoBano extends StatelessWidget {
  const FondoBano({super.key, required this.estado, this.techo = true});

  final EstadoBano estado;

  /// false: hay pared de más encima y la mancha de humedad va allá arriba (ver [PintorMancha]).
  final bool techo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final cx = caja.maxWidth / 2;
      final e = estado;
      Widget en(Offset o, double tam, Widget hijo) => Positioned(left: cx + o.dx - tam / 2, top: o.dy - tam / 2, width: tam, height: tam, child: hijo);
      final v = Bano.ventana.shift(Offset(cx, 0)).deflate(3);
      final hijos = <Widget>[
        Positioned.fill(child: CustomPaint(painter: PintorBano(e, techo: techo), isComplex: true, willChange: false)),
        // Lo que se ve por la ventana.
        if (e.ambiente == AmbienteBano.volcan)
          Positioned.fromRect(rect: v, child: const ClipRect(child: Align(alignment: Alignment(0, 1.4), child: Emoji('🌋', tamano: 44)))),
        if (e.ambiente == AmbienteBano.agujero)
          Positioned.fromRect(rect: v, child: const ClipRect(child: Align(alignment: Alignment(.3, 0), child: Emoji('🌌', tamano: 40)))),
        if (!e.bombillo && !e.lujo('est_lampara')) en(Bano.bombillo, 24, const RotatedBox(quarterTurns: 2, child: Emoji('💡', tamano: 24))),
        if (e.papel || e.lujo('est_papel')) en(Bano.papel, 24, const Emoji('🧻', tamano: 24)),
        if (e.claseMedia >= 8) en(const Offset(172, 180), 22, const Emoji('🫧', tamano: 22)),
        if (e.claseMedia >= 8) en(const Offset(194, 172), 16, const Emoji('🫧', tamano: 16)),
        if (e.planta > 0) en(Bano.reactor.center + const Offset(0, 30), 18, const Emoji('☢️', tamano: 18)),
        if (e.cloaca >= 2) en(const Offset(-150, Bano.alto + 30), 20, const Emoji('🐀', tamano: 20)),
        if (e.lavanda) en(Bano.lavanda, 20, const Emoji('🪻', tamano: 20)),
        ..._repisa(e, en),
        if (_letrero(e) case final l?) en(e.planta > 0 ? Bano.letreroPlanta : Bano.letrero, 26, Emoji(l, tamano: 26)),
      ];
      return Stack(clipBehavior: Clip.hardEdge, children: hijos);
    });
  }

  /// Un emoji teñido de oro (estéticas y moscas de oro).
  static Widget dorado(Widget hijo) =>
      ColorFiltered(colorFilter: ColorFilter.mode(const Color(0xFFFFC21A).withValues(alpha: .55), BlendMode.srcATop), child: hijo);

  static String? _letrero(EstadoBano e) => switch (e.ambiente) {
        AmbienteBano.mina => '⛏️',
        AmbienteBano.templo => '🛕',
        AmbienteBano.laxante => '⏳',
        _ => null,
      };

  // La leche de magnesia en la repisa: botella, botella familiar o pipote, con su cuchara al lado.
  static List<Widget> _repisa(EstadoBano e, Widget Function(Offset, double, Widget) en) {
    if (e.leche == 0) return const [];
    final tam = switch (e.leche) { 1 => 24.0, 2 => 30.0, _ => 36.0 };
    Widget botella = Emoji('🥛', tamano: tam);
    if (e.lecheVerde) {
      botella = ColorFiltered(colorFilter: ColorFilter.mode(const Color(0xFF5BD14B).withValues(alpha: .5), BlendMode.srcATop), child: botella);
    }
    final f = Bano.frasco + Offset(-4, 18 - tam / 2);
    return [
      en(f, tam, botella),
      en(Bano.frasco + const Offset(16, 12), 14, const RotatedBox(quarterTurns: 1, child: Emoji('🥄', tamano: 14))),
      // Nuclear: el símbolo va como etiqueta pegada a la botella, no suelto al lado.
      if (e.lecheNuclear) en(f + Offset(tam / 4, tam / 5), 12, const Emoji('☢️', tamano: 12)),
    ];
  }
}

/// Las baldosas del piso de más, debajo de los 280 de la escena: misma fuga (-260) y filas que crecen ~25% cada una
/// (la última de la escena mide 24). [size] es solo esa franja; y = 0 es el borde de abajo de la escena.
void pintarPisoDeMas(Canvas canvas, Size size, EstadoBano e) {
  final w = size.width, cx = w / 2;
  const h = Bano.alto, fuga = -260.0;
  final marmol = e.lujo('est_piso');
  final a = marmol ? const Color(0xFFF3EFE6) : (e.ceramica ? const Color(0xFFE4E7EA) : const Color(0xFFB4A88F));
  final b = marmol ? const Color(0xFFD9D3C7) : (e.ceramica ? const Color(0xFFB7C0C8) : const Color(0xFF8A7F69));
  double xEn(double xb, double y) => cx + (xb - cx) * (y + h - fuga) / (h - fuga);
  final pincel = Paint()..isAntiAlias = false;
  var y0 = 0.0, alto = 30.0;
  for (var f = 0; y0 < size.height; f++) {
    final y1 = y0 + alto;
    final n = (w / 2 / 46 * (h - fuga) / (y0 + h - fuga)).ceil() + 1;
    for (var c = -n; c < n; c++) {
      final xb0 = cx + c * 46.0, xb1 = xb0 + 46;
      // Es la fila 6 de la escena en adelante (par): alterna igual que si siguiera.
      pincel.color = (c + f).isEven ? a : b;
      canvas.drawPath(
          Path()
            ..moveTo(xEn(xb0, y0), y0)
            ..lineTo(xEn(xb1, y0), y0)
            ..lineTo(xEn(xb1, y1), y1)
            ..lineTo(xEn(xb0, y1), y1)
            ..close(),
          pincel);
    }
    y0 = y1;
    alto *= 1.25;
  }
}

/// Mancha de humedad que baja del techo (y = 0 del lienzo): borde irregular y dos chorreaditos.
void pintarMancha(Canvas canvas, double cx) {
  final c = Offset(cx - 66, 0);
  final mancha = Path()
    ..moveTo(c.dx - 46, 0)
    ..cubicTo(c.dx - 48, 14, c.dx - 30, 20, c.dx - 32, 30)
    ..cubicTo(c.dx - 30, 40, c.dx - 12, 36, c.dx - 8, 30)
    ..cubicTo(c.dx + 2, 42, c.dx + 18, 34, c.dx + 20, 24)
    ..cubicTo(c.dx + 34, 26, c.dx + 44, 12, c.dx + 40, 0)
    ..close();
  canvas.drawPath(mancha, Paint()..color = const Color(0x2E5A3A12));
  canvas.drawOval(Rect.fromCenter(center: c + const Offset(-6, 6), width: 52, height: 30), Paint()..color = const Color(0x1F5A3A12));
  final chorro = Paint()..color = const Color(0x265A3A12);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - 22, 30, 4, 18), const Radius.circular(2)), chorro);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx + 8, 32, 3, 11), const Radius.circular(2)), chorro);
}

/// Solo la mancha de humedad, para el techo de verdad cuando la pared se estira hacia arriba.
class PintorMancha extends CustomPainter {
  PintorMancha(this.estado);

  final EstadoBano estado;

  @override
  bool shouldRepaint(PintorMancha old) => old.estado != estado;

  @override
  void paint(Canvas canvas, Size size) {
    if (!estado.ceramica) pintarMancha(canvas, size.width / 2);
  }
}

/// El fondo pintado. Solo se repinta si cambia el [EstadoBano].
class PintorBano extends CustomPainter {
  PintorBano(this.estado, {this.techo = true, this.estirar = false});

  final EstadoBano estado;

  /// El borde de arriba del lienzo es el techo: ahí cuelga la mancha de humedad.
  final bool techo;

  /// Para estirar su franja de arriba como pared de más: sin el resplandor de la lámpara, que llega al borde
  /// y estirado se vuelve una franja clara.
  final bool estirar;

  @override
  bool shouldRepaint(PintorBano old) => old.estado != estado || old.techo != techo || old.estirar != estirar;

  @override
  void paint(Canvas canvas, Size size) {
    final e = estado;
    final w = size.width, cx = w / 2;
    final pincel = Paint()..isAntiAlias = true;
    Rect r(double l, double t, double ri, double b) => Rect.fromLTRB(cx + l, t, cx + ri, b);
    // Piso de más: la escena llena la pantalla y el piso sigue debajo de los 280.
    final suelo = max(0.0, size.height - Bano.altura(e));
    final lugar = Bano.lugares(e, suelo);

    _banda(canvas, size, cx);
    _azulejos(canvas, size, cx);
    _piso(canvas, size, cx);
    if (suelo > 0 && e.cloaca == 0) {
      canvas.save();
      canvas.translate(0, Bano.alto);
      pintarPisoDeMas(canvas, Size(w, suelo), e);
      canvas.restore();
    }
    _ventana(canvas, cx);

    // Moldura entre la pintura y la cerámica.
    pincel.color = e.ambiente == AmbienteBano.templo
        ? const Color(0xFFD4A72C)
        : (e.pintura ? const Color(0xFFF4F1E8) : const Color(0xFF8E846C));
    canvas.drawRect(Rect.fromLTWH(0, Bano.banda - 2, w, 3), pincel);

    if (e.ambiente == AmbienteBano.templo) _columnas(canvas, cx);
    if (e.claseMedia >= 5) _calentador(canvas, cx);
    _lavamanos(canvas, cx);
    _repisa(canvas, cx);
    if (e.claseMedia > 0) _claseMedia(canvas, cx);
    final oroPapel = e.lujo('est_papel');
    if (!e.papel && !oroPapel) _periodico(canvas, cx);
    if (e.papel || oroPapel) {
      pincel.color = oroPapel ? const Color(0xFFE0B02A) : const Color(0xFFB9C0C6);
      canvas.drawRect(r(Bano.papel.dx - 13, Bano.papel.dy - 15, Bano.papel.dx + 13, Bano.papel.dy - 12), pincel);
    }
    if (e.planta > 0) _reactor(canvas, cx);
    if (e.tanque > 0) _pipote(canvas, cx, lugar);
    if (e.alfombra || e.lujo('est_alfombra')) _alfombra(canvas, cx);
    _cortina(canvas, size, cx);
    if (e.claseMedia >= 8) _banera(canvas, cx);
    if (e.claseMedia >= 6) _ducha(canvas, cx);
    if (e.arepa > 0 && !lugar.budareDelante) pintarBudare(canvas, Offset(cx + lugar.budare.dx, lugar.budare.dy), e.arepa >= 3);
    if (e.bidet > 0) _bidet(canvas, Offset(cx + lugar.bidet.dx, lugar.bidet.dy), lugar.escalaBidet);
    if (e.cloaca > 0) _sotano(canvas, size, cx);
    _bombillo(canvas, cx);

    // Tinte del ambiente y la penumbra sin bombillo.
    final tinte = switch (e.ambiente) {
      AmbienteBano.volcan => const Color(0xFFFF5A1F).withValues(alpha: .10),
      AmbienteBano.laxante => const Color(0xFF8A4FFF).withValues(alpha: .10),
      AmbienteBano.agujero => const Color(0xFF3A1A6B).withValues(alpha: .16),
      _ => null,
    };
    if (tinte != null) canvas.drawRect(Offset.zero & size, Paint()..color = tinte);
    if (!e.bombillo && !e.lujo('est_lampara')) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x24000000));
  }

  // Pintura de arriba: sucia y pelada, o nueva.
  void _banda(Canvas canvas, Size size, double cx) {
    final e = estado;
    final banda = Rect.fromLTWH(0, 0, size.width, Bano.banda);
    final base = switch (e.ambiente) {
      AmbienteBano.mina => const Color(0xFF6B5E52),
      AmbienteBano.agujero => const Color(0xFF1B1033),
      AmbienteBano.templo => const Color(0xFFE9D9A6),
      _ => e.pintura ? const Color(0xFF6FA89C) : const Color(0xFF9A9A80),
    };
    canvas.drawRect(banda, Paint()..color = base);
    if (e.ambiente == AmbienteBano.mina) {
      final roca = Paint()..color = const Color(0xFF574B40);
      for (var i = 0; i < 14; i++) {
        final x = (i * 53.0 + 17) % size.width, y = 8.0 + (i * 23) % 44;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 26 + (i % 3) * 8, height: 12 + (i % 2) * 6), roca);
      }
    }
    if (e.ambiente == AmbienteBano.agujero) {
      final estrella = Paint()..color = Colors.white;
      for (var i = 0; i < 26; i++) {
        canvas.drawCircle(Offset((i * 37.0 + 11) % size.width, 4.0 + (i * 19) % 52), i % 4 == 0 ? 1.4 : .8, estrella);
      }
    }
    if (!e.pintura && e.ambiente != AmbienteBano.agujero && e.ambiente != AmbienteBano.mina) {
      // Pintura pelada: parches claros con borde.
      final claro = Paint()..color = const Color(0xFFB5B39A);
      final borde = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x667C7A62);
      for (final (x, y, s) in const [(14.0, 20.0, 1.0), (-118.0, 12.0, .8), (150.0, 30.0, .9)]) {
        final p = Path()
          ..moveTo(cx + x, y)
          ..lineTo(cx + x + 14 * s, y - 6 * s)
          ..lineTo(cx + x + 26 * s, y + 2 * s)
          ..lineTo(cx + x + 20 * s, y + 12 * s)
          ..lineTo(cx + x + 6 * s, y + 10 * s)
          ..close();
        canvas.drawPath(p, claro);
        canvas.drawPath(p, borde);
      }
    }
    if (techo && !e.ceramica) pintarMancha(canvas, cx);
  }

  void _azulejos(Canvas canvas, Size size, double cx) {
    final e = estado;
    final zona = Rect.fromLTRB(0, Bano.banda, size.width, Bano.piso);
    final limpia = e.ceramica;
    canvas.drawRect(zona, Paint()..color = limpia ? const Color(0xFFEEF2F4) : const Color(0xFFD6CCAF));
    final junta = Paint()
      ..strokeWidth = 1
      ..color = limpia ? const Color(0xFFC3CDD3) : const Color(0xFF9F947A);
    const a = Bano.azulejo;
    for (var y = Bano.piso; y > Bano.banda; y -= a) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), junta);
    }
    var x0 = cx + a / 2;
    while (x0 > 0) {
      x0 -= a;
    }
    for (var x = x0; x < size.width; x += a) {
      canvas.drawLine(Offset(x, Bano.banda), Offset(x, Bano.piso), junta);
    }
    Rect celda(double dx, double fila) => Rect.fromLTWH(cx + a / 2 + dx * a, Bano.piso - (fila + 1) * a, a, a);
    if (limpia) {
      // Una hilera de azulejos de color, a la altura del asiento.
      final franja = Paint()..color = const Color(0xFF4C7FB0);
      canvas.drawRect(Rect.fromLTRB(0, Bano.piso - 3 * a, size.width, Bano.piso - 3 * a + 6), franja);
      return;
    }
    // Sucia: un azulejo que falta, dos partidos y moho en las juntas de abajo.
    final falta = celda(-5, 1);
    canvas.drawRect(falta, Paint()..color = const Color(0xFF8A8070));
    final punto = Paint()..color = const Color(0xFF6E6558);
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(falta.topLeft + Offset(4 + (i * 7) % 15, 4 + (i * 5) % 14), 1.2, punto);
    }
    final grieta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF5F5646);
    for (final c in [celda(-4, 4), celda(2, 4), celda(5, 2)]) {
      canvas.drawPath(
          Path()
            ..moveTo(c.left + 2, c.top + 3)
            ..lineTo(c.left + 9, c.top + 10)
            ..lineTo(c.left + 7, c.top + 15)
            ..lineTo(c.right - 2, c.bottom - 2),
          grieta);
    }
    canvas.drawRect(Rect.fromLTRB(0, Bano.piso - a, size.width, Bano.piso), Paint()..color = const Color(0x1A3A4A1A));
  }

  // Piso en perspectiva: cuadros que se achican hacia la pared.
  void _piso(Canvas canvas, Size size, double cx) {
    final e = estado;
    const h = Bano.alto; // con cloaca el sótano va debajo
    const fuga = -260.0;
    final marmol = e.lujo('est_piso');
    final a = marmol ? const Color(0xFFF3EFE6) : (e.ceramica ? const Color(0xFFE4E7EA) : const Color(0xFFB4A88F));
    final b = marmol ? const Color(0xFFD9D3C7) : (e.ceramica ? const Color(0xFFB7C0C8) : const Color(0xFF8A7F69));
    final filas = [Bano.piso, 200.0, 210.0, 222.0, 237.0, 256.0, h];
    double xEn(double xb, double y) => cx + (xb - cx) * (y - fuga) / (h - fuga);
    final pincel = Paint()..isAntiAlias = false;
    for (var f = 0; f < filas.length - 1; f++) {
      final y0 = filas[f], y1 = filas[f + 1];
      for (var c = -8; c < 8; c++) {
        final xb0 = cx + c * 46.0, xb1 = xb0 + 46;
        pincel.color = (c + f).isEven ? a : b;
        canvas.drawPath(
            Path()
              ..moveTo(xEn(xb0, y0), y0)
              ..lineTo(xEn(xb1, y0), y0)
              ..lineTo(xEn(xb1, y1), y1)
              ..lineTo(xEn(xb0, y1), y1)
              ..close(),
            pincel);
      }
    }
    if (marmol) {
      // Vetas del mármol.
      final veta = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x55807A70);
      for (var i = 0; i < 9; i++) {
        final x = cx - 200 + i * 52.0, y = 206.0 + (i * 17) % 60;
        canvas.drawPath(
            Path()
              ..moveTo(x, y)
              ..quadraticBezierTo(x + 14, y - 6, x + 26, y + 3)
              ..quadraticBezierTo(x + 34, y + 9, x + 44, y + 4),
            veta);
      }
    }
    // Zócalo.
    canvas.drawRect(Rect.fromLTWH(0, Bano.piso - 1, size.width, 3),
        Paint()..color = marmol ? const Color(0xFFD4A72C) : (e.ceramica ? const Color(0xFF8E9AA4) : const Color(0xFF5E5545)));
    if (!e.ceramica && !marmol) {
      final grieta = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF4E4536);
      canvas.drawPath(
          Path()
            ..moveTo(cx - 170, 270)
            ..lineTo(cx - 150, 262)
            ..lineTo(cx - 146, 252)
            ..lineTo(cx - 128, 246),
          grieta);
      canvas.drawPath(
          Path()
            ..moveTo(cx + 120, 276)
            ..lineTo(cx + 132, 266)
            ..lineTo(cx + 150, 263),
          grieta);
    }
  }

  void _ventana(Canvas canvas, double cx) {
    final e = estado;
    final v = Bano.ventana.shift(Offset(cx, 0));
    final dentro = v.deflate(3);
    final cielo = switch (e.ambiente) {
      AmbienteBano.volcan => const Color(0xFFE2572B),
      AmbienteBano.laxante => const Color(0xFF6E4BC2),
      AmbienteBano.agujero => const Color(0xFF07060F),
      AmbienteBano.mina => const Color(0xFF2A2622),
      _ => const Color(0xFF8EC5E8),
    };
    canvas.drawRect(dentro, Paint()..color = cielo);
    canvas.save();
    canvas.clipRect(dentro);
    switch (e.ambiente) {
      case AmbienteBano.casa || AmbienteBano.publico || AmbienteBano.camion || AmbienteBano.planta || AmbienteBano.cloaca:
        // Nube y el barrio de enfrente.
        final nube = Paint()..color = Colors.white;
        canvas.drawCircle(dentro.topLeft + const Offset(18, 12), 6, nube);
        canvas.drawCircle(dentro.topLeft + const Offset(26, 10), 8, nube);
        canvas.drawCircle(dentro.topLeft + const Offset(34, 13), 5, nube);
        final casa = Paint()..color = const Color(0xFFC98B5E);
        final casa2 = Paint()..color = const Color(0xFFB0725A);
        for (var i = 0; i < 6; i++) {
          final x = dentro.left + i * 14.0 - 4, alto = 10.0 + (i * 7) % 12;
          canvas.drawRect(Rect.fromLTRB(x, dentro.bottom - alto, x + 15, dentro.bottom), i.isEven ? casa : casa2);
        }
        if (e.ambiente == AmbienteBano.planta) {
          final fab = Paint()..color = const Color(0xFF5C6670);
          canvas.drawRect(Rect.fromLTRB(dentro.left + 46, dentro.bottom - 26, dentro.left + 52, dentro.bottom), fab);
          canvas.drawRect(Rect.fromLTRB(dentro.left + 30, dentro.bottom - 16, dentro.left + 66, dentro.bottom), fab);
        }
      case AmbienteBano.granja:
        canvas.drawOval(Rect.fromLTRB(dentro.left - 20, dentro.bottom - 22, dentro.left + 50, dentro.bottom + 20), Paint()..color = const Color(0xFF6DBE5C));
        canvas.drawOval(Rect.fromLTRB(dentro.left + 26, dentro.bottom - 16, dentro.right + 24, dentro.bottom + 24), Paint()..color = const Color(0xFF4FA048));
      case AmbienteBano.mina:
        canvas.drawCircle(dentro.center, 7, Paint()..color = const Color(0x55FFC94A));
        canvas.drawCircle(dentro.center, 3, Paint()..color = const Color(0xFFFFD86B));
      case AmbienteBano.templo:
        canvas.drawRect(dentro, Paint()..color = const Color(0xFFF7C66B));
        canvas.drawCircle(dentro.bottomCenter + const Offset(0, -6), 12, Paint()..color = const Color(0xFFFFE9A8));
      case AmbienteBano.volcan:
        canvas.drawRect(Rect.fromLTRB(dentro.left, dentro.bottom - 8, dentro.right, dentro.bottom), Paint()..color = const Color(0xFFFF9F1C));
      case AmbienteBano.laxante:
        final anillo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFC9B6FF);
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(dentro.center, i * 7.0, anillo);
        }
      case AmbienteBano.agujero:
        final estrella = Paint()..color = Colors.white;
        for (var i = 0; i < 12; i++) {
          canvas.drawCircle(dentro.topLeft + Offset((i * 23.0) % dentro.width, (i * 13.0) % dentro.height), .9, estrella);
        }
    }
    final vitral = e.lujo('est_ventana');
    if (vitral) {
      // Vitral: vidrios de colores con plomo.
      const colores = [Color(0xAAD8343A), Color(0xAA2F6FD0), Color(0xAAF2C230), Color(0xAA3BA55C), Color(0xAA8A4FFF)];
      final cw = dentro.width / 4, ch = dentro.height / 3;
      for (var f = 0; f < 3; f++) {
        for (var c = 0; c < 4; c++) {
          canvas.drawRect(Rect.fromLTWH(dentro.left + c * cw, dentro.top + f * ch, cw, ch), Paint()..color = colores[(f * 2 + c) % colores.length]);
        }
      }
      final plomo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF2B2B2B);
      for (var c = 1; c < 4; c++) {
        canvas.drawLine(Offset(dentro.left + c * cw, dentro.top), Offset(dentro.left + c * cw, dentro.bottom), plomo);
      }
      for (var f = 1; f < 3; f++) {
        canvas.drawLine(Offset(dentro.left, dentro.top + f * ch), Offset(dentro.right, dentro.top + f * ch), plomo);
      }
      canvas.drawCircle(dentro.center, ch * .9, plomo);
    }
    canvas.restore();
    // Marco y rejas (aquí todas las ventanas tienen rejas).
    final marco = e.pintura ? const Color(0xFFF4F4F0) : const Color(0xFF8B5A3C);
    canvas.drawRect(
        v.deflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = marco);
    if (!vitral && e.ambiente != AmbienteBano.volcan && e.ambiente != AmbienteBano.agujero) {
      final reja = Paint()
        ..strokeWidth = 2
        ..color = const Color(0xFF3A3A3A);
      for (var i = 1; i <= 3; i++) {
        final x = v.left + v.width * i / 4;
        canvas.drawLine(Offset(x, v.top + 3), Offset(x, v.bottom - 3), reja);
      }
    }
    // Repisa de la ventana.
    canvas.drawRect(Rect.fromLTRB(v.left - 3, v.bottom, v.right + 3, v.bottom + 3), Paint()..color = marco);
  }

  void _columnas(Canvas canvas, double cx) {
    final oro = Paint()..color = const Color(0xFFD4A72C);
    final raya = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFFA7801A);
    for (final x in const [-196.0, 128.0]) {
      final c = Rect.fromLTRB(cx + x, 0, cx + x + 14, Bano.piso);
      canvas.drawRect(c, oro);
      canvas.drawLine(Offset(c.left + 5, 8), Offset(c.left + 5, Bano.piso - 8), raya);
      canvas.drawLine(Offset(c.left + 9, 8), Offset(c.left + 9, Bano.piso - 8), raya);
      canvas.drawRect(Rect.fromLTRB(c.left - 3, 0, c.right + 3, 6), oro);
      canvas.drawRect(Rect.fromLTRB(c.left - 3, Bano.piso - 6, c.right + 3, Bano.piso), oro);
    }
  }

  void _lavamanos(Canvas canvas, double cx) {
    final e = estado;
    final sx = cx + Bano.lavamanos;
    // Espejo.
    final espejo = Rect.fromLTRB(sx - 26, 26, sx + 26, 90);
    canvas.drawRect(espejo, Paint()..color = const Color(0xFFCFE3EA));
    canvas.drawPath(
        Path()
          ..moveTo(espejo.left + 10, espejo.bottom)
          ..lineTo(espejo.left + 30, espejo.top)
          ..lineTo(espejo.left + 40, espejo.top)
          ..lineTo(espejo.left + 20, espejo.bottom)
          ..close(),
        Paint()..color = const Color(0x66FFFFFF));
    canvas.drawRect(
        espejo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = e.iman ? const Color(0xFFD4A72C) : const Color(0xFF8D949A));
    if (e.lujo('est_espejo')) {
      // Espejo de camerino: bombillos alrededor.
      final luz = Paint()..color = const Color(0xFFFFF3C4);
      final halo = Paint()..color = const Color(0x40FFE9A8);
      for (var i = 0; i < 4; i++) {
        final x = espejo.left + 6 + i * (espejo.width - 12) / 3;
        canvas.drawCircle(Offset(x, espejo.top - 3), 6, halo);
        canvas.drawCircle(Offset(x, espejo.top - 3), 3, luz);
      }
      for (var i = 0; i < 3; i++) {
        final y = espejo.top + 12 + i * 20.0;
        for (final x in [espejo.left - 3, espejo.right + 3]) {
          canvas.drawCircle(Offset(x, y), 6, halo);
          canvas.drawCircle(Offset(x, y), 3, luz);
        }
      }
    }
    // Pedestal y poceta del lavamanos.
    final marmol = e.lujo('est_lavamanos');
    final loza = Paint()..color = marmol ? const Color(0xFFF4F0E8) : const Color(0xFFF2F2EE);
    final linea = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9C9A92);
    final pie = Path()
      ..moveTo(sx - 7, 130)
      ..lineTo(sx + 7, 130)
      ..lineTo(sx + 11, 202)
      ..lineTo(sx - 11, 202)
      ..close();
    canvas.drawPath(pie, loza);
    canvas.drawPath(pie, linea);
    final taza = Path()
      ..moveTo(sx - 30, 114)
      ..lineTo(sx + 30, 114)
      ..quadraticBezierTo(sx + 28, 134, sx, 136)
      ..quadraticBezierTo(sx - 28, 134, sx - 30, 114)
      ..close();
    canvas.drawPath(taza, loza);
    canvas.drawPath(taza, linea);
    canvas.drawRect(Rect.fromLTRB(sx - 32, 112, sx + 32, 117), loza);
    canvas.drawRect(Rect.fromLTRB(sx - 32, 112, sx + 32, 117), linea);
    if (marmol) {
      // Vetas grises del mármol.
      final veta = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x998A857C);
      canvas.drawPath(
          Path()
            ..moveTo(sx - 24, 118)
            ..quadraticBezierTo(sx - 10, 126, sx + 2, 121)
            ..quadraticBezierTo(sx + 12, 117, sx + 20, 127),
          veta);
      canvas.drawPath(
          Path()
            ..moveTo(sx - 3, 140)
            ..quadraticBezierTo(sx + 4, 160, sx - 2, 176)
            ..quadraticBezierTo(sx - 6, 186, sx + 3, 198),
          veta);
      canvas.drawLine(Offset(sx - 30, 113.5), Offset(sx + 30, 115.5), veta);
    }
    // Grifo: oxidado, cromado o dorado.
    final metal = Paint()
      ..color = marmol ? const Color(0xFFE0B02A) : switch (e.valvula) {
        2 => const Color(0xFFE0B02A),
        1 => const Color(0xFFC9CED3),
        _ => const Color(0xFF8C7B6A),
      };
    canvas.drawRect(Rect.fromLTRB(sx - 3, 100, sx + 3, 112), metal);
    canvas.drawRect(Rect.fromLTRB(sx - 3, 100, sx + 11, 105), metal);
    canvas.drawRect(Rect.fromLTRB(sx - 6, 97, sx + 6, 100), metal);
    if (e.valvula == 0 && !marmol) {
      // Óxido y la mancha de la gota en la loza.
      canvas.drawCircle(Offset(sx + 9, 116), 3, Paint()..color = const Color(0x66A0702A));
    }
  }

  // Bidet de piso: la taza de porcelana baja, con su pie, el grifo atrás y las dos llaves (fría y caliente). [b] es
  // donde toca el piso y [k] la escala (más grande con piso de más).
  void _bidet(Canvas canvas, Offset b, double k) {
    Offset p(double x, double y) => Offset(b.dx + x * k, b.dy + y * k);
    Path poli(List<Offset> l) => Path()..addPolygon(l, true);
    final borde = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF9AA3AA);
    final cromo = Paint()..color = const Color(0xFFC9D1D8);
    canvas.drawOval(Rect.fromCenter(center: p(0, 0), width: 50 * k, height: 8 * k), Paint()..color = const Color(0x33000000));
    // Pie.
    final pie = poli([p(-11, -16), p(11, -16), p(14, 0), p(-14, 0)]);
    canvas.drawPath(pie, Paint()..color = const Color(0xFFE3E5E7));
    canvas.drawPath(poli([p(5, -16), p(11, -16), p(14, 0), p(7, 0)]), Paint()..color = const Color(0xFFCDD1D5));
    canvas.drawPath(pie, borde);
    // Taza: se angosta hacia el pie.
    final taza = Path()
      ..moveTo(p(-23, -40).dx, p(-23, -40).dy)
      ..cubicTo(p(-23, -24).dx, p(-23, -24).dy, p(-14, -14).dx, p(-14, -14).dy, p(-11, -12).dx, p(-11, -12).dy)
      ..lineTo(p(11, -12).dx, p(11, -12).dy)
      ..cubicTo(p(14, -14).dx, p(14, -14).dy, p(23, -24).dx, p(23, -24).dy, p(23, -40).dx, p(23, -40).dy)
      ..close();
    canvas.drawPath(taza, Paint()..color = const Color(0xFFF2F3F1));
    final lado = Path()
      ..moveTo(p(10, -40).dx, p(10, -40).dy)
      ..cubicTo(p(10, -26).dx, p(10, -26).dy, p(8, -15).dx, p(8, -15).dy, p(6, -12).dx, p(6, -12).dy)
      ..lineTo(p(11, -12).dx, p(11, -12).dy)
      ..cubicTo(p(14, -14).dx, p(14, -14).dy, p(23, -24).dx, p(23, -24).dy, p(23, -40).dx, p(23, -40).dy)
      ..close();
    canvas.drawPath(lado, Paint()..color = const Color(0xFFDADDE0));
    canvas.drawPath(taza, borde);
    // Grifo atrás del borde, con su caño hacia adelante, y las llaves a los lados.
    canvas.drawRect(Rect.fromLTRB(p(-2.5, -54).dx, p(-2.5, -54).dy, p(2.5, -44).dx, p(2.5, -44).dy), cromo);
    canvas.drawRect(Rect.fromLTRB(p(-1.5, -55).dx, p(-1.5, -55).dy, p(1.5, -48).dx, p(1.5, -48).dy), Paint()..color = const Color(0xFF9AA3AA));
    for (final (x, punto) in const [(-11.0, Color(0xFFD9443A)), (11.0, Color(0xFF3A7BD9))]) {
      canvas.drawCircle(p(x, -47), 3.2 * k, cromo);
      canvas.drawCircle(p(x, -47), 1.2 * k, Paint()..color = punto);
    }
    // Borde de arriba y el hueco con un poquito de agua.
    final borde0 = Rect.fromCenter(center: p(0, -40), width: 46 * k, height: 12 * k);
    canvas.drawOval(borde0, Paint()..color = const Color(0xFFFAFAF8));
    canvas.drawOval(borde0, borde);
    canvas.drawOval(Rect.fromCenter(center: p(0, -40), width: 36 * k, height: 7 * k), Paint()..color = const Color(0xFFD5DCE1));
    canvas.drawOval(Rect.fromCenter(center: p(0, -39.5), width: 24 * k, height: 4 * k), Paint()..color = const Color(0xFFA9CCDD));
    // La boquilla del chorro en el medio.
    canvas.drawCircle(p(0, -41), 1.6 * k, Paint()..color = const Color(0xFF7F8A93));
  }

  void _repisa(Canvas canvas, double cx) {
    final r = Bano.repisa.shift(Offset(cx, 0));
    if (estado.lujo('est_repisa')) {
      // Vidrio con soportes cromados.
      canvas.drawRect(r.inflate(1), Paint()..color = const Color(0x8890D0E0));
      canvas.drawLine(r.topLeft, r.topRight, Paint()..color = const Color(0xFFE6F7FB));
      final cromo = Paint()..color = const Color(0xFFC9D1D8);
      canvas.drawRect(Rect.fromLTRB(r.left + 6, r.bottom + 1, r.left + 9, r.bottom + 8), cromo);
      canvas.drawRect(Rect.fromLTRB(r.right - 9, r.bottom + 1, r.right - 6, r.bottom + 8), cromo);
      return;
    }
    final madera = Paint()..color = const Color(0xFF8A6A48);
    canvas.drawRect(r, madera);
    canvas.drawRect(Rect.fromLTRB(r.left + 6, r.bottom, r.left + 9, r.bottom + 8), madera);
    canvas.drawRect(Rect.fromLTRB(r.right - 9, r.bottom, r.right - 6, r.bottom + 8), madera);
  }

  // Sin porta-rollo: periódico ensartado en un clavo.
  void _periodico(Canvas canvas, double cx) {
    final c = Offset(cx + Bano.papel.dx, Bano.papel.dy);
    canvas.save();
    canvas.translate(c.dx, c.dy - 14);
    canvas.rotate(.12);
    final hoja = Rect.fromLTWH(-11, 0, 22, 28);
    canvas.drawRect(hoja.shift(const Offset(3, 2)), Paint()..color = const Color(0xFFC8C4B8));
    canvas.drawRect(hoja, Paint()..color = const Color(0xFFE2DED2));
    final letra = Paint()
      ..strokeWidth = 1.4
      ..color = const Color(0xFF8F8B80);
    canvas.drawRect(Rect.fromLTWH(-8, 4, 16, 4), Paint()..color = const Color(0xFF6E6A60));
    for (var y = 11.0; y < 26; y += 3.5) {
      canvas.drawLine(Offset(-8, y), Offset(y > 20 ? 2 : 8, y), letra);
    }
    canvas.restore();
    canvas.drawCircle(c + const Offset(0, -12), 2, Paint()..color = const Color(0xFF4A4A4A));
  }

  void _pipote(Canvas canvas, double cx, LugaresBano l) {
    final grande = estado.tanque == 2;
    final c = Offset(cx + l.tobo.dx + (grande ? 4 : 0), l.tobo.dy);
    final ancho = grande ? 42.0 : 32.0, alto = grande ? 58.0 : 44.0;
    final cuerpo = Rect.fromLTRB(c.dx - ancho / 2, c.dy + 16 - alto, c.dx + ancho / 2, c.dy + 16);
    final oro = estado.lujo('est_tobo');
    canvas.drawRect(cuerpo, Paint()..color = oro ? const Color(0xFFE0B02A) : const Color(0xFF2F6FB5));
    final aro = Paint()..color = oro ? const Color(0xFFB8861B) : const Color(0xFF24588F);
    for (final f in const [.12, .5, .88]) {
      canvas.drawRect(Rect.fromLTWH(cuerpo.left, cuerpo.top + cuerpo.height * f - 2, cuerpo.width, 4), aro);
    }
    canvas.drawRect(Rect.fromLTWH(cuerpo.left + 5, cuerpo.top + 4, 4, cuerpo.height - 8), Paint()..color = const Color(0x44FFFFFF));
    canvas.drawOval(Rect.fromLTWH(cuerpo.left, cuerpo.top - 4, cuerpo.width, 8), Paint()..color = oro ? const Color(0xFFF2CB55) : const Color(0xFF3B80C9));
    if (grande) {
      // Llavecita abajo.
      canvas.drawRect(Rect.fromLTWH(cuerpo.left - 6, cuerpo.bottom - 14, 7, 4), Paint()..color = const Color(0xFFC9CED3));
    }
  }

  // Alfombra en U al pie de la poceta.
  void _alfombra(Canvas canvas, double cx) {
    const centro = -4.0;
    final exterior = RRect.fromRectAndCorners(Rect.fromLTRB(cx + centro - 56, 200, cx + centro + 56, 244),
        bottomLeft: const Radius.circular(22), bottomRight: const Radius.circular(22));
    final hueco = Path()..addOval(Rect.fromCenter(center: Offset(cx + centro, 200), width: 54, height: 22));
    final forma = Path.combine(PathOperation.difference, Path()..addRRect(exterior), hueco);
    final roja = estado.lujo('est_alfombra');
    canvas.drawPath(forma, Paint()..color = roja ? const Color(0xFFB3202E) : const Color(0xFF5B8F7B));
    canvas.drawPath(
        forma,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = roja ? const Color(0xFFE0B02A) : const Color(0xFF8CC0AA));
  }

  void _cortina(Canvas canvas, Size size, double cx) {
    final e = estado;
    final izq = cx + 150;
    if (izq > size.width - 6) return;
    // Tubo.
    canvas.drawRect(Rect.fromLTRB(izq - 4, 8, size.width, 11), Paint()..color = const Color(0xFF9AA1A7));
    final tela = Rect.fromLTRB(izq, 11, size.width, Bano.piso + 6);
    if (e.lujo('est_cortina')) {
      // Terciopelo rojo recogido con cordón dorado.
      final p = Path()
        ..moveTo(tela.left, tela.top)
        ..lineTo(tela.right, tela.top)
        ..lineTo(tela.right, tela.bottom)
        ..lineTo(tela.left + 22, tela.bottom)
        ..quadraticBezierTo(tela.left + 6, 150, tela.left + 16, 118)
        ..quadraticBezierTo(tela.left + 4, 70, tela.left, tela.top)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xFF8E1B2A));
      final pliegue = Paint()
        ..strokeWidth = 2
        ..color = const Color(0x55300008);
      for (var x = tela.left + 14; x < tela.right; x += 10) {
        canvas.drawLine(Offset(x, tela.top + 2), Offset(x + 4, tela.bottom - 2), pliegue);
      }
      final oro = Paint()..color = const Color(0xFFE0B02A);
      canvas.drawRect(Rect.fromLTRB(tela.left + 10, 114, tela.right, 119), oro);
      canvas.drawRect(Rect.fromLTRB(tela.left + 12, 119, tela.left + 16, 136), oro);
      canvas.drawRect(Rect.fromLTRB(tela.left + 9, 134, tela.left + 19, 142), oro); // borla
      canvas.drawRect(Rect.fromLTRB(tela.left, 8, tela.right, 11), oro);
      return;
    }
    if (e.cortina) {
      canvas.drawRect(tela, Paint()..color = const Color(0xFFF6E3EA));
      final petalo = Paint()..color = const Color(0xFFE77FA5);
      final centro = Paint()..color = const Color(0xFFF7C948);
      for (var y = tela.top + 16; y < tela.bottom - 8; y += 30) {
        for (var x = tela.left + ((y ~/ 30).isEven ? 10 : 22); x < tela.right - 4; x += 26) {
          for (var k = 0; k < 5; k++) {
            final ang = k * 2 * pi / 5;
            canvas.drawCircle(Offset(x + cos(ang) * 4, y + sin(ang) * 4), 3, petalo);
          }
          canvas.drawCircle(Offset(x, y), 2, centro);
        }
      }
    } else {
      // Plástico viejo, rajado abajo y con un gancho suelto.
      final p = Path()
        ..moveTo(tela.left, tela.top + 6)
        ..lineTo(tela.right, tela.top)
        ..lineTo(tela.right, tela.bottom)
        ..lineTo(tela.left + 20, tela.bottom)
        ..lineTo(tela.left + 12, tela.bottom - 30)
        ..lineTo(tela.left + 6, tela.bottom - 4)
        ..lineTo(tela.left, tela.bottom - 4)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xCCDDE5E2));
      canvas.drawCircle(Offset(tela.left + 3, tela.top + 2), 2.5, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF6E767C));
    }
    final pliegue = Paint()
      ..strokeWidth = 1
      ..color = e.cortina ? const Color(0x33A0506E) : const Color(0x33506068);
    for (var x = tela.left + 9; x < tela.right; x += 12) {
      canvas.drawLine(Offset(x, tela.top + 4), Offset(x, tela.bottom - 6), pliegue);
    }
  }

  static void pintarBudare(Canvas canvas, Offset c, bool grande) {
    final rx = grande ? 34.0 : 27.0;
    // Hornilla con brasas y el budare encima.
    canvas.drawRect(Rect.fromCenter(center: c + const Offset(0, 9), width: rx * 1.4, height: 8), Paint()..color = const Color(0xFF3E3A36));
    final brasa = Paint()..color = const Color(0xFFE2572B);
    for (var i = -2; i <= 2; i++) {
      canvas.drawCircle(c + Offset(i * rx * .25, 9), 1.6, brasa);
    }
    canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: 12), Paint()..color = const Color(0xFF1E1C1A));
    canvas.drawOval(Rect.fromCenter(center: c + const Offset(0, -1), width: rx * 1.7, height: 8), Paint()..color = const Color(0xFF34302C));
    canvas.drawRect(Rect.fromLTWH(c.dx + rx - 2, c.dy - 2, 14, 4), Paint()..color = const Color(0xFF1E1C1A));
  }

  // Lámpara de araña: cadena, brazos dorados, velitas y cristales.
  void _arana(Canvas canvas, Offset b) {
    final oro = Paint()..color = const Color(0xFFE0B02A);
    final brazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFC8961F);
    if (!estirar) canvas.drawCircle(b + const Offset(0, 4), 60, Paint()..color = const Color(0x1CFFE3A0));
    canvas.drawLine(Offset(b.dx, 0), b + const Offset(0, -6), brazo);
    canvas.drawRect(Rect.fromCenter(center: b + const Offset(0, -2), width: 8, height: 10), oro);
    for (final d in const [-26.0, -13.0, 13.0, 26.0]) {
      final punta = b + Offset(d, 0);
      canvas.drawPath(
          Path()
            ..moveTo(b.dx, b.dy + 2)
            ..quadraticBezierTo(b.dx + d * .5, b.dy + 14, punta.dx, punta.dy + 2),
          brazo);
      canvas.drawRect(Rect.fromLTRB(punta.dx - 2, punta.dy - 8, punta.dx + 2, punta.dy + 2), Paint()..color = const Color(0xFFF6F1E4));
      canvas.drawCircle(punta + const Offset(0, -11), 3, Paint()..color = const Color(0xFFFFE08A));
      canvas.drawRect(Rect.fromLTRB(punta.dx - 1.5, punta.dy + 4, punta.dx + 1.5, punta.dy + 12), Paint()..color = const Color(0xCCD8F0FF));
    }
    canvas.drawRect(Rect.fromLTRB(b.dx - 2, b.dy + 8, b.dx + 2, b.dy + 20), Paint()..color = const Color(0xCCD8F0FF));
  }

  // Calentador de agua en la pared, con su tubo.
  void _calentador(Canvas canvas, double cx) {
    final c = Rect.fromLTRB(cx - 64, 6, cx - 44, 52);
    canvas.drawRect(c, Paint()..color = const Color(0xFFF1F1EC));
    canvas.drawRect(
        c,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF9C9A92));
    canvas.drawRect(Rect.fromLTRB(c.left, c.top + 6, c.right, c.top + 8), Paint()..color = const Color(0xFFD9D7CE));
    canvas.drawRect(Rect.fromLTRB(c.left + 7, c.bottom - 12, c.left + 13, c.bottom - 8), Paint()..color = const Color(0xFFE53935));
    canvas.drawRect(Rect.fromLTRB(c.center.dx - 2, c.bottom, c.center.dx + 2, 68), Paint()..color = const Color(0xFFB87333));
  }

  // Lo del baño de clase media: toallero, toallas, mueble, jabones.
  void _claseMedia(Canvas canvas, double cx) {
    final c = estado.claseMedia;
    final sx = cx + Bano.lavamanos;
    if (c >= 3) {
      // Mueble de madera bajo el lavamanos (tapa el pie).
      final m = Rect.fromLTRB(sx - 28, 134, sx + 28, 200);
      canvas.drawRect(m, Paint()..color = const Color(0xFF9A6B43));
      final borde = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF6E4A2C);
      canvas.drawRect(m, borde);
      canvas.drawLine(Offset(m.center.dx, m.top + 6), Offset(m.center.dx, m.bottom - 4), borde);
      canvas.drawRect(Rect.fromLTRB(m.left + 4, m.top + 6, m.right - 4, m.bottom - 4), borde);
      final pomo = Paint()..color = const Color(0xFFE0B02A);
      canvas.drawRect(Rect.fromCenter(center: Offset(m.center.dx - 5, m.center.dy), width: 3, height: 8), pomo);
      canvas.drawRect(Rect.fromCenter(center: Offset(m.center.dx + 5, m.center.dy), width: 3, height: 8), pomo);
    }
    // Toallero con toalla: torcida al principio, dobladitas con la mejora.
    final barra = Paint()..color = const Color(0xFFC9D1D8);
    canvas.drawRect(Rect.fromLTRB(cx - 104, 95, cx - 66, 98), barra);
    canvas.drawRect(Rect.fromLTRB(cx - 106, 92, cx - 103, 100), barra);
    canvas.drawRect(Rect.fromLTRB(cx - 67, 92, cx - 64, 100), barra);
    if (c >= 2) {
      for (final (i, color) in const [(0, Color(0xFF7FB6D9)), (1, Color(0xFFF2F2EE))].indexed.map((x) => x.$2)) {
        final l = cx - 101 + i * 17.0;
        canvas.drawRect(Rect.fromLTRB(l, 98, l + 16, 128), Paint()..color = color);
        canvas.drawRect(Rect.fromLTRB(l, 120, l + 16, 123), Paint()..color = const Color(0xFFE0B02A));
      }
    } else {
      canvas.save();
      canvas.translate(cx - 86, 97);
      canvas.rotate(.12);
      canvas.drawRect(const Rect.fromLTRB(-13, 0, 11, 30), Paint()..color = const Color(0xFF7FB6D9));
      canvas.drawRect(const Rect.fromLTRB(-13, 22, 11, 25), Paint()..color = const Color(0xFF5E93B8));
      canvas.restore();
    }
    if (c >= 7) {
      // Jabones de visita en el borde (no se usan).
      canvas.drawRect(Rect.fromLTRB(sx - 28, 106, sx - 19, 112), Paint()..color = const Color(0xFFF2A7C3));
      canvas.drawRect(Rect.fromLTRB(sx - 18, 107, sx - 11, 112), Paint()..color = const Color(0xFFB5E3B0));
      canvas.drawRect(Rect.fromLTRB(sx + 16, 106, sx + 26, 112), Paint()..color = const Color(0xFFFFE08A));
    }
  }

  // Ducha de lluvia: regadera cuadrada grande con gotas quietas.
  void _ducha(Canvas canvas, double cx) {
    final d = Offset(cx + Bano.ducha.dx, Bano.ducha.dy);
    final cromo = Paint()..color = const Color(0xFFC9D1D8);
    canvas.drawRect(Rect.fromLTRB(d.dx - 2, 0, d.dx + 2, d.dy - 3), cromo);
    canvas.drawRect(Rect.fromLTRB(d.dx - 18, d.dy - 4, d.dx + 18, d.dy + 3), cromo);
    canvas.drawRect(Rect.fromLTRB(d.dx - 18, d.dy + 2, d.dx + 18, d.dy + 3), Paint()..color = const Color(0xFF7F8A93));
    final gota = Paint()
      ..strokeWidth = 1.5
      ..color = const Color(0x8879B8E8);
    for (var i = 0; i < 8; i++) {
      final x = d.dx - 15 + i * 4.3, y = d.dy + 10 + (i * 13) % 30;
      canvas.drawLine(Offset(x, y), Offset(x, y + 7), gota);
    }
  }

  // Bañera (jacuzzi) y, con la última mejora, borde y patas de oro.
  void _banera(Canvas canvas, double cx) {
    final b = Bano.banera.shift(Offset(cx, 0));
    final oro = estado.claseMedia >= 9;
    final dorado = Paint()..color = const Color(0xFFE0B02A);
    if (oro) {
      for (final x in [b.left + 8, b.right - 16]) {
        canvas.drawRect(Rect.fromLTRB(x, b.bottom, x + 8, b.bottom + 7), dorado);
        canvas.drawRect(Rect.fromLTRB(x - 2, b.bottom + 6, x + 10, b.bottom + 9), dorado);
      }
    }
    canvas.drawRect(b, Paint()..color = const Color(0xFFF4F4F0));
    canvas.drawRect(Rect.fromLTRB(b.left + 6, b.top + 3, b.right - 4, b.top + 9), Paint()..color = const Color(0xFF8EC9E8));
    canvas.drawRect(Rect.fromLTRB(b.left - 2, b.top - 3, b.right + 2, b.top + 3), oro ? dorado : Paint()..color = const Color(0xFFE2E2DC));
    canvas.drawRect(
        b,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF9C9A92));
  }

  // Planta de tratamiento: tubo desde el tanque y el reactor a la derecha.
  void _reactor(Canvas canvas, double cx) {
    final p = estado.planta;
    Rect r(double l, double t, double ri, double b) => Rect.fromLTRB(cx + l, t, cx + ri, b);
    Offset o(Offset x) => Offset(cx + x.dx, x.dy);
    final tubo = Path()..moveTo(o(Bano.tuboPlanta.first).dx, Bano.tuboPlanta.first.dy);
    for (final x in Bano.tuboPlanta.skip(1)) {
      tubo.lineTo(o(x).dx, x.dy);
    }
    canvas.drawPath(
        tubo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = const Color(0xFF5E676E));
    canvas.drawPath(
        tubo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = const Color(0xFF9AA4AB));
    final union = Paint()..color = const Color(0xFF5E676E);
    for (final x in Bano.tuboPlanta.skip(1).take(Bano.tuboPlanta.length - 2)) {
      canvas.drawRect(Rect.fromCenter(center: o(x), width: 12, height: 12), union);
    }
    final linea = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF3E454B);
    if (p >= 4) {
      // Chimenea a rayas.
      final ch = r(120, 50, 130, 106);
      canvas.drawRect(ch, Paint()..color = const Color(0xFFF2F2EE));
      for (var y = ch.top; y < ch.bottom; y += 12) {
        canvas.drawRect(Rect.fromLTRB(ch.left, y, ch.right, y + 6), Paint()..color = const Color(0xFFD8343A));
      }
      canvas.drawRect(ch, linea);
    }
    canvas.drawRect(r(84, 196, 140, 208), Paint()..color = const Color(0xFF4A5056));
    final cuerpo = r(92, 112, 132, 196);
    canvas.drawRect(cuerpo, Paint()..color = const Color(0xFFB8C2C9));
    canvas.drawRect(Rect.fromLTRB(cuerpo.left + 4, cuerpo.top + 4, cuerpo.left + 8, cuerpo.bottom - 4), Paint()..color = const Color(0x55FFFFFF));
    canvas.drawRect(cuerpo, linea);
    final domo = r(92, 100, 132, 124);
    canvas.drawOval(domo, Paint()..color = const Color(0xFFCBD4DA));
    canvas.drawOval(domo, linea);
    // Ventana del núcleo (el brillo que late lo pone Poceta).
    final nucleo = r(102, 132, 122, 166);
    canvas.drawRect(nucleo, Paint()..color = p >= 6 ? const Color(0xFF5BE35B) : const Color(0xFFFFB347));
    canvas.drawRect(nucleo.deflate(4), Paint()..color = p >= 6 ? const Color(0xFFC8FFB0) : const Color(0xFFFFE3A0));
    canvas.drawRect(nucleo, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF3E454B));
    final anillo = Paint()..color = const Color(0xFF59626A);
    final franja = Paint()..color = const Color(0xFFFFD60A);
    for (final (n, y) in const [(1, 124.0), (2, 172.0), (5, 184.0)]) {
      if (p < n) continue;
      canvas.drawRect(r(88, y, 136, y + 6), anillo);
      canvas.drawRect(r(88, y + 2, 136, y + 3), franja);
    }
    if (p >= 3) {
      final roja = Paint()..color = const Color(0xFFE53935);
      canvas.drawRect(Rect.fromCenter(center: o(Bano.lucesReactor[0]), width: 5, height: 5), roja);
      canvas.drawRect(Rect.fromCenter(center: o(Bano.lucesReactor[1]), width: 5, height: 5), roja);
    }
    if (p >= 7) {
      // Placa ISO 9001 en el pedestal.
      canvas.drawRect(r(96, 198, 128, 206), Paint()..color = const Color(0xFFF2F2EE));
      final t = TextPainter(
          text: const TextSpan(text: 'ISO 9001', style: TextStyle(fontSize: 6, color: Color(0xFF1B3A6B), fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      t.paint(canvas, Offset(cx + 112 - t.width / 2, 202 - t.height / 2));
    }
    if (p >= 9) {
      canvas.drawOval(
          Bano.orbita.shift(Offset(cx, 0)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0x99FFD60A));
    }
  }

  // Sótano con la cloaca: ladrillos, canal de aguas negras y el tubo que baja.
  void _sotano(Canvas canvas, Size size, double cx) {
    final c = estado.cloaca;
    const top = Bano.alto, bot = Bano.alto + Bano.sotano;
    canvas.drawRect(Rect.fromLTRB(0, top, size.width, bot), Paint()..color = const Color(0xFF1A1714));
    final junta = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF2E2620);
    for (var f = 0; f < 4; f++) {
      final y = top + 4 + f * 10.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), junta);
      for (var x = (f.isEven ? 0.0 : 14.0); x < size.width; x += 28) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 10), junta);
      }
    }
    final canal = Rect.fromLTRB(0, top + 22, size.width, top + 36);
    canvas.drawRect(canal, Paint()..color = c >= 4 ? const Color(0xFF3F7A2A) : const Color(0xFF3B3A26));
    canvas.drawRect(Rect.fromLTRB(0, canal.top, size.width, canal.top + 2), Paint()..color = c >= 4 ? const Color(0xFF8CFF5A) : const Color(0xFF5C5A3A));
    if (c >= 4) canvas.drawRect(Rect.fromLTRB(0, canal.top - 8, size.width, canal.bottom), Paint()..color = const Color(0x2266FF44));
    canvas.drawRect(Rect.fromLTRB(0, top, size.width, top + 4), Paint()..color = const Color(0xFF6B6660));
    if (c >= 3) {
      // Rejilla de la alcantarilla en el piso.
      final rj = Rect.fromLTRB(cx - 172, top - 10, cx - 140, top);
      canvas.drawRect(rj, Paint()..color = const Color(0xFF3A3A3A));
      for (var x = rj.left + 4; x < rj.right; x += 6) {
        canvas.drawRect(Rect.fromLTRB(x, rj.top + 2, x + 2, rj.bottom - 1), Paint()..color = const Color(0xFF111111));
      }
    }
    final t = Bano.tuboCloaca(estado);
    final a = Offset(cx + t.first.dx, t.first.dy), b = Offset(cx + t.last.dx, t.last.dy);
    canvas.drawLine(a, b, Paint()
      ..strokeWidth = 10
      ..color = const Color(0xFF4A5056));
    canvas.drawLine(a, b, Paint()
      ..strokeWidth = 7
      ..color = const Color(0xFF7D868D));
    canvas.drawRect(Rect.fromCenter(center: Offset(a.dx, top + 2), width: 14, height: 6), Paint()..color = const Color(0xFF4A5056));
  }

  void _bombillo(Canvas canvas, double cx) {
    final b = Offset(cx + Bano.bombillo.dx, Bano.bombillo.dy);
    final cable = Paint()
      ..strokeWidth = 1.5
      ..color = const Color(0xFF2A2A2A);
    if (estado.lujo('est_lampara')) {
      _arana(canvas, b);
      return;
    }
    if (!estado.bombillo) {
      // Pelado, colgando del cable.
      canvas.drawLine(Offset(b.dx, 0), b + const Offset(0, -12), cable);
      return;
    }
    // Lámpara con su luz cálida.
    if (!estirar) {
      canvas.drawCircle(b + const Offset(0, 16), 70, Paint()..color = const Color(0x1AFFD27A));
      canvas.drawCircle(b + const Offset(0, 10), 34, Paint()..color = const Color(0x1FFFD27A));
    }
    canvas.drawLine(Offset(b.dx, 0), b + const Offset(0, -12), cable);
    final pantalla = Path()
      ..moveTo(b.dx - 9, b.dy - 12)
      ..lineTo(b.dx + 9, b.dy - 12)
      ..lineTo(b.dx + 19, b.dy + 4)
      ..lineTo(b.dx - 19, b.dy + 4)
      ..close();
    canvas.drawOval(Rect.fromCenter(center: b + const Offset(0, 5), width: 14, height: 8), Paint()..color = const Color(0xFFFFE9A8));
    canvas.drawPath(pantalla, Paint()..color = const Color(0xFFF2E6C9));
    canvas.drawPath(
        pantalla,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFB59E6E));
  }
}

/// La tela peluda del forro, dibujada ENCIMA de la poceta (la imagen no se toca). [lado] es el de toilet.png.
class PintorForro extends CustomPainter {
  const PintorForro();

  @override
  bool shouldRepaint(PintorForro old) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width;
    final tela = Paint()..color = const Color(0xFFF3A6C4);
    final pelo = Paint()..color = const Color(0xFFE584AC);
    // Funda del asiento (vista de lado) y de la tapa del tanque.
    for (final r in [Rect.fromLTRB(l * .08, l * .435, l * .63, l * .525), Rect.fromLTRB(l * .615, l * .045, l * .89, l * .12)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)), tela);
      for (var x = r.left + 3; x < r.right - 2; x += 4.5) {
        canvas.drawCircle(Offset(x, r.top + 1), 1.8, tela);
        canvas.drawCircle(Offset(x + 2, r.bottom - 1), 1.8, tela);
        canvas.drawCircle(Offset(x + 1, r.center.dy + ((x ~/ 4.5).isEven ? -1.5 : 1.5)), 1, pelo);
      }
    }
  }
}

/// Las mejoras del bidet sobre la poceta principal, en el mismo cuadro que toilet.png (vista de lado: la taza a la
/// izquierda, el tanque a la derecha). La tapa acolchada no se pinta si hay forro: el forro va encima.
class PintorMejorasPoceta extends CustomPainter {
  const PintorMejorasPoceta(this.estado);

  final EstadoBano estado;

  @override
  bool shouldRepaint(PintorMejorasPoceta old) => old.estado != estado;

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width;
    final e = estado;
    Offset p(double x, double y) => Offset(l * x, l * y);
    if (e.marmol && !e.pocetaOro) {
      final veta = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x667A7F8C);
      for (final v in const [
        [.20, .60, .30, .66, .27, .74, .38, .80],
        [.42, .58, .47, .65, .55, .66, .57, .74],
        [.68, .16, .72, .24, .70, .30, .76, .38],
        [.80, .20, .78, .28, .83, .34, .81, .42],
      ]) {
        canvas.drawPath(
            Path()
              ..moveTo(l * v[0], l * v[1])
              ..cubicTo(l * v[2], l * v[3], l * v[4], l * v[5], l * v[6], l * v[7]),
            veta);
      }
    }
    if (e.tapaAcolchada && !e.forro) {
      final r = Rect.fromLTRB(l * .08, l * .44, l * .63, l * .52);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)), Paint()..color = const Color(0xFFB8D4EC));
      final costura = Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFF86A9C9);
      for (var x = r.left + 8; x < r.right - 6; x += 7) {
        canvas.drawLine(Offset(x, r.center.dy), Offset(x + 3, r.center.dy), costura);
      }
    }
    if (e.asientoCaliente) {
      final calor = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xCCE8552E);
      for (final x in const [.18, .32, .46]) {
        canvas.drawPath(
            Path()
              ..moveTo(l * x, l * .42)
              ..cubicTo(l * (x - .03), l * .39, l * (x + .03), l * .36, l * x, l * .32),
            calor);
      }
    }
    if (e.descargaDoble) {
      for (final x in const [.70, .80]) {
        canvas.drawCircle(p(x, .045), l * .032, Paint()..color = const Color(0xFF8E979F));
        canvas.drawCircle(p(x, .04), l * .024, Paint()..color = const Color(0xFFDCE2E7));
      }
    }
    if (e.wifi) {
      final ondas = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF3B82C4);
      final c = p(.755, .30);
      canvas.drawCircle(c, 1.6, Paint()..color = ondas.color);
      for (final r in const [4.0, 7.0, 10.0]) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi * .75, pi * .5, false, ondas);
      }
    }
    if (e.japones) {
      final panel = Rect.fromLTRB(l * .55, l * .53, l * .67, l * .60);
      canvas.drawRect(panel, Paint()..color = const Color(0xFF2B2F36));
      const luces = [Color(0xFF4FC3F7), Color(0xFFFFD60A), Color(0xFFEF5350)];
      for (var i = 0; i < luces.length; i++) {
        canvas.drawCircle(Offset(panel.left + panel.width * (i + 1) / 4, panel.center.dy), 1.6, Paint()..color = luces[i]);
      }
    }
  }
}
