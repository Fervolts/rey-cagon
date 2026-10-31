import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'telemetria.dart';

class _Minijuego {
  const _Minijuego(this.id, this.emoji, this.es, this.en, this.lineaEs, this.lineaEn);

  /// Va en el evento `minijuego_toca`.
  final String id;
  final String emoji, es, en, lineaEs, lineaEn;
}

const _juegos = [
  _Minijuego('tuberia', '🚰', 'Tubería Express', 'Pipe Express', 'El mojón vuela por el desagüe esquivando codos.', 'The poop flies down the drain, dodging bends.'),
  _Minijuego('blanco', '🎯', 'Al blanco', 'Bullseye', 'Lanza el mojón al inodoro con ángulo y fuerza.', 'Throw the poop into the toilet with angle and power.'),
  _Minijuego('corre', '🏃', 'Corre al baño', 'Run to the Bathroom', 'Llega antes de que se salga. Esquiva colas.', "Get there before it's too late. Dodge the lines."),
  _Minijuego('destapa', '🪠', 'Destapa', 'Unclog', 'Toca al compás y destapa inodoros.', 'Tap to the beat and unclog toilets.'),
  _Minijuego('memoria', '🃏', 'Memoria del rollo', 'Roll Memory', 'Parejas de cartas con los emojis de la app.', 'Match pairs of cards with the app emojis.'),
  _Minijuego('simon', '🎹', 'Simón del pujo', 'Push Simon', 'Repite secuencias de pujos cortos, largos y épicos.', 'Repeat sequences of short, long and epic pushes.'),
  _Minijuego('trivia', '❓', 'Trivia de cagología', 'Poop Trivia', 'Datos reales y raros del baño. Ranking semanal.', 'Real and weird bathroom facts. Weekly ranking.'),
  _Minijuego('pesca', '🎣', 'Pesca en la cloaca', 'Sewer Fishing', 'Pesca cosas raras y arma tu colección.', 'Fish up weird stuff and build your collection.'),
  _Minijuego('cucarachas', '🪳', 'Carrera de cucarachas', 'Cockroach Race', 'Apuesta MJ con tus amigos a tu cucaracha.', 'Bet MJ with friends on your cockroach.'),
  _Minijuego('duelo', '⚔️', 'Duelo de pujos', 'Push Duel', '1 contra 1: quién puja más en 10 segundos.', '1v1: who pushes more in 10 seconds.'),
  _Minijuego('constructor_bano', '🛁', 'Constructor de baño', 'Bathroom Builder', 'Decora tu baño con los muebles que compres.', 'Decorate your bathroom with furniture you buy.'),
];

/// Sala de juegos: todo "PRÓXIMAMENTE" en la fase 1.
class PantallaSala extends StatelessWidget {
  const PantallaSala({super.key});

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('SALA DE JUEGOS', 'GAME ROOM'))),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 190,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _juegos.length,
        itemBuilder: (context, i) {
          final j = _juegos[i];
          // Solo se anota el interés: los juegos todavía no existen.
          final tarjeta = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.tarjeta,
              border: Border.all(color: p.borde),
              borderRadius: BorderRadius.circular(radio),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Emoji(j.emoji, tamano: 32),
                const SizedBox(height: 8),
                Text(tr(j.es, j.en), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    tr(j.lineaEs, j.lineaEn),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textoSuave),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.primario),
                    borderRadius: BorderRadius.circular(radio),
                  ),
                  child: Text(
                    tr('PRÓXIMAMENTE', 'COMING SOON'),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.primario),
                  ),
                ),
              ],
            ),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Telemetria.instancia.registrar('minijuego_toca', {'id': j.id}),
            child: tarjeta,
          );
        },
      ),
    );
  }
}
