import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/minijuegos/tuberia_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/tuberia_vista.dart';

/// Bot perfecto: mira lo más cercano por delante (codo sin pasar o rollo sin resolver) y se pone en el carril que pide.
void jugarPerfecto(JuegoTuberia j) {
  final d = j.distancia;
  double mejor = double.infinity;
  int? pide;
  for (final c in j.codos) {
    if (c.distancia > d - JuegoTuberia.radioCodo - 0.2 && c.distancia < mejor) {
      mejor = c.distancia;
      pide = 1 - c.carril;
    }
  }
  for (final r in j.rollos) {
    if (!r.resuelto && r.distancia < mejor) {
      mejor = r.distancia;
      pide = r.carril;
    }
  }
  if (pide != null && pide != j.carril) j.toque();
}

/// Juega con [bot] a pasos de 60 fps; devuelve el peor exceso sobre 16 puntos por segundo (negativo = nunca pasó).
double jugar(JuegoTuberia j, void Function(JuegoTuberia) bot, {int maxPasos = 200000}) {
  var peor = -double.infinity;
  for (var i = 0; i < maxPasos && j.vivo; i++) {
    bot(j);
    j.avanzar(1 / 60);
    peor = max(peor, j.puntos - 16 * (j.tiempo + 1));
  }
  return peor;
}

void main() {
  test('partida perfecta llega a la planta, bajo el tope y el anti-trampa del servidor', () {
    for (final semilla in [1, 2, 3, 7, 42]) {
      final j = JuegoTuberia(azar: Random(semilla));
      final peor = jugar(j, jugarPerfecto);
      // ignore: avoid_print
      print('semilla $semilla: ${j.puntos} pts, ${j.tiempo.toStringAsFixed(1)} s, ${j.distancia.round()} m, '
          'rollos ${j.rollosAgarrados}, casis ${j.casis}, racha max ${j.rachaMaxima}, '
          'pps ${(j.puntos / j.tiempo).toStringAsFixed(2)}, techo ${(JuegoTuberia.ppsSeguro * (j.tiempo + 1)).floor()}');
      expect(j.llego, isTrue, reason: 'semilla $semilla chocó en ${j.distancia.round()} m');
      expect(peor, lessThan(0));
      expect(j.puntos, lessThan(10000));
      expect(j.tiempo * 1000, lessThan(1200000 / 2));
      // El techo de seguridad no debería morder en una partida limpia.
      expect(j.puntos, lessThan((JuegoTuberia.ppsSeguro * (j.tiempo + 1)).floor()));
    }
  });

  test('la dureza y la velocidad suben con los metros y nunca pasan el máximo', () {
    var antes = -1.0;
    var vAntes = 0.0;
    for (var d = 0.0; d <= JuegoTuberia.meta; d += 25) {
      final h = JuegoTuberia.dureza(d);
      final v = JuegoTuberia.velocidadBase(d);
      expect(h, greaterThanOrEqualTo(antes));
      expect(v, greaterThanOrEqualTo(vAntes));
      expect(v * JuegoTuberia.empujeDescarga, lessThanOrEqualTo(JuegoTuberia.velocidadMaxima + 1e-9));
      antes = h;
      vAntes = v;
    }
    expect(JuegoTuberia.velocidadMaxima, lessThan(16));
  });

  test('la descarga empuja más rápido y avisa antes', () {
    final j = JuegoTuberia(azar: Random(5));
    var aviso = false, descarga = false, vDescarga = 0.0, vBase = 0.0;
    for (var i = 0; i < 200000 && j.vivo && !descarga; i++) {
      jugarPerfecto(j);
      j.avanzar(1 / 60);
      for (final s in j.tomarSucesos()) {
        if (s.tipo == TipoSuceso.avisoDescarga) aviso = true;
        if (s.tipo == TipoSuceso.descarga) {
          descarga = true;
          vDescarga = j.velocidad;
          vBase = JuegoTuberia.velocidadBase(j.distancia);
        }
      }
    }
    expect(aviso, isTrue);
    expect(descarga, isTrue);
    expect(vDescarga, closeTo(vBase * JuegoTuberia.empujeDescarga, 0.01));
  });

  test('rollos seguidos suben el multiplicador y perder uno lo resetea', () {
    final j = JuegoTuberia(azar: Random(9));
    var subio = false, perdido = false;
    for (var i = 0; i < 60000 && j.vivo; i++) {
      jugarPerfecto(j);
      j.avanzar(1 / 60);
      for (final s in j.tomarSucesos()) {
        if (s.tipo == TipoSuceso.multiplicador) subio = true;
      }
    }
    expect(subio, isTrue);
    // Perfecto hasta los 60 m; después solo esquiva codos y deja pasar rollos: la racha se rompe.
    final k = JuegoTuberia(azar: Random(9));
    var rachaAlPerder = -1;
    for (var i = 0; i < 60000 && k.vivo && !perdido; i++) {
      if (k.distancia < 60) {
        jugarPerfecto(k);
      } else {
        for (final c in k.codos) {
          final dd = c.distancia - k.distancia;
          if (dd > -JuegoTuberia.radioCodo && dd < 6 && c.carril == k.carril) {
            k.toque();
            break;
          }
        }
      }
      k.avanzar(1 / 60);
      for (final s in k.tomarSucesos()) {
        if (s.tipo == TipoSuceso.perdido) {
          perdido = true;
          rachaAlPerder = s.valor;
        }
      }
    }
    expect(perdido, isTrue);
    expect(rachaAlPerder, greaterThan(0));
    expect(k.racha, 0);
    expect(k.multiplicador, 1);
  });

  test('pista enseña tocar, después esquivar', () {
    final j = JuegoTuberia(azar: Random(1));
    expect(j.pista, PistaTuberia.toca);
    j.toque();
    // Al carril 1: va a agarrar los rollos del intro y luego el codo del carril 1 pide esquivar.
    for (var i = 0; i < 2000 && j.distancia < 16; i++) {
      j.avanzar(1 / 60);
    }
    expect(j.rollosAgarrados, 2);
    expect(j.pista, PistaTuberia.esquiva);
  });

  test('un jugador humano (reacción de 0.3 s, algún error) muere a mitad de camino', () {
    final puntos = <int>[];
    for (final semilla in [11, 12, 13, 14, 15, 16, 17, 18]) {
      final j = JuegoTuberia(azar: Random(semilla));
      final azar = Random(semilla * 7);
      double? tocarEn;
      Object? visto;
      jugar(j, (j) {
        if (tocarEn != null && j.tiempo >= tocarEn!) {
          j.toque();
          tocarEn = null;
        }
        if (tocarEn != null) return;
        // Lo más cercano por delante que pida cambiar de carril.
        final d = j.distancia;
        double mejor = double.infinity;
        Object? cosa;
        int? pide;
        for (final c in j.codos) {
          if (c.distancia > d && c.distancia < mejor) {
            mejor = c.distancia;
            pide = 1 - c.carril;
            cosa = c;
          }
        }
        for (final r in j.rollos) {
          if (!r.resuelto && r.distancia > d && r.distancia < mejor) {
            mejor = r.distancia;
            pide = r.carril;
            cosa = r;
          }
        }
        if (pide == null || pide == j.carril || identical(cosa, visto)) return;
        visto = cosa;
        if (azar.nextDouble() < 0.02) return; // se le pasó
        tocarEn = j.tiempo + 0.26 + azar.nextDouble() * 0.12;
      });
      expect(j.puntos, lessThan(16000));
      puntos.add(j.puntos);
    }
    // ignore: avoid_print
    print('humano: $puntos');
    puntos.sort();
    // La mediana cae en el rango de una partida normal (meta del día 600).
    expect(puntos[puntos.length ~/ 2], inInclusiveRange(150, 3000));
  });

  for (final mov in Movimiento.values) {
    testWidgets('la vista juega, choca y entrega puntos y ms ($mov)', (t) async {
      int? puntos, ms;
      final j = JuegoTuberia(azar: Random(3));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: VistaTuberia(juego: j, mov: mov, alTerminar: (p, m) => (puntos, ms) = (p, m))),
      ));
      expect(find.byKey(const Key('tuberia_metros')), findsOneWidget);
      await t.tap(find.byKey(const Key('tuberia_toque')));
      // Sin tocar más, tarde o temprano un codo lo atasca.
      for (var i = 0; i < 3000 && !j.terminado; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(j.terminado, isTrue);
      await t.pump(const Duration(milliseconds: 1100));
      expect(puntos, j.puntos);
      expect(ms, isNotNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
