import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

Future<void> cancelarRecordatorio() => notificaciones.cancel(id: _id);
