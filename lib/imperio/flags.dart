// Flags remotos del Imperio (tabla imperio_flags, RPC imperio_flags_mias). Los defaults de aquí son los mismos de la
// migración y del catálogo: sin red o antes de aplicar la migración, el juego queda igual.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import 'catalogo.dart';

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

  /// MJ que suma cada Dedo a cada pujo (`dedo_pujo`).
  final double dedoPujo;

  /// Pujo épico: probabilidad base (`epico_base`), lo que suma cada Dedo (`epico_por_dedo`), tope (`epico_tope`),
  /// multiplicador del buff tipo 1 (`epico_tipo1_x`) y lo que vale un épico (`epico_x`).
  final double epicoBase, epicoPorDedo, epicoTope, epicoTipo1, epicoMultiplicador;

  /// Cadena: cagadas reales entre jaladas (`cadena_cagadas`). El botón prefiere la cuenta que manda `imperio_cadena`.
  final int cadenaCagadas;

  /// Candados pagados con MJ: horas de producción de la primera cagada (`candado_horas`) y cuánto sube cada una
  /// (`candado_subida`).
  final double candadoHoras, candadoSubida;

  /// Rollos de Oro = piso((MJ en total / `cadena_divisor`) ^ `cadena_exponente`).
  final double cadenaDivisor, cadenaExponente;

  /// Producción extra por Rollo de Oro (`rollo_pct`, 0,01 = +1%).
  final double rolloPct;

  /// Cuántas veces el precio del catálogo cuestan los edificios (`escala_edificios`) y las mejoras (`escala_mejoras`).
  /// Calibrado con la telemetría de un jugador que spamea (test/imperio_loco_test.dart): con 1 y 1 llegaba al tope en
  /// unas 6 horas de juego (día 2), antes de juntar las cagadas para jalar la cadena; con 10 y 100 llega hacia las 25.
  /// Como los MJ salen más lentos, `cadena_divisor` bajó de 1e10 a 1e8 para que la cadena dé los mismos rollos.
  final double escalaEdificios, escalaMejoras;

  /// Multiplica el precio en MJ de la tienda de estilo (lib/imperio/tienda_estilo.dart). El servidor usa el mismo
  /// flag en imperio_estilo_comprar. Los Rollos y las cagadas no cambian.
  final double estiloPrecioMult;

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
    this.dedoPujo = 1,
    this.epicoBase = 0.005,
    this.epicoPorDedo = 0.0003,
    this.epicoTope = 0.03,
    this.epicoTipo1 = 3,
    this.epicoMultiplicador = 10,
    this.cadenaCagadas = 5,
    this.candadoHoras = 2,
    this.candadoSubida = 0.1,
    this.cadenaDivisor = 1e8,
    this.cadenaExponente = 0.5,
    this.rolloPct = 0.04,
    this.escalaEdificios = 10,
    this.escalaMejoras = 100,
    this.estiloPrecioMult = 1,
    this.variantes = const {},
  });

  static const FlagsImperio porDefecto = FlagsImperio();

  static const Duration espera = Duration(seconds: 8);

  /// Los números que usa el motor ([Imperio.ajustes]).
  Ajustes get ajustes => Ajustes(
        doradoMinMin: doradoIntervaloMin.isNotEmpty ? doradoIntervaloMin[0].toDouble() : 5,
        doradoMaxMin: doradoIntervaloMin.length > 1 ? doradoIntervaloMin[1].toDouble() : 15,
        offlinePorcentaje: offlinePorcentaje,
        offlineTopeH: offlineTopeH,
        precioCrecimiento: precioCrecimiento,
        precioGuantes: precioGuantes,
        precioFaja: precioFaja,
        cagadaBonoPct: cagadaBonoPct,
        dedoPujo: dedoPujo,
        epicoBase: epicoBase,
        epicoPorDedo: epicoPorDedo,
        epicoTope: epicoTope,
        epicoTipo1: epicoTipo1,
        epicoMultiplicador: epicoMultiplicador,
        cadenaCagadas: cadenaCagadas,
        candadoHoras: candadoHoras,
        candadoSubida: candadoSubida,
        cadenaDivisor: cadenaDivisor,
        cadenaExponente: cadenaExponente,
        rolloPct: rolloPct,
        escalaEdificios: escalaEdificios,
        escalaMejoras: escalaMejoras,
      );

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
      dedoPujo: numero('dedo_pujo', d.dedoPujo, 0, 100),
      epicoBase: numero('epico_base', d.epicoBase, 0, 0.5),
      epicoPorDedo: numero('epico_por_dedo', d.epicoPorDedo, 0, 0.01),
      epicoTope: numero('epico_tope', d.epicoTope, 0, 0.5),
      epicoTipo1: numero('epico_tipo1_x', d.epicoTipo1, 1, 10),
      epicoMultiplicador: numero('epico_x', d.epicoMultiplicador, 1, 100),
      cadenaCagadas: numero('cadena_cagadas', d.cadenaCagadas.toDouble(), 1, 1000).round(),
      candadoHoras: numero('candado_horas', d.candadoHoras, 0.1, 1000),
      candadoSubida: numero('candado_subida', d.candadoSubida, 0, 10),
      cadenaDivisor: numero('cadena_divisor', d.cadenaDivisor, 1, 1e15),
      cadenaExponente: numero('cadena_exponente', d.cadenaExponente, 0.1, 1),
      rolloPct: numero('rollo_pct', d.rolloPct, 0, 1),
      escalaEdificios: numero('escala_edificios', d.escalaEdificios, 1, 1000),
      escalaMejoras: numero('escala_mejoras', d.escalaMejoras, 1, 10000),
      estiloPrecioMult: numero('estilo_precio_mult', d.estiloPrecioMult, 0.01, 1000),
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
