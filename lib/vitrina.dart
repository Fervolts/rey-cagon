import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'calendario.dart' show meses;
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'imperio/catalogo.dart' as imperio show logros;
import 'imperio/hoja_racha.dart' show nombreLogro;
import 'imperio/logros.dart' show cargarLogrosImperio, presumirLogroImperio;
import 'logros.dart';
import 'main.dart' show db, textoError;
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
/// Secretos: easter eggs, invisibles hasta que se ganan. Imperio: logros del modo clicker, solo
/// en la vitrina propia (no salen de [trofeos], sino de [trofeosImperio]).
enum Grupo { hito, hazana, secreto, imperio }

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
/// [vistos]: en la vitrina de otro, los secretos que ya encontró quien mira; solo esos salen
/// (null en la propia: salen todos los ganados).
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
  Set<String>? vistos,
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
      if (ganados.contains(l.clave) && (verLadoSecreto || !l.ladoSecreto) && (vistos == null || vistos.contains(l.clave)))
        (clave: l.clave, emoji: l.emoji, nombre: l.nombre, detalle: l.detalle, ganado: true, grupo: Grupo.secreto),
  ];
  return [...normales, ...secretos];
}

/// Cuántos secretos le faltan por encontrar a quien mira su propia vitrina.
int secretosPorEncontrar(List<Trofeo> lista) => logrosSecretos.length - lista.where((t) => t.grupo == Grupo.secreto).length;

/// Cómo se gana cada trofeo normal, para el detalle. Los secretos y el Imperio usan su propio texto.
String _comoSeGana(String clave) => switch (clave) {
      'hitos' => tr('Llega a 10, 25, 50, 100, 200, 365, 500 y 1000 cagadas.', 'Reach 10, 25, 50, 100, 200, 365, 500 and 1000 poops.'),
      'semana' => tr('Caga al menos una vez 7 días seguidos.', 'Poop at least once 7 days in a row.'),
      'mes' => tr('Caga todos los días de un mes del calendario.', 'Poop every day of a calendar month.'),
      'accesorios' => tr('Suma cagadas hasta desbloquear un accesorio para tu avatar.', 'Keep pooping until you unlock an avatar accessory.'),
      'favorita' => tr('Anota el tipo de tus cagadas: la que más repitas es tu favorita.', 'Log the type of your poops: the one you repeat most is your favorite.'),
      'coleccionista' => tr('Anota al menos una de cada tipo.', 'Log at least one of every type.'),
      'social' => tr('Sigue a 10 personas.', 'Follow 10 people.'),
      'influencer' => tr('Llega a 10 seguidores.', 'Reach 10 followers.'),
      'cagadon' => tr('Gana un reto 1 contra 1 del Cagadón.', 'Win a 1 on 1 Poop-Off challenge.'),
      'leyenda' => tr('Gana 10 retos del Cagadón.', 'Win 10 Poop-Off challenges.'),
      'racha' => tr('Caga 2 veces en un mismo día.', 'Poop 2 times in the same day.'),
      'triple' => tr('Caga 3 veces en un mismo día.', 'Poop 3 times in the same day.'),
      'ultra' => tr('Caga 4 veces en un mismo día.', 'Poop 4 times in the same day.'),
      'rampage' => tr('Caga 5 veces en un mismo día.', 'Poop 5 times in the same day.'),
      'ballena' => tr('Anota una cagada de peso 5.', 'Log a weight 5 poop.'),
      'pluma' => tr('Anota 10 cagadas de peso 1.', 'Log 10 weight 1 poops.'),
      'nocturno' => tr('Caga entre las 12 y las 4 de la madrugada.', 'Poop between 12 and 4 am.'),
      'madrugador' => tr('Caga entre las 4 y las 6 de la mañana.', 'Poop between 4 and 6 am.'),
      'almuerzo' => tr('Caga 5 veces entre las 12 y las 2 de la tarde.', 'Poop 5 times between 12 and 2 pm.'),
      'oficinista' => tr('Caga 10 veces de lunes a viernes, entre las 9 y las 5.', 'Poop 10 times on weekdays, between 9 and 5.'),
      'finde' => tr('Caga un sábado y también el domingo siguiente.', 'Poop on a Saturday and on the Sunday after.'),
      'puntual' => tr('Caga a la misma hora 3 días seguidos.', 'Poop at the same hour 3 days in a row.'),
      _ => '',
    };

/// El emoji de cada logro del Imperio en la vitrina. El que no esté sale con 🏆.
const _emojisImperio = {
  'primer_pujo': '👆',
  'calentando': '🔥',
  'profesional': '🦾',
  'hemorroides': '🩸',
  'nalgazo': '🍑',
  'epico': '💥',
  'gotea': '💧',
  'fluye': '💦',
  'corre': '🏃',
  'mojonero': '🪙',
  'mojonista': '💰',
  'mojonario': '💎',
  'primer_guayoyo': '☕',
  'cafeina': '☢️',
  'segundo_trono': '🚽',
  'primer_oro': '🟡',
  'buscador_oro': '⛏️',
  'plomero': '🪠',
  'descarga': '🚰',
  'cagar_fiebre': '🌶️',
  'primera_jalada': '💨',
  'diez_jaladas': '🚽',
  'primer_rollo': '🧻',
  'cien_rollos': '👑',
  'constancia': '🗓️',
  // Fase 2.
  'primer_mana': '🌀',
  'brujo_tripa': '🌀',
  'chorro_fallido': '🚿',
  'cliente_fijo': '🧰',
  'bodeguero': '🍵',
  'brocha_gorda': '🎨',
  'plomero_confianza': '🦸',
  'papel_al_poceto': '🧻',
  'primer_cofre': '🎁',
  'mes_de_hierro': '🔥',
  'congelado': '🧊',
  'minero': '⛏️',
  'rey_templo': '🛕',
  'erupcion': '🌋',
  'se_lo_trago': '🕳️',
};

const _prefijoImperio = 'imperio:';

/// Los logros del Imperio como trofeos de la vitrina, con [ganados] (ids de `cargarLogrosImperio`).
/// La clave lleva el prefijo `imperio:` para no chocar con las de los trofeos normales.
List<Trofeo> trofeosImperio(Set<String> ganados) => [
      for (final l in imperio.logros)
        (
          clave: '$_prefijoImperio${l.id}',
          emoji: _emojisImperio[l.id] ?? '🏆',
          nombre: nombreLogro(l),
          detalle: tr(l.descEs, l.descEn),
          ganado: ganados.contains(l.id),
          grupo: Grupo.imperio,
        ),
    ];

/// Los secretos que faltan, tapados: silueta con '?' y placa '???'.
List<Trofeo> _tapados(int n) => [
      for (var i = 0; i < n; i++)
        (clave: 'tapado-$i', emoji: '❓', nombre: '???', detalle: '', ganado: false, grupo: Grupo.secreto),
    ];

bool _esTapado(Trofeo t) => t.clave.startsWith('tapado-');

/// La zona VITRINA del perfil: una repisa con los mejores trofeos (primero los recién revelados,
/// luego los secretos y los ganados) y "N de M". Toda la tarjeta abre [PantallaVitrina].
/// [nuevos]: secretos que se revelan con animación. [porEncontrar]: si es > 0, la línea
/// "+N secretos por encontrar". [propio]: es el perfil de quien mira; la vitrina completa trae
/// la sección IMPERIO. [imperio]: ids de logros del Imperio ya cargados, para contarlos aquí.
class Vitrina extends StatelessWidget {
  const Vitrina({
    super.key,
    required this.trofeos,
    this.nuevos = const {},
    this.porEncontrar = 0,
    this.propio = false,
    this.imperio,
    this.alVolver,
  });

  final List<Trofeo> trofeos;
  final Set<String> nuevos;
  final int porEncontrar;
  final bool propio;
  final Set<String>? imperio;

  /// Al volver de la vitrina completa (para recargar lo que haga falta).
  final VoidCallback? alVolver;

  Future<void> _abrir(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaVitrina(trofeos: trofeos, porEncontrar: porEncontrar, nuevos: nuevos, conImperio: propio, imperio: imperio),
      ),
    );
    // Si salió antes de que terminara la animación, igual quedan vistos.
    for (final c in nuevos) {
      await marcarRevelado(c);
    }
    alVolver?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final todos = [...trofeos, if (propio && imperio != null) ...trofeosImperio(imperio!)];
    final ganados = todos.where((t) => t.ganado).length;
    int orden(Trofeo t) => nuevos.contains(t.clave) ? 0 : (t.ganado ? (t.grupo == Grupo.secreto ? 1 : 2) : 3);
    final indice = {for (var i = 0; i < todos.length; i++) todos[i].clave: i};
    final ordenados = [...todos]..sort((a, b) => orden(a) != orden(b) ? orden(a) - orden(b) : indice[a.clave]! - indice[b.clave]!);
    return Material(
      color: p.tarjeta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: p.borde)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('zona-vitrina'),
        onTap: () => _abrir(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Rotulo(tr('Vitrina', 'Trophy case')),
                  if (nuevos.isNotEmpty) ...[const SizedBox(width: 8), const _Nuevo()],
                  const Spacer(),
                  Text(tr('$ganados de ${todos.length}', '$ganados of ${todos.length}'),
                      style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.textoSuave)),
                  Icon(Icons.chevron_right, size: 20, color: p.textoSuave),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: LayoutBuilder(builder: (context, caja) {
                  final n = (caja.maxWidth / 64).floor().clamp(3, 5);
                  return _Repisa(trofeos: ordenados.take(n).toList(), columnas: n, nuevos: nuevos, tamano: 34, conPlaca: false);
                }),
              ),
              if (porEncontrar > 0) _PorEncontrar(porEncontrar),
            ],
          ),
        ),
      ),
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
            Flexible(
              child: Text(tr('+$n secreto${n == 1 ? '' : 's'} por encontrar', '+$n secret${n == 1 ? '' : 's'} to find'),
                  style: numeros(context, tamano: 12, weight: FontWeight.w700, color: paleta(context).textoSuave)),
            ),
            const SizedBox(width: 6),
            const Emoji('🤫', tamano: 16),
          ],
        ),
      );
}

/// La etiqueta NUEVO, cuadrada y en acento.
class _Nuevo extends StatelessWidget {
  const _Nuevo();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: acento, borderRadius: BorderRadius.circular(radio)),
        child: Text(tr('NUEVO', 'NEW'),
            style: const TextStyle(fontSize: 9, height: 1.2, fontWeight: FontWeight.w900, color: acentoTexto, letterSpacing: .6)),
      );
}

/// La vitrina completa, como un mueble: una sección por grupo (Hitos, Hazañas, Imperio, Secretos),
/// cada una con repisas de 2px y los trofeos parados encima con su placa. Tocar uno abre el detalle.
/// [conImperio]: trae la sección IMPERIO (solo en el perfil propio); si [imperio] es null la carga.
/// [irAImperio]: al abrir baja hasta esa sección.
class PantallaVitrina extends StatefulWidget {
  const PantallaVitrina({
    super.key,
    required this.trofeos,
    this.porEncontrar = 0,
    this.nuevos = const {},
    this.conImperio = false,
    this.imperio,
    this.irAImperio = false,
  });

  final List<Trofeo> trofeos;
  final int porEncontrar;
  final Set<String> nuevos;
  final bool conImperio;
  final Set<String>? imperio;
  final bool irAImperio;

  @override
  State<PantallaVitrina> createState() => _PantallaVitrinaState();
}

class _PantallaVitrinaState extends State<PantallaVitrina> {
  final _seccionImperio = GlobalKey();
  Set<String>? _imperio;
  String? _error;
  var _bajo = false;

  @override
  void initState() {
    super.initState();
    _imperio = widget.imperio;
    if (widget.conImperio && _imperio == null) {
      _cargar();
    } else {
      _bajarAImperio();
    }
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final ids = await cargarLogrosImperio();
      if (!mounted) return;
      setState(() => _imperio = ids);
      _bajarAImperio();
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
    }
  }

  void _bajarAImperio() {
    if (!widget.irAImperio || _bajo) return;
    _bajo = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _seccionImperio.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: Duration.zero);
    });
  }

  void _detalle(Trofeo t) {
    final esImperio = t.grupo == Grupo.imperio;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (hoja) => _Detalle(
        trofeo: t,
        nuevo: widget.nuevos.contains(t.clave),
        alPresumir: esImperio && t.ganado && widget.conImperio
            ? () {
                Navigator.pop(hoja);
                presumirLogroImperio(context, t.clave.substring(_prefijoImperio.length));
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final secretos = [...widget.trofeos.where((t) => t.grupo == Grupo.secreto), ..._tapados(widget.porEncontrar)];
    final secciones = [
      (Grupo.hito, tr('Hitos', 'Milestones'), widget.trofeos.where((t) => t.grupo == Grupo.hito).toList()),
      (Grupo.hazana, tr('Hazañas', 'Feats'), widget.trofeos.where((t) => t.grupo == Grupo.hazana).toList()),
      if (widget.conImperio) (Grupo.imperio, tr('Imperio', 'Empire'), _imperio == null ? <Trofeo>[] : trofeosImperio(_imperio!)),
      (Grupo.secreto, tr('Secretos', 'Secrets'), secretos),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('VITRINA', 'TROPHY CASE'))),
      body: SingleChildScrollView(
        padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
        child: LayoutBuilder(builder: (context, caja) {
          final columnas = ((caja.maxWidth - 18) / 100).floor().clamp(3, 6);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (grupo, nombre, lista) in secciones)
                if (lista.isNotEmpty || grupo == Grupo.imperio)
                  _Mueble(
                    key: grupo == Grupo.imperio ? _seccionImperio : null,
                    titulo: nombre,
                    contador: grupo == Grupo.secreto ? null : '${lista.where((t) => t.ganado).length} / ${lista.length}',
                    child: grupo == Grupo.imperio && lista.isEmpty
                        ? _CargandoImperio(error: _error, reintentar: _cargar)
                        : Column(
                            children: [
                              for (var i = 0; i < lista.length; i += columnas)
                                _Repisa(
                                  trofeos: lista.sublist(i, math.min(i + columnas, lista.length)),
                                  columnas: columnas,
                                  nuevos: widget.nuevos,
                                  alTocar: _detalle,
                                ),
                              if (grupo == Grupo.secreto && widget.porEncontrar > 0) _PorEncontrar(widget.porEncontrar),
                            ],
                          ),
                  ),
              Text(tr('Toca un trofeo para ver cómo se gana.', 'Tap a trophy to see how to win it.'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textoSuave)),
            ],
          );
        }),
      ),
    );
  }
}

/// Una sección de la vitrina: el fondo del mueble, el rótulo arriba y las repisas.
class _Mueble extends StatelessWidget {
  const _Mueble({super.key, required this.titulo, required this.contador, required this.child});

  final String titulo;
  final String? contador;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: p.suave, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(color: p.tarjeta, border: Border(bottom: BorderSide(color: p.bordeFuerte))),
            child: Row(
              children: [
                Expanded(child: Rotulo(titulo)),
                if (contador != null) Text(contador!, style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.textoSuave)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 10), child: child),
        ],
      ),
    );
  }
}

class _CargandoImperio extends StatelessWidget {
  const _CargandoImperio({required this.error, required this.reintentar});

  final String? error;
  final VoidCallback reintentar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: error == null
            ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                children: [
                  Text(error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: paleta(context).textoSuave)),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: reintentar, child: Text(tr('REINTENTAR', 'RETRY'))),
                ],
              ),
      );
}

/// Una repisa: los trofeos parados sobre una tabla de 2px (en acento bajo los ganados) y,
/// con [conPlaca], una placa con el nombre debajo de cada uno.
class _Repisa extends StatelessWidget {
  const _Repisa({
    required this.trofeos,
    required this.columnas,
    this.nuevos = const {},
    this.tamano = 40,
    this.conPlaca = true,
    this.alTocar,
  });

  final List<Trofeo> trofeos;
  final int columnas;
  final Set<String> nuevos;
  final double tamano;
  final bool conPlaca;
  final void Function(Trofeo)? alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Padding(
      padding: EdgeInsets.only(top: conPlaca ? 10 : 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < columnas; i++)
            Expanded(
              child: i >= trofeos.length
                  ? Column(children: [SizedBox(height: tamano * 1.45), Container(height: 2, color: p.bordeFuerte)])
                  : _Puesto(
                      trofeo: trofeos[i],
                      nuevo: nuevos.contains(trofeos[i].clave),
                      tamano: tamano,
                      conPlaca: conPlaca,
                      alTocar: alTocar,
                    ),
            ),
        ],
      ),
    );
  }
}

/// Un puesto de la repisa: el trofeo, su tramo de tabla y la placa.
class _Puesto extends StatelessWidget {
  const _Puesto({required this.trofeo, required this.nuevo, required this.tamano, required this.conPlaca, this.alTocar});

  final Trofeo trofeo;
  final bool nuevo;
  final double tamano;
  final bool conPlaca;
  final void Function(Trofeo)? alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final t = trofeo;
    final figura = nuevo ? _Revelado(key: ValueKey('revelar-${t.clave}'), trofeo: t, tamano: tamano) : _Figura(trofeo: t, tamano: tamano);
    final puesto = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: tamano * 1.45,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 2), child: figura)),
              if (nuevo && conPlaca) const Positioned(top: 0, left: 2, child: _Nuevo()),
            ],
          ),
        ),
        Container(height: 2, color: t.ganado ? acento : p.bordeFuerte),
        if (conPlaca) ...[
          const SizedBox(height: 5),
          _Placa(clave: t.clave, texto: t.nombre, apagada: !t.ganado),
        ],
      ],
    );
    if (alTocar == null) return puesto;
    return Semantics(
      button: true,
      label: t.nombre,
      child: InkWell(key: ValueKey('trofeo-${t.clave}'), onTap: () => alTocar!(t), child: puesto),
    );
  }
}

/// La placa con el nombre. Si una palabra no cabe en el ancho, achica la letra en vez de partirla.
class _Placa extends StatelessWidget {
  const _Placa({required this.clave, required this.texto, required this.apagada});

  final String clave;
  final String texto;
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: LayoutBuilder(builder: (context, caja) {
        final escala = MediaQuery.textScalerOf(context);
        final base = DefaultTextStyle.of(context).style;
        final palabras = texto.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        TextStyle estiloDe(double tamano) =>
            TextStyle(fontSize: tamano, height: 1.15, fontWeight: FontWeight.w700, color: apagada ? p.textoSuave : p.texto);
        // Cabe si ninguna palabra pasa del ancho y el nombre entero entra en 3 líneas.
        bool cabe(TextStyle estilo) {
          TextPainter medir(String t, int? lineas) =>
              TextPainter(text: TextSpan(text: t, style: base.merge(estilo)), textDirection: TextDirection.ltr, textScaler: escala, maxLines: lineas)
                ..layout(maxWidth: lineas == null ? double.infinity : caja.maxWidth);
          for (final w in palabras) {
            final tp = medir(w, null);
            final ancho = tp.width;
            tp.dispose();
            if (ancho > caja.maxWidth) return false;
          }
          final todo = medir(texto, 3);
          final sobra = todo.didExceedMaxLines;
          todo.dispose();
          return !sobra;
        }

        var tamano = 11.0;
        while (tamano > 5 && !cabe(estiloDe(tamano))) {
          tamano -= .5;
        }
        final estilo = estiloDe(tamano);
        return Text(
          texto,
          key: ValueKey('placa-$clave'),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: estilo,
        );
      }),
    );
  }
}

/// El trofeo en sí. Ganado: su emoji con un halo suave en acento. Sin ganar: la silueta oscura
/// con 🔒 (o '?' si es un secreto tapado). [reverso]: la cara de atrás mientras se voltea.
class _Figura extends StatelessWidget {
  const _Figura({required this.trofeo, required this.tamano, this.reverso = false});

  final Trofeo trofeo;
  final double tamano;
  final bool reverso;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final t = trofeo;
    final sombra = p.bordeFuerte.withValues(alpha: .55);
    if (reverso || _esTapado(t)) {
      return ColorFiltered(colorFilter: ColorFilter.mode(reverso ? p.texto : sombra, BlendMode.srcIn), child: Emoji('❓', tamano: tamano));
    }
    if (!t.ganado) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ColorFiltered(colorFilter: ColorFilter.mode(sombra, BlendMode.srcIn), child: Emoji(t.emoji, tamano: tamano)),
          Positioned(right: -tamano * .2, bottom: -2, child: Opacity(opacity: .8, child: Emoji('🔒', tamano: tamano * .4))),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -tamano * .35,
          right: -tamano * .35,
          top: -tamano * .35,
          bottom: -tamano * .2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [acento.withValues(alpha: .32), acento.withValues(alpha: 0)]),
              ),
            ),
          ),
        ),
        Emoji(t.emoji, tamano: tamano),
      ],
    );
  }
}

/// El detalle de un trofeo: grande, nombre, estado, lo que lleva y cómo se gana.
/// Con [alPresumir] (Imperio, ganado, perfil propio) sale PRESUMIR.
class _Detalle extends StatelessWidget {
  const _Detalle({required this.trofeo, required this.nuevo, this.alPresumir});

  final Trofeo trofeo;
  final bool nuevo;
  final VoidCallback? alPresumir;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final t = trofeo;
    final tapado = _esTapado(t);
    final grupo = switch (t.grupo) {
      Grupo.hito => tr('Hito', 'Milestone'),
      Grupo.hazana => tr('Hazaña', 'Feat'),
      Grupo.secreto => tr('Secreto', 'Secret'),
      Grupo.imperio => tr('Imperio', 'Empire'),
    };
    final como = switch (t.grupo) {
      _ when tapado => tr('Nadie te lo va a decir. Sigue cagando y fíjate en los detalles.', "Nobody's telling. Keep pooping and pay attention."),
      Grupo.secreto || Grupo.imperio => t.detalle,
      _ => _comoSeGana(t.clave),
    };
    final avance = t.grupo == Grupo.hito || t.grupo == Grupo.hazana ? t.detalle : '';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _Figura(trofeo: t, tamano: 72)),
            const SizedBox(height: 16),
            Text(t.nombre, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.texto)),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Rotulo(grupo),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.ganado ? acento : null,
                    border: Border.all(color: t.ganado ? acento : p.borde),
                    borderRadius: BorderRadius.circular(radio),
                  ),
                  child: Text(t.ganado ? tr('GANADO', 'WON') : tr('POR GANAR', 'NOT YET'),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: t.ganado ? acentoTexto : p.textoSuave)),
                ),
                if (nuevo) const _Nuevo(),
              ],
            ),
            if (avance.isNotEmpty && avance != como) ...[
              const SizedBox(height: 12),
              Text(avance, textAlign: TextAlign.center, style: numeros(context, tamano: 14, weight: FontWeight.w700, color: p.textoSuave)),
            ],
            if (como.isNotEmpty) ...[
              const SizedBox(height: 16),
              Rotulo(tr('Cómo se gana', 'How to win it')),
              const SizedBox(height: 4),
              Text(como, style: TextStyle(fontSize: 15, color: p.texto)),
            ],
            if (alPresumir != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: alPresumir, child: Text(tr('PRESUMIR', 'SHOW OFF'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un secreto recién ganado: destello dorado y el trofeo se voltea de '?' a su cara.
/// Con movimiento simple solo el destello; con nada, aparece y ya. Al terminar queda marcado.
class _Revelado extends StatefulWidget {
  const _Revelado({super.key, required this.trofeo, required this.tamano});

  final Trofeo trofeo;
  final double tamano;

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
    final tamano = widget.tamano;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (t >= 1) return _Figura(trofeo: widget.trofeo, tamano: tamano);
        // Destello: sube rápido en el primer tercio y se apaga despacio.
        final brillo = t < .3 ? t / .3 : (1 - (t - .3) / .7);
        // Volteo entre 0.15 y 0.75: de 0 a pi; pasada la mitad se ve la cara.
        final giro = completo ? Curves.easeInOutCubic.transform(((t - .15) / .6).clamp(0.0, 1.0)) * math.pi : math.pi;
        final cara = giro > math.pi / 2;
        final escala = 1 + .12 * math.sin(t * math.pi);
        return Transform.scale(
          scale: completo ? escala : 1,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .002)
                  ..rotateY(cara ? giro - math.pi : giro),
                child: _Figura(trofeo: widget.trofeo, tamano: tamano, reverso: !cara),
              ),
              Positioned(
                left: -tamano * .4,
                right: -tamano * .4,
                top: -tamano * .4,
                bottom: -tamano * .4,
                child: IgnorePointer(
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
