// Íconos alternos de la app, ganados con logros. La lógica es pura (quién tiene qué); el cambio real lo hace
// MainActivity.kt con activity-alias (canal rey_cagon/icono). Los nombres de alias DEBEN coincidir con el manifest.
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'idioma.dart';
import 'main.dart' show conReintento, db;
import 'vitrina.dart' show cagadasPropias;

/// Un ícono: [id] (también sufijo del recurso `ic_launcher_<id>`), [alias] (sufijo de `.Icono<alias>` en el manifest).
typedef IconoApp = ({String id, String alias, String emoji, String nombreEs, String nombreEn, String comoEs, String comoEn});

const iconosApp = <IconoApp>[
  (id: 'normal', alias: 'Normal', emoji: '💩', nombreEs: 'Normal', nombreEn: 'Classic', comoEs: 'El de siempre.', comoEn: 'The usual one.'),
  (id: 'dorado', alias: 'Dorado', emoji: '🥇', nombreEs: 'Dorado', nombreEn: 'Golden', comoEs: 'Llega a 100 cagadas.', comoEn: 'Reach 100 poops.'),
  (id: 'corona', alias: 'Corona', emoji: '👑', nombreEs: 'Corona', nombreEn: 'Crown', comoEs: 'Abdica al menos una vez en el Imperio.', comoEn: 'Abdicate at least once in the Imperio.'),
  (id: 'noche', alias: 'Noche', emoji: '🌙', nombreEs: 'Noche', nombreEn: 'Night', comoEs: 'Caga 7 días seguidos (Semana perfecta).', comoEn: 'Poop 7 days in a row (Perfect week).'),
  (id: 'cloaca', alias: 'Cloaca', emoji: '🕳️', nombreEs: 'Cloaca', nombreEn: 'Sewer', comoEs: 'Se gana en las Cloacas.', comoEn: 'Earned in the Sewers.'),
];

/// Emoji del premio que otorga el ícono Cloaca (tabla `premios` del servidor).
const premioIconoCloaca = 'icono_cloaca';

/// Lo que el servidor dice del jugador.
typedef DatosIcono = ({int cagadas, int abdicaciones, int mejorRacha, bool premioCloaca});

const datosIconoVacios = (cagadas: 0, abdicaciones: 0, mejorRacha: 0, premioCloaca: false);

/// Racha más larga de días seguidos con al menos una cagada (misma regla que la Semana perfecta de la vitrina).
int mejorRachaDias(Iterable<DateTime> cuando) {
  final dias = {for (final c in cuando) DateTime(c.year, c.month, c.day)}.toList()..sort();
  var seguidos = 0, mejor = 0;
  for (var i = 0; i < dias.length; i++) {
    seguidos = i > 0 && dias[i].difference(dias[i - 1]).inHours.round() <= 25 ? seguidos + 1 : 1;
    if (seguidos > mejor) mejor = seguidos;
  }
  return mejor;
}

/// Ids de los íconos que [d] desbloquea. El normal siempre.
Set<String> iconosGanados(DatosIcono d) => {
      'normal',
      if (d.cagadas >= 100) 'dorado',
      if (d.abdicaciones >= 1) 'corona',
      if (d.mejorRacha >= 7) 'noche',
      if (d.premioCloaca) 'cloaca',
    };

/// ¿Se puede elegir [id]? Ganado, o el que ya está puesto (si se pierde el desbloqueo, el ícono puesto se queda).
bool iconoDisponible(String id, Set<String> ganados, String puesto) => ganados.contains(id) || id == puesto;

IconoApp iconoPorId(String id) => iconosApp.firstWhere((i) => i.id == id, orElse: () => iconosApp.first);

String nombreIcono(IconoApp i) => tr(i.nombreEs, i.nombreEn);
String comoGanarIcono(IconoApp i) => tr(i.comoEs, i.comoEn);

const _canal = MethodChannel('rey_cagon/icono');
const _clave = 'icono_app_elegido';

/// Cambia el ícono (puede tardar segundos o cerrar la app según el launcher). false si falla o no es Android.
Future<bool> ponerIcono(IconoApp i) async {
  try {
    await _canal.invokeMethod('poner', i.alias);
    try {
      (await SharedPreferences.getInstance()).setString(_clave, i.id);
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}

/// El ícono puesto ahora, según el sistema (si no responde, lo último que elegimos, y si no, el normal).
Future<String> iconoPuesto() async {
  try {
    final alias = await _canal.invokeMethod<String>('actual');
    for (final i in iconosApp) {
      if (i.alias == alias) return i.id;
    }
  } catch (_) {}
  try {
    return iconoPorId((await SharedPreferences.getInstance()).getString(_clave) ?? 'normal').id;
  } catch (_) {
    return 'normal';
  }
}

/// De dónde salen los datos de los íconos (en pruebas y demos se cambia por una falsa).
Future<DatosIcono> Function() cargadorDatosIcono = cargarDatosIcono;

/// Carga del servidor lo que desbloquea los íconos. Si algo falla, esa parte queda en cero.
Future<DatosIcono> cargarDatosIcono() async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) return datosIconoVacios;
  var cagadas = 0, abdicaciones = 0, racha = 0;
  var cloaca = false;
  try {
    final p = await conReintento(() => db.from('profiles').select('cagadas').eq('id', uid).maybeSingle());
    cagadas = (p?['cagadas'] as num?)?.toInt() ?? 0;
  } catch (_) {}
  try {
    final f = await conReintento(() => db.from('imperio').select('abdicaciones').eq('user_id', uid).maybeSingle());
    abdicaciones = (f?['abdicaciones'] as num?)?.toInt() ?? 0;
  } catch (_) {}
  try {
    racha = mejorRachaDias((await cagadasPropias(uid)).map((c) => c.cuando));
  } catch (_) {}
  try {
    final f = await conReintento(() => db.from('premios').select('emoji').eq('emoji', premioIconoCloaca));
    cloaca = f.isNotEmpty;
  } catch (_) {}
  return (cagadas: cagadas, abdicaciones: abdicaciones, mejorRacha: racha, premioCloaca: cloaca);
}
