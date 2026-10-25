import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emoji.dart';

/// Rachas del día al estilo del anunciador de DotA. Siempre en inglés, en los dos idiomas: es el chiste.
/// Desde la segunda cagada del día el servidor también la manda al chat general (trigger cagadas_racha).
String? nombreRacha(int n) => switch (n) {
      < 2 => null,
      2 => 'DOUBLE POOP!',
      3 => 'TRIPLE POOP!',
      4 => 'ULTRA POOP!',
      _ => 'RAMPAGE!',
    };

/// Colores del texto y emoji que vuela, por nivel.
(List<Color>, String) estiloRacha(int n) => switch (n) {
      2 => (const [Color(0xFFFFE259), Color(0xFFFF9F1C)], '💩'),
      3 => (const [Color(0xFFFFB347), Color(0xFFFF3B30)], '💩'),
      4 => (const [Color(0xFFFF6FD8), Color(0xFF7B2FF7)], '🔥'),
      _ => (const [Color(0xFFFF3B30), Color(0xFF5A0000)], '💀'),
    };

/// El anuncio a pantalla completa. Se cierra solo o con un toque.
Future<void> mostrarRacha(BuildContext context, int n) async {
  if (nombreRacha(n) == null) return;
  HapticFeedback.heavyImpact();
  // El audio del anunciador va aquí cuando exista.
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Material(type: MaterialType.transparency, child: _Anuncio(n)),
  );
}

class _Anuncio extends StatefulWidget {
  const _Anuncio(this.n);

  final int n;

  @override
  State<_Anuncio> createState() => _AnuncioState();
}

class _AnuncioState extends State<_Anuncio> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward().whenComplete(_cerrar);
  final _azar = math.Random();
  late final _particulas = [
    for (var i = 0; i < 18; i++) (angulo: i / 18 * 2 * math.pi + _azar.nextDouble() * .3, distancia: 140 + _azar.nextDouble() * 160, giro: _azar.nextDouble() * 4 - 2),
  ];
  var _cerrado = false;

  void _cerrar() {
    if (_cerrado || !mounted) return;
    _cerrado = true;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Avance de 0 a 1 dentro del tramo [a, b] de la animación.
  double _tramo(double a, double b, [Curve curva = Curves.linear]) => curva.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final nombre = nombreRacha(widget.n)!;
    final (colores, emoji) = estiloRacha(widget.n);
    final rampage = widget.n >= 5;
    return GestureDetector(
      onTap: _cerrar,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final entrada = _tramo(0, .28, Curves.elasticOut);
          final salida = _tramo(.85, 1);
          final temblor = (1 - _tramo(.08, .45)) * (rampage ? 14 : 8);
          final dx = math.sin(_c.value * 120) * temblor;
          final dy = math.cos(_c.value * 97) * temblor * .6;
          final destello = 1 - _tramo(0, .12);
          final vuelo = _tramo(.05, .7, Curves.easeOutCubic);
          return Opacity(
            opacity: 1 - salida,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .72))),
                Positioned.fill(child: ColoredBox(color: colores.first.withValues(alpha: destello * .55))),
                // Emojis que salen disparados desde el centro.
                for (final p in _particulas)
                  Transform.translate(
                    offset: Offset(math.cos(p.angulo), math.sin(p.angulo)) * p.distancia * vuelo,
                    child: Transform.rotate(
                      angle: p.giro * vuelo * math.pi,
                      child: Opacity(opacity: (1 - vuelo).clamp(0.0, 1.0), child: Emoji(emoji, tamano: 40)),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(
                    scale: 3 - 2 * entrada,
                    child: Transform.rotate(
                      angle: -.06,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Letrero(nombre, colores: colores, tamano: rampage ? 64 : 52),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.n} POOPS TODAY',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: _tramo(.25, .4)),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Texto grueso con borde negro, degradado y brillo, como el de los juegos.
class _Letrero extends StatelessWidget {
  const _Letrero(this.texto, {required this.colores, required this.tamano});

  final String texto;
  final List<Color> colores;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: tamano, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 1, height: 1);
    return FittedBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            Text(
              texto,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = tamano / 7
                  ..color = Colors.black,
                shadows: [Shadow(color: colores.last, blurRadius: 28)],
              ),
            ),
            ShaderMask(
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colores,
              ).createShader(r),
              child: Text(texto, style: base.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
