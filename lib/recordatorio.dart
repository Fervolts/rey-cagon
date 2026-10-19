import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _id = 1;
const _hora = 20;
final _plugin = FlutterLocalNotificationsPlugin();

const _detalles = NotificationDetails(
  android: AndroidNotificationDetails(
    'recordatorio',
    'Recordatorio diario',
    channelDescription: 'Te pregunta si ya cagaste hoy',
  ),
);

Future<void> initRecordatorio() async {
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('America/Caracas'));
  }
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

/// Aparte de [initRecordatorio] para no pedir el permiso antes de que se pinte la app.
Future<void> pedirPermisoNotificaciones() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

/// Un solo aviso pendiente a las 8pm: hoy si todavía no registraste nada, si no mañana.
/// Se reprograma cada vez que se abre la app o se registra/deshace una cagada.
Future<void> reprogramarRecordatorio({required bool yaCagoHoy}) async {
  final ahora = tz.TZDateTime.now(tz.local);
  var cuando = tz.TZDateTime(tz.local, ahora.year, ahora.month, ahora.day, _hora);
  if (yaCagoHoy || !cuando.isAfter(ahora)) cuando = cuando.add(const Duration(days: 1));
  await _plugin.cancel(id: _id);
  await _plugin.zonedSchedule(
    id: _id,
    title: 'Hey, ¿has cagado hoy??? 💩',
    body: 'Tus panas te están sacando ventaja en el ranking.',
    scheduledDate: cuando,
    notificationDetails: _detalles,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<void> cancelarRecordatorio() => _plugin.cancel(id: _id);
