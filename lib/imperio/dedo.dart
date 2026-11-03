// Dedos de la primera vez: un resaltado, un 👆 y una línea corta sobre la próxima cosa que hay que tocar. Salen solos,
// según cómo vas, uno a la vez y una vez cada uno (clave `dedo_<paso>` en Partida.guiaVista). Un toque en cualquier
// parte lo quita y el toque sigue de largo. Reemplaza al recorrido guiado de la 2.15.0.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'motor.dart';

/// Clave en [Partida.guiaVista] cuando el dedo [paso] ya salió.
String claveDedo(String paso) => 'dedo_$paso';

/// Un dedo: [paso] va a la telemetría (`imperio_dedo`) y a la clave; [objetivo] es la llave del widget que señala.
class Dedo {
  const Dedo(this.paso, this.objetivo, this.es, this.en);

  final String paso;
  final Key objetivo;
  final String es;
  final String en;

  String get texto => tr(es, en);

  @override
  bool operator ==(Object other) => other is Dedo && other.paso == paso && other.objetivo == objetivo;

  @override
  int get hashCode => Object.hash(paso, objetivo);
}

/// El primer edificio que se puede comprar ya (con [n] por toque), en el orden del cajón.
Edificio? primerEdificioComprable(Imperio im, int ahora, {int n = 1}) {
  for (final e in edificios) {
    if (!im.edificioVisible(e.id) || !im.edificioAbierto(e.id) || im.atascado(e.id)) continue;
    if (im.precioEdificioVarios(e.id, n, ahora) <= im.saldo) return e;
  }
  return null;
}

/// La primera mejora que alcanza, en el orden del cajón: las del baño y luego las de cada edificio.
Mejora? primeraMejoraComprable(Imperio im) {
  bool alcanza(Mejora m) => im.precioMejora(m) <= im.saldo;
  for (final m in im.mejorasPoceta()) {
    if (alcanza(m)) return m;
  }
  for (final e in edificios) {
    if (!im.edificioVisible(e.id) || !im.edificioAbierto(e.id) || im.atascado(e.id) || im.edificioMisterioso(e.id)) continue;
    for (final m in im.mejorasDeEdificio(e.id)) {
      if (alcanza(m)) return m;
    }
  }
  return null;
}

/// El dedo que toca ahora, o null. Solo pasos no vistos y que todavía no pasaste: con una jalada o una mudanza encima ya
/// no sale ninguno de la corrida (poceta, cagadores, mejora, cadena).
/// [cajonAbierto]: el cajón de edificios está abierto del todo. [abiertos]: desplegables de mejoras abiertos ('poceta' o
/// el id del edificio). [jalarVisible]: el botón JALAR se ve. [mudanza]: el botón MUDANZA se ve y todavía brilla.
/// [cantidad]: cuántos compra cada toque en el cajón.
Dedo? siguienteDedo(Imperio im, int ahora,
    {required bool cajonAbierto,
    Set<String> abiertos = const {},
    bool jalarVisible = false,
    bool mudanza = false,
    int cantidad = 1}) {
  final pa = im.partida;
  bool libre(String paso) => !pa.guiaVista.contains(claveDedo(paso));
  final empezando = pa.jaladas == 0 && pa.mudanzas == 0;
  final sinCagadores = pa.edificios.values.every((n) => n <= 0);

  if (empezando && sinCagadores && pa.mejoras.isEmpty && !cajonAbierto && libre('poceta') &&
      im.mjTotal < edificios.first.precioBase * im.ajustes.escalaEdificios) {
    return const Dedo('poceta', Key('dedo_poceta'), 'Toca para pujar', 'Tap to push');
  }
  if (empezando && sinCagadores) {
    final e = primerEdificioComprable(im, ahora, n: cantidad);
    if (e != null && !cajonAbierto && libre('cagadores')) {
      return const Dedo('cagadores', Key('boton_edificios'), 'Ya te alcanza: compra un cagador', 'You can afford it: buy a pooper');
    }
    if (e != null && cajonAbierto && libre('cagadores_fila')) {
      return Dedo('cagadores_fila', Key('fila_${e.id}'), 'Toca para comprarlo', 'Tap to buy it');
    }
  }
  if (empezando && pa.mejoras.isEmpty) {
    final m = primeraMejoraComprable(im);
    if (m != null) {
      final clave = m.edificio ?? 'poceta';
      const es = 'Una mejora multiplica lo que produces', en = 'An upgrade multiplies what you make';
      if (!cajonAbierto && libre('mejora')) return const Dedo('mejora', Key('boton_edificios'), es, en);
      if (cajonAbierto && !abiertos.contains(clave) && libre('mejora_flecha')) {
        return Dedo('mejora_flecha', Key('flecha_$clave'), es, en);
      }
      if (cajonAbierto && abiertos.contains(clave) && libre('mejora_comprar')) {
        return Dedo('mejora_comprar', Key('comprar_mejora_${m.id}'), 'Toca para comprarla', 'Tap to buy it');
      }
    }
  }
  if (empezando && im.cadenaDesbloqueada && jalarVisible && libre('jalar')) {
    return const Dedo('jalar', Key('boton_jalar'), 'La Cadena: cambia todo por Rollos de Oro', 'The Chain: trade it all for Golden Rolls');
  }
  if (mudanza && pa.mudanzas == 0 && libre('mudanza')) {
    return const Dedo('mudanza', Key('boton_mudanza'), 'Ya no cabes: múdate', "You don't fit anymore: move");
  }
  return null;
}

/// Rectángulo del widget con llave [llave] dentro de [raiz], en las coordenadas de [raiz]. Null si no está o no se midió.
Rect? cajaDe(BuildContext raiz, Key llave) {
  Element? hallado;
  void visitar(Element e) {
    if (hallado != null) return;
    if (e.widget.key == llave) {
      hallado = e;
      return;
    }
    e.visitChildren(visitar);
  }

  (raiz as Element).visitChildren(visitar);
  final caja = hallado?.findRenderObject();
  final base = raiz.findRenderObject();
  if (caja is! RenderBox || base is! RenderBox || !caja.hasSize || !caja.attached) return null;
  final arriba = caja.localToGlobal(Offset.zero, ancestor: base);
  return arriba & caja.size;
}

/// El dedo puesto sobre la escena: oscurece un poco todo menos el objetivo, le pone borde de acento y un 👆 con su línea.
/// No atrapa toques: el primero que llega (en cualquier parte) llama a [alTocar] y sigue de largo.
/// [alVer] sale una vez, la primera vez que encuentra el objetivo; [alPerder] si el objetivo no aparece en unos cuadros.
/// Va en el Stack cuya llave es [escena] (las medidas son de ese Stack).
class DedoImperio extends StatefulWidget {
  const DedoImperio({super.key, required this.dedo, required this.escena, required this.alVer, required this.alTocar, required this.alPerder});

  final Dedo dedo;
  final GlobalKey escena;
  final VoidCallback alVer;
  final VoidCallback alTocar;
  final VoidCallback alPerder;

  @override
  State<DedoImperio> createState() => _DedoImperioState();
}

class _DedoImperioState extends State<DedoImperio> with SingleTickerProviderStateMixin {
  Rect? _hueco;
  var _visto = false;
  var _fallos = 0;
  var _tocado = false;
  // Tres brincos y quieto: una animación que se repite para siempre no deja asentarse a la pantalla.
  late final AnimationController _brinco = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100));

  @override
  void dispose() {
    _brinco.dispose();
    super.dispose();
  }

  void _medir() {
    if (!mounted || _tocado) return;
    final raiz = widget.escena.currentContext;
    final nuevo = raiz == null ? null : cajaDe(raiz, widget.dedo.objetivo);
    if (nuevo == null) {
      // Se fue (o nunca estuvo): unos cuadros de gracia por si se está armando, y luego se quita sin marcarse.
      if (++_fallos >= 3) widget.alPerder();
      return;
    }
    _fallos = 0;
    final viejo = _hueco;
    final cambio = viejo == null ||
        [nuevo.left - viejo.left, nuevo.top - viejo.top, nuevo.width - viejo.width, nuevo.height - viejo.height].any((d) => d.abs() > 0.5);
    if (cambio) setState(() => _hueco = nuevo);
    if (!_visto) {
      _visto = true;
      if (movimiento(context) != Movimiento.nada) _brinco.forward();
      widget.alVer();
    }
  }

  void _tocar() {
    if (_tocado) return;
    _tocado = true;
    widget.alTocar();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
    final mov = movimiento(context);
    if (mov == Movimiento.nada && _brinco.isAnimating) _brinco.stop();
    final hueco = _hueco?.inflate(4);
    return Positioned.fill(
      child: Listener(
        key: const Key('dedo'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _tocar(),
        child: IgnorePointer(
          child: hueco == null
              ? const SizedBox.expand()
              : LayoutBuilder(builder: (context, caja) => _puesto(context, caja.biggest, hueco, mov)),
        ),
      ),
    );
  }

  Widget _puesto(BuildContext context, Size tam, Rect hueco, Movimiento mov) {
    const dedo = 34.0, separa = 6.0, necesita = 100.0;
    // Abajo del objetivo si cabe; si no, arriba con el dedo apuntando hacia abajo. Un objetivo enorme (la poceta) lo lleva
    // por dentro, en el medio.
    final dentro = hueco.height > tam.height * .45;
    final abajo = dentro || tam.height - hueco.bottom >= necesita || hueco.top < necesita;
    final cx = hueco.center.dx.clamp(dedo / 2, tam.width - dedo / 2);
    final topDedo = dentro ? hueco.center.dy - dedo / 2 : (abajo ? hueco.bottom + separa : hueco.top - separa - dedo);
    final alinear = Alignment(tam.width <= 0 ? 0 : (cx / tam.width * 2 - 1).clamp(-1.0, 1.0), 0);
    final linea = _linea(context);
    final Widget dedoW = AnimatedBuilder(
      animation: _brinco,
      builder: (context, hijo) => Transform.translate(
        offset: Offset(0, (abajo ? 1 : -1) * 6 * math.sin(_brinco.value * math.pi * 3).abs()),
        child: hijo,
      ),
      child: Transform.rotate(angle: abajo ? 0 : math.pi, child: const Emoji('👆', tamano: dedo - 4)),
    );
    final contenido = Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _Sombra(hueco, acento))),
        Positioned(left: cx - dedo / 2, top: topDedo, width: dedo, height: dedo, child: Center(child: dedoW)),
        Positioned(
          left: 16,
          right: 16,
          top: abajo ? topDedo + dedo + separa : null,
          bottom: abajo ? null : tam.height - topDedo + separa,
          child: Align(alignment: alinear, child: linea),
        ),
      ],
    );
    if (mov == Movimiento.nada) return contenido;
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.dedo.paso),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      builder: (context, v, hijo) => Opacity(opacity: v, child: hijo),
      child: contenido,
    );
  }

  Widget _linea(BuildContext context) {
    final p = paleta(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        key: const Key('dedo_linea'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: p.fondo, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
        child: TextoConEmojis(widget.dedo.texto,
            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto, height: 1.25)),
      ),
    );
  }
}

/// Oscurece un poco todo menos [hueco] y le pone un borde de 2px del acento con esquinas de [radio].
class _Sombra extends CustomPainter {
  _Sombra(this.hueco, this.color);

  final Rect hueco;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final caja = RRect.fromRectAndRadius(hueco, const Radius.circular(radio));
    final todo = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(caja)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(todo, Paint()..color = const Color(0x73000000));
    canvas.drawRRect(
        caja,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color);
  }

  @override
  bool shouldRepaint(_Sombra viejo) => viejo.hueco != hueco || viejo.color != color;
}
