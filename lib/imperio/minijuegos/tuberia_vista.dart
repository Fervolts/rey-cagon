// Tubería Express: el mojón baja por el desagüe; un toque cambia de lado. Lógica en tuberia_logica.dart.

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'marco.dart';
import 'tuberia_logica.dart';

class VistaTuberia extends StatefulWidget {
  const VistaTuberia({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});
  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Solo para pruebas: una partida ya armada.
  final JuegoTuberia? juego;

  @override
  State<VistaTuberia> createState() => _VistaTuberiaState();
}

class _VistaTuberiaState extends State<VistaTuberia> with SingleTickerProviderStateMixin {
  late final JuegoTuberia _j = widget.juego ?? JuegoTuberia();
  late final RelojJuego _reloj;
  final _tic = _Aviso();
  final _sw = Stopwatch();
  int _ultimoPuntos = -1;
  bool _fin = false;

  @override
  void initState() {
    super.initState();
    _reloj = RelojJuego(this, _paso);
    _sw.start();
    _reloj.arrancar();
  }

  void _paso(double dt) {
    if (_fin) return;
    _j.avanzar(dt);
    _tic.avisar();
    if (_j.puntos != _ultimoPuntos) {
      setState(() => _ultimoPuntos = _j.puntos);
    }
    if (_j.terminado) {
      _fin = true;
      _reloj.parar();
      _sw.stop();
      // Un instante para ver el choque.
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) widget.alTerminar(_j.puntos, _sw.elapsedMilliseconds);
      });
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    _tic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return GestureDetector(
      key: const Key('tuberia_toque'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (!_fin) _j.toque();
      },
      child: LayoutBuilder(builder: (context, c) {
        final ancho = c.maxWidth, alto = c.maxHeight;
        final tubo = (ancho * 0.8).clamp(160.0, 420.0);
        final x0 = (ancho - tubo) / 2;
        final yJugador = alto * 0.28;
        final pxPorM = (alto * 0.72) / 18;
        return Stack(children: [
          Positioned.fill(
            child: CustomPaint(painter: _PintorTubo(_j, _tic, p, x0, tubo, yJugador, pxPorM, widget.mov != Movimiento.nada)),
          ),
          AnimatedBuilder(
            animation: _tic,
            builder: (context, _) {
              final cx = x0 + tubo * (0.25 + 0.5 * _j.posicion);
              return Positioned(left: cx - 16, top: yJugador - 16, child: Opacity(opacity: _j.terminado ? 0.4 : 1, child: const Emoji('💩', tamano: 32)));
            },
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Text('${_j.puntos} m', key: const Key('tuberia_metros'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: p.texto)),
            ),
          ),
          if (_j.toques == 0 && !_j.terminado)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(child: Text(tr('Toca la pantalla', 'Tap the screen'), style: TextStyle(color: p.textoSuave))),
            ),
        ]);
      }),
    );
  }
}

class _Aviso extends ChangeNotifier {
  void avisar() => notifyListeners();
}

class _PintorTubo extends CustomPainter {
  _PintorTubo(this.j, Listenable repintar, this.p, this.x0, this.tubo, this.yJugador, this.pxPorM, this.decorar) : super(repaint: repintar);
  final JuegoTuberia j;
  final Paleta p;
  final double x0, tubo, yJugador, pxPorM;
  final bool decorar;

  double _y(double metros) => yJugador + (metros - j.distancia) * pxPorM;

  @override
  void paint(Canvas canvas, Size size) {
    final pared = Paint()
      ..color = p.bordeFuerte
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fondo = Paint()..color = p.suave;
    canvas.drawRect(Rect.fromLTWH(x0, 0, tubo, size.height), fondo);
    canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), pared);
    canvas.drawLine(Offset(x0 + tubo, 0), Offset(x0 + tubo, size.height), pared);
    // Juntas del tubo: pasan hacia arriba y dan la sensación de velocidad.
    final junta = Paint()
      ..color = p.borde
      ..strokeWidth = 1;
    final primera = (j.distancia / 3).floor();
    for (var k = primera; k < primera + (size.height / pxPorM / 3).ceil() + 3; k++) {
      final y = _y(k * 3.0);
      canvas.drawLine(Offset(x0, y), Offset(x0 + tubo, y), junta);
    }
    if (decorar) _decorado(canvas, size, primera);
    // Codos: bloques cuadrados que tapan un lado.
    final relleno = Paint()..color = p.primario;
    final borde = Paint()
      ..color = p.acento
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final c in j.codos) {
      final y = _y(c.distancia);
      if (y < -40 || y > size.height + 40) continue;
      final ancho = tubo / 2;
      final r = Rect.fromLTWH(x0 + c.carril * ancho, y - JuegoTuberia.radioCodo * pxPorM, ancho, JuegoTuberia.radioCodo * 2 * pxPorM);
      canvas.drawRect(r, relleno);
      canvas.drawRect(r, borde);
    }
  }

  // Burbujas y cucarachas de adorno: posiciones fijas por tramo, sin azar en cada cuadro.
  void _decorado(Canvas canvas, Size size, int primera) {
    final burbuja = Paint()
      ..color = p.bordeFuerte
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var k = primera - 2; k < primera + (size.height / pxPorM / 3).ceil() + 4; k++) {
      final h = (k * 2654435761) & 0xFFFF;
      final bx = x0 + 8 + (h % 1000) / 1000 * (tubo - 16);
      canvas.drawCircle(Offset(bx, _y(k * 3.0 + (h % 7) * 0.3)), 2 + (h % 4).toDouble(), burbuja);
      if (h % 5 == 0) {
        // Cucaracha: óvalo con dos antenas, pegada a la pared.
        final izq = h % 2 == 0;
        final cx = izq ? x0 + 7 : x0 + tubo - 7;
        final cy = _y(k * 3.0 + 1.5);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: 7, height: 12), Paint()..color = p.textoSuave);
        final dir = izq ? 1.0 : -1.0;
        canvas.drawLine(Offset(cx, cy - 6), Offset(cx + 3 * dir, cy - 11), burbuja);
        canvas.drawLine(Offset(cx, cy - 6), Offset(cx - 1 * dir, cy - 11), burbuja);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PintorTubo old) => true;
}
