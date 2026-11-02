// Efecto del botón CAGUÉ comprado en la tienda de estilo (lib/imperio/tienda_estilo.dart). Solo lo ves tú.
// Va en su propia capa del overlay, debajo del inodoro (se inserta antes) y sin tocar el dedo: no tapa ni atrasa la
// animación del mojón. Con movimiento "nada" no sale; con "simple" sale una versión corta con pocas piezas.
import 'dart:math';

import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'imperio/estilos.dart';
import 'imperio/estilos_mios.dart' show efectoElegido;
import 'tema.dart';

/// Lanza el efecto elegido (si hay) alrededor del botón [boton] (en coordenadas globales). No espera a que termine.
void lanzarEfectoCague(BuildContext context, {required Rect boton, String? id}) {
  final efecto = id ?? efectoElegido.value;
  if (efecto == efectoNinguno || estiloPorId(efecto)?.tipo != TipoEstilo.efecto) return;
  final nivel = movimiento(context);
  if (nivel == Movimiento.nada) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final caja = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || caja == null || !caja.hasSize) return;
  final local = caja.globalToLocal(boton.topLeft) & boton.size;
  late final OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _Efecto(
        id: efecto,
        simple: nivel == Movimiento.simple,
        boton: local,
        acento: acento,
        alTerminar: () {
          if (entrada.mounted) entrada.remove();
        },
      ),
    ),
  );
  overlay.insert(entrada);
}

class _Efecto extends StatefulWidget {
  const _Efecto({required this.id, required this.simple, required this.boton, required this.acento, required this.alTerminar});

  final String id;
  final bool simple;
  final Rect boton;
  final Color acento;
  final VoidCallback alTerminar;

  @override
  State<_Efecto> createState() => _EfectoState();
}

class _EfectoState extends State<_Efecto> with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  late final List<_Pieza> _piezas;
  final _azar = Random();

  @override
  void initState() {
    super.initState();
    final ms = switch (widget.id) {
      'efecto_rayo' => 700,
      'efecto_fuegos' => 1700,
      _ => 1300,
    };
    _t = AnimationController(vsync: this, duration: Duration(milliseconds: widget.simple ? ms * 2 ~/ 3 : ms));
    _piezas = _armar();
    _t.forward().whenCompleteOrCancel(widget.alTerminar);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  List<Color> get _colores => [widget.acento, const Color(0xFFFF4D6D), const Color(0xFF3AB0FF), const Color(0xFF7BE36B), Colors.white];

  List<_Pieza> _armar() {
    final n = widget.simple ? 14 : 48;
    final colores = _colores;
    switch (widget.id) {
      case 'efecto_confeti':
        // Sale del botón hacia arriba en abanico y cae con gravedad.
        return [
          for (var i = 0; i < n; i++)
            _Pieza(
              angulo: -pi / 2 + (_azar.nextDouble() - .5) * pi * .9,
              rapidez: 380 + _azar.nextDouble() * 520,
              giro: (_azar.nextDouble() - .5) * 14,
              tam: 5 + _azar.nextDouble() * 5,
              color: colores[i % colores.length],
            ),
        ];
      case 'efecto_papel':
        // Hojas de papel en todas direcciones, más lentas y grandes.
        return [
          for (var i = 0; i < n * 2 ~/ 3; i++)
            _Pieza(
              angulo: _azar.nextDouble() * 2 * pi,
              rapidez: 160 + _azar.nextDouble() * 360,
              giro: (_azar.nextDouble() - .5) * 8,
              tam: 10 + _azar.nextDouble() * 10,
              color: i.isEven ? Colors.white : const Color(0xFFF1EFE8),
            ),
        ];
      case 'efecto_remolino':
        return [
          for (var i = 0; i < n; i++)
            _Pieza(
              angulo: i / n * 2 * pi,
              rapidez: 70 + _azar.nextDouble() * 110,
              giro: 0,
              tam: 4 + _azar.nextDouble() * 4,
              color: colores[i % 3],
            ),
        ];
      case 'efecto_fuegos':
        // Tres cohetes (uno en simple) que revientan en un círculo de chispas.
        final cohetes = widget.simple ? 1 : 3;
        final porCohete = widget.simple ? 14 : 22;
        return [
          for (var c = 0; c < cohetes; c++)
            for (var i = 0; i < porCohete; i++)
              _Pieza(
                angulo: i / porCohete * 2 * pi,
                rapidez: 90 + _azar.nextDouble() * 40,
                giro: c.toDouble(),
                tam: 3.5,
                color: colores[(c * 2) % colores.length],
              ),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _Pintor(id: widget.id, simple: widget.simple, boton: widget.boton, acento: widget.acento, piezas: _piezas, t: _t),
      ),
    );
  }
}

class _Pieza {
  const _Pieza({required this.angulo, required this.rapidez, required this.giro, required this.tam, required this.color});

  final double angulo, rapidez, giro, tam;
  final Color color;
}

class _Pintor extends CustomPainter {
  _Pintor({required this.id, required this.simple, required this.boton, required this.acento, required this.piezas, required this.t})
      : super(repaint: t);

  final String id;
  final bool simple;
  final Rect boton;
  final Color acento;
  final List<_Pieza> piezas;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    switch (id) {
      case 'efecto_confeti':
        _volar(canvas, v, gravedad: 900, segundos: 1.3, alto: .45);
      case 'efecto_papel':
        _volar(canvas, v, gravedad: 260, segundos: 1.3, alto: .7);
      case 'efecto_rayo':
        _rayo(canvas, size, v);
      case 'efecto_remolino':
        _remolino(canvas, v);
      case 'efecto_fuegos':
        _fuegos(canvas, size, v);
    }
  }

  // Piezas que salen del centro del botón con una rapidez y caen. [alto] = proporción ancho/alto del rectángulo.
  void _volar(Canvas canvas, double v, {required double gravedad, required double segundos, required double alto}) {
    final s = v * segundos;
    final opacidad = v < .7 ? 1.0 : (1 - v) / .3;
    final pincel = Paint();
    final c = boton.center;
    for (final p in piezas) {
      final x = c.dx + cos(p.angulo) * p.rapidez * s;
      final y = c.dy + sin(p.angulo) * p.rapidez * s + gravedad * s * s / 2;
      pincel.color = p.color.withValues(alpha: opacidad);
      canvas.save();
      canvas.translate(x, y);
      if (!simple) canvas.rotate(p.giro * s);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.tam, height: p.tam * alto), pincel);
      if (alto > .6) {
        // Hoja de papel: un borde para que se vea sobre fondos claros.
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.tam, height: p.tam * alto),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF999999).withValues(alpha: opacidad),
        );
      }
      canvas.restore();
    }
  }

  // Un rayo en zigzag del borde de arriba al botón y un destello que se apaga.
  void _rayo(Canvas canvas, Size size, double v) {
    final fuerza = v < .15 ? v / .15 : (1 - v) / .85;
    if (!simple) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: .35 * fuerza));
    final azar = Random(7);
    final c = boton.center;
    final camino = Path()..moveTo(c.dx + (azar.nextDouble() - .5) * 120, 0);
    const pasos = 7;
    for (var i = 1; i <= pasos; i++) {
      final f = i / pasos;
      final x = i == pasos ? c.dx : c.dx + (azar.nextDouble() - .5) * 90 * (1 - f);
      camino.lineTo(x, c.dy * f);
    }
    canvas.drawPath(
      camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = simple ? 4 : 7
        ..strokeJoin = StrokeJoin.miter
        ..color = acento.withValues(alpha: fuerza),
    );
    canvas.drawPath(
      camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: fuerza),
    );
  }

  // Piezas que giran en espiral hacia el botón, como el agua al jalar la cadena.
  void _remolino(Canvas canvas, double v) {
    final c = boton.center;
    final opacidad = v < .8 ? 1.0 : (1 - v) / .2;
    final pincel = Paint();
    final radioInicial = boton.shortestSide / 2 + 20;
    for (final p in piezas) {
      final r = (radioInicial + p.rapidez) * (1 - Curves.easeIn.transform(v));
      final a = p.angulo + v * (simple ? 3 : 5) * pi;
      pincel.color = p.color.withValues(alpha: opacidad);
      canvas.drawRect(Rect.fromCenter(center: c + Offset(cos(a) * r, sin(a) * r), width: p.tam, height: p.tam), pincel);
    }
  }

  // Cohetes que suben del botón y revientan arriba (giro = número de cohete).
  void _fuegos(Canvas canvas, Size size, double v) {
    final c = boton.center;
    final cohetes = piezas.isEmpty ? 0 : piezas.map((p) => p.giro).reduce(max).toInt() + 1;
    final pincel = Paint();
    for (var k = 0; k < cohetes; k++) {
      final inicio = k * .18;
      final local = ((v - inicio) / (1 - inicio * 1.2)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final destino = Offset(size.width * (cohetes == 1 ? .5 : .25 + k * .25), size.height * (.18 + (k % 2) * .1));
      if (local < .35) {
        final f = Curves.easeOut.transform(local / .35);
        pincel.color = Colors.white;
        canvas.drawRect(Rect.fromCenter(center: Offset.lerp(c, destino, f)!, width: 3, height: 9), pincel);
        continue;
      }
      final e = (local - .35) / .65;
      final opacidad = 1 - e;
      for (final p in piezas) {
        if (p.giro.toInt() != k) continue;
        final r = p.rapidez * Curves.easeOut.transform(e);
        final punto = destino + Offset(cos(p.angulo) * r, sin(p.angulo) * r + 40 * e * e);
        pincel.color = p.color.withValues(alpha: opacidad);
        canvas.drawRect(Rect.fromCenter(center: punto, width: p.tam, height: p.tam), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_Pintor viejo) => false;
}
