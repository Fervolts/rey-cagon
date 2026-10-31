// Estado guardable del Imperio Cagón. Dart puro: se serializa a JSON para la nube (`imperio_guardar`).
// Las cagadas totales y las Fichas NO van aquí: las manda el servidor y las pone el controlador en `Imperio`.

double _dbl(Object? v, [double d = 0]) {
  final r = v is num ? v.toDouble() : double.tryParse('$v');
  return r == null || r.isNaN || r.isInfinite ? d : r;
}

int _ent(Object? v, [int d = 0]) => v is num ? (v.isFinite ? v.toInt() : d) : int.tryParse('$v') ?? d;
int? _entN(Object? v) => v == null ? null : (v is num ? (v.isFinite ? v.toInt() : null) : int.tryParse('$v'));
bool _bool(Object? v) => v == true || v == 1 || v == 'true';

Map<String, int> _mapaEnt(Object? v) {
  if (v is! Map) return {};
  return {for (final e in v.entries) '${e.key}': _ent(e.value)};
}

Set<String> _conjunto(Object? v) => v is List ? {for (final x in v) '$x'} : <String>{};

/// Atasco en un edificio: produce 0 hasta 10 toques.
class Atasco {
  final String edificio;

  /// Desde cuándo se ve (ms epoch). Para el "Destape perfecto" (< 3 s).
  int desde;
  int toques;
  Atasco(this.edificio, this.desde, [this.toques = 0]);

  Map<String, dynamic> toJson() => {'e': edificio, 'd': desde, 't': toques};

  static Atasco? desdeJson(Object? v) {
    if (v is! Map || v['e'] == null) return null;
    return Atasco('${v['e']}', _ent(v['d']), _ent(v['t']));
  }
}

/// Mojón dorado en pantalla. `x` e `y` van de 0 a 1 (posición relativa en la zona de juego).
class DoradoVisible {
  final int desde, hasta;
  final double x, y;
  const DoradoVisible(this.desde, this.hasta, this.x, this.y);

  Map<String, dynamic> toJson() => {'d': desde, 'h': hasta, 'x': x, 'y': y};

  static DoradoVisible? desdeJson(Object? v) {
    if (v is! Map) return null;
    return DoradoVisible(_ent(v['d']), _ent(v['h']), _dbl(v['x'], 0.5), _dbl(v['y'], 0.5));
  }
}

/// Partida guardable. Todos los tiempos en ms epoch del reloj del servidor.
class Partida {
  static const int version = 1;

  /// Cuántos pujos recientes se guardan para el logro Nalgazo.
  static const int maxPujosRecientes = 100;

  double saldo;

  /// MJ ganados en la vida. Nunca baja.
  double mjTotal;

  /// Cantidad por id de edificio.
  Map<String, int> edificios;
  Set<String> mejoras;
  Set<String> logros;

  // Contadores
  int pujos, epicos, dorados, destapes, destapesPerfectos, descargas;

  /// Descargas abiertas con la Fiebre de un mojón dorado activa.
  int enFiebre;

  /// Veces que hizo 100 pujos en 10 s.
  int nalgazos;

  /// Consumibles guardados por id de objeto.
  Map<String, int> inventario;

  /// Efectos temporales: id → fin (ms). Ids: fiebre_dorada, fiebre_trono, pujo_loco, constructor, cagada_fresca, ambientador, laxante.
  Map<String, int> efectos;

  /// Esperas: id de objeto → cuándo se puede volver a usar/alquilar (ms).
  Map<String, int> esperas;

  /// Fin del alquiler del Robot destapador (ms). 0 = nunca.
  int robotHasta;

  Atasco? atasco;
  bool vioPrimerAtasco;

  /// Segundos de juego activo que faltan para el próximo mojón dorado. Negativo = sin programar.
  double segHastaDorado;
  DoradoVisible? dorado;

  /// Papel doble hoja usado: el próximo dorado da el doble.
  bool papelDoble;

  /// Buff del tipo de la última cagada real (1 a 7) y su fin (ms).
  int? tipoBuff;
  int tipoBuffHasta;

  /// Tipo 6: el próximo offline cuenta x1,5.
  bool offlineBonus;

  /// Última vez que se vio la partida (ms, reloj del servidor).
  int ultimaVez;

  /// Momentos (ms) de los últimos pujos, el más viejo primero.
  List<int> pujosRecientes;

  /// Segundos de juego activo de esta partida (solo `tick`, no el tiempo offline).
  double segPartida;

  Partida({
    this.saldo = 0,
    this.mjTotal = 0,
    Map<String, int>? edificios,
    Set<String>? mejoras,
    Set<String>? logros,
    this.pujos = 0,
    this.epicos = 0,
    this.dorados = 0,
    this.destapes = 0,
    this.destapesPerfectos = 0,
    this.descargas = 0,
    this.enFiebre = 0,
    this.nalgazos = 0,
    Map<String, int>? inventario,
    Map<String, int>? efectos,
    Map<String, int>? esperas,
    this.robotHasta = 0,
    this.atasco,
    this.vioPrimerAtasco = false,
    this.segHastaDorado = -1,
    this.dorado,
    this.papelDoble = false,
    this.tipoBuff,
    this.tipoBuffHasta = 0,
    this.offlineBonus = false,
    this.ultimaVez = 0,
    List<int>? pujosRecientes,
    this.segPartida = 0,
  })  : edificios = edificios ?? {},
        mejoras = mejoras ?? {},
        logros = logros ?? {},
        inventario = inventario ?? {},
        efectos = efectos ?? {},
        esperas = esperas ?? {},
        pujosRecientes = pujosRecientes ?? [];

  Map<String, dynamic> toJson() => {
        'v': version,
        'saldo': saldo,
        'mj_total': mjTotal,
        'edificios': edificios,
        'mejoras': mejoras.toList(),
        'logros': logros.toList(),
        'pujos': pujos,
        'epicos': epicos,
        'dorados': dorados,
        'destapes': destapes,
        'perfectos': destapesPerfectos,
        'descargas': descargas,
        'en_fiebre': enFiebre,
        'nalgazos': nalgazos,
        'inventario': inventario,
        'efectos': efectos,
        'esperas': esperas,
        'robot_hasta': robotHasta,
        'atasco': atasco?.toJson(),
        'vio_atasco': vioPrimerAtasco,
        'seg_dorado': segHastaDorado,
        'dorado': dorado?.toJson(),
        'papel_doble': papelDoble,
        'tipo_buff': tipoBuff,
        'tipo_buff_hasta': tipoBuffHasta,
        'offline_bonus': offlineBonus,
        'ultima_vez': ultimaVez,
        'pujos_recientes': pujosRecientes,
        'seg_partida': segPartida,
      };

  /// Lee una partida guardada. Aguanta claves que faltan, sobran o vienen con otro tipo.
  factory Partida.desdeJson(Map<String, dynamic>? j) {
    if (j == null) return Partida();
    final saldo = _dbl(j['saldo']);
    final total = _dbl(j['mj_total']);
    final recientes = j['pujos_recientes'] is List ? [for (final x in j['pujos_recientes'] as List) _ent(x)] : <int>[];
    final tipo = _entN(j['tipo_buff']);
    final segPartida = _dbl(j['seg_partida']);
    return Partida(
      saldo: saldo < 0 ? 0 : saldo,
      mjTotal: total < saldo ? saldo : total,
      edificios: _mapaEnt(j['edificios'])..removeWhere((_, n) => n <= 0),
      mejoras: _conjunto(j['mejoras']),
      logros: _conjunto(j['logros']),
      pujos: _ent(j['pujos']),
      epicos: _ent(j['epicos']),
      dorados: _ent(j['dorados']),
      destapes: _ent(j['destapes']),
      destapesPerfectos: _ent(j['perfectos']),
      descargas: _ent(j['descargas']),
      enFiebre: _ent(j['en_fiebre']),
      nalgazos: _ent(j['nalgazos']),
      inventario: _mapaEnt(j['inventario'])..removeWhere((_, n) => n <= 0),
      efectos: _mapaEnt(j['efectos']),
      esperas: _mapaEnt(j['esperas']),
      robotHasta: _ent(j['robot_hasta']),
      atasco: Atasco.desdeJson(j['atasco']),
      vioPrimerAtasco: _bool(j['vio_atasco']),
      segHastaDorado: _dbl(j['seg_dorado'], -1),
      dorado: DoradoVisible.desdeJson(j['dorado']),
      papelDoble: _bool(j['papel_doble']),
      tipoBuff: tipo != null && tipo >= 1 && tipo <= 7 ? tipo : null,
      tipoBuffHasta: _ent(j['tipo_buff_hasta']),
      offlineBonus: _bool(j['offline_bonus']),
      ultimaVez: _ent(j['ultima_vez']),
      pujosRecientes: recientes.length > maxPujosRecientes ? recientes.sublist(recientes.length - maxPujosRecientes) : recientes,
      segPartida: segPartida < 0 ? 0 : segPartida,
    );
  }
}
