import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/ajustes_avisos.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/tema.dart';

Future<void> _montar(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: tema(Brightness.light), home: pantalla));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => idioma.value = 'es');

  testWidgets('muestra una fila por categoría con lo que dice la base', (tester) async {
    await _montar(
      tester,
      PantallaAjustesAvisos(cargar: () async => {for (final c in categoriasAvisos) c.$1: c.$1 != 'cierres'}, guardar: (_, _) async {}),
    );
    expect(find.text('NOTIFICACIONES'), findsOneWidget);
    for (final (clave, _, nombre, descripcion) in categoriasAvisos) {
      expect(find.byKey(ValueKey('aviso_$clave')), findsOneWidget);
      expect(find.text(nombre), findsOneWidget);
      expect(find.text(descripcion), findsOneWidget);
    }
    expect(tester.getSemantics(find.byKey(const ValueKey('aviso_cierres'))), isSemantics(hasToggledState: true, isToggled: false));
    expect(tester.getSemantics(find.byKey(const ValueKey('aviso_cagadas'))), isSemantics(hasToggledState: true, isToggled: true));
  });

  testWidgets('tocar una fila guarda el cambio', (tester) async {
    final guardados = <(String, bool)>[];
    await _montar(
      tester,
      PantallaAjustesAvisos(cargar: () async => {for (final c in categoriasAvisos) c.$1: true}, guardar: (c, v) async => guardados.add((c, v))),
    );
    await tester.tap(find.byKey(const ValueKey('aviso_rachas')));
    await tester.pumpAndSettle();
    expect(guardados, [('rachas', false)]);
    await tester.tap(find.byKey(const ValueKey('aviso_rachas')));
    await tester.pumpAndSettle();
    expect(guardados, [('rachas', false), ('rachas', true)]);
  });

  testWidgets('si no se pudo guardar, vuelve como estaba y avisa', (tester) async {
    await _montar(
      tester,
      PantallaAjustesAvisos(cargar: () async => {'imperio': true}, guardar: (_, _) async => throw Exception('caído')),
    );
    await tester.tap(find.byKey(const ValueKey('aviso_imperio')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const ValueKey('aviso_imperio'))), isSemantics(hasToggledState: true, isToggled: true));
  });

  testWidgets('si no carga, deja reintentar', (tester) async {
    var veces = 0;
    await _montar(
      tester,
      PantallaAjustesAvisos(
        cargar: () async {
          veces++;
          if (veces == 1) throw Exception('sin red');
          return {'chat': false};
        },
        guardar: (_, _) async {},
      ),
    );
    expect(find.text('REINTENTAR'), findsOneWidget);
    await tester.tap(find.text('REINTENTAR'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aviso_chat')), findsOneWidget);
  });

  testWidgets('en inglés', (tester) async {
    idioma.value = 'en';
    await _montar(tester, PantallaAjustesAvisos(cargar: () async => const {}, guardar: (_, _) async {}));
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('Winners'), findsOneWidget);
  });
}
