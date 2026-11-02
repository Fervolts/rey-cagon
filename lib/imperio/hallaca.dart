// Hallaca dorada: el mojón dorado en la temporada de Navidad (lib/imperio/temporadas.dart). Mismo efecto, otro aspecto.
// Dibujada a mano (sin emoji ni imagen): hoja de plátano cuadrada con borde dorado, amarrada con cordón.

import 'package:flutter/material.dart';

class HallacaDorada extends StatelessWidget {
  final double tamano;
  const HallacaDorada({super.key, this.tamano = 60});

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: tamano, child: const CustomPaint(painter: _PintorHallaca()));
}

class _PintorHallaca extends CustomPainter {
  const _PintorHallaca();

  static const _hoja = Color(0xFF2E7D32), _vena = Color(0xFF4CAF50), _oro = Color(0xFFFFC21A), _cordon = Color(0xFFEADBB0);
  static const _sombraCordon = Color(0xFF8A6D1F);

  @override
  void paint(Canvas canvas, Size size) {
    final t = size.shortestSide;
    final c = size.center(Offset.zero);
    final caja = Rect.fromCenter(center: c, width: t * .86, height: t * .7);
    // Hoja de plátano con venas finas.
    canvas.drawRect(caja, Paint()..color = _hoja);
    final vena = Paint()
      ..color = _vena
      ..strokeWidth = t * .025;
    for (var i = 1; i <= 4; i++) {
      final y = caja.top + caja.height * i / 5;
      canvas.drawLine(Offset(caja.left + t * .06, y), Offset(caja.right - t * .06, y), vena);
    }
    // Borde dorado (la "dorada").
    canvas.drawRect(
        caja.deflate(t * .03),
        Paint()
          ..color = _oro
          ..style = PaintingStyle.stroke
          ..strokeWidth = t * .06);
    // Cordón en cruz con su nudo cuadrado.
    final ancho = t * .05;
    final h = Paint()..color = _sombraCordon;
    final cordon = Paint()..color = _cordon;
    for (final r in [
      Rect.fromCenter(center: c, width: caja.width + t * .04, height: ancho),
      Rect.fromCenter(center: c, width: ancho, height: caja.height + t * .04),
    ]) {
      canvas.drawRect(r.inflate(t * .012), h);
      canvas.drawRect(r, cordon);
    }
    final nudo = Rect.fromCenter(center: c, width: t * .14, height: t * .14);
    canvas.drawRect(nudo.inflate(t * .012), h);
    canvas.drawRect(nudo, Paint()..color = _oro);
    // Brillitos dorados en dos esquinas.
    final brillo = Paint()..color = _oro;
    for (final o in [Offset(caja.right - t * .02, caja.top - t * .06), Offset(caja.left + t * .02, caja.bottom + t * .06)]) {
      canvas.drawRect(Rect.fromCenter(center: o, width: t * .07, height: t * .07), brillo);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
