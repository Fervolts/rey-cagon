import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'genero.dart';
import 'idioma.dart';
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
Future<void> limpiarWidget() => _pintar(hoy: 0, estado: tr('ABRE LA APP', 'OPEN THE APP'));

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
    frase = global ? tr('Eres el único. Invita a alguien', "You're the only one. Invite someone") : tr('Estás cagando solo. Sigue a tus amigos', "You're pooping alone. Follow your friends");
  } else if (filas.first['total'] == 0) {
    frase = tr('Nadie ha cagado esta semana. Estrena el trono', 'Nobody has pooped this week. Break in the throne');
  } else if (rey) {
    final segundo = filas[1]['total'] as int;
    frase = mio == segundo
        ? tr('${segun('Rey empatado', 'Reina empatada')}. Una más y es tuyo', 'Tied for ${segun('king', 'queen')}. One more and it is yours')
        : tr('${global ? segun('Rey del mundo', 'Reina del mundo') : segun('Eres el rey', 'Eres la reina')}. Le llevas ${mio - segundo} al segundo',
            '${global ? segun('King of the world', 'Queen of the world') : segun("You're the king", "You're the queen")}. You lead the runner-up by ${mio - segundo}');
  } else {
    final arriba = filas[i - 1];
    final falta = (arriba['total'] as int) - mio + 1;
    frase = falta == 1
        ? tr('Una más y pasas a ${arriba['username']}', 'One more and you pass ${arriba['username']}')
        : tr('Te faltan $falta para pasar a ${arriba['username']}', 'You need $falta to pass ${arriba['username']}');
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
  await HomeWidget.saveWidgetData<String>('${c}_de', tr('DE ${filas.length} · ${global ? 'TODOS · SEMANA' : 'SEMANA'}', 'OF ${filas.length} · ${global ? 'EVERYONE · WEEK' : 'WEEK'}'));
  await HomeWidget.saveWidgetData<String>('${c}_frase', frase);
  await HomeWidget.saveWidgetData<bool>('${c}_rey', rey);
  await HomeWidget.updateWidget(qualifiedAndroidName: global ? _proveedorGlobal : _proveedorRanking);
}

/// Supabase para código que corre sin la app abierta (widget, push en segundo plano).
///
/// Este motor y el de la app comparten la sesión guardada en el teléfono, pero no la memoria.
/// Si los dos renuevan el token por su cuenta, uno termina usando un token viejo y el servidor
/// lo toma como robado: revoca la sesión y la app pide iniciar sesión otra vez. Por eso aquí no
/// se renueva solo ni se guarda nada: solo la app escribe la sesión, y este motor la relee.
/// Devuelve null si no hay una sesión vigente con la que consultar.
Future<SupabaseClient?> clienteDeFondo() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      authOptions: const FlutterAuthClientOptions(
        // Sin actividad no hay deep links que escuchar.
        detectSessionInUri: false,
        autoRefreshToken: false,
        persistSession: false,
      ),
    );
  } catch (_) {
    // Ya estaba inicializado en este motor.
  }
  final db = Supabase.instance.client;
  await _tomarSesion(db);
  // Con una sesión vencida cualquier consulta intentaría renovarla con el token en memoria,
  // que puede ser viejo: mejor no consultar.
  final sesion = db.auth.currentSession;
  return sesion == null || sesion.isExpired ? null : db;
}

/// Carga la sesión que guardó la app si la de este motor falta o ya venció.
Future<void> _tomarSesion(SupabaseClient db) async {
  final actual = db.auth.currentSession;
  if (actual != null && !actual.isExpired) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    // La app pudo escribirla en otro motor después de abrir este: hay que releer el disco.
    await prefs.reload();
    // Misma clave que usa supabase_flutter al guardar la sesión.
    final guardada = prefs.getString('sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token');
    if (guardada == null) return;
    final sesion = Session.fromJson(jsonDecode(guardada) as Map<String, dynamic>);
    if (sesion == null) return;
    if (!sesion.isExpired) {
      await db.auth.recoverSession(guardada);
    } else if (sesion.refreshToken != null) {
      // Renueva solo en memoria a partir del último token de la app. El servidor acepta que la
      // app vuelva a usar ese mismo token después (le devuelve el nuevo), así que no hay choque.
      await db.auth.setSession(sesion.refreshToken!);
    }
  } catch (_) {
    // Sin internet o sesión inválida: el que llama ve que no hay sesión.
  }
}

/// Toque en el botón del widget. Corre en un motor de Flutter aparte, sin la app abierta,
/// usando la sesión guardada en el teléfono.
@pragma('vm:entry-point')
Future<void> widgetCague(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await cargarGenero();
  await _pintar(estado: '...');
  final db = await clienteDeFondo();
  if (db == null) return _pintar(estado: tr('ABRE LA APP', 'OPEN THE APP'));

  String? aviso;
  try {
    await db.from('cagadas').insert({});
    aviso = '+1 💩';
  } on PostgrestException catch (e) {
    // El trigger limitar_cagadas indica los minutos que faltan.
    final min = RegExp(r'Espera (\d+) min').firstMatch(e.message)?.group(1);
    aviso = min == null ? 'ERROR' : tr('ESPERA $min MIN', 'WAIT $min MIN');
  } catch (_) {
    aviso = tr('SIN INTERNET', 'NO INTERNET');
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
