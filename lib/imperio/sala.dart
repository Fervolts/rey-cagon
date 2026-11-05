import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'control.dart';
import 'minijuegos/datos.dart';
import 'minijuegos/estadisticas.dart' show juegosAbiertos;
import 'minijuegos/marco.dart';
import 'telemetria.dart';

class _Minijuego {
  const _Minijuego(this.id, this.emoji, this.es, this.en, this.lineaEs, this.lineaEn);

  /// Va en el evento `minijuego_toca`.
  final String id;
  final String emoji, es, en, lineaEs, lineaEn;
}

const _juegos = [
  _Minijuego('tuberia', '🚰', 'Tubería Express', 'Pipe Express', 'Surfea el lodo con un dedo: toca para saltar, mantén para bajar.', 'Surf the mud with one finger: tap to jump, hold to go down.'),
  _Minijuego('blanco', '🎯', 'Al blanco', 'Bullseye', 'Lanza el mojón al inodoro con ángulo y fuerza.', 'Throw the poop into the toilet with angle and power.'),
  _Minijuego('corre', '🏃', 'Corre al baño', 'Run to the Bathroom', 'Llega antes de que se salga. Esquiva colas.', "Get there before it's too late. Dodge the lines."),
  _Minijuego('destapa', '🪠', 'Destapa', 'Unclog', 'Medio tiempo en el estadio: destapa antes de que se desborden.', 'Stadium halftime: unclog before they overflow.'),
  _Minijuego('memoria', '👑', 'Fusión real', 'Royal Merge', 'Junta mojones iguales en la poceta hasta hacer un Rey.', 'Merge matching poos in the bowl until you make a King.'),
  _Minijuego('simon', '🎹', 'Simón del pujo', 'Push Simon', 'Repite secuencias de pujos cortos, largos y épicos.', 'Repeat sequences of short, long and epic pushes.'),
  _Minijuego('trivia', '❓', 'Trivia de cagología', 'Poop Trivia', 'Datos reales y raros del baño. Ranking semanal.', 'Real and weird bathroom facts. Weekly ranking.'),
  _Minijuego('pesca', '🎣', 'Pesca en la cloaca', 'Sewer Fishing', 'Pesca cosas raras y arma tu colección.', 'Fish up weird stuff and build your collection.'),
  _Minijuego('cucarachas', '🪳', 'Carrera de cucarachas', 'Cockroach Race', 'Apuesta MJ con tus amigos a tu cucaracha.', 'Bet MJ with friends on your cockroach.'),
  _Minijuego('duelo', '⚔️', 'Duelo de pujos', 'Push Duel', '1 contra 1: quién puja más en 10 segundos.', '1v1: who pushes more in 10 seconds.'),
  _Minijuego('constructor_bano', '🛁', 'Constructor de baño', 'Bathroom Builder', 'Decora tu baño con los muebles que compres.', 'Decorate your bathroom with furniture you buy.'),
];

/// Lo que cabe en la tarjeta: cuánto puede dar hoy.
String lineaTarjeta(ResumenMinijuegos? r) {
  if (r == null) return tr('Hasta $minutosMaxDefecto min por partida', 'Up to $minutosMaxDefecto min per game');
  if (!r.activo) return tr('Premios en pausa', 'Prizes paused');
  final p = r.puedeDarHoy;
  if (p <= 0) return tr('Hoy: sin más premio', 'Today: no more prize');
  return tr('Hoy: hasta $p min', 'Today: up to $p min');
}

/// Sala de juegos: tres juegos abiertos (Tubería Express, Destapa, Fusión real) y el resto "PRÓXIMAMENTE".
/// [control] es opcional: si no llega se usa el del Imperio abierto ([ControlImperio.vivo]).
class PantallaSala extends StatelessWidget {
  const PantallaSala({super.key, this.control});
  final ControlImperio? control;

  ControlImperio? get _c => control ?? ControlImperio.vivo;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: Text(tr('SALA DE JUEGOS', 'GAME ROOM'))),
      body: ListenableBuilder(
        listenable: c ?? ValueNotifier(0),
        builder: (context, _) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 200,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _juegos.length,
          itemBuilder: (context, i) {
            final j = _juegos[i];
            final abierto = juegosAbiertos.contains(j.id);
            final etiqueta = abierto
                ? lineaTarjeta(c?.minijuegos)
                : tr('PRÓXIMAMENTE', 'COMING SOON');
            final tarjeta = Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.tarjeta,
                border: Border.all(color: abierto ? p.acento : p.borde),
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
                    key: Key(abierto ? 'sala_abierto_${j.id}' : 'sala_proximo_${j.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: abierto ? p.acento : p.primario),
                      borderRadius: BorderRadius.circular(radio),
                    ),
                    child: Text(
                      etiqueta,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: abierto ? 0 : 0.6, color: abierto ? p.texto : p.primario),
                    ),
                  ),
                ],
              ),
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Telemetria.instancia.registrar('minijuego_toca', {'id': j.id});
                if (abierto) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaMinijuego(juego: j.id, control: c)));
                }
              },
              child: tarjeta,
            );
          },
        ),
      ),
    );
  }
}
