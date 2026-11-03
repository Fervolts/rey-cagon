// Abdicar 👑 y La Corte: la cuenta de La Corte igual que en el servidor, las Coronas, lo que se va y se queda al
// abdicar, lo que hace cada nodo y la guía (Qué hago y el dedo).
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/casas.dart';
import 'package:rey_cagon/imperio/dedo.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/que_hago.dart';

int _m(int a, int b) => a < b ? a : b;

/// La misma cuenta que imperio_corte_costo (migración de abdicar), en forma cerrada.
int _costoServidor(Map<String, int> corte) {
  var total = 0;
  corte.forEach((k, v) {
    final n = v < 0 ? 0 : _m(v, 1000);
    final int c = switch (k) {
      'bufon' => _m(n, 20) + _m(n, 20) * (_m(n, 20) - 1) ~/ 2,
      'heraldo' => const [0, 2, 6, 14][_m(n, 3)],
      'tesorero' => 2 * _m(n, 5) + _m(n, 5) * (_m(n, 5) - 1),
      'maestro_obras' => _m(n, 5) + _m(n, 5) * (_m(n, 5) - 1) ~/ 2,
      'catador' => _m(n, 4) + _m(n, 4) * (_m(n, 4) - 1) ~/ 2,
      'mayordomo_real' => n >= 1 ? 6 : 0,
      _ => 0,
    };
    total += c;
  });
  return total;
}

/// En el Palacio con [llaves] Llaves ganadas en el reinado y [coronas] Coronas ganadas antes.
Imperio _rey({int llaves = 0, int coronas = 0, int mudanzas = 4}) {
  final imp = Imperio(azar: Random(1));
  imp.partida
    ..mudanzas = mudanzas
    ..llavesGanadas = llaves
    ..coronasGanadas = coronas
    ..jaladas = 40
    ..mjTotal = 1e40
    ..mjBase = 1e30
    ..mjEnCasa = 1e35
    ..rollos = 500
    ..llavero = {'cimientos': 5, 'camion_mudanza': 1};
  return imp;
}

const t0 = 1700000000000;

void main() {
  group('La Corte', () {
    test('costoCorte es la misma cuenta del servidor en cada nivel', () {
      for (final m in mejorasCorte) {
        for (var n = 0; n <= m.limite + 2; n++) {
          expect(costoCorte({m.id: n}), _costoServidor({m.id: n}), reason: '${m.id} nivel $n');
        }
      }
      final llena = {for (final m in mejorasCorte) m.id: m.limite};
      expect(costoCorte(llena), _costoServidor(llena));
      expect(costoCorte(llena), 210 + 14 + 30 + 15 + 10 + 6);
      expect(costoCorte({'no_existe': 4}), 0);
    });

    test('comprar: alcanza o no, tope por nodo y las Coronas se descuentan', () {
      final im = _rey(coronas: 3);
      expect(im.coronas, 3);
      expect(im.puedeComprarCorte('mayordomo_real'), isFalse, reason: 'cuesta 6');
      expect(im.comprarCorte('heraldo'), isTrue);
      expect(im.coronas, 1);
      expect(im.nivelCorte('heraldo'), 1);
      expect(im.comprarCorte('heraldo'), isFalse, reason: 'el nivel 2 cuesta 4');
      expect(im.comprarCorte('bufon'), isTrue);
      expect(im.coronas, 0);
      expect(im.comprarCorte('no_existe'), isFalse);

      final rico = _rey(coronas: 10000);
      for (var i = 0; i < 30; i++) {
        rico.comprarCorte('heraldo');
      }
      expect(rico.nivelCorte('heraldo'), 3);
      expect(rico.puedeComprarCorte('heraldo'), isFalse);
    });

    test('multiplicadorCorte: x1 sin abdicar, x3 por Bufón y +50% por Corona sin gastar', () {
      expect(_rey().multiplicadorCorte, 1);
      final im = _rey(coronas: 3);
      expect(im.multiplicadorCorte, closeTo(1 + 3 * im.ajustes.coronaPct, 1e-9));
      im.comprarCorte('bufon');
      expect(im.coronas, 2);
      expect(im.multiplicadorCorte, closeTo(3 * (1 + 2 * im.ajustes.coronaPct), 1e-9));
    });

    test('Maestro de obras: 1 jalada menos (mínimo 4) y 10% menos cagadas (mínimo la mitad) por nivel', () {
      final im = _rey(coronas: 1000);
      final rollos = im.rollosParaMudanza;
      expect(im.jaladasParaMudanza, 9);
      expect(im.cagadasParaMudanza, 30);
      final jaladas = <int>[];
      final cagadas = <int>[];
      for (var i = 0; i < 5; i++) {
        expect(im.comprarCorte('maestro_obras'), isTrue);
        jaladas.add(im.jaladasParaMudanza);
        cagadas.add(im.cagadasParaMudanza);
      }
      expect(jaladas, [8, 7, 6, 5, 4]);
      expect(cagadas, [27, 24, 21, 18, 15]);
      expect(im.comprarCorte('maestro_obras'), isFalse, reason: 'máximo 5');
      expect(im.rollosParaMudanza, rollos, reason: 'los Rollos no cambian');

      // puedeMudarse usa los requisitos rebajados: 4 jaladas y 15 cagadas reales en la casa.
      im.partida
        ..jaladasBase = im.partida.jaladas - 4
        ..rollos = im.rollosParaMudanza.ceil() + 1;
      expect(im.puedeMudarse(15), isTrue);
      expect(im.puedeMudarse(14), isFalse);
      im.partida.jaladasBase = im.partida.jaladas - 3;
      expect(im.puedeMudarse(1000), isFalse);
    });

    test('Mayordomo real: trae el Mayordomo del Llavero en este reinado', () {
      final im = _rey(coronas: 6);
      expect(im.nivelLlavero('mayordomo'), 0);
      expect(im.comprarCorte('mayordomo_real'), isTrue);
      expect(im.nivelLlavero('mayordomo'), 1);
      expect(descuentoLlaveroCorte(im.partida.corte, im.partida.llavero), mejorasLlavero.firstWhere((m) => m.id == 'mayordomo').precio(0));
    });
  });

  group('Abdicar', () {
    test('Coronas: 0 bajo el requisito, 3 justo en él y 6 con cuatro veces', () {
      final r = _rey().ajustes.abdicarLlaves.round();
      expect(_rey(llaves: r - 1).coronasPorGanar, 0);
      expect(_rey(llaves: r).coronasPorGanar, 3);
      expect(_rey(llaves: r * 4).coronasPorGanar, 6);
    });

    test('requisitos: mudanzas, Llaves ganadas y cagadas del reinado', () {
      final a = _rey().ajustes;
      final r = a.abdicarLlaves.round();
      expect(_rey(llaves: r).puedeAbdicar(a.abdicarCagadas), isTrue);
      expect(_rey(llaves: r).puedeAbdicar(a.abdicarCagadas - 1), isFalse);
      expect(_rey(llaves: r - 1).puedeAbdicar(a.abdicarCagadas), isFalse);
      expect(_rey(llaves: r, mudanzas: a.abdicarMudanzas - 1).puedeAbdicar(a.abdicarCagadas), isFalse);
    });

    test('se va todo lo del reinado y se quedan Coronas, Corte, logros y la historia', () {
      final r = _rey().ajustes.abdicarLlaves.round();
      final im = _rey(llaves: r);
      im.partida.logros.add('metiche');
      final total = im.mjTotal;
      final ganadas = im.abdicar(ahora: t0);
      expect(ganadas, 3);
      final p = im.partida;
      expect(p.abdicaciones, 1);
      expect(p.coronasGanadas, 3);
      expect(im.coronas, 3);
      expect(p.mudanzas, 0, reason: 'vuelve al Rancho');
      expect(p.llavesGanadas, 0);
      expect(p.llavero, isEmpty);
      expect(p.rollos, 0);
      expect(p.edificios.values.every((n) => n == 0), isTrue);
      expect(p.jaladas, 40, reason: 'las jaladas históricas se quedan');
      expect(p.jaladasBase, 40);
      expect(im.mjTotal, total);
      expect(p.logros, contains('metiche'));
      expect(p.casaEn, t0);
    });

    test('lo que manda el servidor pisa la cuenta de aquí', () {
      final im = _rey(llaves: 500);
      expect(im.abdicar(coronasServidor: 2, mudanzasServidor: 1, llavesServidor: 7, ahora: t0), 2);
      expect(im.partida.coronasGanadas, 2);
      expect(im.partida.mudanzas, 1);
      expect(im.partida.llavesGanadas, 7);
    });

    test('Heraldo, Tesorero y Mayordomo real al abdicar', () {
      final im = _rey(llaves: 200, coronas: 40);
      im.comprarCorte('heraldo');
      im.comprarCorte('heraldo');
      im.comprarCorte('tesorero');
      im.comprarCorte('tesorero');
      im.comprarCorte('mayordomo_real');
      expect(im.coronas, 40 - 6 - 6 - 6);
      im.abdicar(ahora: t0);
      final p = im.partida;
      expect(p.mudanzas, 2, reason: 'el Heraldo 2 arranca en la Quinta');
      expect(nombreCasa(p.mudanzas), nombreCasa(2));
      expect(p.llavesGanadas, 40, reason: 'el Tesorero 2 guarda el 20% de 200');
      expect(p.llavero, {'mayordomo': 1});
      expect(im.nivelCorte('heraldo'), 2, reason: 'La Corte se queda');
    });

    test('abdicar sin gastar Llaves en el Llavero cuenta para el logro avaro', () {
      final im = _rey(llaves: 200);
      im.partida.llavero = {};
      im.abdicar(ahora: t0);
      expect(im.partida.abdicacionesAvaras, 1);
      final otra = _rey(llaves: 200);
      otra.abdicar(ahora: t0);
      expect(otra.partida.abdicacionesAvaras, 0);
    });

    test('Dinastía: nada sin abdicar, II después de la primera', () {
      expect(dinastia(0), '');
      expect(dinastia(1), endsWith(' II'));
      expect(dinastia(3), endsWith(' IV'));
      expect(conDinastia('Rancho', 0), 'Rancho');
      expect(conDinastia('Rancho', 1), 'Rancho · ${dinastia(1)}');
    });
  });

  group('Guía', () {
    test('Qué hago: abdicar va antes que mudarse; luego La Corte si alcanzan las Coronas', () {
      final r = _rey().ajustes.abdicarLlaves.round();
      final im = _rey(llaves: r);
      expect(queHagoAhora(im, t0, mudanzaLista: true, abdicarLista: true).id, 'abdicar');
      expect(queHagoAhora(im, t0, mudanzaLista: true).id, 'mudanza');
      im.abdicar(ahora: t0);
      im.partida.coronasGanadas = 1;
      final s = queHagoAhora(im, t0);
      expect(s.id, 'corte');
      expect(s.ir, DestinoQueHago.abdicar);
      expect(s.objetivo, 'maestro_obras');
      im.comprarCorte('maestro_obras');
      expect(corteConviene(im), isNull);
      expect(queHagoAhora(im, t0).id, isNot('corte'));
    });

    test('dedo: ABDICAR una sola vez, en la primera dinastía', () {
      final im = _rey(llaves: 200);
      im.partida.guiaVista.add(claveDedo('mudanza'));
      expect(siguienteDedo(im, t0, cajonAbierto: false), isNull);
      final d = siguienteDedo(im, t0, cajonAbierto: false, mudanza: true, abdicar: true);
      expect(d?.paso, 'abdicar');
      expect(d?.objetivo, const Key('boton_abdicar'));
      im.partida.guiaVista.add(claveDedo('abdicar'));
      expect(siguienteDedo(im, t0, cajonAbierto: false, abdicar: true), isNull);
      final otra = _rey(llaves: 200)..partida.abdicaciones = 1;
      expect(siguienteDedo(otra, t0, cajonAbierto: false, abdicar: true), isNull);
    });
  });
}
