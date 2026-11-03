// Eventos del Imperio para estudiar cómo se juega. Cola en memoria + SharedPreferences, se manda en lotes por RPC.
// Nunca lanza al que llama: si no hay red, los eventos esperan al próximo vaciar().

import 'dart:convert';
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

/// Manda un lote al servidor y devuelve cuántos guardó. Si lanza, el lote se queda en la cola.
typedef EnviarEventos = Future<int> Function(List<Map<String, Object?>> lote);

Future<int> _enviarPorRpc(List<Map<String, Object?>> lote) async {
  final r = await conReintento(() => db.rpc('imperio_registrar', params: {'p_eventos': lote}));
  return r is num ? r.toInt() : 0;
}

/// Telemetría del Imperio. Usar `Telemetria.instancia`; en las pruebas se crea una con `enviar` falso.
///
/// CATÁLOGO DE EVENTOS (nombre {campos de datos}). Lo emite el controlador; `seg_partida` = segundos de juego activo de
/// la partida guardada (`Partida.segPartida`, lo suma `tick`).
///
/// - `sesion_inicio` {cagadas, mj_total, mps, offline_s, variantes} (variantes = `FlagsImperio.variantes`, clave→variante)
/// - `sesion_fin` {segundos, pujos, mj_ganados, compras}
/// - `edificio` {id, cantidad, precio, seg_partida} (cantidad = cuántos tiene después de comprar)
/// - `mejora` {id, precio, seg_partida}
/// - `objeto_compra` {id}
/// - `objeto_uso` {id}
/// - `dorado_aparece` {}
/// - `dorado_toca` {efecto} (nombre de `EfectoDorado`)
/// - `dorado_pierde` {}
/// - `atasco_aparece` {edificio, abiertos}: abiertos = cuántos Atascos hay abiertos contando este (tope `atascos_max`)
/// - `atasco_destapa` {ms, perfecto, robot}: uno por Atasco; el Robot y los que destapan todo mandan uno por cada uno
/// - `atasco_pierde` {}: uno por cada Atasco que sigue abierto al cerrar la sesión (una vez por Atasco)
/// - `atasco_offline` {edificio, edificios, minutos, mj_perdidos, robot}: al volver, los Atascos sorteados al salir que
///   cayeron dentro del tiempo contado. edificio, minutos y robot son del primero; edificios = todos, en orden;
///   minutos = desde que se fue hasta el primero; robot = al primero lo destapó solo un Robot, Robot Turbo o Súper Plomero
///   (los cubiertos no suman a mj_perdidos); mj_perdidos suma los que no se destaparon solos
/// - `atasco_offline_aviso` {edificio, minutos}: al salir se programó el aviso local del primer Atasco offline que nada
///   destapa solo (minutos hasta él; un solo aviso aunque haya varios)
/// - `logro` {id}
/// - `offline` {segundos, tope_lleno, ganado}
/// - `descarga` {cagadas, ganado}
/// - `bienvenida` {cagadas, fichas, fundador}
/// - `ficha_usa` {}: ya no se emite (la Cagada fresca sale sola con cada cagada real; las Fichas son para minijuegos)
/// - `sala_abre` {}
/// - `minijuego_toca` {id} (los "próximamente")
/// - `pestana_abre` {}
/// - `mejoras_abre` {edificio}: desplegó las mejoras de un edificio (`poceta` = las de TU POCETA)
/// - `cadena_abre` {puede}: tocó JALAR (`puede` = estaba encendido)
/// - `cadena_jala` {rollos, jaladas}: jaló la cadena (rollos ganados en esta jalada, jaladas en total)
/// - `partida_adoptada` {jaladas}: el servidor tenía más jaladas y su partida ya las llevaba (reinicio): se usó esa
/// - `cartera_comparte` {destino}: presumió la cartera (`chat` = tarjeta en la sala general, `fuera` = imagen para historias)
/// - `personalizar_abre` {}: abrió la hoja Personalizar el baño
/// - `bano_compartir` {}: presumió su baño en la sala general (tarjeta 'bano', foto del baño que arma el servidor)
/// - `ciruela_suerte` {origen, cantidad, saldo}: cayeron Ciruelas (`pujo` = al pujar, tope diario; `cagada` = al cargar, por cagadas reales)
/// - `ciruelas_gastar` {id, precio, saldo, mj}: compró en la tienda de Ciruelas (id de `ofertasCiruela`; mj = producción ganada al instante)
/// - `estetica_compra` {id, saldo, bono}: compró una estética del baño (bono = suerte total después de comprar)
/// - `tienda_ciruelas_abre` {}
/// - `racha_abre` {}: abrió la hoja de la racha de 30 días (sola al cargar o desde el chip 🔥)
/// - `racha_reclamar` {dia, ciruelas, ficha, mj}: reclamó el día de la racha (ciruelas = las que dio el servidor, ficha = si entró una)
/// - `fichas_abre` {fichas}: abrió la hoja de Fichas desde el chip 🎟️
/// - `fichas_usar` {que, precio, saldo, espera?}: gastó Fichas en la hoja de Fichas (`cagada_fresca`, `sin_espera` con la `espera` borrada,
///   `tanque_extra` o `congelador`)
/// - `cofre_reclamar` {dias, fichas, ciruelas, semanas, mj}: abrió el Cofre del Trono de la semana (fichas/ciruelas = las que dio el servidor)
/// - `congelador_usar` {cantidad, dia, quedan}: el servidor gastó Congeladores 🧊 al reclamar la racha y la racha siguió
/// - `mana_usar` {id, mana, mj, fallo}: usó una habilidad de Maná (id de `habilidades`; mana = el que quedó; mj y fallo del Chorro)
/// - `alquilar` {id, precio, hasta, veces, indefinido, calor}: alquiló un objeto (además del `objeto_compra`; hasta = fin en ms, o
///   cuándo se alquiló el Guardia; precio = MJ pagados; veces = periodos pagados (1, 2, 5, 10; 0 si solo prendió el Indefinido de
///   uno activo); indefinido = puso el modo Indefinido; calor = multiplicador del calor antes de pagar, x1 a x10) (2.13.1)
/// - `alquiler_cortado` {id, precio, saldo}: un alquiler Indefinido no se pudo renovar por falta de MJ y se apagó (precio = lo que
///   costaba el periodo, saldo = los MJ que había) (2.13.1)
/// - `alquiler_apagar` {id, hasta}: apagó a mano el Indefinido; el alquiler sigue hasta `hasta` (2.13.1)
/// - `alquiler_guia` {id, accion}: guía de los alquileres. accion = `ficha` (se vio la ficha de qué hace, la primera vez o
///   con el botón ?), `entendido` (la cerró), `ir` (alquiló desde la ficha) o `empujon` (salió un consejo en la pantalla:
///   id = el alquilable, `robot` con un Atasco de más de 20 s, `primo` pujando rápido a mano, o el recién alquilado)
/// - `imperio_recorrido` {paso, accion}: recorrido guiado de la primera vez (recorrido.dart). paso = id del paso (poceta, saldo,
///   edificios, mejoras, atascos, dorado, objetos, que_hago, cadena); accion = `ver` (salió el paso), `siguiente`, `saltar` o `fin`
/// - `imperio_que_hago` {sugerencia, accion}: hoja "¿Qué hago ahora?" (botón ? de la cabecera). sugerencia = destapar, robot,
///   dorado, jalar, edificio, mejora, esperar o pujar (que_hago.dart); accion = `abrir` (abrió la hoja) o `ir` (tocó el botón IR)
/// - `consumible_usar` {id, quedan, edificio?}: usó un consumible (va con `objeto_uso`, salvo la Pintura marrón, que trae `edificio`)
/// - `rollos_gastar` {id, costo, quedan, tiene}: compró un nivel de la Plomería con Rollos de Oro (id de `objetosRollos`; tiene = nivel)
/// - `imperio_plomeria` {id, nivel}: compró un nivel de la Plomería 🔧 (va con `rollos_gastar`; nivel = el que quedó)
/// - `imperio_llavero` {id, nivel}: compró un nivel del Llavero 🔑 con Llaves (id de `mejorasLlavero`)
/// - `imperio_mudanza` {mudanzas, llaves, dia}: se mudó de casa (mudanzas = las que lleva, llaves = las que ganó, dia = día de juego)
/// - `mudanza_rechazada` {motivo}: el servidor no dejó mudarse (motivo de `imperio_mudar`)
/// - `mudanza_sincroniza` {mudanzas_servidor, mudanzas_partida}: al cargar, el servidor tenía una mudanza que la partida no; se aplicó
/// - `estilo_abre` {}: abrió la tienda de estilo (botón 🎨 de la cabecera)
/// - `estilo_compra` {id, mj, rollos}: compró un estilo (id de `estilos`; mj = precio con `estilo_precio_mult`, rollos gastados)
/// - `estilo_usa` {id}: se puso un tema, un efecto de CAGUÉ o un movimiento del avatar
/// - `temporada_ve` {id}: jugó con una temporada activa (id de lib/imperio/temporadas.dart: `dia_retrete`, `navidad`);
///   una vez por temporada en cada sesión de juego (entre `sesion_inicio` y `sesion_fin`)
/// - `imperio_apuesta` {min, rol, fraccion}: apostó en un Cagadón (lib/imperio/apuesta.dart). min = 15, 30 o 60 minutos de su
///   producción; rol = `reta` o `acepta`; fraccion = parte pagada (0 a 1, menos de 1 si no le alcanzaba el saldo). Puede salir
///   fuera del Imperio (chat): el descuento se aplica al abrirlo
/// - `imperio_apuesta_cobra` {resultado, min, minutos, mj}: tocó COBRAR (`gana`, doble de lo pagado) o RECUPERAR (`devuelve`:
///   empate, rechazo, cancelación, vencido o anulada). minutos = los que dio el servidor; mj = MJ estimados con la producción de ese momento (null si no hay Imperio)
/// - `imperio_regalo_envia` {dados, en_chat}: regaló un Rollo 🧻 a un amigo (perfil o chat; regalos.dart). dados = total
///   regalado según el servidor; en_chat = si salió la tarjeta en el chat (la primera del día)
/// - `imperio_regalo_abre` {minutos, mj, mutuo, quedan}: abrió un Rollo de regalo. minutos = los que pagó el servidor; mj =
///   lo que sumó (minutos de la producción propia); mutuo = si ese mismo día yo también le regalé a quien me lo dio; quedan = Rollos por abrir
/// - `avisos_tarjeta_ve` {total, categoria}: vio la tarjeta "Ordena tus avisos" del inicio (una vez por pantalla;
///   avisos_resumen.dart). total = push que le llegaron en 7 días; categoria = la que más mandó
/// - `avisos_tarjeta_abre` {total}: tocó ELEGIR AVISOS y abrió Ajustes de notificaciones
/// - `avisos_tarjeta_descarta` {total}: la cerró; no vuelve en 14 días
/// - `error` {donde, tipo, red}: tipo = clase de la excepción; red = si fue de red. Los guardados fallidos con la app en el fondo no cuentan (se repiten al volver)
///
/// Nombres: `[a-z0-9_]`, hasta 40. Datos: JSON plano, hasta ~3,5 KB (si no, se manda `{recortado: true}`).
class Telemetria {
  static const int maxCola = 500;
  static const int tamanoLote = 100;
  static const int maxBytesDatos = 3500;
  static const String clavePrefs = 'imperio_telemetria_cola';
  static final RegExp _nombreValido = RegExp(r'^[a-z0-9_]{1,40}$');

  /// La de la app. El controlador llama `vaciar()` cada 60 s y al pausar.
  static final Telemetria instancia = Telemetria();

  final EnviarEventos _enviar;
  final int Function() _reloj;

  /// Id de esta sesión de la app (formato uuid v4, nuevo en cada arranque).
  final String sesion;

  /// Versión de la app (`1.14.2+50`). Se llena con `leerVersion()` o a mano.
  String version;

  final List<Map<String, Object?>> _cola = [];
  final Random _azar;
  Future<void>? _carga;
  bool _guardadoPendiente = false;
  bool _vaciando = false;

  Telemetria({EnviarEventos? enviar, int Function()? reloj, Random? azar, this.version = ''})
      : _enviar = enviar ?? _enviarPorRpc,
        _reloj = reloj ?? (() => DateTime.now().millisecondsSinceEpoch),
        _azar = azar ?? Random.secure(),
        sesion = idSesion(azar ?? Random.secure());

  /// 128 bits al azar con forma de uuid v4 (la columna `sesion` es uuid).
  static String idSesion(Random azar) {
    final b = List<int>.generate(16, (_) => azar.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Eventos esperando envío (los de disco cuentan después de la primera carga).
  int get pendientes => _cola.length;

  /// Copia de la cola, el más viejo primero (para pruebas).
  List<Map<String, Object?>> get cola => List.unmodifiable(_cola);

  Future<void> leerVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      version = '${i.version}+${i.buildNumber}';
    } catch (_) {}
  }

  /// Anota un evento. No espera nada ni lanza.
  void registrar(String evento, [Map<String, Object?> datos = const {}]) {
    if (!_nombreValido.hasMatch(evento)) return;
    var d = _limpiarMapa(datos, 0);
    try {
      if (utf8.encode(jsonEncode(d)).length > maxBytesDatos) d = {'recortado': true};
    } catch (_) {
      d = {'recortado': true};
    }
    // id: uuid propio de cada evento, para que un lote reenviado (falló la respuesta, no el insert) no se cuente dos
    // veces (imperio_registrar lo ignora con on conflict). Viaja en la cola de disco con el evento.
    _cola.add({'id': idSesion(_azar), 'evento': evento, 'datos': d, 'sesion': sesion, 'version': version, 'ms': _reloj()});
    _recortar();
    _cargar();
    _programarGuardado();
  }

  /// Manda la cola en lotes de 100 y quita lo enviado. Si un lote falla, para y lo deja para la próxima.
  Future<void> vaciar() async {
    if (_vaciando) return;
    _vaciando = true;
    try {
      await _cargar();
      while (_cola.isNotEmpty) {
        final lote = _cola.take(tamanoLote).toList();
        try {
          await _enviar(lote);
        } catch (_) {
          break;
        }
        final enviados = Set<Map<String, Object?>>.identity()..addAll(lote);
        _cola.removeWhere(enviados.contains);
      }
      await guardar();
    } catch (_) {
    } finally {
      _vaciando = false;
    }
  }

  /// Escribe la cola en disco ya (al pausar).
  Future<void> guardar() async {
    try {
      await _cargar();
      final p = await SharedPreferences.getInstance();
      await p.setString(clavePrefs, jsonEncode(_cola));
    } catch (_) {}
  }

  void _programarGuardado() {
    if (_guardadoPendiente) return;
    _guardadoPendiente = true;
    Future<void>(() async {
      _guardadoPendiente = false;
      await guardar();
    });
  }

  /// Trae una sola vez lo que quedó en disco de sesiones anteriores y lo pone delante.
  Future<void> _cargar() => _carga ??= () async {
        try {
          final p = await SharedPreferences.getInstance();
          final s = p.getString(clavePrefs);
          if (s == null) return;
          final j = jsonDecode(s);
          if (j is! List) return;
          final viejos = [for (final e in j) if (e is Map && e['evento'] is String) Map<String, Object?>.from(e)];
          _cola.insertAll(0, viejos);
          _recortar();
        } catch (_) {}
      }();

  void _recortar() {
    if (_cola.length > maxCola) _cola.removeRange(0, _cola.length - maxCola);
  }

  // JSON seguro: sin NaN/infinito (jsonEncode los rechaza), textos cortos, poca profundidad.
  static Object? _limpiar(Object? v, int nivel) {
    if (v == null || v is bool || v is int) return v;
    if (v is num) return v.isFinite ? v : null;
    if (v is String) return v.length > 200 ? v.substring(0, 200) : v;
    if (v is Enum) return v.name;
    if (nivel >= 3) return '$v';
    if (v is Map) return _limpiarMapa(v, nivel + 1);
    if (v is Iterable) return [for (final x in v.take(50)) _limpiar(x, nivel + 1)];
    return '$v';
  }

  static Map<String, Object?> _limpiarMapa(Map<dynamic, dynamic> m, int nivel) => {
        for (final e in m.entries.take(40)) '${e.key}': _limpiar(e.value, nivel),
      };
}
