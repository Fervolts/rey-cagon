import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

double _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _ent(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _entN(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
DateTime _fecha(Object? v) => DateTime.tryParse('$v')?.toUtc() ?? DateTime.now().toUtc();

class CagadaNueva {
  final int? tipo;
  final int? peso;
  final DateTime creada;
  const CagadaNueva({this.tipo, this.peso, required this.creada});

  factory CagadaNueva.desdeJson(Map<String, dynamic> j) =>
      CagadaNueva(tipo: _entN(j['tipo']), peso: _entN(j['peso']), creada: _fecha(j['creada']));
}

class CargaImperio {
  final Map<String, dynamic> estado;
  final double mjTotal;
  final double mps;
  final int fichas;
  final bool fundador;
  final bool nuevo;
  final List<CagadaNueva> nuevas;
  final int cagadasTotal;
  final DateTime guardado; // del servidor, UTC
  final DateTime ahora; // del servidor, UTC

  /// Ciruelas 🫐 en el servidor y las que salieron ahora con las cagadas nuevas.
  final int ciruelas;
  final int ciruelasCagadas;

  /// Estéticas premium compradas.
  final Set<String> esteticas;

  /// Último día de racha reclamado y su fecha (local del teléfono que lo reclamó). 0 / null = nunca.
  final int rachaDia;
  final String? rachaFecha;

  /// Congeladores 🧊 guardados (0..2), si ya se pagó el Tanque extra con Fichas y días de racha salvados por congelador.
  final int congeladores;
  final bool tanqueExtra;
  final List<int> rachaSalvados;
  const CargaImperio({
    required this.estado,
    required this.mjTotal,
    required this.mps,
    required this.fichas,
    required this.fundador,
    required this.nuevo,
    required this.nuevas,
    required this.cagadasTotal,
    required this.guardado,
    required this.ahora,
    this.ciruelas = 0,
    this.ciruelasCagadas = 0,
    this.esteticas = const {},
    this.rachaDia = 0,
    this.rachaFecha,
    this.congeladores = 0,
    this.tanqueExtra = false,
    this.rachaSalvados = const [],
  });

  factory CargaImperio.desdeJson(Map<String, dynamic> j) {
    final est = j['estado'];
    final nv = j['nuevas'];
    return CargaImperio(
      estado: est is Map ? Map<String, dynamic>.from(est) : <String, dynamic>{},
      mjTotal: _dbl(j['mj_total']),
      mps: _dbl(j['mps']),
      fichas: _ent(j['fichas']),
      fundador: j['fundador'] == true,
      nuevo: j['nuevo'] == true,
      nuevas: nv is List ? [for (final c in nv) if (c is Map) CagadaNueva.desdeJson(Map<String, dynamic>.from(c))] : const [],
      cagadasTotal: _ent(j['cagadas_total']),
      guardado: _fecha(j['guardado']),
      ahora: _fecha(j['ahora']),
      ciruelas: _ent(j['ciruelas']),
      ciruelasCagadas: _ent(j['ciruelas_cagadas']),
      esteticas: j['esteticas'] is List ? {for (final e in j['esteticas'] as List) '$e'} : const {},
      rachaDia: _ent(j['racha_dia']),
      rachaFecha: j['racha_fecha']?.toString(),
      congeladores: _ent(j['congeladores']),
      tanqueExtra: j['tanque_extra'] == true,
      rachaSalvados: _enteros(j['racha_salvados']),
    );
  }
}

List<int> _enteros(Object? v) => v is List ? [for (final e in v) _ent(e)] : const [];

class ResultadoGuardar {
  final double mjTotal;
  final bool recortado;
  final DateTime guardado;
  const ResultadoGuardar({required this.mjTotal, required this.recortado, required this.guardado});
}

/// Respuesta de `imperio_progreso`.
class ProgresoImperio {
  final int cagadasCandado, pases;
  final bool empujon;
  const ProgresoImperio({required this.cagadasCandado, required this.pases, required this.empujon});

  factory ProgresoImperio.desdeJson(Map<String, dynamic> j) =>
      ProgresoImperio(cagadasCandado: _ent(j['cagadas_candado']), pases: _ent(j['pases']), empujon: j['empujon'] == true);
}

class EstadoCadena {
  final int cagadas;
  final int necesarias;
  final int jaladas;
  const EstadoCadena({required this.cagadas, required this.necesarias, required this.jaladas});

  factory EstadoCadena.desdeJson(Map<String, dynamic> j) =>
      EstadoCadena(cagadas: _ent(j['cagadas']), necesarias: _ent(j['necesarias']), jaladas: _ent(j['jaladas']));
}

/// Respuesta de `imperio_reclamar_racha`.
class ReclamoRacha {
  final int dia;

  /// Ya estaba reclamado ese día (no se acreditó nada).
  final bool ya;
  final int ciruelasGanadas;

  /// Se acreditó una Ficha (false con Fichas llenas: va en Ciruelas).
  final bool ficha;

  /// Saldos después del reclamo.
  final int ciruelas;
  final int fichas;

  /// Congeladores 🧊 gastados para salvar la racha, los que quedan y los días salvados.
  final int congelados;
  final int? congeladores;
  final List<int>? rachaSalvados;

  /// Pases que lleva (cada día reclamado suma uno; dos valen una cagada de candado). null = servidor viejo.
  final int? pases;
  const ReclamoRacha({required this.dia, required this.ya, required this.ciruelasGanadas, required this.ficha, required this.ciruelas,
      required this.fichas, this.congelados = 0, this.congeladores, this.rachaSalvados, this.pases});

  factory ReclamoRacha.desdeJson(Map<String, dynamic> j) => ReclamoRacha(
        dia: _ent(j['dia']),
        ya: j['ya'] == true,
        ciruelasGanadas: _ent(j['ciruelas_ganadas']),
        ficha: j['ficha'] == true,
        ciruelas: _ent(j['ciruelas']),
        fichas: _ent(j['fichas']),
        congelados: _ent(j['congelados']),
        congeladores: _entN(j['congeladores']),
        rachaSalvados: j['racha_salvados'] is List ? _enteros(j['racha_salvados']) : null,
        pases: _entN(j['pases']),
      );
}

/// Respuesta de `imperio_cofre`: días con cagada real esta semana (lunes a domingo, hora local) y si se abrió.
class EstadoCofre {
  final int dias;
  final int meta;

  /// Se puede abrir ya (llegó a la meta y no se abrió esta semana).
  final bool listo;
  final bool reclamado;

  /// Se abrió en esta misma llamada.
  final bool reclamadoAhora;
  final int semanasRacha;
  final int fichas;
  final int ciruelas;
  final int fichasGanadas;
  final int ciruelasGanadas;
  const EstadoCofre({required this.dias, this.meta = 3, required this.listo, required this.reclamado, this.reclamadoAhora = false,
      required this.semanasRacha, required this.fichas, required this.ciruelas, this.fichasGanadas = 0, this.ciruelasGanadas = 0});

  factory EstadoCofre.desdeJson(Map<String, dynamic> j) => EstadoCofre(
        dias: _ent(j['dias']),
        meta: _entN(j['meta']) ?? 3,
        listo: j['listo'] == true,
        reclamado: j['reclamado'] == true,
        reclamadoAhora: j['reclamado_ahora'] == true,
        semanasRacha: _ent(j['semanas_racha']),
        fichas: _ent(j['fichas']),
        ciruelas: _ent(j['ciruelas']),
        fichasGanadas: _ent(j['fichas_ganadas']),
        ciruelasGanadas: _ent(j['ciruelas_ganadas']),
      );
}

class NubeImperio {
  Future<CargaImperio> cargar() async {
    final r = await conReintento(() => db.rpc('imperio_cargar'));
    return CargaImperio.desdeJson(Map<String, dynamic>.from(r as Map));
  }

  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps) async {
    final r = await conReintento(
      () => db.rpc('imperio_guardar', params: {'p_estado': estado, 'p_mj_total': mjTotal, 'p_mps': mps}),
    );
    final j = Map<String, dynamic>.from(r as Map);
    return ResultadoGuardar(mjTotal: _dbl(j['mj_total']), recortado: j['recortado'] == true, guardado: _fecha(j['guardado']));
  }

  /// Gasta 1 Ficha (Cagada fresca de la hoja de Fichas). Devuelve las que quedan, o -1 si no había.
  Future<int> usarFicha() async {
    final r = await conReintento(() => db.rpc('imperio_usar_ficha'));
    return _ent(r);
  }

  /// Gasta Fichas en un uso de la hoja de Fichas: 'sin_espera' (1), 'tanque_extra' (2) o 'congelador' (3).
  /// Devuelve las que quedan, -1 si no alcanzan o -2 si ya no se puede. Sin reintento para no cobrar dos veces.
  Future<int> usarFichas(String que) async => _ent(await db.rpc('imperio_usar_fichas', params: {'p_que': que}));

  /// Estado del Cofre del Trono de esta semana. Con [reclamar] lo abre si toca (una vez por semana en el servidor).
  Future<EstadoCofre> cofre({bool reclamar = false}) async {
    final r = reclamar
        ? await db.rpc('imperio_cofre', params: {'p_reclamar': true})
        : await conReintento(() => db.rpc('imperio_cofre'));
    return EstadoCofre.desdeJson(Map<String, dynamic>.from(r as Map));
  }

  /// Pide la Ciruela que salió al pujar. Devuelve el saldo, o -1 si hoy ya se llegó al tope.
  /// Sin reintento: se pierde una de suerte, nada grave.
  Future<int> ciruelaSuerte() async => _ent(await db.rpc('imperio_ciruela_suerte'));

  /// Paga una oferta de la tienda. Devuelve el saldo, o -1 si no alcanza. Sin reintento para no cobrar dos veces.
  Future<int> gastarCiruelas(String que) async => _ent(await db.rpc('imperio_gastar_ciruelas', params: {'p_que': que}));

  /// Compra una estética. Devuelve el saldo, -1 si no alcanza o -2 si ya la tenías.
  Future<int> comprarEstetica(String id) async => _ent(await db.rpc('imperio_comprar_estetica', params: {'p_id': id}));

  /// Reclama el día de racha de [fecha] ('AAAA-MM-DD', local). Repetir el mismo día no acredita dos veces.
  Future<ReclamoRacha> reclamarRacha(String fecha) async {
    final r = await conReintento(() => db.rpc('imperio_reclamar_racha', params: {'p_fecha': fecha}));
    return ReclamoRacha.desdeJson(Map<String, dynamic>.from(r as Map));
  }

  /// Cagadas para candados (con tope por día), pases de la racha y si toca cobrar el empujón ahora.
  Future<ProgresoImperio> progreso() async {
    final r = await conReintento(() => db.rpc('imperio_progreso'));
    return ProgresoImperio.desdeJson(Map<String, dynamic>.from(r as Map));
  }

  /// Cuántas cagadas reales lleva desde la última jalada (o desde que empezó el Imperio) y cuántas pide la cadena.
  Future<EstadoCadena> cadena() async {
    final r = await conReintento(() => db.rpc('imperio_cadena'));
    return EstadoCadena.desdeJson(Map<String, dynamic>.from(r as Map));
  }

  /// Marca la jalada en el servidor (que revisa las cagadas). Devuelve el número de jaladas que lleva.
  /// Sin reintento: si la respuesta se pierde, la jalada ya quedó marcada y `ControlImperio` la recupera al recargar.
  Future<int> jalar() async {
    final r = await db.rpc('imperio_jalar');
    return _ent(Map<String, dynamic>.from(r as Map)['jaladas']);
  }

  String _clave(String userId) => 'imperio_local_$userId';

  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _clave(userId),
      jsonEncode({
        'estado': estado,
        'mjTotal': mjTotal,
        'mps': mps,
        'guardadoLocal': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<Map<String, dynamic>?> cargarLocal(String userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_clave(userId));
      if (s == null) return null;
      final j = jsonDecode(s);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }
}
