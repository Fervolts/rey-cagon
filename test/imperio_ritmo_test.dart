// Simulación de un jugador codicioso para medir el ritmo del Imperio.
// Pujo 5 veces por segundo, 3 sesiones de 10 min al día, 0,7 cagadas reales al día.
// Compra lo que se paga más rápido (espera + recuperación). Las aserciones son flojas a propósito.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int _seg = 1000;
const int _hora = 3600 * _seg;
const int _dia = 24 * _hora;
const List<int> _sesiones = [8, 14, 20]; // hora de inicio de cada sesión
const int _largoSesion = 600; // segundos
const double _cagadasPorDia = 0.7;
const int _dias = 14;

/// Una opción de compra y lo que rinde en MJ/s equivalentes.
class _Opcion {
  final String id;
  final bool esEdificio;
  final double precio;
  final double ganancia;
  _Opcion(this.id, this.esEdificio, this.precio, this.ganancia);
}

class _Simulacion {
  final Imperio imp;
  final Random azar;
  int activos = 0; // segundos de juego activo
  final Map<String, (int, int)> primeros = {}; // id → (segundos activos, día)
  int? mejorasEnUnaHora;
  _Simulacion(int semilla)
      : azar = Random(semilla),
        imp = Imperio(azar: Random(semilla + 1));

  /// Lo que deja el offline por día con la mejora puesta, convertido a MJ/s de juego activo.
  double _offlinePorSegActivo(Duration tope, double pct, double mps) {
    final hueco = (_dia - _sesiones.length * _largoSesion * _seg) / _sesiones.length / 1000;
    final contado = min(hueco, tope.inSeconds.toDouble());
    return _sesiones.length * contado * pct * mps / (_sesiones.length * _largoSesion);
  }

  double _ingresoPorSeg(int ahora) => imp.mpsSinEfectos(contarAtasco: false) + 5 * imp.valorPujo(ahora);

  List<_Opcion> _opciones(int ahora) {
    final p = imp.partida;
    final r = <_Opcion>[];
    final base = _ingresoPorSeg(ahora);
    for (final e in edificiosFase1) {
      if (!imp.edificioAbierto(e.id)) continue;
      p.edificios[e.id] = imp.cantidad(e.id) + 1;
      final con = _ingresoPorSeg(ahora);
      p.edificios[e.id] = imp.cantidad(e.id) - 1;
      if (p.edificios[e.id] == 0) p.edificios.remove(e.id);
      r.add(_Opcion(e.id, true, imp.precioEdificio(e.id, ahora), con - base));
    }
    final mps = imp.mpsSinEfectos(contarAtasco: false);
    final offlineAntes = _offlinePorSegActivo(imp.topeOffline, imp.porcentajeOffline, mps);
    for (final m in imp.mejorasDisponibles()) {
      p.mejoras.add(m.id);
      var ganancia = _ingresoPorSeg(ahora) - base;
      ganancia += _offlinePorSegActivo(imp.topeOffline, imp.porcentajeOffline, imp.mpsSinEfectos(contarAtasco: false)) - offlineAntes;
      p.mejoras.remove(m.id);
      // Imán y Brillo no suben el MJ/s: se compran si cuestan menos de 10 min de producción.
      if (m.familia == FamiliaMejora.dorado) ganancia = m.precio <= 600 * base ? double.infinity : 0;
      r.add(_Opcion(m.id, false, m.precio, ganancia));
    }
    return r;
  }

  void _comprar(int ahora) {
    for (var k = 0; k < 20; k++) {
      final ingreso = max(_ingresoPorSeg(ahora), 1e-9);
      _Opcion? mejor;
      var puntaje = double.infinity;
      for (final o in _opciones(ahora)) {
        if (o.ganancia <= 0) continue;
        final s = max(0.0, o.precio - imp.saldo) / ingreso + o.precio / o.ganancia;
        if (s < puntaje) {
          puntaje = s;
          mejor = o;
        }
      }
      if (mejor == null || mejor.precio > imp.saldo) return;
      final ok = mejor.esEdificio ? imp.comprarEdificio(mejor.id, ahora) : imp.comprarMejora(mejor.id);
      if (!ok) return;
      primeros.putIfAbsent(mejor.id, () => (activos, ahora ~/ _dia));
    }
  }

  void correr() {
    final siguienteCagada = <int>[];
    for (var t = 0.0; t < _dias * _dia; t += _dia / _cagadasPorDia) {
      siguienteCagada.add((t + _dia / _cagadasPorDia).round());
    }
    var finAnterior = -1;
    for (var d = 0; d < _dias; d++) {
      for (final h in _sesiones) {
        final inicio = d * _dia + h * _hora;
        if (finAnterior >= 0) imp.aplicarOffline(finAnterior, inicio);
        final nuevas = <CagadaReal>[];
        while (siguienteCagada.isNotEmpty && siguienteCagada.first <= inicio) {
          siguienteCagada.removeAt(0);
          nuevas.add(CagadaReal(tipo: 1 + azar.nextInt(7), creada: DateTime.utc(2026).add(Duration(milliseconds: inicio))));
        }
        if (nuevas.isNotEmpty) {
          imp.cagadas += nuevas.length;
          imp.fichas += nuevas.length;
          imp.aplicarCagadas(nuevas, inicio);
        }
        if (imp.fichas > 0) imp.activarCagadaFresca(inicio);
        for (var s = 0; s < _largoSesion; s++) {
          final ahora = inicio + s * _seg;
          for (var k = 0; k < 5; k++) {
            imp.pujar(ahora + k * 200);
          }
          imp.tick(ahora + _seg, 1);
          activos++;
          final dorado = imp.dorado(ahora + _seg);
          if (dorado != null && ahora + _seg - dorado.desde >= 2 * _seg) imp.tocarDorado(ahora + _seg);
          if (imp.atasco != null) {
            for (var k = 0; k < 10; k++) {
              imp.tocarAtasco(ahora + _seg + k * 100);
            }
          }
          _comprar(ahora + _seg);
          if (activos == 3600) mejorasEnUnaHora = imp.partida.mejoras.length;
        }
        finAnterior = inicio + _largoSesion * _seg;
      }
    }
  }
}

String _cuando((int, int)? x) {
  if (x == null) return 'nunca';
  final (s, d) = x;
  return '${(s / 60).toStringAsFixed(1)} min activos (día ${d + 1})';
}

void main() {
  test('ritmo de un jugador codicioso', () {
    final sim = _Simulacion(7)..correr();
    final imp = sim.imp;
    // ignore: avoid_print
    print([
      'Dedo: ${_cuando(sim.primeros['dedo'])}',
      'Ciruela: ${_cuando(sim.primeros['ciruela'])}',
      'Café: ${_cuando(sim.primeros['cafe'])}',
      'Arepa: ${_cuando(sim.primeros['arepa'])}',
      'Inodoro: ${_cuando(sim.primeros['inodoro'])}',
      'Baño: ${_cuando(sim.primeros['bano'])}',
      'Camión: ${_cuando(sim.primeros['camion'])}',
      'Planta: ${_cuando(sim.primeros['planta'])}',
      'Guantes: ${_cuando(sim.primeros['guantes'])}; Faja: ${_cuando(sim.primeros['faja'])}; mejoras en 1 h activa: ${sim.mejorasEnUnaHora}',
      'Al día $_dias: ${imp.cagadas} cagadas, ${imp.mps(0).toStringAsFixed(0)} MJ/s, ${imp.mjTotal.toStringAsExponential(2)} MJ, '
          '${imp.partida.edificios}, ${imp.partida.mejoras.length} mejoras, ${imp.partida.logros.length} logros',
    ].join('\n'));

    final dedo = sim.primeros['dedo'];
    final cafe = sim.primeros['cafe'];
    final inodoro = sim.primeros['inodoro'];
    expect(dedo, isNotNull);
    expect(dedo!.$1, lessThanOrEqualTo(60));
    expect(cafe, isNotNull);
    expect(cafe!.$1, lessThanOrEqualTo(25 * 60)); // ~15 min, con holgura
    expect(inodoro, isNotNull);
    expect(inodoro!.$2, lessThan(7)); // semana 1
  });
}
