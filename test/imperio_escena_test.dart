// Escenas v2 del baño: lo que oculta Personalizar, la palanca de la poceta y la hoja de Personalizar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/bano.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/personalizar.dart';
import 'package:rey_cagon/imperio/poceta.dart';

EstadoBano _bano(Map<String, int> cant, Set<String> mejoras, {Map<String, dynamic>? vista}) =>
    EstadoBano.desde(comprada: mejoras.contains, cantidad: (id) => cant[id] ?? 0, vista: vista);

void main() {
  group('EstadoBano.desde con vista', () {
    final cant = {'bano': 3, 'camion': 2, 'planta': 1, 'cloaca': 1, 'granja': 4, 'templo': 1};
    final mejoras = {'bano_1', 'camion_1', 'planta_1', 'cloaca_1', 'granja_1', 'adorno_alfombra'};

    test('sin vista se ve todo y manda el edificio más alto', () {
      final b = _bano(cant, mejoras);
      expect(b.claseMedia, greaterThan(0));
      expect(b.camion, greaterThan(0));
      expect(b.planta, greaterThan(0));
      expect(b.moscas, greaterThan(0));
      expect(b.alfombra, isTrue);
      expect(b.ambiente, AmbienteBano.templo);
    });

    test('lo oculto no se dibuja y el resto sigue igual', () {
      final b = _bano(cant, mejoras, vista: {
        'ocultos': ['camion', 'moscas', 'alfombra']
      });
      expect(b.camion, 0);
      expect(b.moscas, 0);
      expect(b.alfombra, isFalse);
      expect(b.planta, greaterThan(0));
      expect(b.claseMedia, greaterThan(0));
      expect(b, isNot(_bano(cant, mejoras)));
    });

    test('el ambiente elegido manda solo si está desbloqueado', () {
      expect(_bano(cant, mejoras, vista: {'ambiente': 'camion'}).ambiente, AmbienteBano.camion);
      expect(_bano(cant, mejoras, vista: {'ambiente': 'volcan'}).ambiente, AmbienteBano.templo);
      expect(_bano(cant, mejoras, vista: {'ambiente': 'nada'}).ambiente, AmbienteBano.templo);
    });

    test('la vista viaja en la partida y se limpia al leer', () {
      final p = Partida.desdeJson({
        'vista': {
          'ocultos': ['camion', 7],
          'dedos': 99,
          'ambiente': 'publico',
          'otra': true
        }
      });
      expect(p.vista, {
        'ocultos': ['camion', '7'],
        'dedos': 24,
        'ambiente': 'publico'
      });
      expect(Partida.desdeJson(p.toJson()).vista, p.vista);
      expect(Partida().toJson().containsKey('vista'), isFalse);
    });

    test('cada cosa que se puede ocultar tiene id único', () {
      final ids = [for (final o in ocultablesBano) o.id];
      expect(ids.toSet().length, ids.length);
    });
  });

  group('Poceta', () {
    Future<void> poner(WidgetTester tester, Widget poceta) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: poceta))));
    }

    testWidgets('se dibuja con todo lo nuevo', (tester) async {
      final b = _bano({'bano': 8, 'camion': 8, 'planta': 8, 'cloaca': 8, 'granja': 8, 'ciruela': 8},
          {for (final e in ['bano', 'camion', 'planta', 'cloaca', 'granja', 'ciruela']) for (final n in [1, 5, 10, 25]) '${e}_$n'});
      for (final t in [0.5, 12.0, 45.0]) {
        await poner(tester, Poceta(alTocar: () => (texto: '+1', epico: false), mps: 50, bano: b, dedos: 30, apuro: 9, instante: t, jalar: true, cartelJalar: true));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la palanca llama a alJalar; la poceta no', (tester) async {
      var jaladas = 0, pujos = 0;
      await poner(
          tester,
          Poceta(
            alTocar: () {
              pujos++;
              return (texto: '+1', epico: false);
            },
            mps: 1,
            jalar: true,
            alJalar: () => jaladas++,
          ));
      final origen = tester.getTopLeft(find.byType(Poceta));
      final ancho = tester.getSize(find.byType(Poceta)).width;
      await tester.tapAt(origen + Offset(ancho / 2 + 11, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(jaladas, 1);
      expect(pujos, 0);
      await tester.tapAt(origen + Offset(ancho / 2, 160));
      await tester.pump(const Duration(milliseconds: 50));
      expect(pujos, 1);
      expect(jaladas, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin cadena (jalar null) la palanca no existe', (tester) async {
      var jaladas = 0;
      await poner(tester, Poceta(alTocar: () => (texto: '+1', epico: false), mps: 1, alJalar: () => jaladas++));
      final origen = tester.getTopLeft(find.byType(Poceta));
      final ancho = tester.getSize(find.byType(Poceta)).width;
      await tester.tapAt(origen + Offset(ancho / 2 + 11, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(jaladas, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el pincel abre Personalizar', (tester) async {
      var abiertas = 0;
      await poner(tester, Poceta(alTocar: () => (texto: '+1', epico: false), mps: 1, alPersonalizar: () => abiertas++));
      final origen = tester.getTopLeft(find.byType(Poceta));
      final ancho = tester.getSize(find.byType(Poceta)).width;
      await tester.tapAt(origen + Offset(ancho - 20, 20));
      await tester.pump(const Duration(milliseconds: 50));
      expect(abiertas, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Personalizar edita la vista de la partida', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final control = ControlImperio()
      ..imperio = Imperio(
          partida: Partida(edificios: {'templo': 1, 'camion': 2, 'granja': 1, 'dedo': 10}, mejoras: {'camion_1', 'granja_1', 'adorno_alfombra'}));
    final vista = control.imperio.partida.vista;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Personalizar(control: control))));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(find.byKey(const Key('ver_camion')));
    await tester.tap(find.byKey(const Key('ver_camion')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(vista['ocultos'], ['camion']);

    await tester.ensureVisible(find.byKey(const Key('ver_alfombra')));
    await tester.tap(find.byKey(const Key('ver_alfombra')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(vista['ocultos'], ['alfombra', 'camion']);

    await tester.ensureVisible(find.byKey(const Key('ver_camion')));
    await tester.tap(find.byKey(const Key('ver_camion')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(vista['ocultos'], ['alfombra']);

    // Solo los ambientes desbloqueados tienen botón.
    expect(find.byKey(const Key('ambiente_volcan')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('ambiente_camion')));
    await tester.tap(find.byKey(const Key('ambiente_camion')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(vista['ambiente'], 'camion');

    await tester.tap(find.byKey(const Key('personalizar_todo')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(vista, isEmpty);
    expect(find.byKey(const Key('personalizar_dedos')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
