import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../animaciones.dart';
import '../chat.dart' show aceptoReglas, nombreSala;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show db, textoError;
import '../tema.dart';
import 'control.dart';
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';
import 'nube.dart';

// Jalar la cadena: el prestigio del Imperio. Se pierde la corrida y se ganan Rollos de Oro (+% hasta la mudanza).

/// Qué muestra el botón JALAR.
enum EstadoJalar {
  /// Sin La cadena del trono y sin jaladas: el botón no sale.
  oculto,

  /// El RPC no está o no hay red: todavía no se sabe cuántas cagadas lleva.
  pronto,

  /// Faltan cagadas reales desde la última jalada.
  faltanCagadas,

  /// Faltan MJ históricos para que jalar dé al menos un rollo.
  faltanMj,

  /// Se puede jalar.
  listo,
}

/// El botón JALAR ya decidido: estado, cuántas cagadas faltan, cuántos MJ faltan y cuántos rollos da.
class BotonJalar {
  const BotonJalar(this.estado, {this.cagadas = 0, this.mj = 0, this.rollos = 0});

  final EstadoJalar estado;
  final int cagadas;
  final double mj;
  final int rollos;

  bool get visible => estado != EstadoJalar.oculto;
  bool get encendido => estado == EstadoJalar.listo;

  /// La nota chica debajo de JALAR. En [EstadoJalar.listo] es "+N" (el 🧻 va aparte, con `Emoji`).
  String nota(String moneda) => switch (estado) {
        EstadoJalar.oculto => '',
        EstadoJalar.pronto => tr('PRONTO', 'SOON'),
        EstadoJalar.faltanCagadas =>
          cagadas == 1 ? tr('FALTA 1 CAGADA', '1 POOP LEFT') : tr('FALTAN $cagadas CAGADAS', '$cagadas POOPS LEFT'),
        EstadoJalar.faltanMj => tr('FALTAN ${formatoMj(mj, ingles: enIngles)} $moneda', '${formatoMj(mj, ingles: true)} $moneda LEFT'),
        EstadoJalar.listo => '+$rollos',
      };

  /// Lo que dice el aviso al tocarlo apagado.
  String aviso(String moneda) => switch (estado) {
        EstadoJalar.pronto => tr('La cadena todavía no está lista. Vuelve en un rato.', "The chain isn't ready yet. Come back in a while."),
        EstadoJalar.faltanCagadas => cagadas == 1
            ? tr('Te falta 1 cagada real para jalar la cadena', 'You need 1 more real poop to flush')
            : tr('Te faltan $cagadas cagadas reales para jalar la cadena', 'You need $cagadas more real poops to flush'),
        EstadoJalar.faltanMj => tr('Junta ${formatoMj(mj)} $moneda más para ganar tu siguiente Rollo de Oro',
            'Earn ${formatoMj(mj, ingles: true)} more $moneda for your next Golden Roll'),
        _ => '',
      };
}

/// Estado del botón JALAR para esta partida y lo que dijo `imperio_cadena` ([cadena] null = no llegó).
BotonJalar botonJalar(Imperio im, EstadoCadena? cadena) {
  if (!im.cadenaDesbloqueada) return const BotonJalar(EstadoJalar.oculto);
  if (cadena == null) return const BotonJalar(EstadoJalar.pronto);
  final faltan = cadena.necesarias - cadena.cagadas;
  if (faltan > 0) return BotonJalar(EstadoJalar.faltanCagadas, cagadas: faltan);
  final rollos = im.rollosPorGanar;
  if (rollos < 1) return BotonJalar(EstadoJalar.faltanMj, mj: im.mjParaSiguienteRollo);
  return BotonJalar(EstadoJalar.listo, rollos: rollos);
}

/// "+12%" (con coma en español si hace falta): lo que suman los rollos.
String porcentajeRollos(int rollos, double pct) {
  final v = rollos * pct * 100;
  final t = v >= 100 ? formatoMj(v, ingles: enIngles) : (v == v.roundToDouble() ? '${v.round()}' : formatoMj(v, ingles: enIngles));
  return '+$t%';
}

/// Toque en JALAR encendido: confirmar, remolino, resultado y PRESUMIR. [anotar] en false cuando ya se anotó
/// `cadena_abre` al abrir la hoja de la Cadena (así no sale dos veces).
Future<void> jalarLaCadena(BuildContext context, ControlImperio c,
    {required void Function(String emoji, String texto) avisar, bool anotar = true}) async {
  final im = c.imperio;
  final boton = botonJalar(im, c.cadena);
  if (anotar) c.abrirCadena(boton.encendido);
  if (!boton.encendido || c.jalando) return;
  final antes = im.partida.rollos;
  final pct = im.ajustes.rolloPct;
  final seguro = await showDialog<bool>(
    context: context,
    builder: (context) => _Confirmar(rollos: boton.rollos, antes: antes, pct: pct),
  );
  if (seguro != true || !context.mounted) return;
  final int ganados;
  try {
    ganados = await c.jalarCadena();
  } catch (e) {
    if (context.mounted) avisar('🚽', textoError(e));
    return;
  }
  if (!context.mounted) return;
  await animarJalada(context);
  if (!context.mounted) return;
  final n = c.imperio.partida.jaladas;
  final presumir = await showDialog<bool>(
    context: context,
    builder: (context) => _Resultado(ganados: ganados, total: c.imperio.partida.rollos, jaladas: n, pct: pct),
  );
  if (presumir == true && context.mounted) await presumirJalada(context, n, ganados);
}

// ---------- Diálogos ----------

class _Confirmar extends StatelessWidget {
  const _Confirmar({required this.rollos, required this.antes, required this.pct});

  final int rollos, antes;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final suave = TextStyle(fontSize: 13, color: p.textoSuave);
    Widget linea(String emoji, String titulo, String texto) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Emoji(emoji, tamano: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: p.texto)),
                    Text(texto, style: suave),
                  ],
                ),
              ),
            ],
          ),
        );
    return AlertDialog(
      title: Text(tr('¿Jalar la cadena?', 'Flush the chain?')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: p.primario), borderRadius: BorderRadius.circular(radio)),
              child: Row(
                children: [
                  const Emoji('🧻', tamano: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(tr('+${formatoMj(rollos.toDouble())} Rollos de Oro', '+${formatoMj(rollos.toDouble(), ingles: true)} Golden Rolls'),
                              maxLines: 1, softWrap: false, style: numeros(context, tamano: 18, weight: FontWeight.w900)),
                        ),
                        Text(
                          tr('Producción ${porcentajeRollos(antes, pct)} → ${porcentajeRollos(antes + rollos, pct)} hasta la mudanza',
                              'Production ${porcentajeRollos(antes, pct)} → ${porcentajeRollos(antes + rollos, pct)} until you move'),
                          style: suave,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            linea('💸', tr('SE VA', 'GONE'), tr('Tu saldo, cagadores, mejoras, objetos y efectos.', 'Your balance, poopers, upgrades, items and effects.')),
            linea('🏆', tr('SE QUEDA', 'KEPT'),
                tr('Logros, MJ ganados, Rollos de Oro, Fichas, Cagada fresca y tus cagadas reales.',
                    'Achievements, total earned, Golden Rolls, Tickets, Fresh Poop and your real poops.')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('JALAR', 'FLUSH'))),
      ],
    );
  }
}

/// Antes de comprar La cadena del trono: explica qué es jalar, qué se gana y qué hace falta. true = COMPRAR.
Future<bool> confirmarComprarCadena(BuildContext context, ControlImperio c) async {
  final seguro = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmarCadena(cadena: c.cadena, pct: c.imperio.ajustes.rolloPct, moneda: monedaActual().abreviatura),
  );
  return seguro == true;
}

class _ConfirmarCadena extends StatelessWidget {
  const _ConfirmarCadena({required this.cadena, required this.pct, required this.moneda});

  final EstadoCadena? cadena;
  final double pct;
  final String moneda;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final suave = TextStyle(fontSize: 13, color: p.textoSuave);
    Widget linea(String emoji, String titulo, String texto) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Emoji(emoji, tamano: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: p.texto)),
                    Text(texto, style: suave),
                  ],
                ),
              ),
            ],
          ),
        );
    final uno = porcentajeRollos(1, pct);
    final ca = cadena;
    // Sin respuesta de imperio_cadena no se sabe el número: se explica sin él.
    final String falta;
    if (ca == null) {
      falta = tr('Hacer cagadas reales desde que empezaste el Imperio. El botón JALAR te dice cuántas faltan.',
          'Make real poops since you started the Empire. The FLUSH button tells you how many are left.');
    } else {
      final quedan = ca.necesarias - ca.cagadas;
      falta = quedan <= 0
          ? tr('${ca.necesarias} cagadas reales desde que empezaste. Ya las tienes.',
              '${ca.necesarias} real poops since you started. You already have them.')
          : tr('${ca.necesarias} cagadas reales desde que empezaste. Llevas ${ca.cagadas}: te faltan $quedan.',
              '${ca.necesarias} real poops since you started. You have ${ca.cagadas}: $quedan to go.');
    }
    return AlertDialog(
      title: Text(tr('¿Comprar La cadena del trono?', 'Buy The throne chain?')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: p.primario), borderRadius: BorderRadius.circular(radio)),
              child: Text(
                tr('Esta mejora te da el botón JALAR. Comprarla no borra nada: tú decides cuándo jalar.',
                    'This upgrade gives you the FLUSH button. Buying it erases nothing: you choose when to flush.'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.texto),
              ),
            ),
            linea('🚽', tr('JALAR LA CADENA', 'FLUSHING'),
                tr('Empiezas de cero: se van tus $moneda, cagadores, mejoras y objetos.',
                    'You start over: your $moneda, poopers, upgrades and items are gone.')),
            linea('🏆', tr('SE QUEDA', 'KEPT'),
                tr('Tus logros, tus Rollos de Oro y lo que pagaste con cagadas reales.',
                    'Your achievements, your Golden Rolls and what you paid for with real poops.')),
            linea('🧻', tr('QUÉ GANAS', 'WHAT YOU GET'),
                tr('Rollos de Oro: cada uno suma $uno de producción hasta la mudanza, aunque vuelvas a jalar.',
                    'Golden Rolls: each one adds $uno production until you move, even after you flush again.')),
            linea('💩', tr('QUÉ HACE FALTA', 'WHAT YOU NEED'), falta),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('AHORA NO', 'NOT NOW'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('COMPRAR', 'BUY'))),
      ],
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.ganados, required this.total, required this.jaladas, required this.pct});

  final int ganados, total, jaladas;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Emoji('🚽', tamano: 64),
          const SizedBox(height: 12),
          Text(tr('¡JALASTE LA CADENA!', 'YOU FLUSHED!'),
              textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1, color: p.texto)),
          const SizedBox(height: 4),
          Text(tr('Jalada número $jaladas', 'Flush number $jaladas'), style: TextStyle(fontSize: 12, color: p.textoSuave)),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('+${formatoMj(ganados.toDouble(), ingles: enIngles)}', maxLines: 1, softWrap: false,
                      style: numeros(context, tamano: 28, weight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 6),
              const Emoji('🧻', tamano: 28),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Ahora todo produce ${porcentajeRollos(total, pct)} hasta la mudanza', 'Everything now makes ${porcentajeRollos(total, pct)} until you move'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.textoSuave),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('LISTO', 'DONE'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('PRESUMIR', 'SHOW OFF'))),
      ],
    );
  }
}

// ---------- Presumir ----------

/// Errores de `validar_mensaje` para la tarjeta de jalada (los mismos textos que en la migración).
const _jaladaVieja = 'Esa jalada no existe o ya pasó';
const _jaladaRepetida = 'Esa jalada ya salió en el muro';

/// Pega la tarjeta "jaló la cadena por Nª vez" en el muro. El servidor revisa que la jalada [n] sea la última
/// y de hace menos de un día.
Future<void> presumirJalada(BuildContext context, int n, int rollos) async {
  if (!context.mounted || !await aceptoReglas(context)) return;
  try {
    await db.from('muro').insert({
      'tarjeta': {'tipo': 'jalada', 'n': n, 'rollos': rollos},
    });
    if (context.mounted) _aviso(context, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
  } catch (e) {
    if (!context.mounted) return;
    final mensaje = e is PostgrestException ? e.message : null;
    _aviso(
      context,
      mensaje == _jaladaVieja
          ? tr('Esa jalada ya es vieja para presumirla.', 'That flush is too old to show off.')
          : mensaje == _jaladaRepetida
              ? tr('Esa jalada ya está en el muro.', 'That flush is already on the wall.')
              : textoError(e),
    );
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

// ---------- Remolino ----------

/// El remolino de la jalada, según `movimiento(context)`: completo = todo gira y se encoge (~1,2 s),
/// simple = la poceta aparece y se va (fundido), nada = corte directo (no se muestra nada).
Future<void> animarJalada(BuildContext context) async {
  final mov = movimiento(context);
  if (mov == Movimiento.nada) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => _Remolino(completo: mov == Movimiento.completo),
  );
}

class _Remolino extends StatefulWidget {
  const _Remolino({required this.completo});

  final bool completo;

  @override
  State<_Remolino> createState() => _RemolinoState();
}

class _RemolinoState extends State<_Remolino> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.completo ? 1200 : 600));
  // Lo que se va por el desagüe: (ángulo inicial, distancia en fracción, emoji).
  static const _cosas = ['💩', '🧻', '💩', '🚽', '💩', '🧻', '💩', '🪠'];

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (!widget.completo) {
          // Fundido: sube y baja la opacidad.
          final o = t < .5 ? t * 2 : (1 - t) * 2;
          return ColoredBox(
            color: Colors.black.withValues(alpha: .6 * o),
            child: Center(child: Opacity(opacity: o, child: const Emoji('🚽', tamano: 120))),
          );
        }
        final giro = Curves.easeIn.transform(t);
        final escala = 1 - Curves.easeInCubic.transform(t);
        final fondo = t < .85 ? 1.0 : (1 - t) / .15;
        return ColoredBox(
          color: Colors.black.withValues(alpha: .7 * fondo),
          child: LayoutBuilder(
            builder: (context, caja) {
              final radioMax = min(caja.maxWidth, caja.maxHeight) * .42;
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(size: Size.square(radioMax * 2), painter: _Espiral(giro: giro * 4 * pi, color: p.primario, opacidad: fondo)),
                  for (var i = 0; i < _cosas.length; i++)
                    Transform.translate(
                      offset: Offset.fromDirection(i / _cosas.length * 2 * pi + giro * 5 * pi, radioMax * escala * (.55 + (i % 3) * .2)),
                      child: Transform.scale(scale: max(0.0, escala), child: Emoji(_cosas[i], tamano: 40)),
                    ),
                  Transform.rotate(angle: giro * 6 * pi, child: Transform.scale(scale: .4 + .6 * escala, child: const Emoji('💩', tamano: 72))),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Los brazos del remolino: espirales del color de acento que giran.
class _Espiral extends CustomPainter {
  _Espiral({required this.giro, required this.color, required this.opacidad});

  final double giro, opacidad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: .7 * opacidad);
    for (var brazo = 0; brazo < 4; brazo++) {
      final camino = Path();
      for (var k = 0; k <= 60; k++) {
        final f = k / 60;
        final a = giro + brazo * pi / 2 + f * 2.5 * pi;
        final punto = centro + Offset.fromDirection(a, r * (1 - f));
        if (k == 0) {
          camino.moveTo(punto.dx, punto.dy);
        } else {
          camino.lineTo(punto.dx, punto.dy);
        }
      }
      canvas.drawPath(camino, pincel);
    }
  }

  @override
  bool shouldRepaint(_Espiral vieja) => vieja.giro != giro || vieja.opacidad != opacidad;
}
