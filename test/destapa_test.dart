// Destapa (baño del estadio): lógica pura con bots tontos y buenos, contrato del servidor, fin de partida, determinismo y
// la vista montada en los tres niveles de movimiento.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/minijuegos/destapa_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/destapa_vista.dart';

// Contrato del servidor (flags en vivo).
const topePuntos = 8000;
const topeMs = 1200000;
const puntosPorSegundo = 14;
const dt = 1 / 60;

/// Bot de jugador: ve un atasco tras [reaccion] s, da [toques] golpes por segundo, tarda [cambio] s en pasar de un
/// inodoro a otro. Si no [entiende], le da golpes al patito y toquecitos al celular (como un novato).
class Bot {
  Bot({required this.toques, required this.reaccion, required this.cambio, required this.entiende, this.despiste = 0, int semilla = 0}) : _r = Random(semilla);
  final double toques, reaccion, cambio;
  final bool entiende;

  /// Probabilidad de quedarse mirando 0.7 s al cambiar de inodoro.
  final double despiste;
  final Random _r;
  int? _foco;
  double _ocupado = 0;
  bool _sosteniendo = false;

  void jugar(JuegoDestapa j) {
    _ocupado -= dt;
    if (_sosteniendo) {
      final i = j.inodoros[_foco!];
      if (i.atasco != TipoAtasco.celular) {
        j.soltar(_foco!);
        _sosteniendo = false;
      }
      return;
    }
    if (_ocupado > 0) return;
    // Elige el más urgente que ya vio.
    Inodoro? mejor;
    double urgencia(Inodoro i) => i.atasco == TipoAtasco.cucaracha ? 0.5 + i.cucaracha : i.agua;
    for (final i in j.inodoros) {
      if (!i.tapado || i.edad < reaccion) continue;
      if (mejor == null || urgencia(i) > urgencia(mejor)) mejor = i;
    }
    if (mejor == null) return;
    if (_foco != null && _foco != mejor.indice) {
      final actual = j.inodoros[_foco!];
      // Se queda en el que estaba si no hay otro mucho peor.
      if (actual.tapado && urgencia(mejor) < urgencia(actual) + 0.2) mejor = actual;
    }
    if (_foco != mejor.indice) {
      _foco = mejor.indice;
      _ocupado = cambio + (_r.nextDouble() < despiste ? 0.7 : 0);
      return;
    }
    final paso = 1 / toques * (0.8 + _r.nextDouble() * 0.4);
    switch (mejor.atasco!) {
      case TipoAtasco.patito when entiende:
        j.deslizar(mejor.indice);
        _ocupado = 0.3;
      case TipoAtasco.celular when entiende:
        j.bajar(mejor.indice);
        _sosteniendo = true;
      default:
        j.bajar(mejor.indice);
        j.soltar(mejor.indice);
        _ocupado = paso;
    }
  }
}

Bot malo([int s = 0]) => Bot(toques: 3, reaccion: 0.8, cambio: 0.5, entiende: false, despiste: 0.4, semilla: s);
Bot normal([int s = 0]) => Bot(toques: 5, reaccion: 0.5, cambio: 0.3, entiende: true, despiste: 0.3, semilla: s);
Bot bueno([int s = 0]) => Bot(toques: 9, reaccion: 0.2, cambio: 0.12, entiende: true, despiste: 0.05, semilla: s);

JuegoDestapa partida(Bot bot, int semilla, {void Function(JuegoDestapa)? cadaPaso}) {
  final j = JuegoDestapa(semilla: semilla);
  while (!j.terminado) {
    bot.jugar(j);
    j.avanzar(dt);
    cadaPaso?.call(j);
    j.tomarEventos();
  }
  return j;
}

/// Techo de puntos del servidor para [t] segundos jugados.
int techo(double t) => min(topePuntos, (t.floor() + 1) * puntosPorSegundo);

/// Avanza [s] segundos en pasos de [dt] y devuelve los eventos que salieron.
List<Evento> correr(JuegoDestapa j, double s) {
  final ev = <Evento>[];
  for (var k = 0; k < (s / dt).round() && !j.terminado; k++) {
    j.avanzar(dt);
    ev.addAll(j.tomarEventos());
  }
  return ev;
}

int mediana(List<int> l) => (List.of(l)..sort())[l.length ~/ 2];

void main() {
  group('contrato del servidor', () {
    for (final (nombre, hacer) in [('malo', malo), ('normal', normal), ('bueno', bueno)]) {
      test('bot $nombre: puntos dentro del techo en cada paso y la partida termina', () {
        for (var s = 0; s < 20; s++) {
          final j = partida(hacer(s), s, cadaPaso: (j) => expect(j.puntos, lessThanOrEqualTo(techo(j.tiempo))));
          expect(j.terminado, isTrue);
          expect(j.tiempo, inInclusiveRange(1.5, topeMs / 1000));
          expect(j.puntos, lessThanOrEqualTo(topePuntos));
        }
      });
    }

    test('sin jugar: nada se desborda en el calentamiento y luego se inunda con 0 puntos', () {
      final j = JuegoDestapa(semilla: 3);
      final ev = correr(j, JuegoDestapa.calentamiento);
      expect(j.desbordes, 0);
      expect(ev.where((e) => e.suceso == Suceso.desborde), isEmpty);
      correr(j, 600);
      expect(j.terminado, isTrue);
      expect(j.pitazoFinal, isFalse);
      expect(j.desbordes, JuegoDestapa.vidas);
      expect(j.puntos, 0);
    });

    test('el pitazo final corta la partida aunque nadie pierda', () {
      final j = JuegoDestapa(semilla: 1);
      // Un jugador imposible que destapa todo al instante.
      while (!j.terminado) {
        for (final i in j.inodoros) {
          if (!i.tapado) continue;
          switch (i.atasco!) {
            case TipoAtasco.patito:
              j.deslizar(i.indice);
            case TipoAtasco.celular:
              i.sostenido = JuegoDestapa.sostenerCelular;
              j.bajar(i.indice);
            default:
              j.bajar(i.indice);
              j.soltar(i.indice);
          }
        }
        j.avanzar(dt);
        j.tomarEventos();
        expect(j.puntos, lessThanOrEqualTo(techo(j.tiempo)));
      }
      expect(j.pitazoFinal, isTrue);
      expect(j.tiempo, closeTo(JuegoDestapa.duracionMaxima, 0.05));
    });
  });

  test('calibración: malo ~15–25, normal ~50–70 al minuto y medio, bueno 150+, destapa_60 alcanzable', () {
    final malos = [for (var s = 0; s < 20; s++) partida(malo(s), s).puntos];
    final a90 = <int>[];
    for (var s = 0; s < 20; s++) {
      var p = -1;
      final j = partida(normal(s), s, cadaPaso: (j) {
        if (p < 0 && j.tiempo >= 90) p = j.puntos;
      });
      a90.add(p < 0 ? j.puntos : p);
    }
    final buenos = [for (var s = 0; s < 20; s++) partida(bueno(s), s)];
    expect(mediana(malos), inInclusiveRange(8, 30));
    expect(mediana(a90), inInclusiveRange(40, 90));
    expect(mediana([for (final j in buenos) j.puntos]), greaterThanOrEqualTo(150));
    expect(buenos.every((j) => j.puntos >= 60), isTrue);
  });

  test('misma semilla, misma partida', () {
    final a = partida(normal(7), 42), b = partida(normal(7), 42);
    expect(a.puntos, b.puntos);
    expect(a.tiempo, b.tiempo);
    expect(a.destapados, b.destapados);
    expect(a.desbordes, b.desbordes);
  });

  test('inodoros: 2 al inicio, 3 a los 20 s, 4 a los 50 s; dorado a los 30 s; prórroga a los 90 s', () {
    final j = JuegoDestapa(semilla: 5);
    expect(j.inodoros.length, 2);
    final bot = bueno(5);
    final ev = <(double, Evento)>[];
    while (!j.terminado && j.tiempo < 95) {
      bot.jugar(j);
      j.avanzar(dt);
      for (final e in j.tomarEventos()) {
        ev.add((j.tiempo, e));
      }
      if (j.tiempo > 19.9 && j.tiempo < 20.1) expect(j.inodoros.length, anyOf(2, 3));
      if (j.tiempo > 20.1 && j.tiempo < 49.9) expect(j.inodoros.length, 3);
      if (j.tiempo > 50.1) expect(j.inodoros.length, 4);
    }
    expect(ev.where((e) => e.$2.suceso == Suceso.nuevoInodoro).map((e) => e.$1.round()), [20, 50]);
    expect(ev.any((e) => e.$2.suceso == Suceso.atasco && e.$2.dorado && e.$1 >= 30 && e.$1 < 40), isTrue);
    expect(ev.where((e) => e.$2.suceso == Suceso.prorroga).map((e) => e.$1.round()), [90]);
    expect(j.prorroga, isTrue);
  });

  group('atascos', () {
    test('normal: 5 golpes lo destapan y vale 1', () {
      final j = JuegoDestapa(semilla: 1, calentar: false)..tapar(0, TipoAtasco.normal);
      j.avanzar(1.0);
      for (var k = 0; k < JuegoDestapa.golpesNormal; k++) {
        expect(j.inodoros[0].tapado, isTrue);
        j.bajar(0);
        j.soltar(0);
      }
      expect(j.inodoros[0].tapado, isFalse);
      expect(j.puntos, 1);
      expect(j.racha, 1);
    });

    test('gordo: se recupera si lo sueltas; 12 golpes seguidos lo destapan y vale 3', () {
      final j = JuegoDestapa(semilla: 1, calentar: false)..tapar(0, TipoAtasco.gordo);
      j.avanzar(1.0);
      for (var k = 0; k < 6; k++) {
        j.bajar(0);
        j.soltar(0);
      }
      expect(j.inodoros[0].golpes, 6);
      final ev = correr(j, 2.0);
      expect(ev.any((e) => e.suceso == Suceso.recupera), isTrue);
      expect(j.inodoros[0].golpes, lessThan(6));
      while (j.inodoros[0].tapado) {
        j.bajar(0);
        j.soltar(0);
      }
      expect(j.puntos, 3);
    });

    test('patito: golpearlo no sirve, deslizar hacia arriba sí', () {
      final j = JuegoDestapa(semilla: 1, calentar: false)..tapar(0, TipoAtasco.patito);
      for (var k = 0; k < 10; k++) {
        j.bajar(0);
        j.soltar(0);
      }
      expect(j.inodoros[0].atasco, TipoAtasco.patito);
      j.deslizar(0);
      expect(j.inodoros[0].tapado, isFalse);
      expect(j.puntos, 2);
      // Deslizar sobre otro atasco no hace nada.
      j.tapar(1, TipoAtasco.normal);
      j.deslizar(1);
      expect(j.inodoros[1].tapado, isTrue);
    });

    test('celular: mantener 0.8 s lo saca; toques a lo loco lo hunden y sube el agua', () {
      final j = JuegoDestapa(semilla: 1, calentar: false)..tapar(0, TipoAtasco.celular);
      final agua = j.inodoros[0].agua;
      j.bajar(0);
      j.soltar(0);
      final ev = j.tomarEventos();
      expect(ev.any((e) => e.suceso == Suceso.hundido), isTrue);
      expect(j.inodoros[0].agua, greaterThan(agua));
      j.bajar(0);
      correr(j, JuegoDestapa.sostenerCelular + 0.05);
      expect(j.inodoros[0].tapado, isFalse);
      expect(j.puntos, 2);
    });

    test('cucaracha: se aplasta con un toque; si escapa rompe el combo pero no quita vida', () {
      final j = JuegoDestapa(semilla: 1, calentar: false)..tapar(0, TipoAtasco.cucaracha);
      j.bajar(0);
      expect(j.inodoros[0].tapado, isFalse);
      expect(j.puntos, 2);
      j.racha = JuegoDestapa.rachaX2;
      expect(j.multiplicador, 2);
      j.tapar(1, TipoAtasco.cucaracha);
      final ev = correr(j, j.inodoros[1].vidaCucaracha + 0.1);
      expect(ev.any((e) => e.suceso == Suceso.escapa), isTrue);
      expect(ev.any((e) => e.suceso == Suceso.comboRoto), isTrue);
      expect(j.racha, 0);
      expect(j.desbordes, 0);
    });

    test('desborde: rompe el combo, guarda la causa y a los 3 se acaba', () {
      final j = JuegoDestapa(semilla: 1, calentar: false)..tapar(0, TipoAtasco.gordo);
      j.racha = 20;
      while (j.desbordes == 0) {
        correr(j, 0.1);
      }
      expect(j.tipoUltimoDesborde, isNotNull);
      expect(j.racha, 0);
      correr(j, 600);
      expect(j.terminado, isTrue);
      expect(j.desbordes, JuegoDestapa.vidas);
      j.bajar(0);
      expect(j.puntos, 0);
    });

    test('combo: x2 desde 15 seguidos, x3 desde 35; el dorado vale 5 por el multiplicador', () {
      final j = JuegoDestapa(semilla: 1, calentar: false);
      j.avanzar(30); // sube el techo del servidor
      j.tomarEventos();
      j.racha = JuegoDestapa.rachaX2 - 1;
      j.tapar(0, TipoAtasco.cucaracha);
      j.bajar(0);
      expect(j.multiplicador, 2);
      expect(j.tomarEventos().any((e) => e.suceso == Suceso.combo && e.valor == 2), isTrue);
      j.racha = JuegoDestapa.rachaX3;
      final antes = j.puntos;
      j.tapar(0, TipoAtasco.normal, dorado: true);
      for (var k = 0; k < JuegoDestapa.golpesNormal; k++) {
        j.bajar(0);
        j.soltar(0);
      }
      expect(j.puntos - antes, JuegoDestapa.puntosDorado * 3);
    });
  });

  group('vista', () {
    for (final mov in Movimiento.values) {
      testWidgets('se monta, se juega y termina una sola vez ($mov)', (tester) async {
        final fines = <(int, int)>[];
        final juego = JuegoDestapa(semilla: 2, calentar: false);
        await tester.binding.setSurfaceSize(const Size(393, 873));
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: VistaDestapa(alTerminar: (p, ms) => fines.add((p, ms)), mov: mov, juego: juego))));
        expect(find.byKey(const Key('destapa_puntos')), findsOneWidget);
        expect(find.byKey(const Key('destapa_reloj')), findsOneWidget);
        // Unos golpes en el primer inodoro y en el segundo.
        for (var k = 0; k < 40; k++) {
          await tester.tapAt(Offset(k.isEven ? 90 : 290, 650));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.dragFrom(const Offset(90, 700), const Offset(0, -120));
        var vueltas = 0;
        while (!juego.terminado && vueltas++ < 4000) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(juego.terminado, isTrue);
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(fines.length, 1);
        final (p, ms) = fines.single;
        expect(ms, inInclusiveRange(1500, topeMs));
        expect(p, lessThanOrEqualTo(min(topePuntos, (ms ~/ 1000 + 1) * puntosPorSegundo)));
        expect(p, juego.puntos);
        await tester.pump(const Duration(seconds: 2));
        expect(fines.length, 1);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
