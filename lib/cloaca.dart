// Cloacas: grupos de hasta 25 jugadores con liga semanal, bono de producción en el Imperio y chat propio.
// Todo lo que cuenta (puntos, topes, premios, quién entra) lo decide el servidor (migración 20261110120000_cloacas.sql);
// aquí solo se lee y se muestra.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'accesorios.dart' show Avatar;
import 'avisos.dart' show ir;
import 'chat.dart' show Sala;
import 'emoji.dart';
import 'idioma.dart';
import 'imperio/ranking_amigos.dart' show faltaFuncion, rankingImperio;
import 'main.dart' show conReintento, db, textoError;
import 'perfil.dart' show PantallaPerfil;
import 'periodos.dart' show ContadorCierre;
import 'tema.dart';
import 'vivo.dart' show Cargando;

int _ent(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _real(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
DateTime? _fecha(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();
Map<String, dynamic> _mapa(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _lista(Object? v) => v is List ? [for (final x in v) _mapa(x)] : const [];

/// Lo que dice el servidor si no manda otra cosa (flags `cloaca_max_miembros`, `cloaca_premio_rollos`,
/// `cloaca_bono_por_miembro` y `cloaca_bono_tope`).
const int maxMiembrosDefecto = 25;
const int premioRollosDefecto = 2;
const double bonoPorMiembroDefecto = 0.05;
const double bonoTopeDefecto = 0.5;

/// Emojis para elegir al crear una Cloaca (el servidor acepta cualquier emoji corto).
const emojisCloaca = ['💩', '🚽', '🧻', '🪠', '🦨', '🐀', '👑', '🔥', '💀', '🤢', '🪰', '🧼'];

/// true = la pestaña RANKING muestra la liga de Cloacas.
final rankingCloacas = ValueNotifier<bool>(false);

/// Sube cada vez que alguien crea, entra, sale o saca a alguien: el Imperio vuelve a pedir el bono y el chat su sala.
final cloacaCambio = ValueNotifier<int>(0);

/// Lleva a la pestaña RANKING con las Cloacas a la vista.
void verCloacas() {
  rankingImperio.value = false;
  rankingCloacas.value = true;
  ir('ranking');
}

class MiembroCloaca {
  const MiembroCloaca({
    required this.userId,
    required this.username,
    this.avatar,
    this.dueno = false,
    this.unido,
    this.cagadas = 0,
    this.ptsCagadas = 0,
    this.ptsImperio = 0,
    this.puntos = 0,
    this.cagoHoy = false,
  });

  factory MiembroCloaca.desdeJson(Map<String, dynamic> j) => MiembroCloaca(
        userId: '${j['user_id'] ?? ''}',
        username: '${j['username'] ?? ''}',
        avatar: j['avatar'] as String?,
        dueno: j['dueno'] == true,
        unido: _fecha(j['unido']),
        cagadas: _ent(j['cagadas']),
        ptsCagadas: _ent(j['pts_cagadas']),
        ptsImperio: _ent(j['pts_imperio']),
        puntos: _ent(j['puntos']),
        cagoHoy: j['cago_hoy'] == true,
      );

  final String userId, username;
  final String? avatar;
  final bool dueno, cagoHoy;
  final DateTime? unido;

  /// Cagadas reales de la semana estando en la Cloaca, puntos por ellas (10 c/u, 3 por día), puntos del Imperio
  /// (hasta 10) y la suma.
  final int cagadas, ptsCagadas, ptsImperio, puntos;
}

class Cloaca {
  const Cloaca({
    required this.id,
    required this.nombre,
    required this.emoji,
    required this.codigo,
    required this.sala,
    this.soyDueno = false,
    this.puntos = 0,
    this.puesto,
    this.bono = 0,
    this.miembros = const [],
  });

  factory Cloaca.desdeJson(Map<String, dynamic> j) {
    final id = '${j['id'] ?? ''}';
    final sala = '${j['sala'] ?? ''}';
    return Cloaca(
      id: id,
      nombre: '${j['nombre'] ?? ''}',
      emoji: '${j['emoji'] ?? ''}'.trim().isEmpty ? '💩' : '${j['emoji']}'.trim(),
      codigo: '${j['codigo'] ?? ''}',
      sala: sala.isEmpty ? 'cloaca:$id' : sala,
      soyDueno: j['soy_dueno'] == true,
      puntos: _ent(j['puntos']),
      puesto: j['puesto'] == null ? null : _ent(j['puesto']),
      bono: _real(j['bono']),
      miembros: [for (final m in _lista(j['miembros'])) MiembroCloaca.desdeJson(m)],
    );
  }

  final String id, nombre, emoji, codigo;

  /// Sala del chat de la Cloaca en public.mensajes (`cloaca:<id>`): solo la ven los miembros.
  final String sala;
  final bool soyDueno;
  final int puntos;

  /// Puesto en la liga de esta semana (null si el servidor no lo sabe).
  final int? puesto;

  /// Bono de producción de hoy para mí (0,05 = +5%).
  final double bono;
  final List<MiembroCloaca> miembros;

  int get cagaronHoy => miembros.where((m) => m.cagoHoy).length;
}

/// Rollos de Oro de una liga ganada que aún no se cobraron.
class PremioCloaca {
  const PremioCloaca({required this.id, required this.semana, required this.rollos});

  factory PremioCloaca.desdeJson(Map<String, dynamic> j) =>
      PremioCloaca(id: '${j['id'] ?? ''}', semana: '${j['semana'] ?? ''}', rollos: _ent(j['rollos']));

  final String id;
  final String semana;
  final int rollos;
}

/// Lo que devuelve `cloaca_mia`: mi Cloaca (o null), mis premios por cobrar y los números de la liga.
class EstadoCloaca {
  const EstadoCloaca({
    this.cloaca,
    this.premios = const [],
    this.semana = '',
    this.cierra,
    this.max = maxMiembrosDefecto,
    this.premio = premioRollosDefecto,
    this.bonoPor = bonoPorMiembroDefecto,
    this.bonoTope = bonoTopeDefecto,
  });

  factory EstadoCloaca.desdeJson(Object? v) {
    final j = _mapa(v);
    final c = j['cloaca'];
    return EstadoCloaca(
      cloaca: c is Map ? Cloaca.desdeJson(_mapa(c)) : null,
      premios: [for (final p in _lista(j['premios'])) PremioCloaca.desdeJson(p)],
      semana: '${j['semana'] ?? ''}',
      cierra: _fecha(j['cierra']),
      max: j['max'] == null ? maxMiembrosDefecto : _ent(j['max']),
      premio: j['premio'] == null ? premioRollosDefecto : _ent(j['premio']),
      bonoPor: j['bono_por'] == null ? bonoPorMiembroDefecto : _real(j['bono_por']),
      bonoTope: j['bono_tope'] == null ? bonoTopeDefecto : _real(j['bono_tope']),
    );
  }

  final Cloaca? cloaca;
  final List<PremioCloaca> premios;
  final String semana;
  final DateTime? cierra;
  final int max, premio;
  final double bonoPor, bonoTope;

  int get rollosPorCobrar => premios.fold(0, (s, p) => s + p.rollos);
}

class FilaCloaca {
  const FilaCloaca({required this.id, required this.nombre, required this.emoji, this.puntos = 0, this.miembros = 0, this.puesto = 0, this.mia = false});

  factory FilaCloaca.desdeJson(Map<String, dynamic> j) => FilaCloaca(
        id: '${j['id'] ?? ''}',
        nombre: '${j['nombre'] ?? ''}',
        emoji: '${j['emoji'] ?? ''}'.trim().isEmpty ? '💩' : '${j['emoji']}'.trim(),
        puntos: _ent(j['puntos']),
        miembros: _ent(j['miembros']),
        puesto: _ent(j['puesto']),
        mia: j['mia'] == true,
      );

  final String id, nombre, emoji;
  final int puntos, miembros, puesto;
  final bool mia;
}

/// La Cloaca que ganó la última liga cerrada.
class GanadoraCloaca {
  const GanadoraCloaca({required this.semana, required this.nombre, required this.emoji, this.puntos = 0, this.miembros = 0});

  final String semana, nombre, emoji;
  final int puntos, miembros;
}

/// Lo que devuelve `cloaca_ranking`: la liga de esta semana en vivo.
class RankingCloacas {
  const RankingCloacas({this.semana = '', this.cierra, this.filas = const [], this.anterior});

  factory RankingCloacas.desdeJson(Object? v) {
    final j = _mapa(v);
    final a = j['anterior'];
    return RankingCloacas(
      semana: '${j['semana'] ?? ''}',
      cierra: _fecha(j['cierra']),
      filas: [for (final f in _lista(j['filas'])) FilaCloaca.desdeJson(f)],
      anterior: a is Map
          ? GanadoraCloaca(
              semana: '${a['semana'] ?? ''}',
              nombre: '${a['nombre'] ?? ''}',
              emoji: '${a['emoji'] ?? ''}'.trim().isEmpty ? '💩' : '${a['emoji']}'.trim(),
              puntos: _ent(a['puntos']),
              miembros: _ent(a['miembros']),
            )
          : null,
    );
  }

  final String semana;
  final DateTime? cierra;
  final List<FilaCloaca> filas;
  final GanadoraCloaca? anterior;
}

/// Respuesta de crear, unirse, salir, expulsar o cobrar.
class ResultadoCloaca {
  const ResultadoCloaca({required this.ok, this.motivo, this.texto, this.id, this.codigo, this.rollos = 0});

  factory ResultadoCloaca.desdeJson(Object? v) {
    final j = _mapa(v);
    return ResultadoCloaca(
      ok: j['ok'] == true,
      motivo: j['motivo'] as String?,
      texto: j['texto'] as String?,
      id: j['id'] == null ? null : '${j['id']}',
      codigo: j['codigo'] as String?,
      rollos: _ent(j['rollos']),
    );
  }

  final bool ok;
  final String? motivo;

  /// Con motivo 'nombre': por qué el servidor no aceptó el nombre (en español, como en el chat).
  final String? texto;
  final String? id, codigo;
  final int rollos;
}

/// Texto llano para cada motivo del servidor.
String textoMotivoCloaca(String? motivo, {String? texto}) => switch (motivo) {
      'nombre' => (texto != null && texto.trim().isNotEmpty && idioma.value == 'es')
          ? texto.trim()
          : tr('Ese nombre no se puede usar. Prueba con otro (de 3 a 24 letras).', 'That name is not allowed. Try another one (3 to 24 letters).'),
      'nombre_usado' => tr('Ya hay una Cloaca con ese nombre.', 'There is already a Sewer with that name.'),
      'emoji' => tr('Elige un solo emoji.', 'Pick just one emoji.'),
      'ya_tienes' => tr('Ya estás en una Cloaca. Sal de ella primero.', 'You are already in a Sewer. Leave it first.'),
      'codigo' => tr('No hay ninguna Cloaca con ese código.', 'There is no Sewer with that code.'),
      'llena' => tr('Esa Cloaca está llena.', 'That Sewer is full.'),
      'expulsado' => tr('Te sacaron de esa Cloaca hace poco. Prueba en unos días.', 'You were removed from that Sewer recently. Try again in a few days.'),
      'muchos_cambios' => tr('Cambiaste mucho de Cloaca esta semana. Espera al lunes.', 'You changed Sewers too much this week. Wait until Monday.'),
      'no_dueno' => tr('Solo el dueño puede sacar a alguien.', 'Only the owner can remove someone.'),
      'no_miembro' => tr('Esa persona ya no está en tu Cloaca.', 'That person is no longer in your Sewer.'),
      'sin_cloaca' => tr('No estás en ninguna Cloaca.', 'You are not in any Sewer.'),
      'no_existe' => tr('Ese premio ya se cobró.', 'That prize was already claimed.'),
      'sin_imperio' => tr('Abre el Imperio una vez para cobrar tus Rollos de Oro.', 'Open the Empire once to claim your Golden Rolls.'),
      'sin_sesion' => tr('Entra a tu cuenta primero.', 'Log in first.'),
      _ => tr('No se pudo. Prueba otra vez.', 'It did not work. Try again.'),
    };

final _codigoSolo = RegExp(r'^[A-Za-z0-9]{6}$');
final _codigoEnTexto = RegExp(r'(?<![A-Za-z0-9])[A-Z0-9]{6}(?![A-Za-z0-9])');

/// El código de 6 letras de una Cloaca dentro de lo que pegó la persona: el código solo (en mayúsculas o no) o la
/// invitación entera (el código va en mayúsculas). null si no hay ninguno.
String? codigoDeTexto(String texto) {
  final t = texto.trim();
  if (_codigoSolo.hasMatch(t)) return t.toUpperCase();
  for (final m in _codigoEnTexto.allMatches(t)) {
    final c = m.group(0)!;
    // Una palabra en mayúsculas (CLOACA, IMPERIO) no es un código: los códigos llevan al menos un número.
    if (RegExp(r'[0-9]').hasMatch(c)) return c;
  }
  return null;
}

/// El mensaje para invitar a alguien a mi Cloaca.
String textoInvitacion(Cloaca c) => tr(
      'Únete a mi Cloaca ${c.emoji} ${c.nombre} en Rey Cagón. Código: ${c.codigo} https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon',
      'Join my Sewer ${c.emoji} ${c.nombre} in Rey Cagón. Code: ${c.codigo} https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon',
    );

/// "+15%" para un bono de 0,15.
String textoBono(double bono) => '+${(bono * 100).round()}%';

/// Llamadas al servidor. Las de leer reintentan; las que cambian algo no, para no hacerlo dos veces.
class NubeCloacas {
  const NubeCloacas();

  Future<EstadoCloaca> mia() async => EstadoCloaca.desdeJson(await conReintento(() => db.rpc('cloaca_mia')));

  Future<RankingCloacas> ranking() async => RankingCloacas.desdeJson(await conReintento(() => db.rpc('cloaca_ranking')));

  /// Mi bono de producción de hoy (0 sin Cloaca o si el servidor aún no tiene Cloacas).
  Future<double> bono() async {
    try {
      return _real(await conReintento(() => db.rpc('cloaca_bono')));
    } catch (e) {
      if (faltaFuncion(e)) return 0;
      rethrow;
    }
  }

  Future<ResultadoCloaca> crear(String nombre, String emoji) async =>
      _avisar(ResultadoCloaca.desdeJson(await db.rpc('cloaca_crear', params: {'p_nombre': nombre, 'p_emoji': emoji})));

  Future<ResultadoCloaca> unirse(String codigo) async =>
      _avisar(ResultadoCloaca.desdeJson(await db.rpc('cloaca_unirse', params: {'p_codigo': codigo})));

  Future<ResultadoCloaca> salir() async => _avisar(ResultadoCloaca.desdeJson(await db.rpc('cloaca_salir')));

  Future<ResultadoCloaca> expulsar(String userId) async =>
      _avisar(ResultadoCloaca.desdeJson(await db.rpc('cloaca_expulsar', params: {'p_user': userId})));

  Future<ResultadoCloaca> cobrar(String id) async => ResultadoCloaca.desdeJson(await db.rpc('cloaca_premio_cobrar', params: {'p_id': id}));

  ResultadoCloaca _avisar(ResultadoCloaca r) {
    if (r.ok) cloacaCambio.value++;
    return r;
  }
}

/// Las llamadas de las pantallas de la Cloaca (en pruebas y demos se cambia por una falsa).
NubeCloacas nubeCloacas = const NubeCloacas();

/// La liga de Cloacas dentro de la lista de la pestaña RANKING: mi Cloaca, la tabla de la semana y cómo funciona.
/// [vuelta] sube al tirar para refrescar.
class RankingCloacasVista extends StatefulWidget {
  const RankingCloacasVista({super.key, this.vuelta = 0});

  final int vuelta;

  @override
  State<RankingCloacasVista> createState() => _RankingCloacasVistaState();
}

class _RankingCloacasVistaState extends State<RankingCloacasVista> {
  EstadoCloaca? _mia;
  RankingCloacas? _ranking;
  Object? _error;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    cloacaCambio.addListener(_cargar);
    _cargar();
  }

  @override
  void didUpdateWidget(RankingCloacasVista viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.vuelta != widget.vuelta) _cargar();
  }

  @override
  void dispose() {
    cloacaCambio.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait([nubeCloacas.mia(), nubeCloacas.ranking()]);
      if (!mounted) return;
      setState(() {
        _mia = r[0] as EstadoCloaca;
        _ranking = r[1] as RankingCloacas;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _avisar(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: TextoConEmojis(texto)));

  /// Corre una acción del servidor con el botón bloqueado y avisa si no se pudo.
  Future<ResultadoCloaca?> _hacer(Future<ResultadoCloaca> Function() accion) async {
    if (_ocupado) return null;
    setState(() => _ocupado = true);
    try {
      final r = await accion();
      if (!mounted) return r;
      if (!r.ok) _avisar(textoMotivoCloaca(r.motivo, texto: r.texto));
      return r;
    } catch (e) {
      if (mounted) _avisar(textoError(e));
      return null;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _crear() async {
    final datos = await showDialog<(String, String)>(context: context, builder: (_) => const _DialogoCrear());
    if (datos == null) return;
    final r = await _hacer(() => nubeCloacas.crear(datos.$1, datos.$2));
    if (r != null && r.ok) _avisar(tr('Cloaca creada. Invita a tu gente con el código ${r.codigo ?? ''}.', 'Sewer created. Invite your people with the code ${r.codigo ?? ''}.'));
  }

  Future<void> _unirme() async {
    final codigo = await showDialog<String>(context: context, builder: (_) => const _DialogoUnirse());
    if (codigo == null) return;
    final r = await _hacer(() => nubeCloacas.unirse(codigo));
    if (r != null && r.ok) _avisar(tr('Ya estás dentro. ¡A cagar por tu Cloaca!', 'You are in. Poop for your Sewer!'));
  }

  Future<void> _salir(Cloaca c) async {
    final solo = c.miembros.length <= 1;
    final ok = await _confirmar(
      tr('¿Salir de ${c.nombre}?', 'Leave ${c.nombre}?'),
      solo
          ? tr('Eres el último: la Cloaca y su chat se borran.', 'You are the last one: the Sewer and its chat are deleted.')
          : c.soyDueno
              ? tr('Tus puntos de la semana se quedan fuera. La Cloaca pasa al miembro más viejo.',
                  'Your points this week stay out. The Sewer goes to the oldest member.')
              : tr('Tus puntos de la semana se quedan fuera.', 'Your points this week stay out.'),
      tr('SALIR', 'LEAVE'),
    );
    if (ok) await _hacer(nubeCloacas.salir);
  }

  Future<void> _expulsar(MiembroCloaca m) async {
    final ok = await _confirmar(
      tr('¿Sacar a ${m.username}?', 'Remove ${m.username}?'),
      tr('No podrá volver a entrar en 7 días.', 'They will not be able to come back for 7 days.'),
      tr('SACAR', 'REMOVE'),
    );
    if (ok) await _hacer(() => nubeCloacas.expulsar(m.userId));
  }

  Future<bool> _confirmar(String titulo, String texto, String si) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: TextoConEmojis(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCELAR', 'CANCEL'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(si)),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final mia = _mia;
    final ranking = _ranking;
    if (mia == null || ranking == null) {
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Text(faltaFuncion(_error!) ? tr('Las Cloacas llegan pronto.', 'Sewers are coming soon.') : textoError(_error!), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _cargar, child: Text(tr('REINTENTAR', 'RETRY'))),
          ]),
        );
      }
      return const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: Cargando()));
    }
    final c = mia.cloaca;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c == null) _sinCloaca(mia) else _miCloaca(c, mia),
      const SizedBox(height: 16),
      _liga(ranking),
      const SizedBox(height: 16),
      _Explicacion(mia),
    ]);
  }

  Widget _sinCloaca(EstadoCloaca mia) {
    final p = paleta(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Emoji('🚽', tamano: 40),
        const SizedBox(height: 8),
        Text(tr('Aún no estás en una Cloaca', 'You are not in a Sewer yet'),
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          tr('Crea una con tu gente o entra con el código que te pasaron. Hasta ${mia.max} personas por Cloaca.',
              'Create one with your people or join with the code they gave you. Up to ${mia.max} people per Sewer.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textoSuave),
        ),
        if (mia.rollosPorCobrar > 0) ...[
          const SizedBox(height: 8),
          _premioPendiente(mia),
        ],
        const SizedBox(height: 12),
        FilledButton(key: const Key('cloaca_crear'), onPressed: _ocupado ? null : _crear, child: Text(tr('CREAR CLOACA', 'CREATE SEWER'))),
        const SizedBox(height: 8),
        OutlinedButton(key: const Key('cloaca_unirse'), onPressed: _ocupado ? null : _unirme, child: Text(tr('ENTRAR CON CÓDIGO', 'JOIN WITH CODE'))),
      ]),
    );
  }

  Widget _premioPendiente(EstadoCloaca mia) => TextoConEmojis(
        tr('🏆 Tienes ${mia.rollosPorCobrar} Rollos de Oro 🧻 por cobrar. Se cobran solos al abrir el Imperio.',
            '🏆 You have ${mia.rollosPorCobrar} Golden Rolls 🧻 to claim. They are claimed when you open the Empire.'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      );

  Widget _miCloaca(Cloaca c, EstadoCloaca mia) {
    final p = paleta(context);
    final yo = db.auth.currentUser?.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Emoji(c.emoji, tamano: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextoConEmojis(c.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(
                [
                  if (c.puesto != null) tr('Puesto ${c.puesto}', 'Place ${c.puesto}'),
                  tr('${c.puntos} puntos esta semana', '${c.puntos} points this week'),
                  '${c.miembros.length}/${mia.max}',
                ].join(' · '),
                style: TextStyle(color: p.textoSuave, fontSize: 13),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        // El bono de hoy: lo que más se nota en el Imperio.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: p.suave, borderRadius: BorderRadius.circular(radio)),
          child: TextoConEmojis(
            tr('🏭 Bono de hoy: ${textoBono(c.bono)} de producción en el Imperio (${c.cagaronHoy} de ${c.miembros.length} ya cagaron)',
                '🏭 Today\'s bonus: ${textoBono(c.bono)} production in the Empire (${c.cagaronHoy} of ${c.miembros.length} already pooped)'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (mia.rollosPorCobrar > 0) ...[
          const SizedBox(height: 8),
          _premioPendiente(mia),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(tr('Código: ${c.codigo}', 'Code: ${c.codigo}'),
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
          IconButton(
            tooltip: tr('Copiar código', 'Copy code'),
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: c.codigo));
              _avisar(tr('Código copiado', 'Code copied'));
            },
          ),
          FilledButton.tonal(
            key: const Key('cloaca_invitar'),
            onPressed: () => SharePlus.instance.share(ShareParams(text: textoInvitacion(c))),
            child: Text(tr('INVITAR', 'INVITE')),
          ),
        ]),
        const Divider(height: 20),
        for (final m in c.miembros)
          _FilaMiembro(
            m,
            yo: m.userId == yo,
            puedeSacar: c.soyDueno && m.userId != yo && !_ocupado,
            alSacar: () => _expulsar(m),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => ir('cloaca'),
              child: Text(tr('CHAT 💬', 'CHAT 💬')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('cloaca_salir'),
              onPressed: _ocupado ? null : () => _salir(c),
              child: Text(tr('SALIR', 'LEAVE')),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _liga(RankingCloacas r) {
    final p = paleta(context);
    final a = r.anterior;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(tr('LIGA DE LA SEMANA', 'WEEKLY LEAGUE'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.textoSuave)),
        ),
        const ContadorCierre(periodo: 'week'),
      ]),
      const SizedBox(height: 8),
      if (r.filas.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(tr('Todavía no hay Cloacas. ¡Crea la primera!', 'No Sewers yet. Create the first one!'),
              textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
        ),
      for (final f in r.filas) _FilaLiga(f),
      if (a != null) ...[
        const SizedBox(height: 8),
        TextoConEmojis(
          tr('🏆 La semana pasada ganó ${a.emoji} ${a.nombre} con ${a.puntos} puntos.',
              '🏆 Last week ${a.emoji} ${a.nombre} won with ${a.puntos} points.'),
          style: TextStyle(color: p.textoSuave),
        ),
      ],
    ]);
  }
}

class _FilaMiembro extends StatelessWidget {
  const _FilaMiembro(this.m, {required this.yo, required this.puedeSacar, required this.alSacar});

  final MiembroCloaca m;
  final bool yo, puedeSacar;
  final VoidCallback alSacar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: m.userId))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Avatar({'avatar': m.avatar ?? '💩', 'username': m.username}, tamano: 28, animarMovimiento: false),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextoConEmojis(
                '${m.username}${m.dueno ? ' 👑' : ''}${yo ? tr(' (tú)', ' (you)') : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextoConEmojis('💩 ${m.ptsCagadas} · 🏭 ${m.ptsImperio}${m.cagoHoy ? tr(' · ✅ cagó hoy', ' · ✅ pooped today') : ''}',
                  style: TextStyle(color: p.textoSuave, fontSize: 12)),
            ]),
          ),
          Text('${m.puntos}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (puedeSacar)
            IconButton(
              tooltip: tr('Sacar de la Cloaca', 'Remove from the Sewer'),
              icon: const Icon(Icons.person_remove_outlined, size: 20),
              onPressed: alSacar,
            ),
        ]),
      ),
    );
  }
}

class _FilaLiga extends StatelessWidget {
  const _FilaLiga(this.f);

  final FilaCloaca f;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.tarjeta,
        border: Border.all(color: f.mia ? acento : p.borde, width: f.mia ? 2 : 1),
        borderRadius: BorderRadius.circular(radio),
      ),
      child: Row(children: [
        SizedBox(
          width: 32,
          child: Text('${f.puesto}', style: TextStyle(fontWeight: FontWeight.w800, color: f.puesto == 1 ? acento : p.texto)),
        ),
        Emoji(f.emoji, tamano: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextoConEmojis(f.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(tr('${f.miembros} miembros', '${f.miembros} members'), style: TextStyle(color: p.textoSuave, fontSize: 12)),
          ]),
        ),
        Text(tr('${f.puntos} pts', '${f.puntos} pts'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Cómo funciona, en llano y con los números que manda el servidor.
class _Explicacion extends StatelessWidget {
  const _Explicacion(this.mia);

  final EstadoCloaca mia;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final lineas = [
      tr('🚽 Una Cloaca es un grupo de hasta ${mia.max} personas. Solo puedes estar en una.',
          '🚽 A Sewer is a group of up to ${mia.max} people. You can only be in one.'),
      tr('📅 Cada semana, de lunes a domingo, las Cloacas compiten por puntos.',
          '📅 Every week, Monday to Sunday, the Sewers compete for points.'),
      tr('💩 Cada cagada real da 10 puntos, hasta 3 por día por persona.', '💩 Each real poop gives 10 points, up to 3 a day per person.'),
      tr('🏭 El Imperio da hasta 10 puntos más por persona, según lo que produjiste en la semana.',
          '🏭 The Empire gives up to 10 more points per person, based on what you produced that week.'),
      tr('⏱️ Solo cuenta lo que hiciste estando dentro de la Cloaca.', '⏱️ Only what you did while in the Sewer counts.'),
      tr('🏆 La Cloaca que gana se lleva ${mia.premio} Rollos de Oro 🧻 para cada miembro y el ícono de Cloaca.',
          '🏆 The winning Sewer gets ${mia.premio} Golden Rolls 🧻 for each member and the Sewer icon.'),
      tr('⚡ Cada miembro que cagó hoy le da a todos ${textoBono(mia.bonoPor)} de producción en el Imperio, hasta ${textoBono(mia.bonoTope)}.',
          '⚡ Each member who pooped today gives everyone ${textoBono(mia.bonoPor)} production in the Empire, up to ${textoBono(mia.bonoTope)}.'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('¿CÓMO FUNCIONA?', 'HOW DOES IT WORK?'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.textoSuave)),
        const SizedBox(height: 6),
        for (final l in lineas) Padding(padding: const EdgeInsets.only(bottom: 4), child: TextoConEmojis(l)),
      ]),
    );
  }
}

class _DialogoCrear extends StatefulWidget {
  const _DialogoCrear();

  @override
  State<_DialogoCrear> createState() => _DialogoCrearState();
}

class _DialogoCrearState extends State<_DialogoCrear> {
  final _nombre = TextEditingController();
  String _emoji = emojisCloaca.first;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  bool get _valido => _nombre.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Nueva Cloaca', 'New Sewer')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('cloaca_nombre'),
            controller: _nombre,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Nombre', 'Name')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in emojisCloaca)
              InkWell(
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(color: e == _emoji ? acento : paleta(context).borde, width: e == _emoji ? 2 : 1),
                    borderRadius: BorderRadius.circular(radio),
                  ),
                  child: Emoji(e, tamano: 24),
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('CANCELAR', 'CANCEL'))),
          FilledButton(
            onPressed: _valido ? () => Navigator.pop(context, (_nombre.text.trim(), _emoji)) : null,
            child: Text(tr('CREAR', 'CREATE')),
          ),
        ],
      );
}

class _DialogoUnirse extends StatefulWidget {
  const _DialogoUnirse();

  @override
  State<_DialogoUnirse> createState() => _DialogoUnirseState();
}

class _DialogoUnirseState extends State<_DialogoUnirse> {
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final codigo = codigoDeTexto(_texto.text);
    return AlertDialog(
      title: Text(tr('Entrar a una Cloaca', 'Join a Sewer')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const Key('cloaca_codigo'),
          controller: _texto,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Código', 'Code'),
            helperText: tr('Escribe el código de 6 letras o pega la invitación entera.', 'Type the 6-letter code or paste the whole invitation.'),
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (codigo != null && codigo != _texto.text.trim()) ...[
          const SizedBox(height: 8),
          Text(tr('Código: $codigo', 'Code: $codigo'), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('CANCELAR', 'CANCEL'))),
        FilledButton(onPressed: codigo == null ? null : () => Navigator.pop(context, codigo), child: Text(tr('ENTRAR', 'JOIN'))),
      ],
    );
  }
}

/// La pestaña CLOACA del baño: el chat de mi Cloaca, o cómo entrar a una.
class PestanaCloaca extends StatefulWidget {
  const PestanaCloaca({super.key});

  @override
  State<PestanaCloaca> createState() => _PestanaCloacaState();
}

class _PestanaCloacaState extends State<PestanaCloaca> {
  EstadoCloaca? _mia;
  bool _fallo = false;

  @override
  void initState() {
    super.initState();
    cloacaCambio.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    cloacaCambio.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final m = await nubeCloacas.mia();
      if (mounted) {
        setState(() {
          _mia = m;
          _fallo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fallo = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _mia?.cloaca;
    if (c != null) return Sala(key: ValueKey(c.sala), sala: c.sala);
    if (_mia == null && !_fallo) return const Center(child: Cargando());
    final p = paleta(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Emoji('🚽', tamano: 48),
          const SizedBox(height: 12),
          Text(
            _fallo
                ? tr('No se pudo abrir el chat de tu Cloaca.', 'Could not open your Sewer chat.')
                : tr('Este es el chat de tu Cloaca. Solo lo ven sus miembros.', 'This is your Sewer chat. Only its members can see it.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (!_fallo) ...[
            const SizedBox(height: 4),
            Text(tr('Aún no estás en una Cloaca.', 'You are not in a Sewer yet.'), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _fallo ? _cargar : verCloacas,
            child: Text(_fallo ? tr('REINTENTAR', 'RETRY') : tr('VER CLOACAS', 'SEE SEWERS')),
          ),
        ]),
      ),
    );
  }
}

/// Tarjeta del chat general cuando una Cloaca gana la liga de la semana (la arma el servidor).
class TarjetaCloaca extends StatelessWidget {
  const TarjetaCloaca(this.t, {super.key});

  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final emoji = '${t['emoji'] ?? ''}'.trim();
    final nombre = '${t['nombre'] ?? ''}'.trim();
    final puntos = _ent(t['puntos']);
    final rollos = _ent(t['rollos']);
    return InkWell(
      onTap: verCloacas,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Emoji(emoji.isEmpty ? '💩' : emoji, tamano: 32),
          const SizedBox(width: 10),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextoConEmojis(tr('🏆 LIGA DE CLOACAS', '🏆 SEWER LEAGUE'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.textoSuave)),
              const SizedBox(height: 2),
              TextoConEmojis(tr('$nombre ganó la semana con $puntos puntos', '$nombre won the week with $puntos points'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (rollos > 0)
                TextoConEmojis(tr('$rollos Rollos de Oro 🧻 para cada miembro', '$rollos Golden Rolls 🧻 for each member'),
                    style: TextStyle(color: p.textoSuave, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
