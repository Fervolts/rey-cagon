import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'emoji.dart';
import 'tema.dart';

// Apps que vienen: emoji, nombre y el chiste del anuncio.
const _proximas = [
  (emoji: '🍺', nombre: 'REY MEÓN', texto: 'Tú no viste nada.'),
  (emoji: '🚿', nombre: 'REY PULCRO', texto: 'Para medir qué tanto te bañas. Ya sabemos que poco.'),
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
  final ({String emoji, String nombre, String texto}) _app;

  void _abrir(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Emoji(_app.emoji, tamano: 120),
              const SizedBox(height: 16),
              Text(_app.nombre, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              const Rotulo('Coming soon...'),
              const SizedBox(height: 12),
              Text(_app.texto, textAlign: TextAlign.center),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('ME AGUANTO')),
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
