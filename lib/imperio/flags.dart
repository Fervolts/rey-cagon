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

  /// Atasco offline: minutos de media y mínimo hasta que se atasca un edificio con la app cerrada (45 y 10).
  final double atascoOfflineMediaMin, atascoOfflineMinimoMin;

  /// Atascos abiertos a la vez como máximo (3) y segundos de juego activo por Atasco en promedio (240).
  final int atascosMax;
  final double atascoSeg;

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

  /// Alquileres (lib/imperio/motor.dart, [Ajustes.alquilerDescuento]): `alquiler_descuento` (k del descuento por
  /// etapa), `calor_factor` (cada periodo alquilado multiplica el siguiente), `calor_tope`, `calor_vida_media_h` y
  /// `max_primos`.
  final double alquilerDescuento, calorFactor, calorTope, calorVidaMediaH;
  final int maxPrimos;

  /// `pujos_max_seg`: pujos de la mano que cuentan por segundo ([Ajustes.topePujosSeg]).
  final int topePujosSeg;

  /// Mudanza ([Ajustes.mudanzaRollos]): `mudanza_rollos` (Rollos de la casa que pide el Rancho), `mudanza_rollos_subida`
  /// (x por cada casa), `mudanza_jaladas`, `mudanza_cagadas`, `mudanza_llaves_exp`, `mudanza_llaves_x`, `llave_pct` y
  /// `mudanza_divisor_x` (los MJ de cada casa rinden divisor ^ mudanzas veces menos Rollos).
  /// El servidor lee las mismas claves en imperio_mudar e imperio_rollos_casa; los requisitos de verdad los valida él.
  final double mudanzaRollos, mudanzaRollosSubida, mudanzaLlavesExponente, mudanzaLlavesFactor, llavePct, mudanzaDivisorX;
  final int mudanzaJaladas, mudanzaCagadas;

  /// Cuándo aparece el botón MUDANZA ([Ajustes.mudanzaDescubreJaladas]): `mudanza_descubre_jaladas` (jaladas en la casa)
  /// y `mudanza_descubre_pct` (la próxima jalada da menos que esta parte de los Rollos ya ganados en la casa).
  final int mudanzaDescubreJaladas;
  final double mudanzaDescubrePct;

  /// `version_minima`: build mínimo para jugar el Imperio. Con uno menor la pestaña pide actualizar; el servidor
  /// ignora los guardados de versiones más viejas (imperio_guardar, p_version). 0 = sin mínimo.
  final int versionMinima;

  /// Si un cliente con este build debe dejar de jugar el Imperio. Sin build conocido (web, error) no se bloquea.
  bool bloqueaVersion(int? build) => versionMinima > 0 && build != null && build < versionMinima;

  /// Cuántas veces el precio del catálogo cuestan los edificios (`escala_edificios`) y las mejoras (`escala_mejoras`).
  /// Calibrado con la telemetría de un jugador que spamea (test/imperio_loco_test.dart): con 1 y 1 llegaba al tope en
  /// unas 6 horas de juego (día 2), antes de juntar las cagadas para jalar la cadena; con 10 y 100 llega hacia las 25.
  /// Como los MJ salen más lentos, `cadena_divisor` bajó de 1e10 a 1e8 para que la cadena dé los mismos rollos.
  final double escalaEdificios, escalaMejoras;

  /// Multiplica el precio en MJ de la tienda de estilo (lib/imperio/tienda_estilo.dart). El servidor usa el mismo
  /// flag en imperio_estilo_comprar. Los Rollos y las cagadas no cambian.
  final double estiloPrecioMult;

  /// Tope de la apuesta del Cagadón en minutos de producción (`apuesta_max_min`, lib/imperio/apuesta.dart). 0 apaga
  /// las apuestas. El servidor valida el mismo flag al retar.
  final int apuestaMaxMin;

  /// clave → variante asignada (solo las flags con variantes). Va en `sesion_inicio`.
  final Map<String, String> variantes;

  /// Flag `temporadas`: lista de {id, desde, hasta, x} (lib/imperio/temporadas.dart). Cada una vale solo en su rango.
  final List<Temporada> temporadas;

  const FlagsImperio({
    this.activo = true,
    this.doradoIntervaloMin = const [5, 15],
    this.offlinePorcentaje = 0.25,
    this.offlineTopeH = 2,
    this.atascoOfflineMediaMin = 45,
    this.atascoOfflineMinimoMin = 10,
    this.atascosMax = 3,
    this.atascoSeg = 240,
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
    this.alquilerDescuento = 0.22,
    this.calorFactor = 1.5,
    this.calorTope = 10,
    this.calorVidaMediaH = 6,
    this.maxPrimos = 4,
    this.topePujosSeg = 20,
    this.mudanzaRollos = 1e8,
    this.mudanzaRollosSubida = 30,
    this.mudanzaJaladas = 9,
    this.mudanzaCagadas = 30,
    this.mudanzaLlavesExponente = 1 / 3,
    this.mudanzaLlavesFactor = 3,
    this.llavePct = 0.25,
    this.mudanzaDivisorX = 15,
    this.mudanzaDescubreJaladas = 4,
    this.mudanzaDescubrePct = 0.25,
    this.versionMinima = 0,
    this.escalaEdificios = 10,
    this.escalaMejoras = 100,
    this.estiloPrecioMult = 1,
    this.apuestaMaxMin = 60,
    this.variantes = const {},
    this.temporadas = const [],
  });

  static const FlagsImperio porDefecto = FlagsImperio();

  static const Duration espera = Duration(seconds: 8);

  /// Los números que usa el motor ([Imperio.ajustes]).
  Ajustes get ajustes => Ajustes(
        doradoMinMin: doradoIntervaloMin.isNotEmpty ? doradoIntervaloMin[0].toDouble() : 5,
        doradoMaxMin: doradoIntervaloMin.length > 1 ? doradoIntervaloMin[1].toDouble() : 15,
        offlinePorcentaje: offlinePorcentaje,
        offlineTopeH: offlineTopeH,
        atascoOfflineMediaMin: atascoOfflineMediaMin,
        atascoOfflineMinimoMin: atascoOfflineMinimoMin,
        atascosMax: atascosMax,
        atascoSeg: atascoSeg,
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
        alquilerDescuento: alquilerDescuento,
        calorFactor: calorFactor,
        calorTope: calorTope,
        calorVidaMediaH: calorVidaMediaH,
        maxPrimos: maxPrimos,
        topePujosSeg: topePujosSeg,
        mudanzaRollos: mudanzaRollos,
        mudanzaRollosSubida: mudanzaRollosSubida,
        mudanzaJaladas: mudanzaJaladas,
        mudanzaCagadas: mudanzaCagadas,
        mudanzaLlavesExponente: mudanzaLlavesExponente,
        mudanzaLlavesFactor: mudanzaLlavesFactor,
        llavePct: llavePct,
        mudanzaDivisorX: mudanzaDivisorX,
        mudanzaDescubreJaladas: mudanzaDescubreJaladas,
        mudanzaDescubrePct: mudanzaDescubrePct,
        escalaEdificios: escalaEdificios,
        escalaMejoras: escalaMejoras,
        temporadas: temporadas,
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
      atascoOfflineMediaMin: numero('atasco_offline_media_min', d.atascoOfflineMediaMin, 5, 1440),
      atascoOfflineMinimoMin: numero('atasco_offline_min_min', d.atascoOfflineMinimoMin, 1, 240),
      atascosMax: numero('atascos_max', d.atascosMax.toDouble(), 1, 10).round(),
      atascoSeg: numero('atasco_seg', d.atascoSeg, 30, 3600),
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
      alquilerDescuento: numero('alquiler_descuento', d.alquilerDescuento, 0, 0.5),
      calorFactor: numero('calor_factor', d.calorFactor, 1, 5),
      calorTope: numero('calor_tope', d.calorTope, 1, 100),
      calorVidaMediaH: numero('calor_vida_media_h', d.calorVidaMediaH, 0.25, 168),
      maxPrimos: numero('max_primos', d.maxPrimos.toDouble(), 1, 8).round(),
      topePujosSeg: numero('pujos_max_seg', d.topePujosSeg.toDouble(), 5, 50).round(),
      mudanzaRollos: numero('mudanza_rollos', d.mudanzaRollos, 1, 1e20),
      mudanzaRollosSubida: numero('mudanza_rollos_subida', d.mudanzaRollosSubida, 1, 1e6),
      mudanzaJaladas: numero('mudanza_jaladas', d.mudanzaJaladas.toDouble(), 0, 1000).round(),
      mudanzaCagadas: numero('mudanza_cagadas', d.mudanzaCagadas.toDouble(), 0, 10000).round(),
      mudanzaLlavesExponente: numero('mudanza_llaves_exp', d.mudanzaLlavesExponente, 0.05, 1),
      mudanzaLlavesFactor: numero('mudanza_llaves_x', d.mudanzaLlavesFactor, 0.1, 1000),
      llavePct: numero('llave_pct', d.llavePct, 0, 10),
      mudanzaDivisorX: numero('mudanza_divisor_x', d.mudanzaDivisorX, 1, 1e12),
      mudanzaDescubreJaladas: numero('mudanza_descubre_jaladas', d.mudanzaDescubreJaladas.toDouble(), 0, 1000).round(),
      mudanzaDescubrePct: numero('mudanza_descubre_pct', d.mudanzaDescubrePct, 0, 1),
      versionMinima: numero('version_minima', d.versionMinima.toDouble(), 0, 1e9).round(),
      escalaEdificios: numero('escala_edificios', d.escalaEdificios, 1, 1000),
      escalaMejoras: numero('escala_mejoras', d.escalaMejoras, 1, 10000),
      estiloPrecioMult: numero('estilo_precio_mult', d.estiloPrecioMult, 0.01, 1000),
      apuestaMaxMin: numero('apuesta_max_min', d.apuestaMaxMin.toDouble(), 0, 60).round(),
      temporadas: leerTemporadas(valor('temporadas')),
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
