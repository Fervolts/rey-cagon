import 'package:flutter/material.dart';

import '../idioma.dart';
import '../tema.dart';

// La tarjeta de decisión de cada capa de la escalera (Cadena 🚽, Mudanza 🏠): qué dejas, qué recibes y, debajo, lo
// que falta y el botón. Cuadrada, borde de 1px y el acento cuando ya se puede.

/// DEJAS / RECIBES y lo que venga debajo ([hijos]: barras, aviso, botón).
class TarjetaDecision extends StatelessWidget {
  const TarjetaDecision({super.key, required this.dejas, required this.recibes, required this.lista, this.cabeza, this.hijos = const []});

  final String dejas, recibes;

  /// Ya se puede: borde del acento.
  final bool lista;

  /// Encima de DEJAS (la casa en la Mudanza).
  final Widget? cabeza;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: p.tarjeta, border: Border.all(color: lista ? acento : p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cabeza case final c?) ...[c, const SizedBox(height: 10)],
          _linea(context, tr('DEJAS', 'YOU LEAVE'), dejas, p.textoSuave),
          const SizedBox(height: 6),
          _linea(context, tr('RECIBES', 'YOU GET'), recibes, p.texto),
          ...hijos,
        ],
      ),
    );
  }

  Widget _linea(BuildContext context, String rotulo, String texto, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(rotulo, style: numeros(context, tamano: 11, weight: FontWeight.w900, color: color).copyWith(letterSpacing: 1)),
          ),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
        ],
      );
}
