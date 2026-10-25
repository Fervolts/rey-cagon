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
};

/// Emoji como imagen de [tamano] px. Si no está en el set, usa el emoji del sistema.
class Emoji extends StatelessWidget {
  const Emoji(this.emoji, {super.key, this.tamano = 24});

  final String emoji;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final archivo = _archivos[emoji];
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
  });
}
