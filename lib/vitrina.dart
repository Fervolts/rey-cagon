import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'calendario.dart' show meses;
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'main.dart' show db;
import 'racha.dart';
import 'tema.dart';
import 'tipos.dart';

/// El título que se gana con el total histórico.
String tituloPorTotal(int total) => switch (total) {
      < 10 => tr('Aprendiz del trono', 'Throne apprentice'),
      < 50 => tr(segun('Cagón de confianza', 'Cagona de confianza'), 'Trusted pooper'),
      < 200 => tr(segun('Rey del barrio', 'Reina del barrio'), segun('King of the block', 'Queen of the block')),
      < 500 => tr(segun('Rey indiscutible del trono', 'Reina indiscutible del trono'),
          segun('Undisputed king of the throne', 'Undisputed queen of the throne')),
      _ => tr(segun('Emperador del trono', 'Emperatriz del trono'), segun('Emperor of the throne', 'Empress of the throne')),
    };

const _hitos = [10, 25, 50, 100, 200, 365, 500, 1000];

/// Un trofeo de la vitrina. [ganado] decide si se ve o sale con candado.
typedef Trofeo = ({String emoji, String nombre, String detalle, bool ganado});

/// Las cagadas propias en hora local, para la vitrina y el mapa del mes.
Future<List<({DateTime cuando, int? tipo, int? peso})>> cagadasPropias(String uid) async {
  final filas = await db.from('cagadas').select('created_at, tipo, peso').eq('user_id', uid).order('created_at', ascending: false);
  return [
    for (final f in filas)
      (cuando: DateTime.parse(f['created_at']).toLocal(), tipo: f['tipo'] as int?, peso: f['peso'] as int?),
  ];
}

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Los nueve trofeos a partir de las cagadas, el total, las victorias y el tipo favorito.
List<Trofeo> trofeos({
  required List<({DateTime cuando, int? tipo, int? peso})> cagadas,
  required int total,
  required int victorias,
  required int? favorito,
}) {
  final porDia = <DateTime, int>{};
  for (final c in cagadas) {
    porDia.update(_dia(c.cuando), (n) => n + 1, ifAbsent: () => 1);
  }
  final mejorDia = porDia.values.fold(0, (a, b) => a > b ? a : b);
  final ballenas = cagadas.where((c) => c.peso == 5).length;
  final nocturnas = cagadas.where((c) => c.cuando.hour < 4).length;
  final madrugadas = cagadas.where((c) => c.cuando.hour >= 4 && c.cuando.hour < 6).length;
  // Racha de días seguidos con al menos una, la más larga.
  final dias = porDia.keys.toList()..sort();
  var seguidos = 0, mejorSeguidos = 0;
  for (var i = 0; i < dias.length; i++) {
    seguidos = i > 0 && dias[i].difference(dias[i - 1]).inHours.round() <= 25 ? seguidos + 1 : 1;
    if (seguidos > mejorSeguidos) mejorSeguidos = seguidos;
  }
  final hito = _hitos.lastWhere((h) => h <= total, orElse: () => 0);
  final proximo = _hitos.firstWhere((h) => h > total, orElse: () => 0);
  final accesorios = desbloqueos.where((d) => d.minimo <= total).length;
  final racha = nombreRacha(mejorDia);

  return [
    (
      emoji: mejorDia >= 2 ? estiloRacha(mejorDia).$2 : '💩',
      nombre: racha == null ? tr('Racha', 'Streak') : racha.replaceAll('!', ''),
      detalle: tr('$mejorDia en un día', '$mejorDia in one day'),
      ganado: mejorDia >= 2,
    ),
    (
      emoji: '👑',
      nombre: hito == 0 ? tr('Primer hito', 'First milestone') : tr('$hito cagadas', '$hito poops'),
      detalle: proximo == 0 ? tr('Todos los hitos', 'Every milestone') : tr('Próximo: $proximo', 'Next: $proximo'),
      ganado: hito > 0,
    ),
    (
      emoji: '🐋',
      nombre: tr('Ballena', 'Whale'),
      detalle: ballenas == 0 ? tr('Una de peso 5', 'A weight 5 one') : '×$ballenas',
      ganado: ballenas > 0,
    ),
    (
      emoji: '⚔️',
      nombre: tr('Cagadón', 'Poop-Off'),
      detalle: victorias == 0 ? tr('Gana un reto', 'Win a challenge') : tr('$victorias ganado${victorias == 1 ? '' : 's'}', '$victorias won'),
      ganado: victorias > 0,
    ),
    (
      emoji: tipoEmoji(favorito),
      nombre: tr('Favorita', 'Favorite'),
      detalle: tipos[favorito]?.$2 ?? tr('Anota el tipo', 'Log the type'),
      ganado: tipos[favorito] != null,
    ),
    (
      emoji: '🎩',
      nombre: tr('Accesorios', 'Accessories'),
      detalle: tr('$accesorios de ${desbloqueos.length}', '$accesorios of ${desbloqueos.length}'),
      ganado: accesorios > 0,
    ),
    (
      emoji: '🌙',
      nombre: tr('Nocturno', 'Night owl'),
      detalle: nocturnas == 0 ? tr('Entre 12 y 4 am', 'Between 12 and 4 am') : '×$nocturnas',
      ganado: nocturnas > 0,
    ),
    (
      emoji: '🌅',
      nombre: tr('Madrugador', 'Early bird'),
      detalle: madrugadas == 0 ? tr('Entre 4 y 6 am', 'Between 4 and 6 am') : '×$madrugadas',
      ganado: madrugadas > 0,
    ),
    (
      emoji: '🗓️',
      nombre: tr('Semana perfecta', 'Perfect week'),
      detalle: mejorSeguidos >= 7 ? tr('7 días seguidos', '7 days in a row') : tr('$mejorSeguidos de 7 días', '$mejorSeguidos of 7 days'),
      ganado: mejorSeguidos >= 7,
    ),
  ];
}

/// La cuadrícula de trofeos. Los que faltan salen con candado.
class Vitrina extends StatelessWidget {
  const Vitrina({super.key, required this.trofeos});

  final List<Trofeo> trofeos;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final ganados = trofeos.where((t) => t.ganado).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Rotulo(tr('Vitrina', 'Trophy case')),
            const Spacer(),
            Text(tr('$ganados de ${trofeos.length}', '$ganados of ${trofeos.length}'),
                style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.textoSuave)),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: .9,
          children: [
            for (final t in trofeos)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: t.ganado ? acento : p.suave,
                  border: Border.all(color: t.ganado ? acentoTexto : p.borde, width: t.ganado ? 2 : 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    t.ganado ? Emoji(t.emoji, tamano: 36) : Opacity(opacity: .5, child: const Emoji('🔒', tamano: 30)),
                    const SizedBox(height: 4),
                    Text(
                      t.ganado ? t.nombre.toUpperCase() : '???',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: t.ganado ? acentoTexto : p.textoSuave),
                    ),
                    Text(
                      t.detalle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: t.ganado ? acentoTexto : p.textoSuave),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// El mes en curso en cuadritos, más oscuro cuantas más ese día. Hoy va con borde.
class MapaDelMes extends StatelessWidget {
  const MapaDelMes({super.key, required this.cagadas, required this.onTap});

  final List<({DateTime cuando, int? tipo, int? peso})> cagadas;
  final VoidCallback onTap;

  static const _niveles = [Color(0xFFFFF1A8), Color(0xFFFFE04D), acento, Color(0xFFC9A600)];

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final hoy = DateTime.now();
    final dias = DateUtils.getDaysInMonth(hoy.year, hoy.month);
    final cuantas = <int, int>{};
    for (final c in cagadas) {
      if (c.cuando.year == hoy.year && c.cuando.month == hoy.month) {
        cuantas.update(c.cuando.day, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final mes = '${meses[hoy.month - 1]} ${hoy.year}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Rotulo(mes),
                const Spacer(),
                Text(tr('VER CALENDARIO', 'VIEW CALENDAR'), style: numeros(context, tamano: 11, weight: FontWeight.w800, color: p.textoSuave)),
                Icon(Icons.chevron_right, size: 18, color: p.textoSuave),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [
                for (var d = 1; d <= dias; d++)
                  Container(
                    decoration: BoxDecoration(
                      color: switch (cuantas[d] ?? 0) {
                        0 => p.suave,
                        final n => _niveles[(n - 1).clamp(0, _niveles.length - 1)],
                      },
                      border: d == hoy.day ? Border.all(color: p.bordeFuerte, width: 2) : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
