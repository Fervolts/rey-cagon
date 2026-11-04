// Tubería Express, efectos baratos para el CustomPainter: chispas cuadradas (con tope), letreros que flotan, destello de
// pantalla, sacudida y el "brinco" del mojón al agarrar un rollo. Nada de widgets: se mueven con [EfectosTuberia.avanzar]
// y se pintan con [EfectosTuberia.pintar]. Con Movimiento.nada no hay chispas ni sacudida y los letreros no se mueven;
// con simple solo destello, brinco y letreros.

import 'dart:math';

import 'package:flutter/painting.dart';

import '../../animaciones.dart';

class _Chispa {
  double x = 0, y = 0, vx = 0, vy = 0, vida = 0, total = 1, tam = 3;
  Color color = const Color(0xFFFFFFFF);
}

class _Letrero {
  _Letrero(this.tp, this.x, this.y, this.total);
  final TextPainter tp;
  double x, y, vida = 0;
  final double total;
}

class EfectosTuberia {
  EfectosTuberia(this.mov);

  final Movimiento mov;
  static const int maxChispas = 90;
  static const int maxLetreros = 6;

  final _azar = Random();
  final List<_Chispa> _chispas = [];
  final List<_Chispa> _libres = [];
  final List<_Letrero> _letreros = [];
  final _pinta = Paint();

  double _flash = 0;
  Color _colorFlash = const Color(0xFFFFFFFF);
  double _sacudida = 0;

  /// 1 justo al agarrar algo, baja a 0: el mojón crece un poco.
  double brinco = 0;

  /// Reloj propio para pulsos (codo peligroso, letreros). Sigue corriendo después del choque.
  double fase = 0;

  bool get completo => mov == Movimiento.completo;
  bool get anima => mov != Movimiento.nada;

  /// Desplazamiento de la sacudida en este cuadro (cero si no hay). Se sortea una vez por cuadro en [avanzar].
  Offset get sacudida => _off;
  Offset _off = Offset.zero;

  void chispas(Offset en, Color color, int n, {double fuerza = 140, double arriba = 0, double tam = 3}) {
    if (!completo) return;
    for (var i = 0; i < n; i++) {
      if (_chispas.length >= maxChispas) _libres.add(_chispas.removeAt(0));
      final c = _libres.isEmpty ? _Chispa() : _libres.removeLast();
      final ang = _azar.nextDouble() * pi * 2;
      final f = fuerza * (0.4 + _azar.nextDouble() * 0.6);
      c
        ..x = en.dx
        ..y = en.dy
        ..vx = cos(ang) * f
        ..vy = sin(ang) * f - arriba
        ..vida = 0
        ..total = 0.35 + _azar.nextDouble() * 0.35
        ..tam = tam * (0.6 + _azar.nextDouble() * 0.8)
        ..color = color;
      _chispas.add(c);
    }
  }

  /// Una gota que se queda atrás (la estela del mojón).
  void gota(Offset en, Color color, double subir) {
    if (!completo) return;
    if (_chispas.length >= maxChispas) _libres.add(_chispas.removeAt(0));
    final c = _libres.isEmpty ? _Chispa() : _libres.removeLast();
    c
      ..x = en.dx + (_azar.nextDouble() * 2 - 1) * 4
      ..y = en.dy
      ..vx = 0
      ..vy = -subir
      ..vida = 0
      ..total = 0.45
      ..tam = 3 + _azar.nextDouble() * 2
      ..color = color;
    _chispas.add(c);
  }

  /// Texto que sube y se desvanece donde pasó algo. El TextPainter se arma una sola vez.
  void letrero(String texto, Offset en, Color color, {double tam = 16, Color? fondo}) {
    if (_letreros.length >= maxLetreros) _letreros.removeAt(0);
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          color: color,
          fontSize: tam,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          background: fondo == null ? null : (Paint()..color = fondo),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _letreros.add(_Letrero(tp, en.dx - tp.width / 2, en.dy - tp.height / 2, anima ? 0.8 : 0.6));
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

  void agarro() {
    if (anima) brinco = 1;
  }

  void avanzar(double dt) {
    fase += dt;
    if (_flash > 0) _flash = max(0, _flash - dt * 3.2);
    if (_sacudida > 0) _sacudida = max(0, _sacudida - _sacudida * dt * 9 - dt * 4);
    _off = _sacudida < 0.3 ? Offset.zero : Offset((_azar.nextDouble() * 2 - 1) * _sacudida, (_azar.nextDouble() * 2 - 1) * _sacudida);
    if (brinco > 0) brinco = max(0, brinco - dt * 5);
    for (var i = _chispas.length - 1; i >= 0; i--) {
      final c = _chispas[i];
      c.vida += dt;
      if (c.vida >= c.total) {
        _libres.add(_chispas.removeAt(i));
        continue;
      }
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      c.vx *= 1 - dt * 3;
      c.vy = c.vy * (1 - dt * 3) + 260 * dt;
    }
    for (var i = _letreros.length - 1; i >= 0; i--) {
      final l = _letreros[i];
      l.vida += dt;
      if (l.vida >= l.total) {
        _letreros.removeAt(i);
        continue;
      }
      if (anima) l.y -= 46 * dt;
    }
  }

  /// Chispas y letreros (en coordenadas de pantalla, antes del destello).
  void pintar(Canvas canvas) {
    for (final c in _chispas) {
      final a = 1 - c.vida / c.total;
      _pinta.color = c.color.withValues(alpha: c.color.a * a);
      final t = c.tam * (0.5 + 0.5 * a);
      canvas.drawRect(Rect.fromCenter(center: Offset(c.x, c.y), width: t, height: t), _pinta);
    }
    for (final l in _letreros) {
      final a = (1 - l.vida / l.total).clamp(0.0, 1.0);
      if (a < 0.99) {
        canvas.saveLayer(Rect.fromLTWH(l.x - 2, l.y - 2, l.tp.width + 4, l.tp.height + 4), Paint()..color = Color.fromRGBO(0, 0, 0, a));
        l.tp.paint(canvas, Offset(l.x, l.y));
        canvas.restore();
      } else {
        l.tp.paint(canvas, Offset(l.x, l.y));
      }
    }
  }

  /// El destello cubre todo: va al final.
  void pintarDestello(Canvas canvas, Size size) {
    if (_flash <= 0.01) return;
    _pinta.color = _colorFlash.withValues(alpha: 0.45 * _flash);
    canvas.drawRect(Offset.zero & size, _pinta);
  }

  bool get quieto => _chispas.isEmpty && _letreros.isEmpty && _flash <= 0 && _sacudida <= 0 && brinco <= 0;
}
