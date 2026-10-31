import 'package:flutter/material.dart';

import '../emoji.dart';
import '../genero.dart';
import '../idioma.dart';
import '../tema.dart';
import 'formato.dart';

/// Bienvenida a quien ya cagaba antes del Imperio: multiplicador, Fichas heredadas e insignia Fundador.
Future<void> mostrarBienvenidaVeterano(
  BuildContext context, {
  required int cagadas,
  required double multiplicador,
  required int fichas,
  required bool fundador,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final p = paleta(context);
      final x = formatoMj(multiplicador, ingles: enIngles);
      final veces = tr(cagadas == 1 ? '1 vez' : '$cagadas veces', cagadas == 1 ? 'once' : '$cagadas times');
      final fichasTxt = tr(fichas == 1 ? '1 Ficha' : '$fichas Fichas', fichas == 1 ? '1 Token' : '$fichas Tokens');
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: p.bordeFuerte)),
        backgroundColor: p.tarjeta,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Emoji('👑', tamano: 72),
              const SizedBox(height: 12),
              Text(
                tr('${segun('BIENVENIDO', 'BIENVENIDA')} AL IMPERIO', 'WELCOME TO THE EMPIRE'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.6, color: p.texto),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Ya cagaste $veces antes del Imperio. Tu trono te espera: x$x de producción y $fichasTxt.',
                  "You pooped $veces before the Empire. Your throne awaits: x$x production and $fichasTxt.",
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: p.texto),
              ),
              if (fundador) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: p.primario), borderRadius: BorderRadius.circular(radio)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Emoji('🏛️', tamano: 24),
                      const SizedBox(width: 8),
                      Text(
                        tr('INSIGNIA FUNDADOR', 'FOUNDER BADGE'),
                        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.texto),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('¡A PUJAR!', 'LET\'S PUSH!'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.8)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
