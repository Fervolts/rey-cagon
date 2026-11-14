import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/muro_dibujo.dart';
import 'package:rey_cagon/muro_editor.dart';
import 'package:rey_cagon/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _valido() => {
      'v': 1,
      'fondo': 8,
      'trazos': [
        {'c': 0, 'g': 2, 'p': [0, 0, 1000, 1000]},
      ],
    };

Map<String, dynamic> _validoV2() => {
      'v': 2,
      'fondo': 'fff8e1',
      'trazos': [
        {'c': 'ff0000', 'g': 8, 'h': 'spray', 'p': [0, 0, 1000, 1000]},
        {'c': '8d5524', 'g': 1, 'h': 'sello', 'p': [500, 500]},
        {'c': '000000', 'g': 3, 'h': 'borrador', 'p': [10, 10]},
      ],
    };

/// Abre el editor en una pantalla de 400x800 y devuelve lo que salga de LISTO.
Future<Dibujo? Function()> _abrir(WidgetTester tester, {PaquetesColor ganados = (oro: false, cloaca: false)}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  cargarPaquetesColor = () async => ganados;
  Dibujo? hecho;
  await tester.pumpWidget(MaterialApp(
    theme: tema(Brightness.light),
    home: Builder(
      builder: (context) => TextButton(onPressed: () async => hecho = await abrirEditorDibujo(context), child: const Text('abrir')),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return () => hecho;
}

/// Elige un color de la paleta BÁSICA (índice de [coloresPaint]).
Future<void> _elegirBasico(WidgetTester tester, int i) async {
  await tester.tap(find.byKey(const Key('color_actual')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BÁSICA'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('color$i')));
  await tester.pumpAndSettle();
}

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
      expect(dibujoInvalido(con((d) => d['v'] = 3)), 'versión desconocida');
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

    test('v1 se sigue leyendo y se guarda como v2', () {
      final d = Dibujo.deJson(_valido())!;
      expect(d.fondo, 0xFFFFFF);
      expect(d.trazos.single.c, 0x000000);
      expect(d.trazos.single.g, 4);
      expect(d.trazos.single.h, Herramienta.pincel);
      expect(d.trazos.single.p, [0, 0, 1000, 1000]);
      final v2 = {
        'v': 2,
        'fondo': 'ffffff',
        'trazos': [
          {'c': '000000', 'g': 4, 'h': 'pincel', 'p': [0, 0, 1000, 1000]},
        ],
      };
      expect(d.aJson(), v2);
      expect(dibujoInvalido(d.aJson()), isNull);
      expect(Dibujo.deJson({'v': 1}), isNull);
    });

    test('v2: acepta uno bien hecho e ida y vuelta', () {
      expect(dibujoInvalido(_validoV2()), isNull);
      final d = Dibujo.deJson(_validoV2())!;
      expect(d.fondo, 0xFFF8E1);
      expect(d.trazos.map((t) => t.h), [Herramienta.spray, Herramienta.sello, Herramienta.borrador]);
      expect(d.aJson(), _validoV2());
    });

    test('v2: rechaza hex malo, grosor, herramienta, sello y claves', () {
      Map<String, dynamic> con(void Function(Map<String, dynamic>) f) => _validoV2()..let(f);
      expect(dibujoInvalido(con((d) => d['fondo'] = 'FFFFFF')), 'fondo fuera de rango');
      expect(dibujoInvalido(con((d) => d['fondo'] = 8)), 'fondo fuera de rango');
      expect(dibujoInvalido(con((d) => d['fondo'] = '#ffffff')), 'fondo fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['c'] = 'zzzzzz')), 'color fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['c'] = 10)), 'color fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['g'] = 9)), 'grosor fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['g'] = 0)), 'grosor fuera de rango');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['h'] = 'lapiz')), 'herramienta desconocida');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['h'] = 'balde')), 'herramienta desconocida');
      expect(dibujoInvalido(con((d) => d['trazos'][1]['p'] = [1, 1, 2, 2])), 'trazo con número de puntos inválido');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['x'] = 1)), 'trazo con claves de más o de menos');
      expect(dibujoInvalido(con((d) => (d['trazos'][0] as Map).remove('h'))), 'trazo con claves de más o de menos');
      expect(dibujoInvalido(con((d) => d['extra'] = 1)), 'claves de más o de menos');
      expect(dibujoInvalido(con((d) => d['trazos'][0]['p'] = [0, 1001])), 'coordenada fuera de rango');
    });

    test('colorEn: el cuentagotas ve el último trazo encima y el borrador da el fondo', () {
      final d = Dibujo(fondo: 0x112233, trazos: [Trazo(0xFF0000, 3, p: [100, 100, 300, 100])]);
      expect(colorEn(d, 200, 100), 0xFF0000);
      expect(colorEn(d, 200, 500), 0x112233);
      d.trazos.add(Trazo(0x00FF00, 2, h: Herramienta.sello, p: [200, 100]));
      expect(colorEn(d, 200, 100), 0x00FF00);
      d.trazos.add(Trazo(0x000000, 8, h: Herramienta.borrador, p: [200, 100]));
      expect(colorEn(d, 200, 100), 0x112233);
    });
  });

  testWidgets('el editor pinta, deshace, rehace y devuelve un dibujo v2 válido', (tester) async {
    final hecho = await _abrir(tester);
    expect(find.text('DIBUJAR'), findsOneWidget);

    final lienzo = find.byKey(const Key('lienzo'));
    await _elegirBasico(tester, 10);
    await tester.dragFrom(tester.getTopLeft(lienzo) + const Offset(20, 20), const Offset(150, 100));
    await tester.pump();
    await tester.dragFrom(tester.getTopLeft(lienzo) + const Offset(50, 200), const Offset(0, 80));
    await tester.pump();
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    await tester.tap(find.byTooltip('Rehacer'));
    await tester.pump();

    await tester.tap(find.text('LISTO'));
    await tester.pumpAndSettle();
    expect(hecho(), isNotNull);
    expect(hecho()!.trazos, hasLength(1));
    expect(hecho()!.trazos.single.c, 0xFF0000);
    expect(hecho()!.aJson()['v'], 2);
    expect(dibujoInvalido(hecho()!.aJson()), isNull);
  });

  testWidgets('balde cambia el fondo y se deshace; sello deja un punto; cuentagotas agarra el color', (tester) async {
    final hecho = await _abrir(tester);
    final lienzo = find.byKey(const Key('lienzo'));
    final arriba = tester.getTopLeft(lienzo);

    await _elegirBasico(tester, 14); // azul
    await tester.tap(find.byKey(const Key('util_balde')));
    await tester.pump();
    await tester.tapAt(arriba + const Offset(10, 10));
    await tester.pump();
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    await tester.tap(find.byTooltip('Rehacer'));
    await tester.pump();

    await _elegirBasico(tester, 10); // rojo
    await tester.tap(find.byKey(const Key('util_sello')));
    await tester.pump();
    await tester.tapAt(arriba + const Offset(100, 100));
    await tester.pump();

    // Cuentagotas sobre el fondo azul: vuelve al sello con el azul.
    await tester.tap(find.byKey(const Key('util_gotero')));
    await tester.pump();
    await tester.tapAt(arriba + const Offset(300, 300));
    await tester.pump();
    expect(find.text('#0000ff'), findsOneWidget);
    await tester.tapAt(arriba + const Offset(200, 200));
    await tester.pump();

    await tester.tap(find.text('LISTO'));
    await tester.pumpAndSettle();
    final d = hecho()!;
    expect(d.fondo, 0x0000FF);
    expect(d.trazos.map((t) => (t.h, t.c, t.p.length)), [(Herramienta.sello, 0xFF0000, 2), (Herramienta.sello, 0x0000FF, 2)]);
    expect(dibujoInvalido(d.aJson()), isNull);
  });

  testWidgets('paquetes ORO y CLOACA salen con candado hasta ganarlos', (tester) async {
    await _abrir(tester);
    await tester.tap(find.byKey(const Key('color_actual')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ORO'));
    await tester.tap(find.text('ORO'));
    await tester.pumpAndSettle();
    expect(find.text('Se gana con racha de 30 días'), findsOneWidget);
  });

  testWidgets('con racha de 30 días el ORO se abre', (tester) async {
    await _abrir(tester, ganados: (oro: true, cloaca: false));
    await tester.tap(find.byKey(const Key('color_actual')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ORO'));
    await tester.tap(find.text('ORO'));
    await tester.pumpAndSettle();
    expect(find.text('Se gana con racha de 30 días'), findsNothing);
    await tester.ensureVisible(find.text('CLOACA'));
    await tester.tap(find.text('CLOACA'));
    await tester.pumpAndSettle();
    expect(find.text('Tu cloaca en el top 10 de la liga'), findsOneWidget);
  });
}

extension on Map<String, dynamic> {
  void let(void Function(Map<String, dynamic>) f) => f(this);
}
