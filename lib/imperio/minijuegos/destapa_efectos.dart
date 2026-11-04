// Destapa, efectos baratos para el CustomPainter: gotas y chispas (con tope y reciclaje), letreros que flotan, cosas que
// salen volando (el patito hacia la tribuna, el celular, la cucaracha), manchas que se secan, destello y sacudida.
// Nada de widgets: se mueven con [EfectosDestapa.avanzar] y se pintan con [EfectosDestapa.pintar].
// Con Movimiento.nada no hay partículas, voladores ni sacudida y los letreros no suben; con simple solo lo barato
// (destello, letreros, voladores).

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../animaciones.dart';

class _Particula {
  double x = 0, y = 0, vx = 0, vy = 0, vida = 0, total = 1, tam = 3, gravedad = 500;
  bool redonda = true;
  Color color = const Color(0xFFFFFFFF);
}

class _Letrero {
  _Letrero(this.tp, this.x, this.y, this.total);
  final TextPainter tp;
  double x, y, vida = 0;
  final double total;
}

class _Volador {
  ui.Image? img;
  double x = 0, y = 0, vx = 0, vy = 0, giro = 0, vgiro = 0, tam = 30, vida = 0, total = 1, gravedad = 0, crece = 0;
  Color color = const Color(0xFF8B5A2B);
}

class _Mancha {
  _Mancha(this.x, this.y, this.tam);
  final double x, y, tam;
  double vida = 0;
}

class EfectosDestapa {
  EfectosDestapa(this.mov);

  final Movimiento mov;
  static const int maxParticulas = 140;
  static const int maxLetreros = 7;
  static const int maxVoladores = 8;

  final _azar = Random();
  final List<_Particula> _parts = [];
  final List<_Particula> _libres = [];
  final List<_Letrero> _letreros = [];
  final List<_Volador> _voladores = [];
  final List<_Mancha> _manchas = [];
  final _pinta = Paint();
  final _pintaImg = Paint()..filterQuality = FilterQuality.medium;
  final _capa = Paint();

  double _flash = 0;
  Color _colorFlash = const Color(0xFFFFFFFF);
  double _sacudida = 0;
  Offset _off = Offset.zero;

  /// Reloj propio de los efectos (sigue corriendo al terminar).
  double fase = 0;

  bool get completo => mov == Movimiento.completo;
  bool get anima => mov != Movimiento.nada;

  /// Desplazamiento de la sacudida en este cuadro (se sortea una vez por cuadro en [avanzar]).
  Offset get sacudida => _off;

  /// Salpicón: [n] gotas o chispas que salen de [en].
  void salpicar(Offset en, Color color, int n,
      {double fuerza = 180, double arriba = 120, double tam = 4, bool redonda = true, double gravedad = 520, double abanico = pi * 2}) {
    if (!completo) return;
    for (var i = 0; i < n; i++) {
      if (_parts.length >= maxParticulas) _libres.add(_parts.removeAt(0));
      final c = _libres.isEmpty ? _Particula() : _libres.removeLast();
      final ang = -pi / 2 + (_azar.nextDouble() - 0.5) * abanico;
      final f = fuerza * (0.35 + _azar.nextDouble() * 0.65);
      c
        ..x = en.dx
        ..y = en.dy
        ..vx = cos(ang) * f
        ..vy = sin(ang) * f - arriba
        ..vida = 0
        ..total = 0.45 + _azar.nextDouble() * 0.4
        ..tam = tam * (0.6 + _azar.nextDouble() * 0.8)
        ..gravedad = gravedad
        ..redonda = redonda
        ..color = color;
      _parts.add(c);
    }
  }

  /// Texto que sube y se desvanece donde pasó algo. El TextPainter se arma una sola vez.
  void letrero(String texto, Offset en, Color color, {double tam = 18, Color? fondo, double dura = 0.85}) {
    if (_letreros.length >= maxLetreros) _letreros.removeAt(0);
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: color,
          fontSize: tam,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          background: fondo == null ? null : (Paint()..color = fondo),
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: fondo == null ? const [Shadow(color: Color(0xAA000000), offset: Offset(0, 2))] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _letreros.add(_Letrero(tp, en.dx - tp.width / 2, en.dy - tp.height / 2, dura));
  }

  /// Algo que sale volando con su dibujo ([img] puede faltar si el PNG no cargó: entonces un cuadrito de [color]).
  void volar(ui.Image? img, Offset desde, Offset vel,
      {double tam = 40, double giro = 0, double vgiro = 0, double gravedad = 0, double total = 1, double crece = 0, Color? color}) {
    if (!anima) return;
    if (_voladores.length >= maxVoladores) _voladores.removeAt(0);
    _voladores.add(_Volador()
      ..img = img
      ..x = desde.dx
      ..y = desde.dy
      ..vx = vel.dx
      ..vy = vel.dy
      ..tam = tam
      ..giro = giro
      ..vgiro = vgiro
      ..gravedad = gravedad
      ..total = total
      ..crece = crece
      ..color = color ?? const Color(0xFF8B5A2B));
  }

  /// Mancha en el piso o en la porcelana que se seca sola.
  void mancha(Offset en, double tam) {
    if (_manchas.length >= 6) _manchas.removeAt(0);
    _manchas.add(_Mancha(en.dx, en.dy, tam));
  }

  void destello(Color color, double fuerza) {
    if (!anima) return;
    _colorFlash = color;
    _flash = max(_flash, fuerza.clamp(0.0, 1.0));
  }

  void sacudir(double px) {
    if (!completo) return;
    _sacudida = max(_sacudida, px);
  }

  void avanzar(double dt) {
    fase += dt;
    if (_flash > 0) _flash = max(0, _flash - dt * 3.0);
    if (_sacudida > 0) _sacudida = max(0, _sacudida - _sacudida * dt * 8 - dt * 4);
    _off = _sacudida < 0.3 ? Offset.zero : Offset((_azar.nextDouble() * 2 - 1) * _sacudida, (_azar.nextDouble() * 2 - 1) * _sacudida);
    for (var i = _parts.length - 1; i >= 0; i--) {
      final c = _parts[i];
      c.vida += dt;
      if (c.vida >= c.total) {
        _libres.add(_parts.removeAt(i));
        continue;
      }
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      c.vx *= 1 - dt * 2.2;
      c.vy += c.gravedad * dt;
    }
    for (var i = _letreros.length - 1; i >= 0; i--) {
      final l = _letreros[i];
      l.vida += dt;
      if (l.vida >= l.total) {
        _letreros.removeAt(i);
        continue;
      }
      if (anima) l.y -= 40 * dt;
    }
    for (var i = _voladores.length - 1; i >= 0; i--) {
      final v = _voladores[i];
      v.vida += dt;
      if (v.vida >= v.total) {
        _voladores.removeAt(i);
        continue;
      }
      v.x += v.vx * dt;
      v.y += v.vy * dt;
      v.vy += v.gravedad * dt;
      v.giro += v.vgiro * dt;
      v.tam = max(2, v.tam + v.crece * dt);
    }
    for (var i = _manchas.length - 1; i >= 0; i--) {
      _manchas[i].vida += dt;
      if (_manchas[i].vida > 2.5) _manchas.removeAt(i);
    }
  }

  /// Manchas (van debajo de todo lo que se mueve).
  void pintarManchas(Canvas canvas) {
    for (final s in _manchas) {
      final a = (1 - s.vida / 2.5).clamp(0.0, 1.0);
      _pinta.color = Color.fromRGBO(70, 40, 20, 0.55 * a);
      canvas.drawOval(Rect.fromCenter(center: Offset(s.x, s.y), width: s.tam, height: s.tam * 0.45), _pinta);
      _pinta.color = Color.fromRGBO(150, 100, 55, 0.5 * a);
      canvas.drawOval(Rect.fromCenter(center: Offset(s.x + s.tam * 0.12, s.y - 1), width: s.tam * 0.35, height: s.tam * 0.16), _pinta);
    }
  }

  /// Partículas, voladores y letreros (en coordenadas de pantalla, antes del destello).
  void pintar(Canvas canvas) {
    for (final c in _parts) {
      final a = 1 - c.vida / c.total;
      _pinta.color = c.color.withValues(alpha: c.color.a * a);
      final t = c.tam * (0.5 + 0.5 * a);
      if (c.redonda) {
        canvas.drawCircle(Offset(c.x, c.y), t / 2, _pinta);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset(c.x, c.y), width: t, height: t), _pinta);
      }
    }
    for (final v in _voladores) {
      final a = (1 - v.vida / v.total).clamp(0.0, 1.0);
      final fade = a < 0.25 ? a / 0.25 : 1.0;
      canvas.save();
      canvas.translate(v.x, v.y);
      canvas.rotate(v.giro);
      final r = Rect.fromCenter(center: Offset.zero, width: v.tam, height: v.tam);
      final img = v.img;
      if (img != null) {
        _pintaImg.color = Color.fromRGBO(0, 0, 0, fade);
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r, _pintaImg);
      } else {
        _pinta.color = v.color.withValues(alpha: fade);
        canvas.drawRect(r.deflate(v.tam * 0.15), _pinta);
      }
      canvas.restore();
    }
    for (final l in _letreros) {
      final a = (1 - l.vida / l.total).clamp(0.0, 1.0);
      final fade = a < 0.35 ? a / 0.35 : 1.0;
      // Entra con un pequeño salto de escala.
      final s = l.vida < 0.08 ? 0.7 + l.vida / 0.08 * 0.5 : (l.vida < 0.16 ? 1.2 - (l.vida - 0.08) / 0.08 * 0.2 : 1.0);
      final c = Offset(l.x + l.tp.width / 2, l.y + l.tp.height / 2);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      if (anima) canvas.scale(s);
      if (fade < 0.99) {
        _capa.color = Color.fromRGBO(0, 0, 0, fade);
        canvas.saveLayer(Rect.fromCenter(center: Offset.zero, width: l.tp.width + 8, height: l.tp.height + 8), _capa);
        l.tp.paint(canvas, Offset(-l.tp.width / 2, -l.tp.height / 2));
        canvas.restore();
      } else {
        l.tp.paint(canvas, Offset(-l.tp.width / 2, -l.tp.height / 2));
      }
      canvas.restore();
    }
  }

  /// El destello cubre todo: va al final.
  void pintarDestello(Canvas canvas, Size size) {
    if (_flash <= 0.01) return;
    _pinta.color = _colorFlash.withValues(alpha: 0.4 * _flash);
    canvas.drawRect(Offset.zero & size, _pinta);
  }
}
