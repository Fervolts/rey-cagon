// Estado guardable del Imperio Cagón. Dart puro: se serializa a JSON para la nube (`imperio_guardar`).
// Las cagadas totales y las Fichas NO van aquí: las manda el servidor y las pone el controlador en `Imperio`.

import 'dart:math';

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

/// Preferencias de vista del baño: solo las claves conocidas y con su tipo.
Map<String, dynamic> _vista(Object? v) {
  if (v is! Map) return {};
  final r = <String, dynamic>{};
  if (v['ocultos'] is List) r['ocultos'] = [for (final x in v['ocultos'] as List) '$x'];
  final d = _entN(v['dedos']);
  if (d != null) r['dedos'] = d.clamp(0, 24);
  if (v['ambiente'] is String) r['ambiente'] = v['ambiente'];
  return r;
}

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

  /// Alquilados: id de objeto → fin del alquiler (ms). El Robot viejo (`robot_hasta`) vive aquí como 'robot'.
  Map<String, int> alquilados;

  /// Fin del alquiler del Robot destapador (ms). 0 = nunca. Atajo a `alquilados['robot']`.
  int get robotHasta => alquilados['robot'] ?? 0;
  set robotHasta(int v) => v > 0 ? alquilados['robot'] = v : alquilados.remove('robot');

  /// Maná de Tripa (0 a 100) y cuándo se calculó por última vez (ms).
  double mana;
  int manaEn;

  // Contadores de la fase 2 (logros).
  int habilidades, chorrosFallidos, consumiblesUsados;

  /// Ids de alquilables alquilados alguna vez.
  Set<String> alquiladosUsados;

  /// Edificios con Pintura marrón (+10% c/u). Se borra al jalar la cadena.
  Set<String> pintura;

  /// Objetos de Rollos de Oro: 'super_plomero' (0/1), 'tanque_lujo' (0 a 6), 'cadena_reserva' (1 = pendiente). No se borran al jalar.
  Map<String, int> objetosRollos;

  /// Veces que se tocó cada cosa del baño en la Poceta (id de [objetosTocables]), para los logros escondidos.
  /// No se borra al jalar.
  Map<String, int> toques;

  /// Temporadas (id de lib/imperio/temporadas.dart) en las que se jugó con la app abierta. Las anota `tick` y abren
  /// logros exclusivos (`dia_retrete`). No se borra al jalar.
  Set<String> temporadas;

  /// Última compra de la Cadena de reserva (ms), para el límite semanal.
  int cadenaReservaEn;

  /// Día real (días desde epoch, UTC) del último regalo del Súper Plomero.
  int superPlomeroDia;

  /// Cofres del Trono abiertos, semanas seguidas con cofre y Congeladores gastados (los escribe el carril de la nube).
  int cofres, semanasRacha, congeladosUsados;

  /// Horas de más en el tope offline pagadas con Fichas (Tanque extra, 0 o 1). No se borra al jalar.
  int horasExtraTanque;

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

  /// Segundos de juego activo de esta partida (solo `tick`, no el tiempo offline). Jalar la cadena lo pone en 0.
  double segPartida;

  /// Rollos de Oro ganados jalando la cadena. No se pierden nunca.
  int rollos;

  /// Rollos gastados en objetos de Rollos. Cuentan como ya ganados: jalar no los devuelve.
  int rollosGastados;

  /// Todos los Rollos que se ganaron (los que quedan más los gastados): abren edificios, mejoras y logros.
  int get rollosGanados => rollos + rollosGastados;

  /// Cagadas de candado compradas con MJ (`Imperio.pagarCandado`). Cuentan para los candados, como mucho la mitad de lo
  /// que pide cada uno. Jalar la cadena no las quita.
  int cagadasPagadas;

  /// Segundos activos de todas las partidas (jalar no los borra) y el primer momento en que se jugó (ms, 0 = nunca).
  /// Dicen si juega poco (tope offline más largo).
  double segHistoricos;
  int primerDia;

  /// Veces que se jaló la cadena (el servidor lleva la cuenta buena en `imperio.jaladas`).
  int jaladas;

  /// Cómo se ve el baño (Personalizar): 'ocultos' (lista de ids), 'dedos' (int), 'ambiente' (nombre). Solo visual.
  Map<String, dynamic> vista;

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
    int robotHasta = 0,
    Map<String, int>? alquilados,
    this.mana = 0,
    this.manaEn = 0,
    this.habilidades = 0,
    this.chorrosFallidos = 0,
    this.consumiblesUsados = 0,
    Set<String>? alquiladosUsados,
    Set<String>? pintura,
    Map<String, int>? objetosRollos,
    Map<String, int>? toques,
    Set<String>? temporadas,
    this.cadenaReservaEn = 0,
    this.superPlomeroDia = 0,
    this.cofres = 0,
    this.semanasRacha = 0,
    this.congeladosUsados = 0,
    this.horasExtraTanque = 0,
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
    this.rollos = 0,
    this.rollosGastados = 0,
    this.cagadasPagadas = 0,
    this.segHistoricos = 0,
    this.primerDia = 0,
    this.jaladas = 0,
    Map<String, dynamic>? vista,
  })  : vista = vista ?? {},
        edificios = edificios ?? {},
        mejoras = mejoras ?? {},
        logros = logros ?? {},
        inventario = inventario ?? {},
        efectos = efectos ?? {},
        esperas = esperas ?? {},
        pujosRecientes = pujosRecientes ?? [],
        alquilados = alquilados ?? {},
        alquiladosUsados = alquiladosUsados ?? {},
        pintura = pintura ?? {},
        objetosRollos = objetosRollos ?? {},
        toques = toques ?? {},
        temporadas = temporadas ?? {} {
    // El robot viejo pasa al mapa; si ya está en el mapa gana el fin más tarde.
    if (robotHasta > (this.alquilados['robot'] ?? 0)) this.alquilados['robot'] = robotHasta;
  }

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
        'alquilados': alquilados,
        'mana': mana,
        'mana_en': manaEn,
        'habilidades': habilidades,
        'chorros_fallidos': chorrosFallidos,
        'consumibles_usados': consumiblesUsados,
        'alquilados_usados': alquiladosUsados.toList(),
        'pintura': pintura.toList(),
        'objetos_rollos': objetosRollos,
        'toques': toques,
        if (temporadas.isNotEmpty) 'temporadas': temporadas.toList(),
        'cadena_reserva_en': cadenaReservaEn,
        'super_plomero_dia': superPlomeroDia,
        'cofres': cofres,
        'semanas_racha': semanasRacha,
        'congelados_usados': congeladosUsados,
        'horas_extra_tanque': horasExtraTanque,
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
        'rollos': rollos,
        'rollos_gastados': rollosGastados,
        'cagadas_pagadas': cagadasPagadas,
        'seg_historicos': segHistoricos,
        'primer_dia': primerDia,
        'jaladas': jaladas,
        if (vista.isNotEmpty) 'vista': vista,
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
      alquilados: _mapaEnt(j['alquilados'])..removeWhere((_, n) => n <= 0),
      mana: _dbl(j['mana']).clamp(0, 100).toDouble(),
      manaEn: _ent(j['mana_en']),
      habilidades: max(0, _ent(j['habilidades'])),
      chorrosFallidos: max(0, _ent(j['chorros_fallidos'])),
      consumiblesUsados: max(0, _ent(j['consumibles_usados'])),
      alquiladosUsados: _conjunto(j['alquilados_usados']),
      pintura: _conjunto(j['pintura']),
      objetosRollos: _mapaEnt(j['objetos_rollos'])..removeWhere((_, n) => n <= 0),
      toques: _mapaEnt(j['toques'])..removeWhere((_, n) => n <= 0),
      temporadas: _conjunto(j['temporadas']),
      cadenaReservaEn: _ent(j['cadena_reserva_en']),
      superPlomeroDia: _ent(j['super_plomero_dia']),
      cofres: max(0, _ent(j['cofres'])),
      semanasRacha: max(0, _ent(j['semanas_racha'])),
      congeladosUsados: max(0, _ent(j['congelados_usados'])),
      horasExtraTanque: max(0, _ent(j['horas_extra_tanque'])),
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
      rollos: _ent(j['rollos']) < 0 ? 0 : _ent(j['rollos']),
      rollosGastados: max(0, _ent(j['rollos_gastados'])),
      cagadasPagadas: max(0, _ent(j['cagadas_pagadas'])),
      segHistoricos: max(0.0, _dbl(j['seg_historicos'])),
      primerDia: max(0, _ent(j['primer_dia'])),
      jaladas: _ent(j['jaladas']) < 0 ? 0 : _ent(j['jaladas']),
      vista: _vista(j['vista']),
    );
  }
}
