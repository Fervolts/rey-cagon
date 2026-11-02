import 'package:flutter/material.dart';

import '../actualizar.dart' show abrirActualizacion;
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';

/// Tarjeta que tapa la pestaña IMPERIO cuando el build instalado es menor que el flag `version_minima`
/// (o el servidor respondió `version_vieja`): con una versión vieja el progreso ya no se guarda en la nube.
class TarjetaVersionMinima extends StatelessWidget {
  const TarjetaVersionMinima({super.key});

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Emoji('🚽', tamano: 48),
          const SizedBox(height: 12),
          Text(tr('Actualiza para seguir jugando', 'Update to keep playing'),
              textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: p.texto)),
          const SizedBox(height: 8),
          Text(
              tr('Esta versión ya no guarda tu Imperio en la nube. Actualiza y sigues donde ibas.',
                  'This version no longer saves your Empire to the cloud. Update and pick up where you left off.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textoSuave)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => abrirActualizacion(context),
              child: Text(tr('ACTUALIZAR', 'UPDATE'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
            ),
          ),
        ],
      ),
    );
  }
}
