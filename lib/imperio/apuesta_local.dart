// Cagadón con apuesta: lo que toca el teléfono y la red. La cuenta pura está en apuesta.dart y la validación en el
// servidor (supabase/migrations/20261108140000_cagadon_apuesta.sql).
//
// Se puede apostar desde el chat con el Imperio cerrado: el saldo y la producción salen de la copia del teléfono
// (la que guarda el controlador) y los descuentos, premios y devoluciones esperan en una cola hasta que el Imperio
// cargue. Con el Imperio abierto ([ControlImperio.vivo]) se aplican al momento.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show db;
import 'apuesta.dart';
import 'control.dart';
import 'flags.dart';
import 'nube.dart';
import 'telemetria.dart';

String get _usuario => db.auth.currentUser?.id ?? 'sin_sesion';
String _claveCola(String usuario) => 'imperio_apuestas_$usuario';

/// null si no se puede apostar: Imperio apagado, nunca abierto, sin producción o apuestas apagadas. No lanza.
Future<ResumenApuesta?> resumenApuesta() async {
  final vivo = ControlImperio.vivo;
  if (vivo != null && vivo.apuestaCargada) return vivo.resumenApuesta;
  try {
    final local = await NubeImperio().cargarLocal(_usuario);
    final estado = local?['estado'];
    if (local == null || estado is! Map) return null;
    final mjTotal = (local['mjTotal'] as num?)?.toDouble() ?? 0;
    final mps = (local['mps'] as num?)?.toDouble() ?? 0;
    final saldo = (estado['saldo'] as num?)?.toDouble() ?? 0;
    final p = await SharedPreferences.getInstance();
    final s = p.getString(FlagsImperio.claveCache(db.auth.currentUser?.id));
    final flags = s == null ? FlagsImperio.porDefecto : FlagsImperio.desdeJson(jsonDecode(s));
    if (!flags.activo || flags.apuestaMaxMin <= 0 || mjTotal <= 0 || !mps.isFinite || mps <= 0) return null;
    return ResumenApuesta(saldo: saldo.isFinite && saldo > 0 ? saldo : 0, mps: mps, tope: flags.apuestaMaxMin);
  } catch (_) {
    return null;
  }
}

/// El servidor ya guardó la apuesta: apunta el descuento de [min] × [fraccion] minutos y la telemetría. No lanza.
Future<void> pagarApuesta({required int reto, required int min, required double fraccion, required String rol}) async {
  try {
    Telemetria.instancia.registrar('imperio_apuesta', {'min': min, 'rol': rol, 'fraccion': fraccion});
  } catch (_) {}
  if (min > 0 && fraccion > 0) await _apuntar(ApunteApuesta(TipoApunte.cobro, reto, min * fraccion, apuesta: min));
}

/// COBRAR o RECUPERAR. Lanza el error del servidor (ya cobrada, perdida, todavía no...).
/// Devuelve el resultado (`gana` o `devuelve`), los minutos de producción y los MJ estimados (null sin Imperio).
Future<({String resultado, double minutos, double? mj})> cobrarApuesta(int reto) async {
  final r = await db.rpc('reto_apuesta_cobrar', params: {'rid': reto});
  final m = r is Map ? r : const {};
  final resultado = m['resultado'] is String ? m['resultado'] as String : '';
  final minutos = (m['minutos'] as num?)?.toDouble() ?? 0;
  final apuesta = (m['apuesta'] as num?)?.toInt() ?? 0;
  final ganadas = (m['ganadas'] as num?)?.toInt() ?? 0;
  final resumen = await resumenApuesta();
  final mj = resumen == null ? null : minutos * 60 * resumen.mps;
  try {
    Telemetria.instancia.registrar('imperio_apuesta_cobra', {'resultado': resultado, 'min': apuesta, 'minutos': minutos, 'mj': mj});
  } catch (_) {}
  if (minutos > 0 && (resultado == 'gana' || resultado == 'devuelve')) {
    final tipo = resultado == 'gana' ? TipoApunte.premio : TipoApunte.devolucion;
    await _apuntar(ApunteApuesta(tipo, reto, minutos, apuesta: apuesta, ganadas: ganadas));
  }
  return (resultado: resultado, minutos: minutos, mj: mj);
}

Future<void> _apuntar(ApunteApuesta a) async {
  try {
    final p = await SharedPreferences.getInstance();
    final clave = _claveCola(_usuario);
    await p.setStringList(clave, [...?p.getStringList(clave), jsonEncode(a.toJson())]);
  } catch (_) {}
  await ControlImperio.vivo?.aplicarApuestas();
}

/// Saca y vacía la cola de [usuario]. Lo llama el controlador ya cargado.
Future<List<ApunteApuesta>> sacarApuntes(String usuario) async {
  try {
    final p = await SharedPreferences.getInstance();
    final clave = _claveCola(usuario);
    final cola = p.getStringList(clave) ?? const [];
    if (cola.isEmpty) return const [];
    await p.remove(clave);
    return [for (final s in cola) ?ApunteApuesta.desdeJson(_json(s))];
  } catch (_) {
    return const [];
  }
}

/// Vuelve a poner [apuntes] en la cola (el controlador se cerró antes de aplicarlos).
Future<void> devolverApuntes(String usuario, List<ApunteApuesta> apuntes) async {
  if (apuntes.isEmpty) return;
  try {
    final p = await SharedPreferences.getInstance();
    final clave = _claveCola(usuario);
    await p.setStringList(clave, [for (final a in apuntes) jsonEncode(a.toJson()), ...?p.getStringList(clave)]);
  } catch (_) {}
}

Object? _json(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}
