// Recorrido guiado del Imperio (la primera vez que se abre, para todos, veteranos incluidos) y la hoja "¿Qué hago ahora?".
// El recorrido oscurece la pantalla, deja un hueco cuadrado sobre el elemento de verdad (lo busca por su Key dentro de la
// escena) y muestra una tarjeta con SIGUIENTE / SALTAR. Los pasos se arman con los números de la partida y solo salen los
// que ya están abiertos. La cuenta de la próxima jugada está en que_hago.dart (pura, sin widgets).

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'cadena.dart';
import 'control.dart';
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';
import 'que_hago.dart';

/// Clave en [Partida.guiaVista] cuando el recorrido ya se vio (terminado o saltado). Subir la versión lo muestra otra vez.
const claveRecorrido = 'recorrido_v1';

/// Un paso del recorrido. [objetivo] es la Key del elemento a resaltar (null: la tarjeta sale en el centro, sin hueco).
class PasoRecorrido {
  const PasoRecorrido(this.id, this.emoji, this.titulo, this.texto, {this.objetivo});

  final String id;
  final String emoji;
  final String titulo;
  final String texto;
  final Key? objetivo;
}

String _mj(double v) => formatoMj(v, ingles: enIngles);

/// Los pasos para esta partida, en orden: poceta, saldo, edificios, mejoras, atascos, mojón dorado, tienda, ¿qué hago? y,
/// si la cadena ya está abierta, jalar con los números del jugador (el último, para los veteranos). Mejoras, atascos,
/// tienda y cadena solo salen si ya están abiertos. [jalarVisible]: el botón JALAR se ve; [cadenaLista]: está encendido.
List<PasoRecorrido> pasosRecorrido(Imperio im, int ahora, {String moneda = 'MJ', bool jalarVisible = false, bool cadenaLista = false}) {
  final pasos = <PasoRecorrido>[];
  final pujo = _mj(im.valorPujo(ahora));
  pasos.add(PasoRecorrido('poceta', '💩', tr('Puja en la poceta', 'Push on the toilet'),
      tr('Cada toque te da $pujo $moneda. Todo imperio empezó así: pujando.',
          'Each tap gives you $pujo $moneda. Every empire started like this: pushing.'),
      objetivo: const Key('recorrido_poceta')));

  final mps = im.mps(ahora);
  pasos.add(PasoRecorrido('saldo', '💰', tr('Tus $moneda', 'Your $moneda'),
      mps > 0
          ? tr('Aquí ves lo que tienes. Ahora produces ${_mj(mps)} $moneda/s, aunque no toques nada.',
              "This is what you've got. You make ${_mj(mps)} $moneda/s right now, even without tapping.")
          : tr('Aquí ves lo que tienes. Por ahora todo sale de tus pujos: compra un edificio para que entre solo.',
              "This is what you've got. For now it all comes from your pushes: buy a building so it flows by itself."),
      objetivo: const Key('recorrido_saldo')));

  final edificio = mejorCompra(im, ahora, soloEdificios: true);
  pasos.add(PasoRecorrido('edificios', '🏗️', tr('Edificios', 'Buildings'),
      edificio == null
          ? tr('Aquí compras edificios: producen $moneda solos, hasta con el teléfono guardado.',
              'Buy buildings here: they make $moneda by themselves, even with your phone in your pocket.')
          : tr('Producen $moneda solos, hasta con el teléfono guardado. Tu próximo edificio que más rinde: ${edificio.emoji} ${edificio.nombre} '
                  '(+${_mj(edificio.suma)} $moneda/s por ${_mj(edificio.precio)}).',
              'They make $moneda by themselves, even with your phone in your pocket. Your best next building: ${edificio.emoji} '
                  '${edificio.nombre} (+${_mj(edificio.suma)} $moneda/s for ${_mj(edificio.precio)}).'),
      objetivo: const Key('boton_edificios')));

  if (im.mejorasDisponibles().isNotEmpty || im.partida.mejoras.isNotEmpty) {
    pasos.add(PasoRecorrido('mejoras', '⬆️', tr('Mejoras', 'Upgrades'),
        tr('Dentro de Edificios, cada uno tiene su ▼ con mejoras que lo multiplican. Las de la poceta engordan cada pujo.',
            'Inside Buildings, each one has a ▼ with upgrades that multiply it. The toilet ones make every push fatter.'),
        objetivo: const Key('boton_edificios')));
  }

  if (im.partida.vioPrimerAtasco || im.atascos.isNotEmpty) {
    pasos.add(PasoRecorrido('atascos', '🪠', tr('Atascos', 'Clogs'),
        tr('A veces un edificio se tapa y no produce nada. Destápalo a toques, o alquila el Robot para que lo haga él.',
            'Sometimes a building clogs and makes nothing. Unclog it by tapping, or rent the Plunger bot to do it for you.'),
        objetivo: im.atascos.isNotEmpty ? const Key('tarjeta_atasco') : const Key('boton_edificios')));
  }

  pasos.add(PasoRecorrido('dorado', '🟡', tr('Mojón dorado', 'Golden poop'),
      tr('De vez en cuando pasa flotando un mojón dorado. Tócalo antes de que se vaya: trae premio.',
          "Every now and then a golden poop floats by. Tap it before it leaves: it brings a prize."),
      objetivo: im.dorado(ahora) != null ? const Key('mojon_dorado') : null));

  if (objetos.any((o) => o.tipo == TipoObjeto.alquilable && im.objetoAbierto(o.id))) {
    pasos.add(PasoRecorrido('objetos', '🛒', tr('Tienda', 'Shop'),
        tr('Aquí alquilas ayudantes y usas tus fichas. Cada uno tiene su ? que te explica qué hace, con tus números.',
            'Rent helpers and use your tokens here. Each one has a ? that explains what it does, with your numbers.'),
        objetivo: const Key('boton_tienda')));
  }

  pasos.add(PasoRecorrido('que_hago', '❓', tr('¿Qué hago ahora?', 'What do I do now?'),
      tr('¿Perdido? Este botón te dice la mejor jugada del momento. Y desde ahí repites este recorrido.',
          'Lost? This button tells you the best move right now. You can also replay this tour from there.'),
      objetivo: const Key('boton_que_hago')));

  if (im.cadenaDesbloqueada) pasos.add(_pasoCadena(im, moneda, jalarVisible: jalarVisible, cadenaLista: cadenaLista));
  return pasos;
}

PasoRecorrido _pasoCadena(Imperio im, String moneda, {required bool jalarVisible, required bool cadenaLista}) {
  final pct = im.ajustes.rolloPct;
  final r = im.partida.rollos;
  final j = cuentaJalar(im);
  final tienes = r == 0
      ? tr('Todavía no tienes Rollos de Oro.', "You don't have Golden Rolls yet.")
      : tr('Tienes ${_mj(r.toDouble())} Rollos de Oro: todo produce ${porcentajeRollos(r, pct)}.',
          'You have ${_mj(r.toDouble())} Golden Rolls: everything makes ${porcentajeRollos(r, pct)}.');
  final String plan;
  if (j.nuevos < 1) {
    plan = tr('Te faltan ${_mj(im.mjParaSiguienteRollo)} $moneda para el próximo rollo. Sigue juntando.',
        "You're ${_mj(im.mjParaSiguienteRollo)} $moneda away from the next roll. Keep going.");
  } else {
    final ahoraSi = j.salto >= saltoRollosConviene || j.abre != null;
    final gana = tr('Si jalas ahora ganas ${_mj(j.nuevos.toDouble())} y quedas en ${porcentajeRollos(r + j.nuevos, pct)}.',
        'Flush now and you get ${_mj(j.nuevos.toDouble())}, ending at ${porcentajeRollos(r + j.nuevos, pct)}.');
    final consejo = ahoraSi
        ? (j.abre != null
            ? tr(' Conviene: se abre ${j.abre!.nombreEs}.', ' Worth it: it unlocks ${j.abre!.nombreEn}.')
            : tr(' Conviene: produces x${_mj(j.salto)}.', ' Worth it: you make x${_mj(j.salto)}.'))
        : tr(' Todavía no: espera a que suba x${_mj(saltoRollosConviene)} o más.',
            ' Not yet: wait until it goes up x${_mj(saltoRollosConviene)} or more.');
    final cagadas = cadenaLista ? '' : tr(' Ojo: la cadena también pide cagadas reales.', ' Heads up: the chain also needs real poops.');
    plan = '$gana$consejo$cagadas';
  }
  final que = tr('Jalar borra tus $moneda y edificios, pero te da Rollos de Oro para siempre.',
      'Flushing wipes your $moneda and buildings, but gives you Golden Rolls forever.');
  return PasoRecorrido('cadena', '🧻', tr('Jalar la cadena', 'Flush the chain'), '$que $tienes $plan',
      objetivo: jalarVisible ? const Key('boton_jalar') : null);
}

/// Busca dentro de [raiz] el elemento cuya Key es [llave] y devuelve su caja en coordenadas de [raiz] (null si no está).
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

/// La capa del recorrido: va como `Positioned.fill` al final de la escena. [escena] es la Key del Stack de la escena, donde
/// se buscan los objetivos. Anota `imperio_recorrido` y, al saltar o terminar, marca [claveRecorrido].
class RecorridoImperio extends StatefulWidget {
  const RecorridoImperio({super.key, required this.control, required this.pasos, required this.escena, required this.alTerminar});

  final ControlImperio control;
  final List<PasoRecorrido> pasos;
  final GlobalKey escena;
  final VoidCallback alTerminar;

  @override
  State<RecorridoImperio> createState() => _RecorridoImperioState();
}

class _RecorridoImperioState extends State<RecorridoImperio> {
  var _i = 0;
  Rect? _hueco;
  var _medido = false;

  PasoRecorrido get _paso => widget.pasos[_i];

  @override
  void initState() {
    super.initState();
    _anotar('ver');
  }

  void _anotar(String accion) => widget.control.anotar('imperio_recorrido', {'paso': _paso.id, 'accion': accion});

  void _medir() {
    if (!mounted) return;
    final raiz = widget.escena.currentContext;
    final llave = _paso.objetivo;
    final nuevo = raiz == null || llave == null ? null : cajaDe(raiz, llave);
    final viejo = _hueco;
    final cambio = (nuevo == null) != (viejo == null) ||
        (nuevo != null &&
            viejo != null &&
            [nuevo.left - viejo.left, nuevo.top - viejo.top, nuevo.width - viejo.width, nuevo.height - viejo.height].any((d) => d.abs() > 0.5));
    if (cambio || !_medido) {
      setState(() {
        _hueco = nuevo;
        _medido = true;
      });
    }
  }

  void _terminar(String accion) {
    _anotar(accion);
    widget.control.marcarGuia(claveRecorrido);
    widget.alTerminar();
  }

  void _siguiente() {
    if (_i >= widget.pasos.length - 1) return _terminar('fin');
    _anotar('siguiente');
    setState(() {
      _i++;
      _medido = false;
    });
    _anotar('ver');
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
    final quieto = movimiento(context) == Movimiento.nada;
    final hueco = _medido ? _hueco?.inflate(4) : null;
    return LayoutBuilder(builder: (context, caja) {
      final alto = caja.maxHeight;
      const necesita = 190.0;
      final tarjeta = _tarjeta(context);
      final Widget puesta;
      if (!_medido) {
        puesta = const SizedBox.shrink();
      } else if (hueco == null) {
        puesta = Positioned(left: 16, right: 16, top: 0, bottom: 0, child: Center(child: tarjeta));
      } else if (alto - hueco.bottom >= necesita) {
        puesta = Positioned(left: 16, right: 16, top: hueco.bottom + 10, child: tarjeta);
      } else if (hueco.top >= necesita) {
        puesta = Positioned(left: 16, right: 16, bottom: alto - hueco.top + 10, child: tarjeta);
      } else {
        puesta = Positioned(left: 16, right: 16, bottom: alto - hueco.bottom + 12, child: tarjeta);
      }
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: AnimatedOpacity(
                opacity: _medido ? 1 : 0,
                duration: quieto ? Duration.zero : const Duration(milliseconds: 180),
                child: CustomPaint(painter: _Sombra(hueco, acento)),
              ),
            ),
          ),
          puesta,
        ],
      );
    });
  }

  Widget _tarjeta(BuildContext context) {
    final p = paleta(context);
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final ultimo = _i == widget.pasos.length - 1;
    final quieto = movimiento(context) == Movimiento.nada;
    final contenido = Container(
      key: const Key('recorrido_tarjeta'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.fondo, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Emoji(_paso.emoji, tamano: 22),
              const SizedBox(width: 8),
              Expanded(
                child: TextoConEmojis(_paso.titulo.toUpperCase(),
                    style: numeros(context, tamano: 12, weight: FontWeight.w900, color: oscuro ? acento : p.texto)),
              ),
              Text('${_i + 1}/${widget.pasos.length}', style: numeros(context, tamano: 11, weight: FontWeight.w700, color: p.textoSuave)),
            ],
          ),
          const SizedBox(height: 6),
          TextoConEmojis(_paso.texto, style: TextStyle(fontWeight: FontWeight.w600, color: p.texto, height: 1.3)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('recorrido_saltar'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: p.texto, side: BorderSide(color: p.borde)),
                  onPressed: () => _terminar('saltar'),
                  child: Text(tr('SALTAR', 'SKIP'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  key: const Key('recorrido_siguiente'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: acento, foregroundColor: acentoTexto),
                  onPressed: _siguiente,
                  child: Text(ultimo ? tr('LISTO', 'DONE') : tr('SIGUIENTE', 'NEXT'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (quieto) return contenido;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_paso.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      builder: (context, v, hijo) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: hijo)),
      child: contenido,
    );
  }
}

/// Oscurece todo menos [hueco] y le pone un borde de 2px del acento con esquinas de [radio].
class _Sombra extends CustomPainter {
  _Sombra(this.hueco, this.color);

  final Rect? hueco;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Path()..addRect(Offset.zero & size);
    final h = hueco;
    if (h != null) todo.addRRect(RRect.fromRectAndRadius(h, const Radius.circular(radio)));
    todo.fillType = PathFillType.evenOdd;
    canvas.drawPath(todo, Paint()..color = const Color(0xB3000000));
    if (h != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(h, const Radius.circular(radio)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color);
    }
  }

  @override
  bool shouldRepaint(_Sombra viejo) => viejo.hueco != hueco || viejo.color != color;
}

/// El botón ? chico y permanente que abre "¿Qué hago ahora?".
class BotonQueHago extends StatelessWidget {
  const BotonQueHago({super.key, required this.alTocar});

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return SizedBox(
      width: 34,
      height: 34,
      child: OutlinedButton(
        key: const Key('boton_que_hago'),
        onPressed: alTocar,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          foregroundColor: p.texto,
          side: BorderSide(color: acento),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
        ),
        child: Text('?', style: numeros(context, tamano: 15, weight: FontWeight.w900, color: p.texto)),
      ),
    );
  }
}

String _textoIr(DestinoQueHago ir) => switch (ir) {
      DestinoQueHago.edificios => tr('IR A EDIFICIOS', 'GO TO BUILDINGS'),
      DestinoQueHago.tienda => tr('IR A LA TIENDA', 'GO TO THE SHOP'),
      DestinoQueHago.jalar => tr('JALAR', 'FLUSH'),
      DestinoQueHago.cerrar => tr('VAMOS', "LET'S GO"),
    };

/// Hoja "¿Qué hago ahora?": la próxima jugada en vivo, con IR (cierra la hoja y llama a [alIr]) y VER EL RECORRIDO
/// (cierra la hoja y llama a [alRecorrido]). [cadenaLista]: el botón JALAR está encendido. Anota `imperio_que_hago`.
Future<void> abrirQueHago(BuildContext context, ControlImperio control,
    {required bool Function() cadenaLista, required void Function(Sugerencia) alIr, required VoidCallback alRecorrido}) {
  final moneda = monedaActual().abreviatura;
  Sugerencia calcular() => queHagoAhora(control.imperio, control.ahora, cadenaLista: cadenaLista(), moneda: moneda);
  control.anotar('imperio_que_hago', {'sugerencia': calcular().id, 'accion': 'abrir'});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (hoja) => ListenableBuilder(
      listenable: control,
      builder: (hoja, _) {
        final p = paleta(hoja);
        final oscuro = Theme.of(hoja).brightness == Brightness.dark;
        final s = calcular();
        return SafeArea(
          child: Padding(
            key: const Key('hoja_que_hago'),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('¿QUÉ HAGO AHORA?', 'WHAT DO I DO NOW?'),
                    style: numeros(hoja, tamano: 12, weight: FontWeight.w900, color: oscuro ? acento : p.textoSuave)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Emoji(s.emoji, tamano: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextoConEmojis(s.titulo, key: const Key('que_hago_titulo'),
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: p.texto)),
                            const SizedBox(height: 4),
                            TextoConEmojis(s.texto, style: TextStyle(fontWeight: FontWeight.w600, color: p.texto, height: 1.3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('que_hago_ir'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: acento, foregroundColor: acentoTexto),
                  onPressed: () {
                    control.anotar('imperio_que_hago', {'sugerencia': s.id, 'accion': 'ir'});
                    Navigator.of(hoja).pop();
                    alIr(s);
                  },
                  child: Text(_textoIr(s.ir), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  key: const Key('que_hago_recorrido'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: p.texto, side: BorderSide(color: p.borde)),
                  onPressed: () {
                    Navigator.of(hoja).pop();
                    alRecorrido();
                  },
                  child: Text(tr('VER EL RECORRIDO', 'REPLAY THE TOUR'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
