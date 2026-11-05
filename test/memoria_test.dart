// Fusión real: contrato del servidor con bots, determinismo, desborde, descarga final, palanca, descarga real
// y la vista montada de punta a punta.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/minijuegos/memoria_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/memoria_vista.dart';
import 'package:rey_cagon/tema.dart';

import 'memoria_bots.dart';

/// Pone una pieza quieta en la poceta (para armar situaciones).
Mojon poner(JuegoFusion j, int nivel, double x, double y, {int id = 0}) {
  final m = Mojon(5000 + id, nivel, x, y)
    ..edad = 2
    ..tocado = true;
  j.mojones.add(m);
  return m;
}

void correr(JuegoFusion j, double segundos) {
  for (var t = 0.0; t < segundos && !j.terminado; t += pasoFijo) {
    j.avanzar(pasoFijo);
  }
}

void main() {
  group('Fusión real: contrato', () {
    test('las constantes son las del servidor', () {
      expect(topePuntosFusion, 3600);
      expect(puntosPorSegundoFusion, 400);
      expect(minMsFusion, 3000);
      expect(maxMsFusion, 600000);
      expect(puntosReportables(99999, 1000), 800);
      expect(puntosReportables(99999, 500000), 3600);
      expect(puntosReportables(-5, 4000), 0);
    });

    for (final tipo in TipoBot.values) {
      test('bot ${tipo.name}: puntos y duración dentro del contrato', () {
        for (var s = 1; s <= 6; s++) {
          final r = jugarBot(tipo, s);
          expect(r.puntos, inInclusiveRange(0, topePuntosFusion));
          expect(r.puntos, lessThanOrEqualTo(((r.ms / 1000 + 1) * puntosPorSegundoFusion).floor()));
          expect(r.ms, inInclusiveRange(minMsFusion, maxMsFusion));
          expect(r.soltadas, greaterThan(0));
        }
      });
    }

    test('el bot bueno llega a 1800 (logro alcanzable) y el malo queda por debajo', () {
      final buenos = [for (var s = 1; s <= 4; s++) jugarBot(TipoBot.bueno, s).puntos];
      final malos = [for (var s = 1; s <= 4; s++) jugarBot(TipoBot.malo, s).puntos];
      expect(buenos.where((p) => p >= 1800), isNotEmpty);
      expect(malos.reduce((a, b) => a + b) / malos.length, lessThan(buenos.reduce((a, b) => a + b) / buenos.length));
    });

    test('con dt irregular tampoco se sale', () {
      final r = jugarBot(TipoBot.normal, 3, dt: 1 / 23);
      expect(r.puntos, lessThanOrEqualTo(((r.ms / 1000 + 1) * puntosPorSegundoFusion).floor()));
      expect(r.ms, inInclusiveRange(minMsFusion, maxMsFusion));
    });
  });

  group('Fusión real: reglas', () {
    test('misma semilla y mismos toques: misma partida', () {
      final a = jugarBot(TipoBot.normal, 9), b = jugarBot(TipoBot.normal, 9);
      expect((a.puntos, a.ms, a.desbordo, a.nivelMasAlto, a.soltadas), (b.puntos, b.ms, b.desbordo, b.nivelMasAlto, b.soltadas));
    });

    test('al principio solo caen bolitas y frijolitos; nunca más que nivel 4', () {
      final j = JuegoFusion(semilla: 3);
      final vistos = <int>{};
      for (var k = 0; k < 200; k++) {
        vistos.add(j.actual);
        j.avanzar(pasoFijo);
        if (j.t < 12) expect(j.actual, lessThanOrEqualTo(2));
      }
      final b = JuegoFusion(semilla: 4);
      correr(b, 30);
      for (var k = 0; k < 400; k++) {
        if (b.puedeSoltar) {
          expect(b.siguiente, inInclusiveRange(1, nivelMaximoSoltar));
          b.apuntar(-40 + (k * 13 % 80).toDouble());
          b.soltar();
        }
        b.avanzar(pasoFijo);
        b.tomarSucesos();
      }
    });

    test('dos iguales que se tocan se funden en el siguiente nivel', () {
      final j = JuegoFusion(semilla: 1);
      poner(j, 3, -radioDe(3) - 0.5, yFondo - radioDe(3) - 30, id: 1);
      poner(j, 3, radioDe(3) + 0.5, yFondo - radioDe(3) - 30, id: 2);
      correr(j, 1.5);
      final s = j.tomarSucesos();
      expect(s.where((e) => e.tipo == TipoSuceso.fusion && e.nivel == 4), isNotEmpty);
      expect(j.mojones.where((m) => m.nivel == 4).length, 1);
      expect(j.mojones.where((m) => m.nivel == 3), isEmpty);
      expect(j.puntosCrudos, greaterThan(0));
      expect(j.fusiones, 1);
    });

    test('dos Reyes: descarga real que limpia todo y da bonus', () {
      final j = JuegoFusion(semilla: 1);
      final r = radioDe(nivelMaximo);
      poner(j, nivelMaximo, -r - 0.5, yFondo - r - 20, id: 1);
      poner(j, nivelMaximo, r + 0.5, yFondo - r - 20, id: 2);
      poner(j, 2, 0, 0, id: 3);
      correr(j, 1.5);
      final s = j.tomarSucesos();
      final real = s.where((e) => e.tipo == TipoSuceso.descargaReal).toList();
      expect(real, hasLength(1));
      expect(real.first.puntos, greaterThanOrEqualTo(bonusDescargaReal));
      expect(j.mojones, isEmpty);
      expect(j.fase, FaseFusion.jugando);
    });

    test('la palanca se carga con fusiones y se traga solo los nivel 1 y 2', () {
      final j = JuegoFusion(semilla: 1);
      expect(j.jalarPalanca(), isFalse);
      poner(j, 1, -30, 80, id: 1);
      poner(j, 2, 20, 80, id: 2);
      poner(j, 5, 0, 60, id: 3);
      j.carga = cargaPalanca;
      expect(j.palancaLista, isTrue);
      final antes = j.puntosCrudos;
      expect(j.jalarPalanca(), isTrue);
      expect(j.mojones.map((m) => m.nivel), [5]);
      expect(j.puntosCrudos, antes);
      expect(j.carga, 0);
      final s = j.tomarSucesos();
      expect(s.first.tipo, TipoSuceso.palanca);
      expect(s.where((e) => e.tipo == TipoSuceso.tragado), hasLength(2));
    });

    test('tirar al azar sin pensar desborda la poceta', () {
      var alguno = false;
      for (var s = 1; s <= 4; s++) {
        final r = jugarBot(TipoBot.malo, s);
        if (r.desbordo) {
          alguno = true;
          expect(r.ms, greaterThanOrEqualTo(minMsFusion));
        }
      }
      expect(alguno, isTrue);
    });

    test('desborde: algo encima de la línea más de 2 s acaba la partida, con alerta antes', () {
      final j = JuegoFusion(semilla: 2);
      correr(j, 4);
      j.tomarSucesos();
      // Una columna alta de piezas grandes que no se funden entre sí.
      var y = yFondo - 10.0;
      for (var k = 0; k < 14; k++) {
        final nivel = 5 + k % 3;
        poner(j, nivel, (k.isEven ? -1 : 1) * 12.0, y, id: k);
        y -= radioDe(nivel) * 1.4;
      }
      final tipos = <TipoSuceso>[];
      for (var k = 0; k < 60 * 8 && !j.terminado; k++) {
        j.avanzar(pasoFijo);
        tipos.addAll(j.tomarSucesos().map((e) => e.tipo));
      }
      expect(j.terminado, isTrue);
      expect(j.desbordo, isTrue);
      expect(tipos, contains(TipoSuceso.alerta));
      expect(tipos, contains(TipoSuceso.desborde));
      expect(tipos.indexOf(TipoSuceso.alerta), lessThan(tipos.indexOf(TipoSuceso.desborde)));
    });

    test('sin reloj: si no se desborda la partida sigue', () {
      final j = JuegoFusion(semilla: 5);
      final claves = <String>[];
      for (var k = 0; k < 60 * 240; k++) {
        j.avanzar(pasoFijo);
        claves.addAll(j.tomarSucesos().where((s) => s.tipo == TipoSuceso.aviso).map((s) => s.clave));
      }
      expect(j.terminado, isFalse);
      expect(j.fase, FaseFusion.jugando);
      expect(j.t, greaterThan(239));
      // Pasada la lista fija los eventos siguen en rueda.
      expect(claves.sublist(claves.length - 3), ['temblor', 'frijoles', 'lluvia']);
      expect(claves, isNot(contains('ultimos10')));
    });

    test('arranque al azar: mojones de niveles distintos, asentados, sin puntos ni sucesos', () {
      for (var s = 1; s <= 20; s++) {
        final j = JuegoFusion(semilla: s, piezasInicio: 4);
        expect(j.mojones, hasLength(4));
        expect(j.inicio.toSet(), hasLength(4));
        expect(j.inicio.every((n) => n >= 1 && n <= nivelMaximoInicio), isTrue);
        expect(j.puntosCrudos, 0);
        expect(j.tomarSucesos(), isEmpty);
        for (final m in j.mojones) {
          expect(m.y - m.r, greaterThan(lineaDesborde));
          expect(m.x.abs() + m.r, lessThanOrEqualTo(mitadAncho + 0.5));
        }
        // Al arrancar la pila puede rodar un poco, pero no se funde, no suma ni pasa la línea.
        correr(j, 3);
        expect(j.mojones, hasLength(4));
        expect(j.puntosCrudos, 0);
        expect(j.mojones.every((m) => m.y - m.r > lineaDesborde), isTrue);
        expect(j.terminado, isFalse);
      }
      final a = JuegoFusion(semilla: 8, piezasInicio: 6), b = JuegoFusion(semilla: 8, piezasInicio: 6);
      expect([for (final m in a.mojones) (m.nivel, m.x, m.y)], [for (final m in b.mojones) (m.nivel, m.x, m.y)]);
      expect(JuegoFusion(semilla: 8, piezasInicio: 99).mojones, hasLength(piezasInicioMaximo));
      expect(JuegoFusion(semilla: 8).mojones, isEmpty);
    });

    test('con arranque al azar los bots siguen dentro del contrato', () {
      for (final tipo in TipoBot.values) {
        final r = jugarBot(tipo, 2, piezasInicio: 6);
        expect(r.puntos, lessThanOrEqualTo(((r.ms / 1000 + 1) * puntosPorSegundoFusion).floor()));
        expect(r.ms, inInclusiveRange(minMsFusion, maxMsFusion));
      }
    });

    test('al llegar al puntaje máximo se acaba ganando', () {
      final j = JuegoFusion(semilla: 1);
      correr(j, 5);
      j.tomarSucesos();
      j.puntosCrudos = topePuntosFusion;
      final tipos = <TipoSuceso>[];
      while (!j.terminado) {
        j.avanzar(pasoFijo);
        tipos.addAll(j.tomarSucesos().map((e) => e.tipo));
      }
      expect(tipos, contains(TipoSuceso.maximo));
      expect(j.desbordo, isFalse);
      expect(j.llegoAlMaximo, isTrue);
    });

    test('la presión sube a x2 y x4 con el tiempo', () {
      final j = JuegoFusion(semilla: 1);
      expect(j.presion, 1);
      j.t = 61;
      expect(j.presion, 2);
      j.t = 121;
      expect(j.presion, 4);
    });
  });

  group('Fusión real: vista', () {
    for (final (mov, tam) in [(Movimiento.completo, const Size(393, 817)), (Movimiento.simple, const Size(320, 560)), (Movimiento.nada, const Size(420, 900))]) {
      testWidgets('se juega con el dedo y avisa al marco una sola vez (${mov.name}, ${tam.width.round()}x${tam.height.round()})', (tester) async {
        final llamadas = <(int, int)>[];
        final j = JuegoFusion(semilla: 21);
        await tester.binding.setSurfaceSize(tam);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          theme: tema(Brightness.dark),
          home: Scaffold(body: VistaMemoria(juego: j, mov: mov, alTerminar: (a, b) => llamadas.add((a, b)))),
        ));
        final zona = find.byKey(const Key('memoria_toque'));
        expect(zona, findsOneWidget);
        expect(find.byKey(const Key('memoria_puntos')), findsOneWidget);
        final caja = tester.getRect(zona);
        final rng = Random(4);
        for (var k = 0; k < 12; k++) {
          final g = await tester.startGesture(Offset(caja.center.dx, caja.top + caja.height * 0.6));
          await g.moveTo(Offset(caja.left + caja.width * (0.25 + rng.nextDouble() * 0.5), caja.top + caja.height * 0.6));
          await g.up();
          for (var f = 0; f < 20; f++) {
            await tester.pump(const Duration(milliseconds: 33));
          }
        }
        expect(j.mojones.length + j.fusiones, greaterThan(4));
        expect(llamadas, isEmpty);
        // Que termine solo: llega al puntaje máximo.
        j.t = 30;
        j.puntosCrudos = topePuntosFusion;
        for (var f = 0; f < 400 && llamadas.isEmpty; f++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        for (var f = 0; f < 40; f++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(llamadas, hasLength(1));
        final (puntos, ms) = llamadas.single;
        expect(ms, inInclusiveRange(minMsFusion, maxMsFusion));
        expect(puntos, lessThanOrEqualTo(((ms / 1000 + 1) * puntosPorSegundoFusion).floor()));
        expect(puntos, j.puntosVisibles);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
