import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'actualizar.dart' show esDePlay;
import 'main.dart' show db;
import 'recordatorio.dart' show notificaciones;
import 'widget.dart' show clienteDeFondo, refrescarRanking;

// Mismo id que usa la Edge Function notificaciones en android.notification.channel_id.
const _canal = AndroidNotificationChannel(
  'cagadas',
  'Cagadas de tus amigos',
  description: 'Avisa cuando alguien registra una cagada',
  importance: Importance.high,
);

/// Push con la app cerrada o en segundo plano: si alguien cagó, se refresca el widget de ranking.
@pragma('vm:entry-point')
Future<void> _alFondo(RemoteMessage m) async {
  if (m.data['tipo'] != 'cagada') return;
  try {
    await refrescarRanking(await clienteDeFondo());
  } catch (_) {}
}

Future<void> iniciarPush() async {
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_alFondo);
  await notificaciones
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_canal);
  // Con la app abierta Android no pinta el push solo: lo mostramos nosotros.
  FirebaseMessaging.onMessage.listen((m) {
    final n = m.notification;
    if (n == null) return;
    notificaciones.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_canal.id, _canal.name,
            channelDescription: _canal.description, importance: Importance.high, priority: Priority.high),
      ),
    );
  });
  // getToken/onTokenRefresh están deprecados a favor de register()/FID, pero la Edge Function
  // manda por `message.token` de FCM HTTP v1, que sigue siendo el token clásico.
  // ignore: deprecated_member_use
  FirebaseMessaging.instance.onTokenRefresh.listen(_guardar);
}

Future<void> _guardar(String token) async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) return;
  final build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
  await db.from('push_tokens').upsert({
    'token': token,
    'user_id': uid,
    'app_build': build,
    'canal': esDePlay ? 'play' : 'directo',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}

/// Llamar con sesión abierta: asocia este teléfono al usuario para recibir los avisos.
Future<void> registrarTelefono() async {
  // ignore: deprecated_member_use
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await _guardar(token);
}

/// Antes de cerrar sesión, para que este teléfono deje de recibir avisos de esa cuenta.
Future<void> olvidarTelefono() async {
  // ignore: deprecated_member_use
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await db.from('push_tokens').delete().eq('token', token);
}
