// Tubería Express, el dibujo del desagüe en un solo CustomPainter (se repinta con el Ticker, no reconstruye widgets):
// tubo con juntas, rayas de velocidad, adornos, tinte de la descarga, rollos, codos (el que te toca late), la meta a
// cuadros, la barra de camino a la planta y los efectos. El mojón no va aquí: es el Emoji de la vista.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../tema.dart';
import 'tuberia_efectos.dart';
import 'tuberia_logica.dart';

/// Marrón de las aguas de la descarga y de la estela.
const colorAguas = Color(0xFF7A5230);

class PintorTuberia extends CustomPainter {
  PintorTuberia({
    required this.j,
    required this.ef,
    required this.p,
    required this.x0,
    required this.tubo,
    required this.yJugador,
    required this.pxPorM,
    required this.mov,
    required Listenable repintar,
  }) : super(repaint: repintar);

  final JuegoTuberia j;
  final EfectosTuberia ef;
  final Paleta p;
  final double x0, tubo, yJugador, pxPorM;
  final Movimiento mov;

  double _y(double metros) => yJugador + (metros - j.distancia) * pxPorM;

  @override
  void paint(Canvas canvas, Size size) {
    final s = ef.sacudida;
    canvas.save();
    if (s != Offset.zero) canvas.translate(s.dx, s.dy);
    _tubo(canvas, size);
    _rollos(canvas, size);
    _codos(canvas, size);
    _meta(canvas, size);
    canvas.restore();
    ef.pintar(canvas);
    _camino(canvas, size);
    ef.pintarDestello(canvas, size);
  }

  void _tubo(Canvas canvas, Size size) {
    final alto = size.height;
    canvas.drawRect(Rect.fromLTWH(x0, -20, tubo, alto + 40), Paint()..color = p.suave);
    // La descarga tiñe el agua de marrón, más fuerte en el centro de la zona.
    final enDescarga = j.enDescarga;
    if (enDescarga) canvas.drawRect(Rect.fromLTWH(x0, -20, tubo, alto + 40), Paint()..color = colorAguas.withValues(alpha: 0.22));
    // Línea que separa los carriles, a trazos.
    final medio = Paint()
      ..color = p.borde
      ..strokeWidth = 1;
    final cx = x0 + tubo / 2;
    final paso = 1.2 * pxPorM;
    final corrido = (j.distancia * pxPorM) % paso;
    for (var y = -corrido; y < alto; y += paso) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + paso * 0.45), medio);
    }
    // Juntas cada 3 m: pasan hacia arriba.
    final junta = Paint()
      ..color = p.borde
      ..strokeWidth = 1;
    final primera = (j.distancia / 3).floor() - 4;
    final cuantas = (alto / pxPorM / 3).ceil() + 8;
    for (var k = primera; k < primera + cuantas; k++) {
      final y = _y(k * 3.0);
      canvas.drawLine(Offset(x0, y), Offset(x0 + tubo, y), junta);
      // Remaches en las paredes.
      canvas.drawRect(Rect.fromLTWH(x0 + 3, y - 2, 4, 4), junta);
      canvas.drawRect(Rect.fromLTWH(x0 + tubo - 7, y - 2, 4, 4), junta);
    }
    if (mov != Movimiento.nada) _adornos(canvas, size, primera, cuantas);
    if (mov == Movimiento.completo) _rayas(canvas, size);
    final pared = Paint()
      ..color = enDescarga ? colorAguas : p.bordeFuerte
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x0, -20), Offset(x0, alto + 20), pared);
    canvas.drawLine(Offset(x0 + tubo, -20), Offset(x0 + tubo, alto + 20), pared);
  }

  // Rayas de velocidad: más largas y más claras cuanto más rápido va.
  void _rayas(Canvas canvas, Size size) {
    final v = j.velocidad;
    final f = ((v - JuegoTuberia.velocidadInicial) / (JuegoTuberia.velocidadMaxima - JuegoTuberia.velocidadInicial)).clamp(0.0, 1.0);
    if (f < 0.05) return;
    final raya = Paint()
      ..color = p.bordeFuerte.withValues(alpha: 0.15 + 0.35 * f)
      ..strokeWidth = 1;
    final largo = (0.6 + 2.4 * f) * pxPorM;
    final primera = (j.distancia / 2.3).floor() - 2;
    for (var k = primera; k < primera + (size.height / pxPorM / 2.3).ceil() + 4; k++) {
      final h = (k * 40503) & 0xFFFF;
      if (h % 3 != 0) continue;
      final x = x0 + 10 + (h % 997) / 997 * (tubo - 20);
      final y = _y(k * 2.3);
      canvas.drawLine(Offset(x, y), Offset(x, y + largo), raya);
    }
  }

  // Burbujas y cucarachas: fijas por tramo (hash), sin azar por cuadro.
  void _adornos(Canvas canvas, Size size, int primera, int cuantas) {
    final burbuja = Paint()
      ..color = p.bordeFuerte
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final bicho = Paint()..color = p.textoSuave;
    for (var k = primera; k < primera + cuantas; k++) {
      final h = (k * 2654435761) & 0xFFFF;
      final bx = x0 + 12 + (h % 1000) / 1000 * (tubo - 24);
      final lado = 2.0 + (h % 4);
      canvas.drawRect(Rect.fromCenter(center: Offset(bx, _y(k * 3.0 + (h % 7) * 0.3)), width: lado, height: lado), burbuja);
      if (h % 5 == 0) {
        final izq = h % 2 == 0;
        final cx = izq ? x0 + 9 : x0 + tubo - 9;
        // Las cucarachas corren por la pared contra la corriente.
        final cy = _y(k * 3.0 + 1.5 + (ef.fase * 0.8) % 3);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 6, height: 10), bicho);
        final dir = izq ? 1.0 : -1.0;
        canvas.drawLine(Offset(cx, cy - 5), Offset(cx + 3 * dir, cy - 10), burbuja);
        canvas.drawLine(Offset(cx, cy - 5), Offset(cx - 1 * dir, cy - 10), burbuja);
      }
    }
  }

  void _rollos(Canvas canvas, Size size) {
    final ancho = tubo / 2;
    final lado = min(ancho * 0.36, 1.25 * pxPorM).clamp(14.0, 30.0);
    final papel = Paint()..color = const Color(0xFFF7F3EA);
    final dorado = Paint()..color = p.acento;
    final borde = Paint()
      ..color = p.bordeFuerte
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final hueco = Paint()..color = p.suave;
    for (final r in j.rollos) {
      if (r.agarrado) continue;
      final y = _y(r.distancia);
      if (y < -30 || y > size.height + 30) continue;
      // Gira un poco al caer (cuadrado inclinado) si hay movimiento.
      final cx = x0 + ancho * (r.carril + 0.5);
      canvas.save();
      canvas.translate(cx, y);
      if (mov == Movimiento.completo) canvas.rotate(sin(ef.fase * 3 + r.distancia) * 0.25);
      final rect = Rect.fromCenter(center: Offset.zero, width: lado, height: lado);
      canvas.drawRect(rect, r.dorado ? dorado : papel);
      canvas.drawRect(rect, borde);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: lado * 0.34, height: lado * 0.34), hueco);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: lado * 0.34, height: lado * 0.34), borde);
      canvas.restore();
    }
  }

  void _codos(Canvas canvas, Size size) {
    final ancho = tubo / 2;
    final relleno = Paint()..color = p.primario;
    final rejilla = Paint()
      ..color = p.sobrePrimario.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final borde = Paint()
      ..color = p.acento
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final alerta = Paint()
      ..color = p.acento
      ..style = PaintingStyle.stroke;
    final alto = JuegoTuberia.radioCodo * 2 * pxPorM;
    for (final c in j.codos) {
      final y = _y(c.distancia);
      if (y < -40 || y > size.height + 40) continue;
      final r = Rect.fromLTWH(x0 + c.carril * ancho, y - alto / 2, ancho, alto);
      canvas.drawRect(r, relleno);
      // Tornillos y franjas: que se lea como una pieza de tubo y no como un botón.
      for (var x = r.left + 10; x < r.right - 6; x += 12) {
        canvas.drawLine(Offset(x, r.top + 2), Offset(x - 6, r.bottom - 2), rejilla);
      }
      canvas.drawRect(r, borde);
      // El que viene por tu carril late para avisar.
      final dd = c.distancia - j.distancia;
      if (j.vivo && c.carril == j.carril && dd > 0 && dd < 9 && mov != Movimiento.nada) {
        final pulso = mov == Movimiento.completo ? 0.5 + 0.5 * sin(ef.fase * 18) : 1.0;
        alerta.strokeWidth = 1 + 2 * pulso;
        alerta.color = p.acento.withValues(alpha: 0.4 + 0.6 * (1 - dd / 9));
        canvas.drawRect(r.inflate(3 + 2 * pulso), alerta);
      }
    }
  }

  // La planta de tratamiento: línea a cuadros.
  void _meta(Canvas canvas, Size size) {
    final y = _y(JuegoTuberia.meta);
    if (y < -20 || y > size.height + 20) return;
    const n = 12;
    final lado = tubo / n;
    final a = Paint()..color = p.texto;
    final b = Paint()..color = p.fondo;
    for (var fila = 0; fila < 2; fila++) {
      for (var i = 0; i < n; i++) {
        canvas.drawRect(Rect.fromLTWH(x0 + i * lado, y + fila * lado, lado, lado), (i + fila).isEven ? a : b);
      }
    }
  }

  // Barra fina a la derecha del tubo: cuánto falta para la planta, con marcas en cada zona.
  void _camino(Canvas canvas, Size size) {
    final x = min(size.width - 6, x0 + tubo + 8);
    final top = 56.0, bottom = size.height - 24;
    final largo = bottom - top;
    if (largo < 60) return;
    final linea = Paint()
      ..color = p.borde
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, top), Offset(x, bottom), linea);
    final marca = Paint()
      ..color = p.bordeFuerte
      ..strokeWidth = 1;
    for (final z in JuegoTuberia.zonas.skip(1)) {
      final yz = top + largo * z / JuegoTuberia.meta;
      canvas.drawLine(Offset(x - 3, yz), Offset(x + 3, yz), marca);
    }
    final hecho = top + largo * (j.distancia / JuegoTuberia.meta).clamp(0.0, 1.0);
    canvas.drawLine(Offset(x, top), Offset(x, hecho), Paint()
      ..color = p.acento
      ..strokeWidth = 2);
    canvas.drawRect(Rect.fromCenter(center: Offset(x, hecho), width: 6, height: 6), Paint()..color = p.acento);
    canvas.drawRect(Rect.fromLTWH(x - 4, bottom, 8, 8), Paint()..color = p.texto);
  }

  @override
  bool shouldRepaint(covariant PintorTuberia old) =>
      old.j != j || old.p != p || old.x0 != x0 || old.tubo != tubo || old.pxPorM != pxPorM || old.mov != mov;
}
