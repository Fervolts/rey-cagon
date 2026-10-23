import 'idioma.dart';

// Tipos de mojón. Son de chiste: no es una escala médica ni dice nada de tu salud.
Map<int, (String, String)> get tipos => {
  1: ('🪨', tr('Piedritas de conejo', 'Rabbit pellets')),
  2: ('🧱', tr('Ladrillo', 'Brick')),
  3: ('🌽', tr('Mazorca', 'Corn cob')),
  4: ('🐍', tr('Anaconda', 'Anaconda')),
  5: ('🍦', tr('Helado suave', 'Soft serve')),
  6: ('🌋', tr('Volcán', 'Volcano')),
  7: ('💧', tr('Manguera', 'Fire hose')),
};

String tipoEmoji(int? tipo) => tipos[tipo]?.$1 ?? '💩';

String get disclaimer => tr(
    'Rey Cagón es puro entretenimiento. Nada de lo que veas o registres aquí es '
    'información de salud ni consejo médico. Si te preocupa tu salud, habla con un médico.',
    'King of the Throne is purely for entertainment. Nothing you see or log here is '
    'health information or medical advice. If you are worried about your health, talk to a doctor.');
