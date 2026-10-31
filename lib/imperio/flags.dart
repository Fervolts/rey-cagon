// Flags remotos del Imperio (tabla imperio_flags, RPC imperio_flags_mias). Los defaults de aquí son los mismos de la
// migración y del catálogo: sin red o antes de aplicar la migración, el juego queda igual.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

/// Pide `{clave: {valor, variante}}` al servidor.
typedef PedirFlags = Future<Object?> Function();

Future<Object?> _pedirPorRpc() => conReintento(() => db.rpc('imperio_flags_mias'));

class FlagsImperio {
  /// false = la pestaña Imperio se apaga.
  final bool activo;

  /// Minutos activos entre mojones dorados: [mínimo, máximo] (sin Imán ni tipo 5).
  final List<int> doradoIntervaloMin;

  /// Parte del MJ/s que cuenta offline sin válvulas (0,25).
  final double offlinePorcentaje;

  /// Tope offline sin tanques, en horas.
  final double offlineTopeH;

  /// Cada unidad de un edificio cuesta esto por la anterior.
  final double precioCrecimiento;
  final double precioGuantes, precioFaja;

  /// Producción extra por cagada real hasta 150, en % (2 = +2%).
  final double cagadaBonoPct;

  /// clave → variante asignada (solo las flags con variantes). Va en `sesion_inicio`.
  final Map<String, String> variantes;

  const FlagsImperio({
    this.activo = true,
    this.doradoIntervaloMin = const [5, 15],
    this.offlinePorcentaje = 0.25,
    this.offlineTopeH = 2,
    this.precioCrecimiento = 1.15,
    this.precioGuantes = 100,
    this.precioFaja = 500,
    this.cagadaBonoPct = 2,
    this.variantes = const {},
  });

  static const FlagsImperio porDefecto = FlagsImperio();

  static const Duration espera = Duration(seconds: 8);

  static String claveCache(String? usuario) => 'imperio_flags_${usuario ?? 'anon'}';

  /// Lee la respuesta del RPC. Lo que falte o venga con otro tipo queda en el default; los números se recortan a un rango sano.
  factory FlagsImperio.desdeJson(Object? json) {
    const d = porDefecto;
    final m = json is Map ? json : const {};
    Object? valor(String clave) {
      final f = m[clave];
      return f is Map ? f['valor'] : null;
    }

    double numero(String clave, double defecto, double minimo, double maximo) {
      final v = valor(clave);
      final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
      if (n == null || !n.isFinite) return defecto;
      return n.clamp(minimo, maximo).toDouble();
    }

    List<int> intervalo() {
      final v = valor('dorado_intervalo_min');
      if (v is! List || v.length != 2 || v.any((x) => x is! num || !x.isFinite)) return d.doradoIntervaloMin;
      var a = (v[0] as num).round(), b = (v[1] as num).round();
      if (b < a) (a, b) = (b, a);
      a = a.clamp(1, 60);
      b = b.clamp(a, 120);
      return [a, b];
    }

    final act = valor('imperio_activo');
    return FlagsImperio(
      activo: act is bool ? act : d.activo,
      doradoIntervaloMin: intervalo(),
      offlinePorcentaje: numero('offline_porcentaje', d.offlinePorcentaje, 0, 1),
      offlineTopeH: numero('offline_tope_h', d.offlineTopeH, 0.5, 24),
      precioCrecimiento: numero('precio_crecimiento', d.precioCrecimiento, 1.01, 2),
      precioGuantes: numero('precio_guantes', d.precioGuantes, 1, 1e6),
      precioFaja: numero('precio_faja', d.precioFaja, 1, 1e7),
      cagadaBonoPct: numero('cagada_bono_pct', d.cagadaBonoPct, 0, 10),
      variantes: {
        for (final e in m.entries)
          if (e.key is String && e.value is Map && (e.value as Map)['variante'] is String) e.key as String: (e.value as Map)['variante'] as String,
      },
    );
  }

  /// Flags del servidor (y las guarda); sin red, las últimas guardadas; sin nada, los defaults. No lanza.
  static Future<FlagsImperio> cargar({String? usuario, PedirFlags? pedir}) async {
    final clave = claveCache(usuario);
    try {
      final r = await (pedir ?? _pedirPorRpc)().timeout(espera);
      if (r is Map) {
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(clave, jsonEncode(r));
        } catch (_) {}
        return FlagsImperio.desdeJson(r);
      }
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(clave);
      if (s != null) return FlagsImperio.desdeJson(jsonDecode(s));
    } catch (_) {}
    return porDefecto;
  }
}
