// Memoria del rollo: puntaje y tope del servidor, mazo, vista previa, flujo rápido, exploración contra fallo, racha,
// destapador, cucaracha, PNG de los emojis y una partida entera en la vista.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/minijuegos/memoria_carta.dart';
import 'package:rey_cagon/imperio/minijuegos/memoria_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/memoria_vista.dart';
import 'package:rey_cagon/tema.dart';

/// Índice de la otra carta con el mismo emoji.
int pareja(JuegoMemoria j, int i) => [for (var k = 0; k < j.cartas.length; k++) k].firstWhere((k) => k != i && j.cartas[k].emoji == j.cartas[i].emoji);

/// Una carta tapada cuyo emoji no es el de [i] (ni la cucaracha, para no mover nada).
int otra(JuegoMemoria j, int i) => [for (var k = 0; k < j.cartas.length; k++) k].firstWhere(
    (k) => k != i && j.cartas[k].emoji != j.cartas[i].emoji && j.cartas[k].emoji != emojiCucaracha && j.cartas[k].estado == EstadoCarta.oculta);

int primeraDe(JuegoMemoria j, String emoji) => j.cartas.indexWhere((c) => c.emoji == emoji);

/// Todas las parejas seguidas, sin perder tiempo (salvo esperar al destapador, que no gasta papel).
void jugarPerfecto(JuegoMemoria j) {
  while (!j.terminado) {
    if (j.bloqueado) {
      j.avanzar(0.05);
      continue;
    }
    final i = j.cartas.indexWhere((c) => c.estado == EstadoCarta.oculta);
    expect(j.toca(i), isTrue);
    expect(j.toca(pareja(j, i)), isTrue);
  }
}

void main() {
  group('Memoria: puntaje', () {
    test('el máximo teórico es exactamente el tope del servidor (3600)', () {
      expect(maximoPartidaMemoria, lessThanOrEqualTo(3600));
      expect(maximoPartidaMemoria, 3600);
      expect([for (final n in nivelesMemoria) maximoNivelMemoria(n)], [870, 1200, 1530]);
    });

    test('multiplicador de 1 a 4 y puntos por pareja', () {
      expect([for (var r = 0; r <= 6; r++) multiplicadorDe(r)], [1, 1, 2, 3, 4, 4, 4]);
      expect(puntosDePareja(1), 50);
      expect(puntosDePareja(4), 110);
    });

    test('partida perfecta da el máximo, con y sin vista previa', () {
      for (final previa in [false, true]) {
        final p = PartidaMemoria(azar: Random(7), conPrevia: previa);
        for (var n = 0; n < nivelesMemoria.length; n++) {
          if (previa) {
            expect(p.juego.toca(0), isFalse);
            p.juego.avanzar(nivelesMemoria[n].previa + 0.01);
          }
          jugarPerfecto(p.juego);
          expect(p.juego.puntos, maximoNivelMemoria(nivelesMemoria[n]));
          expect(p.terminada, n == nivelesMemoria.length - 1);
          if (!p.terminada) expect(p.siguiente(), isTrue);
        }
        expect(p.puntos, maximoPartidaMemoria);
        expect(p.erroresTotal, 0);
        expect(p.siguiente(), isFalse);
      }
    });

    test('partidas al azar nunca pasan del máximo ni bajan de 0', () {
      for (var semilla = 0; semilla < 150; semilla++) {
        final r = Random(semilla);
        final p = PartidaMemoria(azar: Random(semilla + 1000), conPrevia: r.nextBool());
        var pasos = 0;
        while (pasos++ < 20000) {
          final j = p.juego;
          if (j.terminado) {
            if (!p.siguiente()) break;
            continue;
          }
          if (r.nextDouble() < 0.3) j.avanzar(r.nextDouble() * 0.6);
          j.toca(r.nextInt(j.cartas.length));
          expect(p.puntosEnVivo, inInclusiveRange(0, maximoPartidaMemoria));
        }
        expect(p.terminada, isTrue, reason: 'semilla $semilla');
        expect(p.puntos, inInclusiveRange(0, maximoPartidaMemoria));
      }
    });

    test('lento gasta el papel y baja el bonus; con fallos no hay bonus limpio', () {
      final j = JuegoMemoria(nivelesMemoria[0], azar: Random(3), conPrevia: false);
      final a = 0;
      j.toca(a);
      j.avanzar(1);
      expect(j.papel, closeTo(nivelesMemoria[0].papelInicial - 1, 1e-9));
      j.toca(pareja(j, a));
      j.avanzar(100);
      expect(j.papel, 0);
      // Fallo: volver a tocar una carta ya vista con otra que no es su pareja.
      final b = otra(j, a);
      final c = otra(j, b);
      j.toca(b);
      j.toca(c);
      j.avanzar(1);
      j.toca(c);
      j.toca(b);
      expect(j.errores, 1);
      jugarPerfecto(j);
      expect(j.bonusPapel, lessThan(bonusPapelPorPareja * j.nivel.pares));
      expect(j.bonusLimpio, 0);
    });
  });

  group('Memoria: mazo', () {
    test('cada emoji dos veces, especiales solo en su nivel, el rollo no sale de cara', () {
      for (var s = 0; s < 20; s++) {
        for (final n in nivelesMemoria) {
          final j = JuegoMemoria(n, azar: Random(s));
          expect(j.cartas.length, n.cartas);
          final cuenta = <String, int>{};
          for (final c in j.cartas) {
            cuenta[c.emoji] = (cuenta[c.emoji] ?? 0) + 1;
          }
          expect(cuenta.values.every((v) => v == 2), isTrue);
          expect(cuenta.length, n.pares);
          expect(cuenta.containsKey(emojiDestapador), n.destapador);
          expect(cuenta.containsKey(emojiCucaracha), n.cucaracha);
          expect(cuenta.containsKey(emojiReverso), isFalse);
        }
      }
    });

    test('los PNG de los emojis (y del reverso) existen y están en emoji.dart', () {
      final src = File('lib/emoji.dart').readAsStringSync();
      final mapa = {for (final m in RegExp(r"'([^']+)':\s*'([a-z0-9_\-]+)'").allMatches(src)) m.group(1)!: m.group(2)!};
      for (final e in [...emojisMemoria, emojiReverso]) {
        final f = mapa[e];
        expect(f, isNotNull, reason: 'falta $e en emoji.dart');
        expect(File('assets/emoji/$f.png').existsSync(), isTrue, reason: 'falta PNG de $e');
      }
      expect(emojisMemoria.toSet().length, emojisMemoria.length);
      expect(emojisMemoria.length, greaterThanOrEqualTo(nivelesMemoria.map((n) => n.pares).reduce(max)));
    });
  });

  group('Memoria: jugadas', () {
    test('la vista previa muestra todo, bloquea y no gasta papel', () {
      final j = JuegoMemoria(nivelesMemoria[0], azar: Random(1));
      expect(j.enPrevia, isTrue);
      expect([for (var i = 0; i < j.cartas.length; i++) j.seVe(i)].every((v) => v), isTrue);
      expect(j.toca(0), isFalse);
      j.avanzar(1);
      expect(j.papel, j.nivel.papelInicial);
      j.avanzar(j.nivel.previa);
      expect(j.enPrevia, isFalse);
      expect(j.seVe(0), isFalse);
      expect(j.papel, j.nivel.papelInicial);
      expect(j.toca(0), isTrue);
    });

    test('exploración no castiga; repetir una carta vista sí es fallo y corta la racha', () {
      final j = JuegoMemoria(nivelesMemoria[0], azar: Random(2), conPrevia: false);
      j.toca(0);
      j.toca(pareja(j, 0));
      expect(j.racha, 1);
      expect(j.multiplicadorSiguiente, 2);
      final a = otra(j, 0);
      final b = otra(j, a);
      j.toca(a);
      j.toca(b);
      expect(j.jugada!.tipo, TipoJugada.exploracion);
      expect(j.errores, 0);
      expect(j.racha, 1, reason: 'explorar no corta la racha');
      j.avanzar(JuegoMemoria.esperaFallo + 0.01);
      j.toca(b);
      j.toca(a);
      expect(j.jugada!.tipo, TipoJugada.fallo);
      expect(j.errores, 1);
      expect(j.racha, 0);
      expect(j.multiplicadorSiguiente, 1);
      expect(j.toca(-1), isFalse);
      expect(j.toca(999), isFalse);
    });

    test('flujo rápido: tocar otra carta tapa la pareja equivocada al instante', () {
      final j = JuegoMemoria(nivelesMemoria[0], azar: Random(4), conPrevia: false);
      final a = 0;
      final b = otra(j, a);
      j.toca(a);
      expect(j.toca(a), isFalse);
      j.toca(b);
      expect(j.esperando, isTrue);
      final c = otra(j, b);
      expect(j.toca(c), isTrue);
      expect(j.esperando, isFalse);
      expect(j.cartas[a].estado, EstadoCarta.oculta);
      expect(j.cartas[b].estado, EstadoCarta.oculta);
      expect(j.cartas[c].estado, EstadoCarta.visible);
      // Sin tocar nada, la pareja equivocada se tapa sola.
      final d = otra(j, c);
      j.toca(d);
      j.avanzar(JuegoMemoria.esperaFallo + 0.01);
      expect(j.cartas[c].estado, EstadoCarta.oculta);
      expect(j.cartas[d].estado, EstadoCarta.oculta);
    });

    test('la racha sube el multiplicador hasta x4', () {
      final j = JuegoMemoria(nivelesMemoria[2], azar: Random(5), conPrevia: false);
      final mults = <int>[];
      for (var k = 0; k < 6; k++) {
        if (j.bloqueado) j.avanzar(JuegoMemoria.tiempoDestapa + 0.01);
        final i = j.cartas.indexWhere((c) => c.estado == EstadoCarta.oculta);
        j.toca(i);
        j.toca(pareja(j, i));
        mults.add(j.jugada!.multiplicador);
      }
      expect(mults, [1, 2, 3, 4, 4, 4]);
      expect(j.mejorRacha, 6);
    });

    test('destapador: deja ver todo un momento, bloquea y congela el papel', () {
      final j = JuegoMemoria(nivelesMemoria[1], azar: Random(6), conPrevia: false);
      final i = primeraDe(j, emojiDestapador);
      j.toca(i);
      j.avanzar(0.5);
      final papel = j.papel;
      j.toca(pareja(j, i));
      expect(j.jugada!.destapa, isTrue);
      expect(j.destapando, isTrue);
      expect(j.bloqueado, isTrue);
      expect([for (var k = 0; k < j.cartas.length; k++) j.seVe(k)].every((v) => v), isTrue);
      final libre = j.cartas.indexWhere((c) => c.estado == EstadoCarta.oculta);
      expect(j.toca(libre), isFalse);
      j.avanzar(JuegoMemoria.tiempoDestapa / 2);
      expect(j.papel, greaterThanOrEqualTo(papel), reason: 'no se gasta mientras se ve todo');
      j.avanzar(JuegoMemoria.tiempoDestapa);
      expect(j.destapando, isFalse);
      expect(j.seVe(libre), isFalse);
      expect(j.toca(libre), isTrue);
    });

    test('cucaracha: en una pareja equivocada cambia de sitio dos cartas tapadas', () {
      final j = JuegoMemoria(nivelesMemoria[2], azar: Random(8), conPrevia: false);
      final antes = [...j.cartas];
      final a = primeraDe(j, emojiCucaracha);
      final b = otra(j, a);
      j.toca(a);
      j.toca(b);
      final cambio = j.jugada!.cambio;
      expect(cambio, isNotNull);
      final (x, y) = cambio!;
      expect({x, y}.intersection({a, b}), isEmpty);
      expect(identical(j.cartas[x], antes[y]), isTrue);
      expect(identical(j.cartas[y], antes[x]), isTrue);
      expect(j.cartas[x].estado, EstadoCarta.oculta);
      expect(j.cartas[y].estado, EstadoCarta.oculta);
      // Sin cucaracha no se mueve nada.
      j.avanzar(JuegoMemoria.esperaFallo + 0.01);
      final c = otra(j, a);
      j.toca(c);
      j.toca(otra(j, c));
      expect(j.jugada!.cambio, isNull);
    });

    test('en el nivel sin cucaracha nunca se mueven cartas', () {
      final j = JuegoMemoria(nivelesMemoria[0], azar: Random(9), conPrevia: false);
      final r = Random(9);
      for (var k = 0; k < 200 && !j.terminado; k++) {
        if (j.toca(r.nextInt(j.cartas.length))) expect(j.jugada!.cambio, isNull);
      }
    });
  });

  group('Memoria: vista', () {
    for (final (mov, tam) in [(Movimiento.completo, const Size(420, 820)), (Movimiento.simple, const Size(320, 560)), (Movimiento.nada, const Size(360, 640))]) {
      testWidgets('partida entera en la vista termina y avisa al marco (${mov.name}, ${tam.width.round()}x${tam.height.round()})', (tester) async {
        int? puntos, ms;
        final p = PartidaMemoria(azar: Random(11), conPrevia: false);
        await tester.binding.setSurfaceSize(tam);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          theme: tema(Brightness.light),
          home: Scaffold(body: VistaMemoria(partida: p, mov: mov, alTerminar: (a, b) => (puntos, ms) = (a, b))),
        ));
        Future<void> esperar(double segundos) async {
          for (var t = 0.0; t < segundos; t += 0.05) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        for (var n = 0; n < nivelesMemoria.length; n++) {
          final j = p.juego;
          while (!j.terminado) {
            if (j.bloqueado) {
              await esperar(0.1);
              continue;
            }
            final i = j.cartas.indexWhere((c) => c.estado == EstadoCarta.oculta);
            await tester.tap(find.byKey(Key('carta_$i')));
            await tester.tap(find.byKey(Key('carta_${pareja(j, i)}')));
            await tester.pump();
          }
          await esperar(1.2);
          if (n < nivelesMemoria.length - 1) {
            expect(find.byKey(const Key('memoria_siguiente')), findsOneWidget);
            await tester.ensureVisible(find.byKey(const Key('memoria_siguiente')));
            await tester.tap(find.byKey(const Key('memoria_siguiente')));
            await tester.pump();
          }
        }
        expect(puntos, maximoPartidaMemoria);
        expect(ms, isNotNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
