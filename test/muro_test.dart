import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/muro_dibujo.dart';
import 'package:rey_cagon/tema.dart';

Map<String, dynamic> _valido() => {
      'v': 1,
      'fondo': 8,
      'trazos': [
        {'c': 0, 'g': 2, 'p': [0, 0, 1000, 1000]},
      ],
    };

void main() {
  setUp(() => idioma.value = 'es');

  group('dibujoInvalido (igual que el trigger)', () {
    test('acepta uno bien hecho y un punto solo', () {
      expect(dibujoInvalido(_valido()), isNull);
      expect(dibujoInvalido({'v': 1, 'fondo': 0, 'trazos': [{'c': 15, 'g': 4, 'p': [5, 5]}]}), isNull);
    });

    test('rechaza forma, rangos y topes', () {
      Map<String, dynamic> con(void Function(Map<String, dynamic>) f) => _valido()..let(f);
      expect(dibujoInvalido(null), 'no es un objeto');
      expect(dibujoInvalido(con((d) => d['extra'] = 1)), 'claves de más o de menos');
      expect(dibujoInvalido(con((d) => d['v'] = 2)), 'versión desconocida');
      expect(dibujoInvalido(con((d) => d['fondo'] = 16)), 'fondo fuera de rango');
      expect(dibujoInvalido(con((d) => d['fondo'] = 1.5)), 'fondo fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'] = [])), 'entre 1 y 400 trazos');
      expect(dibujoInvalido(con((d) => d['trazos'] = [for (var i = 0; i < 401; i++) {'c': 0, 'g': 1, 'p': [1, 1]}])), 'entre 1 y 400 trazos');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['c'] = -1)), 'color fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['g'] = 5)), 'grosor fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['g'] = 0)), 'grosor fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['p'] = [1, 2, 3])), 'trazo con número de puntos inválido');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['p'] = List.filled(4002, 1))), 'trazo con número de puntos inválido');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['p'] = [0, 1001])), 'coordenada fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['p'] = [0, -1])), 'coordenada fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['x'] = 1)), 'trazo con claves de más o de menos');
      final muchos = [for (var i = 0; i < 8; i++) {'c': 0, 'g': 1, 'p': List.filled(4000, 1)}];
      expect(dibujoInvalido(con((d) => d['trazos'] = muchos)), 'demasiados puntos');
    });

    test('ida y vuelta por JSON', () {
      final d = Dibujo.deJson(_valido())!;
      expect(d.fondo, 8);
      expect(d.trazos.single.p, [0, 0, 1000, 1000]);
      expect(d.aJson(), _valido());
      expect(Dibujo.deJson({'v': 1}), isNull);
    });
  });

  testWidgets('el editor pinta, deshace y devuelve un dibujo válido', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Dibujo? hecho;
    await tester.pumpWidget(MaterialApp(
      theme: tema(Brightness.light),
      home: Builder(
        builder: (context) => TextButton(onPressed: () async => hecho = await abrirEditorDibujo(context), child: const Text('abrir')),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('DIBUJAR'), findsOneWidget);

    final lienzo = find.byKey(const Key('lienzo'));
    await tester.tap(find.byKey(const Key('color10')));
    await tester.dragFrom(tester.getTopLeft(lienzo) + const Offset(20, 20), const Offset(150, 100));
    await tester.pump();
    await tester.dragFrom(tester.getTopLeft(lienzo) + const Offset(50, 200), const Offset(0, 80));
    await tester.pump();
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();

    await tester.tap(find.text('LISTO'));
    await tester.pumpAndSettle();
    expect(hecho, isNotNull);
    expect(hecho!.trazos, hasLength(1));
    expect(hecho!.trazos.single.c, 10);
    expect(dibujoInvalido(hecho!.aJson()), isNull);
  });
}

extension on Map<String, dynamic> {
  void let(void Function(Map<String, dynamic>) f) => f(this);
}
