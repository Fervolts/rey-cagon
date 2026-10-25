import 'package:flutter/material.dart';

import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'tema.dart';

/// Peso del mojón (cagadas.peso 1-5). De chiste, como el tipo: nadie pesa nada de verdad.
Map<int, (String, String, String)> get pesos => {
  1: ('🪶', tr('Pluma', 'Feather'), tr('Ni se sintió. ¿Seguro que cagaste?', 'Barely there. Are you sure you went?')),
  2: ('🍌', tr('Cambur', 'Banana'), tr('Lo normal de un martes cualquiera', 'Your average Tuesday')),
  3: ('🧱', tr('Ladrillo', 'Brick'), tr('Se escuchó el golpe contra el agua', 'You heard the splash')),
  4: ('⚓', tr('Ancla', 'Anchor'), tr('Te levantaste un kilo más liviano', 'You got up a kilo lighter')),
  5: ('🐋', tr('Ballena', 'Whale'), tr('Hay que llamar al plomero', 'Call the plumber')),
};

/// La hoja de PESO DEL MOJÓN después de "¿Qué salió?". null si no quiere decir.
Future<int?> preguntarPeso(BuildContext context) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final p = paleta(context);
        return ListView(
          shrinkWrap: true,
          padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 0, 16, 16)),
          children: [
            Text(tr('PESO DEL MOJÓN', 'POOP WEIGHT'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr(segun('¿Cuánto soltaste en esta? Sé honesto, rey: la báscula del baño no miente.',
                      '¿Cuánto soltaste en esta? Sé honesta, reina: la báscula del baño no miente.'),
                  'How much did you drop this time? Be honest, your majesty: the bathroom scale never lies.'),
              style: TextStyle(color: p.textoSuave),
            ),
            const SizedBox(height: 12),
            for (final e in pesos.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: p.tarjeta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radio),
                    side: BorderSide(color: p.borde),
                  ),
                  child: ListTile(
                    leading: Emoji(e.value.$1, tamano: 36),
                    title: Text(e.value.$2.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                    subtitle: Text(e.value.$3),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (var i = 0; i < 5; i++) Icon(Icons.square, size: 8, color: i < e.key ? acento : p.borde)],
                    ),
                    onTap: () => Navigator.pop(context, e.key),
                  ),
                ),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Prefiero no decir', 'Rather not say'))),
          ],
        );
      },
    );
