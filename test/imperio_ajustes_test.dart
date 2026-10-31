import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/flags.dart';
import 'package:rey_cagon/imperio/motor.dart';

/// Azar que siempre devuelve lo mismo, para forzar resultados.
class _AzarFijo implements Random {
  double d;
  _AzarFijo({this.d = 0.5});
  @override
  double nextDouble() => d;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

const int t0 = 1800000000000;
const int seg = 1000;
const int hora = 3600 * seg;

int _primerDorado(Imperio imp) {
  imp.tick(t0, 1); // programa
  for (var s = 1; s <= 4000; s++) {
    imp.tick(t0 + s * seg, 1);
    if (imp.dorado(t0 + s * seg) != null) return s;
  }
  return -1;
}

void main() {
  group('Ajustes del motor', () {
    test('por defecto son los números de siempre', () {
      const a = Ajustes.porDefecto;
      expect([a.doradoMinMin, a.doradoMaxMin, a.offlinePorcentaje, a.offlineTopeH], [5, 15, 0.25, 2]);
      expect([a.precioCrecimiento, a.precioGuantes, a.precioFaja, a.cagadaBonoPct], [1.15, 100, 500, 2]);
    });

    test('intervalo del dorado', () {
      const a = Ajustes(doradoMinMin: 1, doradoMaxMin: 3);
      expect(_primerDorado(Imperio(azar: _AzarFijo(d: 0), ajustes: a)), 60);
      expect(_primerDorado(Imperio(azar: _AzarFijo(d: 0.999), ajustes: a)), inInclusiveRange(179, 180));
      final iman = Imperio(azar: _AzarFijo(d: 0), partida: Partida(mejoras: {'iman'}), ajustes: a);
      expect(_primerDorado(iman), 30);
    });

    test('offline: base de porcentaje y tope; tanques y válvulas no bajan de la base', () {
      final imp = Imperio(ajustes: const Ajustes(offlinePorcentaje: 0.6, offlineTopeH: 5));
      imp.partida.edificios['ciruela'] = 10; // 10 MJ/s
      var r = imp.aplicarOffline(t0, t0 + 10 * hora);
      expect(r.segundosContados, 5 * 3600);
      expect(r.ganado, closeTo(5 * 3600 * 10 * 0.6, 1e-6));
      imp.partida.mejoras.addAll({'tanque_4', 'valvula_50'}); // 4 h y 50%: menos que la base
      expect(imp.topeOffline, const Duration(hours: 5));
      expect(imp.porcentajeOffline, 0.6);
      imp.partida.mejoras.addAll({'tanque_8', 'valvula_75'});
      expect(imp.topeOffline, const Duration(hours: 8));
      expect(imp.porcentajeOffline, 0.75);
      r = imp.aplicarOffline(t0, t0 + 20 * hora);
      expect(r.ganado, closeTo(8 * 3600 * 10 * 0.75, 1e-6));
    });

    test('crecimiento de precio de edificios', () {
      final imp = Imperio(ajustes: const Ajustes(precioCrecimiento: 1.5));
      imp.partida.edificios['dedo'] = 2;
      expect(imp.precioEdificio('dedo', t0), (15 * 2.25).ceilToDouble());
      expect(imp.precioEdificioVarios('dedo', 2, t0), (15 * 2.25).ceilToDouble() + (15 * 3.375).ceilToDouble());
      imp.partida.saldo = 34 + 51;
      expect(imp.maxComprable('dedo', t0), 2);
      expect(Imperio().precioEdificio('dedo', t0), 15);
    });

    test('precio de Guantes y Faja', () {
      final imp = Imperio(partida: Partida(saldo: 60, mjTotal: 60), ajustes: const Ajustes(precioGuantes: 50, precioFaja: 40));
      imp.partida.edificios['dedo'] = 1;
      expect(imp.precioMejora(mejoraPorId('guantes')!), 50);
      expect(imp.precioMejora(mejoraPorId('dedo_1')!), mejoraPorId('dedo_1')!.precio);
      expect(imp.mejorasDisponibles().take(2).map((m) => m.id), ['faja', 'guantes']);
      expect(imp.comprarMejora('guantes'), isTrue);
      expect(imp.saldo, 10);
      expect(imp.comprarMejora('faja'), isFalse);
    });

    test('bono por cagada: +X% hasta 150, luego +0,5% cada una', () {
      const a = Ajustes(cagadaBonoPct: 3);
      expect(Imperio(cagadas: 10, ajustes: a).multiplicadorCagadas, closeTo(1.3, 1e-9));
      expect(Imperio(cagadas: 150, ajustes: a).multiplicadorCagadas, closeTo(5.5, 1e-9));
      expect(Imperio(cagadas: 250, ajustes: a).multiplicadorCagadas, closeTo(6.0, 1e-9));
      expect(multiplicadorPorCagadas(150), closeTo(4.0, 1e-9));
    });

    test('los ajustes pasan por desdeJson', () {
      final imp = Imperio.desdeJson(null, ajustes: const Ajustes(precioCrecimiento: 2));
      imp.partida.edificios['dedo'] = 1;
      expect(imp.precioEdificio('dedo', t0), 30);
    });
  });

  group('segPartida', () {
    test('solo suma el tiempo activo del tick, no el offline', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 1;
      imp.tick(t0, 0.5);
      imp.tick(t0 + seg, 5); // se recorta a 1
      expect(imp.partida.segPartida, closeTo(1.5, 1e-9));
      imp.aplicarOffline(t0 + seg, t0 + 3 * hora);
      expect(imp.partida.segPartida, closeTo(1.5, 1e-9));
    });

    test('JSON: ida y vuelta, y partidas viejas arrancan en 0', () {
      expect(Partida.desdeJson({'saldo': 5}).segPartida, 0);
      expect(Partida.desdeJson({'seg_partida': -3}).segPartida, 0);
      final p = Partida(segPartida: 123.5);
      expect(Partida.desdeJson(p.toJson()).segPartida, 123.5);
    });
  });

  group('ContadorSesion', () {
    test('cuenta tiempo, pujos y compras; lo ganado no baja de 0', () {
      final c = ContadorSesion(1000)
        ..sumarTiempo(0.4)
        ..sumarTiempo(double.nan)
        ..sumarTiempo(-1)
        ..sumarTiempo(1.2);
      c.pujos += 3;
      c.compras++;
      expect(c.fin(1500), {'segundos': 2, 'pujos': 3, 'mj_ganados': 500.0, 'compras': 1});
      expect(c.fin(900)['mj_ganados'], 0.0);
    });
  });

  test('FlagsImperio.ajustes copia los números', () {
    expect(FlagsImperio.porDefecto.ajustes.precioCrecimiento, Ajustes.porDefecto.precioCrecimiento);
    final a = FlagsImperio.desdeJson({
      'dorado_intervalo_min': {'valor': [2, 8]},
      'precio_faja': {'valor': 700},
    }).ajustes;
    expect([a.doradoMinMin, a.doradoMaxMin, a.precioFaja, a.precioGuantes], [2, 8, 700, 100]);
  });
}
