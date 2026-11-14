import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/chat_panel.dart';
import 'package:rey_cagon/chat_sin_leer.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/privados.dart' show privadosSinLeer;
import 'package:rey_cagon/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    idioma.value = 'es';
    privadosSinLeer.value = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('etiquetaCuenta', () {
    test('sin número con 0 o menos', () {
      expect(etiquetaCuenta(0), isNull);
      expect(etiquetaCuenta(-3), isNull);
    });

    test('el número hasta 99 y "99+" desde 100', () {
      expect(etiquetaCuenta(1), '1');
      expect(etiquetaCuenta(99), '99');
      expect(etiquetaCuenta(100), '99+');
      expect(etiquetaCuenta(5000), '99+');
    });
  });

  group('pestanaInicial', () {
    test('la primera con algo sin leer', () {
      expect(pestanaInicial([false, true, false, true]), 1);
      expect(pestanaInicial([false, false, false, true]), 3);
    });

    test('General (0) si no hay nada sin leer', () {
      expect(pestanaInicial([false, false, false]), 0);
      expect(pestanaInicial([]), 0);
    });
  });

  group('ChatSinLeer', () {
    test('sin mensajes no hay nada nuevo', () {
      final s = ChatSinLeer();
      expect(s.hay(ChatCual.general), isFalse);
      expect(s.cuenta(ChatCual.soporte), 0);
      expect(s.hayNuevo, isFalse);
    });

    test('un privado sin leer prende el punto y avisa a quien escucha', () {
      final s = ChatSinLeer();
      var avisos = 0;
      s.addListener(() => avisos++);
      privadosSinLeer.value = true;
      expect(s.hayNuevo, isTrue);
      expect(avisos, 1);
    });
  });

  group('PlacaSinLeer', () {
    Future<void> poner(WidgetTester tester, int cuenta) => tester.pumpWidget(MaterialApp(
          theme: tema(Brightness.light),
          home: Scaffold(body: Center(child: PlacaSinLeer(cuenta: cuenta))),
        ));

    testWidgets('con número muestra el número', (tester) async {
      await poner(tester, 7);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('desde 100 dice 99+', (tester) async {
      await poner(tester, 250);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('sin número es un punto amarillo cuadrado', (tester) async {
      await poner(tester, 0);
      expect(find.byType(Text), findsNothing);
      final caja = tester.widget<Container>(find.byType(Container));
      final deco = caja.decoration! as BoxDecoration;
      expect(deco.color, paleta(tester.element(find.byType(Container))).acento);
      expect(deco.borderRadius, BorderRadius.circular(radio));
    });
  });
}
