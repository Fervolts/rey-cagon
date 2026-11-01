// La poceta del Imperio: el botón grande que se toca para pujar, en medio de su baño (bano.dart).
//
// Cada toque deja caer un mojoncito dentro, sale dinero y sube un "+N". El épico salpica y tiembla. Con muchos
// MJ/s la poceta vibra y echa vapor (la imagen no se tiñe). Alrededor, el baño: el fondo quieto viene de
// [FondoBano] y aquí va lo que se mueve: los dedos que pinchan, el bombillo pelado que parpadea, la gota del grifo,
// la cucaracha, la ciruela que cae, el chorro de café, la arepa que salta en el budare...
//
// Barato a propósito: un solo Ticker que mueve un ValueNotifier. El fondo va en su propio RepaintBoundary como
// `child` del ValueListenableBuilder, así que no se reconstruye ni se repinta en cada tick. Sin sombras ni saveLayer.
// Con movimiento "completo" el ticker corre mientras se ve; con "simple" solo mientras haya "+N" en el aire y lo
// demás queda en pose quieta; con "nada" no corre nunca.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'bano.dart';
import 'moneda_app.dart';

/// Lo que devuelve un toque: el texto que sube ("+12", "¡ÉPICO! +3,4 K") y si fue épico.
typedef ToquePoceta = ({String texto, bool epico});

class Poceta extends StatefulWidget {
  const Poceta({
    super.key,
    required this.alTocar,
    required this.mps,
    this.bano = const EstadoBano(),
    this.fiebre = false,
    this.pujoLoco = false,
    this.efectos = const [],
    this.dedos = 0,
    this.activo = true,
    @visibleForTesting this.instante,
  });

  /// Puja de verdad (motor) y devuelve qué mostrar.
  final ToquePoceta Function() alTocar;

  /// MJ/s actuales: de aquí sale el calor (vibración y vapor).
  final double mps;

  /// Qué hay en el baño.
  final EstadoBano bano;
  final bool fiebre, pujoLoco;

  /// Emojis de los efectos activos que no tienen dibujo propio (objetos, robot, papel...).
  final List<String> efectos;

  /// Cuántos dedos hay. Rodean la poceta hasta cerrar el anillo ([topeDedos]); los demás van en el número.
  final int dedos;

  /// La pestaña se ve. Si no, el ticker se para.
  final bool activo;

  /// Solo para pruebas: dibuja la escena quieta en este segundo, como con movimiento completo.
  final double? instante;

  static const topeDedos = 24;

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
  static const _cy = 150.0; // centro de la poceta en el baño

  // Boca de la taza en toilet.png: la misma fracción que usa inodoro.dart (.33, .47).
  static const _boca = Offset(_lado * .33 - _lado / 2, _lado * .47 - _lado / 2);

  // Los dedos van en un anillo alrededor de la poceta: [Poceta.topeDedos] puestos fijos, el 0 abajo (90 grados) y
  // los demás en sentido horario. Se llenan en orden de bits invertidos (0, 12, 6, 18, 3...): cada dedo nuevo cae
  // en el hueco más grande, el anillo se ve parejo con pocos y los que ya estaban no se mueven.
  static final _ordenDedos = _bitsInvertidos(Poceta.topeDedos);
  // Un poco más ancho que alto: el tanque de la poceta no tapa los dedos de arriba a la derecha.
  static const _radioDedos = 100.0, _altoDedos = 90.0;

  static List<int> _bitsInvertidos(int n) {
    var bits = 0;
    while ((1 << bits) < n) {
      bits++;
    }
    final orden = <int>[];
    for (var k = 0; k < (1 << bits); k++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if (k & (1 << b) != 0) r |= 1 << (bits - 1 - b);
      }
      // Con n que no es potencia de 2 se escala el puesto al anillo y se saltan los repetidos.
      final puesto = (r * n) >> bits;
      if (!orden.contains(puesto)) orden.add(puesto);
    }
    return orden;
  }

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

  bool get _debeCorrer =>
      widget.instante == null && widget.activo && _mov != Movimiento.nada && (_mov == Movimiento.completo || _particulas.isNotEmpty);

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
    final p = paleta(context);
    final fijo = widget.instante;
    return Semantics(
      button: true,
      label: tr('Pujar', 'Push'),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _tocar(),
        child: RepaintBoundary(
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: p.borde))),
            child: SizedBox(
              height: Bano.alto,
              width: double.infinity,
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, caja) => ValueListenableBuilder<double>(
                    valueListenable: _t,
                    // El fondo no depende del tick: se arma una vez y se repinta solo si cambia el baño.
                    child: RepaintBoundary(child: FondoBano(estado: widget.bano)),
                    builder: (context, t, fondo) {
                      final vivo = fijo != null || _mov == Movimiento.completo;
                      return _dibujo(context, caja.maxWidth / 2, fijo ?? (_mov == Movimiento.nada ? 0 : t), vivo, fondo!);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Relativo al centro de la poceta.
  Widget _en(double cx, Offset o, double tam, Widget hijo, {Key? key}) =>
      Positioned(key: key, left: cx + o.dx - tam / 2, top: _cy + o.dy - tam / 2, width: tam, height: tam, child: hijo);

  // x relativa al centro de la pantalla, y desde arriba (como en bano.dart).
  Widget _abs(double cx, Offset o, double tam, Widget hijo) =>
      Positioned(left: cx + o.dx - tam / 2, top: o.dy - tam / 2, width: tam, height: tam, child: hijo);

  Widget _dibujo(BuildContext context, double cx, double t, bool vivo, Widget fondo) {
    final p = paleta(context);
    final b = widget.bano;
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

    final hijos = <Widget>[Positioned.fill(child: fondo)];
    final encima = <Widget>[]; // textos: no les cae el parpadeo del bombillo

    _ambienteVivo(hijos, cx, t, vivo);

    // Dedos en anillo, apuntando a la poceta. El pinchazo da la vuelta como una ola. Todos van bajo un solo
    // ColorFiltered (una capa para el anillo, no una por dedo); lo que llevan puesto va aparte, sin teñir.
    final nDedos = min(widget.dedos, Poceta.topeDedos);
    if (nDedos > 0) {
      final dedos = <Widget>[], puestos = <Widget>[];
      for (var k = 0; k < nDedos; k++) {
        final i = _ordenDedos[k];
        final a = pi / 2 + 2 * pi * i / Poceta.topeDedos;
        var r = 1.0;
        if (vivo) {
          final f = (t * .9 - i / Poceta.topeDedos) % 1;
          if (f < .15) r -= .075 * sin(pi * f / .15);
        }
        final o = Offset(cos(a) * _radioDedos * r, sin(a) * _altoDedos * r);
        final (dedo, puesto) = _dedo(i, a);
        dedos.add(_en(cx, o, 32, dedo));
        if (puesto != null) puestos.add(_en(cx, o, 32, puesto));
      }
      final tinte = _tinte(widget.bano.colorDedo);
      final anillo = Stack(clipBehavior: Clip.none, children: dedos);
      hijos.add(Positioned.fill(child: tinte == null ? anillo : ColorFiltered(colorFilter: ColorFilter.matrix(tinte), child: anillo)));
      hijos.addAll(puestos);
    }

    // Fiebre: candela debajo.
    if (widget.fiebre) {
      for (var i = -1; i <= 1; i++) {
        final esc = vivo ? .85 + .2 * sin(t * 13 + i * 2) : 1.0;
        final fuego = Transform.scale(scale: esc, alignment: Alignment.bottomCenter, child: const Emoji('🔥', tamano: 34));
        hijos.add(_en(cx, Offset(i * 40.0, _lado / 2 - 6), 34, fuego));
      }
    }

    // La poceta, sin tinte (salvo la de oro). Las mejoras del bidet y el forro van encima, dentro del mismo temblor.
    Widget taza = Image.asset('assets/emoji/toilet.png', width: _lado, height: _lado, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    if (b.pocetaOro) taza = ColorFiltered(colorFilter: ColorFilter.matrix(_tinte(ColorDedo.oro)!), child: taza);
    hijos.add(_en(
      cx,
      Offset(dx, dy),
      _lado,
      Transform.rotate(
        angle: giro,
        child: Transform.scale(
          scale: escala,
          child: Stack(children: [
            taza,
            Positioned.fill(child: CustomPaint(painter: PintorMejorasPoceta(b))),
            if (b.forro) const Positioned.fill(child: CustomPaint(painter: PintorForro())),
          ]),
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

    if (vivo) {
      _ciruela(hijos, cx, t);
      _cafe(hijos, cx, t);
      _chorritos(hijos, cx, t);
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
          encima.add(Positioned(
            key: llave,
            left: cx + q.x - 110,
            width: 220,
            top: _cy - 70 - 70 * f,
            child: Opacity(
              opacity: 1 - f,
              child: montoMj(
                  q.texto, _contorno(numeros(context, tamano: q.epico ? 28 : 18, weight: FontWeight.w900, color: q.epico ? p.primario : Colors.white)),
                  alineacion: Alignment.center),
            ),
          ));
      }
    }

    // Bombillo pelado: se va la luz un momentico cada tanto.
    if (vivo && !b.bombillo) {
      final g = t % 7.3;
      if (g < .08 || (g > .16 && g < .22) || (g > .3 && g < .5)) {
        hijos.add(const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x47000000)))));
      }
    }

    // Objetos activos, arriba a la izquierda.
    for (var i = 0; i < widget.efectos.length && i < 5; i++) {
      encima.add(Positioned(
        left: 8.0 + i * 26,
        top: 4 + (vivo ? 2 * sin(t * 2 + i) : 0),
        child: Emoji(widget.efectos[i], tamano: 22),
      ));
    }

    // Con "nada": el último pujo queda fijo arriba.
    if (_ultimoTexto != null) {
      encima.add(Positioned(
        top: 2,
        left: 0,
        right: 0,
        child: montoMj(_ultimoTexto!, _contorno(numeros(context, tamano: 16, weight: FontWeight.w900, color: Colors.white)), alineacion: Alignment.center),
      ));
    }

    // Más dedos de los que caben: el número en una placa.
    if (widget.dedos > Poceta.topeDedos) {
      // Abajo, entre el anillo de dedos y el borde.
      encima.add(Positioned(
        left: cx - 26,
        bottom: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Emoji('👆', tamano: 14),
            const SizedBox(width: 3),
            Text('x${widget.dedos}', style: numeros(context, tamano: 11, weight: FontWeight.w800)),
          ]),
        ),
      ));
    }

    return Stack(clipBehavior: Clip.hardEdge, children: [...hijos, ...encima]);
  }

  // El "+N" va en blanco con un borde oscuro duro (sin difuminar): se lee sobre cualquier pared.
  static TextStyle _contorno(TextStyle e) => e.copyWith(shadows: const [
        Shadow(color: Color(0xE6000000), offset: Offset(1.2, 1.2)),
        Shadow(color: Color(0xE6000000), offset: Offset(-1.2, 1.2)),
        Shadow(color: Color(0xE6000000), offset: Offset(1.2, -1.2)),
        Shadow(color: Color(0xE6000000), offset: Offset(-1.2, -1.2)),
      ]);

  // Matrices sobre la luz del emoji: conservan el volumen (un tinte plano lo dejaba como una mancha).
  static List<double>? _tinte(ColorDedo c) => switch (c) {
        ColorDedo.oro => const <double>[.40, 1.36, .14, 0, -150, .34, 1.14, .12, 0, -150, .10, .30, .03, 0, -40, 0, 0, 0, 1, 0],
        ColorDedo.acero => const <double>[.53, 1.79, .18, 0, -330, .53, 1.79, .18, 0, -322, .55, 1.86, .19, 0, -310, 0, 0, 0, 1, 0],
        ColorDedo.latex => const <double>[.13, .43, .04, 0, 115, .13, .43, .04, 0, 115, .14, .46, .05, 0, 122, 0, 0, 0, 1, 0],
        ColorDedo.piel => null,
      };

  // Un dedo con su apariencia (la mejor mejora comprada), sin teñir, y aparte lo único que lleva puesto.
  (Widget, Widget?) _dedo(int i, double a) {
    final b = widget.bano;
    final impar = i.isOdd;
    final (archivo, giro, espejo) = switch (b.formaDedo) {
      FormaDedo.mano => ('raised_hand', a - pi / 2, false),
      FormaDedo.pie when impar => ('foot', a + pi, false),
      FormaDedo.ambidiestro || FormaDedo.pie => ('backhand_index_pointing_up', a - pi / 2, impar),
      FormaDedo.normal => ('backhand_index_pointing_up', a - pi / 2, false),
    };
    final esPie = archivo == 'foot';
    Widget img = Image.asset('assets/emoji/$archivo.png', width: 26, height: 26, filterQuality: FilterQuality.medium);
    if (espejo) img = Transform.flip(flipX: true, child: img);
    final adorno = b.adornoDedo;
    // Sin girar, el dedo apunta hacia arriba: la punta arriba y la base abajo.
    final (Offset donde, double tam) = switch (adorno) {
      // En la mano entera la corona va en el dorso, no en la punta de los dedos.
      '👑' => (Offset(0, esPie ? -4 : (b.formaDedo == FormaDedo.mano ? 6 : -12)), 12.0),
      '💍' => (Offset(esPie ? 6 : 0, esPie ? 0 : -2), 10.0),
      _ => (Offset(0, esPie ? 5 : 8), 12.0),
    };
    return (
      Transform.rotate(angle: giro, child: Center(child: img)),
      adorno == null
          ? null
          : Transform.rotate(angle: giro, child: Center(child: Transform.translate(offset: donde, child: Emoji(adorno, tamano: tam)))),
    );
  }

  // Lo que se mueve del baño: gota, humo, destellos, cucaracha, ojos, arepa.
  void _ambienteVivo(List<Widget> hijos, double cx, double t, bool vivo) {
    final b = widget.bano;
    // El grifo sin válvula gotea.
    if (b.valvula == 0 && vivo) {
      final f = (t % 1.6) / 1.6;
      final g = Bano.grifo;
      final y = f < .6 ? g.dy - 4 : g.dy - 4 + 14 * Curves.easeIn.transform((f - .6) / .4);
      hijos.add(_abs(cx, Offset(g.dx + 1, y), 9, Opacity(opacity: f < .6 ? f / .6 : 1, child: const Emoji('💧', tamano: 9))));
    }
    if (b.lavanda) {
      for (var k = 0; k < 2; k++) {
        final f = vivo ? (t * .5 + k * .5) % 1 : .3 + k * .3;
        hijos.add(_abs(cx, Bano.lavanda + Offset(3 + 5 * sin(f * 6 + k), -16 - 24 * f), 16,
            Opacity(opacity: (1 - f) * .6, child: const Emoji('💨', tamano: 16))));
      }
    }
    if (b.brillo) {
      for (var i = 0; i < Bano.destellos.length; i++) {
        final esc = vivo ? .4 + .6 * sin(t * 1.7 + i * 2.1).abs() : .8;
        hijos.add(_abs(cx, Bano.destellos[i], 16, Transform.scale(scale: esc, child: const Emoji('✨', tamano: 16))));
      }
    }
    // Cucaracha que cruza el piso (mientras no haya cerámica nueva). Se para a la mitad, como hacen.
    if (!b.ceramica && vivo) {
      final fase = t % 40;
      if (fase >= 6 && fase < 11) {
        final f = (fase - 6) / 5;
        final u = f < .4 ? f / .4 * .45 : (f < .55 ? .45 : .45 + (f - .55) / .45 * .55);
        final x = -20 + (2 * cx + 40) * u;
        hijos.add(Positioned(
            left: x - 9,
            top: 262 + (f < .4 || f >= .55 ? sin(t * 30) : 0),
            width: 18,
            height: 18,
            child: Transform.rotate(angle: pi / 2, child: const Emoji('🪳', tamano: 18))));
      }
    }
    if (b.ambiente == AmbienteBano.cloaca) {
      final parpadeo = vivo && (t % 4.5) < .14;
      hijos.add(_abs(cx, Bano.rejilla + const Offset(0, -3), 16,
          Transform.scale(scaleY: parpadeo ? .15 : 1, child: const Emoji('👀', tamano: 16))));
    }
    if (b.arepa > 0) {
      final base = Bano.budare + const Offset(0, -9);
      final fase = t % 9;
      final salto = vivo && fase < .6 ? fase / .6 : 0.0;
      if (b.arepa >= 2) hijos.add(_abs(cx, base + const Offset(-5, 3), 22, const Emoji('🫓', tamano: 22)));
      if (b.arepa >= 3) hijos.add(_abs(cx, base + const Offset(14, 3), 22, const Emoji('🫓', tamano: 22)));
      hijos.add(_abs(
          cx,
          base + Offset(b.arepa >= 2 ? 3 : 0, (b.arepa >= 2 ? -4 : 0) - 28 * sin(pi * salto)),
          24,
          Transform.rotate(angle: 2 * pi * salto, child: const Emoji('🫓', tamano: 24))));
      if (b.arepaBrillo) {
        final esc = vivo ? .5 + .5 * sin(t * 2.3).abs() : .8;
        hijos.add(_abs(cx, base + const Offset(22, -12), 12, Transform.scale(scale: esc, child: const Emoji('✨', tamano: 12))));
      }
    }
  }

  // Cada 25 s una ciruela salta del frasco a la poceta.
  void _ciruela(List<Widget> hijos, double cx, double t) {
    final b = widget.bano;
    if (b.ciruela == 0 || t < 15) return;
    final fase = (t - 15) % 25;
    if (fase >= .9) return;
    final f = fase / .9;
    final desde = Bano.frasco + const Offset(0, -12), hasta = Offset(_boca.dx, _cy + _boca.dy);
    final pos = Offset.lerp(desde, hasta, Curves.easeIn.transform(f))! + Offset(0, -46 * sin(pi * f));
    final fruta = Image.asset('assets/emoji/blueberries.png',
        width: 15,
        height: 15,
        filterQuality: FilterQuality.medium,
        color: b.ciruelaVerde ? const Color(0xFF5BD14B).withValues(alpha: .55) : null,
        colorBlendMode: BlendMode.srcATop);
    hijos.add(_abs(cx, pos, 15, Transform.rotate(angle: 6 * f, child: Opacity(opacity: f > .85 ? (1 - f) / .15 : 1, child: fruta))));
  }

  // Cada 2 min (la primera a los 8 s) aparece la taza encima de la poceta y le echa un chorro de café.
  // El chorrito de la poceta japonesa (cada 7 s, dura 1,6 s) y el de la manguerita a presión (cada 11 s, 0,9 s).
  void _chorritos(List<Widget> hijos, double cx, double t) {
    final b = widget.bano;
    final boca = Offset(cx + _boca.dx, _cy + _boca.dy);
    if (b.japones) {
      final e = (t - 3) % 7;
      if (t >= 3 && e < 1.6) {
        hijos.add(Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _Agua(boca + const Offset(10, 2), boca + const Offset(-14, 2), 46, e / 1.6)))));
      }
    }
    if (b.bidet >= 2) {
      final e = (t - 5) % 11;
      if (t >= 5 && e < .9) {
        final d = Offset(cx + Bano.boquilla.dx, Bano.boquilla.dy);
        hijos.add(Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _Agua(d, d + const Offset(-34, 44), 10, e / .9, gotas: true)))));
      }
    }
  }

  void _cafe(List<Widget> hijos, double cx, double t) {
    final b = widget.bano;
    if (b.cafe == 0 || t < 8) return;
    final e = (t - 8) % 120;
    if (e >= 3.4) return;
    final objeto = b.objetoCafe;
    // Dónde flota, cuánto se inclina y por dónde sale el chorro (sin girar), según lo que sea.
    final (Offset centro, double giroFinal, Offset salida, bool espejo, double tam) = switch (objeto) {
      '🫖' => (const Offset(-62, 92), .5, const Offset(16, -2), true, 34.0),
      '💉' => (const Offset(-58, 96), 1.65, const Offset(13, -13), false, 32.0),
      _ => (const Offset(-54, 94), .95, const Offset(3, -12), false, 30.0),
    };
    final aparece = (e / .4).clamp(0.0, 1.0), seVa = ((e - 3.1) / .3).clamp(0.0, 1.0);
    final inclina = Curves.easeOut.transform(aparece) * (1 - seVa);
    final giro = giroFinal * inclina;
    final opacidad = aparece * (1 - seVa);
    final c = Offset(cx + centro.dx, centro.dy);
    final punta = c + Offset(salida.dx * cos(giro) - salida.dy * sin(giro), salida.dx * sin(giro) + salida.dy * cos(giro));
    final boca = Offset(cx + _boca.dx + 4, _cy + _boca.dy + 2);
    final u1 = ((e - .4) / .3).clamp(0.0, 1.0), u0 = ((e - 2.8) / .3).clamp(0.0, 1.0);
    if (u1 > 0 && u0 < 1) {
      final grosor = 3.0 + min(b.cafe - 1, 4) * 1.1;
      hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Chorro(punta, boca, grosor, u0, u1, objeto == '💉')))));
    }
    Widget w = Emoji(objeto, tamano: tam);
    if (espejo) w = Transform.flip(flipX: true, child: w);
    hijos.add(Positioned(
      left: c.dx - tam / 2,
      top: c.dy - tam / 2,
      width: tam,
      height: tam,
      child: Opacity(opacity: opacidad, child: Transform.rotate(angle: giro, child: w)),
    ));
  }
}

/// Agua del bidet: el chorrito de la poceta japonesa (un arco que sube y cae en la taza) o el chorro de la
/// manguerita (gotas que salen en abanico). [f] va de 0 a 1 en lo que dura.
class _Agua extends CustomPainter {
  _Agua(this.desde, this.hasta, this.alto, this.f, {this.gotas = false});

  final Offset desde, hasta;
  final double alto, f;
  final bool gotas;

  static const _color = Color(0xD98FD3F5);

  Offset _en(double u) {
    final x = desde.dx + (hasta.dx - desde.dx) * u;
    final y = desde.dy + (hasta.dy - desde.dy) * u - alto * 4 * u * (1 - u);
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final punta = Paint()..color = _color;
    if (gotas) {
      for (var k = 0; k < 6; k++) {
        final u = (f * 1.4 - k * .08).clamp(0.0, 1.0);
        if (u <= 0 || u >= 1) continue;
        canvas.drawCircle(_en(u) + Offset(0, (k.isEven ? 2.0 : -2.0) * u), 2.2 - k * .2, punta);
      }
      return;
    }
    // Sube y baja de altura con f; la punta del arco lleva una gota.
    final crece = sin(pi * f);
    final camino = Path()..moveTo(desde.dx, desde.dy);
    for (var i = 1; i <= 16; i++) {
      final o = _en(i / 16);
      camino.lineTo(o.dx, desde.dy + (o.dy - desde.dy) * crece);
    }
    canvas.drawPath(
        camino,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = _color);
    final arriba = _en(.5);
    canvas.drawCircle(Offset(arriba.dx, desde.dy + (arriba.dy - desde.dy) * crece - 3), 1.8, punta);
  }

  @override
  bool shouldRepaint(_Agua old) => old.f != f || old.desde != desde;
}

/// El chorro de café de la taza a la poceta: una curva que cae, dibujada entre [u0] y [u1] (0 a 1).
class _Chorro extends CustomPainter {
  _Chorro(this.desde, this.hasta, this.grosor, this.u0, this.u1, this.fino);

  final Offset desde, hasta;
  final double grosor, u0, u1;
  final bool fino; // café en vena: más fino y más oscuro

  Offset _en(double u) {
    final control = Offset(desde.dx + (hasta.dx - desde.dx) * .65, desde.dy - 6);
    final a = 1 - u;
    return desde * (a * a) + control * (2 * a * u) + hasta * (u * u);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final camino = Path();
    const pasos = 14;
    for (var k = 0; k <= pasos; k++) {
      final q = _en(u0 + (u1 - u0) * k / pasos);
      k == 0 ? camino.moveTo(q.dx, q.dy) : camino.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
        camino,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = fino ? grosor * .7 : grosor
          ..color = fino ? const Color(0xFF3E2210) : const Color(0xFF6B3E1F));
    if (u1 >= 1 && u0 < .9) {
      // Salpica un poquito al caer en la taza.
      final gota = Paint()..color = const Color(0xFF6B3E1F);
      canvas.drawCircle(hasta + const Offset(-6, -3), 1.8, gota);
      canvas.drawCircle(hasta + const Offset(5, -4), 1.5, gota);
    }
  }

  @override
  bool shouldRepaint(_Chorro old) => old.u0 != u0 || old.u1 != u1 || old.desde != desde || old.hasta != hasta || old.grosor != grosor;
}
