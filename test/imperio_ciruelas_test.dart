// Ciruelas 🫐, tienda, estéticas y racha de 30 días del Imperio: lógica pura y paridad con la base.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/cantidades.dart';
import 'package:rey_cagon/imperio/ciruelas.dart';
import 'package:rey_cagon/imperio/esteticas.dart';
import 'package:rey_cagon/imperio/hoja_racha.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/racha_imperio.dart';

const t0 = 1700000000000;
const hora = 3600000;
final _migracion = File('supabase/migrations/20261101120000_imperio_ciruelas_racha.sql').readAsStringSync();

/// Lee `nombre int[] := array[...]` de la migración.
List<int> _arregloSql(String nombre) {
  final m = RegExp('$nombre int\\[\\] := array\\[([^\\]]*)\\]').firstMatch(_migracion)!;
  return m.group(1)!.split(',').map((s) => int.parse(s.trim())).toList();
}

DateTime _dia(int d) => DateTime.utc(2026, 11, d);

void main() {
  group('racha', () {
    test('sin racha: día 1', () {
      final e = estadoRacha(0, null, _dia(5));
      expect((e.dia, e.reclamado, e.previos), (1, false, 0));
    });

    test('reclamó ayer: toca el siguiente', () {
      final e = estadoRacha(4, _dia(4), _dia(5));
      expect((e.dia, e.reclamado, e.previos), (5, false, 4));
    });

    test('reclamó hoy: el mismo, ya hecho', () {
      final e = estadoRacha(5, _dia(5), _dia(5));
      expect((e.dia, e.reclamado, e.previos), (5, true, 4));
    });

    test('se saltó un día: vuelve al 1', () {
      final e = estadoRacha(12, _dia(3), _dia(5));
      expect((e.dia, e.reclamado), (1, false));
    });

    test('después del 30 vuelve al 1', () {
      final e = estadoRacha(30, _dia(4), _dia(5));
      expect((e.dia, e.reclamado, e.previos), (1, false, 0));
    });

    test('cruce de mes', () {
      final e = estadoRacha(7, DateTime.utc(2026, 10, 31), DateTime.utc(2026, 11, 1));
      expect(e.dia, 8);
    });

    test('fechas: texto y lectura', () {
      expect(fechaTexto(DateTime.utc(2026, 1, 9)), '2026-01-09');
      expect(leerFecha('2026-01-09'), DateTime.utc(2026, 1, 9));
      expect(leerFecha(null), isNull);
    });

    test('tabla: 30 días, premioDia hace ciclo', () {
      expect(premiosRacha.length, diasRacha);
      expect(premioDia(31), same(premioDia(1)));
      expect(premioDia(30).logro, 'constancia');
      expect(logroPorId('constancia'), isNotNull);
      for (final p in premiosRacha) {
        for (final id in p.objetos.keys) {
          expect(objetoPorId(id), isNotNull, reason: id);
        }
      }
    });

    test('paridad con la base: Ciruelas y Fichas por día', () {
      final cir = _arregloSql('cir_por_dia');
      final fichas = _arregloSql('ficha_dias');
      expect(cir.length, diasRacha);
      for (var d = 1; d <= diasRacha; d++) {
        expect(premioDia(d).ciruelas, cir[d - 1], reason: 'día $d');
        expect(premioDia(d).ficha, fichas.contains(d), reason: 'día $d');
      }
    });

    test('paridad con el push: 30 textos con las Ciruelas de cada día', () {
      final ts = File('supabase/functions/notificaciones/index.ts').readAsStringSync();
      final bloque = RegExp(r'const premiosRacha: \[string, string\]\[\] = \[([\s\S]*?)\n\];').firstMatch(ts)!.group(1)!;
      final filas = RegExp(r'\["([^"]*)", "([^"]*)"\]').allMatches(bloque).toList();
      expect(filas.length, diasRacha);
      for (var d = 1; d <= diasRacha; d++) {
        final c = premioDia(d).ciruelas;
        if (c > 0) expect(filas[d - 1].group(1), contains('$c 🫐'), reason: 'día $d');
      }
    });

    test('premio de producción, objetos y logro', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 1; // 1 MJ/s
      expect(imp.aplicarPremioRacha(1, t0), closeTo(15 * 60, 1e-6));
      imp.aplicarPremioRacha(16, t0);
      expect(imp.enInventario('ambientador'), 2);
      imp.aplicarPremioRacha(23, t0);
      expect(imp.enInventario('papel'), 1);
      expect(imp.partida.robotHasta, greaterThan(t0));
      expect(imp.aplicarPremioRacha(30, t0), 0);
      expect(imp.partida.logros, contains('constancia'));
    });

    test('textos del premio', () {
      expect(partesPremio(premioDia(7)).map((p) => p.$1), ['🎟️', '🫐']);
      expect(textoPremio(premioDia(7)), contains('+'));
      expect(textoPremio(premioDia(1)), isNotEmpty);
    });
  });

  group('tienda de Ciruelas', () {
    test('paridad con la base: precios de imperio_gastar_ciruelas', () {
      for (final o in ofertasCiruela) {
        expect(_migracion, contains("when '${o.id}' then ${o.precio}"), reason: o.id);
        expect(ofertaPorId(o.id), same(o));
      }
    });

    test('Cagada fresca: suma 1 h de x2 y no gasta Fichas', () {
      final imp = Imperio(fichas: 2);
      imp.partida.edificios['ciruela'] = 1;
      expect(imp.aplicarOfertaCiruela('cagada_fresca', t0), 0);
      expect(imp.mps(t0), 2);
      expect(imp.fichas, 2);
      imp.aplicarOfertaCiruela('cagada_fresca', t0);
      expect(imp.mps(t0 + hora + 1), 2);
      expect(imp.mps(t0 + 2 * hora), 1);
    });

    test('2 h de producción al instante', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 1;
      final antes = imp.saldo;
      expect(imp.aplicarOfertaCiruela('produccion_2h', t0), closeTo(7200, 1e-6));
      expect(imp.saldo - antes, closeTo(7200, 1e-6));
    });

    test('Robot 24 h se suma', () {
      final imp = Imperio();
      imp.aplicarOfertaCiruela('robot_24h', t0);
      expect(imp.partida.robotHasta, t0 + 24 * hora);
      imp.aplicarOfertaCiruela('robot_24h', t0);
      expect(imp.partida.robotHasta, t0 + 48 * hora);
    });

    test('oferta desconocida no hace nada', () {
      final imp = Imperio();
      expect(imp.aplicarOfertaCiruela('nada', t0), 0);
      expect(imp.partida.robotHasta, 0);
    });
  });

  group('Cagada fresca por cagada real', () {
    test('aplicarFrescaHasta alarga, nunca acorta', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 1;
      expect(imp.aplicarFrescaHasta(t0 + hora), isTrue);
      expect(imp.mps(t0), 2);
      expect(imp.aplicarFrescaHasta(t0 + hora ~/ 2), isFalse);
      expect(imp.mps(t0 + hora - 1), 2);
      expect(imp.mps(t0 + hora), 1);
    });
  });

  group('estéticas y suerte', () {
    test('paridad con la base: id, precio y bono', () {
      for (final e in esteticas) {
        expect(_migracion, contains("('${e.id}', ${e.precio}, ${e.bono})"), reason: e.id);
        expect(esteticaPorId(e.id), same(e));
      }
      final filas = RegExp(r"\('est_\w+', \d+, [\d.]+\)").allMatches(_migracion).length;
      expect(filas, esteticas.length);
    });

    test('bono suma y la probabilidad sube', () {
      expect(bonoSuerteDe(const []), 0);
      expect(bonoSuerteDe(const ['est_tobo', 'est_piso']), closeTo(0.12, 1e-9));
      expect(bonoSuerteDe(const ['no_existe']), 0);
      expect(probConBono(probCiruelaPujoBase, const ['est_tobo']), closeTo(probCiruelaPujoBase * 1.04, 1e-12));
      final todas = esteticas.map((e) => e.id);
      expect(probConBono(probCiruelaCagadaBase, todas), greaterThan(probCiruelaCagadaBase));
    });

    test('tope diario de suerte igual que en la base', () {
      expect(_migracion, contains('suerte_hoy < 3 + cardinality(esteticas) / 2'));
      expect(topeSuertePujo(0), 3);
      expect(topeSuertePujo(1), 3);
      expect(topeSuertePujo(2), 4);
      expect(topeSuertePujo(10), 8);
    });
  });

  group('cantidades de compra', () {
    test('al principio solo x1 y x10', () {
      expect(cantidadesVisibles(tenidos: const [3, 0], saldo: 10, masBarato: (n) => 1e9), {1, 10});
    });

    test('x100 con 50 de un edificio, x1000 con 500', () {
      expect(cantidadesVisibles(tenidos: const [50], saldo: 0, masBarato: (n) => 1e9), {1, 10, 100});
      expect(cantidadesVisibles(tenidos: const [500], saldo: 0, masBarato: (n) => 1e9), {1, 10, 100, 1000});
    });

    test('sale si te alcanza', () {
      expect(cantidadesVisibles(tenidos: const [1], saldo: 1000, masBarato: (n) => n * 10.0), {1, 10, 100});
    });

    test('lo visto se queda', () {
      expect(cantidadesVisibles(tenidos: const [0], saldo: 0, masBarato: (n) => 1e9, vistas: {1000}), {1, 10, 1000});
    });

    test('desde la partida', () {
      final imp = Imperio();
      expect(cantidadesDe(imp, t0), {1, 10});
      imp.partida.edificios['dedo'] = 60;
      expect(cantidadesDe(imp, t0), containsAll([100]));
    });
  });
}
