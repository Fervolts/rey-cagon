import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'idioma.dart';

// Fluent Emoji 3D de Microsoft (MIT, assets/emoji/LICENSE). Se usan como imágenes para que
// se vean igual en todos los teléfonos.
const _archivos = {
  '💩': 'pile_of_poo',
  '👑': 'crown',
  '🥈': '2nd_place_medal',
  '🥉': '3rd_place_medal',
  '🫥': 'dotted_line_face',
  '🚽': 'toilet',
  '🪨': 'rock',
  '🧱': 'brick',
  '🌽': 'ear_of_corn',
  '🐍': 'snake',
  '🍦': 'soft_ice_cream',
  '🌋': 'volcano',
  '💧': 'droplet',
  '🧻': 'roll_of_paper',
  '🐻': 'bear',
  '🦍': 'gorilla',
  '🐷': 'pig_face',
  '🐸': 'frog',
  '🦄': 'unicorn',
  '🤡': 'clown_face',
  '😎': 'smiling_face_with_sunglasses',
  '🙂': 'slightly_smiling_face',
  '🍺': 'beer_mug',
  '🚿': 'shower',
  '🪽': 'wing',
  '✨': 'sparkles',
  '🩸': 'drop_of_blood',
  '💦': 'sweat_droplets',
  '💨': 'dashing_away',
  '👻': 'ghost',
  '🔥': 'fire',
  '🌶️': 'hot_pepper',
  '🌶': 'hot_pepper',
  '🍑': 'peach',
  '🦖': 't-rex',
  '🪰': 'fly',
  '🧢': 'billed_cap',
  '👓': 'glasses',
  '🐛': 'bug',
  '👒': 'womans_hat',
  '👽': 'alien',
  '🕶️': 'sunglasses',
  '🕶': 'sunglasses',
  '🐀': 'rat',
  '🎓': 'graduation_cap',
  '🤖': 'robot',
  '🪳': 'cockroach',
  '🎩': 'top_hat',
  '🥽': 'goggles',
  '🐲': 'dragon_face',
  '🦨': 'skunk',
  '🪖': 'military_helmet',
  '💎': 'gem_stone',
  '🦆': 'duck',
  '🏆': 'trophy',
  '🏃': 'person_running',
  '⏰': 'alarm_clock',
  '☕': 'hot_beverage',
  '🙅': 'person_gesturing_no',
  '📱': 'mobile_phone',
  '🪶': 'feather',
  '🍌': 'banana',
  '⚓': 'anchor',
  '🐋': 'whale',
  '🤴': 'prince',
  '👸': 'princess',
  '🫅': 'person_with_crown',
  '💀': 'skull',
  '🔒': 'locked',
  '⚔️': 'crossed_swords',
  '⚔': 'crossed_swords',
  '🌙': 'crescent_moon',
  '🌅': 'sunrise',
  '🗓️': 'spiral_calendar',
  '🗓': 'spiral_calendar',
  '🤷': 'person_shrugging',
  '💡': 'light_bulb',
  '☢️': 'radioactive',
  '☢': 'radioactive',
  '💥': 'collision',
  // Imperio.
  '🏭': 'factory',
  '👆': 'backhand_index_pointing_up',
  '🫐': 'plum', // Ciruela: durazno Fluent recoloreado (no hay ciruela en Fluent).
  '🫓': 'flatbread',
  '🚻': 'restroom',
  '🚛': 'articulated_lorry',
  '🕳️': 'hole',
  '🌱': 'seedling',
  '⛏️': 'pick',
  '🛕': 'hindu_temple',
  '⏳': 'hourglass_not_done',
  '🌌': 'milky_way',
  '🧤': 'gloves',
  '🩲': 'briefs',
  '🦾': 'mechanical_arm',
  '🫁': 'lungs',
  '🙌': 'raising_hands',
  '🛢️': 'oil_drum',
  '🔧': 'wrench',
  '🧲': 'magnet',
  '🪻': 'hyacinth',
  '🧴': 'lotion_bottle',
  '🛒': 'shopping_cart',
  '💊': 'pill',
  '🪠': 'plunger',
  '🟡': 'yellow_circle',
  '🏛️': 'classical_building',
  '🏗️': 'building_construction',
  '🕹️': 'joystick',
  '🎟️': 'admission_tickets',
  '🚰': 'potable_water',
  '🎯': 'bullseye',
  '🃏': 'joker',
  '🎹': 'musical_keyboard',
  '❓': 'red_question_mark',
  '🎣': 'fishing_pole',
  '🛁': 'bathtub',
  // Poceta del Imperio: el dinero que sale al pujar.
  '💰': 'money_bag',
  '💸': 'money_with_wings',
  '🪙': 'coin',
  // El baño del Imperio: adornos y lo que hacen los edificios.
  '🧶': 'yarn',
  '🟫': 'brown_square',
  '🌸': 'cherry_blossom',
  '🪴': 'potted_plant',
  '🎨': 'artist_palette',
  '🪣': 'bucket',
  '👀': 'eyes',
  '💍': 'ring',
  '🦶': 'foot',
  '✋': 'raised_hand',
  '🫖': 'teapot',
  '💉': 'syringe',
  '🫙': 'jar',
  // Escenas v2 del baño: leche de magnesia, clase media, camión volador.
  '🥛': 'glass_of_milk',
  '🪞': 'mirror',
  '🖼️': 'framed_picture',
  '🥄': 'spoon',
  '🫧': 'bubbles',
  '🚁': 'helicopter',
  // Imperio fase 2: Maná, alquilables, consumibles y objetos de Rollos.
  '🌀': 'cyclone',
  '🧰': 'toolbox',
  '👦': 'boy',
  '👷': 'construction_worker',
  '🔦': 'flashlight',
  '🌲': 'evergreen_tree',
  '🍵': 'teacup_without_handle',
  '🧪': 'test_tube',
  '🦸': 'superhero',
  '⛓️': 'chains',
  '⛓': 'chains',
  // Imperio fase 2: Fichas, Cofre del Trono y Congelador de racha.
  '🧊': 'ice',
  '🎁': 'wrapped_gift',
  '⏩': 'fast-forward_button',
  // Imperio fase 4: Mudanza, casas, Llavero y Mayordomo.
  '🛖': 'hut',
  '🏠': 'house',
  '🏡': 'house_with_garden',
  '🏰': 'castle',
  '🔑': 'key',
  '🚚': 'delivery_truck',
  '🤵': 'person_in_tuxedo',
};

// Las mismas claves sin FE0F, para encontrar '🌶' igual que '🌶️'.
final _sinVariacion = {for (final e in _archivos.entries) e.key.replaceAll('\u{FE0F}', ''): e.value};

/// Emoji como imagen de [tamano] px. Si no está en el set, usa el emoji del sistema.
class Emoji extends StatelessWidget {
  const Emoji(this.emoji, {super.key, this.tamano = 24});

  final String emoji;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    // El teclado a veces manda el selector de variación (FE0F) y a veces no: vale igual.
    final archivo = _archivos[emoji] ?? _sinVariacion[emoji.replaceAll('\u{FE0F}', '')];
    if (archivo == null) {
      return SizedBox(
        width: tamano,
        height: tamano,
        child: FittedBox(child: Text(emoji)),
      );
    }
    return Image.asset(
      'assets/emoji/$archivo.png',
      width: tamano,
      height: tamano,
      filterQuality: FilterQuality.medium,
      semanticLabel: emoji,
    );
  }
}

void registrarLicencias() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Fluent Emoji (Microsoft)'],
      await rootBundle.loadString('assets/emoji/LICENSE'),
    );
    yield LicenseEntryWithLineBreaks(
      [tr('Noto Emoji (Google), ícono de la app', 'Noto Emoji (Google), app icon')],
      '${tr('Noto Emoji © Google LLC. Licencia Apache 2.0 / CC BY 4.0.', 'Noto Emoji © Google LLC. Apache 2.0 / CC BY 4.0 license.')}\n'
      'https://github.com/googlefonts/noto-emoji',
    );
    yield LicenseEntryWithLineBreaks(
      [tr('Noto Color Emoji (Google), emojis nuevos', 'Noto Color Emoji (Google), newer emojis')],
      await rootBundle.loadString('assets/fonts/LICENSE-OFL.txt'),
    );
  });
}

/// Un emoji dentro de un texto: con tono de piel, uniones (ZWJ) y banderas.
// El analizador no conoce \p{Extended_Pictographic}; Dart sí.
final _emojiEnTexto = RegExp(
    // ignore: valid_regexps
    r'(?:\p{Extended_Pictographic}|\p{Regional_Indicator})(?:\u{FE0F}|[\u{1F3FB}-\u{1F3FF}]|\u{200D}\p{Extended_Pictographic}|\p{Regional_Indicator})*',
    unicode: true);

/// Parte [texto] en tramos de texto y emojis dibujados con [Emoji].
///
/// En algunos teléfonos (Samsung) el texto que va después de un emoji del sistema sale con los espacios anchísimos:
/// la línea se queda con la fuente del emoji. Con el emoji como widget aparte eso no pasa.
List<InlineSpan> spansConEmojis(String texto, {TextStyle? estilo, double tamano = 18}) {
  final partes = <InlineSpan>[];
  var desde = 0;
  for (final m in _emojiEnTexto.allMatches(texto)) {
    // ©, ®, ™ y compañía también son "pictográficos": sin FE0F se quedan como letra.
    if (m.group(0)!.runes.first < 0x2000 && !m.group(0)!.contains('\u{FE0F}')) continue;
    if (m.start > desde) partes.add(TextSpan(text: texto.substring(desde, m.start), style: estilo));
    partes.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: Emoji(m.group(0)!, tamano: tamano)));
    desde = m.end;
  }
  if (desde < texto.length) partes.add(TextSpan(text: texto.substring(desde), style: estilo));
  return partes;
}

/// [Text] que dibuja sus emojis con [Emoji] (ver [spansConEmojis]). El emoji sale un poco más grande que la letra.
class TextoConEmojis extends StatelessWidget {
  const TextoConEmojis(this.texto, {super.key, this.style, this.maxLines, this.overflow, this.textAlign});

  final String texto;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final tam = (style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.2;
    return Text.rich(TextSpan(children: spansConEmojis(texto, tamano: tam)),
        style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign);
  }
}
