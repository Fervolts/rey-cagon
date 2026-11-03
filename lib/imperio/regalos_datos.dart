// Regalos 🎁: un Rollo de papel 🧻 de regalo al día por amigo (seguirse los dos). Lo valida y lo cuenta todo el servidor
// (migración imperio_regalos: amistad, 1 por pareja por día de Caracas, topes de enviar y abrir, abrir una sola vez).
// Aquí: lo que responde el servidor, los topes para pintar los botones y los textos de los motivos.
// Los MJ de abrirlo los calcula el motor (`Imperio.mjDeRegalo`): N minutos de la producción propia, como la Lluvia.

import '../idioma.dart';
import '../main.dart' show conReintento, db;

int _ent(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime _fecha(Object? v) => DateTime.tryParse('$v')?.toUtc() ?? DateTime.now().toUtc();

/// Minutos de producción que da un Rollo si el servidor no dice otra cosa (flag `regalos_minutos`).
const int minutosRegaloDefecto = 30;

/// Topes por día si el servidor no dice otra cosa (flags `regalos_envios_dia` y `regalos_recibidos_dia`).
const int topeRegalosDefecto = 5;

/// Un Rollo por abrir.
class Regalo {
  final String id;
  final String de;
  final String deNombre;
  final DateTime creado;
  const Regalo({required this.id, required this.de, required this.deNombre, required this.creado});

  factory Regalo.desdeJson(Map<String, dynamic> j) =>
      Regalo(id: '${j['id']}', de: '${j['de']}', deNombre: '${j['de_nombre'] ?? '?'}', creado: _fecha(j['creado']));
}

/// Lo que tengo por abrir y cómo van los topes de hoy (RPC `imperio_regalos_pendientes`).
class EstadoRegalos {
  final bool activo;
  final int minutos;
  final int topeAbrir;
  final int topeEnvios;
  final int abiertosHoy;
  final int enviadosHoy;

  /// A quiénes ya les regalé hoy (día de Caracas).
  final Set<String> regaladosHoy;

  /// Cuántos he regalado en total (para los logros).
  final int dados;
  final List<Regalo> regalos;

  const EstadoRegalos({
    this.activo = true,
    this.minutos = minutosRegaloDefecto,
    this.topeAbrir = topeRegalosDefecto,
    this.topeEnvios = topeRegalosDefecto,
    this.abiertosHoy = 0,
    this.enviadosHoy = 0,
    this.regaladosHoy = const {},
    this.dados = 0,
    this.regalos = const [],
  });

  factory EstadoRegalos.desdeJson(Map<String, dynamic> j) => EstadoRegalos(
        activo: j['activo'] != false,
        minutos: j['minutos'] == null ? minutosRegaloDefecto : _ent(j['minutos']).clamp(1, 60),
        topeAbrir: j['tope_abrir'] == null ? topeRegalosDefecto : _ent(j['tope_abrir']).clamp(1, 10),
        topeEnvios: j['tope_envios'] == null ? topeRegalosDefecto : _ent(j['tope_envios']).clamp(1, 10),
        abiertosHoy: _ent(j['abiertos_hoy']),
        enviadosHoy: _ent(j['enviados_hoy']),
        regaladosHoy: {for (final u in (j['regalados_hoy'] as List? ?? const [])) '$u'},
        dados: _ent(j['dados']),
        regalos: [for (final r in (j['regalos'] as List? ?? const [])) if (r is Map) Regalo.desdeJson(Map<String, dynamic>.from(r))],
      );

  /// Cuántos puedo abrir todavía hoy.
  int get abrirQuedan => (topeAbrir - abiertosHoy).clamp(0, topeAbrir);

  /// Cuántos puedo regalar todavía hoy.
  int get enviosQuedan => (topeEnvios - enviadosHoy).clamp(0, topeEnvios);

  bool get puedeAbrir => activo && abrirQuedan > 0 && regalos.isNotEmpty;

  /// Si el botón REGALAR a [amigo] sale encendido. El servidor decide de verdad (amistad, bloqueos).
  bool puedeRegalarA(String amigo) => activo && enviosQuedan > 0 && !regaladosHoy.contains(amigo);

  /// Copia con el Rollo [id] ya abierto (cuenta para el tope de hoy).
  EstadoRegalos trasAbrir(String id) => _copia(abiertosHoy: abiertosHoy + 1, regalos: [for (final r in regalos) if (r.id != id) r]);

  /// Copia sin el Rollo [id] (ya no se puede abrir), sin contarlo.
  EstadoRegalos sinRegalo(String id) => _copia(regalos: [for (final r in regalos) if (r.id != id) r]);

  /// Copia con el regalo a [amigo] ya hecho; [dadosServidor] es el total que contó el servidor.
  EstadoRegalos trasRegalar(String amigo, int dadosServidor) =>
      _copia(enviadosHoy: enviadosHoy + 1, regaladosHoy: {...regaladosHoy, amigo}, dados: dadosServidor > dados ? dadosServidor : dados + 1);

  EstadoRegalos _copia({int? abiertosHoy, int? enviadosHoy, Set<String>? regaladosHoy, int? dados, List<Regalo>? regalos}) => EstadoRegalos(
        activo: activo,
        minutos: minutos,
        topeAbrir: topeAbrir,
        topeEnvios: topeEnvios,
        abiertosHoy: abiertosHoy ?? this.abiertosHoy,
        enviadosHoy: enviadosHoy ?? this.enviadosHoy,
        regaladosHoy: regaladosHoy ?? this.regaladosHoy,
        dados: dados ?? this.dados,
        regalos: regalos ?? this.regalos,
      );
}

/// Respuesta de `imperio_regalar` o `imperio_regalo_abrir`. Si no es [ok], [motivo] dice por qué.
class ResultadoRegalo {
  final bool ok;
  final String? motivo;
  final String? id;
  final int minutos;
  final bool mutuo;
  final bool enChat;
  final int dados;
  const ResultadoRegalo({required this.ok, this.motivo, this.id, this.minutos = 0, this.mutuo = false, this.enChat = false, this.dados = 0});

  factory ResultadoRegalo.desdeJson(Object? r) {
    final j = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
    return ResultadoRegalo(
      ok: j['ok'] == true,
      motivo: j['motivo'] as String?,
      id: j['id']?.toString(),
      minutos: _ent(j['minutos']).clamp(0, 60),
      mutuo: j['mutuo'] == true,
      enChat: j['en_chat'] == true,
      dados: _ent(j['dados']),
    );
  }
}

/// Texto para la gente de cada motivo del servidor.
String textoMotivoRegalo(String? motivo) => switch (motivo) {
      'no_amigos' => tr('Solo se regala entre amigos: tienen que seguirse los dos.', 'Gifts are for friends only: you both have to follow each other.'),
      'ya_hoy' => tr('Hoy ya le regalaste. Mañana otro.', 'You already gifted them today. Another one tomorrow.'),
      'tope_envios' => tr('Ya regalaste todos los Rollos de hoy.', 'You gave away all of today\'s Rolls.'),
      'tope_recibidos' => tr('Hoy ya le llegaron muchos Rollos. Prueba mañana.', 'They got plenty of Rolls today. Try tomorrow.'),
      'tope_abrir' => tr('Ya abriste todos los Rollos de hoy. Los demás esperan a mañana.', 'You opened all of today\'s Rolls. The rest wait until tomorrow.'),
      'ya_abierto' => tr('Ese Rollo ya estaba abierto.', 'That Roll was already open.'),
      'vencido' => tr('Ese Rollo se venció.', 'That Roll expired.'),
      'no_existe' => tr('Ese Rollo no es tuyo o ya no existe.', 'That Roll isn\'t yours or no longer exists.'),
      'apagado' => tr('Los regalos están apagados por ahora.', 'Gifts are turned off for now.'),
      _ => tr('No se pudo. Prueba otra vez.', 'It didn\'t work. Try again.'),
    };

/// Las llamadas al servidor. En las pruebas se cambia por una falsa.
class NubeRegalos {
  const NubeRegalos();

  Future<EstadoRegalos> pendientes() async {
    final r = await conReintento(() => db.rpc('imperio_regalos_pendientes'));
    return EstadoRegalos.desdeJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  /// Sin reintento: si la respuesta se pierde, el servidor responde `ya_hoy` a la segunda.
  Future<ResultadoRegalo> regalar(String para) async => ResultadoRegalo.desdeJson(await db.rpc('imperio_regalar', params: {'p_para': para}));

  /// Sin reintento: si la respuesta se pierde, el Rollo queda abierto en el servidor y se ve como `ya_abierto`.
  Future<ResultadoRegalo> abrir(String id) async => ResultadoRegalo.desdeJson(await db.rpc('imperio_regalo_abrir', params: {'p_id': id}));

  /// Si [id] es para mí y sigue sin abrir (la tarjeta del chat). null si no se pudo saber.
  Future<bool?> sinAbrir(String id) async {
    final r = await db.from('imperio_regalos').select('abierto').eq('id', id).maybeSingle();
    if (r == null) return null;
    return r['abierto'] == null;
  }
}
