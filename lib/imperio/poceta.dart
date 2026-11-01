// La poceta del Imperio: el botón grande que se toca para pujar, en medio de su baño (bano.dart).
//
// Cada toque deja caer un mojoncito dentro, sale dinero y sube un "+N". El épico salpica y tiembla. Con muchos
// MJ/s la poceta vibra y echa vapor (la imagen no se tiñe). Alrededor, el baño: el fondo quieto viene de
// [FondoBano] y aquí va lo que se mueve: los dedos que pinchan, el bombillo pelado que parpadea, la gota del grifo,
// la cucaracha, la cucharada de leche de magnesia, el chorro de café, la arepa que salta en el budare, el camión
// vacuum que viene a descargar, el reactor de la planta, la cloaca con sus ojitos, las moscas y la palanca del tanque.
//
// Barato a propósito: un solo Ticker que mueve un ValueNotifier. El fondo va en su propio RepaintBoundary como
// `child` del ValueListenableBuilder, así que no se reconstruye ni se repinta en cada tick. Sin sombras ni saveLayer.
// Con movimiento "completo" el ticker corre mientras se ve; con "simple" solo mientras haya "+N" en el aire y lo
// demás queda en pose quieta; con "nada" no corre nunca.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'bano.dart';
import 'formato.dart';
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
    this.apuro = 1,
    this.alPersonalizar,
    this.jalar,
    this.alJalar,
    this.cartelJalar = false,
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

  /// Cuántas veces más rápido produce que sin efectos (1 = normal). Más "+N" sueltos, escena más acelerada.
  final double apuro;

  /// Abre la hoja de Personalizar (el pincel arriba a la derecha). null = no se ve.
  final VoidCallback? alPersonalizar;

  /// Palanca del tanque: null = no hay cadena; false = gris, todavía no; true = lista, brilla.
  final bool? jalar;
  final VoidCallback? alJalar;

  /// El cartelito "JALAR ⬇" sobre la palanca (solo la primera vez que queda lista).
  final bool cartelJalar;

  /// Solo para pruebas: dibuja la escena quieta en este segundo, como con movimiento completo.
  final double? instante;

  static const topeDedos = 24;

  @override
  State<Poceta> createState() => _PocetaState();
}

enum _Tipo { caida, moneda, flotante, salpicon, gota, tic }

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
  Timer? _tics; // con movimiento "simple": un "+N" suelto cada tanto, sin ticker fijo
  double _jalo = -9; // cuándo se bajó la palanca
  double _cx = 0; // centro de la escena, para saber qué se tocó

  // Palanca del tanque: x relativa al centro, y desde arriba. Pivote y brazo en coordenadas de la poceta (140x140).
  static const _palanca = Offset(11, 100);
  static const _pivote = Offset(88, 20);

  double get _ahora => _reloj.elapsedMicroseconds / 1e6;

  @override
  void dispose() {
    _tics?.cancel();
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  bool get _debeCorrer =>
      widget.instante == null &&
      widget.activo &&
      _mov != Movimiento.nada &&
      (_mov == Movimiento.completo || _particulas.isNotEmpty || _ahora - _jalo < .6);

  void _ajustarTicker() {
    if (_debeCorrer) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    final tics = widget.instante == null && widget.activo && _mov == Movimiento.simple && widget.mps > 0;
    if (tics && _tics == null) {
      _tics = Timer.periodic(const Duration(seconds: 3), (_) => _ticSimple());
    } else if (!tics && _tics != null) {
      _tics!.cancel();
      _tics = null;
    }
  }

  // Movimiento "simple": un "+N" suelto cada 3 s con lo que se ganó en ese rato.
  void _ticSimple() {
    if (!mounted) return;
    final texto = '+${formatoMj(widget.mps * 3, ingles: enIngles)}';
    _agregar(_Particula(_id++, _Tipo.tic, _ahora, 1, x: _azar.nextDouble() * 120 - 60, texto: texto), 2);
    _ajustarTicker();
  }

  // Qué se tocó: el pincel de Personalizar, la palanca o, si no, la poceta (pujar).
  void _pulsar(Offset o) {
    if (widget.alPersonalizar != null && o.dx >= 2 * _cx - 46 && o.dy <= 46) {
      widget.alPersonalizar!();
      return;
    }
    if (widget.jalar != null && Rect.fromCenter(center: Offset(_cx + _palanca.dx, _palanca.dy), width: 48, height: 48).contains(o)) {
      _jalar();
      return;
    }
    _tocar();
  }

  // La palanca baja y sube; si está lista, el remolino arranca cuando ya bajó.
  void _jalar() {
    HapticFeedback.selectionClick();
    final al = widget.alJalar;
    if (_mov != Movimiento.nada) {
      _jalo = _ahora;
      _ajustarTicker();
    }
    if (al == null) return;
    if (widget.jalar == true && _mov != Movimiento.nada) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) al();
      });
    } else {
      al();
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
        onPointerDown: (ev) => _pulsar(ev.localPosition),
        child: RepaintBoundary(
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: p.borde))),
            child: SizedBox(
              height: Bano.altura(widget.bano),
              width: double.infinity,
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, caja) => ValueListenableBuilder<double>(
                    valueListenable: _t,
                    // El fondo no depende del tick: se arma una vez y se repinta solo si cambia el baño.
                    child: RepaintBoundary(child: FondoBano(estado: widget.bano)),
                    builder: (context, t, fondo) {
                      _cx = caja.maxWidth / 2;
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
    // Apuro: con efectos que multiplican la producción la escena va más rápido y tiembla un poco.
    final k = vivo ? ((widget.apuro - 1) / 2).clamp(0.0, 1.0) : 0.0;
    final tv = t * (1 + .6 * k);

    // Apretón al tocar.
    final s = t - _ultimoToque;
    var escala = s >= 0 && s < .14 ? 1 - .08 * sin(pi * s / .14) : 1.0;
    if (vivo) escala *= 1 + .015 * sin(t * 2.4);

    // Temblor: calor, pujo loco y el golpe del épico.
    var dx = 0.0, dy = 0.0, giro = 0.0;
    if (vivo) {
      final amp = (widget.pujoLoco ? 4.5 : (calor > .25 ? 2.2 * (calor - .25) / .75 : 0.0)) + 1.5 * k;
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
    if (vivo) _planta(hijos, cx, tv);
    _cloaca(hijos, cx, t, tv, vivo);
    final trasTaza = <Widget>[]; // la manguera y la lluvia del camión van delante de la poceta
    _camion(context, hijos, trasTaza, encima, cx, t, vivo);

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
          final f = (tv * .9 - i / Poceta.topeDedos) % 1;
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
            if (widget.jalar != null) Positioned.fill(child: CustomPaint(painter: _Palanca(widget.jalar!, _bajada(), vivo ? t : null))),
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

    hijos.addAll(trasTaza);
    _moscas(hijos, cx, vivo ? tv : 3.3, vivo);

    if (vivo) {
      _leche(hijos, cx, t);
      _cafe(hijos, cx, t);
      _chorritos(hijos, cx, t);
      if (k > 0) _apurado(hijos, cx, tv, k);
      if (widget.mps > 0) _sueltos(context, encima, cx, t);
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
        case _Tipo.tic:
          encima.add(_suelto(context, cx + q.x, _cy - 30 - 50 * f, q.texto, .65 * (1 - f), 12, Colors.white, key: llave));
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

    // La primera vez que la cadena queda lista, un cartelito encima de la palanca.
    if (widget.cartelJalar && widget.jalar == true) {
      encima.add(Positioned(
        left: cx + _palanca.dx - 50,
        width: 100,
        top: 62 + (vivo ? 2 * sin(t * 4) : 0),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFFFD60A), border: Border.all(color: Colors.black), borderRadius: BorderRadius.circular(radio)),
            child: Text(tr('JALAR ⬇', 'FLUSH ⬇'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: .5)),
          ),
        ),
      ));
    }
    if (widget.jalar != null) {
      encima.add(Positioned(
        left: cx + _palanca.dx - 24,
        top: _palanca.dy - 24,
        width: 48,
        height: 48,
        child: Semantics(container: true, button: true, label: tr('Jalar la cadena', 'Flush'), onTap: _jalar, child: const SizedBox.expand()),
      ));
    }

    // Pincel de Personalizar, arriba a la derecha.
    if (widget.alPersonalizar != null) {
      encima.add(Positioned(
        right: 6,
        top: 6,
        width: 30,
        height: 30,
        child: Semantics(
          container: true,
          button: true,
          label: tr('Personalizar el baño', 'Customize the bathroom'),
          onTap: widget.alPersonalizar,
          child: DecoratedBox(
            decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
            child: const Center(child: Emoji('🎨', tamano: 18)),
          ),
        ),
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

  // Lo que se mueve del baño: gota, humo, destellos, cucaracha, arepa.
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

  // Azar fijo por número: lo mismo en cada frame, sin guardar nada.
  static double _h(double k) {
    final v = sin(k * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  // Cuánto está bajada la palanca (0 arriba, 1 abajo): baja y sube en medio segundo.
  double _bajada() {
    final d = _ahora - _jalo;
    return d < 0 || d > .5 ? 0 : sin(pi * d / .5);
  }

  // Planta: bolitas por el tubo al reactor, el núcleo que late, humo de la chimenea y destellos.
  void _planta(List<Widget> hijos, double cx, double tv) {
    final p = widget.bano.planta;
    if (p == 0) return;
    hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Planta(cx, p, tv)))));
    if (p >= 4) {
      for (var k = 0; k < 2; k++) {
        final f = (tv * .4 + k * .5) % 1;
        hijos.add(_abs(cx, Bano.chimenea + Offset(4 * sin(f * 6 + k), -10 - 26 * f), 16,
            Opacity(opacity: (1 - f) * .7, child: const Emoji('💨', tamano: 16))));
      }
    }
    if (p >= 8) {
      for (var i = 0; i < 2; i++) {
        final esc = .4 + .6 * sin(tv * 2.1 + i * 2.4).abs();
        hijos.add(_abs(cx, Offset(i == 0 ? 84 : 142, i == 0 ? 142 : 182), 14, Transform.scale(scale: esc, child: const Emoji('✨', tamano: 14))));
      }
    }
  }

  // Cloaca: el flujo por el tubo y el canal, y a los 20 s de mirar salen los ojitos de la oscuridad.
  void _cloaca(List<Widget> hijos, double cx, double t, double tv, bool vivo) {
    final c = widget.bano.cloaca;
    if (c == 0) return;
    if (vivo) {
      final tubo = Bano.tuboCloaca(widget.bano);
      hijos.add(Positioned.fill(
          child: IgnorePointer(
              child: CustomPaint(painter: _Cloaca(Offset(cx + tubo.first.dx, tubo.first.dy), Offset(cx + tubo.last.dx, tubo.last.dy), c, tv)))));
    }
    final opacidad = vivo ? (t - 20).clamp(0.0, 1.0) : 1.0;
    if (opacidad <= 0) return;
    const xs = [-100.0, 70.0, -30.0];
    final n = c >= 4 ? 3 : (c >= 3 ? 2 : 1);
    for (var i = 0; i < n; i++) {
      final parpadeo = vivo && (t + i * 1.7) % 4.5 < .14;
      hijos.add(_abs(cx, Offset(xs[i], 293), 16,
          Opacity(opacity: opacidad, child: Transform.scale(scaleY: parpadeo ? .15 : 1, child: const Emoji('👀', tamano: 16)))));
    }
  }

  // Camión vacuum: cada 40 s (el primero a los 10 s) entra de retroceso, mete la manguera en la poceta, descarga una
  // lluvia de mojones y se va. El cuerpo va detrás de la poceta; la manguera y la lluvia, delante (trasTaza).
  void _camion(BuildContext context, List<Widget> hijos, List<Widget> trasTaza, List<Widget> encima, double cx, double t, bool vivo) {
    final c = widget.bano.camion;
    if (!vivo || c == 0 || t < 10) return;
    final e = (t - 10) % 40;
    if (e >= 9.5) return;
    const parado = -75.0;
    final fuera = -cx - 5;
    final double x;
    if (e < 2.5) {
      x = fuera + (parado - fuera) * Curves.easeOut.transform(e / 2.5);
    } else if (e < 7) {
      x = parado + .6 * sin(t * 40);
    } else {
      x = parado + (fuera - parado) * Curves.easeIn.transform((e - 7) / 2.5);
    }
    final s = c >= 4 ? 1.2 : 1.0;
    final suelo = c >= 9 ? 272 - 46 + 3 * sin(t * 3) : 272.0;
    final largo = (c >= 7 ? 110 : 76) * s;
    final arriba = suelo - 12 * s - 30 * s;
    final cola = cx + x, izq = cola - largo;
    hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Camion(cola, suelo, c, t)))));
    void en(List<Widget> l, Offset o, double tam, Widget w) => l.add(Positioned(left: o.dx - tam / 2, top: o.dy - tam / 2, width: tam, height: tam, child: w));
    en(hijos, Offset(izq + largo / 2, arriba + 15 * s), 16 * s, Emoji('💩', tamano: 16 * s));
    if (c >= 8) en(hijos, Offset(izq - 4 - 3 * s, arriba - 20 * s), 14, Transform.scale(scale: .8 + .25 * sin(t * 19), child: const Emoji('🔥', tamano: 14)));
    if (c >= 9) {
      en(hijos, Offset(izq + largo * .3, arriba - 6), 22, Transform.rotate(angle: -.3 + .25 * sin(t * 9), child: const Emoji('🪽', tamano: 22)));
    }

    // Manguera: sale a 2,5 s, descarga de 3,2 a 6,5 s y se recoge.
    final u = e < 2.5 ? 0.0 : (e < 3.2 ? (e - 2.5) / .7 : (e < 6.5 ? 1.0 : (1 - (e - 6.5) / .5).clamp(0.0, 1.0)));
    final boquilla = Offset(cx + _boca.dx - 6, _cy + _boca.dy - 46);
    final boca = Offset(cx + _boca.dx, _cy + _boca.dy);
    if (u > 0) {
      trasTaza.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Manguera(Offset(cola - 8 * s, arriba + 2), boquilla, u)))));
    }
    if (e >= 3.2 && e < 6.9) {
      final paso = c >= 6 ? .04 : .06;
      for (var k = max(0, ((e - 3.6) / paso).ceil()); 3.2 + k * paso <= min(e, 6.5); k++) {
        final f = (e - 3.2 - k * paso) / .4;
        if (f < 0 || f > 1) continue;
        final tam = 13 + 5 * _h(k + .5);
        final y = boquilla.dy + 4 + (boca.dy - boquilla.dy - 4) * Curves.easeIn.transform(f);
        en(trasTaza, Offset(boquilla.dx + 6 + 16 * (_h(k * 1.0) - .5), y), tam,
            Opacity(opacity: f > .8 ? (1 - f) / .2 : 1, child: Emoji('💩', tamano: tam)));
      }
    }

    // Sonidos escritos (la app no tiene audio).
    void grito(double gx, double gy, String texto, Color color, double tam, double giro) => encima.add(Positioned(
        left: max(4.0, gx),
        top: gy,
        child: IgnorePointer(
            child: Transform.rotate(angle: giro, child: Text(texto, style: _contorno(numeros(context, tamano: tam, weight: FontWeight.w900, color: color)))))));
    final cabina = izq - 34 * s;
    if (e < 2.5 || e >= 7) grito(cabina - 10, arriba - 34 + 2 * sin(t * 30), 'BRRRUM', Colors.white, 13, -.12);
    if (c >= 3 && e < 2.5 && (t * 3) % 1 < .6) grito(cola - 30, arriba - 52, tr('PII PII', 'BEEP BEEP'), acento, 12, .1);
    if (c >= 5 && e >= 2.3 && e < 3) grito(cabina - 6, arriba - 56, tr('TUUUU', 'HOOONK'), Colors.white, 15, -.08);
    if (e >= 3.2 && e < 6.5) grito(boquilla.dx + 26, boquilla.dy - 30 + 3 * sin(t * 9), 'FLUUUSH', const Color(0xFF8FD3F5), 16, .08);
  }

  // Criadero de moscas: vuelan alrededor de la poceta con senos sumados (parece al azar y no da vueltas en redondo).
  void _moscas(List<Widget> hijos, double cx, double tv, bool vivo) {
    final m = widget.bano.moscas;
    if (m == 0) return;
    final n = m >= 4 ? 6 : (m >= 2 ? 3 : 2);
    final reina = m >= 3;
    final bichos = <Widget>[], puestos = <Widget>[];
    for (var i = 0; i < n + (reina ? 1 : 0); i++) {
      final esReina = reina && i == n;
      final f = i * 1.37 + .5;
      final u = tv * (esReina ? .45 : .9);
      final x = 85 * (.6 * sin(u * .9 + f) + .4 * sin(u * 2.3 + f * 2.1));
      final y = 55 * (.6 * cos(u * .7 + f * 1.3) + .4 * sin(u * 1.9 + f * .7));
      final vx = .54 * cos(u * .9 + f) + .92 * cos(u * 2.3 + f * 2.1);
      final zum = vivo ? Offset(1.2 * sin(tv * 47 + i), 1.2 * cos(tv * 53 + i * 2)) : Offset.zero;
      final o = Offset(cx + x, 140 + y) + zum;
      final tam = esReina ? 24.0 : 16.0;
      Widget w = Emoji('🪰', tamano: tam);
      if (vx > 0) w = Transform.flip(flipX: true, child: w);
      bichos.add(Positioned(left: o.dx - tam / 2, top: o.dy - tam / 2, width: tam, height: tam, child: w));
      if (esReina) {
        puestos.add(Positioned(left: o.dx - 6, top: o.dy - tam / 2 - 8, width: 12, height: 12, child: const Emoji('👑', tamano: 12)));
      } else if (m >= 2) {
        puestos.add(Positioned(left: o.dx - 4, top: o.dy - 10, width: 8, height: 8, child: const Emoji('🪖', tamano: 8)));
      }
    }
    final enjambre = Stack(clipBehavior: Clip.none, children: bichos);
    hijos.add(Positioned.fill(
        child: IgnorePointer(child: m >= 5 ? ColorFiltered(colorFilter: ColorFilter.matrix(_tinte(ColorDedo.oro)!), child: enjambre) : enjambre)));
    if (puestos.isNotEmpty) hijos.add(Positioned.fill(child: IgnorePointer(child: Stack(clipBehavior: Clip.none, children: puestos))));
  }

  // Leche de magnesia: cada 12 s (la primera a los 15 s) sale una cuchara de la botella y echa una cucharada en la poceta.
  void _leche(List<Widget> hijos, double cx, double t) {
    final b = widget.bano;
    if (b.leche == 0 || t < 15) return;
    final e = (t - 15) % 12;
    if (e >= 2.2) return;
    final desde = Bano.frasco + const Offset(0, -6);
    const sobre = Offset(-34, 104);
    final boca = Offset(_boca.dx, _cy + _boca.dy);
    Offset pos;
    var giro = 0.0, opacidad = 1.0;
    if (e < .5) {
      final f = Curves.easeOut.transform(e / .5);
      pos = Offset.lerp(desde, sobre, f)! + Offset(0, -20 * sin(pi * f));
      opacidad = (e / .15).clamp(0.0, 1.0);
    } else if (e < 1.3) {
      pos = sobre;
      giro = -.9 * Curves.easeInOut.transform(((e - .5) / .3).clamp(0.0, 1.0));
    } else {
      final f = (e - 1.3) / .9;
      pos = Offset.lerp(sobre, desde, Curves.easeIn.transform(f))!;
      giro = -.9 * (1 - f);
      opacidad = 1 - f;
    }
    hijos.add(_abs(cx, pos, 26, Opacity(opacity: opacidad, child: Transform.rotate(angle: giro, child: const Emoji('🥄', tamano: 26)))));
    if (e >= .8 && e < 1.3) {
      final f = Curves.easeIn.transform((e - .8) / .5);
      final color = b.lecheNuclear ? const Color(0xFFB6FF3B) : (b.lecheVerde ? const Color(0xFF7BE36B) : const Color(0xFFF7F7F2));
      hijos.add(_abs(
          cx,
          Offset(sobre.dx - 6 + (boca.dx - sobre.dx + 6) * f, sobre.dy + 2 + (boca.dy - sobre.dy - 2) * f),
          10,
          DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6E6E6A))))));
    }
  }

  // Apurado: rayas de velocidad a los lados y destellos que dan vueltas a la poceta.
  void _apurado(List<Widget> hijos, double cx, double tv, double k) {
    hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Rayas(k, tv)))));
    if (k <= .3) return;
    for (var i = 0; i < 3; i++) {
      final a = tv * 1.5 + i * 2 * pi / 3;
      hijos.add(_en(cx, Offset(cos(a) * 95, sin(a) * 80), 14, Opacity(opacity: k, child: const Emoji('✨', tamano: 14))));
    }
  }

  // "+N" sueltos de la producción pasiva: ~4 por segundo, más con apuro (tope 14); pasado el tope crecen y se doran.
  void _sueltos(BuildContext context, List<Widget> encima, double cx, double t) {
    final apuro = widget.apuro.isFinite ? widget.apuro : 1.0;
    final r = (4 * apuro).clamp(2.0, 14.0);
    final extra = (4 * apuro / 14 - 1).clamp(0.0, 1.0);
    final texto = '+${formatoMj(widget.mps / r, ingles: enIngles)}';
    for (var k = ((t - .9) * r).floor() + 1; k <= (t * r).floor(); k++) {
      final f = (t - k / r) / .9;
      if (f < 0 || f > 1) continue;
      encima.add(_suelto(context, cx + 180 * (_h(k * 1.0) - .5), 100 + 60 * _h(k + .37) - 50 * f, texto, .65 * (1 - f),
          extra > 0 ? 12 + 6 * extra : 12, extra > 0 ? acento : Colors.white));
    }
  }

  // Un "+N" suelto: más chico y más tenue que el de los toques.
  Widget _suelto(BuildContext context, double x, double y, String texto, double opacidad, double tam, Color color, {Key? key}) => Positioned(
        key: key,
        left: x - 60,
        width: 120,
        top: y,
        child: IgnorePointer(
          child: Opacity(
            opacity: opacidad.clamp(0.0, 1.0),
            child: montoMj(texto, _contorno(numeros(context, tamano: tam, weight: FontWeight.w800, color: color)), alineacion: Alignment.center),
          ),
        ),
      );

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

// Camión vacuum de perfil, con la cabina a la izquierda y la cola (la cisterna) a la derecha, hacia la poceta.
class _Camion extends CustomPainter {
  final double cola, suelo, t;
  final int nivel;
  _Camion(this.cola, this.suelo, this.nivel, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = nivel;
    final s = c >= 4 ? 1.2 : 1.0;
    final largo = (c >= 7 ? 110 : 76) * s;
    final chasis = suelo - 12 * s;
    final arriba = chasis - 30 * s;
    final izq = cola - largo;
    final cab = izq - 34 * s;
    final borde = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final colorCab = c >= 2 ? const Color(0xFFD0342C) : const Color(0xFF5E7D4A);
    final colorTanque = c >= 2 ? const Color(0xFFC9D1D9) : const Color(0xFF8A8F94);

    // Chasis
    final base = Rect.fromLTRB(cab, chasis - 4 * s, cola, chasis + 2 * s);
    canvas.drawRect(base, Paint()..color = const Color(0xFF2B2B2B));
    // Cisterna (una o dos)
    final tanques = c >= 6 ? 2 : 1;
    final ancho = largo / tanques;
    for (var i = 0; i < tanques; i++) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTRB(izq + i * ancho + 2, arriba, izq + (i + 1) * ancho - 2, chasis - 4 * s), Radius.circular(12 * s));
      canvas.drawRRect(r, Paint()..color = colorTanque);
      if (c < 2) {
        canvas.drawCircle(Offset(r.left + ancho * .3, r.top + 10 * s), 4 * s, Paint()..color = const Color(0xFF8B5A2B));
        canvas.drawCircle(Offset(r.left + ancho * .7, r.bottom - 7 * s), 3 * s, Paint()..color = const Color(0xFF8B5A2B));
      } else {
        canvas.drawRect(Rect.fromLTRB(r.left + 6, r.center.dy - 2 * s, r.right - 6, r.center.dy + 2 * s), Paint()..color = acento);
      }
      canvas.drawRRect(r, borde);
    }
    // Cabina con el frente inclinado
    final cabina = Path()
      ..moveTo(izq, chasis - 4 * s)
      ..lineTo(izq, arriba + 2 * s)
      ..lineTo(cab + 12 * s, arriba + 2 * s)
      ..lineTo(cab, arriba + 16 * s)
      ..lineTo(cab, chasis - 4 * s)
      ..close();
    canvas.drawPath(cabina, Paint()..color = colorCab);
    canvas.drawPath(cabina, borde);
    final vidrio = Path()
      ..moveTo(izq - 6 * s, arriba + 6 * s)
      ..lineTo(cab + 13 * s, arriba + 6 * s)
      ..lineTo(cab + 5 * s, arriba + 16 * s)
      ..lineTo(izq - 6 * s, arriba + 16 * s)
      ..close();
    canvas.drawPath(vidrio, Paint()..color = const Color(0xFF9FD3F0));
    canvas.drawPath(vidrio, borde);
    // Escape con fuego (los efectos van en la poceta)
    if (c >= 8) canvas.drawRect(Rect.fromLTRB(izq - 6 * s, arriba - 12 * s, izq - 2 * s, arriba + 2 * s), Paint()..color = const Color(0xFF555555));
    // Hélice arriba de la cisterna (volador)
    if (c >= 9) {
      final eje = Offset(izq + largo * .55, arriba - 6);
      canvas.drawLine(Offset(eje.dx, arriba), eje, borde..strokeWidth = 2);
      final w = 30 * cos(t * 30).abs() + 4;
      canvas.drawRect(Rect.fromCenter(center: eje, width: w, height: 3), Paint()..color = const Color(0xFF333333));
      borde.strokeWidth = 1;
    }
    // Ruedas con un rayo que gira
    final ruedas = <double>[cab + 10 * s, cola - 12 * s, if (c >= 7) cola - 30 * s];
    for (final x in ruedas) {
      final o = Offset(x, suelo - 7 * s);
      canvas.drawCircle(o, 7 * s, Paint()..color = const Color(0xFF222222));
      canvas.drawCircle(o, 3 * s, Paint()..color = const Color(0xFF9A9A9A));
      final a = -t * 8;
      canvas.drawLine(o, o + Offset(cos(a), sin(a)) * 6 * s, Paint()
        ..color = const Color(0xFF9A9A9A)
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// Manguera del camión a la poceta: curva que se estira según u (0 a 1).
class _Manguera extends CustomPainter {
  final Offset desde, hasta;
  final double u;
  _Manguera(this.desde, this.hasta, this.u);

  @override
  void paint(Canvas canvas, Size size) {
    final control = Offset((desde.dx + hasta.dx) / 2, min(desde.dy, hasta.dy) - 40);
    final camino = Path()
      ..moveTo(desde.dx, desde.dy)
      ..quadraticBezierTo(control.dx, control.dy, hasta.dx, hasta.dy);
    final m = camino.computeMetrics().first;
    final trozo = m.extractPath(0, m.length * u);
    canvas.drawPath(trozo, Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6);
    canvas.drawPath(trozo, Paint()
      ..color = const Color(0xFF6B6B6B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    if (u >= 1) canvas.drawRect(Rect.fromCenter(center: hasta, width: 10, height: 6), Paint()..color = const Color(0xFF2A2A2A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// Planta: bolitas por el tubo, núcleo que late y luces que parpadean (el reactor quieto lo pinta FondoBano).
class _Planta extends CustomPainter {
  final double cx, tv;
  final int nivel;
  _Planta(this.cx, this.nivel, this.tv);

  @override
  void paint(Canvas canvas, Size size) {
    final p = nivel;
    final tubo = [for (final o in Bano.tuboPlanta) Offset(cx + o.dx, o.dy)];
    var total = 0.0;
    for (var i = 1; i < tubo.length; i++) {
      total += (tubo[i] - tubo[i - 1]).distance;
    }
    final n = 3 + min(p, 4);
    final bola = Paint()..color = const Color(0xFF6B3E1F);
    final aro = Paint()
      ..color = const Color(0xFF2A1A0E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var k = 0; k < n; k++) {
      var d = ((tv * .35 + k / n) % 1) * total;
      for (var i = 1; i < tubo.length; i++) {
        final l = (tubo[i] - tubo[i - 1]).distance;
        if (d <= l) {
          final o = Offset.lerp(tubo[i - 1], tubo[i], d / l)!;
          canvas.drawCircle(o, 3.5, bola);
          canvas.drawCircle(o, 3.5, aro);
          break;
        }
        d -= l;
      }
    }
    // Núcleo que late
    final nucleo = Bano.nucleo.shift(Offset(cx, 0));
    final latido = .5 + .5 * sin(tv * 3);
    final verde = p >= 6 ? const Color(0xFF8CFF5A) : const Color(0xFF5BD14B);
    canvas.drawRect(nucleo.inflate(2 + 3 * latido), Paint()..color = verde.withValues(alpha: .18 + .2 * latido));
    canvas.drawRect(nucleo.deflate(3), Paint()..color = verde.withValues(alpha: .35 + .45 * latido));
    // Luces rojas
    if (p >= 3) {
      for (var i = 0; i < Bano.lucesReactor.length; i++) {
        if ((tv * 2 + i * .5) % 1 < .5) {
          canvas.drawCircle(Bano.lucesReactor[i] + Offset(cx, 0), 3, Paint()..color = const Color(0xFFFF3B30));
        }
      }
    }
    // Electrón que da vueltas en la órbita
    if (p >= 9) {
      final o = Bano.orbita.shift(Offset(cx, 0));
      final a = tv * 2.4;
      canvas.drawCircle(o.center + Offset(cos(a) * o.width / 2, sin(a) * o.height / 2), 3, Paint()..color = acento);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// Cloaca: rayitas que bajan por el tubo y corren por el canal.
class _Cloaca extends CustomPainter {
  final Offset a, b;
  final int nivel;
  final double tv;
  _Cloaca(this.a, this.b, this.nivel, this.tv);

  @override
  void paint(Canvas canvas, Size size) {
    final color = nivel >= 4 ? const Color(0xFF8CFF5A) : const Color(0xFF6B4A2A);
    final raya = Paint()
      ..color = color
      ..strokeWidth = 3;
    final largo = (b - a).distance;
    final dir = (b - a) / largo;
    for (var d = (tv * 40) % 12; d < largo - 5; d += 12) {
      canvas.drawLine(a + dir * d, a + dir * (d + 5), raya);
    }
    const y = 309.0;
    final canal = Paint()
      ..color = color.withValues(alpha: .8)
      ..strokeWidth = 2;
    for (var x = (tv * 30) % 22 - 22; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, y), Offset(x + 8, y), canal);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// Rayas de velocidad que suben por los bordes cuando la producción va apurada.
class _Rayas extends CustomPainter {
  final double k, tv;
  _Rayas(this.k, this.tv);

  @override
  void paint(Canvas canvas, Size size) {
    final pintura = Paint()
      ..color = Colors.white.withValues(alpha: .35 * k)
      ..strokeWidth = 2;
    for (var i = 0; i < 8; i++) {
      final lado = i.isEven;
      final x = lado ? 6.0 + (i * 7) % 30 : size.width - 6 - (i * 7) % 30;
      final y = size.height - ((tv * 260 + i * 53) % (size.height + 40));
      canvas.drawLine(Offset(x, y), Offset(x, y + 18 + 10 * k), pintura);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// Palanca del tanque: gris si la cadena no está lista; amarilla y con halo que late cuando sí (t != null = animada).
class _Palanca extends CustomPainter {
  final bool lista;
  final double baja;
  final double? t;
  _Palanca(this.lista, this.baja, this.t);

  static const _pivote = _PocetaState._pivote;

  @override
  void paint(Canvas canvas, Size size) {
    final a = .6 * baja;
    final punta = _pivote + Offset(-cos(a), sin(a)) * 14;
    final color = lista ? acento : const Color(0xFF8C8C8C);
    if (lista) {
      final latido = t == null ? 1.0 : .5 + .5 * sin(t! * 5);
      canvas.drawCircle(punta, 7 + 2 * latido, Paint()..color = acento.withValues(alpha: .25 + .25 * latido));
    }
    canvas.drawRect(Rect.fromCenter(center: _pivote, width: 8, height: 6), Paint()..color = const Color(0xFFD9DEE3));
    canvas.drawRect(Rect.fromCenter(center: _pivote, width: 8, height: 6), Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    canvas.drawLine(_pivote, punta, Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.square);
    canvas.drawLine(_pivote, punta, Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square);
    canvas.drawCircle(punta, 3.5, Paint()..color = color);
    canvas.drawCircle(punta, 3.5, Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
