import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/bano.dart';
import 'package:rey_cagon/imperio/motor.dart';

const t0 = 1800000000000;
const hora = 3600000;

/// Imperio con los alquilables abiertos (30 cagadas, ya vio un atasco), algo de producción y mucho saldo.
Imperio _imperio({int arepas = 10, double saldo = 1e15, Ajustes ajustes = Ajustes.porDefecto}) {
  final imp = Imperio(cagadas: 30, ajustes: ajustes, azar: Random(1));
  imp.partida.vioPrimerAtasco = true;
  imp.partida.edificios['arepa'] = arepas;
  imp.partida.saldo = saldo;
  return imp;
}

int _dur(String id) => objetoPorId(id)!.duracion!.inMilliseconds;

void main() {
  group('Precio con descuento por etapa', () {
    test('sigue la fórmula y queda por debajo del precio sin descuento', () {
      final imp = _imperio();
      final m = imp.mpsSinEfectos();
      expect(m, greaterThan(10));
      for (final id in ['robot', 'robot_turbo', 'plomero_horas', 'primo', 'cuadrilla', 'guardia']) {
        final o = objetoPorId(id)!;
        final esperado = max(100.0, (o.minutosPrecio * 60 * m * pow(m / 10, -0.22)).ceilToDouble());
        expect(imp.precioAlquiler(id, t0, 1), esperado, reason: id);
        expect(imp.precioAlquiler(id, t0, 1), lessThan(o.minutosPrecio * 60 * m), reason: id);
      }
    });

    test('sin descuento (k = 0) es minutos x 60 x MJ/s', () {
      final imp = _imperio(ajustes: const Ajustes(alquilerDescuento: 0));
      final m = imp.mpsSinEfectos();
      expect(imp.precioAlquiler('primo', t0, 1), (10 * 60 * m).ceilToDouble());
    });

    test('mínimo 100 MJ', () {
      final imp = _imperio(arepas: 0);
      expect(imp.precioAlquiler('cuadrilla', t0, 1), 100);
    });
  });

  group('Calor', () {
    test('sube x1,5 por periodo y baja a la mitad cada 6 h', () {
      final imp = _imperio();
      expect(imp.multiplicadorCalor('primo', t0), 1);
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.calor('primo', t0), closeTo(1, 1e-9));
      expect(imp.multiplicadorCalor('primo', t0), closeTo(1.5, 1e-9));
      expect(imp.calor('primo', t0 + 6 * hora), closeTo(0.5, 1e-9));
      expect(imp.calor('primo', t0 + 12 * hora), closeTo(0.25, 1e-9));
    });

    test('tope x10: el calor no pasa de log(10)/log(1,5)', () {
      final imp = _imperio();
      final tope = log(10) / log(1.5);
      expect(imp.comprarObjeto('cuadrilla', t0, veces: 10), isTrue);
      expect(imp.calor('cuadrilla', t0), closeTo(tope, 1e-9));
      expect(imp.multiplicadorCalor('cuadrilla', t0), closeTo(10, 1e-9));
      // Ya en el tope, otro periodo cuesta 10 veces la base.
      final base = _imperio().precioAlquiler('cuadrilla', t0, 1);
      final fin = t0 + 10 * _dur('cuadrilla');
      expect(imp.precioAlquiler('cuadrilla', fin, 1), closeTo((base * imp.multiplicadorCalor('cuadrilla', fin)).ceilToDouble(), 1));
    });

    test('cada alquilable tiene su calor', () {
      final imp = _imperio();
      final robotAntes = imp.precioAlquiler('robot', t0, 1);
      expect(imp.comprarObjeto('primo', t0, veces: 5), isTrue);
      expect(imp.calor('robot', t0), 0);
      expect(imp.precioAlquiler('robot', t0, 1), robotAntes);
    });

    test('varios periodos: suma de ceil(base x 1,5^(calor + i))', () {
      final imp = _imperio();
      final base = imp.precioAlquiler('plomero_horas', t0, 1);
      final esperado = base + (base * 1.5).ceilToDouble() + (base * 2.25).ceilToDouble();
      expect(imp.precioAlquiler('plomero_horas', t0, 3), esperado);
      // Con calor previo, los periodos siguientes arrancan más caros.
      expect(imp.comprarObjeto('plomero_horas', t0), isTrue);
      final c = imp.calor('plomero_horas', t0);
      var conCalor = 0.0;
      for (var i = 0; i < 3; i++) {
        conCalor += (base * min(pow(1.5, c + i), 10)).ceilToDouble();
      }
      expect(imp.precioAlquiler('plomero_horas', t0, 3), conCalor);
    });
  });

  group('Duraciones xN', () {
    test('x5 cobra la suma y dura 5 periodos', () {
      final imp = _imperio();
      final antes = imp.saldo;
      final precio = imp.precioAlquiler('robot', t0, 5);
      expect(imp.comprarObjeto('robot', t0, veces: 5), isTrue);
      expect(imp.saldo, closeTo(antes - precio, 1e-3));
      expect(imp.partida.alquilados['robot'], t0 + 5 * _dur('robot'));
    });

    test('tope de 10 periodos por delante', () {
      final imp = _imperio();
      expect(imp.periodosQueCaben('primo', t0), 10);
      expect(imp.puedeComprarObjeto('primo', t0, veces: 11), isFalse);
      expect(imp.comprarObjeto('primo', t0, veces: 10), isTrue);
      expect(imp.periodosQueCaben('primo', t0), 0);
      expect(imp.comprarObjeto('primo', t0), isFalse);
      // Pasado un periodo cabe uno más.
      expect(imp.periodosQueCaben('primo', t0 + _dur('primo')), 1);
    });

    test('las opciones son x1, x2, x5 y x10', () {
      expect(opcionesAlquiler, [1, 2, 5, 10]);
      expect(vecesAlquilerMax, 10);
    });
  });

  group('Indefinido', () {
    test('se renueva al vencer y cobra el periodo', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('cuadrilla', t0, indefinido: true), isTrue);
      expect(imp.alquilerIndefinido('cuadrilla'), isTrue);
      final fin = t0 + _dur('cuadrilla');
      expect(imp.partida.alquilados['cuadrilla'], fin);
      final antes = imp.saldo;
      final precio = imp.precioAlquiler('cuadrilla', fin, 1);
      imp.tick(fin, 0);
      expect(imp.saldo, closeTo(antes - precio, 1e-3));
      expect(imp.partida.alquilados['cuadrilla'], fin + _dur('cuadrilla'));
      expect(imp.alquiladoActivo('cuadrilla', fin + 1), isTrue);
      expect(imp.tomarIndefinidosCortados(), isEmpty);
    });

    test('se corta si no alcanzan los MJ y se avisa una vez', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('cuadrilla', t0, indefinido: true), isTrue);
      imp.partida.saldo = 0;
      final fin = t0 + _dur('cuadrilla');
      imp.tick(fin, 0);
      expect(imp.alquilerIndefinido('cuadrilla'), isFalse);
      expect(imp.alquiladoActivo('cuadrilla', fin), isFalse);
      final cortados = imp.tomarIndefinidosCortados();
      expect(cortados.length, 1);
      expect(cortados.first.$1, 'cuadrilla');
      expect(imp.tomarIndefinidosCortados(), isEmpty);
    });

    test('apagarlo deja terminar el periodo sin renovar', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0, indefinido: true), isTrue);
      expect(imp.apagarIndefinido('primo'), isTrue);
      final fin = t0 + _dur('primo');
      expect(imp.alquiladoActivo('primo', fin - 1), isTrue);
      final antes = imp.saldo;
      imp.tick(fin, 0);
      expect(imp.saldo, antes);
      expect(imp.alquiladoActivo('primo', fin), isFalse);
      expect(imp.tomarIndefinidosCortados(), isEmpty);
    });

    test('el Guardia no tiene Indefinido y es de un solo uso', () {
      final imp = _imperio();
      expect(imp.puedeIndefinido('guardia', t0), isFalse);
      expect(imp.comprarObjeto('guardia', t0, indefinido: true), isFalse);
      expect(imp.comprarObjeto('guardia', t0), isTrue);
      expect(imp.comprarObjeto('guardia', t0 + hora), isFalse);
      expect(imp.periodosQueCaben('guardia', t0), 0);
    });
  });

  test('cantidad de primos: 1 + uno por cada x1000 de MJ/s, hasta 4', () {
    for (final arepas in [0, 1, 30, 1000, 100000]) {
      final imp = _imperio(arepas: arepas);
      final m = max(imp.mpsSinEfectos(), 1.0);
      final esperado = (1 + (log(m) / ln10 / 3 + 1e-9).floor()).clamp(1, 4);
      expect(imp.primosActivos(), esperado, reason: '$arepas arepas');
    }
    expect(_imperio(arepas: 0).primosActivos(), 1);
    expect(_imperio(arepas: 100000).primosActivos(), greaterThan(1));
    final mucho = _imperio(arepas: 10);
    mucho.partida.edificios['planta'] = 1000000;
    expect(mucho.primosActivos(), 4);
  });

  group('Partidas viejas', () {
    test('cargan sin las claves nuevas', () {
      final p = Partida.desdeJson({'v': 1, 'saldo': 500.0, 'mj_total': 900.0, 'alquilados': {'primo': t0 + 1000}, 'tipo_buff': 2,
          'tipo_buff_hasta': t0 + hora, 'offline_bonus': true, 'esperas': {'primo': t0 + hora}});
      expect(p.calor, isEmpty);
      expect(p.calorEn, isEmpty);
      expect(p.indefinidos, isEmpty);
      expect(p.tipoBuffFuerza, 1);
      expect(p.offlineBonusFuerza, 1);
      expect(p.rachaTipoVeces, 0);
      expect(p.rachaTipo, isNull);
    });

    test('ida y vuelta conserva calor, Indefinidos y racha', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0, indefinido: true), isTrue);
      imp.aplicarCagadas([CagadaReal(tipo: 2, creada: DateTime.fromMillisecondsSinceEpoch(t0))], t0);
      imp.aplicarCagadas([CagadaReal(tipo: 2, creada: DateTime.fromMillisecondsSinceEpoch(t0 + hora))], t0 + hora);
      final p = Partida.desdeJson(imp.toJson());
      expect(p.calor['primo'], closeTo(1, 1e-9));
      expect(p.calorEn['primo'], t0);
      expect(p.indefinidos, {'primo'});
      expect(p.rachaTipo, 2);
      expect(p.rachaTipoVeces, 2);
      expect(p.tipoBuffFuerza, 0.5);
    });
  });

  test('sin espera: una espera vieja guardada no frena el alquiler', () {
    final imp = _imperio();
    imp.partida.esperas['primo'] = t0 + 10 * hora;
    expect(imp.esperaRestante('primo', t0), isNull);
    expect(imp.comprarObjeto('primo', t0), isTrue);
    // Recomprar enseguida también se puede (lo frena el calor, no una espera).
    expect(imp.comprarObjeto('primo', t0 + 1), isTrue);
  });

  group('Buff de tipo cansado', () {
    CagadaReal c(int? tipo, int ms) => CagadaReal(tipo: tipo, creada: DateTime.fromMillisecondsSinceEpoch(ms));

    test('mismo tipo seguido: entero, mitad, nada', () {
      final imp = _imperio();
      expect(imp.aplicarCagadas([c(2, t0)], t0).fuerza, 1);
      expect(imp.fuerzaTipo, 1);
      expect(imp.aplicarCagadas([c(2, t0 + hora)], t0 + hora).fuerza, 0.5);
      expect(imp.fuerzaTipo, 0.5);
      final hasta = imp.partida.tipoBuffHasta;
      final r = imp.aplicarCagadas([c(2, t0 + 90 * 60000)], t0 + 90 * 60000);
      expect(r.fuerza, 0);
      expect(imp.partida.tipoBuffHasta, hasta, reason: 'sin fuerza no alarga el buff que estaba');
      expect(imp.fuerzaTipo, 0.5);
      expect(imp.partida.rachaTipoVeces, 3);
    });

    test('24 h sin ese tipo reinicia la racha', () {
      final imp = _imperio();
      imp.aplicarCagadas([c(2, t0)], t0);
      imp.aplicarCagadas([c(2, t0 + hora)], t0 + hora);
      final tarde = t0 + hora + 25 * hora;
      expect(imp.aplicarCagadas([c(2, tarde)], tarde).fuerza, 1);
      expect(imp.partida.rachaTipoVeces, 1);
    });

    test('cambiar de tipo reinicia la racha', () {
      final imp = _imperio();
      imp.aplicarCagadas([c(2, t0)], t0);
      imp.aplicarCagadas([c(2, t0 + hora)], t0 + hora);
      expect(imp.aplicarCagadas([c(4, t0 + 2 * hora)], t0 + 2 * hora).fuerza, 1);
      expect(imp.tipoActivo(t0 + 2 * hora), 4);
    });

    test('una cagada sin tipo no corta ni cuenta en la racha', () {
      final imp = _imperio();
      imp.aplicarCagadas([c(2, t0)], t0);
      imp.aplicarCagadas([c(null, t0 + hora)], t0 + hora);
      expect(imp.partida.rachaTipoVeces, 1);
      expect(imp.aplicarCagadas([c(2, t0 + 2 * hora)], t0 + 2 * hora).fuerza, 0.5);
    });

    test('fuerzaPorRacha', () {
      expect(Imperio.fuerzaPorRacha(0), 1);
      expect(Imperio.fuerzaPorRacha(1), 1);
      expect(Imperio.fuerzaPorRacha(2), 0.5);
      expect(Imperio.fuerzaPorRacha(3), 0);
      expect(Imperio.fuerzaPorRacha(9), 0);
    });

    test('con fuerza 0,5 cada bono m pasa a 1 + (m - 1) x 0,5', () {
      final ahora = t0 + 10 * 60000;
      Imperio con(int tipo) {
        final imp = _imperio();
        imp.partida.tipoBuff = tipo;
        imp.partida.tipoBuffHasta = t0 + hora;
        imp.partida.tipoBuffFuerza = 0.5;
        return imp;
      }

      expect(con(7).multiplicadorProduccionTemporal(ahora), 2.0);
      expect(con(7).multiplicadorPujoTemporal(ahora), 0.75);
      expect(con(4).multiplicadorProduccionTemporal(ahora), 1.5);
      expect(con(2).multiplicadorPujoTemporal(ahora), 1.5);
      expect(con(3).factorPrecioEdificios(ahora), closeTo(0.95, 1e-12));
    });

    test('tipo 6 cansado: el bono offline da +25 %', () {
      final imp = _imperio();
      imp.aplicarCagadas([c(6, t0)], t0);
      imp.aplicarCagadas([c(6, t0 + hora)], t0 + hora);
      expect(imp.partida.offlineBonus, isTrue);
      expect(imp.partida.offlineBonusFuerza, 0.5);
      final r = imp.aplicarOffline(t0 + hora, t0 + 3 * hora);
      expect(r.fuerzaBonus, 0.5);
      expect(imp.partida.offlineBonusFuerza, 1);
    });
  });

  group('Pausa a mano', () {
    test('pausar guarda lo que queda y seguir lo devuelve', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.pausarAlquiler('primo', t0 + 60000), isTrue);
      expect(imp.alquiladoActivo('primo', t0 + 60000), isFalse);
      expect(imp.enPausa('primo'), Duration(milliseconds: _dur('primo') - 60000));
      expect(imp.reanudarAlquiler('primo', t0 + 10 * hora), isTrue);
      expect(imp.enPausa('primo'), isNull);
      expect(imp.partida.alquilados['primo'], t0 + 10 * hora + _dur('primo') - 60000);
    });

    test('solo Primo, Cuadrilla y Plomero por horas, y solo activos', () {
      final imp = _imperio();
      for (final id in ['primo', 'cuadrilla', 'plomero_horas', 'robot', 'robot_turbo', 'guardia']) {
        expect(imp.comprarObjeto(id, t0), isTrue, reason: id);
      }
      for (final id in ['robot', 'robot_turbo', 'guardia']) {
        expect(imp.pausarAlquiler(id, t0), isFalse, reason: id);
      }
      expect(imp.pausarAlquiler('cuadrilla', t0 + _dur('cuadrilla')), isFalse);
      expect(imp.pausarAlquiler('plomero_horas', t0), isTrue);
      expect(imp.pausarAlquiler('plomero_horas', t0), isFalse);
      expect(imp.reanudarAlquiler('primo', t0), isFalse);
    });

    test('en pausa el Indefinido no se renueva ni cobra; sigue siendo Indefinido', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('cuadrilla', t0, indefinido: true), isTrue);
      expect(imp.pausarAlquiler('cuadrilla', t0 + 1000), isTrue);
      final antes = imp.saldo;
      imp.tick(t0 + 3 * _dur('cuadrilla'), 0);
      expect(imp.saldo, antes);
      expect(imp.alquilerIndefinido('cuadrilla'), isTrue);
      expect(imp.enPausa('cuadrilla'), Duration(milliseconds: _dur('cuadrilla') - 1000));
    });

    test('alquilar en pausa lo sigue y le suma el periodo', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.pausarAlquiler('primo', t0), isTrue);
      final t = t0 + 5 * hora;
      expect(imp.comprarObjeto('primo', t), isTrue);
      expect(imp.enPausa('primo'), isNull);
      expect(imp.partida.alquilados['primo'], t + 2 * _dur('primo'));
    });

    test('Indefinido en pausa: activarlo lo sigue sin cobrar', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.pausarAlquiler('primo', t0), isTrue);
      final antes = imp.saldo;
      expect(imp.puedeIndefinido('primo', t0 + hora), isTrue);
      expect(imp.comprarObjeto('primo', t0 + hora, indefinido: true), isTrue);
      expect(imp.saldo, antes);
      expect(imp.partida.alquilados['primo'], t0 + hora + _dur('primo'));
    });

    test('el resumen offline cuenta lo que corrió sin pausar, no lo pausado', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.comprarObjeto('cuadrilla', t0), isTrue);
      expect(imp.pausarAlquiler('cuadrilla', t0), isTrue);
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.corridos, [('primo', _dur('primo'))]);
      expect(imp.enPausa('cuadrilla'), Duration(milliseconds: _dur('cuadrilla')));
    });

    test('ida y vuelta conserva la pausa; jalar la borra', () {
      final imp = _imperio();
      expect(imp.comprarObjeto('primo', t0), isTrue);
      expect(imp.pausarAlquiler('primo', t0 + 1000), isTrue);
      final p = Partida.desdeJson(imp.toJson());
      expect(p.pausados, {'primo': _dur('primo') - 1000});
      expect(p.alquilados.containsKey('primo'), isFalse);
      expect(Partida.desdeJson(_imperio().toJson()).pausados, isEmpty);
    });
  });

  test('EstadoBano compara también lo alquilado', () {
    const a = EstadoBano(alquiler: (primos: 2, cuadrilla: false, plomero: false, robot: 0, guardia: false));
    const b = EstadoBano(alquiler: (primos: 2, cuadrilla: false, plomero: false, robot: 0, guardia: false));
    const c = EstadoBano(alquiler: (primos: 3, cuadrilla: false, plomero: false, robot: 0, guardia: false));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
    expect(const EstadoBano() == a, isFalse);
  });
}
