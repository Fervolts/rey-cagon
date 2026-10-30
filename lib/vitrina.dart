import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'calendario.dart' show meses;
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'logros.dart';
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

/// Hitos: lo que se junta con el tiempo. Hazañas: lo que se hace en un día o a una hora.
/// Secretos: easter eggs, invisibles hasta que se ganan.
enum Grupo { hito, hazana, secreto }

/// Un trofeo de la vitrina. [ganado] decide si se ve o sale con candado. Los secretos solo
/// llegan a la lista si están ganados.
typedef Trofeo = ({String clave, String emoji, String nombre, String detalle, bool ganado, Grupo grupo});

/// Las cagadas propias en hora local, para la vitrina y el mapa del mes.
Future<List<({DateTime cuando, int? tipo, int? peso})>> cagadasPropias(String uid) async {
  final filas = await db.from('cagadas').select('created_at, tipo, peso').eq('user_id', uid).order('created_at', ascending: false);
  return [
    for (final f in filas)
      (cuando: DateTime.parse(f['created_at']).toLocal(), tipo: f['tipo'] as int?, peso: f['peso'] as int?),
  ];
}

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

String _veces(int n, int meta) => n == 0 ? '' : '×$n${n < meta ? ' / $meta' : ''}';

/// Los trofeos a partir de las cagadas, el total, las victorias, el tipo favorito y los
/// seguidores. [claves]: logros de eventos guardados (tabla `logros` y teléfono).
/// [ladoSecreto]: el dueño tiene el lado secreto. [verLadoSecreto]: quien mira también lo
/// tiene (o es el dueño); si no, los logros del lado secreto no salen ni ganados.
List<Trofeo> trofeos({
  required List<({DateTime cuando, int? tipo, int? peso})> cagadas,
  required int total,
  required int victorias,
  required int? favorito,
  int seguidores = 0,
  int siguiendo = 0,
  Set<String> claves = const {},
  bool ladoSecreto = false,
  bool verLadoSecreto = true,
}) {
  final porDia = <DateTime, int>{};
  final horasPorDia = <DateTime, Set<int>>{};
  for (final c in cagadas) {
    porDia.update(_dia(c.cuando), (n) => n + 1, ifAbsent: () => 1);
    horasPorDia.putIfAbsent(_dia(c.cuando), () => {}).add(c.cuando.hour);
  }
  final mejorDia = porDia.values.fold(0, (a, b) => a > b ? a : b);
  final ballenas = cagadas.where((c) => c.peso == 5).length;
  final plumas = cagadas.where((c) => c.peso == 1).length;
  final nocturnas = cagadas.where((c) => c.cuando.hour < 4).length;
  final madrugadas = cagadas.where((c) => c.cuando.hour >= 4 && c.cuando.hour < 6).length;
  final almuerzos = cagadas.where((c) => c.cuando.hour >= 12 && c.cuando.hour < 14).length;
  final laborales = cagadas.where((c) => c.cuando.weekday <= DateTime.friday && c.cuando.hour >= 9 && c.cuando.hour < 17).length;
  final tiposVistos = {for (final c in cagadas) if (tipos.containsKey(c.tipo)) c.tipo}.length;
  // Racha de días seguidos con al menos una, la más larga.
  final dias = porDia.keys.toList()..sort();
  var seguidos = 0, mejorSeguidos = 0;
  for (var i = 0; i < dias.length; i++) {
    seguidos = i > 0 && dias[i].difference(dias[i - 1]).inHours.round() <= 25 ? seguidos + 1 : 1;
    if (seguidos > mejorSeguidos) mejorSeguidos = seguidos;
  }
  DateTime manana(DateTime d) => DateTime(d.year, d.month, d.day + 1);
  // Sábado y el domingo que sigue.
  final finde = dias.any((d) => d.weekday == DateTime.saturday && porDia.containsKey(manana(d)));
  // Tres días seguidos con una a la misma hora.
  final puntual = dias.any((d) {
    final a = horasPorDia[manana(d)], b = horasPorDia[manana(manana(d))];
    return a != null && b != null && horasPorDia[d]!.any((h) => a.contains(h) && b.contains(h));
  });
  // El mes con más días cubiertos, y si alguno se llenó entero.
  final diasPorMes = <(int, int), int>{};
  for (final d in dias) {
    diasPorMes.update((d.year, d.month), (n) => n + 1, ifAbsent: () => 1);
  }
  final mesCompleto = diasPorMes.entries.any((e) => e.value >= DateUtils.getDaysInMonth(e.key.$1, e.key.$2));
  final mejorMes = diasPorMes.values.fold(0, (a, b) => a > b ? a : b);
  final hito = _hitos.lastWhere((h) => h <= total, orElse: () => 0);
  final proximo = _hitos.firstWhere((h) => h > total, orElse: () => 0);
  final accesorios = desbloqueos.where((d) => d.minimo <= total).length;

  Trofeo racha(String clave, int n) => (
        clave: clave,
        emoji: mejorDia >= n ? estiloRacha(n).$2 : '💩',
        nombre: (nombreRacha(n) ?? '').replaceAll('!', ''),
        detalle: tr('$n en un día', '$n in one day'),
        ganado: mejorDia >= n,
        grupo: Grupo.hazana,
      );

  final normales = <Trofeo>[
    (
      clave: 'hitos',
      emoji: '👑',
      nombre: hito == 0 ? tr('Primer hito', 'First milestone') : tr('$hito cagadas', '$hito poops'),
      detalle: proximo == 0 ? tr('Todos los hitos', 'Every milestone') : tr('Próximo: $proximo', 'Next: $proximo'),
      ganado: hito > 0,
      grupo: Grupo.hito,
    ),
    (
      clave: 'semana',
      emoji: '🗓️',
      nombre: tr('Semana perfecta', 'Perfect week'),
      detalle: mejorSeguidos >= 7 ? tr('7 días seguidos', '7 days in a row') : tr('$mejorSeguidos de 7 días', '$mejorSeguidos of 7 days'),
      ganado: mejorSeguidos >= 7,
      grupo: Grupo.hito,
    ),
    (
      clave: 'mes',
      emoji: '📅',
      nombre: tr('Mes perfecto', 'Perfect month'),
      detalle: mesCompleto ? tr('Todos los días de un mes', 'Every day of a month') : tr('Mejor: $mejorMes días', 'Best: $mejorMes days'),
      ganado: mesCompleto,
      grupo: Grupo.hito,
    ),
    (
      clave: 'accesorios',
      emoji: '🎩',
      nombre: tr('Accesorios', 'Accessories'),
      detalle: tr('$accesorios de ${desbloqueos.length}', '$accesorios of ${desbloqueos.length}'),
      ganado: accesorios > 0,
      grupo: Grupo.hito,
    ),
    (
      clave: 'favorita',
      emoji: tipoEmoji(favorito),
      nombre: tr('Favorita', 'Favorite'),
      detalle: tipos[favorito]?.$2 ?? tr('Anota el tipo', 'Log the type'),
      ganado: tipos[favorito] != null,
      grupo: Grupo.hito,
    ),
    (
      clave: 'coleccionista',
      emoji: '🦄',
      nombre: tr(segun('Coleccionista', 'Coleccionista'), 'Collector'),
      detalle: tr('$tiposVistos de ${tipos.length} tipos', '$tiposVistos of ${tipos.length} types'),
      ganado: tiposVistos >= tipos.length,
      grupo: Grupo.hito,
    ),
    (
      clave: 'social',
      emoji: '🫂',
      nombre: tr(segun('Sociable', 'Sociable'), 'Social butterfly'),
      detalle: siguiendo >= 10 ? tr('Sigues a $siguiendo', 'Following $siguiendo') : tr('Sigue a 10 ($siguiendo)', 'Follow 10 ($siguiendo)'),
      ganado: siguiendo >= 10,
      grupo: Grupo.hito,
    ),
    (
      clave: 'influencer',
      emoji: '📱',
      nombre: tr('Influencer del baño', 'Bathroom influencer'),
      detalle: seguidores >= 10 ? tr('$seguidores te siguen', '$seguidores followers') : tr('10 seguidores ($seguidores)', '10 followers ($seguidores)'),
      ganado: seguidores >= 10,
      grupo: Grupo.hito,
    ),
    (
      clave: 'cagadon',
      emoji: '⚔️',
      nombre: tr('Cagadón', 'Poop-Off'),
      detalle: victorias == 0 ? tr('Gana un reto', 'Win a challenge') : tr('$victorias ganado${victorias == 1 ? '' : 's'}', '$victorias won'),
      ganado: victorias > 0,
      grupo: Grupo.hito,
    ),
    (
      clave: 'leyenda',
      emoji: '🏆',
      nombre: tr('Leyenda del Cagadón', 'Poop-Off legend'),
      detalle: tr('$victorias de 10 retos', '$victorias of 10 challenges'),
      ganado: victorias >= 10,
      grupo: Grupo.hito,
    ),
    racha('racha', 2),
    racha('triple', 3),
    racha('ultra', 4),
    racha('rampage', 5),
    (
      clave: 'ballena',
      emoji: '🐋',
      nombre: tr('Ballena', 'Whale'),
      detalle: ballenas == 0 ? tr('Una de peso 5', 'A weight 5 one') : '×$ballenas',
      ganado: ballenas > 0,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'pluma',
      emoji: '🪶',
      nombre: tr('Peso pluma', 'Featherweight'),
      detalle: plumas == 0 ? tr('10 de peso 1', '10 weight 1 ones') : _veces(plumas, 10),
      ganado: plumas >= 10,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'nocturno',
      emoji: '🌙',
      nombre: tr(segun('Nocturno', 'Nocturna'), 'Night owl'),
      detalle: nocturnas == 0 ? tr('Entre 12 y 4 am', 'Between 12 and 4 am') : '×$nocturnas',
      ganado: nocturnas > 0,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'madrugador',
      emoji: '🌅',
      nombre: tr(segun('Madrugador', 'Madrugadora'), 'Early bird'),
      detalle: madrugadas == 0 ? tr('Entre 4 y 6 am', 'Between 4 and 6 am') : '×$madrugadas',
      ganado: madrugadas > 0,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'almuerzo',
      emoji: '🍔',
      nombre: tr('Sobremesa', 'Lunch break'),
      detalle: almuerzos == 0 ? tr('5 entre 12 y 2 pm', '5 between 12 and 2 pm') : _veces(almuerzos, 5),
      ganado: almuerzos >= 5,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'oficinista',
      emoji: '💼',
      nombre: tr('Cagando en horario laboral', 'Paid to poop'),
      detalle: laborales == 0 ? tr('10 de lunes a viernes, 9 a 5', '10 on weekdays, 9 to 5') : _veces(laborales, 10),
      ganado: laborales >= 10,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'finde',
      emoji: '🛋️',
      nombre: tr('Fin de semana', 'Weekend warrior'),
      detalle: tr('Sábado y domingo', 'Saturday and Sunday'),
      ganado: finde,
      grupo: Grupo.hazana,
    ),
    (
      clave: 'puntual',
      emoji: '⏰',
      nombre: tr('Reloj suizo', 'Swiss watch'),
      detalle: tr('Misma hora 3 días seguidos', 'Same hour 3 days in a row'),
      ganado: puntual,
      grupo: Grupo.hazana,
    ),
  ];

  // Los secretos: los de eventos salen de [claves]; los demás se calculan aquí.
  bool a(int h, int m) => cagadas.any((c) => c.cuando.hour == h && c.cuando.minute == m);
  final ganados = <String>{
    ...claves,
    if (ladoSecreto) 'placer_lado',
    if (mejorDia >= 6) 'hexa',
    if (a(11, 11) || a(23, 11)) 'hora_1111',
    if (a(3, 33)) 'hora_333',
    if (cagadas.any((c) => c.cuando.month == 1 && c.cuando.day == 1)) 'ano_nuevo',
    if (cagadas.any((c) => c.cuando.weekday == DateTime.friday && c.cuando.day == 13)) 'viernes_13',
  };
  final secretos = <Trofeo>[
    for (final l in logrosSecretos)
      if (ganados.contains(l.clave) && (verLadoSecreto || !l.ladoSecreto))
        (clave: l.clave, emoji: l.emoji, nombre: l.nombre, detalle: l.detalle, ganado: true, grupo: Grupo.secreto),
  ];
  return [...normales, ...secretos];
}

/// Cuántos secretos le faltan por encontrar a quien mira su propia vitrina.
int secretosPorEncontrar(List<Trofeo> lista) => logrosSecretos.length - lista.where((t) => t.grupo == Grupo.secreto).length;

/// La vitrina del perfil: los 9 mejores (primero los recién revelados, luego los ganados) y
/// VER TODOS para la vitrina completa por grupos. [nuevos]: secretos que se revelan con
/// animación. [porEncontrar]: si es > 0, la línea "+N secretos por encontrar".
class Vitrina extends StatelessWidget {
  const Vitrina({super.key, required this.trofeos, this.nuevos = const {}, this.porEncontrar = 0});

  final List<Trofeo> trofeos;
  final Set<String> nuevos;
  final int porEncontrar;

  static const _vistaPrevia = 9;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final ganados = trofeos.where((t) => t.ganado).length;
    int orden(Trofeo t) => nuevos.contains(t.clave) ? 0 : (t.ganado ? (t.grupo == Grupo.secreto ? 1 : 2) : 3);
    final indice = {for (var i = 0; i < trofeos.length; i++) trofeos[i].clave: i};
    final ordenados = [...trofeos]..sort((a, b) => orden(a) != orden(b) ? orden(a) - orden(b) : indice[a.clave]! - indice[b.clave]!);
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
        _Cuadricula(trofeos: ordenados.take(_vistaPrevia).toList(), nuevos: nuevos),
        if (trofeos.length > _vistaPrevia) ...[
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PantallaVitrina(trofeos: trofeos, porEncontrar: porEncontrar)),
            ),
            child: Text(tr('VER TODOS (${trofeos.length})', 'VIEW ALL (${trofeos.length})')),
          ),
        ],
        if (porEncontrar > 0) _PorEncontrar(porEncontrar),
      ],
    );
  }
}

class _PorEncontrar extends StatelessWidget {
  const _PorEncontrar(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(tr('+$n secreto${n == 1 ? '' : 's'} por encontrar', '+$n secret${n == 1 ? '' : 's'} to find'),
                style: numeros(context, tamano: 12, weight: FontWeight.w700, color: paleta(context).textoSuave)),
            const SizedBox(width: 6),
            const Emoji('🤫', tamano: 16),
          ],
        ),
      );
}

/// La vitrina completa: Hitos, Hazañas y, si hay alguno ganado, Secretos.
class PantallaVitrina extends StatelessWidget {
  const PantallaVitrina({super.key, required this.trofeos, this.porEncontrar = 0});

  final List<Trofeo> trofeos;
  final int porEncontrar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final grupos = [
      (Grupo.hito, tr('Hitos', 'Milestones')),
      (Grupo.hazana, tr('Hazañas', 'Feats')),
      (Grupo.secreto, tr('Secretos', 'Secrets')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('VITRINA', 'TROPHY CASE'))),
      body: ListView(
        padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
        children: [
          for (final (grupo, nombre) in grupos)
            if (trofeos.any((t) => t.grupo == grupo)) ...[
              Row(
                children: [
                  Rotulo(nombre),
                  const Spacer(),
                  if (grupo != Grupo.secreto)
                    Text(
                      '${trofeos.where((t) => t.grupo == grupo && t.ganado).length} / ${trofeos.where((t) => t.grupo == grupo).length}',
                      style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.textoSuave),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _Cuadricula(trofeos: trofeos.where((t) => t.grupo == grupo).toList()),
              const SizedBox(height: 20),
            ],
          if (porEncontrar > 0) _PorEncontrar(porEncontrar),
        ],
      ),
    );
  }
}

class _Cuadricula extends StatelessWidget {
  const _Cuadricula({required this.trofeos, this.nuevos = const {}});

  final List<Trofeo> trofeos;
  final Set<String> nuevos;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: .9,
        children: [
          for (final t in trofeos)
            nuevos.contains(t.clave) ? _Revelado(key: ValueKey('revelar-${t.clave}'), trofeo: t) : _Casilla(trofeo: t),
        ],
      );
}

class _Casilla extends StatelessWidget {
  const _Casilla({required this.trofeo, this.reverso = false});

  final Trofeo trofeo;

  /// La cara de atrás mientras se voltea: oscura y con '???', como un secreto todavía tapado.
  final bool reverso;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final t = trofeo;
    if (reverso) {
      return Container(
        decoration: BoxDecoration(color: p.texto, border: Border.all(color: acento, width: 2)),
        alignment: Alignment.center,
        child: Text('???', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: p.fondo)),
      );
    }
    final secreto = t.grupo == Grupo.secreto;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.ganado ? acento : p.suave,
        border: Border.all(color: t.ganado ? acentoTexto : p.borde, width: t.ganado ? 2 : 1),
      ),
      child: Stack(
        children: [
          Center(
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
          if (secreto) const Positioned(top: 0, right: 0, child: Emoji('🤫', tamano: 14)),
        ],
      ),
    );
  }
}

/// Un secreto recién ganado: destello dorado y el trofeo se voltea de '???' a su cara.
/// Con movimiento simple solo el destello; con nada, aparece y ya. Al terminar queda marcado.
class _Revelado extends StatefulWidget {
  const _Revelado({super.key, required this.trofeo});

  final Trofeo trofeo;

  @override
  State<_Revelado> createState() => _ReveladoState();
}

class _ReveladoState extends State<_Revelado> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  var _empezo = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_empezo) return;
    _empezo = true;
    if (movimiento(context) == Movimiento.nada) {
      _c.value = 1;
      marcarRevelado(widget.trofeo.clave);
      return;
    }
    // Con la pestaña YO escondida el ticker está en pausa: se revela cuando la ve.
    _c.forward().whenComplete(() => marcarRevelado(widget.trofeo.clave));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completo = movimiento(context) == Movimiento.completo;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (t >= 1) return _Casilla(trofeo: widget.trofeo);
        // Destello: sube rápido en el primer tercio y se apaga despacio.
        final brillo = t < .3 ? t / .3 : (1 - (t - .3) / .7);
        // Volteo entre 0.15 y 0.75: de 0 a pi; pasada la mitad se ve la cara.
        final giro = completo ? Curves.easeInOutCubic.transform(((t - .15) / .6).clamp(0.0, 1.0)) * math.pi : math.pi;
        final cara = giro > math.pi / 2;
        final escala = 1 + .12 * math.sin(t * math.pi);
        return Transform.scale(
          scale: completo ? escala : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .002)
                  ..rotateY(cara ? giro - math.pi : giro),
                child: _Casilla(trofeo: widget.trofeo, reverso: !cara),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [
                      Colors.white.withValues(alpha: .9 * brillo),
                      acento.withValues(alpha: .7 * brillo),
                      acento.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
