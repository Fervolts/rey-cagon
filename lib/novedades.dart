import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'animaciones.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'tema.dart';

/// Una línea de novedad: emoji, texto en español y texto en inglés.
typedef Novedad = (String, String, String);

/// Una versión publicada: número, fecha (AAAA-MM-DD) y sus novedades. Solo cosas que se ven jugando.
class VersionNovedades {
  const VersionNovedades(this.version, this.fecha, this.novedades);

  final String version;
  final String fecha;
  final List<Novedad> novedades;
}

/// El historial público, de la más nueva a la más vieja. Al sacar una versión nueva se agrega arriba.
const historialNovedades = <VersionNovedades>[
  VersionNovedades('2.17.0', '2026-11-03', [
    ('👑', 'ABDICAR: cuando ni el Palacio te alcanza, abdica. Vuelves al Rancho, pero ganas Coronas y empiezas una dinastía nueva. Cada Corona sin gastar te da +50% de producción.',
        'ABDICATE: when not even the Palace is enough, abdicate. You go back to the Shack, but you earn Crowns and start a new dynasty. Every unspent Crown gives you +50% production.'),
    ('🏰', 'LA CORTE: gasta tus Coronas en el Bufón, el Heraldo, el Tesorero, el Maestro de obras, el Catador y el Mayordomo real. Lo que compras se queda para siempre.',
        'THE COURT: spend your Crowns on the Jester, the Herald, the Treasurer, the Master builder, the Taster and the Royal butler. What you buy stays forever.'),
    ('🔨', 'El Maestro de obras hace que cada mudanza pida menos jaladas y menos cagadas, así cada reinado va más rápido.',
        'The Master builder makes every move ask for fewer flushes and fewer poops, so every reign goes faster.'),
  ]),
  VersionNovedades('2.16.0', '2026-11-03', [
    ('✨', 'Pantalla más limpia: arriba quedan tu saldo, el ? y el ⋯. Toca el saldo para ver tus Fichas, Ciruelas, el Cofre y los Rollos; en ⋯ están el estilo, el ranking, la foto del baño y la cartera.',
        'A cleaner screen: up top you only see your balance, the ? and the ⋯. Tap the balance to see your Tokens, Plums, the Chest and your Rolls; ⋯ holds style, the leaderboard, the bathroom photo and your wallet.'),
    ('⛓️', 'JALAR abre la Cadena con su Plomería, y la MUDANZA sale cuando ya no cabes en tu casa, con el Llavero adentro.',
        'FLUSH opens the Chain with its Plumbing, and MOVING shows up when you no longer fit in your house, with the Keyring inside.'),
    ('👆', 'Un dedo te enseña dónde tocar la primera vez: la poceta, los cagadores, la primera mejora, JALAR y la MUDANZA.',
        'A finger shows you where to tap the first time: the toilet, the poopers, the first upgrade, FLUSH and MOVING.'),
  ]),
  VersionNovedades('2.15.0', '2026-11-02', [
    ('🏠', 'MUDANZA: cuando ya jalaste bastante la cadena, múdate a una casa más grande. Se reinicia todo, pero ganas Llaves y cada casa produce mucho más que la anterior. Rancho, Casa, Quinta, Mansión y Palacio, y en cada casa tus cagadores cambian de nombre.',
        'MOVING: once you have flushed enough, move to a bigger house. Everything resets, but you earn Keys and every house produces way more than the last one. Shack, House, Villa, Mansion and Palace, and your poopers get new names in every house.'),
    ('🔧', 'PLOMERÍA: lo que compras con Rollos de Oro ahora sube de nivel y se queda entre jaladas hasta que te mudas.',
        'PLUMBING: what you buy with Golden Rolls now levels up and stays between flushes until you move.'),
    ('🔑', 'LLAVERO: gasta tus Llaves en mejoras para todas las casas, como el Mayordomo que compra solo.',
        'KEYRING: spend your Keys on upgrades for every house, like the Butler who buys for you.'),
    ('💩', 'Los edificios ahora se llaman cagadores.', 'Buildings are now called poopers.'),
    ('🎁', 'Regálale un Rollo a tus amigos desde su perfil, uno por día a cada uno: al abrirlo le da 30 minutos de su producción.',
        'Gift your friends a Roll from their profile, one per day each: opening it gives them 30 minutes of their production.'),
    ('⚔️', 'Cagadón con apuesta: al retar puedes apostar 15, 30 o 60 minutos de producción. El que gana cobra el doble; si empatan, cada uno recupera lo suyo.',
        'Poop-Off with a bet: when you challenge someone you can bet 15, 30 or 60 minutes of production. The winner takes double; on a tie, each one gets theirs back.'),
    ('📱', 'Menos avisos: las cagadas de tus amigos llegan juntas, como mucho una cada 90 minutos, y en ajustes ves cuántos avisos te llegaron de cada tipo. El aviso de atasco ahora sale a cualquier hora.',
        'Fewer notifications: your friends\' poops come bundled, at most one every 90 minutes, and settings show how many of each kind you got. The clog alert now comes at any hour.'),
    ('🎓', 'Recorrido por el Imperio: te enseña la poceta, los cagadores, las mejoras, los atascos y la cadena con tus propios números. Sale una vez, también si ya vas avanzado.',
        'Empire tour: it walks you through the toilet, poopers, upgrades, clogs and the chain with your own numbers. It shows up once, even if you are far along.'),
    ('❓', 'Botón "?" arriba: "¿Qué hago ahora?" te dice la mejor jugada del momento y te lleva directo.',
        '"?" button at the top: "What now?" tells you the best move right now and takes you there.'),
    ('🪠', 'Se pueden tapar hasta 3 cagadores a la vez, y mientras más rápido produces, más seguido se tapan. El Robot y el Destapacaños los destapan todos.',
        'Up to 3 poopers can clog at once, and the faster you produce, the more often they clog. The Plunger bot and Drain cleaner unclog all of them.'),
    ('💡', 'Cada alquilable tiene su "?" con lo que hace y cuánto te rinde, y el juego te avisa cuando uno te vendría bien.',
        'Every rental has a "?" showing what it does and how much it gives you, and the game tells you when one would help.'),
    ('📱', 'Arreglado el texto con espacios gigantes en "Mientras no estabas" en algunos Samsung.',
        'Fixed the text with huge gaps in "While you were away" on some Samsung phones.'),
  ]),
  VersionNovedades('2.14.1', '2026-11-02', [
    ('👦', 'Los Primos se ven pujando de verdad: 10 toques por segundo, y cada uno tira su mojón a la taza.',
        'Cousins really push now: 10 taps per second, and each one drops its poop into the bowl.'),
    ('🏆', 'El ranking del Imperio ahora está en la pestaña RANKING: escoge CAGADAS o IMPERIO arriba.',
        'The Empire leaderboard now lives in the LEADERBOARD tab: pick POOPS or EMPIRE at the top.'),
    ('🥵', 'Si pujas más de 20 veces por segundo sale "¡CALMA!": esos toques de más no cuentan.',
        'Push more than 20 times per second and you get "EASY!": those extra taps do not count.'),
    ('🔔', 'El aviso de versión nueva sale aunque tengas la app abierta.', 'The new version notice shows up even with the app open.'),
  ]),
  VersionNovedades('2.14.0', '2026-11-02', [
    ('💬', 'En el Baño ves quién está escribiendo: su avatar se mueve con los puntitos.',
        'In the Bathroom you can see who is typing: their avatar moves with the little dots.'),
    ('📣', 'Las menciones con @ se resaltan. Tócala para ver un resumen de esa persona y toca el resumen para abrir su perfil.',
        'Mentions with @ are highlighted. Tap one to see a quick summary of that person and tap the summary to open their profile.'),
    ('👦', 'Lo que alquilas trabaja a la vista: los Primos pujan, el robot destapa, la cuadrilla compra y una tira te dice cuánto le queda a cada uno.',
        'What you rent works in plain sight: Cousins push, the robot unclogs, the crew buys and a strip shows how long each one has left.'),
    ('🚽', 'La poceta también se puede tapar mientras tienes la app cerrada. Vuelve a destaparla.',
        'The toilet can also clog while the app is closed. Come back and unclog it.'),
    ('✋', 'Los pujos con el dedo cuentan hasta 20 por segundo. Los Primos no entran en ese tope.',
        'Finger pushes count up to 20 per second. Cousins are not part of that limit.'),
    ('📱', 'La app se queda siempre en vertical y la barra de abajo ya no deja un hueco encima de los iconos.',
        'The app always stays upright and the bottom bar no longer leaves a gap above the icons.'),
  ]),
  VersionNovedades('2.13.1', '2026-11-02', [
    ('💸', 'Los alquilables del Imperio tienen su propia sección, Alquiler, y salen más baratos mientras más grande es tu imperio.',
        'Empire rentals have their own section, Rentals, and get cheaper the bigger your empire is.'),
    ('⏳', 'Alquila por x1, x2, x5 o x10 de una vez, o en Indefinido: se renueva solo mientras te alcance y lo apagas cuando quieras.',
        'Rent for x1, x2, x5 or x10 at once, or Indefinite: it renews by itself while you can afford it and you can turn it off anytime.'),
    ('🔥', 'Alquilar lo mismo seguido lo encarece (lo ves en la fila: x1,6 por uso) y se enfría solo con las horas.',
        'Renting the same thing again and again makes it pricier (the row shows it: x1.6 from use) and it cools down over the hours.'),
    ('👦', 'Puedes tener varios Primos pujadores a la vez, y lo que alquilas se ve en tu baño.',
        'You can have several Pushing cousins at once, and what you rent shows up in your bathroom.'),
    ('🌀', 'El efecto de tu tipo de cagada se cansa: el mismo tipo dos veces seguidas rinde la mitad y desde la tercera no da nada. Cambia de tipo o deja pasar 24 horas.',
        'Your poop type effect gets tired: the same type twice in a row gives half and from the third time on it gives nothing. Switch types or let 24 hours pass.'),
  ]),
  VersionNovedades('2.13.0', '2026-11-02', [
    ('🎨', 'Tienda de estilo en el Imperio: temas para toda la app, efectos al apretar CAGUÉ y movimientos para tu avatar. Lo que compras se queda aunque jales la cadena.',
        'Style shop in the Empire: themes for the whole app, effects when you press CAGUÉ and moves for your avatar. What you buy stays even when you pull the chain.'),
    ('🏆', 'Ranking del Imperio global y entre amigos, por mojonólares o por Rollos de Oro. Desliza hacia abajo para actualizarlo.',
        'Global and friends Empire ranking, by Poopbucks or by Golden Rolls. Pull down to refresh it.'),
    ('👤', 'Tu Imperio sale en tu perfil: mojonólares, rollos y jaladas.', 'Your Empire shows on your profile: Poopbucks, rolls and pulls.'),
    ('🚽', '19 de noviembre, Día Mundial del Retrete: todo x3 en el Imperio y un logro que solo sale ese día.',
        'November 19, World Toilet Day: everything x3 in the Empire and an achievement you can only get that day.'),
    ('🎄', 'En diciembre: hallaca dorada en el Imperio y gorro de Santa para quien cague en Navidad.',
        'In December: golden hallaca in the Empire and a Santa hat for whoever poops at Christmas.'),
  ]),
  VersionNovedades('2.12.3', '2026-11-02', [
    ('💰', 'Precios del Imperio rebalanceados: el juego dura más y ya no te quedas trancado esperando.',
        'Imperio prices rebalanced: the game lasts longer and you no longer get stuck waiting.'),
    ('🔒', 'Candados más justos: cada día que reclamas tu racha suma media cagada, puedes pagar con MJ hasta la mitad de lo que pide, y cuentan hasta 3 cagadas por día.',
        'Fairer locks: every day you claim your streak adds half a poop, you can pay up to half of what a lock asks with MJ, and up to 3 poops a day count.'),
    ('🎁', 'Regalos para cuando vuelves después de unos días y un empujón si te quedaste atrás.',
        'Gifts for when you come back after a few days, and a boost if you fell behind.'),
    ('🚽', 'Avisos nuevos: poceta llena, cadena lista para jalar, mejora que ya te alcanza.',
        'New alerts: full toilet, chain ready to pull, upgrade you can now afford.'),
    ('🏆', 'Ranking del Imperio con la gente que sigues y tres logros ocultos nuevos.',
        'Imperio ranking with the people you follow and three new hidden achievements.'),
    ('🚛', 'El camión ya no tapa las arepas del baño.', 'The truck no longer covers the arepas in the bathroom.'),
    ('💡', 'Esta pantalla de Novedades.', 'This What\'s new screen.'),
  ]),
  VersionNovedades('2.12.2', '2026-11-01', [
    ('🚽', 'Los atascos ahora se ven en todos los cagadores del Imperio.', 'Clogs now show up in every Imperio pooper.'),
    ('💰', 'El saldo en las tiendas se queda fijo y ya no salta mientras compras.', 'Your balance in the shops stays put instead of jumping while you buy.'),
    ('🏆', 'Premios exclusivos para quienes juegan el Imperio.', 'Exclusive prizes for people playing the Imperio.'),
    ('🏭', 'Cagadores animados en el baño y dos logros bien escondidos.', 'Animated poopers in the bathroom and two well-hidden achievements.'),
  ]),
  VersionNovedades('2.12.1', '2026-11-01', [
    ('🚽', 'Poceta tapada: si abusas de cagar y deshacer, la poceta se tapa un rato.', 'Clogged toilet: if you abuse poop and undo, the toilet clogs for a while.'),
    ('🔥', 'Avisos de racha para que no se te pierda ni un día.', 'Streak alerts so you never lose a day.'),
    ('🎁', 'El Cofre del Trono se entiende mucho mejor.', 'The Throne Chest is much easier to understand.'),
  ]),
  VersionNovedades('2.12.0', '2026-11-01', [
    ('👑', 'La pantalla TRONO cobra vida y trae cinco logros secretos.', 'The THRONE screen comes alive and brings five secret achievements.'),
    ('🛁', 'El baño del Imperio quedó reacomodado, con bidet de piso y objetos que reaccionan.', 'The Imperio bathroom was rearranged, with a floor bidet and objects that react.'),
    ('🏆', 'Seis logros ocultos nuevos en el Imperio.', 'Six new hidden achievements in the Imperio.'),
    ('💨', 'Avisos para ganadores y cierres de periodo, y más ajustes en las notificaciones.', 'Alerts for winners and period closings, plus more notification settings.'),
  ]),
  VersionNovedades('2.1.3', '2026-11-01', [
    ('🛁', 'El baño del Imperio ahora ocupa toda la pantalla.', 'The Imperio bathroom now fills the whole screen.'),
    ('🏗️', 'Cajón de cagadores para ver y comprar todo desde un solo lugar.', 'A poopers drawer to see and buy everything in one place.'),
    ('💩', 'Puedes mandar la foto de tu baño al chat para presumir.', 'You can send a photo of your bathroom to the chat to show off.'),
    ('🪙', 'Maná, Rollos, Fichas, Cofre y Congelador de racha: objetos y monedas nuevas.', 'Mana, Rolls, Chips, Chest and Streak Freezer: new items and coins.'),
  ]),
  VersionNovedades('2.1.2', '2026-10-31', [
    ('🛁', 'TU BAÑO: la poceta vive en un baño viejo que vas arreglando.', 'YOUR BATHROOM: the toilet lives in an old bathroom you slowly fix up.'),
    ('🫐', 'Ciruelas, racha de 30 días y una tarjeta de racha épica.', 'Plums, a 30-day streak and an epic streak card.'),
    ('🧻', 'Tienda unificada y objetos que se compran con Ciruelas.', 'One unified shop and items you buy with Plums.'),
    ('🚽', 'El inodoro extra pasa a ser el bidet.', 'The extra toilet is now the bidet.'),
    ('✨', 'Presumir tiene una cara distinta cada vez y se comparte más liviano.', 'Showing off has a different look every time and shares lighter.'),
  ]),
  VersionNovedades('2.1.1', '2026-10-31', [
    ('🏆', 'Vitrina de premios con repisas, y los logros del Imperio viven dentro.', 'Prize cabinet with shelves, and the Imperio achievements live inside.'),
    ('🚽', 'Jala la cadena de la poceta cuando quieras.', 'Pull the toilet chain whenever you want.'),
    ('💰', 'Icono de billete para la moneda y precios de mejoras más separados.', 'A banknote icon for the currency and upgrade prices spaced further apart.'),
    ('🔧', 'Ya no se pisa tu partida si juegas en dos teléfonos.', 'Your save no longer gets overwritten if you play on two phones.'),
  ]),
  VersionNovedades('2.0.0', '2026-10-31', [
    ('🕹️', 'Llega el Imperio Cagón: un juego de clics para construir tu imperio de mojones.', 'The Imperio Cagón arrives: a clicker game to build your poop empire.'),
    ('💰', 'Gana mojonólares (MJ) y compra cagadores y mejoras.', 'Earn mojonólares (MJ) and buy poopers and upgrades.'),
    ('🚽', 'Poceta mascota y mejoras por cagador.', 'A pet toilet and upgrades per pooper.'),
    ('💩', 'Nueva pestaña IMPERIO en la barra de abajo.', 'New IMPERIO tab in the bottom bar.'),
    ('🔥', 'Reconexión del chat al volver a la app y ver quién reaccionó.', 'The chat reconnects when you return to the app, and you can see who reacted.'),
  ]),
  VersionNovedades('1.14.2', '2026-10-30', [
    ('🎨', 'Teclado de emojis propio en el chat, en la sala y en los hilos.', 'Our own emoji keyboard in the chat, the room and threads.'),
    ('💩', 'Avisos de respuestas en hilos y avisos por día.', 'Alerts for thread replies and alerts per day.'),
  ]),
  VersionNovedades('1.14.0', '2026-10-30', [
    ('💩', 'Burbujas estilo WhatsApp en el chat, con reacciones y respuestas en hilo.', 'WhatsApp-style bubbles in the chat, with reactions and thread replies.'),
    ('🔥', 'HEXA POOP: seis cagadas en un día y alerta nuclear para todos.', 'HEXA POOP: six poops in one day and a nuclear alert for everyone.'),
    ('🏆', 'Trece logros nuevos, logros secretos y vitrina por grupos.', 'Thirteen new achievements, secret achievements and a cabinet by groups.'),
    ('🌙', 'Ranking secreto como modo del ranking y esquina doblada en YO.', 'Secret ranking as a ranking mode and a folded corner in YO.'),
    ('✨', 'Widgets con vida: aparecen, cuentan y rebotan en trono, ranking, perfil y calendario.', 'Lively widgets: they appear, count up and bounce in throne, ranking, profile and calendar.'),
  ]),
  VersionNovedades('1.12.0', '2026-10-28', [
    ('🚽', 'Animación del mojón al inodoro cada vez que cagas.', 'Animation of the poop going into the toilet every time you go.'),
    ('📱', 'Tema claro y oscuro.', 'Light and dark theme.'),
    ('🥈', 'Podio en el ranking y contador de cierre del periodo.', 'Podium in the ranking and a countdown to the period close.'),
    ('💩', 'Parte de cagada: cuéntanos tipo y peso del mojón.', 'Poop report: tell us the type and weight of your poop.'),
    ('👑', 'Pestaña YO con tu perfil y racha que puedes compartir.', 'YO tab with your profile and a streak you can share.'),
  ]),
];

/// Compara "2.12.3" con "2.1.3" número a número. Negativo si a < b.
int compararVersiones(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Después de una actualización, muestra un aviso corto con lo nuevo. En la primera instalación no muestra nada.
Future<void> quizasMostrarNovedades(BuildContext context) async {
  try {
    final actual = (await PackageInfo.fromPlatform()).version;
    final prefs = await SharedPreferences.getInstance();
    final guardada = prefs.getString('novedades_vistas');
    await prefs.setString('novedades_vistas', actual);
    if (guardada == null || compararVersiones(actual, guardada) <= 0) return;
    final entrada = historialNovedades.where((v) => v.version == actual).firstOrNull;
    if (entrada == null) return;
    // Un respiro para no pegarse a otros avisos que acaban de cerrarse.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!context.mounted) return;
    final verTodo = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = paleta(ctx);
        return AlertDialog(
          backgroundColor: p.tarjeta,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: p.bordeFuerte)),
          title: Text(tr('Novedades de la ${entrada.version}', "What's new in ${entrada.version}")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final n in entrada.novedades.take(3)) _FilaNovedad(n)],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ver todo', 'See all'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Listo', 'Done'))),
          ],
        );
      },
    );
    if (verTodo == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaNovedades()));
    }
  } catch (_) {}
}

class _FilaNovedad extends StatelessWidget {
  const _FilaNovedad(this.n);

  final Novedad n;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Emoji(n.$1, tamano: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(tr(n.$2, n.$3), style: const TextStyle(height: 1.3))),
          ],
        ),
      );
}

/// Pantalla pública con todo el historial de versiones.
class PantallaNovedades extends StatelessWidget {
  const PantallaNovedades({super.key});

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final anima = movimiento(context) == Movimiento.completo;
    return Scaffold(
      appBar: AppBar(title: Text(tr('NOVEDADES', "WHAT'S NEW"))),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: historialNovedades.length,
        itemBuilder: (context, i) {
          final v = historialNovedades[i];
          final tarjeta = Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.tarjeta,
              borderRadius: BorderRadius.circular(radio),
              border: Border.all(color: i == 0 ? acento : p.borde),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('v${v.version}', style: numeros(context, tamano: 20, weight: FontWeight.w800)),
                    if (i == 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: acento, borderRadius: BorderRadius.circular(radio)),
                        child: Text(tr('NUEVO', 'NEW'),
                            style: numeros(context, tamano: 10, weight: FontWeight.w800, color: acentoTexto)),
                      ),
                    ],
                    const Spacer(),
                    Rotulo(v.fecha),
                  ],
                ),
                const SizedBox(height: 6),
                for (final n in v.novedades) _FilaNovedad(n),
              ],
            ),
          );
          if (!anima || i > 5) return tarjeta;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 250 + i * 60),
            curve: Curves.easeOut,
            builder: (_, t, hijo) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: hijo)),
            child: tarjeta,
          );
        },
      ),
    );
  }
}
