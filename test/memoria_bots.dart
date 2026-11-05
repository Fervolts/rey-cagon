// Bots para probar Fusión real: uno que suelta al azar, uno normal y uno bueno.
import 'dart:math';

import 'package:rey_cagon/imperio/minijuegos/memoria_logica.dart';

enum TipoBot { malo, normal, bueno }

class ResultadoBot {
  ResultadoBot(this.puntos, this.ms, this.desbordo, this.nivelMasAlto, this.reyes, this.soltadas);
  final int puntos, ms, nivelMasAlto, reyes, soltadas;
  final bool desbordo;
}

double elegirX(JuegoFusion j, Random rng, double ruido, {bool listo = false}) {
  final r = radioDe(j.actual);
  var mejor = 0.0, mejorP = -1e9;
  const n = 31;
  final miedo = j.peligro;
  for (var i = 0; i < n; i++) {
    final x = -mitadAncho + r + (2 * (mitadAncho - r)) * i / (n - 1);
    final y = j.alturaDeCaida(x, r);
    var p = y * (0.4 + (listo ? miedo * 2.5 : 0));
    var igual = false;
    for (final m in j.mojones) {
      final dx = m.x - x, dy = m.y - y;
      final d = sqrt(dx * dx + dy * dy);
      if (d > r + m.r + 2) continue;
      if (m.nivel == j.actual) {
        igual = true;
        p += 80;
        if (listo) {
          // Si el que nace toca a uno de su nivel, mejor (cadena).
          for (final o in j.mojones) {
            if (o != m && o.nivel == j.actual + 1) {
              final ex = o.x - m.x, ey = o.y - m.y;
              if (sqrt(ex * ex + ey * ey) < o.r + radioDe(j.actual + 1) + 3) p += 40;
            }
          }
        }
      } else if (m.nivel < j.actual) {
        p -= listo ? 45 : 25;
      } else if (m.nivel == j.actual + 1) {
        p += 8;
      }
    }
    if (listo && !igual) {
      // Los grandes a un lado (izquierda), los chicos a la derecha.
      p += (j.actual >= 3 ? -x : x) * 0.25;
    } else if (!listo) {
      p += (j.actual >= 3 ? 1 : -1) * x.abs() * 0.15;
    }
    p += (rng.nextDouble() - 0.5) * ruido;
    if (p > mejorP) {
      mejorP = p;
      mejor = x;
    }
  }
  return mejor;
}

/// Bot que mira adelante: prueba varias x en una copia de la poceta, simula 1.2 s y se queda con la mejor.
double elegirXMirando(JuegoFusion j, Random rng) {
  final r = radioDe(j.actual);
  var mejor = 0.0, mejorP = -1e9;
  const n = 17;
  for (var i = 0; i < n; i++) {
    final x = -mitadAncho + r + (2 * (mitadAncho - r)) * i / (n - 1);
    final c = JuegoFusion(semilla: 1);
    for (final m in j.mojones) {
      if (!m.vivo) continue;
      c.mojones.add(Mojon(m.id, m.nivel, m.x, m.y)
        ..px = m.px
        ..py = m.py
        ..r = m.r
        ..edad = 2
        ..tocado = true);
    }
    c.actual = j.actual;
    c.apuntar(x);
    c.soltar();
    for (var k = 0; k < 72; k++) {
      c.avanzar(pasoFijo);
    }
    var tope = 200.0, suma = 0.0;
    for (final m in c.mojones) {
      tope = min(tope, m.y - m.r);
      suma += m.nivel * m.nivel;
    }
    var p = c.fusiones * 14.0 + c.puntosCrudos * 2.0 + tope * (0.5 + j.peligro * 2) - c.mojones.length * 3 + suma * 0.01;
    // Pequeño empujón al heurístico simple para desempatar (que toque a uno igual).
    for (final m in j.mojones) {
      if (m.nivel == j.actual && (m.x - x).abs() < m.r + r + 2) p += 4;
    }
    p += rng.nextDouble() * 0.5;
    if (p > mejorP) {
      mejorP = p;
      mejor = x;
    }
  }
  return mejor;
}

ResultadoBot jugarBot(TipoBot tipo, int semilla, {double dt = 1 / 60, int piezasInicio = 0}) {
  final j = JuegoFusion(semilla: semilla, piezasInicio: piezasInicio);
  final rng = Random(semilla * 31 + tipo.index);
  var proximo = 0.3;
  var ms = 0.0;
  var soltadas = 0;
  while (!j.terminado && ms < maxMsFusion) {
    j.avanzar(dt);
    ms += dt * 1000;
    j.tomarSucesos();
    if (j.t >= proximo && j.puedeSoltar) {
      switch (tipo) {
        case TipoBot.malo:
          j.apuntar(-50 + rng.nextDouble() * 100);
          proximo = j.t + 0.55 + rng.nextDouble() * 0.4;
        case TipoBot.normal:
          j.apuntar(elegirX(j, rng, 160));
          proximo = j.t + 0.9 + rng.nextDouble() * 0.6;
          if (j.palancaLista && j.peligro > 0.7) j.jalarPalanca();
        case TipoBot.bueno:
          j.apuntar(elegirXMirando(j, rng));
          proximo = j.t + 0.95 + rng.nextDouble() * 0.3;
          if (j.palancaLista && j.peligro > 0.6) j.jalarPalanca();
      }
      if (j.soltar()) soltadas++;
    }
  }
  // Igual que la vista: sin reloj una partida puede pasar del máximo del servidor, y se reporta justo debajo.
  final reportado = ms.round().clamp(minMsFusion, maxMsFusion - 1);
  return ResultadoBot(puntosReportables(j.puntosCrudos, reportado), reportado, j.motivoDesborde, j.nivelMasAlto, j.reyes, soltadas);
}
