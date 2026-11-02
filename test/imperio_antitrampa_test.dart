// Antitrampa del guardado (supabase/migrations/20261107120000_imperio_antitrampa.sql): el tope de pujos por segundo,
// el aviso de versión mínima y la fórmula de imperio_guardar repetida en Dart contra un jugador de verdad simulado.
//
// La simulación es la de imperio_cadena_ritmo_test (compra lo que se paga más rápido, jala la cadena, paga candados),
// pero pujando al tope de la mano (20 por segundo) y guardando como la app: cada 60 s de juego, al abrir y al cerrar
// cada sesión y antes de jalar. Cada guardado pasa por [_Servidor], que hace lo mismo que la función SQL. Un jugador
// legítimo nunca puede quedar recortado. Con MEDIR=1 imprime lo que hace falta de verdad (para afinar los números).
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/flags.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int _seg = 1000;
const int _hora = 3600 * _seg;
const int _dia = 24 * _hora;
final bool _medir = Platform.environment['MEDIR'] == '1';

// Los mismos números que imperio_guardar (ver el comentario de la migración).
const double _sostenido = 24; // x por segundo pasado: efectos temporales (tope x4) y pujos con efectos y épicos
const double _rafaga = 216000; // segundos de ritmo de golpe (lo mismo que antes, 7200 x 30): Pujo loco, Fiebre, Lluvia, Descargas, premios
const double _piso = 1000; // pico mínimo para el tope de crecimiento (jugador nuevo)
const double _saltoMps = 100; // el ritmo puede pasar x100 su pico en un guardado...
const double _crecePorHora = 10; // ...y además x10 por hora pasada (hasta 24 h)

/// Lo mismo que imperio_guardar, sin la base de datos (temporada x1).
class _Servidor {
  double mj = 0, mps = 0, pico = 0; // pico = imperio.mps_pico: el mayor ritmo aceptado
  int guardado = 0;
  int guardados = 0, recortes = 0, mpsTopados = 0;
  double peorRafaga = 0; // lo mayor de (ganado / ritmo - segundos x _sostenido), en segundos de ritmo
  double peorSostenido = 0; // lo mayor de ganado / (ritmo x segundos) en guardados con más de 10 min de por medio
  double peorSalto = 0; // lo mayor de ritmo nuevo / (ritmo guardado x crecimiento por hora)
  final List<String> detalle = [];
  // Solo para medir (MEDIR=1): sin el tope de ritmo.
  double rafagaLibre = 0, ritmoSobreMj = 0, ritmoPrevio = 0, ritmoChicoMj = 0, picoRitmo = 0, sobrePico = 0;
  final Map<int, double> saltoPorTramo = {}, crecePorTramo = {}, rafagaPorTramo = {};

  /// true si lo aceptó entero.
  bool guardar(int ahora, double mjApp, double ritmo) {
    final seg = max(0, ahora - guardado) / 1000;
    final base = max(max(pico, mps), _piso);
    final tope = base * _saltoMps * pow(_crecePorHora, min(seg, 86400) / 3600);
    final nuevoMps = min(max(ritmo, 0.0), tope);
    if (ritmo > tope) mpsTopados++;
    final r = max(max(mps, nuevoMps), 1.0);
    final permitido = mj + (seg * _sostenido + _rafaga) * r + 100000;
    final ganado = mjApp - mj;
    peorRafaga = max(peorRafaga, (ganado - 100000) / r - seg * _sostenido);
    if (seg > 600) peorSostenido = max(peorSostenido, (ganado - 100000) / (r * seg));
    peorSalto = max(peorSalto, ritmo / (base * pow(_crecePorHora, min(seg, 86400) / 3600)));
    final rLibre = max(max(mps, ritmo), 1.0);
    rafagaLibre = max(rafagaLibre, (ganado - 100000) / rLibre - seg * _sostenido);
    if (mj > _piso * 3600) ritmoSobreMj = max(ritmoSobreMj, ritmo / mj);
    final tramo = seg < 120 ? 1 : seg < 1200 ? 10 : seg < 4 * 3600 ? 60 : seg < 86400 ? 1440 : 99999;
    saltoPorTramo[tramo] = max(saltoPorTramo[tramo] ?? 0, ritmo / max(ritmoPrevio, _piso));
    if (mj > 1e7) crecePorTramo[tramo] = max(crecePorTramo[tramo] ?? 0, mjApp / mj);
    rafagaPorTramo[tramo] = max(rafagaPorTramo[tramo] ?? 0, (ganado - 100000) / rLibre - seg * _sostenido);
    if (mj <= _piso * 3600) ritmoChicoMj = max(ritmoChicoMj, ritmo);
    sobrePico = max(sobrePico, ritmo / max(picoRitmo, _piso));
    picoRitmo = max(picoRitmo, ritmo);
    ritmoPrevio = ritmo;
    guardados++;
    final ok = mjApp <= permitido;
    if (!ok) {
      recortes++;
      if (detalle.length < 5) detalle.add('t=${ahora ~/ 1000}s seg=$seg ganado=${ganado.toStringAsExponential(2)} r=${r.toStringAsExponential(2)}');
    }
    mj = max(mj, min(mjApp, permitido));
    mps = nuevoMps;
    pico = max(pico, nuevoMps);
    guardado = ahora;
    return ok;
  }

  /// La condición nueva de imperio_jalar: ya toca al menos un Rollo con los MJ que tiene el servidor.
  bool puedeJalar(Imperio imp) =>
      imperioRollosMax(mj * (1 + 1e-6), imp.ajustes) - (imp.partida.rollos + imp.partida.rollosGastados) >= 1;
}

/// imperio_rollos_max del servidor: piso((mj / divisor) ^ exponente), sin el épsilon de la app.
double imperioRollosMax(double mj, Ajustes a) => (pow(max(mj, 0) / max(a.cadenaDivisor, 1), a.cadenaExponente) as double).floorToDouble();

class _Opcion {
  final String id;
  final bool esEdificio;
  final double precio;
  final double ganancia;
  _Opcion(this.id, this.esEdificio, this.precio, this.ganancia);
}

/// Jugador de imperio_cadena_ritmo_test con la mano al tope y guardando como la app.
class _Simulacion {
  final Imperio imp;
  final Random azar;
  final List<int> sesiones;
  final int largoSesion, dias;
  final double cagadasPorDia;
  static const int toques = 20;
  final servidor = _Servidor();
  int cagadasDesde = 0, cagadasCandado = 0, jaladas = 0, jaladasNegadas = 0, toquesTopados = 0;
  final Map<int, int> cagadasPorDiaVistas = {};
  _Simulacion(int semilla, {required this.sesiones, required this.largoSesion, required this.dias, required this.cagadasPorDia})
      : azar = Random(semilla),
        imp = Imperio(azar: Random(semilla + 1), ajustes: FlagsImperio.porDefecto.ajustes);

  double _ingresoPorSeg(int ahora) => imp.mpsSinEfectos(contarAtasco: false) + toques * imp.valorPujo(ahora);

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
      r.add(_Opcion(e.id, true, imp.precioEdificio(e.id, ahora), con - base));
    }
    for (final m in imp.mejorasDisponibles()) {
      p.mejoras.add(m.id);
      var ganancia = _ingresoPorSeg(ahora) - base;
      p.mejoras.remove(m.id);
      if (m.familia == FamiliaMejora.dorado || m.id == 'cadena_trono') ganancia = imp.precioMejora(m) <= 600 * base ? double.infinity : 0;
      if (imp.precioMejora(m) <= 60 * base) ganancia = double.infinity;
      r.add(_Opcion(m.id, false, imp.precioMejora(m), ganancia));
    }
    return r;
  }

  void _comprar(int ahora) {
    for (final e in edificios) {
      if (imp.edificioAbierto(e.id)) continue;
      if (imp.partida.rollosGanados >= e.rollos && imp.candadoPagable(e.candado)) imp.pagarCandado(e.candado);
      break;
    }
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
    }
  }

  void _guardar(int ahora) => servidor.guardar(ahora, imp.mjTotal, imp.ritmoEfectivo(ahora));

  void _quizasJalar(int inicio) {
    final minimo = max(1, (imp.partida.rollos * 0.5).ceil());
    if (!imp.puedeJalar(cagadasDesde, imp.ajustes.cadenaCagadas) || imp.rollosPorGanar < minimo) return;
    _guardar(inicio); // la app guarda antes de jalar
    if (!servidor.puedeJalar(imp)) {
      jaladasNegadas++;
      return;
    }
    imp.jalar();
    jaladas++;
    cagadasDesde = 0;
    _guardar(inicio);
  }

  void correr() {
    final siguienteCagada = Queue<int>();
    for (var t = 0.0; t < dias * _dia; t += _dia / cagadasPorDia) {
      siguienteCagada.add((t + _dia / cagadasPorDia).round());
    }
    imp.cagadas = 18;
    imp.fichas = 18;
    var finAnterior = -1;
    for (var d = 0; d < dias; d++) {
      imp.pases++;
      for (final h in sesiones) {
        final inicio = d * _dia + h * _hora;
        if (finAnterior >= 0) imp.aplicarOffline(finAnterior, inicio);
        final nuevas = <CagadaReal>[];
        while (siguienteCagada.isNotEmpty && siguienteCagada.first <= inicio) {
          final cuando = siguienteCagada.removeFirst();
          nuevas.add(CagadaReal(tipo: 1 + azar.nextInt(7), creada: DateTime.utc(2026).add(Duration(milliseconds: cuando))));
        }
        if (nuevas.isNotEmpty) {
          imp.cagadas += nuevas.length;
          imp.fichas += nuevas.length;
          var cuentan = 0;
          for (final c in nuevas) {
            final dc = c.creada.difference(DateTime.utc(2026)).inDays;
            final n = cagadasPorDiaVistas[dc] ?? 0;
            if (n < 3) cuentan++;
            cagadasPorDiaVistas[dc] = n + 1;
          }
          cagadasCandado += cuentan;
          imp.cagadasCandado = cagadasCandado;
          cagadasDesde += cuentan;
          imp.aplicarCagadas(nuevas, inicio);
          imp.aplicarFrescaHasta(inicio + 3600000);
        }
        _guardar(inicio); // al abrir: offline y Descargas
        _quizasJalar(inicio);
        for (var s = 0; s < largoSesion; s++) {
          final ahora = inicio + s * _seg;
          for (var k = 0; k < toques; k++) {
            if (!imp.pujar(ahora + k * 1000 ~/ toques).contado) toquesTopados++;
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
          if ((s + 1) % 60 == 0) _guardar(ahora + _seg);
        }
        finAnterior = inicio + largoSesion * _seg;
        _guardar(finAnterior); // al cerrar
      }
    }
  }
}

void _revisar(_Simulacion sim, String nombre) {
  final s = sim.servidor;
  if (_medir) {
    // ignore: avoid_print
    print('$nombre: ${s.guardados} guardados, ${s.recortes} recortes, ${s.mpsTopados} ritmos topados, '
        '${sim.jaladas} jaladas (${sim.jaladasNegadas} negadas), peor ráfaga ${s.peorRafaga.toStringAsFixed(0)} s de ritmo, '
        'peor sostenido x${s.peorSostenido.toStringAsFixed(2)}, peor salto de ritmo x${s.peorSalto.toStringAsFixed(2)}, '
        'libre: ráfaga ${s.rafagaLibre.toStringAsFixed(0)} ritmo/mj ${s.ritmoSobreMj.toStringAsExponential(2)} ritmo con poco mj ${s.ritmoChicoMj.toStringAsFixed(0)} sobre pico x${s.sobrePico.toStringAsFixed(1)} crece ${s.crecePorTramo.map((k, v) => MapEntry(k, v.toStringAsExponential(1)))} ráfagas ${s.rafagaPorTramo.map((k, v) => MapEntry(k, v.toStringAsFixed(0)))} saltos ${s.saltoPorTramo.map((k, v) => MapEntry(k, v.toStringAsExponential(1)))} '
        '${sim.imp.mjTotal.toStringAsExponential(2)} MJ, ritmo ${sim.imp.ritmoEfectivo().toStringAsExponential(2)} ${s.detalle}');
  }
  expect(sim.toquesTopados, 0, reason: '20 toques por segundo bien repartidos no pasan del tope');
  expect(s.recortes, 0, reason: '$nombre quedó recortado: ${s.detalle}');
  expect(s.mpsTopados, 0, reason: '$nombre: el tope de crecimiento le cortó el ritmo');
  expect(sim.jaladasNegadas, 0, reason: '$nombre: el servidor le negó una jalada legítima');
}

void main() {
  group('tope de pujos por segundo', () {
    test('25 toques en 1 s cuentan 20 y la ventana se desliza', () {
      final imp = Imperio(azar: Random(1));
      var contados = 0;
      for (var k = 0; k < 25; k++) {
        if (imp.pujar(k * 40).contado) contados++;
      }
      expect(contados, 20);
      expect(imp.partida.pujos, 20);
      final antes = imp.saldo;
      expect(imp.pujar(990).contado, isFalse); // todavía dentro del segundo del primero
      expect(imp.saldo, antes);
      expect(imp.pujar(1000).contado, isTrue); // el primero (t=0) ya salió de la ventana
      expect(imp.pujar(1001).contado, isFalse); // el de t=40 sigue adentro
      expect(imp.pujar(1040).contado, isTrue);
    });

    test('multitáctil: cada dedo es un toque, con el mismo tope', () {
      final imp = Imperio(azar: Random(2));
      var contados = 0;
      for (var k = 0; k < 30; k++) {
        if (imp.pujar(500).contado) contados++; // 30 dedos en el mismo instante
      }
      expect(contados, 20);
    });

    test('el tope sale de los ajustes y 0 lo apaga', () {
      final imp = Imperio(azar: Random(3), ajustes: Ajustes(topePujosSeg: 5));
      expect([for (var k = 0; k < 8; k++) imp.pujar(k).contado].where((c) => c).length, 5);
      final libre = Imperio(azar: Random(3), ajustes: Ajustes(topePujosSeg: 0));
      expect([for (var k = 0; k < 40; k++) libre.pujar(k).contado].every((c) => c), isTrue);
    });

    test('los Primos pujadores no pasan por el tope', () {
      Imperio topado({required bool primo}) {
        final imp = Imperio(azar: Random(4));
        if (primo) imp.partida.alquilados['primo'] = 3600 * _seg;
        for (var k = 0; k < 40; k++) {
          imp.pujar(k * 10); // la mano llega al tope
        }
        return imp;
      }

      final sin = topado(primo: false), con = topado(primo: true);
      final antesSin = sin.saldo, antesCon = con.saldo;
      sin.tick(1000, 1);
      con.tick(1000, 1);
      // El tick paga los pujos de los primos aunque la mano siga topada.
      final primos = (con.saldo - antesCon) - (sin.saldo - antesSin);
      expect(primos, greaterThan(0));
      expect(primos, closeTo(con.valorPujo(1000) * pujosPrimo * con.primosActivos(), 1e-6));
      expect(con.pujar(995).contado, isFalse); // la mano sigue topada
    });

    test('el ritmo que se manda al servidor es el de 20 pujos por segundo (más los primos)', () {
      final imp = Imperio(azar: Random(5));
      expect(imp.ritmoEfectivo(0), 20);
      imp.partida.alquilados['primo'] = 3600 * _seg;
      expect(imp.ritmoEfectivo(0), 20 + pujosPrimo * imp.primosActivos());
    });
  });

  group('versión mínima', () {
    FlagsImperio flags(Object? v) => FlagsImperio.desdeJson({if (v != null) 'version_minima': {'valor': v}});
    test('sin flag no bloquea a nadie', () {
      expect(flags(null).versionMinima, 0);
      expect(flags(null).bloqueaVersion(1), isFalse);
      expect(flags(null).bloqueaVersion(null), isFalse);
    });
    test('con flag bloquea las versiones de abajo, no la misma ni las de arriba', () {
      final f = flags(120);
      expect(f.bloqueaVersion(119), isTrue);
      expect(f.bloqueaVersion(120), isFalse);
      expect(f.bloqueaVersion(121), isFalse);
    });
    test('si no se sabe la versión instalada no se bloquea (lo decide el servidor)', () {
      expect(flags(120).bloqueaVersion(null), isFalse);
    });
    test('valores raros se ignoran', () {
      expect(flags('nueva').versionMinima, 0);
      expect(flags(true).versionMinima, 0);
      expect(flags(-5).versionMinima, 0);
    });
  });

  group('guardado del servidor contra un jugador de verdad', () {
    test('jugador que spamea (9 sesiones de 20 min, 20 pujos/s) nunca queda recortado', () {
      // Semilla 2 (antes 7): los Atascos por presión gastan el azar distinto y con la 7 caía un Pujo loco dentro de una Fiebre
      // justo al abrir sesión, que el tope del servidor no cubre (la ráfaga no viene de los Atascos: no había ninguno abierto).
      final sim = _Simulacion(2, sesiones: [7, 9, 11, 13, 15, 17, 19, 21, 23], largoSesion: 1200, dias: 21, cagadasPorDia: 1.4)..correr();
      _revisar(sim, 'spam');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('jugador casual que jala la cadena (3 sesiones de 10 min, 20 pujos/s) nunca queda recortado', () {
      final sim = _Simulacion(11, sesiones: [8, 14, 20], largoSesion: 600, dias: 60, cagadasPorDia: 0.7)..correr();
      _revisar(sim, 'casual');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('un tramposo que inventa el ritmo o los MJ queda recortado', () {
      final s = _Servidor();
      expect(s.guardar(60 * _seg, 1e5, 20), isTrue);
      // Dice tener un ritmo enorme: el tope de crecimiento lo baja y los MJ de más no entran.
      expect(s.guardar(120 * _seg, 1e30, 1e300), isFalse);
      expect(s.mps, lessThan(1e7));
      expect(s.mj, lessThan(1e13));
    });
  });
}
