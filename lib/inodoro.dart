import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emoji.dart';

/// El mojón del botón brinca en arco y cae en un inodoro que sale debajo, salpica y el inodoro
/// se va. [alSalpicar] se llama cuando cae, para que el botón vuelva a mostrar su mojón.
/// Termina cuando se quita el inodoro.
Future<void> tirarAlInodoro(BuildContext context, {required Rect boton, required bool secreto, VoidCallback? alSalpicar}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final caja = overlay.context.findRenderObject() as RenderBox;
  final arriba = caja.globalToLocal(boton.topLeft);
  final listo = Completer<void>();
  late final OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (_) => _Inodoro(
      boton: arriba & boton.size,
      pantalla: caja.size,
      secreto: secreto,
      alSalpicar: alSalpicar,
      alTerminar: () {
        if (entrada.mounted) entrada.remove();
        if (!listo.isCompleted) listo.complete();
      },
    ),
  );
  overlay.insert(entrada);
  return listo.future;
}

class _Inodoro extends StatefulWidget {
  const _Inodoro({
    required this.boton,
    required this.pantalla,
    required this.secreto,
    required this.alSalpicar,
    required this.alTerminar,
  });

  final Rect boton;
  final Size pantalla;
  final bool secreto;
  final VoidCallback? alSalpicar;
  final VoidCallback alTerminar;

  @override
  State<_Inodoro> createState() => _InodoroState();
}

class _InodoroState extends State<_Inodoro> with SingleTickerProviderStateMixin {
  static const _tamano = 140.0;
  // Dónde está la boca de la taza dentro de toilet.png, en fracción del ancho y del alto.
  static const _boca = Offset(.33, .47);
  // Momentos de la animación (de 0 a 1): sale el inodoro, vuela el mojón, salpica, se va.
  static const _vuelo = (.08, .52);
  static const _salpica = .52;
  static const _seVa = .8;

  late final AnimationController _c;
  bool _salpico = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..addListener(_alAvanzar);
    _c.forward().whenCompleteOrCancel(widget.alTerminar);
  }

  // Gotas: ángulo hacia arriba y rapidez, fijas para que no cambien en cada cuadro.
  late final List<(double, double)> _gotas = () {
    final azar = Random();
    return [for (var i = 0; i < 7; i++) (-pi * (.18 + .64 * i / 6) + (azar.nextDouble() - .5) * .3, 170 + azar.nextDouble() * 110)];
  }();

  void _alAvanzar() {
    if (!_salpico && _c.value >= _salpica) {
      _salpico = true;
      HapticFeedback.heavyImpact();
      widget.alSalpicar?.call();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// La parte de [t] que cae entre [desde] y [hasta], de 0 a 1.
  double _tramo(double t, double desde, double hasta) => ((t - desde) / (hasta - desde)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final b = widget.boton;
    // El mojón está un poco arriba del centro del botón, encima del texto CAGUÉ.
    final salida = b.center.translate(0, -14);
    final mojon = widget.secreto ? 104.0 : 88.0;
    // El inodoro sale abajo a la derecha del botón, sin salirse de la pantalla.
    final izquierda = min(b.center.dx + 24, widget.pantalla.width - _tamano - 8);
    final tope = min(b.bottom - 30, widget.pantalla.height - _tamano - 24);
    final boca = Offset(izquierda + _boca.dx * _tamano, tope + _boca.dy * _tamano);
    final cima = Offset((salida.dx + boca.dx) / 2, min(salida.dy, boca.dy) - 190);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final entra = Curves.easeOutBack.transform(_tramo(t, 0, .2));
          final sale = Curves.easeIn.transform(_tramo(t, _seVa, 1));
          final temblor = _tramo(t, _salpica, _seVa);
          final vuelo = _tramo(t, _vuelo.$1, _vuelo.$2);
          final v = Curves.easeIn.transform(vuelo);
          // Curva de Bézier de la salida a la boca pasando cerca de la cima.
          final punto = salida * ((1 - v) * (1 - v)) + cima * (2 * (1 - v) * v) + boca * (v * v);
          final gotas = _tramo(t, _salpica, _salpica + .3);
          return Stack(
            children: [
              Positioned(
                left: izquierda,
                top: tope + 30 * (1 - entra) + 24 * sale,
                child: Opacity(
                  opacity: (entra * (1 - sale)).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: .09 * sin(temblor * 6 * pi) * (1 - temblor),
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scale: (.5 + .5 * entra) * (1 - .4 * sale),
                      alignment: Alignment.bottomCenter,
                      child: const Emoji('🚽', tamano: _tamano),
                    ),
                  ),
                ),
              ),
              if (t >= _vuelo.$1 && t < _vuelo.$2)
                Positioned(
                  left: punto.dx - mojon / 2,
                  top: punto.dy - mojon / 2,
                  child: Opacity(
                    // Se mete en la taza: al final se achica y se desvanece.
                    opacity: 1 - _tramo(vuelo, .85, 1),
                    child: Transform.rotate(
                      angle: 2 * pi * Curves.easeInOut.transform(vuelo),
                      child: Transform.scale(
                        scale: 1 - .6 * v,
                        child: widget.secreto
                            ? Image.asset('assets/img/mojon_angel.png', width: mojon, height: mojon)
                            : Emoji('💩', tamano: mojon),
                      ),
                    ),
                  ),
                ),
              if (gotas > 0 && gotas < 1)
                for (final (angulo, rapidez) in _gotas)
                  Positioned(
                    // Tiro parabólico: medio segundo de vuelo con gravedad.
                    left: boca.dx + cos(angulo) * rapidez * gotas * .45 - 9,
                    top: boca.dy + sin(angulo) * rapidez * gotas * .45 + 900 * pow(gotas * .45, 2) / 2 - 9,
                    child: Opacity(opacity: 1 - gotas, child: const Emoji('💧', tamano: 18)),
                  ),
            ],
          );
        },
      ),
    );
  }
}
