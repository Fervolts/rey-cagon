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
import 'decision.dart';
import 'mudanza.dart' show AvisarMudanza, BarraRequisito;
import 'nube.dart';

// ABDICAR 👑 en pantalla (capa 3 de la escalera): cuándo sale el botón de la barra, la hoja con la tarjeta de decisión,
// la confirmación, la lluvia de coronas y el resultado. También LA CORTE, que vive en la hoja y se paga con Coronas.

BoxDecoration _caja(BuildContext context, {Color? borde}) {
  final p = paleta(context);
  return BoxDecoration(color: p.tarjeta, border: Border.all(color: borde ?? p.borde), borderRadius: BorderRadius.circular(radio));
}

/// Clave en [Partida.guiaVista] cuando el botón ABDICAR ya se descubrió (sigue visible aunque la regla deje de cumplirse).
const claveAbdicarVista = 'abdicar_vista';

/// Clave en [Partida.guiaVista] cuando ya abriste la hoja de ABDICAR: el botón deja de brillar.
const claveAbdicarAbierta = 'abdicar_abierta';

/// El botón ABDICAR 👑 de la barra: sale si ya abdicaste, si ya lo descubriste o si la casa ya no rinde ([yaNoRinde]).
bool abdicarDescubierta(ControlImperio c) {
  final pa = c.imperio.partida;
  return pa.abdicaciones > 0 || pa.guiaVista.contains(claveAbdicarVista) || yaNoRinde(c);
}

/// Ya no rinde mudarse: tienes `abdicar_mudanzas` mudanzas, la próxima mudanza daría menos que `abdicar_descubre_pct`
/// de las Llaves que ya ganaste en el reinado y llevas `abdicar_descubre_dias` días en esta casa. Solo con el servidor
/// al día (sin la migración no se puede abdicar).
bool yaNoRinde(ControlImperio c) {
  final im = c.imperio;
  final a = im.ajustes;
  final pa = im.partida;
  if (!c.abdicarDisponible || pa.casaEn <= 0) return false;
  final dias = (c.ahora - pa.casaEn) / Duration.millisecondsPerDay;
  return pa.mudanzas >= a.abdicarMudanzas && im.llavesPorGanar < a.abdicarDescubrePct * pa.llavesGanadas && dias >= a.abdicarDescubreDias;
}

/// El botón brilla hasta que abres la hoja por primera vez (solo antes de la primera abdicación).
bool abdicarResaltada(ControlImperio c) {
  final pa = c.imperio.partida;
  return pa.abdicaciones == 0 && !pa.guiaVista.contains(claveAbdicarAbierta);
}

/// Los 3 requisitos: (emoji, valor, meta, texto es, texto en).
List<(String, double, double, String, String)> _requisitos(ControlImperio c) {
  final im = c.imperio;
  final a = im.ajustes;
  final pa = im.partida;
  return [
    ('🏠', pa.mudanzas.toDouble(), a.abdicarMudanzas.toDouble(), 'Mudanzas en este reinado', 'Moves in this reign'),
    ('🔑', pa.llavesGanadas.toDouble(), a.abdicarLlaves, 'Llaves ganadas en este reinado', 'Keys earned in this reign'),
    ('💩', c.cagadasReinado.toDouble(), a.abdicarCagadas.toDouble(), 'Cagadas reales (3 por día como máximo)',
        'Real poops (3 per day at most)'),
  ];
}

double _fraccion(double valor, double meta) => meta <= 0 ? 1 : valor / meta;

/// Hoja de ABDICAR (capa 3): la tarjeta DEJAS / RECIBES con los 3 requisitos y el botón ABDICAR, y LA CORTE.
Future<void> abrirAbdicar(BuildContext context, ControlImperio control, AvisarMudanza avisar) {
  control.anotar('abdicar_abre');
  control.marcarGuia(claveAbdicarAbierta);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (hoja) => ListenableBuilder(
      listenable: control,
      builder: (hoja, _) => _HojaAbdicar(control: control, avisar: avisar),
    ),
  );
}

class _HojaAbdicar extends StatelessWidget {
  const _HojaAbdicar({required this.control, required this.avisar});

  final ControlImperio control;
  final AvisarMudanza avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final pa = im.partida;
    final puede = control.abdicarDisponible && im.puedeAbdicar(control.cagadasReinado);
    final coronas = im.coronasPorGanar;
    final pct = (im.ajustes.coronaPct * 100).round();
    final suave = TextStyle(fontSize: 12, color: p.textoSuave);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Rotulo(tr('Abdicar', 'Abdicate')),
            const SizedBox(height: 8),
            TarjetaDecision(
              key: const Key('decision_abdicar'),
              lista: puede,
              dejas: tr('Tus casas, tus Llaves, el Llavero y todo lo que se va al mudarte',
                  'Your houses, your Keys, the Key ring and everything a move takes away'),
              recibes: tr('+$coronas Coronas y la ${dinastia(pa.abdicaciones + 1)}: cada Corona sin gastar da +$pct% de producción',
                  '+$coronas Crowns and ${dinastia(pa.abdicaciones + 1)}: each unspent Crown gives +$pct% production'),
              cabeza: Row(
                children: [
                  const Emoji('👑', tamano: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Reinas en: ', 'You reign in: ') + conDinastia(nombreCasa(pa.mudanzas), pa.abdicaciones),
                            style: TextStyle(fontWeight: FontWeight.w900, color: p.texto)),
                        Text(
                            tr('Abdica y vuelve a empezar desde el Rancho, pero con Coronas que multiplican todo.',
                                'Abdicate and start over from the Shack, but with Crowns that multiply everything.'),
                            style: suave),
                      ],
                    ),
                  ),
                ],
              ),
              hijos: [
                const SizedBox(height: 12),
                for (final r in _requisitos(control))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Emoji(r.$1, tamano: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(tr(r.$4, r.$5), style: TextStyle(fontSize: 12, color: p.texto))),
                                  Text('${min(r.$2, r.$3).round()}/${r.$3.round()}', style: numeros(context, tamano: 12)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              BarraRequisito(_fraccion(r.$2, r.$3), alto: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(tr('Más Llaves ganadas en el reinado, más Coronas.', 'More Keys earned in the reign, more Crowns.'), style: suave),
                if (!control.abdicarDisponible) ...[
                  const SizedBox(height: 6),
                  Text(tr('Abdicar necesita conexión. Prueba en un rato.', 'Abdicating needs a connection. Try again in a while.'),
                      style: suave),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  key: const Key('abdicar'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: puede && !control.abdicando && !control.mudando && !control.jalando
                      ? () => _abdicar(context, control, avisar)
                      : null,
                  child: Text(control.abdicando ? tr('ABDICANDO...', 'ABDICATING...') : tr('ABDICAR', 'ABDICATE')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SeccionCorte(control: control, avisar: avisar),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _motivo(String? motivo) => switch (motivo) {
      'mudanzas' => tr('Te faltan mudanzas en este reinado', 'You need more moves in this reign'),
      'llaves' => tr('Te faltan Llaves ganadas en este reinado', 'You need more Keys earned in this reign'),
      'cagadas' => tr('Te faltan cagadas reales (cuentan 3 por día)', 'You need more real poops (3 per day count)'),
      _ => tr('No se pudo abdicar. Prueba otra vez', "The abdication didn't go through. Try again"),
    };

Future<void> _abdicar(BuildContext context, ControlImperio c, AvisarMudanza avisar) async {
  final im = c.imperio;
  final seguro = await showDialog<bool>(
    context: context,
    builder: (_) => _Confirmar(
      abdicaciones: im.partida.abdicaciones,
      coronas: im.coronasPorGanar,
      pct: im.ajustes.coronaPct,
      heraldo: im.nivelCorte('heraldo'),
      tesorero: im.nivelCorte('tesorero'),
    ),
  );
  if (seguro != true || !context.mounted) return;
  final ResultadoAbdicar r;
  try {
    r = await c.abdicar();
  } catch (e) {
    avisar('👑', textoError(e));
    return;
  }
  if (!r.ok) {
    avisar('👑', _motivo(r.motivo));
    return;
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  await animarCoronas(context);
  if (!nav.mounted) return;
  final pa = c.imperio.partida;
  await showDialog<void>(
    context: nav.context,
    builder: (_) => _Resultado(abdicaciones: pa.abdicaciones, mudanzas: pa.mudanzas, coronas: r.coronas, total: c.imperio.coronas),
  );
}

class _Confirmar extends StatelessWidget {
  const _Confirmar({required this.abdicaciones, required this.coronas, required this.pct, required this.heraldo, required this.tesorero});

  final int abdicaciones, coronas, heraldo, tesorero;
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
    final arranque = nombreCasa(heraldo);
    final llaves = tesorero > 0
        ? tr(' El Tesorero te guarda el ${tesorero * 10}% de las Llaves ganadas.', ' The Treasurer keeps ${tesorero * 10}% of the Keys you earned.')
        : '';
    return AlertDialog(
      title: Text(tr('¿Abdicar?', 'Abdicate?')),
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
                  const Emoji('👑', tamano: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('+$coronas Coronas', '+$coronas Crowns'), style: numeros(context, tamano: 18, weight: FontWeight.w900)),
                        Text(
                            tr('Cada una +${(pct * 100).round()}% de producción mientras no la gastes. Empieza la ${dinastia(abdicaciones + 1)}.',
                                'Each one +${(pct * 100).round()}% production while unspent. ${dinastia(abdicaciones + 1)} begins.'),
                            style: suave),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            linea('💸', tr('SE VA', 'GONE'),
                tr('Todo lo que se va al mudarte, tus casas (vuelves a: $arranque), tus Llaves y el Llavero.$llaves',
                    'Everything a move takes, your houses (you go back to: $arranque), your Keys and the Key ring.$llaves')),
            linea('🏆', tr('SE QUEDA', 'KEPT'),
                tr('Logros, estilos, Ciruelas, Fichas, racha, compras, tus jaladas de siempre, los MJ ganados, las Coronas y La Corte, entre abdicaciones.',
                    'Achievements, styles, Plums, Tickets, streak, purchases, all your flushes, total earned, Crowns and the Court, across abdications.')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ABDICAR', 'ABDICATE'))),
      ],
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.abdicaciones, required this.mudanzas, required this.coronas, required this.total});

  final int abdicaciones, mudanzas, coronas, total;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final casa = casaDe(mudanzas);
    return AlertDialog(
      title: Text(tr('¡Larga vida a la ${dinastia(abdicaciones)}!', 'Long live ${dinastia(abdicaciones)}!')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Emoji('👑', tamano: 72),
          const SizedBox(height: 8),
          Text(tr('Vuelves a tu ${nombreCasa(mudanzas)}', 'Back to your ${nombreCasa(mudanzas)}'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.textoSuave)),
          const SizedBox(height: 4),
          Emoji(casa.emoji, tamano: 32),
          const SizedBox(height: 12),
          Text(tr('+$coronas Coronas (tienes $total)', '+$coronas Crowns (you have $total)'),
              style: numeros(context, tamano: 16, weight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(tr('Gástalas en La Corte, en la hoja de Abdicar.', 'Spend them in the Court, in the Abdicate sheet.'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textoSuave)),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('LISTO', 'DONE')))],
    );
  }
}

/// Coronas que caen: una lluvia corta en completo, una corona que aparece en simple y nada si el teléfono pide sin
/// movimiento.
Future<void> animarCoronas(BuildContext context) async {
  final mov = movimiento(context);
  if (mov == Movimiento.nada) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => _Coronas(completo: mov == Movimiento.completo),
  );
}

class _Coronas extends StatefulWidget {
  const _Coronas({required this.completo});

  final bool completo;

  @override
  State<_Coronas> createState() => _CoronasState();
}

class _CoronasState extends State<_Coronas> with SingleTickerProviderStateMixin {
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
            child: Center(child: Opacity(opacity: o, child: const Emoji('👑', tamano: 120))),
          );
        }
        final fondo = t < .85 ? 1.0 : (1 - t) / .15;
        return ColoredBox(
          color: Colors.black.withValues(alpha: .7 * fondo),
          child: LayoutBuilder(
            builder: (context, caja) {
              // 7 coronas que caen de arriba, cada una con su retraso; la del medio, grande, se queda en el centro.
              const n = 7;
              return Stack(
                children: [
                  for (var i = 0; i < n; i++)
                    Builder(builder: (context) {
                      final retraso = (i * 37 % n) / n * .35;
                      final f = ((t - retraso) / (1 - retraso)).clamp(0.0, 1.0);
                      final medio = i == n ~/ 2;
                      final tamano = medio ? 96.0 : 44.0;
                      final x = (i + .5) / n * caja.maxWidth - tamano / 2;
                      final fin = medio ? caja.maxHeight / 2 - tamano / 2 : caja.maxHeight + tamano;
                      final y = -tamano + Curves.easeInCubic.transform(f) * (fin + tamano);
                      return Positioned(
                        left: x,
                        top: y,
                        child: Opacity(opacity: fondo, child: Emoji('👑', tamano: tamano)),
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Sección LA CORTE 👑 de la hoja de ABDICAR: mejoras que se pagan con Coronas y se quedan entre abdicaciones.
class SeccionCorte extends StatelessWidget {
  const SeccionCorte({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final AvisarMudanza avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Rotulo(tr('La Corte', 'The Court'))),
            const Emoji('👑', tamano: 16),
            const SizedBox(width: 4),
            Text(tr('${im.coronas} Coronas', '${im.coronas} Crowns'), style: numeros(context, tamano: 12, weight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
            tr('Se paga con Coronas y se queda entre abdicaciones. Cada Corona que gastas deja de darte +${(im.ajustes.coronaPct * 100).round()}%.',
                'Paid with Crowns and kept across abdications. Each Crown you spend stops giving you +${(im.ajustes.coronaPct * 100).round()}%.'),
            style: TextStyle(fontSize: 12, color: p.textoSuave)),
        const SizedBox(height: 8),
        for (final m in mejorasCorte) _fila(context, p, m),
      ],
    );
  }

  Widget _fila(BuildContext context, Paleta p, MejoraCorte m) {
    final im = control.imperio;
    final n = im.nivelCorte(m.id);
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
            key: Key('corte_${m.id}'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 44)),
            onPressed: !tope && im.puedeComprarCorte(m.id)
                ? () {
                    if (control.comprarCorte(m.id)) avisar(m.emoji, tr('${m.nombreEs}: listo', '${m.nombreEn}: done'));
                  }
                : null,
            child: tope
                ? Text(tr('MÁX', 'MAX'), style: numeros(context, tamano: 13, weight: FontWeight.w900))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${m.precio(n)} ', style: numeros(context, tamano: 13, weight: FontWeight.w900)),
                      const Emoji('👑', tamano: 18),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
