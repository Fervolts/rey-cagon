import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int t0 = 1800000000000;
const int minuto = 60 * 1000;
const int hora = 60 * minuto;

/// 10 Ciruelas (10 MJ/s), ya vio el primer Atasco y con un Atasco offline a los [enMin] minutos de salir.
Imperio _imperio({int? enMin, Random? azar}) {
  final imp = Imperio(azar: azar);
  imp.partida
    ..edificios['ciruela'] = 10
    ..vioPrimerAtasco = true;
  if (enMin != null) {
    imp.partida
      ..atascoOfflineEn = t0 + enMin * minuto
      ..atascoOfflineEdificio = 'ciruela';
  }
  return imp;
}

void main() {
  group('programar al salir', () {
    test('sortea un edificio y una hora desde el mínimo, y se guarda en la partida', () {
      for (var semilla = 0; semilla < 50; semilla++) {
        final imp = _imperio(azar: Random(semilla));
        final a = imp.programarAtascoOffline(t0)!;
        expect(a.edificio, 'ciruela');
        expect(a.en, greaterThanOrEqualTo(t0 + 10 * minuto));
        expect(a.cubierto, isFalse);
        expect(imp.partida.atascoOfflineEn, a.en);
        final j = jsonDecode(jsonEncode(imp.toJson())) as Map<String, dynamic>;
        final p = Partida.desdeJson(j);
        expect(p.atascoOfflineEn, a.en);
        expect(p.atascoOfflineEdificio, 'ciruela');
      }
    });

    test('la media ronda los 45 min', () {
      final azar = Random(7);
      var suma = 0.0;
      const n = 4000;
      for (var k = 0; k < n; k++) {
        final imp = _imperio(azar: azar);
        suma += (imp.programarAtascoOffline(t0)!.en - t0) / minuto;
      }
      expect(suma / n, closeTo(45, 2.5));
    });

    test('no vuelve a sortear el que ya está programado', () {
      final imp = _imperio(enMin: 30, azar: Random(1));
      final a = imp.programarAtascoOffline(t0)!;
      expect(a.en, t0 + 30 * minuto);
    });

    test('nada que programar: ya atascado, sin primer Atasco visto o sin edificios', () {
      final atascado = _imperio()..partida.atasco = Atasco('ciruela', t0);
      expect(atascado.programarAtascoOffline(t0), isNull);
      final nuevo = _imperio()..partida.vioPrimerAtasco = false;
      expect(nuevo.programarAtascoOffline(t0), isNull);
      final vacio = Imperio()..partida.vioPrimerAtasco = true;
      expect(vacio.programarAtascoOffline(t0), isNull);
      expect(vacio.partida.atascoOfflineEn, 0);
    });

    test('con Robot alquilado hasta después del Atasco viene cubierto (sin aviso)', () {
      final imp = _imperio(azar: Random(3))..partida.alquilados['robot'] = t0 + 48 * hora;
      expect(imp.programarAtascoOffline(t0)!.cubierto, isTrue);
    });
  });

  group('al volver', () {
    test('Atasco a mitad de la ausencia: deja de producir desde ahí y queda atascado', () {
      final imp = _imperio(enMin: 30);
      final r = imp.aplicarOffline(t0, t0 + hora);
      // 30 min a 10 MJ/s al 25% y 30 min sin la Ciruela (el único edificio).
      expect(r.ganado, closeTo(1800 * 10 * 0.25, 1e-6));
      expect(r.mjPerdidos, closeTo(1800 * 10 * 0.25, 1e-6));
      expect(r.atascoEdificio, 'ciruela');
      expect(r.atascoEn, t0 + 30 * minuto);
      expect(r.atascoCubierto, isFalse);
      expect(imp.atasco?.edificio, 'ciruela');
      expect(imp.atasco?.desde, t0 + hora);
      expect(imp.partida.atascoOfflineEn, 0);
      expect(imp.partida.atascoOfflineEdificio, '');
    });

    test('solo pierde el edificio atascado; los demás siguen', () {
      final imp = _imperio(enMin: 15)..partida.edificios['dedo'] = 5;
      final sinAtasco = (_imperio()..partida.edificios['dedo'] = 5).aplicarOffline(t0, t0 + hora).ganado;
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.mjPerdidos, closeTo(45 * 60 * 10 * 0.25, 1e-6));
      expect(r.ganado, closeTo(sinAtasco - r.mjPerdidos, 1e-6));
    });

    test('Robot alquilado lo destapa solo: no pierde nada', () {
      final imp = _imperio(enMin: 30)..partida.alquilados['robot'] = t0 + 2 * hora;
      final destapes = imp.partida.destapes;
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.ganado, closeTo(3600 * 10 * 0.25, 1e-6));
      expect(r.mjPerdidos, 0);
      expect(r.atascoEdificio, 'ciruela');
      expect(r.atascoCubierto, isTrue);
      expect(imp.atasco, isNull);
      expect(imp.partida.destapes, destapes + 1);
    });

    test('Robot que se venció antes del Atasco no lo cubre', () {
      final imp = _imperio(enMin: 30)..partida.alquilados['robot'] = t0 + 20 * minuto;
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.atascoCubierto, isFalse);
      expect(r.mjPerdidos, greaterThan(0));
    });

    test('Robot Turbo: el Atasco no frena la producción', () {
      final imp = _imperio(enMin: 30)..partida.alquilados['robot_turbo'] = t0 + 2 * hora;
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.ganado, closeTo(3600 * 10 * 0.25, 1e-6));
      expect(r.mjPerdidos, 0);
      expect(r.atascoCubierto, isTrue);
      expect(imp.atasco, isNull);
    });

    test('Robot Turbo en Indefinido (vencido, se renueva al volver) también cubre', () {
      final imp = _imperio(enMin: 30);
      imp.partida
        ..alquilados['robot_turbo'] = t0 + 10 * minuto
        ..indefinidos.add('robot_turbo');
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.atascoCubierto, isTrue);
      expect(r.mjPerdidos, 0);
    });

    test('Súper Plomero cubre', () {
      final imp = _imperio(enMin: 30)..partida.objetosRollos['super_plomero'] = 1;
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.atascoCubierto, isTrue);
      expect(r.mjPerdidos, 0);
    });

    test('partida vieja sin el campo: offline igual que antes', () {
      final viejo = _imperio().toJson()
        ..remove('atasco_offline_en')
        ..remove('atasco_offline_e');
      final imp = Imperio.desdeJson(viejo);
      expect(imp.partida.atascoOfflineEn, 0);
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.ganado, closeTo(3600 * 10 * 0.25, 1e-6));
      expect(r.atascoEdificio, isNull);
      expect(r.mjPerdidos, 0);
      expect(imp.atasco, isNull);
    });

    test('volvió antes de la hora del Atasco: no hay Atasco y se borra', () {
      final imp = _imperio(enMin: 90);
      final r = imp.aplicarOffline(t0, t0 + hora);
      expect(r.ganado, closeTo(3600 * 10 * 0.25, 1e-6));
      expect(r.atascoEdificio, isNull);
      expect(imp.atasco, isNull);
      expect(imp.partida.atascoOfflineEn, 0);
    });

    test('Atasco después del tope del tanque: no cuenta', () {
      final imp = _imperio(enMin: 150); // tope 2 h, fuera 3 h
      final r = imp.aplicarOffline(t0, t0 + 3 * hora);
      expect(r.atascoEdificio, isNull);
      expect(r.ganado, closeTo(7200 * 10 * 0.25, 1e-6));
      expect(imp.atasco, isNull);
    });

    test('ausencia menor al mínimo offline: se borra sin Atasco', () {
      final imp = _imperio(enMin: 0);
      final r = imp.aplicarOffline(t0, t0 + 30 * 1000);
      expect(r.atascoEdificio, isNull);
      expect(imp.atasco, isNull);
      expect(imp.partida.atascoOfflineEn, 0);
    });

    test('con Guardia la pérdida cuenta al 100% y respeta su tope', () {
      final imp = _imperio(enMin: 60)..partida.alquilados['guardia'] = t0;
      final r = imp.aplicarOffline(t0, t0 + 2 * hora);
      expect(r.conGuardia, isTrue);
      expect(r.mjPerdidos, closeTo(3600 * 10, 1e-6));
      expect(r.ganado, closeTo(3600 * 10, 1e-6));
    });

    test('jugar con la app abierta borra el Atasco offline pendiente', () {
      final imp = _imperio(enMin: 30);
      imp.tick(t0 + 1000, 1);
      expect(imp.partida.atascoOfflineEn, 0);
    });
  });
}
