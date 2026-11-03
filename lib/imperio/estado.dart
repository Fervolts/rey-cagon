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

/// Atascos guardados: `atascos` (lista) o, en partidas viejas, solo `atasco`. Uno por edificio.
List<Atasco> _atascos(Map<String, dynamic> j) {
  final lista = j['atascos'] is List ? j['atascos'] as List : [j['atasco']];
  final r = <Atasco>[];
  for (final v in lista) {
    final a = Atasco.desdeJson(v);
    if (a != null && r.every((b) => b.edificio != a.edificio)) r.add(a);
  }
  return r;
}

/// Atascos offline guardados: `atascos_offline` (lista) o, en partidas viejas, `atasco_offline_en` / `_e`.
List<AtascoProgramado> _atascosOffline(Map<String, dynamic> j) {
  final lista = j['atascos_offline'] is List
      ? j['atascos_offline'] as List
      : [{'en': j['atasco_offline_en'], 'e': j['atasco_offline_e']}];
  return [for (final v in lista) ?AtascoProgramado.desdeJson(v)]..sort((a, b) => a.en.compareTo(b.en));
}

Map<String, double> _mapaDbl(Object? v) {
  if (v is! Map) return {};
  return {for (final e in v.entries) '${e.key}': _dbl(e.value)};
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

/// Atasco offline programado al salir: en [en] (ms epoch) se atasca [edificio].
class AtascoProgramado {
  final int en;
  final String edificio;
  const AtascoProgramado(this.en, this.edificio);

  Map<String, dynamic> toJson() => {'en': en, 'e': edificio};

  static AtascoProgramado? desdeJson(Object? v) {
    if (v is! Map || v['e'] is! String || _ent(v['en']) <= 0) return null;
    return AtascoProgramado(_ent(v['en']), v['e'] as String);
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

  /// Alquileres en modo Indefinido: se renuevan solos cada periodo mientras alcance la plata (2.13.1).
  Set<String> indefinidos;

  /// Guía de los alquileres ya vista: ids de alquilables cuya ficha ya entendió y claves de empujones ya mostrados
  /// (`empujon_robot`, `empujon_primo`, `trabaja_<id>`). Jalar la cadena no la borra.
  Set<String> guiaVista;

  /// Calor de cada alquilable (periodos alquilados, ya bajados por el tiempo) y cuándo se anotó (ms). Lo baja
  /// `Imperio.calor` con su vida media (2.13.1).
  Map<String, double> calor;
  Map<String, int> calorEn;

  /// Edificios con Pintura marrón (+10% c/u). Se borra al jalar la cadena.
  Set<String> pintura;

  /// Plomería (objetos de Rollos de Oro): id → nivel ('cadena_reserva' 1 = pendiente). No se borra al jalar; mudarse la
  /// borra (el Camión de mudanza se lleva una parte).
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

  /// Atascos abiertos en orden de llegada (máximo uno por edificio). Se destapa el primero.
  List<Atasco> atascos;

  /// El primero de [atascos] (null = ninguno). Asignar reemplaza toda la lista.
  Atasco? get atasco => atascos.isEmpty ? null : atascos.first;
  set atasco(Atasco? a) => atascos = [?a];
  bool vioPrimerAtasco;

  /// Atascos programados al salir de la app, en orden de hora. Se resuelven al volver dentro de la cuenta offline y
  /// se borran siempre.
  List<AtascoProgramado> atascosOffline;

  /// Hora (ms epoch, 0 = ninguno) y edificio del primer Atasco offline programado.
  int get atascoOfflineEn => atascosOffline.isEmpty ? 0 : atascosOffline.first.en;
  String get atascoOfflineEdificio => atascosOffline.isEmpty ? '' : atascosOffline.first.edificio;

  /// Presión del azar de Atascos en juego (sube con el tiempo activo y las compras) y el umbral sorteado en que
  /// sale el próximo (0 = sin sortear).
  double presionAtasco, umbralAtasco;

  /// Media móvil de los minutos que el jugador pasa fuera (0 = sin datos). Programa el Atasco offline a su medida.
  double ausenciaMediaMin;

  /// Segundos de juego activo que faltan para el próximo mojón dorado. Negativo = sin programar.
  double segHastaDorado;
  DoradoVisible? dorado;

  /// Papel doble hoja usado: el próximo dorado da el doble.
  bool papelDoble;

  /// Buff del tipo de la última cagada real (1 a 7) y su fin (ms).
  int? tipoBuff;
  int tipoBuffHasta;

  /// Fuerza del buff de tipo (1, 0,5): se cansa si repites el mismo tipo seguido.
  double tipoBuffFuerza;

  /// Tipo 6: el próximo offline cuenta x1,5.
  bool offlineBonus;

  /// Fuerza del bonus offline del tipo 6 (1 = x1,5; 0,5 = x1,25).
  double offlineBonusFuerza;

  /// Racha de repetir tipo: último tipo cagado, cuántas veces seguidas y cuándo (ms de la cagada).
  int? rachaTipo;
  int rachaTipoVeces;
  int rachaTipoEn;

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

  /// Mudanzas hechas (0 = Rancho). El servidor lleva la cuenta buena en `imperio.mudanzas`.
  int mudanzas;

  /// [mjTotal] y [jaladas] el día de la última mudanza: los Rollos y las jaladas de la casa se cuentan desde ahí.
  double mjBase;
  int jaladasBase;

  /// MJ ganados en la casa de ahora, contados aparte: con números grandes mjTotal - mjBase da 0 (1e34 + 1e13 = 1e34 en
  /// double). En el Rancho no se usa (ahí son todos los MJ). El servidor lleva el tope en `imperio.mj_casa`.
  double mjEnCasa;

  /// Llaves ganadas mudándose (las manda el servidor) y mejoras del Llavero (id → nivel). Las Llaves sin gastar son las
  /// ganadas menos lo que cuesta el Llavero ([costoLlavero]). Mudarse no las borra.
  int llavesGanadas;
  Map<String, int> llavero;

  /// El Mayordomo está apagado (el jugador lo apagó en el Imperio).
  bool mayordomoApagado;

  /// Mudanzas hechas sin gastar ni un Rollo en esa casa (logro escondido).
  int mudanzasLimpias;

  /// Jaladas en la casa de ahora.
  int get jaladasCasa => max(0, jaladas - jaladasBase);

  /// MJ ganados en la casa de ahora.
  double get mjCasa => mudanzas <= 0 ? mjTotal : max(0, mjEnCasa);

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
    Set<String>? indefinidos,
    Set<String>? guiaVista,
    Map<String, double>? calor,
    Map<String, int>? calorEn,
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
    Atasco? atasco,
    List<Atasco>? atascos,
    this.vioPrimerAtasco = false,
    List<AtascoProgramado>? atascosOffline,
    this.presionAtasco = 0,
    this.umbralAtasco = 0,
    this.ausenciaMediaMin = 0,
    this.segHastaDorado = -1,
    this.dorado,
    this.papelDoble = false,
    this.tipoBuff,
    this.tipoBuffHasta = 0,
    this.tipoBuffFuerza = 1,
    this.offlineBonus = false,
    this.offlineBonusFuerza = 1,
    this.rachaTipo,
    this.rachaTipoVeces = 0,
    this.rachaTipoEn = 0,
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
    this.mudanzas = 0,
    this.mjBase = 0,
    this.mjEnCasa = 0,
    this.jaladasBase = 0,
    this.llavesGanadas = 0,
    Map<String, int>? llavero,
    this.mayordomoApagado = false,
    this.mudanzasLimpias = 0,
  })  : vista = vista ?? {},
        llavero = llavero ?? {},
        edificios = edificios ?? {},
        mejoras = mejoras ?? {},
        logros = logros ?? {},
        inventario = inventario ?? {},
        efectos = efectos ?? {},
        esperas = esperas ?? {},
        pujosRecientes = pujosRecientes ?? [],
        alquilados = alquilados ?? {},
        alquiladosUsados = alquiladosUsados ?? {},
        indefinidos = indefinidos ?? {},
        guiaVista = guiaVista ?? {},
        calor = calor ?? {},
        calorEn = calorEn ?? {},
        pintura = pintura ?? {},
        objetosRollos = objetosRollos ?? {},
        toques = toques ?? {},
        atascos = atascos ?? [?atasco],
        atascosOffline = atascosOffline ?? [],
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
        if (indefinidos.isNotEmpty) 'alquilados_indef': indefinidos.toList(),
        if (guiaVista.isNotEmpty) 'guia_vista': guiaVista.toList(),
        if (calor.isNotEmpty) 'calor': calor,
        if (calorEn.isNotEmpty) 'calor_en': calorEn,
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
        'atascos': [for (final a in atascos) a.toJson()],
        'vio_atasco': vioPrimerAtasco,
        if (atascoOfflineEn > 0) 'atasco_offline_en': atascoOfflineEn,
        if (atascoOfflineEn > 0) 'atasco_offline_e': atascoOfflineEdificio,
        if (atascosOffline.isNotEmpty) 'atascos_offline': [for (final a in atascosOffline) a.toJson()],
        'presion_atasco': presionAtasco,
        'umbral_atasco': umbralAtasco,
        'ausencia_media_min': ausenciaMediaMin,
        'seg_dorado': segHastaDorado,
        'dorado': dorado?.toJson(),
        'papel_doble': papelDoble,
        'tipo_buff': tipoBuff,
        'tipo_buff_hasta': tipoBuffHasta,
        'tipo_buff_f': tipoBuffFuerza,
        'offline_bonus': offlineBonus,
        'offline_bonus_f': offlineBonusFuerza,
        'racha_tipo': rachaTipo,
        'racha_tipo_n': rachaTipoVeces,
        'racha_tipo_en': rachaTipoEn,
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
        if (mudanzas > 0) 'mudanzas': mudanzas,
        if (mjBase > 0) 'mj_base': mjBase,
        if (mudanzas > 0 && mjEnCasa > 0) 'mj_casa': mjEnCasa,
        if (jaladasBase > 0) 'jaladas_base': jaladasBase,
        if (llavesGanadas > 0) 'llaves_ganadas': llavesGanadas,
        if (llavero.isNotEmpty) 'llavero': llavero,
        if (mayordomoApagado) 'mayordomo_off': true,
        if (mudanzasLimpias > 0) 'mudanzas_limpias': mudanzasLimpias,
      };

  /// Lee una partida guardada. Aguanta claves que faltan, sobran o vienen con otro tipo.
  factory Partida.desdeJson(Map<String, dynamic>? j) {
    if (j == null) return Partida();
    final saldo = _dbl(j['saldo']);
    final total = _dbl(j['mj_total']);
    final recientes = j['pujos_recientes'] is List ? [for (final x in j['pujos_recientes'] as List) _ent(x)] : <int>[];
    final tipo = _entN(j['tipo_buff']);
    final racha = _entN(j['racha_tipo']);
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
      indefinidos: _conjunto(j['alquilados_indef']),
      guiaVista: _conjunto(j['guia_vista']),
      calor: _mapaDbl(j['calor'])..removeWhere((_, n) => n <= 0),
      calorEn: _mapaEnt(j['calor_en']),
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
      atascos: _atascos(j),
      vioPrimerAtasco: _bool(j['vio_atasco']),
      atascosOffline: _atascosOffline(j),
      presionAtasco: max(0, _dbl(j['presion_atasco'], 0)),
      umbralAtasco: max(0, _dbl(j['umbral_atasco'], 0)),
      ausenciaMediaMin: max(0, _dbl(j['ausencia_media_min'], 0)),
      segHastaDorado: _dbl(j['seg_dorado'], -1),
      dorado: DoradoVisible.desdeJson(j['dorado']),
      papelDoble: _bool(j['papel_doble']),
      tipoBuff: tipo != null && tipo >= 1 && tipo <= 7 ? tipo : null,
      tipoBuffHasta: _ent(j['tipo_buff_hasta']),
      tipoBuffFuerza: _dbl(j['tipo_buff_f'], 1).clamp(0, 1).toDouble(),
      offlineBonus: _bool(j['offline_bonus']),
      offlineBonusFuerza: _dbl(j['offline_bonus_f'], 1).clamp(0, 1).toDouble(),
      rachaTipo: racha != null && racha >= 1 && racha <= 7 ? racha : null,
      rachaTipoVeces: max(0, _ent(j['racha_tipo_n'])),
      rachaTipoEn: _ent(j['racha_tipo_en']),
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
      mudanzas: max(0, _ent(j['mudanzas'])),
      mjBase: min(max(0.0, _dbl(j['mj_base'])), total < saldo ? saldo : total),
      // Partidas de antes de la cuenta aparte: la resta (bien mientras los números no sean enormes).
      mjEnCasa: j['mj_casa'] is num
          ? max(0.0, _dbl(j['mj_casa']))
          : max(0.0, (total < saldo ? saldo : total) - min(max(0.0, _dbl(j['mj_base'])), total < saldo ? saldo : total)),
      jaladasBase: max(0, _ent(j['jaladas_base'])),
      llavesGanadas: max(0, _ent(j['llaves_ganadas'])),
      llavero: _mapaEnt(j['llavero'])..removeWhere((_, n) => n <= 0),
      mayordomoApagado: _bool(j['mayordomo_off']),
      mudanzasLimpias: max(0, _ent(j['mudanzas_limpias'])),
    );
  }
}
