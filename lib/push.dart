import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'actualizar.dart' show esDePlay, versionAnunciada;
import 'avisos.dart' show ir;
import 'idioma.dart' show idioma, tr;
import 'imperio/regalos.dart' show irARegalos;
import 'main.dart' show db;
import 'recordatorio.dart' show cancelarAvisoImperio, clavePocetaLocal, notificaciones;
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
    final db = await clienteDeFondo();
    if (db != null) await refrescarRanking(db);
  } catch (_) {}
}

/// Tocaron el push: abrir donde corresponde. Las cagadas y las versiones abren la app y ya.
/// data['envio'] (id en push_envios) se marca como tocado para medir qué avisos sirven.
void _alTocar(RemoteMessage m) {
  final envio = int.tryParse('${m.data['envio']}');
  if (envio != null) db.rpc('push_tocado', params: {'p_id': envio}).catchError((_) {});
  if (m.data['tipo'] == 'respuesta') {
    ir(m.data['sala'] ?? 'todos', hilo: int.tryParse('${m.data['hilo']}'));
    return;
  }
  if (m.data['tipo'] == 'ganadores' || m.data['tipo'] == 'cierre') {
    ir('ranking', periodo: m.data['periodo']);
    return;
  }
  // RAMPAGE / HEXAKILL: queda en el centro de avisos y de ahí se abre el perfil del amigo.
  if (m.data['tipo'] == 'cagada' && m.data['subtipo'] != null) {
    ir('avisos', usuario: m.data['user_id']);
    return;
  }
  if (m.data['tipo'] == 'regalo') {
    irARegalos();
    return;
  }
  final destino = switch (m.data['tipo']) {
    'mencion' || 'reporte_chat' => m.data['sala'] ?? 'todos',
    'soporte' => 'soporte',
    'reto' => 'inicio',
    'follow' || 'placer' || 'anuncio' => 'avisos',
    'poceta' => m.data['subtipo'] == 'constipado' ? 'inicio' : 'imperio',
    'racha' => 'imperio',
    _ => null,
  };
  if (destino != null) ir(destino);
}

AppLifecycleListener? _ciclo;
DateTime? _ultimaApertura;

/// Abrió la app (arranque o vuelta al frente): RPC push_abri_app, a lo sumo una vez cada 5 min.
/// Sirve para no mandar la poceta a quien ya entró hoy y para medir "abrió sin tocar el push".
void registrarApertura() {
  if (db.auth.currentUser == null) return;
  final ahora = DateTime.now();
  if (_ultimaApertura != null && ahora.difference(_ultimaApertura!) < const Duration(minutes: 5)) return;
  _ultimaApertura = ahora;
  db.rpc('push_abri_app').catchError((_) {});
}

Future<void> iniciarPush() async {
  _ciclo ??= AppLifecycleListener(onResume: registrarApertura);
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_alFondo);
  await notificaciones
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_canal);
  // Con la app abierta Android no pinta el push solo: lo mostramos nosotros.
  FirebaseMessaging.onMessage.listen((m) {
    // Versión nueva con la app abierta: además del aviso, se ofrece ya (el toque al aviso local no abre nada).
    if (m.data['tipo'] == 'version') versionAnunciada.value++;
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
  FirebaseMessaging.onMessageOpenedApp.listen(_alTocar);
  final inicial = await FirebaseMessaging.instance.getInitialMessage();
  if (inicial != null) _alTocar(inicial);
  registrarApertura();
  // getToken/onTokenRefresh están deprecados a favor de register()/FID, pero la Edge Function
  // manda por `message.token` de FCM HTTP v1, que sigue siendo el token clásico.
  // ignore: deprecated_member_use
  FirebaseMessaging.instance.onTokenRefresh.listen(_guardar);
}

Future<void> _guardar(String token) async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) return;
  final build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
  final fila = {
    'token': token,
    'user_id': uid,
    'app_build': build,
    'canal': esDePlay ? 'play' : 'directo',
    'idioma': idioma.value,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
  String? zona;
  try {
    zona = (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (_) {}
  if (zona == null) {
    await db.from('push_tokens').upsert(fila);
    return;
  }
  try {
    // zona: para mandar la poceta en el horario de cada quien.
    await db.from('push_tokens').upsert({...fila, 'zona': zona});
  } on PostgrestException {
    // Base sin la columna zona todavía.
    await db.from('push_tokens').upsert(fila);
  }
}

/// Llamar con sesión abierta: asocia este teléfono al usuario para recibir los avisos.
Future<void> registrarTelefono() async {
  // ignore: deprecated_member_use
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await _guardar(token);
  registrarApertura();
}

/// Antes de cerrar sesión, para que este teléfono deje de recibir avisos de esa cuenta.
Future<void> olvidarTelefono() async {
  // ignore: deprecated_member_use
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await db.from('push_tokens').delete().eq('token', token);
}

/// Interruptor "Avisos de la poceta" (ajustes de la tuerca): opt-out en push_ajustes.poceta.
class FilaAvisosPoceta extends StatefulWidget {
  const FilaAvisosPoceta({super.key});

  @override
  State<FilaAvisosPoceta> createState() => _FilaAvisosPocetaState();
}

class _FilaAvisosPocetaState extends State<FilaAvisosPoceta> {
  bool? _activo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final fila = await db.from('push_ajustes').select('poceta').eq('user_id', uid).maybeSingle();
      final activo = (fila?['poceta'] as bool?) ?? true;
      unawaited(SharedPreferences.getInstance().then((p) => p.setBool(clavePocetaLocal, activo)));
      if (mounted) setState(() => _activo = activo);
    } catch (_) {
      // Sin la tabla todavía (o sin red): se muestra encendido y se deja tocar igual.
      if (mounted) setState(() => _activo = true);
    }
  }

  Future<void> _cambiar(bool v) async {
    final antes = _activo;
    setState(() => _activo = v);
    try {
      await db.rpc('push_poceta', params: {'p_activo': v});
      unawaited(SharedPreferences.getInstance().then((p) => p.setBool(clavePocetaLocal, v)));
      if (!v) unawaited(cancelarAvisoImperio());
    } catch (_) {
      if (!mounted) return;
      setState(() => _activo = antes);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr('No se pudo guardar. Intenta otra vez.', "Couldn't save. Try again."))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: Text(tr('Avisos de la poceta', 'Toilet alerts')),
      subtitle: Text(tr('Lo que hizo tu Imperio y si llevas rato sin cagar', 'What your Empire made and if you haven\'t pooped in a while')),
      value: _activo ?? true,
      onChanged: _activo == null ? null : _cambiar,
    );
  }
}
