import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/chat_vivo.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => idioma.value = 'es');

  group('textoEscribiendo', () {
    test('uno, dos y varios en español', () {
      expect(textoEscribiendo([]), '');
      expect(textoEscribiendo(['ana']), 'ana está escribiendo');
      expect(textoEscribiendo(['ana', 'beto']), 'ana y beto están escribiendo');
      expect(textoEscribiendo(['ana', 'beto', 'caro']), 'Varios están escribiendo');
    });

    test('en inglés', () {
      idioma.value = 'en';
      expect(textoEscribiendo(['ana']), 'ana is typing');
      expect(textoEscribiendo(['ana', 'beto']), 'ana and beto are typing');
      expect(textoEscribiendo(['ana', 'beto', 'caro', 'dani']), 'Several people are typing');
    });
  });

  group('Escribiendo', () {
    final t0 = DateTime(2026, 11, 2, 12);

    test('vence a los 5 s sin señal', () {
      final e = Escribiendo()..senal('a', {'username': 'ana'}, ahora: t0);
      expect(e.vigentes(ahora: t0.add(const Duration(seconds: 4))), ['a']);
      expect(e.vigentes(ahora: t0.add(vidaEscribiendo)), isEmpty);
      expect(e.proximoVencimiento, t0.add(vidaEscribiendo));
      expect(e.limpiar(t0.add(const Duration(seconds: 4))), isFalse);
      expect(e.limpiar(t0.add(const Duration(seconds: 6))), isTrue);
      expect(e.vacio, isTrue);
      expect(e.proximoVencimiento, isNull);
    });

    test('otra señal alarga la vida', () {
      final e = Escribiendo()
        ..senal('a', {}, ahora: t0)
        ..senal('a', {}, ahora: t0.add(const Duration(seconds: 3)));
      expect(e.vigentes(ahora: t0.add(const Duration(seconds: 7))), ['a']);
    });

    test('quitar al llegar su mensaje', () {
      final e = Escribiendo()..senal('a', {}, ahora: t0);
      expect(e.quitar('a'), isTrue);
      expect(e.quitar('a'), isFalse);
      expect(e.vigentes(ahora: t0), isEmpty);
    });

    test('la sala y cada hilo van aparte, en orden de llegada', () {
      final e = Escribiendo()
        ..senal('a', {}, ahora: t0)
        ..senal('b', {}, hilo: '7', ahora: t0)
        ..senal('c', {}, ahora: t0);
      expect(e.vigentes(ahora: t0), ['a', 'c']);
      expect(e.vigentes(hilo: '7', ahora: t0), ['b']);
      expect(e.vigentes(hilo: '8', ahora: t0), isEmpty);
    });
  });

  test('Latido deja pasar uno cada 2.5 s', () {
    final t0 = DateTime(2026, 11, 2, 12);
    final l = Latido();
    expect(l.toca(t0), isTrue);
    expect(l.toca(t0.add(const Duration(seconds: 1))), isFalse);
    expect(l.toca(t0.add(pausaEscribiendo)), isTrue);
    l.reiniciar();
    expect(l.toca(t0.add(pausaEscribiendo)), isTrue);
  });

  group('partirMenciones', () {
    test('solo nombres conocidos, sin importar mayúsculas', () {
      expect(partirMenciones('hola @Pepe y @nadie', ['pepe']), [const Mencion(5, 10, 'pepe')]);
    });

    test('la @ no va pegada a una letra', () {
      expect(partirMenciones('@pepe hola', ['pepe']), [const Mencion(0, 5, 'pepe')]);
      expect(partirMenciones('correo@pepe', ['pepe']), isEmpty);
    });

    test('después del nombre no puede seguir una letra, sí puntuación', () {
      expect(partirMenciones('@pepeto', ['pepe']), isEmpty);
      expect(partirMenciones('@pepe, ven', ['pepe']), [const Mencion(0, 5, 'pepe')]);
      expect(partirMenciones('¿@pepe?', ['pepe']), [const Mencion(1, 6, 'pepe')]);
    });

    test('gana el nombre más largo, también con espacios', () {
      expect(partirMenciones('@rey del trono llegó', ['rey', 'rey del trono']), [const Mencion(0, 14, 'rey del trono')]);
      expect(partirMenciones('@rey llegó', ['rey', 'rey del trono']), [const Mencion(0, 4, 'rey')]);
    });

    test('varias en el mismo texto', () {
      final m = partirMenciones('@ana y @beto', ['ana', 'beto']);
      expect(m.map((x) => x.username), ['ana', 'beto']);
    });

    test('sin conocidos no hay nada', () {
      expect(partirMenciones('@ana', []), isEmpty);
    });
  });

  test('candidatosMencion quita la puntuación final', () {
    expect(candidatosMencion('hola @Pepe, (@ana! correo@xy @y'), {'Pepe', 'ana'});
  });

  group('IndicadorEscribiendo', () {
    Future<void> montar(WidgetTester tester, List<Map<String, dynamic>> perfiles, {bool sinAnimar = false}) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        theme: tema(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: sinAnimar),
          child: Scaffold(body: Column(children: [const Spacer(), IndicadorEscribiendo(perfiles: perfiles)])),
        ),
      ));
    }

    testWidgets('vacío no ocupa alto', (tester) async {
      await montar(tester, []);
      expect(tester.getSize(find.byType(IndicadorEscribiendo)).height, 0);
    });

    testWidgets('con movimiento apagado queda quieto', (tester) async {
      await montar(tester, [
        {'id': 'a', 'username': 'ana'},
      ], sinAnimar: true);
      await tester.pumpAndSettle();
      expect(find.text('ana está escribiendo'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con movimiento anima y dice varios', (tester) async {
      movimientoElegido.value = 'completo';
      await montar(tester, [
        {'id': 'a', 'username': 'ana'},
        {'id': 'b', 'username': 'beto'},
        {'id': 'c', 'username': 'caro'},
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Varios están escribiendo'), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
      movimientoElegido.value = 'auto';
    });
  });

  testWidgets('TarjetaMencion muestra nombre y total', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: tema(Brightness.light),
      home: const Scaffold(body: Center(child: TarjetaMencion({'id': 'a', 'username': 'ana', 'cagadas': 12}))),
    ));
    expect(find.text('@ana'), findsOneWidget);
    expect(find.text('12 cagadas'), findsOneWidget);
  });
}
