import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/minijuegos/destapa_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/destapa_vista.dart';
import 'package:rey_cagon/tema.dart';

/// Topes del servidor para destapa (migración de minijuegos).
const topePuntos = 8000;
const topeMs = 1200000;
const puntosPorSegundo = 14;

// Avanza en cuadros de 60 fps hasta [t].
void hasta(JuegoDestapa j, double t) {
  while (!j.terminado && j.tiempo < t - 1e-9) {
    j.avanzar(min(1 / 60, t - j.tiempo));
  }
}

/// Juega una nota: espera su hora (más la compensación de pantalla) con un error de [error] s y toca.
/// Si es de mantener, mantiene hasta su fin (o suelta antes si [soltarAntes]).
Golpe jugarNota(JuegoDestapa j, {double error = 0, bool soltarAntes = false}) {
  final n = esperarNota(j);
  hasta(j, n.t + JuegoDestapa.compensacion + error);
  final g = j.toque();
  if (n.mantener && g != Golpe.fallo) {
    if (soltarAntes) {
      j.avanzar(0.05);
      j.suelta();
    } else {
      hasta(j, n.fin! + JuegoDestapa.compensacion + 0.02);
      j.suelta();
    }
  }
  return g;
}

/// En los respiros no hay nota a la vista: espera a que salga la siguiente.
Nota esperarNota(JuegoDestapa j) {
  while (j.proxima == null) {
    j.avanzar(1 / 60);
  }
  return j.proxima!;
}

/// Partida perfecta entera: hasta que el turno se acaba solo.
JuegoDestapa partidaPerfecta(int semilla) {
  final j = JuegoDestapa(semilla: semilla);
  while (!j.terminado) {
    jugarNota(j);
  }
  return j;
}

/// Un jugador de carne y hueso: error de tiempo normal con desviación [sd] y un despiste cada tanto.
JuegoDestapa partidaHumana(int semilla, {double sd = 0.07, double despiste = 0.03}) {
  final r = Random(semilla);
  final j = JuegoDestapa(semilla: semilla);
  while (!j.terminado) {
    final n = esperarNota(j);
    if (r.nextDouble() < despiste) {
      hasta(j, n.t + 0.5);
      continue;
    }
    // Box-Muller.
    final e = sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble()) * sd;
    jugarNota(j, error: e, soltarAntes: r.nextDouble() < despiste);
  }
  return j;
}

void main() {
  group('Destapa: frases', () {
    test('la primera nota es un toque en la entrada y las frases se generan solas', () {
      final j = JuegoDestapa(semilla: 1);
      expect(j.proxima!.t, JuegoDestapa.entrada);
      expect(j.proxima!.mantener, isFalse);
      for (var i = 0; i < 40; i++) {
        expect(jugarNota(j), Golpe.perfecto);
      }
      expect(j.fallos, 0);
      expect(j.notas.where((n) => n.estado == EstadoNota.pendiente), isNotEmpty);
    });

    test('salen patrones variados: medio tiempo y notas de mantener', () {
      final j = JuegoDestapa(semilla: 7);
      var medios = false, mantener = false;
      final vistas = <double>{};
      while (j.tiempo < 200 && !j.terminado) {
        final n = esperarNota(j);
        if (vistas.add(n.t)) {
          if (n.mantener) mantener = true;
          final enTiempo = (n.t - JuegoDestapa.entrada) / j.compas;
          if ((enTiempo - enTiempo.round()).abs() > 0.2) medios = true;
        }
        jugarNota(j);
      }
      expect(mantener, isTrue);
      expect(medios, isTrue);
    });

    test('mantener hasta el final suma; soltar antes es fallo', () {
      final j = JuegoDestapa(semilla: 3);
      // Juega perfecto hasta que toque una de mantener.
      while (!esperarNota(j).mantener) {
        jugarNota(j);
      }
      final antes = j.puntos;
      expect(jugarNota(j), isNot(Golpe.fallo));
      expect(j.puntos, greaterThan(antes + 1));
      expect(j.fallos, 0);
      while (!esperarNota(j).mantener) {
        jugarNota(j);
      }
      final f = j.fallos;
      jugarNota(j, soltarAntes: true);
      expect(j.fallos, f + 1);
      expect(j.racha, 0);
    });

    test('compensación: tocar en la hora exacta de pantalla es perfecto, muy tarde es fallo', () {
      final j = JuegoDestapa(semilla: 2, calentamiento: false);
      hasta(j, JuegoDestapa.entrada);
      expect(j.toque(desfase: JuegoDestapa.compensacion), Golpe.perfecto);
      final n = esperarNota(j);
      hasta(j, n.t + JuegoDestapa.compensacion + JuegoDestapa.ventanaPerfecta + 0.02);
      expect(j.toque(), Golpe.bueno);
      final n2 = esperarNota(j);
      hasta(j, n2.t + JuegoDestapa.compensacion + JuegoDestapa.ventanaBuena + 0.01);
      expect(j.fallos, 1);
    });
  });

  group('Destapa: calentamiento', () {
    test('sin tocar, la primera frase no suma fallos pero se ve el fallo', () {
      final j = JuegoDestapa(semilla: 1);
      expect(j.calentando, isTrue);
      final primera = j.notas.where((n) => n.calentamiento).toList();
      expect(primera, hasLength(patronesDestapa.first.notas.length));
      // Hasta que pasa la ventana de la última nota de la frase.
      hasta(j, primera.last.t + JuegoDestapa.compensacion + JuegoDestapa.ventanaBuena + 0.05);
      expect(j.fallos, 0);
      expect(j.calentando, isFalse);
      final fallosVistos = j.tomarEventos().where((e) => e.suceso == Suceso.fallo).length;
      expect(fallosVistos, primera.length);
      expect(primera.every((n) => n.estado == EstadoNota.fallada), isTrue);
      // Después sí cuenta: la siguiente nota que pasa sube el agua.
      final n = esperarNota(j);
      expect(n.calentamiento, isFalse);
      hasta(j, n.t + JuegoDestapa.compensacion + JuegoDestapa.ventanaBuena + 0.02);
      expect(j.fallos, 1);
    });

    test('dura más sin tocar que sin calentamiento', () {
      double sinTocar(bool calentamiento) {
        final j = JuegoDestapa(semilla: 3, calentamiento: calentamiento);
        hasta(j, 60);
        expect(j.terminado, isTrue);
        return j.tiempo;
      }

      final con = sinTocar(true), sin = sinTocar(false);
      expect(con, greaterThan(sin + 1));
      expect(sin, lessThan(5));
    });

    test('toque suelto o tarde en el calentamiento: corta la racha y no suma; después sí', () {
      final j = JuegoDestapa(semilla: 4);
      expect(j.toque(), Golpe.fallo);
      expect(j.fallos, 0);
      expect(j.ultimo, Golpe.fallo);
      expect(jugarNota(j), Golpe.perfecto);
      expect(j.racha, 1);
      expect(jugarNota(j, error: JuegoDestapa.ventanaBuena + 0.03), Golpe.fallo);
      expect(j.fallos, 0);
      expect(j.racha, 0);
      while (j.calentando) {
        j.avanzar(1 / 60);
      }
      expect(j.toque(), Golpe.fallo);
      expect(j.fallos, 1);
    });

    test('una sola vez por partida: ninguna otra frase calienta', () {
      final j = JuegoDestapa(semilla: 8);
      var notasCalientes = 0;
      final vistas = <Nota>{};
      var volvio = false;
      var salio = false;
      while (j.tiempo < 120 && !j.terminado) {
        for (final n in j.notas) {
          if (vistas.add(n) && n.calentamiento) notasCalientes++;
        }
        if (!j.calentando) salio = true;
        if (salio && j.calentando) volvio = true;
        jugarNota(j);
      }
      expect(notasCalientes, patronesDestapa.first.notas.length);
      expect(volvio, isFalse);
    });

    test('no cambia los puntos máximos: la partida perfecta da lo mismo con y sin calentamiento', () {
      for (final s in [1, 2, 3]) {
        final con = partidaPerfecta(s);
        final sin = JuegoDestapa(semilla: s, calentamiento: false);
        while (!sin.terminado) {
          jugarNota(sin);
        }
        expect(con.puntos, sin.puntos);
        expect(con.puntos, lessThan(topePuntos));
      }
    });

    testWidgets('la vista avisa que está calentando y lo quita al terminar la frase', (tester) async {
      final j = JuegoDestapa(semilla: 1);
      await tester.pumpWidget(MaterialApp(
        theme: tema(Brightness.light),
        home: Scaffold(body: VistaDestapa(alTerminar: (_, _) {}, mov: Movimiento.nada, juego: j)),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('destapa_calentando')), findsOneWidget);
      // Sin tocar, pasa la primera frase entera: el agua no sube.
      for (var i = 0; i < 300 && j.calentando; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(j.calentando, isFalse);
      expect(j.fallos, 0);
      expect(find.byKey(const Key('destapa_calentando')), findsNothing);
      // Desmonta para que el reloj se pare.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('Destapa: racha y atasco gordo', () {
    test('la racha sube el multiplicador hasta x3 y un fallo lo baja', () {
      final j = JuegoDestapa(semilla: 4);
      expect(j.multiplicador, 1);
      while (j.racha < JuegoDestapa.rachaX2) {
        jugarNota(j);
      }
      expect(j.multiplicador, 2);
      while (j.racha < JuegoDestapa.rachaX3) {
        jugarNota(j);
      }
      expect(j.multiplicador, 3);
      expect(j.tomarEventos().where((e) => e.suceso == Suceso.multiplicador).length, 2);
      j.toque();
      expect(j.multiplicador, 1);
    });

    test('cada 4 inodoros viene un atasco gordo; vencerlo baja el agua', () {
      final j = JuegoDestapa(semilla: 5, calentamiento: false);
      // Un fallo a propósito al principio.
      j.toque();
      expect(j.fallos, 1);
      while (!j.esJefe) {
        jugarNota(j);
      }
      expect(j.inodoros, JuegoDestapa.cadaJefe - 1);
      expect(j.tomarEventos().any((e) => e.suceso == Suceso.jefe), isTrue);
      expect(j.requiere, greaterThan(6 + 2 * j.inodoros));
      while (j.inodoros < JuegoDestapa.cadaJefe) {
        jugarNota(j);
      }
      expect(j.jefesVencidos, 1);
      expect(j.fallos, 0);
      expect(j.tomarEventos().any((e) => e.suceso == Suceso.jefeVencido), isTrue);
    });

    test('el tiempo se acelera por inodoro sin bajar del mínimo', () {
      final j = JuegoDestapa(semilla: 6);
      final c0 = j.compas;
      while (j.inodoros < 3) {
        jugarNota(j);
      }
      expect(j.compas, lessThan(c0));
      while (j.inodoros < 20 && !j.terminado) {
        jugarNota(j);
      }
      expect(j.compas, greaterThanOrEqualTo(JuegoDestapa.compasMinimo));
    });
  });

  group('Destapa: topes del servidor', () {
    test('partida perfecta larga: se acaba sola y queda muy por debajo de los topes', () {
      for (final s in [1, 2, 3]) {
        final j = partidaPerfecta(s);
        final ms = (j.tiempo * 1000).round();
        // ignore: avoid_print
        print('perfecta semilla $s: ${j.puntos} puntos en ${j.tiempo.round()} s, inodoros ${j.inodoros}, '
            '${(j.puntos / j.tiempo).toStringAsFixed(1)} pts/s, perfectos ${j.perfectos}');
        expect(j.turnoCompleto, isTrue);
        expect(j.fallos, 0);
        expect(ms, lessThan(topeMs));
        expect(j.puntos, lessThan(topePuntos * 0.7));
        expect(j.puntos, lessThan((ms / 1000 + 1) * puntosPorSegundo * 0.75));
      }
    });

    test('en ningún momento una partida perfecta pasa del tope de puntos por segundo', () {
      final j = JuegoDestapa(semilla: 9);
      while (!j.terminado) {
        jugarNota(j);
        expect(j.puntos, lessThan((j.tiempo + 1) * puntosPorSegundo), reason: 't=${j.tiempo}');
      }
    });

    test('un jugador normal queda cerca de la meta de 60', () {
      final puntos = [for (var s = 0; s < 200; s++) partidaHumana(s).puntos]..sort();
      final media = puntos.reduce((a, b) => a + b) / puntos.length;
      // ignore: avoid_print
      print('humano: media ${media.round()}, mediana ${puntos[100]}, p90 ${puntos[180]}, max ${puntos.last}');
      expect(media, inInclusiveRange(30, 160));
    });
  });

  group('Destapa: vista', () {
    for (final mov in Movimiento.values) {
      testWidgets('se juega con movimiento $mov: toca, acierta y termina al desbordarse', (tester) async {
        int? fin;
        final j = JuegoDestapa(semilla: 1, calentamiento: false);
        await tester.pumpWidget(MaterialApp(
          theme: tema(Brightness.dark),
          home: Scaffold(body: VistaDestapa(alTerminar: (p, _) => fin = p, mov: mov, juego: j)),
        ));
        // Hasta la primera nota, y toca a su hora.
        for (var i = 0; i < 86; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.tap(find.byKey(const Key('destapa_toque')));
        await tester.pump(const Duration(milliseconds: 16));
        expect(j.puntos, greaterThan(0));
        expect(find.byKey(const Key('destapa_golpe')), findsOneWidget);
        // Toques sueltos hasta desbordar.
        for (var i = 0; i < JuegoDestapa.fallosMaximos + 2 && !j.terminado; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const Key('destapa_toque')));
        }
        await tester.pump(const Duration(milliseconds: 700));
        expect(j.terminado, isTrue);
        expect(fin, j.puntos);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
