// Efectos de Tubería Express: partículas, textos flotantes, sacudida, destello, hitstop, la animación del mojón y la
// cámara. Todo vive en coordenadas del mundo (metros, y hacia arriba) y lo pinta tuberia_pintor.dart. Las partículas
// salen de un pool fijo (nada se crea por cuadro); los textos flotantes crean su TextPainter una vez al nacer.

import 'dart:math';

import 'package:flutter/painting.dart';

import '../../animaciones.dart';
import 'tuberia_logica.dart';

enum FormaParticula { cuadro, gota, papel, chispa }

class Particula {
  double x = 0, y = 0, vx = 0, vy = 0, vida = 0, total = 1, tam = 0.1, giro = 0, vGiro = 0, gravedad = -12;
  Color color = const Color(0xFF000000);
  FormaParticula forma = FormaParticula.cuadro;
  bool viva = false;
}

class TextoFlotante {
  TextoFlotante(this.x, this.y, this.relleno, this.borde, this.total);
  final double x, y, total;
  final TextPainter relleno, borde;
  double vida = 0;
}

class EfectosTuberia {
  EfectosTuberia({this.mov = Movimiento.completo, int semilla = 11}) : _azar = Random(semilla) {
    for (var i = 0; i < _maximo; i++) {
      particulas.add(Particula());
    }
  }

  final Movimiento mov;
  final Random _azar;
  final particulas = <Particula>[];
  final textos = <TextoFlotante>[];

  int get _maximo => switch (mov) { Movimiento.completo => 180, Movimiento.simple => 50, Movimiento.nada => 0 };

  double _sacudida = 0;
  double _tSacudida = 0;
  Offset desplazamiento = Offset.zero; // en píxeles, ya muestreado para este cuadro
  double destello = 0;
  Color colorDestello = const Color(0xFFFFFFFF);
  double _congelado = 0;
  double fase = 0; // reloj real, para lo que se mueve aunque estés quieto

  bool get congelado => _congelado > 0;

  void salpicar(double x, double y, int n,
      {required Color color, double fuerza = 4, FormaParticula forma = FormaParticula.cuadro, double arriba = 1,
      double tam = 0.12, double gravedad = -12, double vida = 0.7, double haciaX = 0}) {
    if (mov == Movimiento.nada) return;
    final cuantos = mov == Movimiento.simple ? (n / 3).ceil() : n;
    var hechos = 0;
    for (final p in particulas) {
      if (hechos >= cuantos) break;
      if (p.viva) continue;
      final a = _azar.nextDouble() * pi;
      final f = fuerza * (0.4 + 0.6 * _azar.nextDouble());
      p
        ..viva = true
        ..x = x
        ..y = y
        ..vx = cos(a) * f + haciaX
        ..vy = sin(a) * f * arriba
        ..vida = 0
        ..total = vida * (0.6 + 0.6 * _azar.nextDouble())
        ..tam = tam * (0.6 + 0.8 * _azar.nextDouble())
        ..giro = _azar.nextDouble() * 6.28
        ..vGiro = (_azar.nextDouble() - 0.5) * 14
        ..gravedad = gravedad
        ..color = color
        ..forma = forma;
      hechos++;
    }
  }

  /// Texto que sube y se desvanece. [tam] en píxeles lógicos.
  void texto(double x, double y, String s, {Color color = const Color(0xFFFFD60A), double tam = 20, double vida = 0.9}) {
    if (textos.length >= 8) textos.removeAt(0);
    final estilo = TextStyle(fontSize: tam, fontWeight: FontWeight.w900, letterSpacing: 0.5, height: 1);
    final relleno = TextPainter(text: TextSpan(text: s, style: estilo.copyWith(color: color)), textDirection: TextDirection.ltr)
      ..layout();
    final borde = TextPainter(
      text: TextSpan(
          text: s,
          style: estilo.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = tam * 0.22
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xE0201008))),
      textDirection: TextDirection.ltr,
    )..layout();
    textos.add(TextoFlotante(x, y, relleno, borde, vida));
  }

  void sacudir(double fuerza) {
    if (mov != Movimiento.completo) return;
    _sacudida = max(_sacudida, fuerza);
  }

  void destellar(Color c, double f) {
    if (mov == Movimiento.nada) return;
    colorDestello = c;
    destello = max(destello, f);
  }

  void hitstop(double s) {
    if (mov == Movimiento.nada) return;
    _congelado = max(_congelado, s);
  }

  /// [dt] real (no se congela con el hitstop). Devuelve el dt que debe usar la lógica.
  double avanzar(double dt) {
    fase += dt;
    var dtJuego = dt;
    if (_congelado > 0) {
      final usa = min(_congelado, dt);
      _congelado -= usa;
      dtJuego = dt - usa;
    }
    for (final p in particulas) {
      if (!p.viva) continue;
      p.vida += dt;
      if (p.vida >= p.total) {
        p.viva = false;
        continue;
      }
      final roce = p.forma == FormaParticula.papel ? 2.2 : 0.4;
      p.vx -= p.vx * roce * dt;
      p.vy += (p.gravedad - (p.forma == FormaParticula.papel ? p.vy * 2.4 : 0)) * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.giro += p.vGiro * dt;
    }
    for (final t in textos) {
      t.vida += dt;
    }
    textos.removeWhere((t) => t.vida >= t.total);
    if (destello > 0) destello = max(0, destello - dt * 3.2);
    if (_sacudida > 0.2) {
      _tSacudida += dt;
      desplazamiento = Offset(sin(_tSacudida * 71) * _sacudida, cos(_tSacudida * 57) * _sacudida * 0.8);
      _sacudida *= pow(0.0015, dt).toDouble();
    } else {
      _sacudida = 0;
      desplazamiento = Offset.zero;
    }
    return dtJuego;
  }
}

/// Cómo se ve el mojón: inclinación suavizada, resorte de aplaste, parpadeo y caras.
class AnimMojon {
  AnimMojon({this.mov = Movimiento.completo});
  final Movimiento mov;

  double inclinacion = 0;
  double aplaste = 0; // >0 aplastado, <0 estirado
  double _resorte = 0, _vResorte = 0;
  double _proxParpadeo = 2.2;
  double cerrado = 0; // 0 abiertos, 1 cerrados
  double mareo = 0; // segundos que quedan con ojos en X
  double alegria = 0; // segundos que quedan sonriendo fuerte
  double pujo = 0; // 0..1 suavizado
  double susto = 0; // 0..1 suavizado
  double giroExtra = 0; // vuelta de campana tras un plaf
  double mirarX = 1, mirarY = 0;

  void golpe(double f) {
    if (mov == Movimiento.nada) return;
    _vResorte += f;
  }

  void avanzar(double dt, JuegoTuberia j, double cercania) {
    final objetivo = j.enSuelo ? j.angulo : atan2(j.vy, max(0.5, j.vx)) * 0.7;
    inclinacion += (objetivo - inclinacion) * min(1, dt * 12);
    // Base: pujando se aplasta, en el aire se estira según la velocidad vertical.
    final base = j.pesado ? (j.enSuelo ? 0.14 : 0.06) : (j.enSuelo ? 0.0 : -min(0.16, j.vy.abs() / 60));
    _vResorte += (-_resorte * 260 - _vResorte * 13) * dt;
    _resorte += _vResorte * dt;
    _resorte = _resorte.clamp(-0.35, 0.45);
    aplaste = mov == Movimiento.nada ? 0 : (base + _resorte).clamp(-0.3, 0.45);
    pujo += ((j.pesado ? 1.0 : 0.0) - pujo) * min(1, dt * 10);
    susto += ((cercania > 0.55 ? 1.0 : 0.0) - susto) * min(1, dt * 5);
    if (mareo > 0) mareo = max(0, mareo - dt);
    if (alegria > 0) alegria = max(0, alegria - dt);
    if (giroExtra > 0) giroExtra = max(0, giroExtra - dt * 9);
    _proxParpadeo -= dt;
    if (_proxParpadeo <= 0) {
      cerrado = 1;
      _proxParpadeo = 2.0 + (j.tiempo * 7.3 % 2.5);
    } else {
      cerrado = max(0, cerrado - dt * 9);
    }
    // Mira hacia donde va; si el Atasco está cerca, mira para atrás de vez en cuando.
    var mx = j.vx, my = j.vy;
    if (cercania > 0.55 && sin(j.tiempo * 2.3) > 0.2) {
      mx = -1;
      my = 0.2;
    }
    final l = sqrt(mx * mx + my * my);
    if (l > 0.01) {
      mirarX += (mx / l - mirarX) * min(1, dt * 8);
      mirarY += (my / l - mirarY) * min(1, dt * 8);
    }
  }
}

/// Cámara con mirada adelante; se aleja cuando el mojón vuela alto.
class CamaraTuberia {
  double x = 0, y = 0, zoom = 1;
  double focoX = 0.32; // fracción del ancho donde va el punto mirado
  bool _primera = true;

  void avanzar(double dt, JuegoTuberia j, double cercania, {bool suave = true}) {
    // x sigue al mojón sin retraso; la mirada adelante va en focoX (más rápido = más a la izquierda, nunca fuera).
    final yo = (j.y + j.altura(j.x + 4)) / 2;
    final h = j.alturaSobreSuelo;
    final zo = (1 - max(0, h - 1.5) / 12).clamp(0.62, 1.0);
    final fo = 0.36 - 0.14 * (j.vx / JuegoTuberia.velocidadMaxima).clamp(0.0, 1.0) + 0.10 * cercania;
    x = j.x;
    if (_primera || !suave) {
      y = yo;
      zoom = zo;
      focoX = fo;
      _primera = false;
      return;
    }
    y += (yo - y) * min(1, dt * 4);
    zoom += (zo - zoom) * min(1, dt * 2.5);
    focoX += (fo - focoX) * min(1, dt * 2);
  }
}
