// Destapa: ritmo sin audio. Un anillo se cierra sobre el inodoro; tocas en el pulso. Lógica en destapa_logica.dart.

import 'dart:math' as m;

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'destapa_logica.dart';
import 'marco.dart';

class VistaDestapa extends StatefulWidget {
  const VistaDestapa({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});
  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Solo para pruebas.
  final JuegoDestapa? juego;

  @override
  State<VistaDestapa> createState() => _VistaDestapaState();
}

class _VistaDestapaState extends State<VistaDestapa> with SingleTickerProviderStateMixin {
  late final JuegoDestapa _j = widget.juego ?? JuegoDestapa();
  late final RelojJuego _reloj;
  final _sw = Stopwatch();
  bool _fin = false;
  double _sacudida = 0; // 1 recién fallado, baja a 0
  double _brillo = 0; // 1 recién acertado
  Golpe? _ultimo;

  @override
  void initState() {
    super.initState();
    _reloj = RelojJuego(this, _paso);
    _sw.start();
    _reloj.arrancar();
  }

  void _paso(double dt) {
    if (_fin) return;
    final antes = _j.paraPulso;
    final fallosAntes = _j.fallos;
    _j.avanzar(dt);
    // Latido: el pulso acaba de pasar. Vibración suave para jugar sin mirar.
    // sonido: aquí se engancha el "tic" del pulso cuando haya audio.
    if (antes > 0 && _j.paraPulso <= 0 && _j.fallos == fallosAntes) vibracionSuave();
    if (_j.fallos != fallosAntes) {
      _sacudida = 1;
      _ultimo = Golpe.fallo;
    }
    _sacudida = m.max(0, _sacudida - dt * 3);
    _brillo = m.max(0, _brillo - dt * 4);
    if (_j.terminado) {
      _fin = true;
      _reloj.parar();
      _sw.stop();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) widget.alTerminar(_j.puntos, _sw.elapsedMilliseconds);
      });
    }
    if (mounted) setState(() {});
  }

  void _toca() {
    if (_fin) return;
    final g = _j.toque();
    _ultimo = g;
    if (g == Golpe.fallo) {
      _sacudida = 1;
    } else {
      _brillo = 1;
      vibracionSuave();
      // sonido: aquí va el golpe del destapador (perfecto o bueno).
    }
    if (_j.terminado && !_fin) {
      _fin = true;
      _reloj.parar();
      _sw.stop();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) widget.alTerminar(_j.puntos, _sw.elapsedMilliseconds);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final animar = widget.mov != Movimiento.nada;
    final t = switch (_ultimo) {
      Golpe.perfecto => tr('PERFECTO', 'PERFECT'),
      Golpe.bueno => tr('BIEN', 'GOOD'),
      Golpe.fallo => tr('FALLO', 'MISS'),
      null => '',
    };
    final dx = animar ? m.sin(_sacudida * 30) * 6 * _sacudida : 0.0;
    return GestureDetector(
      key: const Key('destapa_toque'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _toca(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Text('${_j.puntos}', key: const Key('destapa_puntos'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.texto)),
            const Spacer(),
            Row(children: [
              for (var i = 0; i < JuegoDestapa.fallosMaximos; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Opacity(opacity: i < _j.fallos ? 0.25 : 1, child: const Emoji('🧻', tamano: 22)),
                ),
            ]),
          ]),
        ),
        Expanded(
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: CustomPaint(
              size: Size.infinite,
              foregroundPainter: _PintorDestapa(_j, p, _brillo, animar),
              child: Center(child: Padding(padding: const EdgeInsets.only(top: 80), child: Emoji('🚽', tamano: 72))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(children: [
            SizedBox(height: 22, child: Text(t, key: const Key('destapa_golpe'), style: TextStyle(fontWeight: FontWeight.w900, color: _ultimo == Golpe.fallo ? p.textoSuave : p.acento))),
            LinearProgressIndicator(
              value: _j.avance / _j.requiere,
              minHeight: 6,
              color: p.acento,
              backgroundColor: p.suave,
            ),
            const SizedBox(height: 6),
            Text(tr('Inodoros destapados: ${_j.inodoros}', 'Toilets unclogged: ${_j.inodoros}'), style: TextStyle(fontSize: 12, color: p.textoSuave)),
          ]),
        ),
      ]),
    );
  }
}

class _PintorDestapa extends CustomPainter {
  _PintorDestapa(this.j, this.p, this.brillo, this.animar);
  final JuegoDestapa j;
  final Paleta p;
  final double brillo;
  final bool animar;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 40);
    final objetivo = m.min(size.width, size.height) * 0.22;
    // Blanco fijo: donde hay que tocar.
    canvas.drawCircle(
      c,
      objetivo,
      Paint()
        ..color = p.acento
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Anillo que se cierra. Con las animaciones apagadas se queda en un número: el pulso se ve en el borde de color.
    final f = j.fase;
    final rr = objetivo + (1 - f) * objetivo * 1.6;
    canvas.drawCircle(
      c,
      animar ? rr : objetivo * (1 + (1 - f) * 0.3),
      Paint()
        ..color = Color.lerp(p.bordeFuerte, p.acento, f)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 3 * f,
    );
    if (brillo > 0) {
      canvas.drawCircle(c, objetivo * (1 + (1 - brillo) * 0.6), Paint()..color = p.acento.withValues(alpha: brillo * 0.35));
    }
    // El destapador baja con el avance del inodoro actual.
    final y = c.dy - objetivo * 1.5 + (j.avance / j.requiere) * objetivo * 0.9 - (brillo * 10);
    canvas.drawLine(Offset(c.dx, y - 60), Offset(c.dx, y), Paint()..color = p.textoSuave..strokeWidth = 4);
    canvas.drawArc(Rect.fromCenter(center: Offset(c.dx, y), width: 54, height: 30), 0, m.pi, true, Paint()..color = p.primario);
  }

  @override
  bool shouldRepaint(covariant _PintorDestapa old) => true;
}
