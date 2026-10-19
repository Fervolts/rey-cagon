// Tipos de mojón. Son de chiste: no es una escala médica ni dice nada de tu salud.
const tipos = {
  1: ('🪨', 'Piedritas de conejo'),
  2: ('🧱', 'Ladrillo'),
  3: ('🌽', 'Mazorca'),
  4: ('🐍', 'Anaconda'),
  5: ('🍦', 'Helado suave'),
  6: ('🌋', 'Volcán'),
  7: ('💧', 'Manguera'),
};

String tipoEmoji(int? tipo) => tipos[tipo]?.$1 ?? '💩';

const disclaimer =
    'Rey Cagón es puro entretenimiento. Nada de lo que veas o registres aquí es '
    'información de salud ni consejo médico. Si te preocupa tu salud, habla con un médico.';
