// Memoria del rollo: la carta (volteo 3D, reverso de rollo de papel) y las chispas de los aciertos. La usa memoria_vista.dart.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../tema.dart';

/// El reverso de todas las cartas.
const String emojiReverso = '🧻';

/// Una carta dibujada. Todo lo que se mueve llega como número, así un solo reloj anima el tablero entero.
class CartaMemoriaVista extends StatelessWidget {
  const CartaMemoriaVista({
    super.key,
    required this.emoji,
    required this.lado,
    required this.mov,
    required this.giro,
    this.hecha = false,
    this.pop = 1,
    this.sacude = 1,
    this.marca = 1,
    this.entrada = 1,
  });

  final String emoji;
  final double lado;
  final Movimiento mov;

  /// 0 = reverso, 1 = cara. En medio va volteándose.
  final double giro;
  final bool hecha;

  /// Avance de cada efecto de 0 a 1 (1 = terminado): brinco al acertar, sacudida al fallar, aviso de la cucaracha y
  /// la entrada al empezar el nivel.
  final double pop, sacude, marca, entrada;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final cara = giro >= 0.5;
    Widget hoja = cara ? _cara(p) : _reverso(p);

    if (mov == Movimiento.completo) {
      // Volteo con perspectiva: la cara se dibuja ya girada media vuelta para que no salga al revés.
      final angulo = pi * giro - (cara ? pi : 0);
      hoja = Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, 0.0012)..rotateY(angulo), child: hoja);
    } else if (mov == Movimiento.simple) {
      hoja = Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(max(0.02, cos(pi * giro).abs()), 1, 1), child: hoja);
    }

    if (mov != Movimiento.nada) {
      var escala = 1.0;
      if (pop > 0 && pop < 1) escala += 0.14 * sin(pi * pop);
      if (entrada < 1) escala *= 0.6 + 0.4 * Curves.easeOutBack.transform(entrada.clamp(0.0, 1.0));
      final dx = sacude > 0 && sacude < 1 ? sin(sacude * pi * 6) * lado * 0.07 * (1 - sacude) : 0.0;
      if (escala != 1 || dx != 0) {
        hoja = Transform(alignment: Alignment.center, transform: Matrix4.translationValues(dx, 0, 0)..scaleByDouble(escala, escala, 1, 1), child: hoja);
      }
      if (entrada < 1) hoja = Opacity(opacity: entrada.clamp(0.0, 1.0), child: hoja);
    }
    return hoja;
  }

  Widget _cara(Paleta p) {
    // Aviso de la cucaracha: la carta que se movió parpadea con el acento.
    final aviso = marca < 1 ? (0.5 + 0.5 * cos(marca * pi * 6)) * (1 - marca) : 0.0;
    return Container(
      decoration: BoxDecoration(
        color: hecha ? Color.alphaBlend(p.acento.withValues(alpha: 0.14), p.tarjeta) : p.tarjeta,
        border: Border.all(color: hecha ? p.acento : p.bordeFuerte),
        borderRadius: BorderRadius.circular(radio),
      ),
      foregroundDecoration: aviso > 0
          ? BoxDecoration(border: Border.all(color: p.acento.withValues(alpha: aviso)), borderRadius: BorderRadius.circular(radio))
          : null,
      alignment: Alignment.center,
      child: Opacity(opacity: hecha ? 0.6 : 1, child: Emoji(emoji, tamano: lado * 0.58)),
    );
  }

  Widget _reverso(Paleta p) {
    final aviso = marca < 1 ? (0.5 + 0.5 * cos(marca * pi * 6)) * (1 - marca) : 0.0;
    return Container(
      decoration: BoxDecoration(
        color: aviso > 0 ? Color.alphaBlend(p.acento.withValues(alpha: 0.35 * aviso), p.suave) : p.suave,
        border: Border.all(color: aviso > 0 ? p.acento : p.borde),
        borderRadius: BorderRadius.circular(radio),
      ),
      child: CustomPaint(
        painter: _Perforado(p.borde),
        child: Center(child: Opacity(opacity: 0.85, child: Emoji(emojiReverso, tamano: lado * 0.4))),
      ),
    );
  }
}

/// Las líneas punteadas del papel: dos cortes de hoja, como un rollo desenrollado.
class _Perforado extends CustomPainter {
  _Perforado(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final pincel = Paint()..color = color;
    final paso = max(4.0, s.width / 9);
    final punto = paso * 0.45;
    for (final f in const [0.18, 0.82]) {
      final y = s.height * f;
      for (var x = paso * 0.5; x < s.width - 2; x += paso) {
        canvas.drawRect(Rect.fromLTWH(x, y, punto, 1), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_Perforado viejo) => viejo.color != color;
}

/// Una chispa cuadrada. Vive [vida] segundos.
class Chispa {
  Chispa(this.x, this.y, this.vx, this.vy, this.lado, this.color, this.vida) : resta = vida;
  double x, y, vx, vy;
  final double lado, vida;
  final Color color;
  double resta;

  /// Avanza y devuelve false cuando ya se apagó.
  bool avanzar(double dt) {
    resta -= dt;
    vy += 900 * dt;
    vx *= 1 - 2 * dt;
    x += vx * dt;
    y += vy * dt;
    return resta > 0;
  }
}

/// Pinta todas las chispas de una vez.
class ChispasPintor extends CustomPainter {
  ChispasPintor(this.chispas);
  final List<Chispa> chispas;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint();
    for (final c in chispas) {
      final a = (c.resta / c.vida).clamp(0.0, 1.0);
      pincel.color = c.color.withValues(alpha: a);
      final l = c.lado * (0.5 + 0.5 * a);
      canvas.drawRect(Rect.fromCenter(center: Offset(c.x, c.y), width: l, height: l), pincel);
    }
  }

  @override
  bool shouldRepaint(ChispasPintor viejo) => true;
}
