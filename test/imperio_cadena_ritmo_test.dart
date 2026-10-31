// Simulación larga del Imperio con la cadena: el mismo jugador codicioso de imperio_ritmo_test (5 pujos por segundo,
// 3 sesiones de 10 min al día, 0,7 cagadas reales al día) pero durante 230 días y jalando la cadena.
//
// Regla para jalar (al empezar cada sesión): se puede jalar (cadena desbloqueada, `cadenaCagadas` cagadas desde la
// última jalada, al menos 1 rollo por ganar) y la jalada da al menos max(1, rollos actuales × 0,5). Si la corrida ya
// pasó de 14 días, basta con max(1, rollos × 0,1): un jugador de verdad no se queda trancado esperando para siempre.
//
// Además, de coleccionista: una mejora que cuesta menos de 1 min de ingreso se compra aunque casi no rinda, y si a un
// edificio le faltan unidades para su próxima mejora de nivel (y ya hay los rollos que pide) y todas juntas cuestan menos
// de 1 min de ingreso, se completan.
//
// Para ir más rápido que la simulación corta, compra cada 5 s de juego (hasta 300 compras seguidas, que al volver del
// offline sobra plata) en vez de cada segundo. Las aserciones son flojas a propósito; lo importante es lo que imprime.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int _seg = 1000;
const int _hora = 3600 * _seg;
const int _dia = 24 * _hora;
const List<int> _sesiones = [8, 14, 20];
const int _largoSesion = 600;
const double _cagadasPorDia = 0.7;
const int _dias = 230;

class _Opcion {
  final String id;
  final bool esEdificio;
  final double precio;
  final double ganancia;
  _Opcion(this.id, this.esEdificio, this.precio, this.ganancia);
}

/// Una corrida entre jaladas.
class _Corrida {
  final int dia;
  int? fin;
  int rollosGanados = 0;
  int rollosTotal = 0;
  String masAlto = '-';
  int cantidadMasAlto = 0;
  double mjCorrida = 0;
  _Corrida(this.dia);
}

class _Simulacion {
  final Imperio imp;
  final Random azar;
  final Map<String, int> primerDia = {}; // edificio o mejora → día en que se compró por primera vez
  final List<_Corrida> corridas = [_Corrida(0)];
  int cagadasDesde = 0;
  double mjAlEmpezar = 0;
  _Simulacion(int semilla, Ajustes ajustes)
      : azar = Random(semilla),
        imp = Imperio(azar: Random(semilla + 1), ajustes: ajustes);

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
    for (final e in edificios) {
      if (!imp.edificioAbierto(e.id)) continue;
      p.edificios[e.id] = imp.cantidad(e.id) + 1;
      final con = _ingresoPorSeg(ahora);
      p.edificios[e.id] = imp.cantidad(e.id) - 1;
      if (p.edificios[e.id] == 0) p.edificios.remove(e.id);
      var ganancia = con - base;
      // Coleccionista: si le falta poco para la mejora de su próximo nivel (ya con los rollos que pide), completa las
      // unidades cuando todas juntas cuestan menos de 1 min de ingreso.
      final n = imp.cantidad(e.id);
      for (final (nivel, _) in nivelesMejoraEdificio) {
        if (n >= nivel || p.mejoras.contains(idMejoraEdificio(e.id, nivel))) continue;
        if (p.rollos < (rollosNivelMejora[nivel] ?? 0)) break;
        final faltan = nivel - n;
        final costo = imp.precioEdificio(e.id, ahora) * (pow(imp.ajustes.precioCrecimiento, faltan) - 1) / (imp.ajustes.precioCrecimiento - 1);
        if (costo <= 60 * base) ganancia = double.infinity;
        break;
      }
      r.add(_Opcion(e.id, true, imp.precioEdificio(e.id, ahora), ganancia));
    }
    final mps = imp.mpsSinEfectos(contarAtasco: false);
    final offlineAntes = _offlinePorSegActivo(imp.topeOffline, imp.porcentajeOffline, mps);
    for (final m in imp.mejorasDisponibles()) {
      p.mejoras.add(m.id);
      var ganancia = _ingresoPorSeg(ahora) - base;
      ganancia += _offlinePorSegActivo(imp.topeOffline, imp.porcentajeOffline, imp.mpsSinEfectos(contarAtasco: false)) - offlineAntes;
      p.mejoras.remove(m.id);
      // Imán y Brillo no suben el MJ/s; la cadena tampoco, pero abre las jaladas: se compran si cuestan menos de 10 min.
      if (m.familia == FamiliaMejora.dorado || m.id == 'cadena_trono') ganancia = m.precio <= 600 * base ? double.infinity : 0;
      // Las que ya casi no rinden (un x2 a un edificio viejo) se compran igual cuando cuestan menos de 1 min de ingreso,
      // como haría cualquiera que quiere la colección completa.
      if (m.precio <= 60 * base) ganancia = double.infinity;
      r.add(_Opcion(m.id, false, m.precio, ganancia));
    }
    return r;
  }

  void _comprar(int ahora) {
    for (var k = 0; k < 300; k++) {
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
      primerDia.putIfAbsent(mejor.id, () => ahora ~/ _dia);
    }
  }

  void _cerrarCorrida(int dia) {
    final c = corridas.last;
    c.fin = dia;
    c.mjCorrida = imp.mjTotal - mjAlEmpezar;
    for (final e in edificios.reversed) {
      if (imp.cantidad(e.id) > 0) {
        c.masAlto = e.id;
        c.cantidadMasAlto = imp.cantidad(e.id);
        break;
      }
    }
  }

  void _quizasJalar(int inicio) {
    final dia = inicio ~/ _dia;
    final rollos = imp.partida.rollos;
    final largo = dia - corridas.last.dia;
    final minimo = max(1, (rollos * (largo > 14 ? 0.1 : 0.5)).ceil());
    if (!imp.puedeJalar(cagadasDesde, imp.ajustes.cadenaCagadas) || imp.rollosPorGanar < minimo) return;
    _cerrarCorrida(dia);
    final ganados = imp.jalar();
    corridas.last
      ..rollosGanados = ganados
      ..rollosTotal = imp.partida.rollos;
    corridas.add(_Corrida(dia));
    cagadasDesde = 0;
    mjAlEmpezar = imp.mjTotal;
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
          cagadasDesde += nuevas.length;
          imp.aplicarCagadas(nuevas, inicio);
        }
        _quizasJalar(inicio);
        if (imp.fichas > 0) imp.activarCagadaFresca(inicio);
        for (var s = 0; s < _largoSesion; s++) {
          final ahora = inicio + s * _seg;
          for (var k = 0; k < 5; k++) {
            imp.pujar(ahora + k * 200);
          }
          imp.tick(ahora + _seg, 1);
          final dorado = imp.dorado(ahora + _seg);
          if (dorado != null && ahora + _seg - dorado.desde >= 2 * _seg) imp.tocarDorado(ahora + _seg);
          if (imp.atasco != null) {
            for (var k = 0; k < 10; k++) {
              imp.tocarAtasco(ahora + _seg + k * 100);
            }
          }
          if (s % 5 == 0) _comprar(ahora + _seg);
        }
        finAnterior = inicio + _largoSesion * _seg;
      }
    }
    _cerrarCorrida(_dias);
  }
}

void main() {
  test('la cadena lleva a todos los edificios y mejoras', () {
    final sim = _Simulacion(7, Ajustes.porDefecto)..correr();
    final imp = sim.imp;
    final lineas = <String>['Corridas (día de inicio, días, MJ de la corrida, rollos ganados, rollos en total, edificio más alto):'];
    for (var i = 0; i < sim.corridas.length; i++) {
      final c = sim.corridas[i];
      lineas.add('  #${i + 1}: día ${c.dia + 1}, ${(c.fin ?? _dias) - c.dia} d, ${c.mjCorrida.toStringAsExponential(2)} MJ, '
          '${i == sim.corridas.length - 1 ? 'sin jalar' : '+${c.rollosGanados} 🧻 (=${c.rollosTotal})'}, '
          '${c.masAlto} x${c.cantidadMasAlto}');
    }
    lineas.add('Primer día de compra de cada edificio:');
    for (final e in edificios) {
      final d = sim.primerDia[e.id];
      lineas.add('  ${e.id}: ${d == null ? 'nunca' : 'día ${d + 1}'}');
    }
    final faltan = [for (final m in mejoras) if (!sim.primerDia.containsKey(m.id)) m.id];
    final ultimaMejora = [for (final m in mejoras) sim.primerDia[m.id] ?? -1].reduce(max);
    lineas.add('Mejoras nunca compradas: ${faltan.isEmpty ? 'ninguna' : faltan.join(', ')}; la última salió el día ${ultimaMejora + 1}');
    for (final n in [100, 150, 200]) {
      final dias = [for (final e in edificiosFase1) sim.primerDia['${e.id}_$n'] ?? 9999];
      lineas.add('  nivel $n: primera el día ${dias.reduce(min) + 1}, última el día ${dias.reduce(max) + 1}');
    }
    lineas.add('Al final: ${imp.cagadas} cagadas, ${imp.partida.jaladas} jaladas, ${imp.partida.rollos} rollos '
        '(x${imp.multiplicadorRollos.toStringAsExponential(2)}), ${imp.mjTotal.toStringAsExponential(2)} MJ en total');
    // ignore: avoid_print
    print(lineas.join('\n'));

    final corridas = sim.corridas;
    expect(corridas.length, greaterThan(2));
    expect(corridas.first.fin, lessThan(14)); // la primera jalada antes del día 14
    int indice(String id) => edificios.indexWhere((e) => e.id == id);
    for (var i = 2; i < corridas.length; i++) {
      // Desde la 2ª, cada corrida llega por lo menos tan lejos como la anterior.
      expect(indice(corridas[i].masAlto), greaterThanOrEqualTo(indice(corridas[i - 1].masAlto)), reason: 'corrida ${i + 1}');
    }
    expect(sim.primerDia['granja'], isNotNull);
    expect(sim.primerDia['granja']!, lessThan(60));
    for (final e in edificios) {
      expect(sim.primerDia[e.id], isNotNull, reason: '${e.id} nunca se compra');
      // El Agujero lo frena su candado de 150 cagadas (día ~215 a 0,7 por día).
      expect(sim.primerDia[e.id]!, lessThan(222), reason: e.id);
    }
    expect(faltan, isEmpty, reason: 'mejoras inalcanzables');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
