import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int t0 = 1800000000000;
const int segundo = 1000;
const int minuto = 60 * segundo;
const int hora = 60 * minuto;

/// Ya vio el primer Atasco y no es novato (sin el x0,6). [edificios] = cuántos de cada uno.
Imperio _imperio({Map<String, int> edificios = const {'ciruela': 10, 'cafe': 10, 'arepa': 10}, Random? azar, Ajustes ajustes = Ajustes.porDefecto}) {
  final imp = Imperio(azar: azar, ajustes: ajustes);
  imp.partida
    ..edificios.addAll(edificios)
    ..vioPrimerAtasco = true
    ..segHistoricos = 100000;
  return imp;
}

/// Destapa a mano el primero (los 10 toques).
void _destaparPrimero(Imperio imp, int ahora) {
  for (var k = 0; k < toquesAtasco; k++) {
    imp.tocarAtasco(ahora);
  }
}

/// Juega [segundos] activos de a 1 s sin pujar. Si [destapar], destapa a mano cada Atasco apenas sale (el tope nunca se
/// llena). [comprarCada] > 0: compra una Leche de magnesia cada tantos segundos. Devuelve los segundos en que salió cada
/// Atasco.
List<int> _jugar(Imperio imp, int segundos, {bool destapar = true, int comprarCada = 0}) {
  final salidas = <int>[];
  for (var k = 1; k <= segundos; k++) {
    final ahora = t0 + k * segundo;
    final antes = imp.atascos.length;
    imp.tick(ahora, 1);
    if (comprarCada > 0 && k % comprarCada == 0) {
      imp.partida.saldo = 1e300;
      imp.comprarEdificio('ciruela', ahora);
    }
    if (imp.atascos.length > antes) salidas.add(k);
    if (destapar) {
      while (imp.atascos.isNotEmpty) {
        _destaparPrimero(imp, ahora);
      }
    }
  }
  return salidas;
}

void main() {
  group('en juego', () {
    test('se acumulan hasta el tope, uno por edificio', () {
      final imp = _imperio(azar: Random(1));
      _jugar(imp, 2 * 3600, destapar: false);
      expect(imp.atascos.length, 3);
      expect(imp.atascos.map((a) => a.edificio).toSet().length, 3);
      // Con el tope lleno la presión espera en el umbral.
      expect(imp.partida.presionAtasco, imp.partida.umbralAtasco);
    });

    test('el tope sale del ajuste y nunca pasa de los edificios que producen', () {
      final cinco = _imperio(
          edificios: const {'ciruela': 5, 'cafe': 5, 'arepa': 5, 'inodoro': 5, 'bano': 5}, azar: Random(2), ajustes: const Ajustes(atascosMax: 5));
      _jugar(cinco, 3 * 3600, destapar: false);
      expect(cinco.atascos.length, 5);
      final dos = _imperio(edificios: const {'dedo': 50, 'ciruela': 5, 'cafe': 5}, azar: Random(2));
      expect(dos.topeAtascos, 2);
      _jugar(dos, 3 * 3600, destapar: false);
      expect(dos.atascos.length, 2);
      expect(dos.atascado('dedo'), isFalse);
      final uno = _imperio(azar: Random(2), ajustes: const Ajustes(atascosMax: 1));
      _jugar(uno, 3600, destapar: false);
      expect(uno.atascos.length, 1);
    });

    test('sin compras, nunca dos Atascos a menos de ~0,75 x 240 / 1,5 s', () {
      for (var semilla = 0; semilla < 5; semilla++) {
        final salidas = _jugar(_imperio(azar: Random(semilla)), 3 * 3600);
        expect(salidas.length, greaterThan(20));
        for (var k = 1; k < salidas.length; k++) {
          expect(salidas[k] - salidas[k - 1], greaterThanOrEqualTo(0.75 * 240 / 1.5), reason: 'semilla $semilla, Atasco $k');
        }
      }
    });

    test('en 10 h la media ronda los 240 s (±20%) sin novato ni pujos', () {
      for (var semilla = 0; semilla < 3; semilla++) {
        final salidas = _jugar(_imperio(azar: Random(semilla)), 10 * 3600);
        final media = (salidas.last - salidas.first) / (salidas.length - 1);
        expect(media, inInclusiveRange(240 * 0.8, 240 * 1.2), reason: 'semilla $semilla');
      }
    });

    test('de novato salen más espaciados', () {
      final novato = _imperio(azar: Random(4))..partida.segHistoricos = 0;
      // Los primeros 600 s historicos van a x0,6; se mide solo ese tramo.
      final salidas = _jugar(novato, 590);
      final normal = _jugar(_imperio(azar: Random(4)), 590);
      expect(salidas.length, lessThanOrEqualTo(normal.length));
      expect(novato.factorPresionAtasco(t0), closeTo(0.6, 1e-9)); // 590 s: sigue novato
      _jugar(novato, 20);
      expect(novato.factorPresionAtasco(t0), closeTo(1.0, 1e-9)); // ya pasó de 600 s
    });

    test('pujar rápido acelera hasta x1,5', () {
      final imp = _imperio(azar: Random(5));
      for (var k = 0; k < 200; k++) {
        imp.pujar(t0 + k * 50); // 20 pujos por segundo durante 10 s
      }
      expect(imp.factorPresionAtasco(t0 + 9999), closeTo(1.5, 1e-9));
      // A los 10 s sin pujar se olvida el ritmo.
      expect(imp.factorPresionAtasco(t0 + 30 * segundo), closeTo(1.0, 1e-9));
    });

    test('comprar edificios acerca los Atascos', () {
      for (var semilla = 0; semilla < 3; semilla++) {
        final sin = _jugar(_imperio(azar: Random(semilla)), 2 * 3600).length;
        final con = _jugar(_imperio(azar: Random(semilla)), 2 * 3600, comprarCada: 10).length;
        expect(con, greaterThan(sin * 1.25), reason: 'semilla $semilla: $sin sin compras, $con con compras');
      }
      final imp = _imperio()..partida.saldo = 1e300;
      imp.comprarEdificioVarios('ciruela', 100, t0);
      expect(imp.partida.presionAtasco, closeTo(0.2, 1e-9)); // tope por compra
    });

    test('el Laxante de la abuela fuerza uno si hay lugar', () {
      final imp = _imperio(azar: Random(6));
      imp.partida.efectos['abuela'] = t0 + segundo;
      imp.tick(t0 + segundo, 1);
      expect(imp.atascos.length, 1);
      expect(imp.partida.presionAtasco, lessThan(0.01)); // no toca la presión
    });
  });

  group('destapar', () {
    test('destapar el primero deja el siguiente adelante (y su perfecto cuenta desde ahí)', () {
      final imp = _imperio();
      imp.partida.atascos = [Atasco('ciruela', t0), Atasco('cafe', t0)];
      expect(imp.atascado('ciruela') && imp.atascado('cafe'), isTrue);
      expect(imp.mpsEdificio('ciruela', t0), 0);
      expect(imp.mpsEdificio('cafe', t0), 0);
      expect(imp.mpsEdificio('arepa', t0), greaterThan(0));
      _destaparPrimero(imp, t0 + 10 * segundo);
      expect(imp.atascos.length, 1);
      expect(imp.atasco!.edificio, 'cafe');
      expect(imp.atasco!.desde, t0 + 10 * segundo);
      expect(imp.atascado('ciruela'), isFalse);
      expect(imp.partida.destapes, 1);
    });

    test('el Robot los destapa todos y cuenta cada uno', () {
      final imp = _imperio();
      imp.partida
        ..atascos = [Atasco('ciruela', t0), Atasco('cafe', t0), Atasco('arepa', t0)]
        ..robotHasta = t0 + hora;
      imp.tick(t0 + segundo, 1);
      expect(imp.atascos, isEmpty);
      expect(imp.partida.destapes, 3);
    });

    test('jalar borra los Atascos y la presión', () {
      final imp = _imperio(azar: Random(7));
      _jugar(imp, 3600, destapar: false);
      imp.partida.ausenciaMediaMin = 50;
      expect(imp.atascos, isNotEmpty);
      final p = imp.partida;
      // Lo mismo que hace jalar con estos campos.
      final j = jsonDecode(jsonEncode(imp.toJson())) as Map<String, dynamic>;
      expect(Partida.desdeJson(j).atascos.length, imp.atascos.length);
      expect(p.presionAtasco, greaterThan(0));
    });
  });

  group('guardado', () {
    test('guarda la lista y el primero aparte; carga la lista', () {
      final p = Partida()
        ..atascos = [Atasco('ciruela', t0, 3), Atasco('cafe', t0 + 5)]
        ..presionAtasco = 0.4
        ..umbralAtasco = 1.1
        ..ausenciaMediaMin = 33;
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      expect((j['atasco'] as Map)['e'], 'ciruela');
      final q = Partida.desdeJson(j);
      expect(q.atascos.map((a) => a.edificio), ['ciruela', 'cafe']);
      expect(q.atasco!.toques, 3);
      expect(q.presionAtasco, 0.4);
      expect(q.umbralAtasco, 1.1);
      expect(q.ausenciaMediaMin, 33);
    });

    test('un JSON viejo con solo `atasco` carga ese', () {
      final j = jsonDecode(jsonEncode(Partida().toJson())) as Map<String, dynamic>;
      j.remove('atascos');
      j['atasco'] = {'e': 'cafe', 'd': t0, 't': 2};
      final q = Partida.desdeJson(j);
      expect(q.atascos.length, 1);
      expect(q.atasco!.edificio, 'cafe');
      expect(q.atasco!.toques, 2);
      expect(q.presionAtasco, 0);
      expect(q.umbralAtasco, 0);
      final vacio = Partida.desdeJson(jsonDecode(jsonEncode(Partida().toJson()..remove('atascos'))) as Map<String, dynamic>);
      expect(vacio.atascos, isEmpty);
    });
  });

  group('offline', () {
    test('con ausencia media, el primero cae entre el 35% y el 65% de ella', () {
      for (var semilla = 0; semilla < 100; semilla++) {
        final imp = _imperio(azar: Random(semilla))..partida.ausenciaMediaMin = 100;
        final a = imp.programarAtascoOffline(t0)!;
        final min = (a.en - t0) / minuto;
        expect(min, inInclusiveRange(35, 65), reason: 'semilla $semilla');
        // Llena el tope (3) y cada siguiente va entre 0,6 y 1,4 de la media de los ajustes después del anterior.
        final todos = imp.atascosOfflineProgramados;
        expect(todos.length, 3);
        expect(todos.map((x) => x.edificio).toSet().length, 3);
        final media = Ajustes.porDefecto.atascoOfflineMediaMin;
        for (var k = 1; k < todos.length; k++) {
          final paso = (todos[k].en - todos[k - 1].en) / minuto;
          expect(paso, inInclusiveRange(media * 0.6 - 1e-6, media * 1.4 + 1e-6));
        }
      }
    });

    test('con Atascos abiertos programa solo los que faltan para el tope', () {
      final imp = _imperio(azar: Random(3))..partida.atascos = [Atasco('ciruela', t0), Atasco('cafe', t0)];
      imp.programarAtascoOffline(t0);
      expect(imp.atascosOfflineProgramados.map((a) => a.edificio), ['arepa']);
      final lleno = _imperio(azar: Random(3))..partida.atascos = [Atasco('ciruela', t0), Atasco('cafe', t0), Atasco('arepa', t0)];
      expect(lleno.programarAtascoOffline(t0), isNull);
    });

    test('varios Atascos offline descuentan por tramos', () {
      final imp = _imperio(edificios: const {'ciruela': 10, 'cafe': 10});
      imp.partida.atascosOffline = [AtascoProgramado(t0 + 60 * minuto, 'cafe'), AtascoProgramado(t0 + 30 * minuto, 'ciruela')];
      final r = imp.aplicarOffline(t0, t0 + 2 * hora);
      // 2 h al 25%: la Ciruela (10 MJ/s) deja de contar a los 30 min y el Café (80 MJ/s) a los 60 min.
      const perdido = (90 * 60) * 10 * 0.25 + (60 * 60) * 80 * 0.25;
      expect(r.mjPerdidos, closeTo(perdido, 1e-6));
      expect(r.ganado, closeTo(7200 * 90 * 0.25 - perdido, 1e-6));
      expect(r.atascos.map((a) => a.edificio), ['ciruela', 'cafe']);
      expect(r.atascoEdificio, 'ciruela');
      expect(r.atascosTapados, 2);
      expect(imp.atascos.map((a) => a.edificio), ['ciruela', 'cafe']);
      expect(imp.partida.atascosOffline, isEmpty);
    });

    test('los cubiertos por el Robot no cuestan y suman destapes', () {
      final imp = _imperio(edificios: const {'ciruela': 10, 'cafe': 10});
      imp.partida
        ..atascosOffline = [AtascoProgramado(t0 + 30 * minuto, 'ciruela'), AtascoProgramado(t0 + 60 * minuto, 'cafe')]
        ..robotHasta = t0 + 3 * hora;
      final r = imp.aplicarOffline(t0, t0 + 2 * hora);
      expect(r.mjPerdidos, 0);
      expect(r.ganado, closeTo(7200 * 90 * 0.25, 1e-6));
      expect(r.atascos.every((a) => a.cubierto), isTrue);
      expect(r.atascosTapados, 0);
      expect(imp.partida.destapes, 2);
      expect(imp.atascos, isEmpty);
    });

    test('la ausencia media es una media móvil (alfa 0,3) entre 1 y 1440 min', () {
      final imp = _imperio();
      imp.aplicarOffline(t0, t0 + 100 * minuto);
      expect(imp.partida.ausenciaMediaMin, closeTo(100, 1e-9));
      imp.aplicarOffline(t0, t0 + 200 * minuto);
      expect(imp.partida.ausenciaMediaMin, closeTo(0.7 * 100 + 0.3 * 200, 1e-9));
      imp.aplicarOffline(t0, t0 + 10 * 24 * hora);
      expect(imp.partida.ausenciaMediaMin, closeTo(0.7 * 130 + 0.3 * 1440, 1e-9));
    });
  });
}
