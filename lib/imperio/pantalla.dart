import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import 'sala.dart';

/// Provisional: la pantalla real del Imperio la reemplaza.
class PantallaImperio extends StatefulWidget {
  const PantallaImperio({super.key});

  @override
  State<PantallaImperio> createState() => _PantallaImperioState();
}

class _PantallaImperioState extends State<PantallaImperio> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Emoji('💩', tamano: 72),
            const SizedBox(height: 12),
            Text(tr('IMPERIO', 'EMPIRE'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaSala())),
              child: Text(tr('SALA DE JUEGOS', 'GAME ROOM')),
            ),
          ],
        ),
      ),
    );
  }
}
