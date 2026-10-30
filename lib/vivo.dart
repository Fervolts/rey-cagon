import 'dart:math';

import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'emoji.dart';

/// Piezas de movimiento reutilizables. Todas respetan `movimiento(context)`:
/// nada = quieto, simple = solo fundidos cortos, completo = todo.

/// Entrada de una fila o tarjeta: aparece y sube un poco, escalonada por [orden].
/// Solo se anima la primera vez que se pinta (al crearse su State).
class Aparece extends StatefulWidget {
  const Aparece({super.key, this.orden = 0, this.desplazamiento = 14, this.paso = 35, this.tope = 12, required this.child});

  final int orden;
  // Milisegundos entre una y otra, y cuántas se escalonan (las de más abajo entran juntas).
  final int paso, tope;
  final double desplazamiento;
  final Widget child;

  @override
  State<Aparece> createState() => _ApareceState();
}

class _ApareceState extends State<Aparece> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final nivel = movimiento(context);
    if (nivel == Movimiento.nada) return;
    final int espera = nivel == Movimiento.completo ? widget.paso * min<int>(widget.orden, widget.tope) : 0;
    final int total = (nivel == Movimiento.completo ? 320 : 160) + espera;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: total));
    _c = c;
    _t = CurvedAnimation(parent: c, curve: Interval(espera / total, 1, curve: Curves.easeOutCubic));
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null || (_c?.isCompleted ?? false)) return widget.child;
    final sube = movimiento(context) == Movimiento.completo;
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: sube ? Transform.translate(offset: Offset(0, widget.desplazamiento * (1 - t.value)), child: child) : child,
      ),
    );
  }
}

/// Número entero que cuenta hacia arriba (desde 0 la primera vez, desde el anterior después).
class Contador extends StatelessWidget {
  const Contador(this.valor, {super.key, this.estilo, this.prefijo = '', this.sufijo = '', this.relleno = 0});

  final int valor;
  final TextStyle? estilo;
  final String prefijo;
  final String sufijo;
  // Ceros a la izquierda.
  final int relleno;

  String _texto(int n) => '$prefijo${n.toString().padLeft(relleno, '0')}$sufijo';

  @override
  Widget build(BuildContext context) {
    if (movimiento(context) != Movimiento.completo) return Text(_texto(valor), style: estilo);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor.toDouble()),
      duration: Duration(milliseconds: 500 + 8 * min(valor, 50)),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(_texto(v.round()), style: estilo),
    );
  }
}

/// Da un "pop" (se agranda y vuelve) cada vez que [valor] cambia.
class Pop extends StatefulWidget {
  const Pop({super.key, required this.valor, required this.child, this.escala = 1.25, this.alineacion = Alignment.center});

  final Alignment alineacion;
  final Object? valor;
  final double escala;
  final Widget child;

  @override
  State<Pop> createState() => _PopState();
}

class _PopState extends State<Pop> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(Pop viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.valor != widget.valor && movimiento(context) == Movimiento.completo) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          if (!_c.isAnimating) return child!;
          // Sube rápido y vuelve más despacio.
          final t = _c.value;
          final e = t < .3 ? Curves.easeOut.transform(t / .3) : 1 - Curves.easeInOut.transform((t - .3) / .7);
          return Transform.scale(scale: 1 + (widget.escala - 1) * e.clamp(0.0, 1.0), alignment: widget.alineacion, child: child);
        },
      );
}

/// Respiración suave (escala que sube y baja) mientras [activo]. Se detiene sola si la pestaña
/// no está a la vista (TickerMode) y con movimiento simple o apagado no se mueve.
class Respira extends StatefulWidget {
  const Respira({super.key, this.activo = true, this.amplitud = .035, required this.child});

  final bool activo;
  final double amplitud;
  final Widget child;

  @override
  State<Respira> createState() => _RespiraState();
}

class _RespiraState extends State<Respira> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  void _ajustar() {
    final va = widget.activo && movimiento(context) == Movimiento.completo;
    if (va && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!va && _c.isAnimating) {
      _c.animateTo(0, duration: const Duration(milliseconds: 250));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustar();
  }

  @override
  void didUpdateWidget(Respira viejo) {
    super.didUpdateWidget(viejo);
    _ajustar();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) =>
            Transform.scale(scale: 1 + widget.amplitud * Curves.easeInOut.transform(_c.value), child: child),
      );
}

/// Se encoge a .96 mientras el dedo está encima. No se come el toque: solo mira.
class Rebote extends StatefulWidget {
  const Rebote({super.key, required this.child, this.escala = .96});

  final double escala;
  final Widget child;

  @override
  State<Rebote> createState() => _ReboteState();
}

class _ReboteState extends State<Rebote> {
  bool _abajo = false;

  void _poner(bool v) {
    if (_abajo != v && movimiento(context) != Movimiento.nada) setState(() => _abajo = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _poner(true),
        onPointerUp: (_) => _poner(false),
        onPointerCancel: (_) => _poner(false),
        child: AnimatedScale(
          scale: _abajo ? widget.escala : 1,
          duration: Duration(milliseconds: _abajo ? 90 : 220),
          curve: _abajo ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}

/// Ícono de la barra inferior: rebota cuando pasa a [activo].
class IconoRebota extends StatefulWidget {
  const IconoRebota({super.key, required this.activo, required this.child});

  final bool activo;
  final Widget child;

  @override
  State<IconoRebota> createState() => _IconoRebotaState();
}

class _IconoRebotaState extends State<IconoRebota> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));

  @override
  void didUpdateWidget(IconoRebota viejo) {
    super.didUpdateWidget(viejo);
    if (widget.activo && !viejo.activo && movimiento(context) != Movimiento.nada) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          if (!_c.isAnimating) return child!;
          final t = _c.value;
          // Se hunde un poco y sale con rebote.
          final escala = t < .2 ? 1 - .2 * (t / .2) : .8 + .2 * Curves.elasticOut.transform((t - .2) / .8);
          return Transform.scale(scale: escala, child: child);
        },
      );
}

/// Cae desde arriba y rebota (la corona del podio).
class Cae extends StatelessWidget {
  const Cae({super.key, this.retraso = Duration.zero, this.altura = 40, required this.child});

  final Duration retraso;
  final double altura;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (movimiento(context) != Movimiento.completo) return child;
    return _CaeConRetraso(retraso: retraso, altura: altura, child: child);
  }
}

class _CaeConRetraso extends StatefulWidget {
  const _CaeConRetraso({required this.retraso, required this.altura, required this.child});

  final Duration retraso;
  final double altura;
  final Widget child;

  @override
  State<_CaeConRetraso> createState() => _CaeConRetrasoState();
}

class _CaeConRetrasoState extends State<_CaeConRetraso> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.retraso + const Duration(milliseconds: 700));
  late final _t = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.retraso.inMilliseconds / (widget.retraso.inMilliseconds + 700), 1, curve: Curves.bounceOut),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value.clamp(0.0, 1.0) < .05 ? 0 : 1,
          child: Transform.translate(offset: Offset(0, -widget.altura * (1 - _t.value)), child: child),
        ),
      );
}

/// Para esperar o cargar: un 💩 que rebota (quieto con movimiento apagado).
class Cargando extends StatefulWidget {
  const Cargando({super.key, this.tamano = 40});

  final double tamano;

  @override
  State<Cargando> createState() => _CargandoState();
}

class _CargandoState extends State<Cargando> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final va = movimiento(context) != Movimiento.nada;
    if (va && !_c.isAnimating) {
      _c.repeat();
    } else if (!va && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salta = movimiento(context) == Movimiento.completo;
    return Center(
      child: SizedBox(
        height: widget.tamano * 1.6,
        child: AnimatedBuilder(
          animation: _c,
          child: Emoji('💩', tamano: widget.tamano),
          builder: (context, child) {
            final t = _c.value;
            // Simple: late (opacidad). Completo: salta y se aplasta al caer.
            if (!salta) return Opacity(opacity: .55 + .45 * sin(pi * t), child: child);
            final arco = sin(pi * t);
            return Transform.translate(
              offset: Offset(0, -widget.tamano * .6 * arco),
              child: Transform.scale(scaleX: 1 + .12 * (1 - arco), scaleY: 1 - .12 * (1 - arco), child: child),
            );
          },
        ),
      ),
    );
  }
}

/// Entrada con un pequeño balanceo (avatares): llega girado y encogido y se acomoda con rebote.
class Balanceo extends StatelessWidget {
  const Balanceo({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nivel = movimiento(context);
    if (nivel == Movimiento.nada) return child;
    if (nivel == Movimiento.simple) return Aparece(child: child);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.elasticOut,
      child: child,
      builder: (context, t, child) => Transform.rotate(
        angle: -.18 * (1 - t),
        child: Transform.scale(scale: .7 + .3 * t, child: child),
      ),
    );
  }
}
