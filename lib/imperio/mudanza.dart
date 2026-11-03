import 'dart:math';

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'casas.dart';
import 'catalogo.dart';
import 'control.dart';
import 'formato.dart';
import 'nube.dart';

// La Mudanza 🏠 en pantalla: la tira con los 3 requisitos (encima de la barra de abajo), la hoja con el detalle, la
// confirmación, el camión y el resultado. También la sección LLAVERO 🔑 de la tienda.

/// Aviso corto de la pantalla del Imperio (emoji, texto).
typedef AvisarMudanza = void Function(String emoji, String texto);

BoxDecoration _caja(BuildContext context, {Color? borde, Color? fondo}) {
  final p = paleta(context);
  return BoxDecoration(color: fondo ?? p.tarjeta, border: Border.all(color: borde ?? p.borde), borderRadius: BorderRadius.circular(radio));
}

/// x3, x40, x1,5 (coma en español).
String _x(double v) {
  var s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return 'x${tr(s.replaceAll('.', ','), s)}';
}

String _num(double v) => formatoMj(v, ingles: enIngles);

/// La tira sale cuando el servidor ya conoce la mudanza y hubo al menos una jalada, o si ya te mudaste alguna vez.
bool mostrarTiraMudanza(ControlImperio c) {
  final pa = c.imperio.partida;
  return (c.mudanzaDisponible && pa.jaladas >= 1) || pa.mudanzas > 0;
}

/// Barra fina y cuadrada: [f] de 0 a 1.
class _Barra extends StatelessWidget {
  const _Barra(this.f, {this.alto = 6});

  final double f;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final lleno = f >= 1;
    return Container(
      height: alto,
      decoration: BoxDecoration(color: p.suave, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: f.isFinite ? f.clamp(0.0, 1.0) : 0,
          child: ColoredBox(color: lleno ? acento : p.primario, child: const SizedBox.expand()),
        ),
      ),
    );
  }
}

/// Los 3 requisitos: (emoji, valor, meta, texto es, texto en).
List<(String, double, double, String, String)> _requisitos(ControlImperio c) {
  final im = c.imperio;
  final a = im.ajustes;
  final pa = im.partida;
  return [
    ('🧻', im.rollosCasa.toDouble(), im.rollosParaMudanza, 'Rollos de Oro en esta casa', 'Golden Rolls in this house'),
    ('🚽', pa.jaladasCasa.toDouble(), a.mudanzaJaladas.toDouble(), 'Jaladas en esta casa', 'Flushes in this house'),
    ('💩', c.cagadasCasa.toDouble(), a.mudanzaCagadas.toDouble(), 'Cagadas reales (3 por día como máximo)', 'Real poops (3 per day at most)'),
  ];
}

double _fraccion(double valor, double meta) => meta <= 0 ? 1 : valor / meta;

/// Tira compacta encima de la barra de abajo: la casa, los 3 requisitos en mini y el Mayordomo si lo tienes.
class TiraMudanza extends StatelessWidget {
  const TiraMudanza({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final AvisarMudanza avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final m = im.partida.mudanzas;
    final lista = control.mudanzaDisponible && im.puedeMudarse(control.cagadasCasa);
    final mayordomo = im.nivelLlavero('mayordomo') > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('tira_mudanza'),
              borderRadius: BorderRadius.circular(radio),
              onTap: () => abrirMudanza(context, control, avisar),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: _caja(context, borde: lista ? acento : null),
                child: Row(
                  children: [
                    Emoji(casaDe(m).emoji, tamano: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(nombreCasa(m).toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: numeros(context, tamano: 11, weight: FontWeight.w800).copyWith(letterSpacing: 1)),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              for (final (i, r) in _requisitos(control).indexed) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Emoji(r.$1, tamano: 12),
                                const SizedBox(width: 3),
                                Expanded(child: _Barra(_fraccion(r.$2, r.$3), alto: 5)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(lista ? tr('MUDARSE', 'MOVE') : tr('MUDANZA', 'MOVING'),
                        style: numeros(context, tamano: 11, weight: FontWeight.w900, color: lista ? p.texto : p.textoSuave)
                            .copyWith(letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ),
          if (mayordomo) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: im.mayordomoTrabajando
                  ? tr('Mayordomo trabajando. Toca para apagarlo', 'Butler working. Tap to switch him off')
                  : tr('Mayordomo apagado. Toca para prenderlo', 'Butler off. Tap to switch him on'),
              child: InkWell(
                key: const Key('mayordomo_cambiar'),
                borderRadius: BorderRadius.circular(radio),
                onTap: () {
                  control.cambiarMayordomo();
                  avisar('🤵', control.imperio.mayordomoTrabajando
                      ? tr('Mayordomo prendido: compra cagadores solo', 'Butler on: he buys Poopers by himself')
                      : tr('Mayordomo apagado', 'Butler off'));
                },
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: _caja(context, borde: im.mayordomoTrabajando ? acento : null),
                  child: Opacity(opacity: im.mayordomoTrabajando ? 1 : .35, child: const Emoji('🤵', tamano: 22)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hoja de la mudanza: la casa, los requisitos completos, las Llaves por ganar y el botón MUDARSE.
Future<void> abrirMudanza(BuildContext context, ControlImperio control, AvisarMudanza avisar) {
  control.anotar('mudanza_abre');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (hoja) => ListenableBuilder(
      listenable: control,
      builder: (hoja, _) => _HojaMudanza(control: control, avisar: avisar),
    ),
  );
}

class _HojaMudanza extends StatelessWidget {
  const _HojaMudanza({required this.control, required this.avisar});

  final ControlImperio control;
  final AvisarMudanza avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final m = im.partida.mudanzas;
    final casa = casaDe(m);
    final siguiente = casaDe(m + 1);
    final puede = control.mudanzaDisponible && im.puedeMudarse(control.cagadasCasa);
    final llaves = im.llavesPorGanar;
    final suave = TextStyle(fontSize: 12, color: p.textoSuave);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Rotulo(tr('Mudanza', 'Moving')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _caja(context),
              child: Row(
                children: [
                  Emoji(casa.emoji, tamano: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Vives en: ${nombreCasa(m)}', 'You live in: ${nombreCasa(m)}'),
                            style: TextStyle(fontWeight: FontWeight.w900, color: p.texto)),
                        Text(tr(casa.fraseEs, casa.fraseEn), style: suave),
                        const SizedBox(height: 2),
                        Text(
                            tr('Producción ${_x(multiplicadorCasa(m))} · Rollos por jalada ${_x(factorRollosCasa(m).toDouble())}',
                                'Production ${_x(multiplicadorCasa(m))} · Rolls per flush ${_x(factorRollosCasa(m).toDouble())}'),
                            style: numeros(context, tamano: 12, color: p.textoSuave)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Rotulo(tr('Para mudarte', 'To move')),
            const SizedBox(height: 6),
            for (final r in _requisitos(control))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Emoji(r.$1, tamano: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(tr(r.$4, r.$5), style: TextStyle(fontSize: 12, color: p.texto))),
                              Text('${_num(min(r.$2, r.$3))}/${_num(r.$3)}', style: numeros(context, tamano: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _Barra(_fraccion(r.$2, r.$3), alto: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _caja(context, borde: puede ? acento : null),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Emoji('🔑', tamano: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            llaves > 0
                                ? tr('Si te mudas ahora: +$llaves Llaves', 'If you move now: +$llaves Keys')
                                : tr('Todavía no ganas Llaves', 'No Keys yet'),
                            style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      tr('Cada Llave sin gastar da +${(im.ajustes.llavePct * 100).round()}% de producción. Más Rollos en esta casa, más Llaves.',
                          'Each unspent Key gives +${(im.ajustes.llavePct * 100).round()}% production. More Rolls in this house, more Keys.'),
                      style: suave),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(tr('Siguiente: ', 'Next: '), style: suave),
                      Emoji(siguiente.emoji, tamano: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                            tr('${nombreCasa(m + 1)}, producción ${_x(multiplicadorCasa(m + 1))}',
                                '${nombreCasa(m + 1)}, production ${_x(multiplicadorCasa(m + 1))}'),
                            style: suave),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!control.mudanzaDisponible) ...[
              const SizedBox(height: 8),
              Text(tr('La mudanza necesita conexión. Prueba en un rato.', 'Moving needs a connection. Try again in a while.'),
                  style: suave),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('mudarse'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: puede && !control.mudando && !control.jalando ? () => _mudarse(context, control, avisar) : null,
              child: Text(control.mudando ? tr('MUDANDO...', 'MOVING...') : tr('MUDARSE', 'MOVE')),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _motivo(String? motivo) => switch (motivo) {
      'rollos' => tr('Te faltan Rollos de Oro en esta casa', 'You need more Golden Rolls in this house'),
      'jaladas' => tr('Te faltan jaladas en esta casa', 'You need more flushes in this house'),
      'cagadas' => tr('Te faltan cagadas reales (cuentan 3 por día)', 'You need more real poops (3 per day count)'),
      _ => tr('No se pudo hacer la mudanza. Prueba otra vez', "The move didn't go through. Try again"),
    };

Future<void> _mudarse(BuildContext context, ControlImperio c, AvisarMudanza avisar) async {
  final im = c.imperio;
  final seguro = await showDialog<bool>(
    context: context,
    builder: (_) => _Confirmar(
      mudanzas: im.partida.mudanzas,
      llaves: im.llavesPorGanar,
      pct: im.ajustes.llavePct,
      camion: im.nivelLlavero('camion_mudanza'),
    ),
  );
  if (seguro != true || !context.mounted) return;
  final ResultadoMudanza r;
  try {
    r = await c.mudarse();
  } catch (e) {
    avisar('🏠', textoError(e));
    return;
  }
  if (!r.ok) {
    avisar('🏠', _motivo(r.motivo));
    return;
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  await animarMudanza(context);
  if (!nav.mounted) return;
  nav.pop();
  final m = c.imperio.partida.mudanzas;
  await showDialog<void>(
    context: nav.context,
    builder: (_) => _Resultado(mudanzas: m, llaves: r.llaves, total: c.imperio.llaves),
  );
}

class _Confirmar extends StatelessWidget {
  const _Confirmar({required this.mudanzas, required this.llaves, required this.pct, required this.camion});

  final int mudanzas, llaves, camion;
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
    final nueva = casaDe(mudanzas + 1);
    final porLlave = (pct * 100).round();
    final lleva = camion > 0
        ? tr(' El Camión de mudanza se lleva el ${camion * 10}% de cada nodo de Plomería.',
            ' The Moving truck keeps ${camion * 10}% of each Plumbing node.')
        : '';
    return AlertDialog(
      title: Text(tr('¿Mudarte a ${nombreCasa(mudanzas + 1)}?', 'Move to the ${nombreCasa(mudanzas + 1)}?')),
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
                  Emoji(nueva.emoji, tamano: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('+$llaves Llaves', '+$llaves Keys'), style: numeros(context, tamano: 18, weight: FontWeight.w900)),
                        Text(
                            tr('Cada una +$porLlave% de producción mientras no la gastes. La casa nueva produce ${_x(multiplicadorCasa(mudanzas + 1))}.',
                                'Each one +$porLlave% production while unspent. The new house produces ${_x(multiplicadorCasa(mudanzas + 1))}.'),
                            style: suave),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            linea('💸', tr('SE VA', 'GONE'),
                tr('Tu saldo, cagadores, mejoras y objetos, tus Rollos de Oro, la Plomería y las jaladas de esta casa.$lleva',
                    'Your balance, Poopers, upgrades and items, your Golden Rolls, the Plumbing and this house\'s flushes.$lleva')),
            linea('🏆', tr('SE QUEDA', 'KEPT'),
                tr('Logros, estilos, Ciruelas, Fichas, racha, compras, Llaves, Llavero, tus jaladas de siempre y los MJ ganados.',
                    'Achievements, styles, Plums, Tickets, streak, purchases, Keys, Key ring, all your flushes and total earned.')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('MUDARSE', 'MOVE'))),
      ],
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.mudanzas, required this.llaves, required this.total});

  final int mudanzas, llaves, total;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final casa = casaDe(mudanzas);
    return AlertDialog(
      title: Text(tr('¡Bienvenido a tu ${nombreCasa(mudanzas)}!', 'Welcome to your ${nombreCasa(mudanzas)}!')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Emoji(casa.emoji, tamano: 72),
          const SizedBox(height: 8),
          Text(tr(casa.fraseEs, casa.fraseEn), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.textoSuave)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Emoji('🔑', tamano: 24),
              const SizedBox(width: 6),
              Text(tr('+$llaves Llaves (tienes $total)', '+$llaves Keys (you have $total)'),
                  style: numeros(context, tamano: 16, weight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              tr('Producción ${_x(multiplicadorCasa(mudanzas))} y ${_x(factorRollosCasa(mudanzas).toDouble())} Rollos por jalada. Gasta Llaves en el Llavero de la tienda.',
                  'Production ${_x(multiplicadorCasa(mudanzas))} and ${_x(factorRollosCasa(mudanzas).toDouble())} Rolls per flush. Spend Keys in the shop\'s Key ring.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.textoSuave)),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('LISTO', 'DONE')))],
    );
  }
}

/// El camión de la mudanza: cruza la pantalla en completo, un fundido en simple y nada si el teléfono pide sin movimiento.
Future<void> animarMudanza(BuildContext context) async {
  final mov = movimiento(context);
  if (mov == Movimiento.nada) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => _Camion(completo: mov == Movimiento.completo),
  );
}

class _Camion extends StatefulWidget {
  const _Camion({required this.completo});

  final bool completo;

  @override
  State<_Camion> createState() => _CamionState();
}

class _CamionState extends State<_Camion> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.completo ? 1400 : 600));

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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (!widget.completo) {
          final o = t < .5 ? t * 2 : (1 - t) * 2;
          return ColoredBox(
            color: Colors.black.withValues(alpha: .6 * o),
            child: Center(child: Opacity(opacity: o, child: const Emoji('🚚', tamano: 120))),
          );
        }
        final fondo = t < .85 ? 1.0 : (1 - t) / .15;
        return ColoredBox(
          color: Colors.black.withValues(alpha: .7 * fondo),
          child: LayoutBuilder(
            builder: (context, caja) {
              final ancho = caja.maxWidth;
              // El camión entra por la izquierda, frena en el centro y sigue; un saltico cada tanto por los huecos.
              final avance = Curves.easeInOutCubic.transform(t);
              final x = -ancho * .6 + avance * ancho * 1.2;
              final salto = -6 * sin(t * pi * 10).abs();
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(opacity: fondo, child: const Emoji('🏠', tamano: 96)),
                  Transform.translate(
                    offset: Offset(x, 48 + salto),
                    child: Transform.flip(flipX: true, child: const Emoji('🚚', tamano: 88)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Sección LLAVERO 🔑 de la tienda: mejoras que se pagan con Llaves y sobreviven a las mudanzas.
class SeccionLlavero extends StatelessWidget {
  const SeccionLlavero({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final AvisarMudanza avisar;

  /// Sale si ya te mudaste o tienes Llaves.
  static bool visible(ControlImperio c) => c.imperio.partida.mudanzas > 0 || c.imperio.llaves > 0;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Rotulo(tr('Llavero', 'Key ring'))),
            const Emoji('🔑', tamano: 16),
            const SizedBox(width: 4),
            Text(tr('${im.llaves} Llaves', '${im.llaves} Keys'), style: numeros(context, tamano: 12, weight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
            tr('Se paga con Llaves y no se pierde al mudarte. Cada Llave que gastas deja de darte +${(im.ajustes.llavePct * 100).round()}%.',
                'Paid with Keys and kept when you move. Each Key you spend stops giving you +${(im.ajustes.llavePct * 100).round()}%.'),
            style: TextStyle(fontSize: 12, color: p.textoSuave)),
        const SizedBox(height: 8),
        for (final m in mejorasLlavero) _fila(context, p, m),
      ],
    );
  }

  Widget _fila(BuildContext context, Paleta p, MejoraLlavero m) {
    final im = control.imperio;
    final n = im.nivelLlavero(m.id);
    final tope = n >= m.limite;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: _caja(context),
      child: Row(
        children: [
          Emoji(m.emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(m.nombreEs, m.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                Text(tr(m.descEs, m.descEn), style: TextStyle(fontSize: 12, color: p.textoSuave)),
                const SizedBox(height: 2),
                Text('$n/${m.limite}', style: numeros(context, tamano: 11, color: p.textoSuave)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: Key('llavero_${m.id}'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 44)),
            onPressed: !tope && im.puedeComprarLlavero(m.id)
                ? () {
                    if (control.comprarLlavero(m.id)) avisar(m.emoji, tr('${m.nombreEs}: listo', '${m.nombreEn}: done'));
                  }
                : null,
            child: tope
                ? Text(tr('MÁX', 'MAX'), style: numeros(context, tamano: 13, weight: FontWeight.w900))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${m.precio(n)} ', style: numeros(context, tamano: 13, weight: FontWeight.w900)),
                      const Emoji('🔑', tamano: 18),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
