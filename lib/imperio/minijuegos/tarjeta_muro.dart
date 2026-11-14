import 'package:flutter/material.dart';

import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import '../control.dart';
import '../formato.dart';
import 'estadisticas.dart';
import 'marco.dart';

/// Récord de un minijuego pegado en el muro. Quien lo ve puede jugar para ganarle.
class TarjetaMinijuego extends StatelessWidget {
  const TarjetaMinijuego(this.t, {super.key, this.mia = false});

  final Map<String, dynamic> t;

  /// La pegué yo: el botón dice solo JUGAR y el puesto es "entre tus amigos".
  final bool mia;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final juego = '${t['juego'] ?? ''}';
    final d = juegosAbiertosDatos[juego];
    final puntos = (t['puntos'] as num?)?.toInt() ?? 0;
    final puesto = (t['puesto'] as num?)?.toInt();
    final abierto = d != null && juegosAbiertos.contains(juego);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Emoji(d?.emoji ?? '🎮', tamano: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text((d == null ? tr('Minijuego', 'Minigame') : tr(d.es, d.en)).toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.texto)),
          ),
          const SizedBox(width: 10),
          Text(tr('NUEVO RÉCORD', 'NEW RECORD'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: p.acento)),
        ]),
        const SizedBox(height: 6),
        Text('${conMiles(puntos, ingles: enIngles)} pts',
            key: const Key('tarjeta_minijuego_puntos'), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: p.texto)),
        if (puesto != null)
          Text(
            mia ? tr('#$puesto entre tus amigos', '#$puesto among your friends') : tr('#$puesto entre sus amigos', '#$puesto among their friends'),
            key: const Key('tarjeta_minijuego_puesto'),
            style: TextStyle(color: p.textoSuave),
          ),
        if (abierto) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('tarjeta_minijuego_jugar'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.play_arrow),
            label: Text(mia ? tr('JUGAR', 'PLAY') : tr('JUGAR Y GANARLE', 'PLAY AND BEAT IT')),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => PantallaMinijuego(juego: juego, control: ControlImperio.vivo))),
          ),
        ],
      ]),
    );
  }
}
