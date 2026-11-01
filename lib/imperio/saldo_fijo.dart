// Saldo fijo arriba de las tiendas: MJ, Ciruelas, Fichas y Rollos siempre a la vista mientras se baja por la lista.
import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'control.dart';
import 'formato.dart';
import 'moneda_app.dart';

/// Franja con lo que tienes. Va fuera del scroll de la hoja, así no se va al bajar. Se redibuja con el control.
class SaldoFijo extends StatelessWidget {
  const SaldoFijo({super.key, required this.control});

  final ControlImperio control;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    Widget chip(String emoji, String n, Key llave) => Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Emoji(emoji, tamano: 16),
            const SizedBox(width: 3),
            Text(n, key: llave, style: numeros(context, tamano: 14, weight: FontWeight.w900)),
          ]),
        );
    return Container(
      key: const Key('saldo_fijo'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(color: p.fondo, border: Border(bottom: BorderSide(color: p.borde))),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: tr('Tienes', 'You have'),
              child: montoMj(formatoMj(im.saldo, ingles: enIngles), numeros(context, tamano: 22, weight: FontWeight.w900)),
            ),
          ),
          chip('🫐', '${im.ciruelas}', const Key('fijo_ciruelas')),
          chip('🎟️', '${im.fichas}', const Key('fijo_fichas')),
          if (im.partida.rollos > 0) chip('🧻', formatoMj(im.partida.rollos.toDouble(), ingles: enIngles), const Key('fijo_rollos')),
        ],
      ),
    );
  }
}
