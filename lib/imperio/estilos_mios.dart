// Lo que compraste en la tienda de estilo y lo que tienes puesto. La compra vive en la base (imperio_estilos);
// aquí hay una copia local para arrancar sin red. El tema lo pone lib/tema.dart, el efecto de CAGUÉ es local
// (lib/efecto_cague.dart) y el movimiento del avatar se guarda en profiles.movimiento (lo ven todos).
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../main.dart' show conReintento, db;
import '../movimientos_avatar.dart' show ponerMovimientoAvatar;
import '../tema.dart';
import 'estilos.dart';

/// Ids comprados (sin los gratis: esos se tienen siempre, ver [tieneEstilo]).
final estilosComprados = ValueNotifier<Set<String>>(<String>{});

/// Efecto del botón CAGUÉ en uso.
final efectoElegido = ValueNotifier<String>(efectoNinguno);

/// Movimiento del avatar en uso (el de tu perfil).
final movimientoElegidoAvatar = ValueNotifier<String>(movimientoNinguno);

const _prefEfecto = 'efecto_cague';

/// ¿Tienes este estilo? Los gratis siempre.
bool tengoEstilo(String id) => tieneEstilo(estilosComprados.value, id);

/// El que tienes puesto de un tipo.
String estiloEnUso(TipoEstilo tipo) => switch (tipo) {
      TipoEstilo.tema => estiloTema.value,
      TipoEstilo.efecto => efectoElegido.value,
      TipoEstilo.movimiento => movimientoElegidoAvatar.value,
    };

/// Al arrancar (después de iniciarTema): la copia local de lo comprado y el efecto elegido.
Future<void> iniciarEstilos() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    estilosComprados.value = (prefs.getStringList(prefEstilosComprados) ?? const <String>[]).toSet();
    final efecto = prefs.getString(_prefEfecto) ?? efectoNinguno;
    efectoElegido.value = _valido(efecto, TipoEstilo.efecto) ? efecto : efectoNinguno;
  } catch (_) {}
}

bool _valido(String id, TipoEstilo tipo) => estiloPorId(id)?.tipo == tipo && tengoEstilo(id);

Future<void> _guardarCopia(Set<String> ids) async {
  estilosComprados.value = ids;
  try {
    await (await SharedPreferences.getInstance()).setStringList(prefEstilosComprados, ids.toList()..sort());
  } catch (_) {}
}

/// Trae de la base lo comprado (RPC imperio_estilos_mios) y el movimiento de tu perfil. Si lo que tienes puesto ya no
/// está comprado, vuelve al de fábrica. Lanza el error de red sin tocar nada.
Future<void> cargarEstilosMios() async {
  final r = await conReintento(() => db.rpc('imperio_estilos_mios'));
  final ids = {for (final v in (r as List? ?? const [])) if (v is String && estiloPorId(v) != null) v};
  await _guardarCopia(ids);
  if (!_valido(estiloTema.value, TipoEstilo.tema)) await elegirEstiloTema(temaClasico);
  if (!_valido(efectoElegido.value, TipoEstilo.efecto)) await elegirEfecto(efectoNinguno);
  try {
    final yo = db.auth.currentUser?.id;
    if (yo == null) return;
    final fila = await db.from('profiles').select('movimiento').eq('id', yo).maybeSingle();
    final mov = fila?['movimiento'] as String?;
    movimientoElegidoAvatar.value = mov != null && _valido(mov, TipoEstilo.movimiento) ? mov : movimientoNinguno;
  } catch (_) {
    // Columna todavía sin migrar o sin red: se queda el que había.
  }
}

/// Compra en la base (RPC imperio_estilo_comprar) y deja la copia local al día. Lanza el error (en español del
/// servidor, o de red). No descuenta MJ ni Rollos: eso lo hace ControlImperio.comprarEstilo.
Future<void> comprarEstiloEnBase(String id) async {
  final r = await db.rpc('imperio_estilo_comprar', params: {'p_id': id});
  final lista = r is Map ? r['comprados'] : null;
  final ids = {
    ...estilosComprados.value,
    id,
    for (final v in (lista is List ? lista : const [])) if (v is String && estiloPorId(v) != null) v,
  };
  await _guardarCopia(ids);
}

/// Pone el efecto de CAGUÉ (local, solo lo ves tú).
Future<void> elegirEfecto(String id) async {
  efectoElegido.value = estiloPorId(id)?.tipo == TipoEstilo.efecto ? id : efectoNinguno;
  try {
    await (await SharedPreferences.getInstance()).setString(_prefEfecto, efectoElegido.value);
  } catch (_) {}
}

/// Pone el movimiento del avatar en tu perfil (lo ven todos) con `ponerMovimientoAvatar` de lib/movimientos_avatar.dart
/// (mov_ninguno se guarda como null y el trigger del servidor valida). Lanza el error de red.
Future<void> guardarMovimiento(String id) async {
  if (db.auth.currentUser == null) throw StateError('Sin sesión');
  await ponerMovimientoAvatar(id);
  movimientoElegidoAvatar.value = id;
}
