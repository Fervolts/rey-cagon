// La poceta del Imperio: el botón grande que se toca para pujar.
//
// Cada toque deja caer un mojoncito dentro, sale dinero y sube un "+N". El épico salpica y tiembla.
// Se pone más roja y vibra más cuanto más MJ/s hay (escala log10). Alrededor van los dedos comprados
// y los accesorios de las mejoras de la poceta (tanque, válvula, imán, brillo, incienso con humo, guantes...).
//
// Barato a propósito: un solo Ticker que mueve un ValueNotifier, todo dentro de un RepaintBoundary, sin
// sombras ni saveLayer. Con movimiento "completo" el ticker corre mientras se ve (respira, vibra, humo);
// con "simple" solo corre mientras haya "+N" en el aire; con "nada" no corre nunca.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';

/// Lo que devuelve un toque: el texto que sube ("+12", "¡ÉPICO! +3,4 K") y si fue épico.
typedef ToquePoceta = ({String texto, bool epico});

class Poceta extends StatefulWidget {
  const Poceta({
    super.key,
    required this.alTocar,
    required this.mps,
    this.fiebre = false,
    this.pujoLoco = false,
    this.efectos = const [],
    this.accesorios = const [],
    this.dedos = 0,
    this.activo = true,
  });

  /// Puja de verdad (motor) y devuelve qué mostrar.
  final ToquePoceta Function() alTocar;

  /// MJ/s actuales: de aquí sale el calor (rojo y vibración).
  final double mps;
  final bool fiebre, pujoLoco;

  /// Emojis de los efectos activos que no tienen dibujo propio (objetos, robot, papel...).
  final List<String> efectos;

  /// Emojis de las mejoras compradas que se cuelgan de la poceta, sin repetir.
  final List<String> accesorios;

  /// Cuántos dedos hay. Se dibujan hasta [topeDedos]; los demás van en el número.
  final int dedos;

  /// La pestaña se ve. Si no, el ticker se para.
  final bool activo;

  static const topeDedos = 16;

  @override
  State<Poceta> createState() => _PocetaState();
}

enum _Tipo { caida, moneda, flotante, salpicon, gota }

class _Particula {
  _Particula(this.id, this.tipo, this.inicio, this.vida, {this.x = 0, this.vx = 0, this.vy = 0, this.emoji = '', this.texto = '', this.epico = false});
  final int id;
  final _Tipo tipo;
  final double inicio, vida;
  final double x, vx, vy; // relativos al centro de la poceta
  final String emoji, texto;
  final bool epico;
}

class _PocetaState extends State<Poceta> with SingleTickerProviderStateMixin {
  static const _lado = 140.0; // la poceta
  static const _alto = 224.0; // el área entera
  static const _cy = 112.0;
  static const _rojo = Color(0xFFFF3B30);

  // Boca de la taza en toilet.png: la misma fracción que usa inodoro.dart (.33, .47).
  static const _boca = Offset(_lado * .33 - _lado / 2, _lado * .47 - _lado / 2);

  // Huecos de los accesorios alrededor (relativos al centro). Los que no caben no se ven.
  static const _huecos = [
    Offset(-125, -72), Offset(125, -72), Offset(-150, -22), Offset(150, -22), Offset(-125, 28),
    Offset(125, 28), Offset(-62, -96), Offset(62, -96), Offset(-158, 76), Offset(158, 76),
  ];

  late final Ticker _ticker = createTicker(_tic);
  final _reloj = Stopwatch()..start();
  final _t = ValueNotifier<double>(0);
  final _azar = Random();
  final _particulas = <_Particula>[];
  int _id = 0;
  double _ultimoToque = -9, _ultimoEpico = -9;
  String? _ultimoTexto; // con movimiento "nada": queda fijo arriba
  Movimiento _mov = Movimiento.completo;

  double get _ahora => _reloj.elapsedMicroseconds / 1e6;

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  bool get _debeCorrer => widget.activo && _mov != Movimiento.nada && (_mov == Movimiento.completo || _particulas.isNotEmpty);

  void _ajustarTicker() {
    if (_debeCorrer) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tic(Duration _) {
    final t = _ahora;
    _particulas.removeWhere((q) => t - q.inicio > q.vida);
    _t.value = t;
    if (!_debeCorrer) _ticker.stop();
  }

  void _agregar(_Particula q, int tope) {
    final mismas = _particulas.where((x) => x.tipo == q.tipo).toList();
    if (mismas.length >= tope) _particulas.remove(mismas.first);
    _particulas.add(q);
  }

  void _tocar() {
    final r = widget.alTocar();
    if (r.epico) HapticFeedback.heavyImpact();
    if (_mov == Movimiento.nada) {
      setState(() => _ultimoTexto = r.texto);
      return;
    }
    final t = _ahora;
    _ultimoToque = t;
    final dx = _azar.nextDouble() * 120 - 60;
    _agregar(_Particula(_id++, _Tipo.flotante, t + (_mov == Movimiento.completo ? .18 : 0), r.epico ? 1.2 : .8, x: dx, texto: r.texto, epico: r.epico), 14);
    if (_mov == Movimiento.completo) {
      // Mojoncito que cae a la taza y, al llegar, la plata que sale.
      _agregar(_Particula(_id++, _Tipo.caida, t, .3, x: _boca.dx + _azar.nextDouble() * 16 - 8), 6);
      _agregar(_Particula(_id++, _Tipo.moneda, t + .22, .75, x: dx * .6, vx: _azar.nextDouble() * 40 - 20, emoji: _azar.nextBool() ? '💸' : '💰'), 8);
      if (r.epico) {
        _ultimoEpico = t + .25;
        _agregar(_Particula(_id++, _Tipo.salpicon, t + .25, .5), 2);
        for (var i = 0; i < 8; i++) {
          final a = pi * (.15 + .7 * i / 7) + _azar.nextDouble() * .2 - .1;
          final v = 140 + _azar.nextDouble() * 90;
          _agregar(_Particula(_id++, _Tipo.gota, t + .25, .75, vx: cos(a) * v, vy: -sin(a) * v, emoji: i.isEven ? '💧' : '💦'), 16);
        }
        for (var i = 0; i < 3; i++) {
          final x = _azar.nextDouble() * 140 - 70, vx = _azar.nextDouble() * 80 - 40;
          _agregar(_Particula(_id++, _Tipo.moneda, t + .3 + i * .06, .9, x: x, vx: vx, emoji: i.isEven ? '💰' : '🪙'), 8);
        }
      }
    }
    _ajustarTicker();
  }

  @override
  Widget build(BuildContext context) {
    _mov = movimiento(context);
    if (_mov != Movimiento.nada) _ultimoTexto = null;
    _ajustarTicker();
    return Semantics(
      button: true,
      label: tr('Pujar', 'Push'),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _tocar(),
        child: RepaintBoundary(
          child: SizedBox(
            height: _alto,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, caja) => ValueListenableBuilder<double>(
                valueListenable: _t,
                builder: (context, t, _) => _dibujo(context, caja.maxWidth / 2, _mov == Movimiento.nada ? 0 : t),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _en(double cx, Offset o, double tam, Widget hijo, {Key? key}) =>
      Positioned(key: key, left: cx + o.dx - tam / 2, top: _cy + o.dy - tam / 2, width: tam, height: tam, child: hijo);

  Widget _dibujo(BuildContext context, double cx, double t) {
    final p = paleta(context);
    final vivo = _mov == Movimiento.completo; // movimiento de fondo (respirar, vibrar, humo)
    final calor = (log(widget.mps + 1) / ln10 / 9).clamp(0.0, 1.0);

    // Apretón al tocar.
    final s = t - _ultimoToque;
    var escala = s >= 0 && s < .14 ? 1 - .08 * sin(pi * s / .14) : 1.0;
    if (vivo) escala *= 1 + .015 * sin(t * 2.4);

    // Temblor: calor, pujo loco y el golpe del épico.
    var dx = 0.0, dy = 0.0, giro = 0.0;
    if (vivo) {
      final amp = widget.pujoLoco ? 4.5 : (calor > .25 ? 2.2 * (calor - .25) / .75 : 0.0);
      dx = amp * sin(t * 53) * cos(t * 17);
      dy = amp * .6 * sin(t * 41 + 1);
      if (widget.pujoLoco) giro = .06 * sin(t * 37);
      final e = t - _ultimoEpico;
      if (e >= 0 && e < .35) {
        final k = 1 - e / .35;
        dx += 7 * k * sin(e * 70);
        giro += .09 * k * sin(e * 55);
      }
    }

    final hijos = <Widget>[];

    // Objetos activos, arriba a la izquierda.
    for (var i = 0; i < widget.efectos.length && i < 5; i++) {
      hijos.add(Positioned(
        left: 8.0 + i * 26,
        top: 4 + (vivo ? 2 * sin(t * 2 + i) : 0),
        child: Emoji(widget.efectos[i], tamano: 22),
      ));
    }

    // Accesorios. En pantallas angostas solo los huecos que caben a lo ancho.
    final huecos = [for (final h in _huecos) if (h.dx.abs() + 15 <= cx) h];
    for (var i = 0; i < widget.accesorios.length && i < huecos.length; i++) {
      final a = widget.accesorios[i];
      final h = huecos[i];
      Widget w = Emoji(a, tamano: 30);
      if (vivo) {
        if (a == '✨') {
          w = Transform.scale(scale: .75 + .35 * sin(t * 3 + i).abs(), child: w);
        } else if (a == '🧲') {
          w = Transform.rotate(angle: .18 * sin(t * 2), child: w);
        } else {
          w = Transform.translate(offset: Offset(0, 2 * sin(t * 1.7 + i)), child: w);
        }
      }
      hijos.add(_en(cx, h, 30, w));
      if (a == '🪻' && vivo) {
        // El incienso echa humo.
        for (var k = 0; k < 2; k++) {
          final f = (t * .6 + k * .5) % 1;
          hijos.add(_en(cx, h + Offset(4 + 6 * sin(f * 6 + k), -20 - 26 * f), 18,
              Opacity(opacity: (1 - f) * .7, child: const Emoji('💨', tamano: 18))));
        }
      }
    }

    // Dedos alrededor, apuntando a la poceta.
    final nDedos = min(widget.dedos, Poceta.topeDedos);
    for (var i = 0; i < nDedos; i++) {
      final a = nDedos == 1 ? pi / 2 : (-20 + 220 * i / (nDedos - 1)) * pi / 180;
      var r = 94.0;
      if (vivo) {
        final f = (t * 1.3 + i * .37) % 1;
        if (f < .15) r -= 7 * sin(pi * f / .15);
      }
      hijos.add(_en(cx, Offset(cos(a) * r, sin(a) * r), 24, Transform.rotate(angle: a - pi / 2, child: const Emoji('👆', tamano: 24))));
    }

    // Fiebre: candela debajo.
    if (widget.fiebre) {
      for (var i = -1; i <= 1; i++) {
        final esc = vivo ? .85 + .2 * sin(t * 13 + i * 2) : 1.0;
        final fuego = Transform.scale(scale: esc, alignment: Alignment.bottomCenter, child: const Emoji('🔥', tamano: 34));
        hijos.add(_en(cx, Offset(i * 40.0, _lado / 2 - 6), 34, fuego));
      }
    }

    // La poceta. Image.asset y no Emoji: el rojo del calor se pinta con color + srcATop (barato, sin capa aparte).
    hijos.add(_en(
      cx,
      Offset(dx, dy),
      _lado,
      Transform.rotate(
        angle: giro,
        child: Transform.scale(
          scale: escala,
          child: Image.asset(
            'assets/emoji/toilet.png',
            width: _lado,
            height: _lado,
            filterQuality: FilterQuality.medium,
            color: calor > .02 ? _rojo.withValues(alpha: .55 * calor) : null,
            colorBlendMode: BlendMode.srcATop,
            gaplessPlayback: true,
          ),
        ),
      ),
    ));

    // Vapor cuando está muy caliente.
    if (vivo && calor > .6) {
      for (var k = 0; k < 2; k++) {
        final f = (t * .7 + k * .5) % 1;
        hijos.add(_en(cx, Offset(26 + 10 * k + 8 * sin(f * 5), -_lado / 2 + 6 - 40 * f), 22,
            Opacity(opacity: (1 - f) * (calor - .6) / .4, child: const Emoji('💨', tamano: 22))));
      }
    }

    // Partículas de los toques.
    for (final q in _particulas) {
      final e = t - q.inicio;
      if (e < 0) continue;
      final f = (e / q.vida).clamp(0.0, 1.0);
      final llave = ValueKey(q.id);
      switch (q.tipo) {
        case _Tipo.caida:
          final g = Curves.easeIn.transform(f);
          hijos.add(_en(cx, Offset(q.x, -92 + (_boca.dy + 92) * g), 34 * (1 - .5 * g),
              Opacity(opacity: f < .7 ? 1 : (1 - f) / .3, child: const Emoji('💩', tamano: 34)), key: llave));
        case _Tipo.moneda:
          hijos.add(_en(cx, Offset(q.x + q.vx * e, _boca.dy - 20 - 95 * Curves.easeOut.transform(f)), 28,
              Opacity(opacity: 1 - f, child: Emoji(q.emoji, tamano: 28)), key: llave));
        case _Tipo.salpicon:
          hijos.add(_en(cx, _boca, 90,
              Opacity(opacity: 1 - f, child: Transform.scale(scale: .5 + 1.1 * f, child: const Emoji('💥', tamano: 90))), key: llave));
        case _Tipo.gota:
          hijos.add(_en(cx, _boca + Offset(q.vx * e, q.vy * e + 300 * e * e), 20,
              Opacity(opacity: 1 - f, child: Emoji(q.emoji, tamano: 20)), key: llave));
        case _Tipo.flotante:
          hijos.add(Positioned(
            key: llave,
            left: cx + q.x - 110,
            width: 220,
            top: _cy - 70 - 70 * f,
            child: Opacity(
              opacity: 1 - f,
              child: Text(q.texto,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: numeros(context, tamano: q.epico ? 28 : 18, weight: FontWeight.w900, color: q.epico ? p.primario : p.texto)),
            ),
          ));
      }
    }

    // Con "nada": el último pujo queda fijo arriba.
    if (_ultimoTexto != null) {
      hijos.add(Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Text(_ultimoTexto!, textAlign: TextAlign.center, style: numeros(context, tamano: 16, weight: FontWeight.w900)),
      ));
    }

    // Más dedos de los que caben.
    if (widget.dedos > Poceta.topeDedos) {
      hijos.add(Positioned(
        right: 12,
        bottom: 2,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Emoji('👆', tamano: 16),
          const SizedBox(width: 3),
          Text('x${widget.dedos}', style: numeros(context, tamano: 12, weight: FontWeight.w800, color: p.textoSuave)),
        ]),
      ));
    }

    return Stack(clipBehavior: Clip.none, children: hijos);
  }
}
