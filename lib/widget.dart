import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show supabaseKey, supabaseUrl;

const _proveedor = 'com.ahimismito.rey_cagon.ReyCagonWidget';
const _proveedorRanking = 'com.ahimismito.rey_cagon.ReyCagonRankingWidget';
const _proveedorGlobal = 'com.ahimismito.rey_cagon.ReyCagonRankingGlobalWidget';

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

/// Widgets de ranking de la semana: entre los que sigues y entre todos. Tu puesto, cuánto te
/// falta para pasar al de arriba y los vecinos.
Future<void> refrescarRanking(SupabaseClient db) async {
  await _pintarRanking(db, global: false);
  await _pintarRanking(db, global: true);
}

Future<void> _pintarRanking(SupabaseClient db, {required bool global}) async {
  final yo = db.auth.currentUser?.id;
  if (yo == null) return;
  final filas = List<Map<String, dynamic>>.from(
    await db.rpc('leaderboard', params: {'period': 'week', 'solo_siguiendo': !global}),
  );
  final i = filas.indexWhere((f) => f['user_id'] == yo);
  if (i < 0) return;
  final mio = filas[i]['total'] as int;
  final rey = i == 0 && mio > 0;

  String frase;
  if (filas.length == 1) {
    frase = global ? 'Eres el único. Invita a alguien' : 'Estás cagando solo. Sigue a tus amigos';
  } else if (filas.first['total'] == 0) {
    frase = 'Nadie ha cagado esta semana. Estrena el trono';
  } else if (rey) {
    final segundo = filas[1]['total'] as int;
    frase = mio == segundo
        ? 'Rey empatado. Una más y es tuyo'
        : '${global ? 'Rey del mundo' : 'Eres el rey'}. Le llevas ${mio - segundo} al segundo';
  } else {
    final arriba = filas[i - 1];
    final falta = (arriba['total'] as int) - mio + 1;
    frase = falta == 1 ? 'Una más y pasas a ${arriba['username']}' : 'Te faltan $falta para pasar a ${arriba['username']}';
  }

  // Ventana de hasta 6 filas que siempre te incluye, con más gente arriba que abajo.
  const maxFilas = 6;
  final desde = (i - 3).clamp(0, (filas.length - maxFilas).clamp(0, filas.length));
  final vecinos = [
    for (var k = desde; k < filas.length && k < desde + maxFilas; k++)
      {'p': k + 1, 'n': filas[k]['username'], 't': filas[k]['total'], 'yo': filas[k]['user_id'] == yo},
  ];
  final c = global ? 'rkg' : 'rk';
  await HomeWidget.saveWidgetData<String>(c, jsonEncode(vecinos));
  await HomeWidget.saveWidgetData<String>('${c}_puesto', (i + 1).toString().padLeft(2, '0'));
  await HomeWidget.saveWidgetData<String>('${c}_de', 'DE ${filas.length} · ${global ? 'TODOS · SEMANA' : 'SEMANA'}');
  await HomeWidget.saveWidgetData<String>('${c}_frase', frase);
  await HomeWidget.saveWidgetData<bool>('${c}_rey', rey);
  await HomeWidget.updateWidget(qualifiedAndroidName: global ? _proveedorGlobal : _proveedorRanking);
}

/// Supabase para código que corre sin la app abierta (widget, push en segundo plano).
Future<SupabaseClient> clienteDeFondo() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  return Supabase.instance.client;
}

/// Toque en el botón del widget. Corre en un motor de Flutter aparte, sin la app abierta,
/// usando la sesión guardada en el teléfono.
@pragma('vm:entry-point')
Future<void> widgetCague(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _pintar(estado: '...');
  final db = await clienteDeFondo();
  if (db.auth.currentSession == null) return _pintar(estado: 'ABRE LA APP');

  String? aviso;
  try {
    await db.from('cagadas').insert({});
    aviso = '+1 💩';
  } on PostgrestException catch (e) {
    // El trigger limitar_cagadas indica los minutos que faltan.
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
  await refrescarRanking(db).catchError((_) {});
  // El aviso dura un rato y vuelve al contador.
  await Future<void>.delayed(const Duration(seconds: 4));
  await _pintar(estado: null);
}

Future<void> iniciarWidget() => HomeWidget.registerInteractivityCallback(widgetCague);
