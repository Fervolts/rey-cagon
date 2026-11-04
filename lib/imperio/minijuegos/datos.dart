// Minijuegos de la Sala: lo que responde el servidor (migración minijuegos: imperio_minijuego, imperio_minijuegos_resumen
// y imperio_minijuego_ranking) y la cuenta del premio. El servidor decide los minutos; la app los suma como un regalo
// (Imperio.abrirRegalo). Aquí también está la misma cuenta del premio para avisar "así te va" antes de que conteste.

import '../../idioma.dart';
import '../../main.dart' show conReintento, db;
import 'estadisticas.dart';

int _ent(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Valores de respaldo si el servidor no contesta (flags `minijuego_*`).
const int minutosMaxDefecto = 10;
const int minutosDiaDefecto = 30;
const int partidasDiaDefecto = 20;

/// Puntos que dan el premio completo en cada juego (flag `minijuego_meta_*`).
const Map<String, int> metasDefecto = {'tuberia': 600, 'destapa': 60, 'memoria': 1800};

/// Cuenta del servidor: la mitad de la meta da la mitad del premio, mínimo 1 minuto si hiciste algún punto.
/// [restanHoy] es lo que queda del tope del día; nunca da más.
int minutosDePartida({required int puntos, required int meta, int maximo = minutosMaxDefecto, int restanHoy = minutosDiaDefecto}) {
  if (puntos <= 0 || meta <= 0 || maximo <= 0 || restanHoy <= 0) return 0;
  final frac = puntos >= meta ? 1.0 : puntos / meta;
  final m = (maximo * frac).ceil().clamp(1, maximo);
  return m < restanHoy ? m : restanHoy;
}

/// Lo que cuenta el servidor de un juego.
class ResumenJuego {
  final int record, partidas, semana;
  const ResumenJuego({this.record = 0, this.partidas = 0, this.semana = 0});
}

/// Resumen de la Sala: topes, lo ganado hoy y lo de cada juego (RPC `imperio_minijuegos_resumen`).
class ResumenMinijuegos {
  final bool activo;
  final int minutosMax, topeDia, topePartidas, ganadosHoy, partidasHoy;
  final Map<String, ResumenJuego> juegos;
  const ResumenMinijuegos({
    this.activo = true,
    this.minutosMax = minutosMaxDefecto,
    this.topeDia = minutosDiaDefecto,
    this.topePartidas = partidasDiaDefecto,
    this.ganadosHoy = 0,
    this.partidasHoy = 0,
    this.juegos = const {},
  });

  factory ResumenMinijuegos.desdeJson(Map<String, dynamic> j) {
    final js = <String, ResumenJuego>{};
    final raw = j['juegos'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) js['$k'] = ResumenJuego(record: _ent(v['record']), partidas: _ent(v['partidas']), semana: _ent(v['semana']));
      });
    }
    return ResumenMinijuegos(
      activo: j['activo'] != false,
      minutosMax: _ent(j['minutos_max']).clamp(1, 30),
      topeDia: _ent(j['tope_dia']).clamp(1, 120),
      topePartidas: _ent(j['tope_partidas']).clamp(1, 60),
      ganadosHoy: _ent(j['ganados_hoy']),
      partidasHoy: _ent(j['partidas_hoy']),
      juegos: js,
    );
  }

  /// Minutos que todavía caben hoy.
  int get restanHoy => (topeDia - ganadosHoy).clamp(0, topeDia);

  /// Lo máximo que puede dar una partida ahora mismo (0 si ya no hay premio hoy).
  int get puedeDarHoy => !activo || partidasHoy >= topePartidas ? 0 : (restanHoy < minutosMax ? restanHoy : minutosMax);

  ResumenMinijuegos trasPartida(String juego, ResultadoMinijuego r) {
    final ant = juegos[juego] ?? const ResumenJuego();
    final nuevos = Map<String, ResumenJuego>.from(juegos)
      ..[juego] = ResumenJuego(
        record: r.record > ant.record ? r.record : ant.record,
        partidas: ant.partidas + 1,
        semana: r.puntos > ant.semana ? r.puntos : ant.semana,
      );
    return ResumenMinijuegos(
      activo: activo,
      minutosMax: minutosMax,
      topeDia: r.topeDia > 0 ? r.topeDia : topeDia,
      topePartidas: r.topePartidas > 0 ? r.topePartidas : topePartidas,
      ganadosHoy: r.ganadosHoy > 0 ? r.ganadosHoy : ganadosHoy,
      partidasHoy: r.partidasHoy > 0 ? r.partidasHoy : partidasHoy + 1,
      juegos: nuevos,
    );
  }

  /// Pasa lo del servidor al global que leen los logros.
  void alGlobal() {
    estadisticasMinijuegos
      ..clear()
      ..addAll({for (final e in juegos.entries) e.key: EstadisticaJuego(record: e.value.record, partidas: e.value.partidas, semana: e.value.semana)});
  }
}

/// Lo que contesta `imperio_minijuego`.
class ResultadoMinijuego {
  final bool ok;
  final String? motivo;
  final int minutos, puntos, record, ganadosHoy, topeDia, partidasHoy, topePartidas;
  final bool nuevoRecord;
  const ResultadoMinijuego({
    required this.ok,
    this.motivo,
    this.minutos = 0,
    this.puntos = 0,
    this.record = 0,
    this.nuevoRecord = false,
    this.ganadosHoy = 0,
    this.topeDia = 0,
    this.partidasHoy = 0,
    this.topePartidas = 0,
  });

  factory ResultadoMinijuego.desdeJson(Map<String, dynamic> j) => ResultadoMinijuego(
        ok: j['ok'] == true,
        motivo: j['motivo'] as String?,
        minutos: _ent(j['minutos']),
        puntos: _ent(j['puntos']),
        record: _ent(j['record']),
        nuevoRecord: j['nuevo_record'] == true,
        ganadosHoy: _ent(j['ganados_hoy']),
        topeDia: _ent(j['tope_dia']),
        partidasHoy: _ent(j['partidas_hoy']),
        topePartidas: _ent(j['tope_partidas']),
      );

  /// Resultado local cuando no hubo respuesta (sin red): no hay premio.
  const ResultadoMinijuego.sinRed(int puntos) : this(ok: false, motivo: 'sin_red', puntos: puntos);
}

/// Texto llano de por qué no hubo premio (null si todo bien).
String? textoMotivoMinijuego(String? motivo) => switch (motivo) {
      null => null,
      'apagado' => tr('Los minijuegos están en pausa por ahora.', 'Minigames are paused for now.'),
      'tope_partidas' => tr('Ya jugaste las partidas con premio de hoy. Mañana vuelven.', "You've played today's prize games. They're back tomorrow."),
      'invalida' => tr('Esa partida no se pudo comprobar, así que no cuenta.', "That game couldn't be verified, so it doesn't count."),
      'sin_red' => tr('Sin conexión: esta partida no se guardó ni dio premio.', "No connection: this game wasn't saved and gave no prize."),
      _ => tr('No se pudo dar el premio.', "The prize couldn't be given."),
    };

/// Una fila del ranking semanal.
class FilaRankingMinijuego {
  final String userId, username, avatar;
  final int puntos, puesto;
  final bool yo;
  const FilaRankingMinijuego({required this.userId, required this.username, required this.avatar, required this.puntos, required this.puesto, required this.yo});

  factory FilaRankingMinijuego.desdeJson(Map<String, dynamic> j) => FilaRankingMinijuego(
        userId: '${j['user_id']}',
        username: '${j['username'] ?? '?'}',
        avatar: '${j['avatar'] ?? '💩'}',
        puntos: _ent(j['puntos']),
        puesto: _ent(j['puesto']),
        yo: j['yo'] == true,
      );
}

/// Las llamadas al servidor. Se sobrescribe en los tests.
class NubeMinijuegos {
  const NubeMinijuegos();

  Future<ResumenMinijuegos> resumen() async {
    final r = await conReintento(() => db.rpc('imperio_minijuegos_resumen'));
    return ResumenMinijuegos.desdeJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  /// Sin reintento: repetirla guardaría dos partidas.
  Future<ResultadoMinijuego> guardar(String juego, int puntos, int duracionMs) async {
    final r = await db.rpc('imperio_minijuego', params: {'p_juego': juego, 'p_puntos': puntos, 'p_duracion_ms': duracionMs});
    return ResultadoMinijuego.desdeJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<List<FilaRankingMinijuego>> ranking(String juego, String alcance) async {
    final r = await conReintento(() => db.rpc('imperio_minijuego_ranking', params: {'p_juego': juego, 'p_alcance': alcance}));
    if (r is! List) return const [];
    return [for (final f in r) if (f is Map) FilaRankingMinijuego.desdeJson(Map<String, dynamic>.from(f))];
  }
}
