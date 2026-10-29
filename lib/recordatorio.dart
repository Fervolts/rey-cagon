import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'genero.dart';
import 'idioma.dart';

const _id = 1;
const _hora = 20;
final notificaciones = FlutterLocalNotificationsPlugin();

NotificationDetails get _detalles => NotificationDetails(
  android: AndroidNotificationDetails(
    'recordatorio',
    tr('Recordatorio diario', 'Daily reminder'),
    channelDescription: tr('Te pregunta si ya cagaste hoy', 'Asks if you already pooped today'),
  ),
);

Future<void> iniciarRecordatorio() async {
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('America/Caracas'));
  }
  await notificaciones.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_poop'),
    ),
  );
}

/// Aparte de [iniciarRecordatorio] para no pedir el permiso antes de que se pinte la app.
Future<void> pedirPermisoNotificaciones() async {
  await notificaciones
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

/// Un solo aviso pendiente a las 8pm: hoy si todavía no registraste nada, si no mañana.
/// Se reprograma cada vez que se abre la app o se registra/deshace una cagada.
Future<void> reprogramarRecordatorio({required bool yaCagoHoy}) async {
  final ahora = tz.TZDateTime.now(tz.local);
  var cuando = tz.TZDateTime(tz.local, ahora.year, ahora.month, ahora.day, _hora);
  if (yaCagoHoy || !cuando.isAfter(ahora)) cuando = cuando.add(const Duration(days: 1));
  await notificaciones.cancel(id: _id);
  await notificaciones.zonedSchedule(
    id: _id,
    title: tr('Hey, ¿has cagado hoy??? 💩', 'Hey, have you pooped today??? 💩'),
    body: tr('Tus amigos te están sacando ventaja en el ranking.', 'Your friends are pulling ahead on the leaderboard.'),
    scheduledDate: cuando,
    notificationDetails: _detalles,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<void> cancelarRecordatorio() async {
  await notificaciones.cancel(id: _id);
  await cancelarCierres();
}

// Avisos de que se acaba la semana, el mes o el año. Ids 100 a 107, a las 6pm de Caracas.
const _primerCierre = 100;
const _cuantosCierres = 8;

NotificationDetails get _detallesCierre => NotificationDetails(
  android: AndroidNotificationDetails(
    'cierres',
    tr('Cierre del ranking', 'Leaderboard closing'),
    channelDescription: tr('Te avisa cuando se acaba la semana, el mes o el año', 'Tells you when the week, month or year is ending'),
  ),
);

/// Título y texto del aviso de ese día de Caracas, o null si ese día no toca. Uno por día como
/// máximo: si coinciden, gana el año, después el mes y después la semana.
(String, String)? _avisoDelDia(DateTime dia) {
  final ultimoDelMes = dia.add(const Duration(days: 1)).month != dia.month;
  if (dia.month == 12 && dia.day == 31) {
    return (tr('Último día del año 🎆', 'Last day of the year 🎆'),
        tr('A medianoche se cierra el ranking del año. Una más para la historia 💩', 'The yearly leaderboard closes at midnight. One more for the history books 💩'));
  }
  if (dia.month == 12 && dia.day == 25) {
    return (tr('Faltan 7 días para que termine el año', '7 days left in the year'),
        tr('El trono del año se decide el 31. ¿Vas a dejar que te lo quiten?', 'The throne of the year is decided on the 31st. Are you letting them take it?'));
  }
  if (ultimoDelMes) {
    return (tr('Hoy se acaba el mes 🗓️', 'The month ends today 🗓️'),
        tr('A medianoche sale ${segun('el rey', 'la reina')} del mes. Todavía te da tiempo.', 'At midnight we crown the champion of the month. You still have time.'));
  }
  if (dia.add(const Duration(days: 3)).month != dia.month) {
    return (tr('Faltan 3 días para que termine el mes', '3 days left in the month'),
        tr('Todavía puedes remontar en el ranking del mes 🚽', 'You can still climb the monthly leaderboard 🚽'));
  }
  if (dia.weekday == DateTime.sunday) {
    return (tr('Último día de la semana ⏳', 'Last day of the week ⏳'),
        tr('El ranking semanal cierra a medianoche. Una más y quién sabe 💩', 'The weekly leaderboard closes at midnight. One more and who knows 💩'));
  }
  return null;
}

/// Deja programados los próximos avisos de cierre. Se llama junto con el recordatorio diario.
Future<void> reprogramarCierres() async {
  await cancelarCierres();
  final ahora = DateTime.now().toUtc();
  // Hoy en Caracas, guardado en una fecha UTC para contar días sin horario de verano.
  final c = ahora.add(const Duration(hours: -4));
  var id = _primerCierre;
  for (var i = 0; i < 60 && id < _primerCierre + _cuantosCierres; i++) {
    final dia = DateTime.utc(c.year, c.month, c.day + i);
    final aviso = _avisoDelDia(dia);
    // 6pm de Caracas son las 22:00 UTC.
    final cuando = dia.add(const Duration(hours: 22));
    if (aviso == null || !cuando.isAfter(ahora)) continue;
    await notificaciones.zonedSchedule(
      id: id++,
      title: aviso.$1,
      body: aviso.$2,
      scheduledDate: tz.TZDateTime.from(cuando, tz.local),
      notificationDetails: _detallesCierre,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

Future<void> cancelarCierres() async {
  for (var id = _primerCierre; id < _primerCierre + _cuantosCierres; id++) {
    await notificaciones.cancel(id: id);
  }
}
