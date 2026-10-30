import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/teclado_emojis.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('insertar va en el cursor y borrar quita un emoji entero', () {
    final texto = TextEditingController(text: 'hola');
    texto.selection = const TextSelection.collapsed(offset: 2);
    insertarEnTexto(texto, '😮‍💨');
    expect(texto.text, 'ho😮‍💨la');
    borrarEnTexto(texto);
    expect(texto.text, 'hola');
    expect(texto.selection.baseOffset, 2);
    texto.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    borrarEnTexto(texto);
    expect(texto.text, '');
    borrarEnTexto(texto);
    expect(texto.text, '');
  });

  for (final ancho in [320.0, 900.0]) {
    testWidgets('el panel cabe en $ancho px y pone emojis', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final texto = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: TecladoEmojis(texto: texto))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('😀'));
      await tester.pump();
      expect(texto.text, '😀');
      // Saltar a la última categoría y volver.
      await tester.tap(find.byIcon(Icons.sports_soccer_outlined));
      await tester.pumpAndSettle();
      expect(find.text('⚽'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(texto.text, '');
      expect(tester.takeException(), isNull);
    });
  }
}
