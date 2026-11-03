// El botón "?" del Imperio y la hoja "¿Qué hago ahora?" con la próxima jugada en vivo y su IR. La cuenta de la próxima
// jugada está en que_hago.dart (pura, sin widgets). La guía de dedos 👆 está en dedo.dart.

import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'control.dart';
import 'moneda_app.dart';
import 'que_hago.dart';

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
      DestinoQueHago.edificios => tr('IR A CAGADORES', 'GO TO POOPERS'),
      DestinoQueHago.tienda => tr('IR A LA TIENDA', 'GO TO THE SHOP'),
      DestinoQueHago.jalar => tr('IR A LA CADENA', 'GO TO THE CHAIN'),
      DestinoQueHago.mudanza => tr('IR A LA MUDANZA', 'GO TO MOVING'),
      DestinoQueHago.abdicar => tr('IR A ABDICAR', 'GO TO ABDICATE'),
      DestinoQueHago.cerrar => tr('VAMOS', "LET'S GO"),
    };

/// Hoja "¿Qué hago ahora?": la próxima jugada en vivo, con IR (cierra la hoja y llama a [alIr]). [cadenaLista]: el
/// botón JALAR está encendido. Anota `imperio_que_hago`.
Future<void> abrirQueHago(BuildContext context, ControlImperio control,
    {required bool Function() cadenaLista, required void Function(Sugerencia) alIr}) {
  final moneda = monedaActual().abreviatura;
  Sugerencia calcular() => queHagoAhora(control.imperio, control.ahora,
      cadenaLista: cadenaLista(),
      mudanzaLista: control.mudanzaDisponible && control.imperio.puedeMudarse(control.cagadasCasa),
      abdicarLista: control.abdicarDisponible && control.imperio.puedeAbdicar(control.cagadasReinado),
      moneda: moneda);
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
              ],
            ),
          ),
        );
      },
    ),
  );
}
