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
    this.llenar = false,
    this.alTocarObjeto,
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

  /// Cuántos dedos se ven. Hasta [topeDedos] (lo que deja elegir Personalizar) se dibujan todos en el arco; más que
  /// eso es "todos": se ven [visiblesDedos] y el total va en la placa.
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

  /// Ocupa todo el alto que le den: sale más pared arriba y más piso abajo, la poceta queda igual.
  final bool llenar;

  /// Se tocó una cosa del baño (el bidet, el tobo, la cucaracha...). Va además del pujo: ese toque igual puja. El id
  /// es el de [Bano.objetoEn], o 'cucaracha' / 'camion' (los que se mueven).
  final void Function(String id)? alTocarObjeto;

  /// Solo para pruebas: dibuja la escena quieta en este segundo, como con movimiento completo.
  final double? instante;

  static const topeDedos = 24;

  /// Los que se ven con "todos" cuando hay más de [topeDedos]: una sola fila en el arco, sin tapar nada.
  static const visiblesDedos = 12;

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

  // Los dedos van en un arco por debajo de la poceta, de la altura de la taza para abajo (arriba quedan el tanque, la
  // palanca y el papel), de [_arcoDesde] a [_arcoHasta] en radianes (0 a la derecha, pi/2 abajo). Óvalo angosto: no
  // llega al lavamanos ni al reactor.
  static const _arcoDesde = 0.0, _arcoHasta = pi;
  static const _radioDedos = 70.0, _altoDedos = 80.0;

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
  double _arriba = 0; // con llenar: pared de más encima de la escena
  double _suelo = 0; // con llenar: piso de más que entra en la escena (las cosas del piso se reparten en él)
  final _reacciones = <String, double>{}; // cuándo se tocó cada cosa del baño, para su animación
  final _veces = <String, int>{}; // cuántas veces en esta sesión (cada 5 al bidet: chorro en la cara)
  final _donde = <String, Offset>{}; // dónde se tocó (la cucaracha se mueve: su grito sale ahí)
  static const _dura = 1.4; // lo que dura la reacción de una cosa tocada

  // Palanca del tanque: la manija cromada en la cara del tanque, justo bajo la tapa, que sale hacia el frente (a la
  // izquierda). _palanca es la zona de toque (x relativa al centro, y desde arriba); _pivote, el eje de la manija en
  // coordenadas de la poceta (140x140): el tanque de toilet.png va de x 87 a 123 y la tapa termina en y ~13.
  static const _palanca = Offset(11, 100);
  static const _pivote = Offset(97, 21);

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
      (_mov == Movimiento.completo || _particulas.isNotEmpty || _ahora - _jalo < .6 || _reaccionando);

  bool get _reaccionando => _reacciones.values.any((r) => _ahora - r < _dura);

  LugaresBano get _lugar => Bano.lugares(widget.bano, _suelo);

  // Cuánto va la reacción de lo que se tocó (0 a 1), o null si no hay.
  double? _reaccion(String id, double t, [double dura = _dura]) {
    final r = _reacciones[id];
    if (r == null) return null;
    final d = t - r;
    return d >= 0 && d < dura ? d / dura : null;
  }

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

  // Qué se tocó: el pincel de Personalizar, la palanca o, si no, la poceta (pujar). Una cosa del baño hace lo suyo y
  // además puja: tocar la escena nunca deja de pujar.
  void _pulsar(Offset o) {
    if (widget.alPersonalizar != null && o.dx >= 2 * _cx - 46 && o.dy <= 46) {
      widget.alPersonalizar!();
      return;
    }
    if (widget.jalar != null && Rect.fromCenter(center: Offset(_cx + _palanca.dx, _arriba + _palanca.dy), width: 48, height: 48).contains(o)) {
      _jalar();
      return;
    }
    final q = o - Offset(0, _arriba);
    final id = _objetoEn(q);
    if (id != null) {
      if (_mov != Movimiento.nada) {
        _reacciones[id] = _ahora;
        _veces[id] = (_veces[id] ?? 0) + 1;
        _donde[id] = q - Offset(_cx, 0);
      }
      widget.alTocarObjeto?.call(id);
    }
    _tocar();
  }

  // Qué cosa del baño hay en [q] (x absoluta, y desde arriba de la escena). Primero lo que se mueve y va delante.
  String? _objetoEn(Offset q) {
    if (_mov == Movimiento.completo && widget.instante == null) {
      final c = _cucaracha(_cx, _ahora);
      if (c != null && !c.huye && (q - c.o).distance < 22) return 'cucaracha';
      // El budare que va delante del camión gana el toque.
      final l = _lugar;
      if (l.budareDelante && widget.bano.arepa > 0 && Bano.cajaArepa(l).contains(q - Offset(_cx, 0))) return 'arepa';
      if (_cajaCamion(_cx, _ahora)?.contains(q) ?? false) return 'camion';
    }
    return Bano.objetoEn(widget.bano, q - Offset(_cx, 0), _suelo);
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
            child: LayoutBuilder(builder: (context, fuera) {
              final nativo = Bano.altura(widget.bano);
              final alto = widget.llenar && fuera.hasBoundedHeight && fuera.maxHeight > nativo ? fuera.maxHeight : nativo;
              // Lo que sobra: un poco más de pared arriba y el resto de piso hacia uno.
              _arriba = ((alto - nativo) * .4).roundToDouble();
              final abajo = alto - nativo - _arriba;
              // El piso de más entra en la escena (sin cloaca, que pinta su sótano ahí): las cosas del piso bajan a él.
              _suelo = abajo > 0 && widget.bano.cloaca == 0 ? abajo : 0.0;
              final abajoFuera = _suelo > 0 ? 0.0 : abajo;
              return SizedBox(
                height: alto,
                width: double.infinity,
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, caja) {
                      _cx = caja.maxWidth / 2;
                      final escena = ValueListenableBuilder<double>(
                        valueListenable: _t,
                        // El fondo no depende del tick: se arma una vez y se repinta solo si cambia el baño.
                        child: RepaintBoundary(child: FondoBano(estado: widget.bano, techo: _arriba == 0)),
                        builder: (context, t, fondo) {
                          final vivo = fijo != null || _mov == Movimiento.completo;
                          return _dibujo(context, caja.maxWidth / 2, fijo ?? (_mov == Movimiento.nada ? 0 : t), vivo, fondo!);
                        },
                      );
                      if (alto == nativo && widget.efectos.isEmpty && widget.alPersonalizar == null) return escena;
                      return Stack(children: [
                        if (_arriba > 0) Positioned(top: 0, left: 0, right: 0, height: _arriba, child: _pared(nativo)),
                        if (abajoFuera > 0)
                          Positioned(
                            top: _arriba + nativo,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: RepaintBoundary(child: CustomPaint(painter: _PintorSuelo(widget.bano), child: const SizedBox.expand())),
                          ),
                        Positioned(top: _arriba, left: 0, right: 0, height: nativo + _suelo, child: escena),
                        if (alto > nativo || widget.efectos.isNotEmpty)
                          Positioned.fill(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _t,
                              builder: (context, t, _) {
                                final vivo = fijo != null || _mov == Movimiento.completo;
                                return Stack(children: _esquinas(context, fijo ?? (_mov == Movimiento.nada ? 0 : t), vivo, nativo, abajoFuera));
                              },
                            ),
                          )
                        else
                          ..._esquinas(context, 0, false, nativo, abajoFuera),
                      ]);
                    },
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // La franja de arriba de la pared, estirada hacia el techo: sigue la pintura, el cable del bombillo, las columnas
  // y el tinte del ambiente sin dibujar nada nuevo. La mancha de humedad no se estira: va pegada al techo nuevo.
  Widget _pared(double nativo) => RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: [
          ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: nativo,
            maxHeight: nativo,
            child: LayoutBuilder(
              builder: (context, caja) => Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.diagonal3Values(1, _arriba / 2, 1),
                child: CustomPaint(painter: PintorBano(widget.bano, techo: false, estirar: true), size: Size(caja.maxWidth, nativo)),
              ),
            ),
          ),
        ),
          CustomPaint(painter: PintorMancha(widget.bano)),
        ]),
      );

  // Lo que va pegado a las esquinas de todo el espacio (no de la escena): objetos activos, pincel y, sin bombillo,
  // el parpadeo de la luz también en la pared y el piso de más.
  List<Widget> _esquinas(BuildContext context, double t, bool vivo, double nativo, double abajo) {
    final p = paleta(context);
    final l = <Widget>[];
    if (vivo && !widget.bano.bombillo && (_arriba > 0 || abajo > 0)) {
      final g = t % 7.3;
      if (g < .08 || (g > .16 && g < .22) || (g > .3 && g < .5)) {
        const sombra = ColoredBox(color: Color(0x47000000));
        if (_arriba > 0) l.add(Positioned(top: 0, left: 0, right: 0, height: _arriba, child: sombra));
        if (abajo > 0) l.add(Positioned(top: _arriba + nativo, left: 0, right: 0, bottom: 0, child: sombra));
      }
    }

    // Objetos activos, arriba a la izquierda en una ficha (la pareja del pincel de la derecha).
    if (widget.efectos.isNotEmpty) {
      l.add(Positioned(
        left: 6,
        top: 6,
        height: 30,
        child: DecoratedBox(
          decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < widget.efectos.length && i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Transform.translate(offset: Offset(0, vivo ? 1.5 * sin(t * 2 + i) : 0), child: Emoji(widget.efectos[i], tamano: 20)),
                ),
            ]),
          ),
        ),
      ));
    }

    // Pincel de Personalizar, arriba a la derecha.
    if (widget.alPersonalizar != null) {
      l.add(Positioned(
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
    return l;
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
    _cuadro(hijos, cx, t, vivo);
    if (vivo) _planta(hijos, cx, tv);
    _cloaca(hijos, cx, t, tv, vivo);
    final trasTaza = <Widget>[]; // la manguera y la lluvia del camión van delante de la poceta
    _camion(context, hijos, trasTaza, encima, cx, t, vivo);
    if (_lugar.budareDelante) _arepas(hijos, cx, t, vivo);

    // Dedos en un arco por los lados y por debajo, apuntando a la poceta. Hasta [Poceta.visiblesDedos] van en una
    // fila; los que se eligen de más (hasta [Poceta.topeDedos]) se achican y se alternan en dos filas. Con "todos" y más
    // de [Poceta.topeDedos] se ven [Poceta.visiblesDedos] y el número va en la placa. El pinchazo recorre el arco como
    // una ola. Todos van bajo un solo ColorFiltered (una capa, no una por dedo); lo que llevan puesto va aparte, sin teñir.
    final nDedos = widget.dedos > Poceta.topeDedos ? Poceta.visiblesDedos : widget.dedos;
    if (nDedos > 0) {
      final dedos = <Widget>[], puestos = <Widget>[];
      final apretado = ((nDedos - Poceta.visiblesDedos) / (Poceta.topeDedos - Poceta.visiblesDedos)).clamp(0.0, 1.0);
      final tam = 28 - 9 * apretado;
      for (var i = 0; i < nDedos; i++) {
        final a = _arcoDesde + (_arcoHasta - _arcoDesde) * (i + .5) / nDedos;
        var r = 1 + (i.isOdd ? .12 : -.04) * apretado;
        if (vivo) {
          final f = (tv * .9 - i / nDedos) % 1;
          if (f < .15) r -= .075 * sin(pi * f / .15);
        }
        final o = Offset(cos(a) * _radioDedos * r, sin(a) * _altoDedos * r);
        final (dedo, puesto) = _dedo(i, a, tam / 32);
        dedos.add(_en(cx, o, tam, dedo));
        if (puesto != null) puestos.add(_en(cx, o, tam, puesto));
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
      _edificiosVivos(hijos, cx, t);
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

    _tocados(context, hijos, encima, cx, t, vivo);

    // Bombillo pelado: se va la luz un momentico cada tanto.
    if (vivo && !b.bombillo) {
      final g = t % 7.3;
      if (g < .08 || (g > .16 && g < .22) || (g > .3 && g < .5)) {
        hijos.add(const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x47000000)))));
      }
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

    // Más dedos de los que caben: el número en una placa.
    if (widget.dedos > Poceta.topeDedos) {
      // Justo debajo del arco de dedos, centrada (el canal de la cloaca queda libre).
      encima.add(Positioned(
        left: cx - 50,
        width: 100,
        top: _cy + _altoDedos + 16,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Emoji('👆', tamano: 14),
              const SizedBox(width: 3),
              Text('x${widget.dedos}', style: numeros(context, tamano: 11, weight: FontWeight.w800)),
            ]),
          ),
        ),
      ));
    }

    return Stack(clipBehavior: Clip.hardEdge, children: [...hijos, ...encima]);
  }

  // Lo que hace cada cosa del baño cuando la tocan. Con movimiento completo ([vivo]) la animación y el grito; con
  // "simple", solo el grito (barato); con "nada" no llega ninguna reacción. El tobo, la matica, la arepa, la
  // cucaracha y el camión se animan donde se dibujan.
  void _tocados(BuildContext context, List<Widget> hijos, List<Widget> encima, double cx, double t, bool vivo) {
    if (_reacciones.isEmpty) return;
    final b = widget.bano;
    final l = _lugar;
    // Grito: sube un poco y se apaga al final. o con x relativa al centro, y desde arriba.
    void grito(Offset o, String texto, Color color, double f, {double tam = 15}) {
      final x = min(max(cx + o.dx, 110.0), max(110.0, 2 * cx - 110));
      encima.add(Positioned(
        left: x - 110,
        width: 220,
        top: o.dy - tam - 18 * f,
        child: IgnorePointer(
          child: Opacity(
            opacity: f < .7 ? 1 : (1 - f) / .3,
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(texto, textAlign: TextAlign.center, maxLines: 1, style: _contorno(numeros(context, tamano: tam, weight: FontWeight.w900, color: color)))),
          ),
        ),
      ));
    }

    Widget pinta(CustomPainter p) => Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: p)));
    const agua = Color(0xFF8FD3F5);

    if (_reaccion('bidet', t) case final f?) {
      final d = Bano.chorroBidet(l) + Offset(cx, 0);
      final cara = (_veces['bidet'] ?? 0) % 5 == 0;
      if (vivo) {
        if (cara) {
          // Cada quinto toque, el chorro sale torcido y te da en la cara.
          // Sale hacia la izquierda, por el hueco entre la poceta y el reactor, sin subirle encima a nada.
          final fin = d + const Offset(-46, -4);
          final alto = Bano.altoChorro(l, b, 110);
          hijos.add(pinta(_Agua(d, fin, alto, f)));
          hijos.add(pinta(_Agua(d, fin + const Offset(-8, 12), alto * .8, f, gotas: true)));
          final g = (f * 2.5).clamp(0.0, 1.0);
          hijos.add(Positioned(left: fin.dx - 20, top: fin.dy - 20, width: 40, height: 40,
              child: IgnorePointer(child: Opacity(opacity: g * (f < .8 ? 1 : (1 - f) / .2), child: Transform.scale(scale: .5 + g, child: const Emoji('💦', tamano: 40))))));
        } else {
          // Fuente: un chorro al centro y dos que caen al piso por los lados (bajitos para no mojar el reactor).
          final alto = Bano.altoChorro(l, b, 70 * l.escalaBidet);
          hijos.add(pinta(_Agua(d, d + const Offset(4, 0), alto, f)));
          hijos.add(pinta(_Agua(d, d + Offset(-34 * l.escalaBidet, 34 * l.escalaBidet), alto * .8, f, gotas: true)));
          hijos.add(pinta(_Agua(d, d + Offset(36 * l.escalaBidet, 36 * l.escalaBidet), alto * .8, f, gotas: true)));
        }
      }
      grito(l.bidet + Offset(cara ? -40 : 0, -60 * l.escalaBidet), cara ? tr('¡EN LA CARA!', 'RIGHT IN THE FACE!') : tr('¡FSSSHH!', 'FSSSHH!'), agua, f,
          tam: cara ? 17 : 15);
    }
    if (_reaccion('tobo', t) case final f?) {
      final pipote = b.tanque > 0;
      if (vivo && pipote) {
        for (var i = 0; i < 3; i++) {
          final u = (f * 1.6 - i * .2).clamp(0.0, 1.0);
          if (u <= 0 || u >= 1) continue;
          hijos.add(_abs(cx, l.tobo + Offset(-8.0 + 8 * i, -30 - 40 * u), 16, Opacity(opacity: 1 - u, child: const Emoji('🫧', tamano: 16))));
        }
      }
      grito(l.tobo + Offset(0, -l.tamTobo / 2 - 12), pipote ? 'GLUP GLUP' : 'CLONK', Colors.white, f);
    }
    if (_reaccion('bombillo', t) case final f?) {
      if (vivo) {
        if (f < .8 && (f * 9).floor().isEven) hijos.add(const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x5C000000)))));
        hijos.add(_abs(cx, Bano.bombillo + Offset(14, -6 + 4 * sin(t * 30)), 18, Opacity(opacity: 1 - f, child: const Emoji('✨', tamano: 18))));
      }
      grito(Bano.bombillo + const Offset(0, 50), tr('¡BZZT!', 'BZZT!'), acento, f);
    }
    if (_reaccion('espejo', t) case final f?) {
      if (vivo) {
        final s = Curves.elasticOut.transform(min(1.0, f * 2.5));
        hijos.add(_abs(cx, Offset(Bano.lavamanos, 59), 30,
            Opacity(opacity: f < .8 ? 1 : (1 - f) / .2, child: Transform.scale(scale: s, child: const Emoji('👀', tamano: 30)))));
      }
      grito(const Offset(Bano.lavamanos, 30), tr('¡QUÉ PINTA!', 'LOOKING GOOD!'), Colors.white, f);
    }
    if (_reaccion('lavamanos', t) case final f?) {
      if (vivo) {
        for (var i = 0; i < 4; i++) {
          final u = (f * 1.8 - i * .22).clamp(0.0, 1.0);
          if (u <= 0 || u >= 1) continue;
          hijos.add(_abs(cx, Bano.grifo + Offset(0, 4 + 26 * u * u), 12, Opacity(opacity: 1 - u * u, child: const Emoji('💧', tamano: 12))));
        }
      }
      grito(Bano.grifo + const Offset(0, 60), 'PLIC PLOC', agua, f);
    }
    if (_reaccion('reactor', t) case final f?) {
      if (vivo) {
        final a = (.45 * (1 - f) * sin(f * pi * 7).abs()).clamp(0.0, 1.0);
        hijos.add(Positioned.fromRect(rect: Bano.reactor.shift(Offset(cx, 0)), child: IgnorePointer(child: ColoredBox(color: const Color(0xFFFF4D3D).withValues(alpha: a)))));
      }
      grito(Offset(Bano.reactor.center.dx - 20, Bano.reactor.top - 4), tr('¡ALERTA!', 'ALERT!'), const Color(0xFFFF4D3D), f, tam: 16);
    }
    if (_reaccion('arepa', t) case final f?) grito(l.budare + const Offset(0, -40), tr('¡VUELTA!', 'FLIP!'), acento, f);
    if (_reaccion('matica', t) case final f?) grito(l.matica + const Offset(-20, -30), tr('¡RIÉGAME!', 'WATER ME!'), const Color(0xFF7BD88F), f);
    if (_reaccion('ventana', t) case final f?) {
      if (vivo) {
        final sube = sin(pi * f);
        hijos.add(_abs(cx, Offset(Bano.ventana.center.dx, Bano.ventana.bottom - 6 - 20 * sube), 26, Opacity(opacity: sube.clamp(0.0, 1.0), child: const Emoji('👻', tamano: 26))));
      }
      grito(Offset(Bano.ventana.center.dx, Bano.ventana.bottom + 22), 'TOC TOC', Colors.white, f);
    }
    if (_reaccion('papel', t) case final f?) {
      if (vivo) {
        final y = Bano.papel.dy + (Bano.alto - 14 - Bano.papel.dy) * Curves.easeIn.transform(min(1.0, f * 1.6));
        hijos.add(_abs(cx, Offset(Bano.papel.dx + 10 * f, y), 18,
            Opacity(opacity: f < .8 ? 1 : (1 - f) / .2, child: Transform.rotate(angle: 4 * pi * f, child: const Emoji('🧻', tamano: 18)))));
      }
      grito(Bano.papel + const Offset(0, -18), 'RRRIP', Colors.white, f);
    }
    if (_reaccion('banera', t) case final f?) {
      if (vivo) {
        final salto = (sin(f * pi * 3)).abs() * (1 - f);
        hijos.add(_abs(cx, Offset(Bano.banera.center.dx - 10, Bano.banera.top - 8 - 26 * salto), 22, const Emoji('🦆', tamano: 22)));
        hijos.add(_abs(cx, Offset(Bano.banera.center.dx + 16, Bano.banera.top - 6 - 30 * f), 14, Opacity(opacity: 1 - f, child: const Emoji('🫧', tamano: 14))));
      }
      grito(Offset(Bano.banera.center.dx - 30, Bano.banera.top - 36), tr('¡CUAC!', 'QUACK!'), acento, f);
    }
    if (_reaccion('ducha', t) case final f?) grito(Bano.ducha + const Offset(-20, 44), tr('¡AGUA FRÍA!', 'COLD WATER!'), agua, f);
    if (_reaccion('cuadro', t) case final f?) {
      final torcido = (_veces['cuadro'] ?? 0).isOdd;
      grito(Bano.cuadro + const Offset(0, 36), torcido ? tr('¡TORCIDO!', 'CROOKED!') : tr('¡DERECHITO!', 'STRAIGHT!'), Colors.white, f);
    }
    if (_reaccion('cucaracha', t) case final f?) {
      grito((_donde['cucaracha'] ?? Offset(0, l.cucaracha)) + const Offset(0, -6), tr('¡CHAO!', 'BYE!'), Colors.white, f);
    }
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
  (Widget, Widget?) _dedo(int i, double a, double s) {
    final b = widget.bano;
    final impar = i.isOdd;
    final (archivo, giro, espejo) = switch (b.formaDedo) {
      FormaDedo.mano => ('raised_hand', a - pi / 2, false),
      FormaDedo.pie when impar => ('foot', a + pi, false),
      FormaDedo.ambidiestro || FormaDedo.pie => ('backhand_index_pointing_up', a - pi / 2, impar),
      FormaDedo.normal => ('backhand_index_pointing_up', a - pi / 2, false),
    };
    final esPie = archivo == 'foot';
    Widget img = Image.asset('assets/emoji/$archivo.png', width: 26 * s, height: 26 * s, filterQuality: FilterQuality.medium);
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
          : Transform.rotate(angle: giro, child: Center(child: Transform.translate(offset: donde * s, child: Emoji(adorno, tamano: tam * s)))),
    );
  }

  // La cucaracha en t: centro (x absoluta), hacia dónde mira y si va huyendo. null = no está cruzando, o ya se fue.
  ({Offset o, double giro, bool huye})? _cucaracha(double cx, double t) {
    if (widget.bano.ceramica) return null;
    final fase = t % 40;
    if (fase < 6 || fase >= 11) return null;
    final y = _lugar.cucaracha + 9;
    double xEn(double fase) {
      final f = (fase - 6) / 5;
      final u = f < .4 ? f / .4 * .45 : (f < .55 ? .45 : .45 + (f - .55) / .45 * .55);
      return -20 + (2 * cx + 40) * u;
    }

    final r = _reacciones['cucaracha'];
    if (r != null && r <= t && t - r < fase - 6) {
      // La tocaron en esta pasada: corre al borde más cerca, mucho más rápido, y no vuelve hasta la próxima.
      final x0 = xEn(r % 40);
      final dir = x0 < cx ? -1.0 : 1.0;
      final x = x0 + dir * 520 * (t - r);
      if (x < -20 || x > 2 * cx + 20) return null;
      return (o: Offset(x, y + 1.5 * sin(t * 60)), giro: dir * pi / 2, huye: true);
    }
    final f = (fase - 6) / 5;
    return (o: Offset(xEn(fase), y + (f < .4 || f >= .55 ? sin(t * 30) : 0)), giro: pi / 2, huye: false);
  }

  // Lo que se mueve del baño: tobo y matica (se tambalean si los tocan), gota, humo, destellos, cucaracha, arepa.
  void _ambienteVivo(List<Widget> hijos, double cx, double t, bool vivo) {
    final b = widget.bano;
    final l = _lugar;
    double bamboleo(String id) {
      final f = vivo ? _reaccion(id, t, .9) : null;
      return f == null ? 0 : .45 * sin(f * pi * 5) * (1 - f);
    }

    if (b.tanque == 0) {
      Widget w = Emoji('🪣', tamano: l.tamTobo);
      if (b.lujo('est_tobo')) w = FondoBano.dorado(w);
      hijos.add(_abs(cx, l.tobo, l.tamTobo, Transform.rotate(angle: bamboleo('tobo'), alignment: Alignment.bottomCenter, child: w)));
    }
    if (b.matica) {
      hijos.add(_abs(cx, l.matica, 40, Transform.rotate(angle: .6 * bamboleo('matica'), alignment: Alignment.bottomCenter, child: const Emoji('🪴', tamano: 40))));
    }
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
    // Cucaracha que cruza el piso (mientras no haya cerámica nueva). Se para a la mitad, como hacen. Tocada, sale
    // corriendo al borde más cerca.
    if (vivo) {
      if (_cucaracha(cx, t) case final c?) {
        hijos.add(_abs(cx, c.o - Offset(cx, 0), 18, Transform.rotate(angle: c.giro, child: const Emoji('🪳', tamano: 18))));
        if (c.huye) hijos.add(_abs(cx, c.o - Offset(cx + (c.giro > 0 ? 18 : -18), 0), 16, const Emoji('💨', tamano: 16)));
      }
    }
    if (!_lugar.budareDelante) _arepas(hijos, cx, t, vivo);
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
  // La arepa que salta en el budare (y las de al lado). Si el budare va delante del camión, también se pinta aquí.
  void _arepas(List<Widget> hijos, double cx, double t, bool vivo) {
    final b = widget.bano;
    if (b.arepa == 0) return;
    final l = _lugar;
    if (l.budareDelante) {
      hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Budare(Offset(cx + l.budare.dx, l.budare.dy), b.arepa >= 3)))));
    }
    final base = l.budare + const Offset(0, -9);
    final fase = t % 9;
    var salto = vivo && fase < .6 ? fase / .6 : 0.0;
    var alto = 28.0, vueltas = 1.0;
    // Tocada: vuela alto y da tres vueltas.
    if (vivo) {
      if (_reaccion('arepa', t, 1.1) case final v?) (salto, alto, vueltas) = (v, 92.0, 3.0);
    }
    if (b.arepa >= 2) hijos.add(_abs(cx, base + const Offset(-5, 3), 22, const Emoji('🫓', tamano: 22)));
    if (b.arepa >= 3) hijos.add(_abs(cx, base + const Offset(14, 3), 22, const Emoji('🫓', tamano: 22)));
    hijos.add(_abs(
        cx,
        base + Offset(b.arepa >= 2 ? 3 : 0, (b.arepa >= 2 ? -4 : 0) - alto * sin(pi * salto)),
        24,
        Transform.rotate(angle: 2 * pi * vueltas * salto, child: const Emoji('🫓', tamano: 24))));
    if (b.arepaBrillo) {
      final esc = vivo ? .5 + .5 * sin(t * 2.3).abs() : .8;
      hijos.add(_abs(cx, base + const Offset(22, -12), 12, Transform.scale(scale: esc, child: const Emoji('✨', tamano: 12))));
    }
  }

  void _camion(BuildContext context, List<Widget> hijos, List<Widget> trasTaza, List<Widget> encima, double cx, double t, bool vivo) {
    final c = widget.bano.camion;
    if (!vivo) return;
    final q = _posCamion(cx, t);
    if (q == null) return;
    final e = q.e, suelo = q.suelo, x = q.cola - cx;
    final s = c >= 4 ? 1.2 : 1.0;
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
    // Tocado: corneta (y el brinquito va en _posCamion).
    if (_reaccion('camion', t, .9) case final v?) grito(cabina - 24, arriba - 40 - 22 * v, tr('PIIIIII', 'HOOOONK'), acento, 18, -.1);
  }

  // Dónde va el camión en t: la cola (x absoluta), el suelo bajo las ruedas y el segundo de su visita; null si no está.
  ({double cola, double suelo, double e})? _posCamion(double cx, double t) {
    final c = widget.bano.camion;
    if (c == 0 || t < 10) return null;
    final e = (t - 10) % 40;
    if (e >= 9.5) return null;
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
    final piso = _lugar.camion;
    var suelo = c >= 9 ? piso - 46 + 3 * sin(t * 3) : piso;
    if (_reaccion('camion', t, .45) case final v?) suelo -= 9 * sin(pi * v);
    return (cola: cx + x, suelo: suelo, e: e);
  }

  // Lo que ocupa el camión (cabina y cisterna) en t, para tocarlo.
  Rect? _cajaCamion(double cx, double t) {
    final q = _posCamion(cx, t);
    if (q == null) return null;
    final c = widget.bano.camion;
    final s = c >= 4 ? 1.2 : 1.0;
    final largo = (c >= 7 ? 110 : 76) * s;
    return Rect.fromLTRB(q.cola - largo - 34 * s, q.suelo - 50 * s, q.cola, q.suelo + 4);
  }

  // Criadero de moscas: vuelan en una franja encima del tanque con senos sumados (parece al azar y no da vueltas en
  // redondo); no tapan la taza.
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
      final x = 20 + 62 * (.6 * sin(u * .9 + f) + .4 * sin(u * 2.3 + f * 2.1));
      final y = 18 * (.6 * cos(u * .7 + f * 1.3) + .4 * sin(u * 1.9 + f * .7));
      final vx = .54 * cos(u * .9 + f) + .92 * cos(u * 2.3 + f * 2.1);
      final zum = vivo ? Offset(1.2 * sin(tv * 47 + i), 1.2 * cos(tv * 53 + i * 2)) : Offset.zero;
      final o = Offset(cx + x, 52 + y) + zum;
      final tam = esReina ? 18.0 : 13.0;
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

  // "+N" sueltos de la producción pasiva: ~4 por segundo, más con apuro (tope 6, para que no se amontonen); pasado el
  // tope crecen un poco y se doran. Suben tenues por encima del tanque, no sobre la taza.
  void _sueltos(BuildContext context, List<Widget> encima, double cx, double t) {
    final apuro = widget.apuro.isFinite ? widget.apuro : 1.0;
    final r = (4 * apuro).clamp(2.0, 6.0);
    final extra = (4 * apuro / 14 - 1).clamp(0.0, 1.0);
    final texto = '+${formatoMj(widget.mps / r, ingles: enIngles)}';
    for (var k = ((t - .9) * r).floor() + 1; k <= (t * r).floor(); k++) {
      final f = (t - k / r) / .9;
      if (f < 0 || f > 1) continue;
      encima.add(_suelto(context, cx + 220 * (_h(k * 1.0) - .5), 58 + 14 * _h(k + .37) - 40 * f, texto, .5 * (1 - f),
          11 + 2 * extra, extra > 0 ? acento : Colors.white));
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

  // Cada 30 s (la primera a los 8 s) aparece la taza encima de la poceta y le echa un chorro de café.
  // El chorrito de la poceta japonesa (cada 7 s, dura 1,6 s) y la fuentecita del bidet (cada 11 s, 0,9 s; bajita sin la presión).
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
    if (b.bidet >= 1) {
      final e = (t - 5) % 11;
      if (t >= 5 && e < .9) {
        final l = _lugar;
        final d = Bano.chorroBidet(l) + Offset(cx, 0);
        final alto = (b.bidet >= 2 ? 30 : 16) * l.escalaBidet;
        hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Agua(d, d + const Offset(8, 0), Bano.altoChorro(l, b, alto), e / .9)))));
      }
    }
  }

  // El cuadro de la clase media: tocado se bambolea colgado del clavo y queda torcido o derecho, uno y uno.
  void _cuadro(List<Widget> hijos, double cx, double t, bool vivo) {
    if (widget.bano.claseMedia < 4) return;
    final f = vivo ? _reaccion('cuadro', t) : null;
    final giro = ((_veces['cuadro'] ?? 0).isOdd ? .14 : 0.0) + (f == null ? 0 : .45 * sin(f * pi * 4) * (1 - f));
    hijos.add(_abs(cx, Bano.cuadro, 34, Transform.rotate(angle: giro, alignment: Alignment.topCenter, child: const Emoji('🖼️', tamano: 34))));
  }

  // Lo que se mueve solo de los edificios: la llamita del calentador, la ducha que se abre cada tanto, el patico y las
  // burbujas de la bañera, y el ambiente del edificio más alto (piedras de la mina, destellos del templo, chispas del
  // volcán, el remolino del laxante y lo que se traga el agujero negro).
  void _edificiosVivos(List<Widget> hijos, double cx, double t) {
    final b = widget.bano;
    final c = b.claseMedia;
    if (c >= 5) {
      final esc = .75 + .25 * sin(t * 11) * cos(t * 7);
      hijos.add(_abs(cx, Bano.piloto, 10, Transform.scale(scale: esc, alignment: Alignment.bottomCenter, child: const Emoji('🔥', tamano: 10))));
    }
    if (c >= 6) {
      // Cada 25 s se abre 4 s; tocada, un chorrazo.
      final e = (t - 12) % 25;
      final fuerte = _reaccion('ducha', t) != null;
      if (fuerte || (t >= 12 && e < 4)) {
        final abre = fuerte ? 1.0 : min(1.0, min(e, 4 - e) / .4);
        hijos.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Lluvia(Offset(cx + Bano.ducha.dx, Bano.ducha.dy), t, abre, fuerte)))));
      }
    }
    if (c >= 8) {
      final m = Bano.banera;
      if (_reaccion('banera', t) == null) {
        hijos.add(_abs(cx, Offset(m.center.dx - 10, m.top - 8 + 1.5 * sin(t * 2.2)), 22,
            Transform.rotate(angle: .08 * sin(t * 1.6), child: const Emoji('🦆', tamano: 22))));
      }
      for (var k = 0; k < 3; k++) {
        final f = (t * .35 + k / 3) % 1;
        hijos.add(_abs(cx, Offset(m.left + 12 + 10.0 * k + 3 * sin(f * 7 + k), m.top - 4 - 34 * f), 12,
            Opacity(opacity: (1 - f) * .8, child: const Emoji('🫧', tamano: 12))));
      }
    }
    // Lo de adentro de la ventana, recortado a ella (x, y desde la esquina de arriba del vidrio).
    Widget ventana(List<Widget> dentro) => Positioned.fromRect(
        rect: Bano.ventana.shift(Offset(cx, 0)).deflate(3), child: IgnorePointer(child: ClipRect(child: Stack(clipBehavior: Clip.none, children: dentro))));
    switch (b.ambiente) {
      case AmbienteBano.mina:
        // Se desprenden piedritas del techo por los lados y rebotan en el piso.
        for (var k = 0; k < 2; k++) {
          final u = t / 9 + k * .5, e = (u % 1) * 9;
          if (e > 1.4) continue;
          final x = (k == 0 ? -120.0 : 64.0) + 34 * _h(u.floorToDouble() + k);
          final y = e < 1 ? 6 + (Bano.piso + 2) * e * e : Bano.piso + 8 - 16 * sin(pi * (e - 1) / .4);
          hijos.add(_abs(cx, Offset(x, y), 14,
              Opacity(opacity: e < 1.2 ? 1 : (1.4 - e) / .2, child: Transform.rotate(angle: e * 6, child: const Emoji('🪨', tamano: 14)))));
        }
        hijos.add(_abs(cx, Bano.letrero + const Offset(18, 14), 12, Transform.scale(scale: .5 + .5 * sin(t * 1.9).abs(), child: const Emoji('💎', tamano: 12))));
      case AmbienteBano.templo:
        // Destellos dorados que suben despacio a los lados del trono.
        for (var k = 0; k < 4; k++) {
          final f = (t * .18 + k / 4) % 1;
          final x = (k.isEven ? -1 : 1) * (72 + 12 * sin(f * 5 + k));
          hijos.add(_abs(cx, Offset(x, Bano.piso + 6 - 150 * f), 14, Opacity(opacity: sin(pi * f) * .9, child: const Emoji('✨', tamano: 14))));
        }
      case AmbienteBano.volcan:
        // Chispas que suben del piso y humo que echa el volcán de la ventana.
        for (var k = 0; k < 4; k++) {
          final f = (t * .5 + k / 4) % 1;
          final x = -160 + 320 * _h(k + 3.0) + 10 * sin(f * 8 + k);
          hijos.add(_abs(cx, Offset(x, Bano.piso + 20 - 120 * f), 10, Opacity(opacity: (1 - f) * .9, child: const Emoji('🔥', tamano: 10))));
        }
        hijos.add(ventana([
          for (var k = 0; k < 2; k++)
            if ((t * .4 + k * .5) % 1 case final f)
              Positioned(left: 30 + 6 * sin(f * 5 + k), top: 16 - 26 * f, width: 16, height: 16, child: Opacity(opacity: 1 - f, child: const Emoji('💨', tamano: 16))),
        ]));
      case AmbienteBano.laxante:
        hijos.add(ventana([Positioned.fill(child: Center(child: Transform.rotate(angle: t * 2, child: const Opacity(opacity: .85, child: Emoji('🌀', tamano: 34)))))]));
      case AmbienteBano.agujero:
        // Cada 5 s algo del baño se va en espiral al agujero negro.
        final e = t % 5;
        if (e < 3) {
          final f = e / 3, a = f * 4 * pi;
          final cosa = const ['💩', '🧻', '🪠'][(t / 5).floor() % 3];
          final o = Bano.ventana.center + Offset(cos(a), .6 * sin(a)) * 50 * (1 - f);
          hijos.add(_abs(cx, o, 18, Opacity(opacity: 1 - f * f, child: Transform.rotate(angle: a, child: Transform.scale(scale: 1 - .8 * f, child: Emoji(cosa, tamano: 18))))));
        }
      default:
        break;
    }
  }

  void _cafe(List<Widget> hijos, double cx, double t) {
    final b = widget.bano;
    if (b.cafe == 0 || t < 8) return;
    final e = (t - 8) % 30;
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

/// La ducha abierta: rayitas de agua que caen de la regadera. [abre] de 0 a 1 (se abre y se cierra); [fuerte] es el
/// chorrazo de cuando la tocan.
class _Lluvia extends CustomPainter {
  _Lluvia(this.regadera, this.t, this.abre, this.fuerte);

  final Offset regadera;
  final double t, abre;
  final bool fuerte;

  @override
  void paint(Canvas canvas, Size size) {
    final largo = fuerte ? 150.0 : 110.0, n = fuerte ? 14 : 9;
    final pincel = Paint()
      ..strokeWidth = fuerte ? 2 : 1.5
      ..color = const Color(0xFF8FD3F5).withValues(alpha: .75 * abre);
    for (var i = 0; i < n; i++) {
      final x = regadera.dx - 16 + 32 * i / (n - 1);
      final y = regadera.dy + 6 + (t * (fuerte ? 260 : 180) + i * 37) % largo;
      canvas.drawLine(Offset(x, y), Offset(x, y + 8), pincel);
    }
  }

  @override
  bool shouldRepaint(_Lluvia v) => true;
}

/// Agua del bidet: el chorrito de la poceta japonesa o la fuentecita del bidet (un arco que sube y cae), o el
/// rociado de gotas del chorro que te da en la cara. [f] va de 0 a 1 en lo que dura.
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

// Palanca del tanque: una placa cromada atornillada a la cara del tanque y la manija que sale hacia el frente, bajo la
// tapa. Gris si la cadena no está lista; amarilla y con halo que late cuando sí (t != null = animada). Al jalar, la
// manija gira hacia abajo sobre su eje (en reposo ya cae un poquito, como una de verdad).
class _Palanca extends CustomPainter {
  final bool lista;
  final double baja;
  final double? t;
  _Palanca(this.lista, this.baja, this.t);

  static const _pivote = _PocetaState._pivote;
  static const _largo = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final a = .15 + .5 * baja;
    final punta = _pivote + Offset(-cos(a), sin(a)) * _largo;
    final color = lista ? acento : const Color(0xFFB4BAC0);
    const negro = Color(0xFF1A1A1A);
    final borde = Paint()
      ..color = negro
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (lista) {
      final latido = t == null ? 1.0 : .5 + .5 * sin(t! * 5);
      canvas.drawCircle(punta, 7 + 2.5 * latido, Paint()..color = acento.withValues(alpha: .25 + .25 * latido));
    }
    // La placa: cuadrada, en la cara del tanque.
    final placa = Rect.fromCenter(center: _pivote, width: 11, height: 11);
    canvas.drawRect(placa, Paint()..color = const Color(0xFFD9DEE3));
    canvas.drawRect(placa, borde);
    // La manija: brazo grueso y el agarre más ancho en la punta.
    canvas.drawLine(_pivote, punta, Paint()
      ..color = negro
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.square);
    canvas.drawLine(_pivote, punta, Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square);
    canvas.save();
    canvas.translate(punta.dx, punta.dy);
    canvas.rotate(-a);
    final agarre = Rect.fromCenter(center: Offset.zero, width: 7, height: 8);
    canvas.drawRect(agarre, Paint()..color = color);
    canvas.drawRect(agarre, borde);
    canvas.restore();
    // El eje.
    canvas.drawRect(Rect.fromCenter(center: _pivote, width: 4, height: 4), Paint()..color = negro);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// El piso de más, hacia uno: sigue la perspectiva y los colores del piso de bano.dart (y, con cloaca, la pared de
// ladrillo del sótano), con el mismo tinte y la misma penumbra. y = 0 es el borde de abajo de la escena.
class _PintorSuelo extends CustomPainter {
  _PintorSuelo(this.estado);

  final EstadoBano estado;

  @override
  bool shouldRepaint(_PintorSuelo old) => old.estado != estado;

  @override
  void paint(Canvas canvas, Size size) {
    final e = estado;
    final w = size.width;
    if (e.cloaca > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1A1714));
      final junta = Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFF2E2620);
      for (var f = 0; f * 10.0 < size.height; f++) {
        final y = f * 10.0;
        canvas.drawLine(Offset(0, y), Offset(w, y), junta);
        for (var x = (f.isEven ? 0.0 : 14.0); x < w; x += 28) {
          canvas.drawLine(Offset(x, y), Offset(x, y + 10), junta);
        }
      }
    } else {
      pintarPisoDeMas(canvas, size, e);
    }
    final tinte = switch (e.ambiente) {
      AmbienteBano.volcan => const Color(0xFFFF5A1F).withValues(alpha: .10),
      AmbienteBano.laxante => const Color(0xFF8A4FFF).withValues(alpha: .10),
      AmbienteBano.agujero => const Color(0xFF3A1A6B).withValues(alpha: .16),
      _ => null,
    };
    if (tinte != null) canvas.drawRect(Offset.zero & size, Paint()..color = tinte);
    if (!e.bombillo && !e.lujo('est_lampara')) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x24000000));
  }
}

// El budare cuando va delante del camión (si no, lo pinta el fondo).
class _Budare extends CustomPainter {
  const _Budare(this.c, this.grande);

  final Offset c;
  final bool grande;

  @override
  void paint(Canvas canvas, Size size) => PintorBano.pintarBudare(canvas, c, grande);

  @override
  bool shouldRepaint(_Budare v) => v.c != c || v.grande != grande;
}
