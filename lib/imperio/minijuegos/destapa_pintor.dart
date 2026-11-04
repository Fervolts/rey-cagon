// Destapa, dibujo: agua que sube con los fallos, el blanco cuadrado, los anillos que se cierran (y los de mantener),
// y las gotas que salpican. Todo con Paint reusados: se pinta 60 veces por segundo.

import 'dart:math' as m;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../tema.dart';
import 'destapa_logica.dart';

/// Azul del agua: la paleta no trae uno y el agua no puede ser amarilla.
const colorAgua = Color(0xFF3A86FF);

/// Dónde va el blanco dentro del área de juego. La vista lo usa para poner los emojis encima.
class GeoDestapa {
  GeoDestapa(Size s)
      : centro = Offset(s.width / 2, s.height * 0.5),
        lado = m.min(s.width * 0.62, s.height * 0.42).clamp(80.0, 320.0);
  final Offset centro;
  final double lado;
}

/// Una gota de la salpicadura, relativa al centro del blanco.
class Gota {
  Gota(this.x, this.y, this.vx, this.vy, this.tam, this.dorada);
  double x, y, vx, vy, vida = 1;
  final double tam;
  final bool dorada;
}

/// Gotas vivas, con tope para que nunca pese.
class Salpicadura {
  static const maximo = 40;
  final gotas = <Gota>[];
  final _azar = m.Random();

  void soltar(int n, {bool dorada = false, double fuerza = 1}) {
    for (var i = 0; i < n && gotas.length < maximo; i++) {
      final a = -m.pi / 2 + (_azar.nextDouble() - 0.5) * 2.2;
      final v = (220 + _azar.nextDouble() * 260) * fuerza;
      gotas.add(Gota(0, 0, m.cos(a) * v, m.sin(a) * v, 4 + _azar.nextDouble() * 4, dorada && i.isEven));
    }
  }

  void avanzar(double dt) {
    for (final g in gotas) {
      g.vy += 1100 * dt;
      g.x += g.vx * dt;
      g.y += g.vy * dt;
      g.vida -= dt * 1.4;
    }
    gotas.removeWhere((g) => g.vida <= 0);
  }
}

class PintorDestapa extends CustomPainter {
  PintorDestapa({required this.j, required this.p, required this.mov, required this.agua, required this.bump, required this.gotas});
  final JuegoDestapa j;
  final Paleta p;
  final Movimiento mov;

  /// 0 sin fallos, 1 desbordado (suavizado por la vista).
  final double agua;

  /// 1 recién acertado perfecto: el blanco late.
  final double bump;
  final Salpicadura gotas;

  static final _relleno = Paint();
  static final _trazo = Paint()..style = PaintingStyle.stroke;
  static final _ola = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final g = GeoDestapa(size);
    final c = g.centro;
    final completo = mov == Movimiento.completo;

    // Agua: sube con cada fallo. Con todo el movimiento, con olas.
    final nivel = size.height * (1 - (0.08 + 0.62 * agua));
    _relleno.color = colorAgua.withValues(alpha: 0.16 + 0.14 * agua);
    if (completo) {
      _ola.reset();
      _ola.moveTo(0, size.height);
      for (var x = 0.0; x <= size.width + 8; x += 8) {
        _ola.lineTo(x, nivel + m.sin(x / 34 + j.tiempo * 3) * (3 + 5 * agua));
      }
      _ola.lineTo(size.width, size.height);
      _ola.close();
      canvas.drawPath(_ola, _relleno);
    } else {
      canvas.drawRect(Rect.fromLTRB(0, nivel, size.width, size.height), _relleno);
    }
    _trazo
      ..color = colorAgua.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, nivel), Offset(size.width, nivel), _trazo);

    // Blanco fijo: un cuadrado. En el atasco gordo, doble borde.
    final lado = g.lado * (completo ? 1 + 0.06 * bump : 1);
    final blanco = Rect.fromCenter(center: c, width: lado, height: lado);
    _trazo
      ..color = p.acento
      ..strokeWidth = j.esJefe ? 3 : 2;
    canvas.drawRect(blanco, _trazo);
    if (j.esJefe) canvas.drawRect(blanco.inflate(5), _trazo..strokeWidth = 1);

    // Mantener: el blanco se va llenando de abajo arriba mientras el dedo aguanta.
    final h = j.mantenida;
    if (h != null) {
      final f = ((j.tiempo - h.t) / (h.fin! - h.t)).clamp(0.0, 1.0);
      _relleno.color = p.acento.withValues(alpha: 0.35);
      canvas.drawRect(Rect.fromLTRB(blanco.left, blanco.bottom - blanco.height * f, blanco.right, blanco.bottom), _relleno);
    }

    // Anillos: cada nota que viene es un cuadrado que se cierra sobre el blanco. Llega justo a su hora.
    const ver = JuegoDestapa.verAntes;
    for (final n in j.notas) {
      final falta = n.t - j.tiempo;
      if (falta > ver) break;
      if (n.estado == EstadoNota.pendiente && falta > -0.12) {
        _anillo(canvas, c, g.lado, falta, n.mantener ? 4.0 : 2.5, n.mantener);
      }
      // El fin de una nota de mantener: un anillo fino que dice cuándo soltar.
      final fin = n.fin;
      if (fin != null && (n.estado == EstadoNota.pendiente || n.estado == EstadoNota.manteniendo)) {
        final ff = fin - j.tiempo;
        if (ff <= ver && ff > 0) _anillo(canvas, c, g.lado, ff, 1, false);
      }
    }

    // Gotas.
    for (final d in gotas.gotas) {
      _relleno.color = (d.dorada ? p.acento : colorAgua).withValues(alpha: d.vida.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromCenter(center: c + Offset(d.x, d.y - g.lado * 0.2), width: d.tam, height: d.tam), _relleno);
    }
  }

  void _anillo(Canvas canvas, Offset c, double lado, double falta, double grosor, bool doble) {
    final f = (1 - falta / JuegoDestapa.verAntes).clamp(0.0, 1.0); // 0 lejos, 1 en la hora
    final l = lado * (1 + (1 - f) * 1.5) * (falta < 0 ? 1 + falta * 0.8 : 1);
    final r = Rect.fromCenter(center: c, width: l, height: l);
    _trazo
      ..color = Color.lerp(p.bordeFuerte, p.acento, ui.clampDouble(f * f, 0, 1))!.withValues(alpha: 0.3 + 0.7 * f)
      ..strokeWidth = grosor;
    canvas.drawRect(r, _trazo);
    if (doble) canvas.drawRect(r.deflate(6), _trazo..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant PintorDestapa old) => true;
}
