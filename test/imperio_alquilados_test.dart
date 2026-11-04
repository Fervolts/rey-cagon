// Lo alquilado a la vista: los toques de los primos (pocos en pantalla, misma plata), la tira "trabajando ahora" y que
// la poceta se dibuje con todos los alquilados en cada nivel de movimiento.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/alquilados.dart';
import 'package:rey_cagon/imperio/bano.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/poceta.dart';

const t0 = 1800000000000;

Imperio _imperio() {
  final imp = Imperio(cagadas: 30, ajustes: Ajustes.porDefecto, azar: Random(1));
  imp.partida.vioPrimerAtasco = true;
  imp.partida.edificios['arepa'] = 10;
  imp.partida.saldo = 1e15;
  return imp;
}

void main() {
  group('Toques de los primos', () {
    test('se ven los 10 toques por segundo de cada primo', () {
      expect(toquesPorSegundoPrimo, pujosPrimo);
      for (var i = 0; i < 4; i++) {
        final toques = toquePrimo(i, 10.999) - toquePrimo(i, 1);
        expect(toques, inInclusiveRange(99, 100), reason: 'primo $i');
      }
    });

    test('no tocan todos a la vez', () {
      final inicios = {for (var i = 0; i < 4; i++) inicioToquePrimo(i, 7)};
      expect(inicios.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(toquePrimo(i, inicioToquePrimo(i, 7) + 1e-6), 7);
      }
    });

    test('los "+MJ" de un primo, uno por toque, suman lo que gana de verdad', () {
      const porSegundo = 120.0; // valor del pujo x pujosPrimo
      for (var i = 0; i < 4; i++) {
        var suma = 0.0;
        for (var k = 0; inicioToquePrimo(i, k) < 60; k++) {
          suma += montoFlotantePrimo(porSegundo);
        }
        expect(suma, closeTo(porSegundo * 60, porSegundo * .2), reason: 'primo $i');
      }
    });
  });

  group('Tira "trabajando ahora"', () {
    test('texto de cada ficha', () {
      expect(textoFichaAlquiler(indefinido: true), '∞');
      expect(textoFichaAlquiler(restante: const Duration(minutes: 14, seconds: 59), primos: 2), 'x2 14:59');
      expect(textoFichaAlquiler(restante: const Duration(minutes: 14, seconds: 58, milliseconds: 300)), '14:59');
      expect(textoFichaAlquiler(restante: const Duration(hours: 1, minutes: 59, seconds: 59)), '1:59:59');
      expect(textoFichaAlquiler(restante: const Duration(seconds: 5)), '0:05');
      expect(textoFichaAlquiler(restante: const Duration(seconds: -3)), '0:00');
      expect(textoFichaAlquiler(indefinido: true, primos: 3), 'x3 ∞');
    });

    test('sin alquilar no hay fichas', () {
      expect(fichasAlquiler(_imperio(), t0), isEmpty);
    });

    test('una ficha por alquilado activo, con lo que le queda, ∞ y los primos', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.comprarObjeto('cuadrilla', t0, indefinido: true), isTrue);
      final ahora = t0 + 60000;
      final fichas = fichasAlquiler(imp, ahora);
      expect(fichas.map((f) => f.id).toSet(), {'primo', 'cuadrilla'});
      final primo = fichas.firstWhere((f) => f.id == 'primo');
      final resta = Duration(milliseconds: objetoPorId('primo')!.duracion!.inMilliseconds - 60000);
      expect(primo.texto, textoFichaAlquiler(restante: resta, primos: imp.primosActivos()));
      expect(primo.texto, startsWith('x${imp.primosActivos()} '));
      expect(primo.emoji, objetoPorId('primo')!.emoji);
      expect(fichas.firstWhere((f) => f.id == 'cuadrilla').texto, '∞');
      // Vencido el primo, su ficha se va; la cuadrilla indefinida sigue.
      final despues = t0 + objetoPorId('primo')!.duracion!.inMilliseconds + 1000;
      expect(fichasAlquiler(imp, despues).map((f) => f.id), isNot(contains('primo')));
      expect(avisoAlquiler(primo), contains(primo.texto));
    });
  });

  group('Poceta con alquilados', () {
    const todo = EstadoBano(alquiler: (primos: 4, cuadrilla: true, plomero: true, robot: 2, guardia: true));
    const fichas = <FichaAlquiler>[
      (id: 'primo', emoji: '👦', texto: 'x4 9:59', pausado: false),
      (id: 'robot_turbo', emoji: '🦾', texto: '∞', pausado: false),
    ];

    Future<void> poner(WidgetTester tester, Widget poceta) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: poceta))));
    }

    tearDown(() => movimientoElegido.value = 'auto');

    testWidgets('se dibuja con todo alquilado en cada movimiento', (tester) async {
      for (final m in ['completo', 'simple', 'nada']) {
        movimientoElegido.value = m;
        for (final t in [0.2, 3.7, 41.0]) {
          await poner(
            tester,
            Poceta(
              alTocar: () => (texto: '+1', epico: false, contado: true),
              mps: 50,
              bano: todo,
              instante: t,
              pujoPrimo: 120,
              plomeroBono: true,
              alquileres: fichas,
              efectos: const ['🔥'],
              alPersonalizar: () {},
            ),
          );
          expect(tester.takeException(), isNull, reason: '$m $t');
          expect(find.byKey(const ValueKey('ficha_primo')), findsOneWidget);
          expect(find.text('x4 9:59'), findsOneWidget);
        }
      }
    });

    testWidgets('el robot destapa y la cuadrilla compra sin romper nada', (tester) async {
      movimientoElegido.value = 'completo';
      Widget poceta(int destapes, int compras) => Poceta(
            alTocar: () => (texto: '+1', epico: false, contado: true),
            mps: 50,
            bano: todo,
            pujoPrimo: 120,
            destapes: destapes,
            comprasCuadrilla: compras,
            ultimaCuadrilla: edificioPorId('arepa')!.emoji,
            alquileres: fichas,
          );
      await poner(tester, poceta(0, 0));
      await poner(tester, poceta(1, 1));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      // Pasado el destape y la compra, la escena sigue andando sin errores.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tocar una ficha avisa y no puja', (tester) async {
      var pujos = 0;
      final tocadas = <String>[];
      await poner(
        tester,
        Poceta(
          alTocar: () {
            pujos++;
            return (texto: '+1', epico: false, contado: true);
          },
          mps: 1,
          bano: todo,
          instante: 5,
          alquileres: fichas,
          alTocarAlquiler: (f) => tocadas.add(f.id),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ficha_robot_turbo')));
      await tester.pump();
      expect(tocadas, ['robot_turbo']);
      expect(pujos, 0);
    });
  });
}
