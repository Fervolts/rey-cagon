// Tubería Express, el dibujo del desagüe en un solo CustomPainter (se repinta con el Ticker, no reconstruye widgets):
// tubo con paredes gruesas (anillos y remaches que pasan con la distancia), sarro, corriente de agua por carril,
// adornos, tinte de la descarga, rollos (el PNG del 🧻 si ya cargó), codos con franjas de peligro (el que te toca late),
// la meta a cuadros, la barra de camino a la planta y los efectos. El mojón no va aquí: es el Emoji de la vista.
// Los Paint se crean una vez por pintor (la vista lo rehace solo al cambiar el layout o el tema), no por cuadro.

import 'dart:math';
import 'dart:ui' as ui;

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
    this.rollo,
    required Listenable repintar,
  }) : super(repaint: repintar);

  final JuegoTuberia j;
  final EfectosTuberia ef;
  final Paleta p;
  final double x0, tubo, yJugador, pxPorM;
  final Movimiento mov;

  /// El PNG del rollo; mientras no carga se dibuja un cuadrado con hueco.
  final ui.Image? rollo;

  /// Ancho de cada pared del tubo.
  static const double muro = 9;

  /// La corriente avanza más lento que las paredes: así se ve agua y no una textura pegada.
  static const double paralaje = 0.6;

  double _y(double metros) => yJugador + (metros - j.distancia) * pxPorM;

  // Pinceles fijos de este pintor.
  late final Paint _fondo = Paint()..color = p.suave;
  late final Paint _tinte = Paint()..color = colorAguas.withValues(alpha: 0.22);
  late final Paint _banda = Paint()..color = Color.lerp(p.suave, p.bordeFuerte, 0.3)!;
  late final Paint _anillo = Paint()..color = Color.lerp(p.suave, p.bordeFuerte, 0.65)!;
  late final Paint _linea = Paint()
    ..color = p.borde
    ..strokeWidth = 1;
  late final Paint _remache = Paint()..color = p.bordeFuerte;
  late final Paint _sarro = Paint()..color = colorAguas.withValues(alpha: 0.14);
  late final Paint _corriente = Paint()..strokeWidth = 1;
  late final Paint _pared = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  late final Paint _burbuja = Paint()
    ..color = p.bordeFuerte
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  late final Paint _bicho = Paint()..color = p.textoSuave;
  late final Paint _papel = Paint()..color = const Color(0xFFF7F3EA);
  late final Paint _dorado = Paint()..color = p.acento;
  late final Paint _bordeDorado = Paint()
    ..color = p.acentoTexto
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  late final Paint _bordeRollo = Paint()
    ..color = p.bordeFuerte
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  late final Paint _imagen = Paint()..filterQuality = FilterQuality.medium;
  late final Paint _codo = Paint()..color = p.primario;
  // Franjas de peligro: contra el relleno del codo, sea cual sea el tema (negro y amarillo en claro y en oscuro).
  late final Paint _franja = Paint()
    ..color = p.primario == p.acento ? p.sobrePrimario : p.acento
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.butt;
  late final Paint _bordeCodo = Paint()
    ..color = p.acento
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  late final Paint _alerta = Paint()..style = PaintingStyle.stroke;

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
    final todo = Rect.fromLTWH(x0, -20, tubo, alto + 40);
    canvas.drawRect(todo, _fondo);
    // La descarga tiñe el agua de marrón.
    final enDescarga = j.enDescarga;
    if (enDescarga) canvas.drawRect(todo, _tinte);
    final primera = (j.distancia / 3).floor() - 4;
    final cuantas = (alto / pxPorM / 3).ceil() + 8;
    _manchas(canvas, primera, cuantas);
    if (mov != Movimiento.nada) _agua(canvas, size, enDescarga);
    // Línea que separa los carriles, a trazos.
    final cx = x0 + tubo / 2;
    final paso = 1.2 * pxPorM;
    final corrido = (j.distancia * pxPorM) % paso;
    for (var y = -corrido; y < alto; y += paso) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + paso * 0.45), _linea);
    }
    // Paredes gruesas, con su borde interior.
    final der = x0 + tubo - muro;
    canvas.drawRect(Rect.fromLTWH(x0, -20, muro, alto + 40), _banda);
    canvas.drawRect(Rect.fromLTWH(der, -20, muro, alto + 40), _banda);
    canvas.drawLine(Offset(x0 + muro, -20), Offset(x0 + muro, alto + 20), _linea);
    canvas.drawLine(Offset(der, -20), Offset(der, alto + 20), _linea);
    // Cada 3 m una junta: anillo en las paredes, línea de lado a lado y remaches a mitad de tramo. Pasan hacia arriba.
    for (var k = primera; k < primera + cuantas; k++) {
      final y = _y(k * 3.0);
      if (y < -30 || y > alto + 30) continue;
      canvas.drawRect(Rect.fromLTWH(x0, y - 3, muro, 6), _anillo);
      canvas.drawRect(Rect.fromLTWH(der, y - 3, muro, 6), _anillo);
      canvas.drawLine(Offset(x0 + muro, y), Offset(der, y), _linea);
      final ym = _y(k * 3.0 + 1.5);
      canvas.drawRect(Rect.fromCenter(center: Offset(x0 + muro / 2, ym), width: 3, height: 3), _remache);
      canvas.drawRect(Rect.fromCenter(center: Offset(der + muro / 2, ym), width: 3, height: 3), _remache);
    }
    if (mov != Movimiento.nada) _adornos(canvas, size, primera, cuantas);
    _pared.color = enDescarga ? colorAguas : p.bordeFuerte;
    canvas.drawLine(Offset(x0, -20), Offset(x0, alto + 20), _pared);
    canvas.drawLine(Offset(x0 + tubo, -20), Offset(x0 + tubo, alto + 20), _pared);
  }

  // Sarro pegado a las paredes: fijo por tramo (hash), viaja con el tubo.
  void _manchas(Canvas canvas, int primera, int cuantas) {
    for (var k = primera; k < primera + cuantas; k++) {
      final h = (k * 2246822519) & 0xFFFF;
      if (h % 3 != 0) continue;
      final ancho = 3.0 + h % 6;
      final largo = (0.6 + (h % 5) * 0.35) * pxPorM;
      final x = h % 2 == 0 ? x0 + muro : x0 + tubo - muro - ancho;
      canvas.drawRect(Rect.fromLTWH(x, _y(k * 3.0 + (h % 11) * 0.25), ancho, largo), _sarro);
    }
  }

  // Corriente: rayas finas por carril que suben más lento que las paredes y se alargan con la velocidad.
  // Con movimiento simple van rectas; con completo además ondulan un poco.
  void _agua(Canvas canvas, Size size, bool enDescarga) {
    final v = j.velocidad;
    final f = ((v - JuegoTuberia.velocidadInicial) / (JuegoTuberia.velocidadMaxima - JuegoTuberia.velocidadInicial)).clamp(0.0, 1.0);
    _corriente.color = (enDescarga ? colorAguas : p.bordeFuerte).withValues(alpha: 0.14 + 0.3 * f);
    final largo = (0.4 + 1.8 * f) * pxPorM;
    final ondula = mov == Movimiento.completo;
    const paso = 1.7;
    final corrido = j.distancia * paralaje;
    final desde = ((corrido - yJugador / pxPorM) / paso).floor() - 2;
    final hasta = ((corrido + (size.height - yJugador) / pxPorM) / paso).ceil() + 1;
    final ancho = tubo / 2;
    for (var k = desde; k <= hasta; k++) {
      final y = yJugador + (k * paso - corrido) * pxPorM;
      for (var c = 0; c < 2; c++) {
        final h = ((k * 2 + c) * 40503) & 0xFFFF;
        if (h % 3 == 0) continue;
        final izq = c == 0 ? x0 + muro + 6 : x0 + ancho + 6;
        final der = c == 0 ? x0 + ancho - 6 : x0 + tubo - muro - 6;
        var x = izq + (h % 997) / 997 * (der - izq);
        if (ondula) x += sin(ef.fase * 2.2 + k * 1.3 + c) * 2;
        final yy = y + (h % 7) * 0.12 * pxPorM;
        canvas.drawLine(Offset(x, yy), Offset(x, yy + largo), _corriente);
      }
    }
  }

  // Burbujas y cucarachas: fijas por tramo (hash), sin azar por cuadro.
  void _adornos(Canvas canvas, Size size, int primera, int cuantas) {
    for (var k = primera; k < primera + cuantas; k++) {
      final h = (k * 2654435761) & 0xFFFF;
      final bx = x0 + muro + 8 + (h % 1000) / 1000 * (tubo - 2 * muro - 16);
      final lado = 2.0 + (h % 4);
      canvas.drawRect(Rect.fromCenter(center: Offset(bx, _y(k * 3.0 + (h % 7) * 0.3)), width: lado, height: lado), _burbuja);
      if (h % 5 == 0) {
        final izq = h % 2 == 0;
        final cx = izq ? x0 + muro / 2 : x0 + tubo - muro / 2;
        // Las cucarachas corren por la pared contra la corriente.
        final cy = _y(k * 3.0 + 1.5 + (ef.fase * 0.8) % 3);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 6, height: 10), _bicho);
        final dir = izq ? 1.0 : -1.0;
        canvas.drawLine(Offset(cx, cy - 5), Offset(cx + 3 * dir, cy - 10), _burbuja);
        canvas.drawLine(Offset(cx, cy - 5), Offset(cx - 1 * dir, cy - 10), _burbuja);
      }
    }
  }

  void _rollos(Canvas canvas, Size size) {
    final ancho = tubo / 2;
    final img = rollo;
    final lado = min(ancho * 0.45, 1.6 * pxPorM).clamp(22.0, 64.0);
    final completo = mov == Movimiento.completo;
    for (final r in j.rollos) {
      if (r.agarrado) continue;
      final y = _y(r.distancia);
      if (y < -lado || y > size.height + lado) continue;
      final cx = x0 + ancho * (r.carril + 0.5);
      canvas.save();
      canvas.translate(cx, y);
      // Gira un poco al caer si hay movimiento.
      if (completo) canvas.rotate(sin(ef.fase * 3 + r.distancia) * 0.25);
      if (r.dorado) {
        // El dorado lleva un cuadro de acento detrás, que late con movimiento completo.
        final s = lado * 1.05 * (completo ? 1 + 0.08 * sin(ef.fase * 6 + r.distancia) : 1.0);
        final fondo = Rect.fromCenter(center: Offset.zero, width: s, height: s);
        canvas.drawRect(fondo, _dorado);
        canvas.drawRect(fondo, _bordeDorado);
      }
      if (img != null) {
        final t = r.dorado ? lado * 0.85 : lado;
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromCenter(center: Offset.zero, width: t, height: t), _imagen);
      } else {
        // Mientras carga el PNG: cuadrado de papel con hueco.
        final t = lado * 0.62;
        final rect = Rect.fromCenter(center: Offset.zero, width: t, height: t);
        final hueco = Rect.fromCenter(center: Offset.zero, width: t * 0.34, height: t * 0.34);
        canvas.drawRect(rect, _papel);
        canvas.drawRect(rect, _bordeRollo);
        canvas.drawRect(hueco, _fondo);
        canvas.drawRect(hueco, _bordeRollo);
      }
      canvas.restore();
    }
  }

  void _codos(Canvas canvas, Size size) {
    final ancho = tubo / 2;
    final alto = JuegoTuberia.radioCodo * 2 * pxPorM;
    for (final c in j.codos) {
      final y = _y(c.distancia);
      if (y < -40 || y > size.height + 40) continue;
      final r = Rect.fromLTWH(x0 + c.carril * ancho, y - alto / 2, ancho, alto);
      canvas.drawRect(r, _codo);
      // Franjas de cinta de peligro a 45 grados, recortadas a la pieza: se lee como obstáculo y no como botón.
      canvas.save();
      canvas.clipRect(r);
      for (var x = r.left + 4; x < r.right + alto; x += 14) {
        canvas.drawLine(Offset(x, r.top), Offset(x - alto, r.bottom), _franja);
      }
      canvas.restore();
      canvas.drawRect(r, _bordeCodo);
      // El que viene por tu carril late para avisar.
      final dd = c.distancia - j.distancia;
      if (j.vivo && c.carril == j.carril && dd > 0 && dd < 9 && mov != Movimiento.nada) {
        final pulso = mov == Movimiento.completo ? 0.5 + 0.5 * sin(ef.fase * 18) : 1.0;
        _alerta.strokeWidth = 1 + 2 * pulso;
        _alerta.color = p.acento.withValues(alpha: 0.4 + 0.6 * (1 - dd / 9));
        canvas.drawRect(r.inflate(3 + 2 * pulso), _alerta);
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
      old.j != j || old.p != p || old.x0 != x0 || old.tubo != tubo || old.pxPorM != pxPorM || old.mov != mov || old.rollo != rollo;
}
