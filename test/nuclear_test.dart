import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/nuclear.dart';
import 'package:rey_cagon/racha.dart';

// La alerta nuclear se pinta sin red: perfiles inventados, sin foto.
void main() {
  final una = <Hazana>[(perfil: {'id': 'a', 'username': 'prueba'}, n: 6)];
  final varias = <Hazana>[
    (perfil: {'id': 'a', 'username': 'prueba'}, n: 6),
    (perfil: {'id': 'b', 'username': 'otro'}, n: 7),
  ];

  testWidgets('la explosión completa se pinta y el toque la salta', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AlertaNuclear(hazanas: una)));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    expect(find.textContaining('NUCLEAR'), findsOneWidget);
    expect(find.text('@prueba'), findsOneWidget);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('varias hazañas salen en lista', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AlertaNuclear(hazanas: varias, modo: Movimiento.simple)));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('@prueba'), findsOneWidget);
    expect(find.text('@otro'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin movimiento sale quieta con el texto', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AlertaNuclear(hazanas: una, modo: Movimiento.nada)));
    await tester.pump();
    expect(find.text('@prueba'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el hongo se pinta en todo su recorrido', (tester) async {
    for (final t in [0.0, .02, .1, .3, .5, .8, 1.0]) {
      await tester.pumpWidget(MaterialApp(home: Explosion(t: t)));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('el anuncio de HEXA POOP se abre con el hongo', (tester) async {
    expect(nombreRacha(6), 'HEXA POOP!');
    expect(nombreRacha(9), 'HEXA POOP!');
    expect(nombreRacha(5), 'RAMPAGE!');
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () => mostrarRacha(context, 6), child: const Text('abrir'))),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump();
    expect(find.byType(Explosion), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
