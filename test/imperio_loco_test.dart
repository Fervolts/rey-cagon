// Simulación de un jugador que spamea (calibrada con la telemetría de uno real): 9 sesiones de 20 min al día (3 h),
// 7 pujos por segundo, 1,4 cagadas reales al día y 18 cagadas de antes (los candados no lo frenan). Compra lo que se
// paga más rápido. No jala la cadena, así que mide hasta dónde llega solo con MJ: el tope (la mejor compra tarda más de
// 20 h en pagarse) no debe llegar en la primera semana, cuando ya juntó las cagadas para jalar.
// Para afinar sin tocar el código: P=casual (3 sesiones de 10 min, 0,7 cagadas al día, 14 días), C (cagadas de antes),
// DIAS, G (precio_crecimiento), D (dedo_pujo), E (escala_edificios), M (escala_mejoras), K (cadena_divisor).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int _seg = 1000;
const int _hora = 3600 * _seg;
const int _dia = 24 * _hora;
final bool _casual = Platform.environment['P'] == 'casual';
final List<int> _sesiones = _casual ? [8, 14, 20] : [7, 9, 11, 13, 15, 17, 19, 21, 23]; // hora de inicio de cada sesión
final int _largoSesion = _casual ? 600 : 1200; // segundos
final double _cagadasPorDia = _casual ? 0.7 : 1.4;
final int _toques = _casual ? 5 : 7;
final int _dias = int.parse(Platform.environment['DIAS'] ?? (_casual ? '14' : '7'));

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
  final List<double> roiPorDia = []; // horas que tarda en pagarse la mejor compra, al final de cada día
  _Simulacion(int semilla)
      : azar = Random(semilla),
        imp = Imperio(azar: Random(semilla + 1), ajustes: Ajustes(precioCrecimiento: double.parse(Platform.environment['G'] ?? '1.15'), dedoPujo: double.parse(Platform.environment['D'] ?? '1'), escalaEdificios: double.parse(Platform.environment['E'] ?? '10'), escalaMejoras: double.parse(Platform.environment['M'] ?? '100'), cadenaDivisor: double.parse(Platform.environment['K'] ?? '1e8')));

  /// Lo que deja el offline por día con la mejora puesta, convertido a MJ/s de juego activo.
  double _offlinePorSegActivo(Duration tope, double pct, double mps) {
    final hueco = (_dia - _sesiones.length * _largoSesion * _seg) / _sesiones.length / 1000;
    final contado = min(hueco, tope.inSeconds.toDouble());
    return _sesiones.length * contado * pct * mps / (_sesiones.length * _largoSesion);
  }

  double _ingresoPorSeg(int ahora) => imp.mpsSinEfectos(contarAtasco: false) + _toques * imp.valorPujo(ahora);

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
      if (m.familia == FamiliaMejora.dorado) ganancia = imp.precioMejora(m) <= 600 * base ? double.infinity : 0;
      r.add(_Opcion(m.id, false, imp.precioMejora(m), ganancia));
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
    imp.cagadas = int.parse(Platform.environment['C'] ?? '18');
    imp.fichas = imp.cagadas;
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
        // Cada cagada real da x2 por 1 h desde que se hizo (aquí, al abrir la sesión).
        if (nuevas.isNotEmpty) imp.aplicarFrescaHasta(inicio + 3600000);
        for (var s = 0; s < _largoSesion; s++) {
          final ahora = inicio + s * _seg;
          for (var k = 0; k < _toques; k++) {
            imp.pujar(ahora + k * 140);
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
      final ops = _opciones(d * _dia + 23 * _hora).where((o) => o.ganancia > 0 && o.ganancia.isFinite);
      final roi = ops.isEmpty ? 0.0 : ops.map((o) => o.precio / o.ganancia).reduce(min) / 3600;
      roiPorDia.add(roi);
      // ignore: avoid_print
      print('día ${d + 1}: roi ${roi.toStringAsFixed(1)} h, ${(activos / 3600).toStringAsFixed(1)} h, ${imp.mjTotal.toStringAsExponential(2)} MJ, ${imp.mps(0).toStringAsExponential(2)} MJ/s, pujo ${imp.valorPujo(0).toStringAsExponential(2)}, ${imp.partida.edificios}');
    }
  }
}

String _cuando((int, int)? x) {
  if (x == null) return 'nunca';
  final (s, d) = x;
  return '${(s / 60).toStringAsFixed(1)} min activos (día ${d + 1})';
}

void main() {
  test('un jugador que spamea no llega al tope en la primera semana', () {
    final sim = _Simulacion(7)..correr();
    final imp = sim.imp;
    // ignore: avoid_print
    print([
      'Dedo: ${_cuando(sim.primeros['dedo'])}',
      'Ciruela: ${_cuando(sim.primeros['ciruela'])}',
      'Café: ${_cuando(sim.primeros['cafe'])}',
      'Arepa: ${_cuando(sim.primeros['arepa'])}',
      'Bidet: ${_cuando(sim.primeros['inodoro'])}',
      'Baño: ${_cuando(sim.primeros['bano'])}',
      'Camión: ${_cuando(sim.primeros['camion'])}',
      'Planta: ${_cuando(sim.primeros['planta'])}',
      'Guantes: ${_cuando(sim.primeros['guantes'])}; Faja: ${_cuando(sim.primeros['faja'])}; mejoras en 1 h activa: ${sim.mejorasEnUnaHora}',
      'Al día $_dias: ${imp.cagadas} cagadas, ${imp.mps(0).toStringAsFixed(0)} MJ/s, ${imp.valorPujo(0).toStringAsFixed(0)} MJ/pujo, '
          '${imp.mjTotal.toStringAsExponential(2)} MJ, '
          '${imp.partida.edificios}, ${imp.partida.mejoras.length} mejoras, ${imp.partida.logros.length} logros',
    ].join('\n'));
    if (_casual || Platform.environment.keys.any(const {'C', 'DIAS', 'G', 'D', 'E', 'M', 'K'}.contains)) return; // afinando
    for (var d = 0; d < 7; d++) {
      expect(sim.roiPorDia[d], lessThan(20), reason: 'día ${d + 1}: la mejor compra tarda ${sim.roiPorDia[d].toStringAsFixed(1)} h');
    }
    // Pero tampoco se lo come: la Planta no sale en las primeras 3 h de juego.
    expect(sim.primeros['planta']?.$1 ?? 1 << 30, greaterThan(3 * 3600));
  });
}
