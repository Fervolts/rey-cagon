import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'tema.dart';

// Apps que vienen: emoji, nombre y el chiste del anuncio.
const _proximas = [
  (emoji: '🍺', nombre: 'REY MEÓN', reina: 'REINA MEONA', texto: 'Tú no viste nada.', en: 'KING OF THE PEE', enReina: 'QUEEN OF THE PEE', textoEn: 'You saw nothing.'),
  (emoji: '🚿', nombre: 'REY PULCRO', reina: 'REINA PULCRA', texto: 'Para medir qué tanto te bañas. Ya sabemos que poco.', en: 'KING OF CLEAN', enReina: 'QUEEN OF CLEAN', textoEn: 'To track how often you shower. We already know: not much.'),
];

/// Easter egg: más o menos una de cada seis veces que se abre la app aparece un "psst" casi
/// transparente en una esquina al azar. Al tocarlo anuncia una de las próximas apps.
class Secreto extends StatelessWidget {
  Secreto({super.key})
      : _esquina = _azar.nextInt(6) == 0 ? _esquinas[_azar.nextInt(4)] : null,
        _app = _proximas[_azar.nextInt(_proximas.length)];

  static final _azar = math.Random();
  static const _esquinas = [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight];

  final Alignment? _esquina;
  final ({String emoji, String nombre, String reina, String texto, String en, String enReina, String textoEn}) _app;

  void _abrir(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Emoji(_app.emoji, tamano: 120),
              const SizedBox(height: 16),
              Text(tr(segun(_app.nombre, _app.reina), segun(_app.en, _app.enReina)), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              const Rotulo('Coming soon...'),
              const SizedBox(height: 12),
              Text(tr(_app.texto, _app.textoEn), textAlign: TextAlign.center),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ME AGUANTO', 'I CAN WAIT'))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final esquina = _esquina;
    if (esquina == null) return const SizedBox.shrink();
    return Align(
      alignment: esquina,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _abrir(context),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Opacity(
            opacity: .35,
            child: Text('psst… ${_app.emoji}', style: TextStyle(fontSize: 11, color: paleta(context).textoSuave)),
          ),
        ),
      ),
    );
  }
}
