// Imperio fase 2 (carril A): Maná, habilidades, alquileres, consumibles nuevos y objetos de Rollos.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
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
const int min_ = 60 * seg;
const int hora = 60 * min_;

/// Imperio con 15 cagadas (Maná y consumibles nuevos abiertos), algo de producción y saldo de sobra.
Imperio _imperio({int cagadas = 15, double d = 0.5}) {
  final imp = Imperio(cagadas: cagadas, azar: _AzarFijo(d: d));
  imp.partida
    ..edificios['ciruela'] = 10
    ..edificios['cafe'] = 5
    ..saldo = 1e12;
  return imp;
}

void main() {
  group('Maná de Tripa', () {
    test('se abre a las 15 cagadas y arranca lleno', () {
      expect(Imperio(cagadas: 14).manaAbierto, isFalse);
      final imp = _imperio();
      expect(imp.manaAbierto, isTrue);
      expect(imp.mana(t0), manaMax);
      expect(Imperio(cagadas: 14).puedeUsarHabilidad('jalon_doble', t0), isFalse);
    });

    test('gastar 20 deja 80; se llena 50 en 30 min con tope 100; una cagada real lo llena', () {
      final imp = _imperio();
      expect(imp.usarHabilidad('jalon_doble', t0), isNotNull);
      expect(imp.mana(t0), closeTo(80, 1e-9));
      expect(imp.mana(t0 + 30 * min_), closeTo(100, 1e-9)); // 80 + 50, tope 100
      expect(imp.usarHabilidad('pujo_sagrado', t0), isNotNull);
      expect(imp.mana(t0), closeTo(50, 1e-9));
      expect(imp.mana(t0 + 30 * min_), closeTo(100, 1e-9));
      expect(imp.mana(t0 + 15 * min_), closeTo(75, 1e-9));
      imp.aplicarCagadas([DateTime.fromMillisecondsSinceEpoch(t0)].map((c) => CagadaReal(creada: c)).toList(), t0);
      expect(imp.mana(t0), manaMax);
    });

    test('sin Maná suficiente no se puede', () {
      final imp = _imperio();
      imp.partida
        ..mana = 10
        ..manaEn = t0;
      expect(imp.puedeUsarHabilidad('jalon_doble', t0), isFalse);
      expect(imp.usarHabilidad('jalon_doble', t0), isNull);
    });
  });

  group('habilidades', () {
    test('Jalón doble: producción x2 por 60 s y luego espera 1 h', () {
      final imp = _imperio();
      final antes = imp.mps(t0);
      imp.usarHabilidad('jalon_doble', t0);
      expect(imp.mps(t0 + seg), closeTo(antes * 2, antes * 1e-9));
      expect(imp.mps(t0 + 61 * seg), closeTo(antes, antes * 1e-9));
      expect(imp.esperaHabilidad('jalon_doble', t0), const Duration(hours: 1));
      expect(imp.puedeUsarHabilidad('jalon_doble', t0 + 30 * min_), isFalse);
      expect(imp.puedeUsarHabilidad('jalon_doble', t0 + hora), isTrue);
      expect(imp.partida.habilidades, 1);
    });

    test('Corre corre pide un Atasco y lo destapa', () {
      final imp = _imperio();
      expect(imp.puedeUsarHabilidad('corre_corre', t0), isFalse);
      imp.partida.atasco = Atasco('ciruela', t0);
      expect(imp.usarHabilidad('corre_corre', t0), isNotNull);
      expect(imp.partida.atasco, isNull);
      expect(imp.partida.destapes, 1);
    });

    test('Pujo sagrado: pujos x10 por 20 s', () {
      final imp = _imperio();
      final antes = imp.valorPujo(t0);
      imp.usarHabilidad('pujo_sagrado', t0);
      expect(imp.valorPujo(t0 + seg), closeTo(antes * 10, antes * 1e-9));
      expect(imp.valorPujo(t0 + 21 * seg), closeTo(antes, antes * 1e-9));
    });

    test('Chorro a presión: gana 15 min de producción', () {
      final imp = _imperio(d: 0.9);
      final m = imp.mpsSinEfectos(contarAtasco: false);
      final antes = imp.partida.saldo;
      final r = imp.usarHabilidad('chorro', t0)!;
      expect(r.fallo, isFalse);
      expect(r.mj, closeTo(900 * m, 1e-6));
      expect(imp.partida.saldo, closeTo(antes + 900 * m, 1e-3));
      expect(imp.esperaHabilidad('chorro', t0), const Duration(hours: 4));
    });

    test('Chorro a presión que falla: pierde 5 min (sin pasar de lo que tienes)', () {
      final imp = _imperio(d: 0.1);
      final m = imp.mpsSinEfectos(contarAtasco: false);
      imp.partida.saldo = 1000 * m;
      final r = imp.usarHabilidad('chorro', t0)!;
      expect(r.fallo, isTrue);
      expect(r.mj, closeTo(-300 * m, 1e-6));
      expect(imp.partida.saldo, closeTo(700 * m, 1e-6));
      expect(imp.partida.chorrosFallidos, 1);

      final pobre = _imperio(d: 0.1);
      pobre.partida.saldo = 10;
      final r2 = pobre.usarHabilidad('chorro', t0)!;
      expect(r2.mj, -10);
      expect(pobre.partida.saldo, 0);
    });

    test('Aguanta alarga 10% lo que les queda a efectos y alquilados con duración', () {
      final imp = _imperio();
      imp.partida.efectos['pino'] = t0 + 10 * min_;
      imp.partida.efectos['viejo'] = t0 - seg; // ya vencido: no cambia
      imp.partida.alquilados['primo'] = t0 + 20 * min_;
      imp.partida.alquilados['guardia'] = t0; // sin duración: no cambia
      expect(imp.usarHabilidad('aguanta', t0), isNotNull);
      expect(imp.partida.efectos['pino'], t0 + 11 * min_);
      expect(imp.partida.efectos['viejo'], t0 - seg);
      expect(imp.partida.alquilados['primo'], t0 + 22 * min_);
      expect(imp.partida.alquilados['guardia'], t0);
    });
  });

  test('los efectos de producción suman con tope x4', () {
    final imp = _imperio();
    for (final id in ['cagada_fresca', 'ambientador', 'pino', 'abuela', 'greca', 'reina_pepiada', 'jalon_doble', 'plomero_bono']) {
      imp.partida.efectos[id] = t0 + hora;
    }
    expect(imp.multiplicadorProduccionTemporal(t0), topeEfectos);
    expect(imp.multiplicadorProduccionTemporal(t0), lessThanOrEqualTo(4));
  });

  group('alquileres', () {
    test('el Robot se apila: 30 min + 30 min = 1 h; no pasa de 10 duraciones', () {
      final imp = _imperio();
      imp.partida.vioPrimerAtasco = true;
      imp.partida.saldo = 1e12;
      expect(imp.comprarObjeto('robot', t0), isTrue);
      expect(imp.partida.alquilados['robot'], t0 + 30 * min_);
      expect(imp.robotActivo(t0 + 10 * min_), isTrue);
      expect(imp.comprarObjeto('robot', t0), isTrue);
      expect(imp.partida.alquilados['robot'], t0 + 60 * min_);
      expect(imp.comprarObjeto('robot', t0, veces: 8), isTrue);
      expect(imp.partida.alquilados['robot'], t0 + 300 * min_);
      // Ya está en 10 duraciones desde ahora: no cabe más.
      expect(imp.puedeComprarObjeto('robot', t0), isFalse);
      expect(imp.comprarObjeto('robot', t0), isFalse);
      // Más tarde vuelve a caber, pero nunca más de 10 duraciones desde ese momento.
      expect(imp.comprarObjeto('robot', t0 + 30 * min_), isTrue);
      expect(imp.partida.alquilados['robot'], t0 + 330 * min_);
      expect(imp.partida.alquiladosUsados, contains('robot'));
    });

    test('Robot Turbo y Guardia piden 30 cagadas', () {
      final imp = _imperio(cagadas: 29);
      imp.partida.vioPrimerAtasco = true;
      expect(imp.objetoAbierto('robot_turbo'), isFalse);
      expect(imp.objetoAbierto('guardia'), isFalse);
      expect(imp.objetoAbierto('primo'), isTrue);
      final imp30 = _imperio(cagadas: 30)..partida.vioPrimerAtasco = true;
      expect(imp30.objetoAbierto('robot_turbo'), isTrue);
      expect(imp30.objetoAbierto('guardia'), isTrue);
    });

    test('Guardia nocturno: el próximo offline cuenta al 100% hasta 8 h y se gasta', () {
      final imp = _imperio(cagadas: 30);
      expect(imp.comprarObjeto('guardia', t0), isTrue);
      expect(imp.alquiladoActivo('guardia', t0 + 5 * hora), isTrue);
      final m = imp.mpsSinEfectos(contarAtasco: false);
      final r = imp.aplicarOffline(t0, t0 + 10 * hora);
      expect(r.conGuardia, isTrue);
      expect(r.segundosContados, 8 * 3600);
      expect(r.ganado, closeTo(8 * 3600 * m, 1e-3));
      expect(imp.partida.alquilados.containsKey('guardia'), isFalse);
      // El siguiente offline ya es el normal.
      final r2 = imp.aplicarOffline(t0 + 10 * hora, t0 + 20 * hora);
      expect(r2.conGuardia, isFalse);
      expect(r2.segundosContados, imp.topeOffline.inSeconds);
    });

    test('partida vieja con robot_hasta pasa al mapa de alquilados', () {
      final p = Partida.desdeJson({'v': 1, 'robot_hasta': t0 + 5 * min_});
      expect(p.robotHasta, t0 + 5 * min_);
      expect(p.alquilados['robot'], t0 + 5 * min_);
      expect(Imperio(partida: p).robotActivo(t0), isTrue);
    });
  });

  group('consumibles nuevos', () {
    test('Pintura marrón: +10% a un edificio, 1 por edificio; no se usa con usarObjeto', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('pintura', t0), isTrue);
      expect(imp.comprarObjeto('pintura', t0), isTrue);
      expect(imp.usarObjeto('pintura', t0), isFalse);
      final antes = imp.mpsEdificio('ciruela', t0);
      expect(imp.edificiosParaPintura(), containsAll(['ciruela', 'cafe']));
      expect(imp.usarPintura('ciruela', t0), isTrue);
      expect(imp.mpsEdificio('ciruela', t0), closeTo(antes * 1.1, antes * 1e-9));
      expect(imp.edificiosParaPintura(), isNot(contains('ciruela')));
      expect(imp.usarPintura('ciruela', t0), isFalse);
      expect(imp.usarPintura('dedo', t0), isFalse); // no produce
      expect(imp.enInventario('pintura'), 1);
      expect(imp.partida.consumiblesUsados, 1);
    });

    test('jalar borra la Pintura y los alquilados pero no las esperas de habilidades', () {
      final imp = _imperio();
      imp.comprarObjeto('pintura', t0);
      imp.usarPintura('ciruela', t0);
      imp.comprarObjeto('primo', t0);
      imp.usarHabilidad('jalon_doble', t0);
      imp.jalar();
      expect(imp.pintados, isEmpty);
      expect(imp.partida.alquilados, isEmpty);
      expect(imp.esperaHabilidad('jalon_doble', t0), isNotNull);
      expect(imp.partida.esperas.containsKey('primo'), isFalse);
    });

    test('Destapacaños pide un Atasco', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('destapacanos', t0), isTrue);
      expect(imp.usarObjeto('destapacanos', t0), isFalse);
      imp.partida.atasco = Atasco('cafe', t0);
      expect(imp.usarObjeto('destapacanos', t0), isTrue);
      expect(imp.partida.atasco, isNull);
      expect(imp.partida.destapes, 1);
      expect(imp.enInventario('destapacanos'), 0);
    });

    test('Ambientador de pino: +50% de producción por 15 min', () {
      final imp = _imperio();
      final antes = imp.mps(t0);
      imp.comprarObjeto('pino', t0);
      expect(imp.usarObjeto('pino', t0), isTrue);
      expect(imp.mps(t0 + seg), closeTo(antes * 1.5, antes * 1e-9));
      expect(imp.mps(t0 + 16 * min_), closeTo(antes, antes * 1e-9));
    });
  });

  group('objetos de Rollos de Oro', () {
    test('salen después de la primera jalada y bajan los rollos sin tocar los ganados', () {
      final imp = _imperio();
      imp.partida.rollos = 20;
      expect(imp.objetosRollosAbiertos, isFalse);
      expect(imp.comprarObjetoRollos('tanque_lujo', t0), isFalse);
      imp.partida.jaladas = 1;
      final ganados = imp.partida.rollosGanados;
      final tope = imp.topeOffline;
      expect(imp.comprarObjetoRollos('tanque_lujo', t0), isTrue);
      expect(imp.partida.rollos, 15);
      expect(imp.partida.rollosGastados, 5);
      expect(imp.partida.rollosGanados, ganados);
      expect(imp.topeOffline, tope + const Duration(hours: 1));
      expect(imp.comprarObjetoRollos('super_plomero', t0), isTrue);
      expect(imp.comprarObjetoRollos('super_plomero', t0), isFalse); // límite 1
      expect(imp.partida.rollos, 10);
    });

    test('Cadena de reserva: 1 por semana; la jalada devuelve 1 de cada edificio', () {
      final imp = _imperio();
      imp.partida
        ..rollos = 10
        ..jaladas = 1;
      expect(imp.comprarObjetoRollos('cadena_reserva', t0), isTrue);
      expect(imp.esperaCadena(t0), const Duration(days: 7));
      expect(imp.comprarObjetoRollos('cadena_reserva', t0), isFalse);
      imp.jalar();
      expect(imp.partida.edificios, {'ciruela': 1, 'cafe': 1});
      expect(imp.tieneObjetoRollos('cadena_reserva'), 0);
      // Sigue la espera de la semana aunque ya se gastó.
      expect(imp.puedeComprarObjetoRollos('cadena_reserva', t0 + 6 * 24 * hora), isFalse);
      expect(imp.puedeComprarObjetoRollos('cadena_reserva', t0 + 7 * 24 * hora), isTrue);
      // Sin Cadena, la jalada no devuelve nada.
      imp.jalar();
      expect(imp.partida.edificios, isEmpty);
    });

    test('Súper Plomero: 1 h de producción una vez por día real', () {
      final imp = _imperio();
      imp.partida
        ..rollos = 10
        ..jaladas = 1;
      imp.comprarObjetoRollos('super_plomero', t0);
      final m = imp.mpsSinEfectos(contarAtasco: false);
      final antes = imp.partida.saldo;
      imp.tick(t0, 0);
      expect(imp.partida.saldo, closeTo(antes + 3600 * m, 1e-3));
      final regalo = imp.tomarRegaloPlomero();
      expect(regalo, closeTo(3600 * m, 1e-6));
      expect(imp.tomarRegaloPlomero(), 0);
      imp.tick(t0 + min_, 0);
      expect(imp.tomarRegaloPlomero(), 0); // mismo día
      imp.tick(t0 + 24 * hora, 0);
      expect(imp.tomarRegaloPlomero(), greaterThan(0)); // otro día
    });
  });
}
