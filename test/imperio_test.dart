import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

/// Azar que siempre devuelve lo mismo, para forzar resultados.
class _AzarFijo implements Random {
  double d;
  int i;
  _AzarFijo({this.d = 0.5, this.i = 0});
  @override
  double nextDouble() => d;
  @override
  int nextInt(int max) => i % max;
  @override
  bool nextBool() => false;
}

const int t0 = 1800000000000;
const int seg = 1000;
const int min_ = 60 * seg;
const int hora = 60 * min_;

void main() {
  group('precios de edificios', () {
    test('base x 1,15^n redondeado hacia arriba', () {
      final imp = Imperio();
      expect(imp.precioEdificio('dedo', t0), 15);
      imp.partida.edificios['dedo'] = 1;
      expect(imp.precioEdificio('dedo', t0), 18); // 17,25
      imp.partida.edificios['dedo'] = 10;
      expect(imp.precioEdificio('dedo', t0), 61); // 60,68
      imp.partida.edificios.remove('dedo');
      expect(imp.precioEdificioVarios('dedo', 2, t0), 15 + 18);
      expect(imp.precioEdificio('cafe', t0), 1100);
    });

    test('tipo 3 baja 10% y el Constructor 50%', () {
      final imp = Imperio();
      imp.partida.tipoBuff = 3;
      imp.partida.tipoBuffHasta = t0 + hora;
      expect(imp.precioEdificio('dedo', t0), 14); // 13,5
      imp.partida.efectos['constructor'] = t0 + 30 * seg;
      expect(imp.precioEdificio('dedo', t0), 7); // 15 x 0,9 x 0,5 = 6,75
      expect(imp.precioEdificio('dedo', t0 + hora + 1), 15);
    });

    test('comprar descuenta el saldo y sube la cantidad', () {
      final imp = Imperio(partida: Partida(saldo: 40, mjTotal: 40));
      expect(imp.comprarEdificio('dedo', t0), isTrue);
      expect(imp.cantidad('dedo'), 1);
      expect(imp.saldo, 25);
      expect(imp.comprarEdificio('dedo', t0), isTrue);
      expect(imp.saldo, 7);
      expect(imp.comprarEdificio('dedo', t0), isFalse);
      expect(imp.cantidad('dedo'), 2);
      expect(imp.comprarEdificio('cloaca', t0), isFalse);
    });

    test('maxComprable y comprar varios', () {
      final imp = Imperio(partida: Partida(saldo: 50, mjTotal: 50));
      expect(imp.maxComprable('dedo', t0), 2); // 15 + 18 = 33; +21 = 54
      expect(imp.comprarEdificioVarios('dedo', 2, t0), isTrue);
      expect(imp.saldo, 17);
    });

    test('misterioso hasta ganar la mitad del precio base', () {
      final imp = Imperio(partida: Partida(mjTotal: 549));
      expect(imp.edificioMisterioso('cafe'), isTrue);
      imp.partida.mjTotal = 550;
      expect(imp.edificioMisterioso('cafe'), isFalse);
      expect(imp.edificioVisible('cafe'), isTrue);
      expect(imp.edificioVisible('cloaca'), isFalse);
    });
  });

  group('mejoras', () {
    test('mejora de edificio produce x2', () {
      final imp = Imperio(partida: Partida(saldo: 1e6, mjTotal: 1e6));
      imp.partida.edificios['ciruela'] = 2;
      expect(imp.mpsEdificio('ciruela', t0), 2);
      expect(imp.mejorasDisponibles().map((m) => m.id), contains('ciruela_1'));
      expect(imp.comprarMejora('ciruela_1'), isTrue);
      expect(imp.saldo, 1e6 - 1000);
      expect(imp.mpsEdificio('ciruela', t0), 4);
      expect(imp.comprarMejora('ciruela_1'), isFalse);
      expect(imp.comprarMejora('ciruela_5'), isFalse); // pide 5
    });

    test('disponibles ordenadas por precio y con el edificio abierto', () {
      final imp = Imperio();
      imp.partida.edificios.addAll({'dedo': 1, 'cafe': 1, 'inodoro': 1});
      final ids = imp.mejorasDisponibles().map((m) => m.id).toList();
      expect(ids, ['guantes', 'dedo_1', 'faja', 'cafe_1', 'tanque_4']); // inodoro_1 no: candado de 3 cagadas
      imp.cagadas = 3;
      expect(imp.mejorasDisponibles().map((m) => m.id), contains('inodoro_1'));
    });

    test('mejoras de clic: x2 y % de MJ/s', () {
      final imp = Imperio(partida: Partida(saldo: 1e9, mjTotal: 1e9));
      expect(imp.valorPujo(t0), 1);
      imp.partida.edificios['dedo'] = 50;
      imp.partida.edificios['planta'] = 1;
      imp.cagadas = 10; // planta abierta
      expect(imp.comprarMejora('guantes'), isTrue);
      expect(imp.comprarMejora('faja'), isTrue);
      expect(imp.comprarMejora('dedo_acero'), isTrue);
      final m = imp.mps(t0);
      expect(imp.valorPujo(t0), closeTo(8, 1e-9));
      expect(imp.comprarMejora('respiracion'), isTrue);
      expect(imp.valorPujo(t0), closeTo(8 + 0.01 * m, 1e-6));
      expect(imp.comprarMejora('mano_dios'), isTrue);
      expect(imp.valorPujo(t0), closeTo(8 + 0.02 * m, 1e-6));
    });
  });

  group('multiplicadores', () {
    test('por cagadas', () {
      expect(Imperio(cagadas: 0).multiplicadorCagadas, 1);
      expect(Imperio(cagadas: 10).multiplicadorCagadas, closeTo(1.2, 1e-9));
      expect(Imperio(cagadas: 31).multiplicadorCagadas, closeTo(1.62, 1e-9));
      expect(Imperio(cagadas: 150).multiplicadorCagadas, closeTo(4.0, 1e-9));
      expect(Imperio(cagadas: 250).multiplicadorCagadas, closeTo(4.5, 1e-9));
    });

    test('por logros, más con lavanda', () {
      final imp = Imperio(partida: Partida(logros: {'primer_pujo', 'gotea', 'no_existe'}));
      expect(imp.multiplicadorLogros, closeTo(1.02, 1e-9));
      imp.partida.mejoras.add('lavanda');
      expect(imp.multiplicadorLogros, closeTo(1.03, 1e-9));
    });

    test('objetos y tipo se suman con tope x4; la Fiebre multiplica aparte', () {
      final imp = Imperio(cagadas: 10);
      imp.partida.edificios['ciruela'] = 1;
      final base = imp.mps(t0);
      expect(base, closeTo(1.2, 1e-9));
      imp.partida.efectos['ambientador'] = t0 + hora;
      expect(imp.mps(t0), closeTo(base * 1.25, 1e-9));
      imp.partida.efectos['cagada_fresca'] = t0 + hora;
      expect(imp.mps(t0), closeTo(base * 2.25, 1e-9));
      imp.partida.tipoBuff = 7;
      imp.partida.tipoBuffHasta = t0 + hora;
      expect(imp.multiplicadorProduccionTemporal(t0), 4); // 1 + 1 + 0,25 + 2 = 4,25 → 4
      expect(imp.mps(t0), closeTo(base * 4, 1e-9));
      imp.partida.efectos['fiebre_dorada'] = t0 + 77 * seg;
      expect(imp.mps(t0), closeTo(base * 4 * 7, 1e-9));
      imp.partida.efectos['fiebre_trono'] = t0 + 77 * seg;
      expect(imp.mps(t0), closeTo(base * 4 * 7, 1e-9)); // dos Fiebres no se apilan
      expect(imp.mpsSinEfectos(), closeTo(base, 1e-9));
    });

    test('pujo: laxante y tipos con tope, Pujo loco aparte', () {
      final imp = Imperio();
      imp.partida.efectos['laxante'] = t0 + hora;
      expect(imp.valorPujo(t0), 2);
      imp.partida.tipoBuff = 2;
      imp.partida.tipoBuffHasta = t0 + hora;
      expect(imp.valorPujo(t0), 3);
      imp.partida.efectos['pujo_loco'] = t0 + 13 * seg;
      expect(imp.valorPujo(t0), 3 * 777);
      imp.partida.tipoBuff = 7;
      imp.partida.efectos.remove('laxante');
      imp.partida.efectos.remove('pujo_loco');
      expect(imp.valorPujo(t0), 0.5);
    });

    test('pujo épico x10, 8% con tipo 1', () {
      final azar = _AzarFijo(d: 0.05);
      final imp = Imperio(azar: azar);
      expect(imp.pujar(t0).epico, isFalse); // 0,05 >= 0,02
      imp.partida.tipoBuff = 1;
      imp.partida.tipoBuffHasta = t0 + hora;
      final r = imp.pujar(t0);
      expect(r.epico, isTrue);
      expect(r.ganado, 10);
      expect(imp.saldo, 11);
      expect(imp.partida.epicos, 1);
    });
  });

  group('offline', () {
    test('tope de 2 h al 25%, sin efectos temporales', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 10; // 10 MJ/s
      imp.partida.efectos['cagada_fresca'] = t0 + 10 * hora;
      final r = imp.aplicarOffline(t0, t0 + 3 * hora);
      expect(r.segundosContados, 7200);
      expect(r.tanqueLleno, isTrue);
      expect(r.ganado, closeTo(7200 * 10 * 0.25, 1e-6));
      expect(imp.saldo, closeTo(18000, 1e-6));
    });

    test('tanques y válvulas', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 10;
      imp.partida.mejoras.addAll({'tanque_4', 'valvula_50'});
      var r = imp.aplicarOffline(t0, t0 + 3 * hora);
      expect(r.tanqueLleno, isFalse);
      expect(r.ganado, closeTo(3 * 3600 * 10 * 0.5, 1e-6));
      imp.partida.mejoras.addAll({'tanque_8', 'valvula_75'});
      r = imp.aplicarOffline(t0, t0 + 20 * hora);
      expect(r.segundosContados, 8 * 3600);
      expect(r.ganado, closeTo(8 * 3600 * 10 * 0.75, 1e-6));
    });

    test('tipo 6 da x1,5 una vez', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 10;
      imp.aplicarCagadas([CagadaReal(tipo: 6, creada: DateTime.utc(2026))], t0);
      expect(imp.partida.offlineBonus, isTrue);
      final saldo = imp.saldo;
      var r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.conBonus, isTrue);
      expect(r.ganado, closeTo(3600 * 10 * 0.25 * 1.5, 1e-6));
      expect(imp.saldo, closeTo(saldo + r.ganado, 1e-6));
      r = imp.aplicarOffline(t0 + hora, t0 + 2 * hora);
      expect(r.conBonus, isFalse);
      expect(r.ganado, closeTo(3600 * 10 * 0.25, 1e-6));
    });

    test('ausencias cortas no cuentan ni gastan el bonus', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 10;
      imp.partida.offlineBonus = true;
      final r = imp.aplicarOffline(t0, t0 + 30 * seg);
      expect(r.ganado, 0);
      expect(imp.partida.offlineBonus, isTrue);
    });
  });

  group('cagadas reales', () {
    test('Descarga de 15 min por cada una, con el peso', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 1; // 1 MJ/s
      final r = imp.aplicarCagadas([
        CagadaReal(tipo: 2, peso: 3, creada: DateTime.utc(2026, 1, 2)),
        CagadaReal(tipo: 5, creada: DateTime.utc(2026, 1, 1)),
      ], t0);
      expect(r.cantidad, 2);
      expect(r.descargas[0], closeTo(900, 1e-9)); // la vieja (sin peso) va primero
      expect(r.descargas[1], closeTo(900 * 1.3, 1e-9));
      expect(r.ganado, closeTo(2070, 1e-9));
      expect(r.tipoBuff, 2); // la más reciente
      expect(imp.tipoActivo(t0 + hora - 1), 2);
      expect(imp.tipoActivo(t0 + hora), isNull);
      expect(imp.enFiebre(t0 + 76 * seg), isTrue);
      expect(imp.enFiebre(t0 + 77 * seg), isFalse);
      expect(imp.partida.descargas, 2);
      expect(imp.partida.enFiebre, 0);
      expect(imp.fichas, 0);
    });

    test('Cagar en Fiebre cuenta una vez por tanda', () {
      final imp = Imperio();
      imp.partida.efectos['fiebre_dorada'] = t0 + 10 * seg;
      final r = imp.aplicarCagadas([CagadaReal(creada: DateTime.utc(2026)), CagadaReal(creada: DateTime.utc(2026))], t0);
      expect(r.enFiebre, isTrue);
      expect(imp.partida.enFiebre, 1);
      final nuevos = imp.tick(t0, 0).map((l) => l.id);
      expect(nuevos, containsAll(['descarga', 'cagar_fiebre']));
    });

    test('Cagada fresca: x2 por 1 h y gasta una Ficha local', () {
      final imp = Imperio(fichas: 2);
      imp.partida.edificios['ciruela'] = 1;
      imp.activarCagadaFresca(t0);
      expect(imp.fichas, 1);
      expect(imp.mps(t0), 2);
      imp.activarCagadaFresca(t0);
      expect(imp.mps(t0 + hora + 1), 2); // se sumó otra hora
      expect(imp.mps(t0 + 2 * hora), 1);
    });
  });

  group('candados', () {
    test('sin cagadas no se compra el Inodoro extra; con 3 sí', () {
      final imp = Imperio(partida: Partida(saldo: 1e6, mjTotal: 1e6));
      expect(imp.edificioAbierto('inodoro'), isFalse);
      expect(imp.comprarEdificio('inodoro', t0), isFalse);
      imp.cagadas = 3;
      expect(imp.comprarEdificio('inodoro', t0), isTrue);
      expect(imp.edificioAbierto('bano'), isFalse);
    });

    test('el Robot se esconde hasta el primer Atasco aunque tengas 10 cagadas', () {
      final imp = Imperio(cagadas: 10);
      expect(imp.objetoAbierto('robot'), isFalse);
      expect(imp.objetoAbierto('ambientador'), isTrue);
      imp.partida.vioPrimerAtasco = true;
      expect(imp.objetoAbierto('robot'), isTrue);
      expect(Imperio(cagadas: 9, partida: Partida(vioPrimerAtasco: true)).objetoAbierto('robot'), isFalse);
    });

    test('bienvenida', () {
      final b = Imperio(cagadas: 31, fichas: 4).bienvenida();
      expect(b.veterano, isTrue);
      expect(b.multiplicador, closeTo(1.62, 1e-9));
      expect(b.fichas, 4);
      expect(b.candadosAbiertos, 4);
      expect(Imperio(cagadas: 4).bienvenida().candadosAbiertos, 2);
    });
  });

  group('objetos', () {
    test('precio: minutos x MJ/s x 60, mínimo 100', () {
      final imp = Imperio(cagadas: 5);
      expect(imp.precioObjeto('laxante', t0), 100);
      imp.partida.edificios['ciruela'] = 10;
      expect(imp.precioObjeto('ambientador', t0), 6600); // 10 x 1,1 (5 cagadas) x 600 s
      expect(imp.precioObjeto('cagada_fresca', t0), 0);
    });

    test('consumibles: inventario de 5 y espera al usar', () {
      final imp = Imperio(cagadas: 5, partida: Partida(saldo: 1000, mjTotal: 1000));
      for (var k = 0; k < 5; k++) {
        expect(imp.comprarObjeto('laxante', t0), isTrue);
      }
      expect(imp.comprarObjeto('laxante', t0), isFalse);
      expect(imp.saldo, 500);
      expect(imp.usarObjeto('laxante', t0), isTrue);
      expect(imp.enInventario('laxante'), 4);
      expect(imp.valorPujo(t0), 2);
      expect(imp.usarObjeto('laxante', t0 + 29 * min_), isFalse);
      expect(imp.esperaRestante('laxante', t0 + 29 * min_), const Duration(minutes: 1));
      expect(imp.usarObjeto('laxante', t0 + 30 * min_), isTrue);
    });

    test('Robot: 30 min, sube a 1 h máximo, espera 4 h y destapa solo', () {
      final imp = Imperio(cagadas: 10, partida: Partida(saldo: 1000, mjTotal: 1000, vioPrimerAtasco: true), azar: _AzarFijo(d: 0.99));
      expect(imp.comprarObjeto('robot', t0), isTrue);
      expect(imp.partida.robotHasta, t0 + 30 * min_);
      expect(imp.comprarObjeto('robot', t0 + min_), isTrue);
      expect(imp.partida.robotHasta, t0 + hora); // +30 min
      expect(imp.comprarObjeto('robot', t0 + min_), isTrue);
      expect(imp.partida.robotHasta, t0 + hora + min_); // tope: 1 h desde ahora
      expect(imp.comprarObjeto('robot', t0 + min_), isFalse);
      imp.partida.atasco = Atasco('dedo', t0 + 2 * min_);
      imp.tick(t0 + 2 * min_, 1);
      expect(imp.atasco, isNull);
      expect(imp.partida.destapes, 1);
      expect(imp.comprarObjeto('robot', t0 + 3 * hora), isFalse);
      expect(imp.comprarObjeto('robot', t0 + 4 * hora), isTrue);
    });

    test('efectos activos para la barra', () {
      final imp = Imperio();
      imp.partida.efectos['fiebre_dorada'] = t0 + 77 * seg;
      imp.partida.efectos['laxante'] = t0 + 5 * min_;
      imp.partida.tipoBuff = 4;
      imp.partida.tipoBuffHasta = t0 + hora;
      imp.partida.papelDoble = true;
      final e = imp.efectosActivos(t0);
      expect(e.map((x) => x.id), ['fiebre_dorada', 'laxante', 'tipo_4', 'papel']);
      expect(e.first.emoji, '🔥');
      expect(e.first.restante, const Duration(seconds: 77));
      expect(e.last.restante, isNull);
    });
  });

  group('mojón dorado', () {
    test('pesos 40/40/10/10', () {
      expect(Imperio.efectoPorTirada(0), EfectoDorado.fiebre);
      expect(Imperio.efectoPorTirada(39), EfectoDorado.fiebre);
      expect(Imperio.efectoPorTirada(40), EfectoDorado.lluvia);
      expect(Imperio.efectoPorTirada(79), EfectoDorado.lluvia);
      expect(Imperio.efectoPorTirada(80), EfectoDorado.pujoLoco);
      expect(Imperio.efectoPorTirada(89), EfectoDorado.pujoLoco);
      expect(Imperio.efectoPorTirada(90), EfectoDorado.constructor);
      expect(Imperio.efectoPorTirada(99), EfectoDorado.constructor);
    });

    test('con azar fijo la tirada es reproducible y respeta los pesos', () {
      List<EfectoDorado> tirar(int semilla) {
        final imp = Imperio(azar: Random(semilla));
        final r = <EfectoDorado>[];
        for (var k = 0; k < 10000; k++) {
          imp.partida.dorado = DoradoVisible(t0, t0 + 13 * seg, 0.5, 0.5);
          r.add(imp.tocarDorado(t0)!.efecto);
        }
        return r;
      }

      final a = tirar(77);
      expect(tirar(77), a);
      int cuenta(EfectoDorado e) => a.where((x) => x == e).length;
      expect(cuenta(EfectoDorado.fiebre), inInclusiveRange(3750, 4250));
      expect(cuenta(EfectoDorado.lluvia), inInclusiveRange(3750, 4250));
      expect(cuenta(EfectoDorado.pujoLoco), inInclusiveRange(850, 1150));
      expect(cuenta(EfectoDorado.constructor), inInclusiveRange(850, 1150));
    });

    test('sale cada 5 a 15 min activos, dura 13 s; Imán y Brillo', () {
      int primerDorado(Imperio imp) {
        imp.tick(t0, 1); // programa
        for (var s = 1; s <= 2000; s++) {
          imp.tick(t0 + s * seg, 1);
          if (imp.dorado(t0 + s * seg) != null) return s;
        }
        return -1;
      }

      final imp = Imperio(azar: _AzarFijo(d: 0.0, i: 0));
      expect(primerDorado(imp), 300);
      final d = imp.dorado(t0 + 300 * seg)!;
      expect(d.hasta - d.desde, 13 * seg);
      expect(imp.dorado(t0 + 313 * seg), isNull);
      expect(primerDorado(Imperio(azar: _AzarFijo(d: 0.999))), inInclusiveRange(899, 900));
      final iman = Imperio(azar: _AzarFijo(d: 0.0), partida: Partida(mejoras: {'iman', 'brillo'}));
      expect(primerDorado(iman), 150);
      final di = iman.dorado(t0 + 150 * seg)!;
      expect(di.hasta - di.desde, 26 * seg);
    });

    test('Lluvia: mín(15% saldo, 15 min) + 13', () {
      final imp = Imperio(azar: _AzarFijo(i: 40), partida: Partida(saldo: 1000, mjTotal: 1000));
      imp.partida.edificios['ciruela'] = 10;
      imp.partida.dorado = DoradoVisible(t0, t0 + 13 * seg, 0.5, 0.5);
      final r = imp.tocarDorado(t0)!;
      expect(r.efecto, EfectoDorado.lluvia);
      expect(r.cantidad, closeTo(150 + 13, 1e-9));
      imp.partida.saldo = 1e9;
      imp.partida.dorado = DoradoVisible(t0, t0 + 13 * seg, 0.5, 0.5);
      expect(imp.tocarDorado(t0)!.cantidad, closeTo(9000 + 13, 1e-9));
      expect(imp.tocarDorado(t0), isNull);
      expect(imp.partida.dorados, 2);
    });

    test('Papel doble hoja dobla el siguiente', () {
      final imp = Imperio(cagadas: 5, azar: _AzarFijo(i: 0), partida: Partida(inventario: {'papel': 2}));
      expect(imp.usarObjeto('papel', t0), isTrue);
      expect(imp.partida.papelDoble, isTrue);
      imp.partida.dorado = DoradoVisible(t0, t0 + 13 * seg, 0.5, 0.5);
      final r = imp.tocarDorado(t0)!;
      expect(r.doble, isTrue);
      expect(r.duracion, const Duration(seconds: 154));
      expect(imp.enFiebre(t0 + 153 * seg), isTrue);
      expect(imp.partida.papelDoble, isFalse);
    });
  });

  group('Atascos', () {
    test('salen en un edificio con 25 o más y lo dejan en 0', () {
      final imp = Imperio(azar: _AzarFijo(d: 0.0));
      imp.partida.edificios.addAll({'dedo': 25, 'ciruela': 3});
      imp.partida.segHastaDorado = 99999;
      imp.tick(t0, 1);
      expect(imp.atasco?.edificio, 'dedo');
      expect(imp.partida.vioPrimerAtasco, isTrue);
      expect(imp.mpsEdificio('dedo', t0), 0);
      expect(imp.mps(t0), closeTo(3 * imp.multiplicadorPermanente, 1e-9)); // el tick ya dio el logro gotea
      final otro = Imperio(azar: _AzarFijo(d: 0.0));
      otro.partida.edificios['dedo'] = 24;
      otro.tick(t0, 1);
      expect(otro.atasco, isNull);
    });

    test('10 toques; en menos de 3 s es perfecto y da 5 min del edificio', () {
      final imp = Imperio();
      imp.partida.edificios['ciruela'] = 30;
      imp.partida.atasco = Atasco('ciruela', t0);
      for (var k = 1; k < 10; k++) {
        final r = imp.tocarAtasco(t0 + k * 200)!;
        expect(r.destapado, isFalse);
        expect(r.faltan, 10 - k);
      }
      final r = imp.tocarAtasco(t0 + 2900)!;
      expect(r.destapado, isTrue);
      expect(r.perfecto, isTrue);
      expect(r.premio, closeTo(30 * 300, 1e-9));
      expect(imp.atasco, isNull);
      expect(imp.partida.destapesPerfectos, 1);
      expect(imp.tocarAtasco(t0 + 3000), isNull);

      imp.partida.atasco = Atasco('ciruela', t0);
      for (var k = 0; k < 9; k++) {
        imp.tocarAtasco(t0);
      }
      final lento = imp.tocarAtasco(t0 + 3000)!;
      expect(lento.destapado, isTrue);
      expect(lento.perfecto, isFalse);
      expect(lento.premio, 0);
    });
  });

  group('logros', () {
    test('se marcan en el tick y se devuelven una sola vez', () {
      final imp = Imperio(azar: _AzarFijo(d: 0.99));
      imp.pujar(t0);
      final l = imp.tick(t0, 0).map((x) => x.id);
      expect(l, ['primer_pujo']);
      expect(imp.tick(t0, 0), isEmpty);
      imp.partida.edificios['cafe'] = 1;
      expect(imp.tick(t0, 0).map((x) => x.id), containsAll(['gotea', 'primer_guayoyo']));
      expect(imp.multiplicadorLogros, closeTo(1.03, 1e-9));
    });

    test('Nalgazo: 100 pujos en 10 s', () {
      final imp = Imperio(azar: _AzarFijo(d: 0.99));
      for (var k = 0; k < 100; k++) {
        imp.pujar(t0 + k * 100);
      }
      expect(imp.partida.nalgazos, 1);
      expect(imp.tick(t0 + 10 * seg, 0).map((x) => x.id), contains('nalgazo'));
      final lento = Imperio(azar: _AzarFijo(d: 0.99));
      for (var k = 0; k < 150; k++) {
        lento.pujar(t0 + k * 150);
      }
      expect(lento.partida.nalgazos, 0);
    });
  });

  test('JSON ida y vuelta', () {
    final imp = Imperio(cagadas: 12, fichas: 3, azar: _AzarFijo(d: 0.0));
    imp.partida
      ..saldo = 1234.5
      ..mjTotal = 99999
      ..edificios.addAll({'dedo': 26, 'cafe': 2})
      ..mejoras.addAll({'guantes', 'tanque_4'})
      ..inventario['laxante'] = 2
      ..efectos['ambientador'] = t0 + hora
      ..esperas['laxante'] = t0 + 30 * min_
      ..robotHasta = t0 + 5
      ..papelDoble = true
      ..tipoBuff = 6
      ..tipoBuffHasta = t0 + hora
      ..offlineBonus = true;
    imp.pujar(t0);
    imp.tick(t0, 1);
    imp.tick(t0 + seg, 1);
    final texto = jsonEncode(imp.toJson());
    final otro = Imperio.desdeJson(jsonDecode(texto) as Map<String, dynamic>, cagadas: 12, fichas: 3);
    expect(jsonEncode(otro.toJson()), texto);
    expect(otro.toJson()['v'], 1);
    expect(otro.atasco?.edificio, 'dedo');
    expect(otro.mps(t0 + seg), imp.mps(t0 + seg));
    expect(otro.valorPujo(t0), imp.valorPujo(t0));
  });

  test('JSON roto o vacío no revienta', () {
    expect(Imperio.desdeJson(null).saldo, 0);
    final raro = Imperio.desdeJson({
      'saldo': 'abc',
      'mj_total': -5,
      'edificios': {'dedo': '3', 'cafe': -1},
      'mejoras': 'no',
      'tipo_buff': 99,
      'atasco': {'d': 1},
      'pujos_recientes': List.generate(300, (i) => i),
    });
    expect(raro.saldo, 0);
    expect(raro.cantidad('dedo'), 3);
    expect(raro.cantidad('cafe'), 0);
    expect(raro.partida.tipoBuff, isNull);
    expect(raro.atasco, isNull);
    expect(raro.partida.pujosRecientes.length, 100);
  });
}
