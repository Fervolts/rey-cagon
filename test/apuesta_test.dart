// Cagadón con apuesta: cobro, premio, empate y devolución (lógica pura) y paridad con la migración.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/apuesta.dart';
import 'package:rey_cagon/imperio/catalogo.dart';
import 'package:rey_cagon/imperio/estado.dart';
import 'package:rey_cagon/imperio/flags.dart';

final _migracion = File('supabase/migrations/20261108140000_cagadon_apuesta.sql').readAsStringSync();

Partida _p(double saldo, double total) => Partida()
  ..saldo = saldo
  ..mjTotal = total;

void main() {
  _apuntes();
  _logros();
  group('opciones', () {
    test('tope 60 da todas', () => expect(opcionesApuesta(60), [0, 15, 30, 60]));
    test('tope 30 corta la de 60', () => expect(opcionesApuesta(30), [0, 15, 30]));
    test('tope 0 apaga', () => expect(opcionesApuesta(0), [0]));
    test('flag por defecto 60 y se limita a 0..60', () {
      expect(const FlagsImperio().apuestaMaxMin, 60);
      expect(FlagsImperio.desdeJson({'apuesta_max_min': {'valor': 500}}).apuestaMaxMin, 60);
      expect(FlagsImperio.desdeJson({'apuesta_max_min': {'valor': '0'}}).apuestaMaxMin, 0);
    });
    test('los minutos coinciden con el check de la base', () {
      expect(_migracion, contains('apuesta_min in (0, 15, 30, 60)'));
    });
  });

  group('cobro', () {
    test('costo = minutos × 60 × mps', () {
      expect(costoApuesta(30, 10), 18000);
      expect(costoApuesta(0, 10), 0);
      expect(costoApuesta(15, 0), 0);
    });
    test('con saldo de sobra paga completo', () {
      final c = cobroApuesta(50000, 18000);
      expect((c.mj, c.fraccion), (18000, 1.0));
      final p = _p(50000, 90000);
      aplicarCobro(p, c.mj);
      expect((p.saldo, p.mjTotal), (32000, 90000));
    });
    test('sin saldo suficiente paga lo que hay', () {
      final c = cobroApuesta(4500, 18000);
      expect((c.mj, c.fraccion), (4500, 0.25));
      final p = _p(4500, 9000);
      aplicarCobro(p, c.mj);
      expect(p.saldo, 0);
    });
    test('saldo 0 o negativo paga 0', () {
      expect(cobroApuesta(0, 18000), (mj: 0.0, fraccion: 0.0));
      expect(cobroApuesta(-5, 18000), (mj: 0.0, fraccion: 0.0));
    });
    test('el cobro nunca deja saldo negativo', () {
      final p = _p(100, 100);
      aplicarCobro(p, 500);
      expect(p.saldo, 0);
    });
  });

  group('premio', () {
    test('ganador cobra el doble de lo pagado', () {
      expect(premioApuesta(30, 1), 60);
      expect(premioApuesta(60, 0.5), 60);
      expect(premioApuesta(15, 0), 0);
      expect(premioApuesta(15, 3), 30);
    });
    test('el premio sube saldo y MJ de la vida', () {
      final p = _p(1000, 5000);
      aplicarPremio(p, costoApuesta(premioApuesta(30, 1).round(), 2));
      expect((p.saldo, p.mjTotal), (8200, 12200));
    });
  });

  group('empate y devolución', () {
    test('recupera solo lo pagado', () {
      expect(devolucionApuesta(30, 1), 30);
      expect(devolucionApuesta(60, 0.25), 15);
      expect(devolucionApuesta(15, 0), 0);
    });
    test('la devolución no toca los MJ de la vida', () {
      final p = _p(0, 20000);
      aplicarDevolucion(p, 18000);
      expect((p.saldo, p.mjTotal), (18000, 20000));
    });
    test('la devolución no pasa de los MJ de la vida', () {
      final p = _p(15000, 20000);
      aplicarDevolucion(p, 18000);
      expect(p.saldo, 20000);
    });
    test('apostar y recuperar en empate deja el saldo igual', () {
      final p = _p(50000, 90000);
      final c = cobroApuesta(p.saldo, costoApuesta(30, 10));
      aplicarCobro(p, c.mj);
      aplicarDevolucion(p, costoApuesta(1, 10) * devolucionApuesta(30, c.fraccion));
      expect(p.saldo, 50000);
    });
    test('el servidor devuelve en empate, rechazo, cancelación y anulada', () {
      expect(_migracion, contains("'devuelve'"));
      expect(_migracion, contains('apuesta_sin_pagar'));
    });
  });
}

void _apuntes() {
  group('cola de apuntes', () {
    test('ida y vuelta por JSON', () {
      const a = ApunteApuesta(TipoApunte.premio, 7, 30);
      final b = ApunteApuesta.desdeJson(a.toJson())!;
      expect((b.tipo, b.reto, b.minutos), (TipoApunte.premio, 7, 30.0));
      expect(ApunteApuesta.desdeJson({'tipo': 'otro', 'reto': 1, 'minutos': 5}), isNull);
      expect(ApunteApuesta.desdeJson({'tipo': 'cobro', 'reto': 1, 'minutos': 0}), isNull);
    });
    test('apostar, perder: solo baja el saldo', () {
      final p = _p(50000, 90000);
      final mj = aplicarApunte(p, const ApunteApuesta(TipoApunte.cobro, 1, 30), 10);
      expect((mj, p.saldo, p.mjTotal), (18000.0, 32000.0, 90000.0));
    });
    test('apostar con poco saldo y ganar: cobra el doble de lo pagado', () {
      final p = _p(4500, 9000);
      final c = cobroApuesta(p.saldo, costoApuesta(30, 10));
      aplicarApunte(p, ApunteApuesta(TipoApunte.cobro, 1, 30 * c.fraccion), 10);
      expect(p.saldo, 0);
      final mj = aplicarApunte(p, ApunteApuesta(TipoApunte.premio, 1, premioApuesta(30, c.fraccion)), 10);
      expect((mj, p.saldo, p.mjTotal), (9000.0, 9000.0, 18000.0));
    });
    test('empate: devuelve y deja todo como estaba', () {
      final p = _p(50000, 90000);
      aplicarApunte(p, const ApunteApuesta(TipoApunte.cobro, 1, 15), 10);
      final mj = aplicarApunte(p, ApunteApuesta(TipoApunte.devolucion, 1, devolucionApuesta(15, 1)), 10);
      expect((mj, p.saldo, p.mjTotal), (9000.0, 50000.0, 90000.0));
    });
    test('sin producción no mueve nada', () {
      final p = _p(100, 100);
      expect(aplicarApunte(p, const ApunteApuesta(TipoApunte.premio, 1, 30), 0), 0);
      expect(p.saldo, 100);
    });
  });
}

void _logros() {
  test('logros del premio', () {
    expect(logrosDeApunte(const ApunteApuesta(TipoApunte.devolucion, 1, 30, apuesta: 60, ganadas: 9)), isEmpty);
    expect(logrosDeApunte(const ApunteApuesta(TipoApunte.premio, 1, 30, apuesta: 15, ganadas: 1)), ['apuesta_ganada']);
    expect(logrosDeApunte(const ApunteApuesta(TipoApunte.premio, 1, 120, apuesta: 60, ganadas: 5)), ['apuesta_ganada', 'apuestas_5', 'apuesta_60']);
    for (final id in ['apuesta_ganada', 'apuestas_5', 'apuesta_60']) {
      expect(logroPorId(id), isNotNull);
    }
    final b = ApunteApuesta.desdeJson(const ApunteApuesta(TipoApunte.premio, 3, 60, apuesta: 30, ganadas: 2).toJson())!;
    expect((b.apuesta, b.ganadas), (30, 2));
  });
}
