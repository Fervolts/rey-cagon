// Tubería Express (surf de una mano): contrato de puntos con bots tontos, normales y buenos, fin de partida,
// determinismo con semilla y la vista montada en los tres niveles de movimiento.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/minijuegos/tuberia_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/tuberia_vista.dart';

typedef Bot = bool Function(JuegoTuberia j, Random r);

/// Aprieta y suelta al azar.
bool botMalo(JuegoTuberia j, Random r) => r.nextDouble() < 0.5;

bool _veCucaracha(JuegoTuberia j) => j.enSuelo && j.cucarachas.any((c) => c.viva && c.x - j.x > -0.3 && c.x - j.x < 1.6);

/// Pesado en bajada, liviano en subida, con errores.
bool botNormal(JuegoTuberia j, Random r) {
  if (r.nextDouble() < 0.25) return r.nextBool();
  if (_veCucaracha(j) && r.nextDouble() < 0.5) return true;
  if (!j.enSuelo) return j.vy < 0 && j.alturaSobreSuelo < 2.0;
  return j.pendiente(j.x) < 0;
}

// Predice dónde cae con gravedad g; devuelve el ángulo de llegada contra la ladera (castiga caer en subida).
double _caida(JuegoTuberia j, double g) {
  var x = j.x, y = j.y, vx = j.vx, vy = j.vy;
  for (var i = 0; i < 400; i++) {
    vy -= g / 60;
    x += vx / 60;
    y += vy / 60;
    if (y <= j.altura(x)) {
      final d = j.pendiente(x);
      final a = (atan2(vy, vx) - atan(d)).abs();
      return d < -0.08 ? a : 10 + a;
    }
  }
  return 20;
}

/// Aprieta en bajada, aplasta cucarachas y en el aire elige la gravedad que cae mejor alineada.
bool botBueno(JuegoTuberia j, Random r) {
  if (_veCucaracha(j)) return true;
  if (!j.enSuelo) {
    final liviano = _caida(j, JuegoTuberia.gravedad);
    final pesado = _caida(j, JuegoTuberia.gravedad * JuegoTuberia.factorPesado);
    return pesado + 0.05 < liviano;
  }
  return j.pendiente(j.x) < -0.02;
}

/// Juega a 60 fps hasta el final. [cambio] > 0: el bot solo decide cada tanto (el malo). Revisa el contrato cada cuadro.
JuegoTuberia jugar(int semilla, Bot bot, {double cambio = 0, double dt = 1 / 60}) {
  final j = JuegoTuberia(azar: Random(semilla));
  final r = Random(1000 + semilla);
  var p = false, siguiente = 0.0;
  while (!j.terminado) {
    if (cambio > 0) {
      if (j.tiempo >= siguiente) {
        p = bot(j, r);
        siguiente = j.tiempo + cambio * r.nextDouble() * 2;
      }
    } else {
      p = bot(j, r);
    }
    j.presionado = p;
    j.avanzar(dt);
    j.tomarSucesos();
    expect(j.puntos, lessThanOrEqualTo(((j.tiempo + 1) * JuegoTuberia.pps).floor()), reason: 'semilla $semilla t ${j.tiempo}');
    expect(j.puntos, lessThanOrEqualTo(JuegoTuberia.tope));
    expect(j.tiempo, lessThanOrEqualTo(JuegoTuberia.tiempoMaximo + 0.1));
  }
  return j;
}

double _mediana(List<double> v) => (v..sort())[v.length ~/ 2];

void main() {
  group('contrato con bots', () {
    test('bot malo: pierde pronto pero dura más de 2 s', () {
      final d = <double>[], t = <double>[];
      for (var s = 0; s < 10; s++) {
        final j = jugar(s, botMalo, cambio: 0.35);
        expect(j.tiempo, greaterThan(2));
        d.add(j.distancia);
        t.add(j.tiempo);
      }
      expect(_mediana(d), inInclusiveRange(100, 400));
      expect(_mediana(t), inInclusiveRange(15, 70));
    });

    test('bot normal: llega a varios cientos de metros', () {
      final d = <double>[];
      for (var s = 0; s < 10; s++) {
        d.add(jugar(s, botNormal).distancia);
      }
      expect(_mediana(d), inInclusiveRange(400, 1100));
    });

    test('bot bueno: pasa de 2000 m y respeta el contrato en partidas largas', () {
      final d = <double>[];
      for (var s = 0; s < 4; s++) {
        final j = jugar(s, botBueno);
        d.add(j.distancia);
        expect(j.limpios, greaterThan(j.plafs));
      }
      expect(_mediana(d), greaterThan(2000));
    });

    test('a cuadros lentos (dt 0.05) el contrato se cumple igual', () {
      for (var s = 0; s < 3; s++) {
        jugar(s, botNormal, dt: 0.05);
      }
    });
  });

  group('reglas', () {
    test('sin tocar, el Atasco lo alcanza y avisa una sola vez', () {
      final j = JuegoTuberia(azar: Random(1));
      var atrapados = 0;
      for (var i = 0; i < 60 * 600 && !j.terminado; i++) {
        j.avanzar(1 / 60);
        atrapados += j.tomarSucesos().where((s) => s.tipo == TipoSuceso.atrapado).length;
      }
      expect(j.terminado, isTrue);
      expect(atrapados, 1);
      expect(j.distancia, greaterThan(10));
      final p = j.puntos;
      j.avanzar(1);
      expect(j.puntos, p);
      expect(j.tomarSucesos(), isEmpty);
    });

    test('cortar() termina por tiempo una vez', () {
      final j = JuegoTuberia(azar: Random(2));
      j.avanzar(1);
      j.cortar();
      j.cortar();
      final s = j.tomarSucesos().where((s) => s.tipo == TipoSuceso.atrapado).toList();
      expect(j.terminado, isTrue);
      expect(s, hasLength(1));
      expect(s.first.valor, 1);
    });

    test('apretar y soltar cambian el peso', () {
      final j = JuegoTuberia(azar: Random(3));
      expect(j.pesado, isFalse);
      j.apretar();
      expect(j.pesado, isTrue);
      j.soltar();
      expect(j.pesado, isFalse);
      j.presionado = true;
      expect(j.pesado, isTrue);
    });

    test('la velocidad nunca pasa del máximo y el terreno es continuo', () {
      final j = JuegoTuberia(azar: Random(4));
      final r = Random(4);
      for (var i = 0; i < 60 * 120 && !j.terminado; i++) {
        j.presionado = botBueno(j, r);
        j.avanzar(1 / 60);
        expect(j.velocidad, lessThanOrEqualTo(JuegoTuberia.velocidadMaxima + 1e-6));
      }
      for (var x = j.x; x < j.x + 100; x += 0.25) {
        expect((j.altura(x + 0.05) - j.altura(x)).abs(), lessThan(0.5));
      }
    });

    test('las zonas cambian cada 400 m en orden', () {
      expect(JuegoTuberia.zonaEn(0), 0);
      expect(JuegoTuberia.zonaEn(399), 0);
      expect(JuegoTuberia.zonaEn(401), 1);
      expect(JuegoTuberia.zonaEn(1650), 4);
      final j = jugar(0, botBueno);
      expect(j.zona, greaterThanOrEqualTo(4));
    });

    test('el Atasco acelera con el tiempo', () {
      expect(JuegoTuberia.velocidadAtascoEn(200), greaterThan(JuegoTuberia.velocidadAtascoEn(10)));
    });

    test('misma semilla, misma partida', () {
      final a = jugar(7, botNormal), b = jugar(7, botNormal);
      expect(a.puntos, b.puntos);
      expect(a.distancia, b.distancia);
      expect(a.tiempo, b.tiempo);
      expect(a.limpios, b.limpios);
    });
  });

  for (final mov in Movimiento.values) {
    testWidgets('la vista juega, el Atasco lo alcanza y entrega puntos y ms ($mov)', (t) async {
      int? puntos, ms;
      var veces = 0;
      final j = JuegoTuberia(azar: Random(3), separacion: 6);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VistaTuberia(
            juego: j,
            mov: mov,
            alTerminar: (p, m) {
              veces++;
              (puntos, ms) = (p, m);
            },
          ),
        ),
      ));
      expect(find.byKey(const Key('tuberia_metros')), findsOneWidget);
      final gesto = await t.startGesture(t.getCenter(find.byKey(const Key('tuberia_toque'))));
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(j.pesado, isTrue);
      await gesto.up();
      await t.pump(const Duration(milliseconds: 16));
      expect(j.pesado, isFalse);
      for (var i = 0; i < 6000 && !j.terminado; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(j.terminado, isTrue);
      await t.pump(const Duration(milliseconds: 1100));
      expect(veces, 1);
      expect(puntos, j.puntos);
      expect(ms, greaterThanOrEqualTo((j.tiempo * 1000).floor()));
      expect(puntos!, lessThanOrEqualTo((ms! / 1000 + 1) * JuegoTuberia.pps));
      await t.pumpWidget(const SizedBox());
    });
  }
}
