import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'main.dart' show db;
import 'recordatorio.dart' show notificaciones;

// Mismo id que manda la Edge Function notificar-cagada en android.notification.channel_id.
const _canal = AndroidNotificationChannel(
  'cagadas',
  'Cagadas de tus panas',
  description: 'Avisa cuando alguien registra una cagada',
  importance: Importance.high,
);

Future<void> initPush() async {
  await Firebase.initializeApp();
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
  await db.from('push_tokens').upsert({
    'token': token,
    'user_id': uid,
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
