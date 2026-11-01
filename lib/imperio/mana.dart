// Maná de Tripa 🌀 (fase 2): barra fina bajo los chips y hoja de habilidades.
import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'control.dart';
import 'fichas.dart' show faltaCorto;
import 'formato.dart';
import 'motor.dart';

/// Barra fina del Maná. Solo con el candado de 15 cagadas abierto; al tocarla abre la hoja.
class BarraMana extends StatelessWidget {
  const BarraMana({super.key, required this.control, required this.avisar, required this.ahora});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;
  final int ahora;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    if (!im.manaAbierto) return const SizedBox.shrink();
    final mana = im.mana(ahora);
    final lista = habilidades.any((h) => im.puedeUsarHabilidad(h.id, ahora));
    return GestureDetector(
      key: const Key('barra_mana'),
      behavior: HitTestBehavior.opaque,
      onTap: () => abrirHojaMana(context, control, avisar),
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            const Emoji('🌀', tamano: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(color: p.suave, border: Border.all(color: lista ? acento : p.borde)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (mana / manaMax).clamp(0.0, 1.0),
                  child: Container(color: acento),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('${mana.floor()}/${manaMax.round()}', style: numeros(context, tamano: 11, color: p.textoSuave)),
          ],
        ),
      ),
    );
  }
}

/// Abre la hoja de habilidades. [avisar] pone el aviso de arriba de la pantalla del Imperio.
Future<void> abrirHojaMana(BuildContext context, ControlImperio control, void Function(String emoji, String texto) avisar) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => ListenableBuilder(
      listenable: control,
      builder: (context, _) => HojaMana(control: control, avisar: avisar),
    ),
  );
}

class HojaMana extends StatelessWidget {
  const HojaMana({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  void _usar(Habilidad h) {
    final r = control.usarHabilidad(h.id);
    if (r == null) return;
    final mj = formatoMj(r.mj.abs(), ingles: enIngles);
    if (r.fallo) {
      avisar('💦', tr('¡El chorro se tapó! Perdiste $mj', 'The jet clogged! You lost $mj'));
    } else if (h.id == 'chorro') {
      avisar(h.emoji, tr('Chorro a presión: +$mj', 'Pressure jet: +$mj'));
    } else {
      avisar(h.emoji, tr('${h.nombreEs}: ${h.descEs}', '${h.nombreEn}: ${h.descEn}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final ahora = control.ahora;
    final mana = im.mana(ahora);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Emoji('🌀', tamano: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('${mana.floor()}/${manaMax.round()} Maná de Tripa', '${mana.floor()}/${manaMax.round()} Gut Mana'),
                          key: const Key('saldo_mana'), style: numeros(context, tamano: 22, weight: FontWeight.w900)),
                      Text(
                          tr('Se llena solo en 1 h, también fuera de la app. Cada cagada real lo llena entero.',
                              'Refills by itself in 1 h, even with the app closed. Every real poop fills it up.'),
                          style: TextStyle(fontSize: 12, color: p.textoSuave)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final h in habilidades) _fila(context, p, im, h, ahora),
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Paleta p, Imperio im, Habilidad h, int ahora) {
    final espera = im.esperaHabilidad(h.id, ahora);
    final puede = im.puedeUsarHabilidad(h.id, ahora);
    final String estado;
    if (espera != null) {
      estado = tr('Espera: ${faltaCorto(espera.inMilliseconds)}', 'Wait: ${faltaCorto(espera.inMilliseconds)}');
    } else if (im.mana(ahora) < h.mana) {
      estado = tr('Falta Maná', 'Not enough Mana');
    } else if (h.id == 'corre_corre' && !puede) {
      estado = tr('Pide un Atasco', 'Needs a Clog');
    } else {
      estado = tr('Luego espera ${faltaCorto(h.espera.inMilliseconds)}', 'Then wait ${faltaCorto(h.espera.inMilliseconds)}');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Row(
        children: [
          Emoji(h.emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(h.nombreEs, h.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                Text(tr(h.descEs, h.descEn), style: TextStyle(fontSize: 12, color: p.textoSuave)),
                const SizedBox(height: 2),
                Text(estado, style: numeros(context, tamano: 11, color: p.textoSuave)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: Key('usar_hab_${h.id}'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: puede ? () => _usar(h) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('${tr('USAR', 'USE')} ${h.mana} '), const Emoji('🌀', tamano: 14)],
            ),
          ),
        ],
      ),
    );
  }
}
