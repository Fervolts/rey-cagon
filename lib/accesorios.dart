import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'emoji.dart';

/// Algo que se desbloquea al llegar a [minimo] cagadas en total.
typedef Desbloqueo = ({String ranura, String emoji, String nombre, int minimo});

// Mismo catálogo que la tabla desbloqueos (supabase/migrations/…_accesorios.sql).
// El servidor rechaza lo que no esté desbloqueado.
const desbloqueos = <Desbloqueo>[
  (ranura: 'mascota', emoji: '🪰', nombre: 'Mosca', minimo: 1),
  (ranura: 'sombrero', emoji: '🧢', nombre: 'Gorra', minimo: 3),
  (ranura: 'lentes', emoji: '👓', nombre: 'Lentes', minimo: 5),
  (ranura: 'mascota', emoji: '🐛', nombre: 'Gusanito', minimo: 8),
  (ranura: 'sombrero', emoji: '👒', nombre: 'Sombrero de playa', minimo: 12),
  (ranura: 'avatar', emoji: '👽', nombre: 'Alien', minimo: 15),
  (ranura: 'lentes', emoji: '🕶️', nombre: 'Lentes oscuros', minimo: 20),
  (ranura: 'mascota', emoji: '🐀', nombre: 'Rata', minimo: 25),
  (ranura: 'sombrero', emoji: '🎓', nombre: 'Doctor en cagología', minimo: 30),
  (ranura: 'avatar', emoji: '🤖', nombre: 'Robot', minimo: 40),
  (ranura: 'mascota', emoji: '🪳', nombre: 'Cucaracha', minimo: 50),
  (ranura: 'sombrero', emoji: '🎩', nombre: 'Copa', minimo: 60),
  (ranura: 'lentes', emoji: '🥽', nombre: 'Goggles', minimo: 75),
  (ranura: 'avatar', emoji: '🐲', nombre: 'Dragón', minimo: 100),
  (ranura: 'mascota', emoji: '🦨', nombre: 'Mapurite', minimo: 125),
  (ranura: 'sombrero', emoji: '🪖', nombre: 'Casco', minimo: 150),
  (ranura: 'avatar', emoji: '💎', nombre: 'Diamante', minimo: 200),
  (ranura: 'mascota', emoji: '🦆', nombre: 'Pato', minimo: 250),
  (ranura: 'avatar', emoji: '🏆', nombre: 'Un año cagando', minimo: 365),
];

/// Desde estas cagadas la mascota pasea alrededor del avatar.
const mascotaSeMueve = 50;

/// Efectos del avatar según el total histórico. Se aplica el más alto alcanzado.
const efectosAvatar = [
  (nombre: 'Avatar cromado', minimo: 100),
  (nombre: 'Avatar dorado', minimo: 200),
  (nombre: 'Avatar arcoíris', minimo: 300),
];

/// Lo próximo que se desbloquea con [total] cagadas (accesorio o efecto), o null si ya tiene todo.
({String emoji, String nombre, int minimo})? siguienteDesbloqueo(int total) {
  final todo = [
    for (final d in desbloqueos) (emoji: d.emoji, nombre: d.nombre, minimo: d.minimo),
    (emoji: '🪰', nombre: 'Mascota que pasea', minimo: mascotaSeMueve),
    for (final e in efectosAvatar) (emoji: '💩', nombre: e.nombre, minimo: e.minimo),
  ]..sort((a, b) => a.minimo.compareTo(b.minimo));
  for (final d in todo) {
    if (d.minimo > total) return d;
  }
  return null;
}

/// Dónde van lentes y sombrero en cada avatar, en fracciones del cuadro: centro (x, y) y
/// ancho del accesorio. null = ese avatar no lo usa (😎 ya trae lentes, 👑 ya es sombrero).
/// Calibrado a mano sobre los PNG de Fluent: y de lentes es la línea de los ojos, y de
/// sombrero es donde se apoya en la cabeza.
typedef _Punto = ({double x, double y, double ancho});
typedef _Encaje = ({_Punto? lentes, _Punto? sombrero});

const Map<String, _Encaje> _encajes = {
  '💩': (lentes: (x: 0.5, y: 0.6, ancho: 0.7), sombrero: (x: 0.55, y: 0.25, ancho: 0.42)),
  '👑': (lentes: null, sombrero: null),
  '🧻': (lentes: null, sombrero: (x: 0.5, y: 0.17, ancho: 0.5)),
  '🚽': (lentes: null, sombrero: (x: 0.75, y: 0.1, ancho: 0.4)),
  '🐻': (lentes: (x: 0.49, y: 0.51, ancho: 0.52), sombrero: (x: 0.5, y: 0.22, ancho: 0.5)),
  '🦍': (lentes: (x: 0.17, y: 0.19, ancho: 0.26), sombrero: (x: 0.19, y: 0.09, ancho: 0.24)),
  '🐷': (lentes: (x: 0.5, y: 0.51, ancho: 0.56), sombrero: (x: 0.5, y: 0.18, ancho: 0.5)),
  '🐸': (lentes: (x: 0.5, y: 0.3, ancho: 0.82), sombrero: (x: 0.5, y: 0.15, ancho: 0.42)),
  '🦄': (lentes: (x: 0.33, y: 0.44, ancho: 0.32), sombrero: (x: 0.55, y: 0.2, ancho: 0.36)),
  '🤡': (lentes: (x: 0.51, y: 0.37, ancho: 0.72), sombrero: (x: 0.5, y: 0.11, ancho: 0.5)),
  '😎': (lentes: null, sombrero: (x: 0.5, y: 0.09, ancho: 0.55)),
  '👻': (lentes: (x: 0.45, y: 0.27, ancho: 0.52), sombrero: (x: 0.5, y: 0.09, ancho: 0.42)),
  '🔥': (lentes: null, sombrero: (x: 0.45, y: 0.15, ancho: 0.38)),
  '🌶️': (lentes: null, sombrero: (x: 0.6, y: 0.12, ancho: 0.42)),
  '🍑': (lentes: null, sombrero: (x: 0.5, y: 0.12, ancho: 0.45)),
  '🦖': (lentes: (x: 0.29, y: 0.18, ancho: 0.28), sombrero: (x: 0.27, y: 0.17, ancho: 0.32)),
  '👽': (lentes: (x: 0.54, y: 0.49, ancho: 0.86), sombrero: (x: 0.5, y: 0.09, ancho: 0.55)),
  '🤖': (lentes: (x: 0.5, y: 0.42, ancho: 0.66), sombrero: (x: 0.5, y: 0.16, ancho: 0.5)),
  '🐲': (lentes: (x: 0.45, y: 0.45, ancho: 0.35), sombrero: (x: 0.37, y: 0.27, ancho: 0.35)),
  '💎': (lentes: null, sombrero: (x: 0.5, y: 0.27, ancho: 0.45)),
  '🏆': (lentes: null, sombrero: (x: 0.5, y: 0.13, ancho: 0.45)),
};

_Encaje _encaje(String avatar) => _encajes[avatar] ?? _encajes[avatar.replaceAll('\u{FE0F}', '')] ?? _encajes['💩']!;

bool usaLentes(String avatar) => _encaje(avatar).lentes != null;
bool usaSombrero(String avatar) => _encaje(avatar).sombrero != null;

// El dibujo de cada accesorio ocupa ~87,5% del ancho de su PNG.
const _relleno = .875;
// Altura (fracción del PNG) de la línea de los ojos en cada lente.
const _centroLentes = {'👓': .49, '🕶️': .49, '🕶': .49, '🥽': .62};
// Altura (fracción del PNG) por donde cada sombrero se apoya en la cabeza.
const _asiento = {'🧢': .70, '👒': .80, '🎓': .62, '🎩': .90, '🪖': .58};

/// Avatar con sus accesorios encima. Lee avatar, sombrero, lentes, mascota y cagadas de
/// [perfil] (una fila de profiles, leaderboard o perfil). Ocupa [tamano]; los accesorios y
/// la mascota se salen del cuadro.
class Avatar extends StatefulWidget {
  const Avatar(this.perfil, {super.key, this.tamano = 28});

  final Map<String, dynamic> perfil;
  final double tamano;

  @override
  State<Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<Avatar> with SingleTickerProviderStateMixin {
  // Un minuto en bucle: todas las trayectorias tienen periodos que dividen 60 s.
  late final _reloj = AnimationController(vsync: this, duration: const Duration(seconds: 60));

  int get _cagadas => (widget.perfil['cagadas'] as num?)?.toInt() ?? 0;
  String? get _mascota => widget.perfil['mascota'] as String?;
  bool get _pasea => _mascota != null && _cagadas >= mascotaSeMueve;
  // 0 sin efecto, 1 cromado, 2 dorado, 3 arcoíris.
  int get _nivel => efectosAvatar.where((e) => _cagadas >= e.minimo).length;

  @override
  void initState() {
    super.initState();
    _ajustarReloj();
  }

  @override
  void didUpdateWidget(Avatar viejo) {
    super.didUpdateWidget(viejo);
    _ajustarReloj();
  }

  void _ajustarReloj() {
    final animado = _pasea || _nivel > 0;
    if (animado && !_reloj.isAnimating) {
      // Cada usuario arranca en otro punto para que el ranking no se mueva sincronizado.
      _reloj.value = ((widget.perfil['username'] ?? '').hashCode % 600) / 600;
      _reloj.repeat();
    } else if (!animado && _reloj.isAnimating) {
      _reloj.stop();
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tamano;
    final sombrero = widget.perfil['sombrero'] as String?;
    final lentes = widget.perfil['lentes'] as String?;
    final mascota = _mascota;
    final avatar = widget.perfil['avatar'] as String? ?? '💩';
    final encaje = _encaje(avatar);
    final base = Emoji(avatar, tamano: t);
    return SizedBox(
      width: t,
      height: t,
      child: AnimatedBuilder(
        animation: _reloj,
        builder: (context, _) {
          final segundos = _reloj.value * 60;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              _conEfecto(base, _nivel, segundos),
              if (lentes != null && encaje.lentes != null) _ponerLentes(lentes, encaje.lentes!, t),
              if (sombrero != null && encaje.sombrero != null) _ponerSombrero(sombrero, encaje.sombrero!, t),
              if (mascota != null)
                if (_pasea)
                  _paseo(mascota, t, segundos)
                else
                  Positioned(right: -t * .22, bottom: -t * .06, child: Emoji(mascota, tamano: t * .42)),
            ],
          );
        },
      ),
    );
  }
}

Widget _ponerLentes(String lentes, _Punto p, double t) {
  final tam = p.ancho / _relleno * t;
  return Positioned(
    left: p.x * t - tam / 2,
    top: p.y * t - (_centroLentes[lentes] ?? .5) * tam,
    child: Emoji(lentes, tamano: tam),
  );
}

Widget _ponerSombrero(String sombrero, _Punto p, double t) {
  final tam = p.ancho / _relleno * t;
  return Positioned(
    left: p.x * t - tam / 2,
    top: p.y * t - (_asiento[sombrero] ?? .85) * tam,
    child: Emoji(sombrero, tamano: tam),
  );
}

/// Posición de la mascota en unidades del avatar (0..1 es el cuadro; se sale por los lados).
/// [mira] es 1 si camina hacia la derecha (el emoji se voltea), [giro] en radianes.
typedef _Pose = ({double x, double y, double giro, double mira});

const _suelo = .62;
double _lerp(double a, double b, double u) => a + (b - a) * u;
double _suave(double u) => u * u * (3 - 2 * u);

// Número pseudoaleatorio estable en [0, 1) para el paso [k].
double _azar(int k) => ((k * 2654435761) & 0xFFFFFF) / 0x1000000;

_Pose _pose(String mascota, double s) {
  switch (mascota) {
    case '🐛':
      // Oruga: se arrastra lenta de derecha a izquierda, a tirones, y vuelve a entrar.
      final u = (s % 20) / 20;
      final tiron = math.sin(u * 2 * math.pi * 30);
      return (x: _lerp(1.3, -.75, u + .01 * tiron), y: _suelo - .03 * tiron.abs(), giro: 0, mira: 0);
    case '🪰':
      // Mosca: vuela rápido en ocho de lado a lado, con zumbido.
      final u = (s % 3) / 3;
      final a = 2 * math.pi * u;
      return (
        x: .3 + .95 * math.sin(a) + .02 * math.sin(s * 60),
        y: .05 + .4 * math.sin(2 * a) + .02 * math.cos(s * 55),
        giro: .5 * math.cos(a),
        mira: 0,
      );
    case '🐀':
      // Rata: corre por el suelo, sale del cuadro, vuelve y se queda olfateando.
      final u = (s % 6) / 6;
      if (u < .3) return (x: _lerp(1.0, -.9, _suave(u / .3)), y: _suelo, giro: 0, mira: 0);
      if (u < .45) return (x: -.9, y: _suelo, giro: 0, mira: 0);
      if (u < .75) return (x: _lerp(-.9, 1.0, _suave((u - .45) / .3)), y: _suelo, giro: 0, mira: 1);
      return (x: 1.0, y: _suelo - .02 * math.sin(s * 40).abs(), giro: 0, mira: 1);
    case '🪳':
      // Cucaracha: salta entre esquinas a lo loco, se esconde fuera del cuadro y reaparece.
      const puntos = [(-.35, -.3), (1.0, -.3), (-.35, .8), (1.0, .8), (1.6, .3), (-.9, .4), (.35, 1.1)];
      final k = (s / .7).floor();
      final u = (s / .7) - k;
      final (x0, y0) = puntos[(_azar(k - 1) * puntos.length).floor()];
      final (x1, y1) = puntos[(_azar(k) * puntos.length).floor()];
      final v = _suave((u / .35).clamp(0, 1));
      final giro = math.atan2(y1 - y0, x1 - x0) + math.pi / 2;
      final temblor = u > .35 ? .04 * math.sin(s * 70) : 0;
      return (x: _lerp(x0, x1, v), y: _lerp(y0, y1, v), giro: giro + temblor, mira: 0);
    case '🦨':
      // Mapurite: camina lento de un lado a otro con pausas.
      final u = (s % 15) / 15;
      final paso = .02 * math.sin(s * 9).abs();
      if (u < .45) return (x: _lerp(1.2, -.6, u / .45), y: _suelo - paso, giro: 0, mira: 0);
      if (u < .5) return (x: -.6, y: _suelo, giro: 0, mira: 0);
      if (u < .95) return (x: _lerp(-.6, 1.2, (u - .5) / .45), y: _suelo - paso, giro: 0, mira: 1);
      return (x: 1.2, y: _suelo, giro: 0, mira: 1);
    default:
      // Pato y cualquier otro: va y viene contoneándose.
      final u = (s % 6) / 6;
      final a = 2 * math.pi * u;
      return (
        x: .3 + .9 * math.sin(a),
        y: _suelo - .03 * math.sin(s * 14).abs(),
        giro: .18 * math.sin(s * 14),
        mira: math.cos(a) > 0 ? 1 : 0,
      );
  }
}

Widget _paseo(String mascota, double t, double segundos) {
  final p = _pose(mascota, segundos);
  final tam = t * .42;
  Widget emoji = Emoji(mascota, tamano: tam);
  if (p.mira == 1) emoji = Transform.flip(flipX: true, child: emoji);
  return Positioned(
    left: p.x * t,
    top: p.y * t,
    child: Transform.rotate(angle: p.giro, child: emoji),
  );
}

/// Cromado y dorado: el emoji en gris con un brillo que lo cruza. Arcoíris: degradado
/// semitransparente que gira y solo pinta donde hay emoji.
Widget _conEfecto(Widget hijo, int nivel, double segundos) {
  final fase = (segundos % 3) / 3;
  switch (nivel) {
    case 0:
      return hijo;
    case 3:
      return ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => SweepGradient(
          colors: [
            for (final c in const [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red])
              c.withValues(alpha: .55),
          ],
          transform: GradientRotation(fase * 2 * math.pi),
        ).createShader(r),
        child: hijo,
      );
    default:
      final dorado = nivel == 2;
      final base = dorado ? const Color(0xFFF2C94C) : const Color(0xFFC9CED6);
      final gris = ColorFiltered(colorFilter: const ColorFilter.matrix(_escalaDeGris), child: hijo);
      return ShaderMask(
        blendMode: BlendMode.modulate,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(fase * 4 - 2, -1),
          end: Alignment(fase * 4 - 1, 1),
          colors: [base, Colors.white, base],
          stops: const [.3, .5, .7],
        ).createShader(r),
        child: dorado
            ? ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFFFD34D), BlendMode.modulate), child: gris)
            : gris,
      );
  }
}

// Escala de grises aclarada: el café del 💩 en gris puro queda casi negro.
const _escalaDeGris = <double>[
  .32, 1.07, .11, 0, 60,
  .32, 1.07, .11, 0, 60,
  .32, 1.07, .11, 0, 60,
  0, 0, 0, 1, 0,
];
