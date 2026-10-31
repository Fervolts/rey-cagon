import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/tema.dart';
import 'package:rey_cagon/vitrina.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Unas cuantas cagadas: 3 en un día (rachas) y una a las 3:33 am (secreto hora_333).
final _lista = trofeos(
  cagadas: [
    (cuando: DateTime(2026, 10, 6, 3, 33), tipo: null, peso: null),
    (cuando: DateTime(2026, 10, 6, 9), tipo: null, peso: null),
    (cuando: DateTime(2026, 10, 6, 13), tipo: null, peso: null),
  ],
  total: 3,
  victorias: 0,
  favorito: null,
);

Future<void> _montar(WidgetTester tester, {required bool propio}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: tema(Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Vitrina(
          trofeos: _lista,
          nuevos: propio ? {'hora_333'} : const {},
          porEncontrar: propio ? secretosPorEncontrar(_lista) : 0,
          propio: propio,
          imperio: propio ? {'primer_pujo'} : null,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Ninguna placa corta el texto ni parte una palabra entre dos líneas.
void _placasEnteras(WidgetTester tester) {
  final placas = find.byWidgetPredicate((w) => w is Text && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('placa-'));
  expect(placas, findsWidgets);
  for (final e in placas.evaluate()) {
    final rp = e.renderObject! as RenderParagraph;
    final nombre = (e.widget as Text).data!;
    expect(rp.didExceedMaxLines, isFalse, reason: 'placa cortada: $nombre');
    final estilo = (rp.text as TextSpan).style;
    for (final palabra in nombre.split(' ').where((w) => w.isNotEmpty)) {
      final tp = TextPainter(text: TextSpan(text: palabra, style: estilo), textDirection: TextDirection.ltr, textScaler: rp.textScaler)..layout();
      expect(tp.width, lessThanOrEqualTo(rp.size.width + .5), reason: 'palabra partida en "$nombre": $palabra');
      tp.dispose();
    }
  }
}

void main() {
  testWidgets('perfil propio: la zona abre la vitrina, IMPERIO con PRESUMIR, nada partido a 320 px', (tester) async {
    await _montar(tester, propio: true);
    expect(tester.takeException(), isNull);
    expect(find.text('NUEVO'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('zona-vitrina')));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaVitrina), findsOneWidget);
    expect(tester.takeException(), isNull);
    _placasEnteras(tester);
    expect(find.byKey(const ValueKey('trofeo-tapado-0')), findsOneWidget);

    // Un logro del Imperio ganado: el detalle trae PRESUMIR.
    final pujo = find.byKey(const ValueKey('trofeo-imperio:primer_pujo'));
    await tester.ensureVisible(pujo);
    await tester.pumpAndSettle();
    await tester.tap(pujo);
    await tester.pumpAndSettle();
    expect(find.text('PRESUMIR'), findsOneWidget);
    expect(find.text('Cómo se gana'.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('PRESUMIR'))).pop();
    await tester.pumpAndSettle();

    // Uno sin ganar: detalle sin PRESUMIR.
    final calentando = find.byKey(const ValueKey('trofeo-imperio:calentando'));
    await tester.ensureVisible(calentando);
    await tester.pumpAndSettle();
    await tester.tap(calentando);
    await tester.pumpAndSettle();
    expect(find.text('POR GANAR'), findsOneWidget);
    expect(find.text('PRESUMIR'), findsNothing);
  });

  testWidgets('perfil de otro: sin sección IMPERIO ni PRESUMIR', (tester) async {
    await _montar(tester, propio: false);
    await tester.tap(find.byKey(const ValueKey('zona-vitrina')));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaVitrina), findsOneWidget);
    expect(find.byKey(const ValueKey('trofeo-imperio:primer_pujo')), findsNothing);
    expect(find.text('IMPERIO'), findsNothing);
    _placasEnteras(tester);
    expect(tester.takeException(), isNull);
  });
}
