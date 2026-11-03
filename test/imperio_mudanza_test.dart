// Mudanza 🏠 y Llavero 🔑: la cuenta del Llavero igual que en el servidor, las Llaves y lo que se va y se queda al mudarse.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/casas.dart';
import 'package:rey_cagon/imperio/motor.dart';

int _m(int a, int b) => a < b ? a : b;

/// La misma cuenta que imperio_llavero_costo (migración de la mudanza), en forma cerrada.
int _costoServidor(Map<String, int> llavero) {
  var total = 0;
  llavero.forEach((k, v) {
    final n = v < 0 ? 0 : _m(v, 1000);
    final int c = switch (k) {
      'cimientos' => _m(n, 20) + _m(n, 20) * (_m(n, 20) - 1) ~/ 2,
      'mayordomo' => const [0, 3, 8, 16][_m(n, 3)],
      'camion_mudanza' => 2 * _m(n, 5) + _m(n, 5) * (_m(n, 5) - 1),
      'ahorros' => _m(n, 10) + _m(n, 10) * (_m(n, 10) - 1) ~/ 2,
      'primo_extra' => const [0, 4, 12][_m(n, 2)],
      'alquiler_barato' => 2 * _m(n, 5) + _m(n, 5) * (_m(n, 5) - 1) ~/ 2,
      _ => 0,
    };
    total += c;
  });
  return total;
}

/// Una partida lista para mudarse de la casa [mudanzas] con [rollos] ganados en ella.
Imperio _lista({int mudanzas = 0, int rollos = 0, int gastados = 0}) {
  final imp = Imperio(azar: Random(1));
  final p = imp.partida;
  p
    ..mudanzas = mudanzas
    ..jaladas = 20
    ..jaladasBase = 20 - imp.ajustes.mudanzaJaladas
    ..rollos = rollos - gastados
    ..rollosGastados = gastados
    ..mjTotal = 1e30
    ..mjBase = 1e20
    ..mjEnCasa = 1e30;
  return imp;
}

void main() {
  test('el costo del Llavero es el mismo que en el servidor, nivel por nivel', () {
    for (final m in mejorasLlavero) {
      for (var n = 0; n <= m.limite + 3; n++) {
        expect(costoLlavero({m.id: n}), _costoServidor({m.id: n}), reason: '${m.id} nivel $n');
      }
    }
    final todo = {for (final m in mejorasLlavero) m.id: m.limite};
    expect(costoLlavero(todo), 343);
    expect(_costoServidor(todo), 343);
    expect(costoLlavero({'cimientos': 1}), 1);
    expect(costoLlavero({'mayordomo': 2}), 8);
    expect(costoLlavero({'camion_mudanza': 2}), 6);
    expect(costoLlavero({'alquiler_barato': 3}), 9);
    expect(costoLlavero({'no_existe': 5, 'cimientos': -2}), 0);
  });

  test('las Llaves salen de los rollos de la casa y no antes del requisito', () {
    final r = Imperio(azar: Random(1)).rollosParaMudanza.round();
    expect(_lista(rollos: r - 1).llavesPorGanar, 0);
    expect(_lista(rollos: r).llavesPorGanar, 3);
    expect(_lista(rollos: r * 8).llavesPorGanar, 6);
    expect(_lista(rollos: r * 27).llavesPorGanar, 9);
    // Lo gastado en la Plomería cuenta igual.
    expect(_lista(rollos: r * 8, gastados: r * 7).llavesPorGanar, 6);
    // La segunda casa pide 30 veces más.
    expect(_lista(mudanzas: 1, rollos: r).llavesPorGanar, 0);
    expect(_lista(mudanzas: 1, rollos: r * 30).llavesPorGanar, 3);
  });

  test('para mudarse hacen falta rollos, jaladas y cagadas de la casa', () {
    final imp = Imperio(azar: Random(1));
    final r = imp.rollosParaMudanza.round();
    final cag = imp.ajustes.mudanzaCagadas;
    expect(_lista(rollos: r).puedeMudarse(cag), isTrue);
    expect(_lista(rollos: r).puedeMudarse(cag - 1), isFalse);
    expect(_lista(rollos: r - 1).puedeMudarse(cag), isFalse);
    final pocas = _lista(rollos: r)..partida.jaladasBase += 1;
    expect(pocas.puedeMudarse(cag), isFalse);
  });

  test('mudarse se lleva la corrida, los Rollos y la Plomería, y deja las Llaves', () {
    final r = Imperio(azar: Random(1)).rollosParaMudanza.round();
    final imp = _lista(rollos: r * 8, gastados: 100);
    imp.partida
      ..edificios = {'dedo': 50, 'agujero': 3}
      ..objetosRollos = {'tuberia_ancha': 25, 'llave_paso': 9, 'cadena_reserva': 1}
      ..llavero = {'camion_mudanza': 1};
    imp.partida.llavesGanadas = 2;
    final jaladas = imp.partida.jaladas;
    final mj = imp.mjTotal;
    final ganadas = imp.mudarse();
    final p = imp.partida;
    expect(ganadas, 6);
    expect(p.mudanzas, 1);
    expect(p.llavesGanadas, 8);
    expect(imp.llaves, 6);
    expect(p.rollos, 0);
    expect(p.rollosGastados, 0);
    expect(p.jaladas, jaladas);
    expect(p.jaladasCasa, 0);
    expect(p.mjBase, mj);
    expect(p.mjEnCasa, 0);
    expect(p.mjCasa, 0);
    expect(p.edificios['agujero'] ?? 0, 0);
    // El Camión de mudanza nivel 1 se lleva el 10% (piso); la Cadena de reserva no viaja.
    expect(p.objetosRollos, {'tuberia_ancha': 2});
    expect(p.mudanzasLimpias, 0);
    expect(imp.puedeMudarse(1000), isFalse);
  });

  test('los MJ de la casa se cuentan aparte aunque el total sea enorme', () {
    final imp = Imperio(azar: Random(1));
    imp.partida
      ..mudanzas = 2
      ..mjTotal = 1e34
      ..mjBase = 1e34
      ..edificios = {'ciruela': 10};
    for (var k = 0; k < 10; k++) {
      imp.tick(1000 * (k + 1), 1);
    }
    // 1e34 + unos MJ sigue siendo 1e34 en double: la resta daría 0, la cuenta aparte no.
    expect(imp.partida.mjTotal - imp.partida.mjBase, 0);
    expect(imp.partida.mjCasa, greaterThan(0));
    // Y viaja en el guardado.
    final copia = Partida.desdeJson(imp.partida.toJson());
    expect(copia.mjCasa, imp.partida.mjCasa);
    // En el Rancho la casa son todos los MJ (como en la app 63).
    final rancho = Imperio(azar: Random(1))..partida.mjTotal = 500;
    expect(rancho.partida.mjCasa, 500);
    expect(rancho.partida.toJson().containsKey('mj_casa'), isFalse);
  });

  test('en cada casa los MJ rinden menos Rollos (divisor ^ mudanzas) y cada Rollo vale por 1 + mudanzas', () {
    final imp = Imperio(azar: Random(1));
    final d = imp.ajustes.mudanzaDivisorX;
    imp.partida
      ..mjTotal = 1e30
      ..mjEnCasa = 1e30;
    expect(imp.rollosTotales, rollosPorMj(1e30, imp.ajustes));
    imp.partida.mudanzas = 2;
    expect(imp.rollosTotales, rollosPorMj(1e30 / (d * d), imp.ajustes) * 3);
    // El siguiente Rollo pide los MJ de la casa con el mismo divisor.
    final meta = mjParaRollos(rollosPorMj(1e30 / (d * d), imp.ajustes) + 1, imp.ajustes) * d * d;
    expect(imp.mjParaSiguienteRollo + imp.partida.mjCasa, closeTo(meta, meta * 1e-9));
  });

  test('comprar en el Llavero gasta Llaves y respeta el máximo', () {
    final imp = Imperio(azar: Random(1))..partida.llavesGanadas = 4;
    expect(imp.comprarLlavero('mayordomo'), isTrue);
    expect(imp.llaves, 1);
    expect(imp.comprarLlavero('mayordomo'), isFalse);
    expect(imp.comprarLlavero('cimientos'), isTrue);
    expect(imp.llaves, 0);
    expect(imp.comprarLlavero('no_existe'), isFalse);
    imp.partida.llavesGanadas = 1000;
    for (var k = 0; k < 30; k++) {
      imp.comprarLlavero('cimientos');
    }
    expect(imp.nivelLlavero('cimientos'), 20);
  });

  test('casas: producción y rollos por jalada', () {
    expect([for (var m = 0; m < 7; m++) multiplicadorCasa(m)], [1, 3, 10, 40, 200, 600, 1800]);
    expect([for (var m = 0; m < 4; m++) factorRollosCasa(m)], [1, 2, 3, 4]);
    expect(nombreCasa(0), 'Rancho');
    expect(nombreCasa(4), 'Palacio');
    expect(nombreCasa(5), 'Palacio II');
  });
}
