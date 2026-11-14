import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/genero.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/muro.dart';
import 'package:rey_cagon/tema.dart';
import 'package:rey_cagon/vitrina.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _post() => {
      'id': 7,
      'user_id': '00000000-0000-0000-0000-000000000001',
      'texto': 'hola pared',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'likes': 87,
      'yo_like': false,
      'comentarios': 3,
      'username': 'Luisa',
      'cagadas': 60,
      'genero': 'mujer',
      'racha': 12,
      'cloaca_nombre': 'Destapados',
      'top_nombre': 'Pedro',
      'top_texto': 'qué arte',
    };

Future<void> _pintar(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(
    theme: tema(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: w))));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'http://localhost:1',
        publishableKey: 'x',
        authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), detectSessionInUri: false));
  });
  setUp(() {
    idioma.value = 'es';
    miGenero = null;
  });

  test('tituloPorTotal usa el género del autor, no el mío', () {
    expect(tituloPorTotal(60, genero: 'mujer'), 'Reina del barrio');
    expect(tituloPorTotal(60, genero: 'hombre'), 'Rey del barrio');
    expect(tituloPorTotal(60), 'Rey del barrio');
    expect(tituloPorTotal(3, genero: 'mujer'), 'Aprendiz del trono');
  });

  testWidgets('tarjeta: título, racha, Cloaca y último comentario', (t) async {
    await _pintar(t, tarjetaPostDePrueba(_post()));
    expect(find.text('Luisa'), findsOneWidget);
    expect(find.text('Reina del barrio'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.text('DESTAPADOS'), findsOneWidget);
    expect(find.textContaining('Pedro', findRichText: true), findsOneWidget);
    expect(find.textContaining('ver los 3', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('muro_like_7')), findsOneWidget);
    expect(find.textContaining('TRONO DE HOY', findRichText: true), findsNothing);
  });

  testWidgets('trono: encabezado y sin racha ni Cloaca si no hay', (t) async {
    final post = _post()
      ..['racha'] = 0
      ..['cloaca_nombre'] = null
      ..['top_texto'] = null;
    await _pintar(t, tarjetaPostDePrueba(post, trono: true));
    expect(find.textContaining('TRONO DE HOY', findRichText: true), findsOneWidget);
    expect(find.text('DESTAPADOS'), findsNothing);
    expect(find.textContaining('Pedro', findRichText: true), findsNothing);
  });
}
