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
    );
  }
}

class ResultadoGuardar {
  final double mjTotal;
  final bool recortado;
  final DateTime guardado;
  const ResultadoGuardar({required this.mjTotal, required this.recortado, required this.guardado});
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

  /// Devuelve las fichas que quedan, o -1 si no había.
  Future<int> usarFicha() async {
    final r = await conReintento(() => db.rpc('imperio_usar_ficha'));
    return _ent(r);
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
