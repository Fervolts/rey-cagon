import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _id = 1;
const _hora = 20;
final notificaciones = FlutterLocalNotificationsPlugin();

const _detalles = NotificationDetails(
  android: AndroidNotificationDetails(
    'recordatorio',
    'Recordatorio diario',
    channelDescription: 'Te pregunta si ya cagaste hoy',
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
    title: 'Hey, ¿has cagado hoy??? 💩',
    body: 'Tus amigos te están sacando ventaja en el ranking.',
    scheduledDate: cuando,
    notificationDetails: _detalles,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<void> cancelarRecordatorio() => notificaciones.cancel(id: _id);
