import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show supabaseKey, supabaseUrl;

const _proveedor = 'com.ahimismito.rey_cagon.ReyCagonWidget';

// Mismo día que usa leaderboard(): Venezuela, UTC-4 fijo.
String _hoyCaracas() => DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String().substring(0, 10);

Future<void> _pintar({int? hoy, String? estado}) async {
  if (hoy != null) {
    await HomeWidget.saveWidgetData<String>('fecha', _hoyCaracas());
    await HomeWidget.saveWidgetData<String>('hoy', '$hoy');
  }
  await HomeWidget.saveWidgetData<String>('estado', estado);
  await HomeWidget.updateWidget(qualifiedAndroidName: _proveedor);
}

/// La app llama esto cada vez que recarga el ranking, para que el widget muestre el contador del día.
Future<void> actualizarWidget(int hoy) => _pintar(hoy: hoy);

/// Al cerrar sesión el widget no debe seguir mostrando la cuenta de otro.
Future<void> limpiarWidget() => _pintar(hoy: 0, estado: 'ABRE LA APP');

Future<int> _contarHoy(SupabaseClient db) async {
  final filas = await db.rpc('leaderboard', params: {'period': 'day', 'solo_siguiendo': true});
  final yo = (filas as List).where((r) => r['user_id'] == db.auth.currentUser!.id).firstOrNull;
  return (yo?['total'] ?? 0) as int;
}

/// Toque en el círculo del widget. Corre en un motor de Flutter aparte, sin la app abierta:
/// inicializa Supabase con la sesión guardada en el teléfono y registra la cagada.
@pragma('vm:entry-point')
Future<void> widgetCague(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _pintar(estado: '...');
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      // Sin actividad no hay deep links que escuchar.
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  } catch (_) {
    // Ya estaba inicializado en este motor.
  }
  final db = Supabase.instance.client;
  if (db.auth.currentSession == null) return _pintar(estado: 'ABRE LA APP');

  String? aviso;
  try {
    await db.from('cagadas').insert({});
    aviso = '+1 💩';
  } on PostgrestException catch (e) {
    // El trigger limitar_cagadas dice cuánto falta ("Espera N min más.").
    final min = RegExp(r'Espera (\d+) min').firstMatch(e.message)?.group(1);
    aviso = min == null ? 'ERROR' : 'ESPERA $min MIN';
  } catch (_) {
    aviso = 'SIN INTERNET';
  }
  int? hoy;
  try {
    hoy = await _contarHoy(db);
  } catch (_) {}
  await _pintar(hoy: hoy, estado: aviso);
  // El aviso dura un rato y vuelve al contador.
  await Future<void>.delayed(const Duration(seconds: 4));
  await _pintar(estado: null);
}

Future<void> initWidget() => HomeWidget.registerInteractivityCallback(widgetCague);
