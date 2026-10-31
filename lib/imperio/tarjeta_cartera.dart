import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'fila.dart' show textoEnUnaLinea;
import 'formato.dart';
import 'moneda_app.dart';

double _num(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : 0;

/// La tarjeta "estado de cuenta" del chat. Los números los pone el servidor (`validar_mensaje`, rama 'cartera')
/// desde la fila `imperio` del usuario: saldo, mps, pujo, mj_total, jaladas y rollos.
/// Ningún número se parte: si no cabe, se encoge.
class TarjetaCartera extends StatelessWidget {
  const TarjetaCartera(this.t, {super.key});

  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final moneda = monedaActual().abreviatura;
    String mj(Object? v) => formatoMj(_num(v), ingles: enIngles);
    final rollos = _num(t['rollos']);
    final suave = numeros(context, tamano: 13, color: p.textoSuave);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: acento, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: Row(children: [
        const Emoji('💰', tamano: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ESTADO DE CUENTA', 'ACCOUNT STATEMENT'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            textoEnUnaLinea('${mj(t['saldo'])} $moneda', numeros(context, tamano: 24, weight: FontWeight.w900)),
            textoEnUnaLinea('${mj(t['mps'])} /s · ${mj(t['pujo'])} /pujo', suave),
            if (rollos > 0)
              Row(children: [
                const Emoji('🧻', tamano: 14),
                const SizedBox(width: 4),
                Flexible(child: textoEnUnaLinea(tr('${mj(rollos)} Rollos de Oro', '${mj(rollos)} Golden Rolls'), suave)),
              ]),
          ]),
        ),
      ]),
    );
  }
}
