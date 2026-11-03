// Simulación de 300 días con Plomería, Mudanza y Llavero: el mismo jugador codicioso de imperio_cadena_ritmo_test (5 pujos
// por segundo, 3 sesiones de 10 min al día, 0,7 cagadas reales al día, mismas reglas para comprar y jalar), más:
//
// - Plomería: al abrir cada sesión compra el nodo más barato que pueda. Los que suben la producción o los pujos (Tubería
//   ancha, Llave de paso) si cuestan hasta el 20% de los rollos que tiene; los demás, hasta el 5%. La Cadena de reserva no.
// - Jalar: además de la regla de la cadena, jala si con esa jalada ya puede mudarse.
// - Mudanza: apenas puede (rollos de la casa, jaladas de la casa y cagadas reales desde que llegó, máx 3 por día).
// - Llavero: al mudarse gasta todas las Llaves, primero Cimientos y si no alcanza, Camión de mudanza, Ahorros y Mayordomo.
//
// Tarda unos 5 min: solo corre con SIM_MUDANZA=1 (las aserciones son flojas; lo importante es la tabla que imprime).
// Mismo perfil por variables que la otra simulación (SES, LARGO, TOQUES, CPD, DIAS; con cualquiera puesta no hay aserciones).
//
// Con SIM_ABDICAR=1 corre la otra, de 600 días (DIAS la cambia): el mismo jugador abdica apenas puede (Palacio, Llaves
// ganadas en el reinado y cagadas reales desde la última abdicación, máx 3 por día) y gasta las Coronas en La Corte:
// Maestro de obras primero, luego Heraldo, Tesorero y Bufón. Metas: 1.ª abdicación entre los días 300 y 420; el 2.º
// reinado llega al Palacio en 75% o menos de los días del 1.º y, si hay 3.º, en 50% o menos. Tarda unos 10 min.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/casas.dart';
import 'package:rey_cagon/imperio/flags.dart';
import 'package:rey_cagon/imperio/motor.dart';

const int _seg = 1000;
const int _hora = 3600 * _seg;
const int _dia = 24 * _hora;
final Map<String, String> _env = Platform.environment;
final bool _correr = _env['SIM_MUDANZA'] == '1';
final bool _correrAbdicar = _env['SIM_ABDICAR'] == '1';
final bool _perfilPropio = ['SES', 'LARGO', 'TOQUES', 'CPD', 'DIAS'].any(_env.containsKey);
final List<int> _sesiones = (_env['SES'] ?? '8,14,20').split(',').map(int.parse).toList();
final int _largoSesion = int.parse(_env['LARGO'] ?? '600');
final int _toques = int.parse(_env['TOQUES'] ?? '5');
final double _cagadasPorDia = double.parse(_env['CPD'] ?? '0.7');
final int _dias = int.parse(_env['DIAS'] ?? '300');
final int _diasAbdicar = int.parse(_env['DIAS'] ?? '600');

/// Nodos de la Plomería que suben el MJ/s o los pujos: se compran hasta con el 20% de los rollos.
const Set<String> _plomeriaFuerte = {'tuberia_ancha', 'llave_paso'};

/// Orden en el que gasta las Llaves cuando ya no le alcanzan para Cimientos.
const List<String> _ordenLlavero = ['cimientos', 'camion_mudanza', 'ahorros', 'mayordomo'];

/// Orden en el que gasta las Coronas: el primero que le alcance.
const List<String> _ordenCorte = ['maestro_obras', 'heraldo', 'tesorero', 'bufon'];

class _Opcion {
  final String id;
  final bool esEdificio;
  final double precio;
  final double ganancia;
  _Opcion(this.id, this.esEdificio, this.precio, this.ganancia);
}

/// Una casa: desde que llegaste hasta que te mudaste.
class _Casa {
  final int mudanzas;
  final int dia;
  final int abdicaciones;
  int? fin;
  bool abdico = false; // se fue abdicando (no mudándose)
  int llavesReinado = 0; // Llaves ganadas en el reinado al irse
  int coronas = 0; // Coronas sin gastar al irse
  String corte = '-'; // La Corte comprada al abdicar
  int jaladas = 0;
  int rollos = 0;
  int llaves = 0;
  double pico = 0;
  int? diaPicoAnterior; // primer día en que el MJ/s llegó al pico de la casa anterior
  double plomeriaMps = 1; // MJ/s con Plomería / sin Plomería al irse
  double plomeriaIngreso = 1; // lo mismo con los pujos contados
  int nivelesPlomeria = 0;
  String llavero = '-';
  String desglose = ''; // multiplicadores al irse
  _Casa(this.mudanzas, this.dia, [this.abdicaciones = 0]);
}

class _Simulacion {
  final Imperio imp;
  final int dias;
  final bool abdica;
  int cagadasReinado = 0;
  final List<int> diasAbdicacion = [];
  final Random azar;
  final List<_Casa> casasVividas = [_Casa(0, 0)];
  int cagadasDesde = 0;
  int diaJalada = 0; // día de la última jalada (o de la llegada a la casa)
  int cagadasCasa = 0;
  int cagadasCandado = 0;
  final Map<int, int> cagadasPorDia = {};
  final Map<String, int> plomeriaComprada = {};
  final List<double> mpsDiario = [];
  _Simulacion(int semilla, Ajustes ajustes, {this.dias = 300, this.abdica = false})
      : azar = Random(semilla),
        imp = Imperio(azar: Random(semilla + 1), ajustes: ajustes);

  double _ingresoPorSeg(int ahora) => imp.mpsSinEfectos(contarAtasco: false) + _toques * imp.valorPujo(ahora);

  double _offlinePorSegActivo(Duration tope, double pct, double mps) {
    final hueco = (_dia - _sesiones.length * _largoSesion * _seg) / _sesiones.length / 1000;
    final contado = min(hueco, tope.inSeconds.toDouble());
    return _sesiones.length * contado * pct * mps / (_sesiones.length * _largoSesion);
  }

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
      final n = imp.cantidad(e.id);
      for (final (nivel, _) in nivelesMejoraEdificio) {
        if (n >= nivel || p.mejoras.contains(idMejoraEdificio(e.id, nivel))) continue;
        if (p.rollosGanados < (rollosNivelMejora[nivel] ?? 0)) break;
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
      if (m.familia == FamiliaMejora.dorado || m.id == 'cadena_trono') ganancia = imp.precioMejora(m) <= 600 * base ? double.infinity : 0;
      if (imp.precioMejora(m) <= 60 * base) ganancia = double.infinity;
      r.add(_Opcion(m.id, false, imp.precioMejora(m), ganancia));
    }
    return r;
  }

  void _pagarCandado() {
    for (final e in edificios) {
      if (imp.edificioAbierto(e.id)) continue;
      if (imp.partida.rollosGanados < e.rollos || !imp.candadoPagable(e.candado)) return;
      imp.pagarCandado(e.candado);
      return;
    }
  }

  void _comprar(int ahora) {
    _pagarCandado();
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

  /// Plomería: el nodo más barato que cumpla la regla, hasta que no quede ninguno.
  void _comprarPlomeria(int ahora) {
    for (var k = 0; k < 200; k++) {
      ObjetoRollos? mejor;
      var precio = double.infinity;
      for (final o in objetosRollos) {
        if (o.id == 'cadena_reserva' || !imp.puedeComprarObjetoRollos(o.id, ahora)) continue;
        final pr = imp.precioObjetoRollos(o.id);
        if (pr > imp.partida.rollos * (_plomeriaFuerte.contains(o.id) ? 0.2 : 0.05)) continue;
        if (pr < precio) {
          precio = pr;
          mejor = o;
        }
      }
      if (mejor == null || !imp.comprarObjetoRollos(mejor.id, ahora)) return;
      plomeriaComprada[mejor.id] = (plomeriaComprada[mejor.id] ?? 0) + 1;
    }
  }

  void _jalar(int dia) {
    imp.jalar();
    casasVividas.last.jaladas++;
    cagadasDesde = 0;
    diaJalada = dia;
  }

  void _quizasJalar(int inicio) {
    if (!imp.puedeJalar(cagadasDesde, imp.ajustes.cadenaCagadas)) return;
    final p = imp.partida;
    final dia = inicio ~/ _dia;
    // Con los Rollos de la casa ya listos solo faltan jaladas: cada una acerca la mudanza.
    final rollosListos = p.rollosGanados + imp.rollosPorGanar >= imp.rollosParaMudanza;
    final minimo = max(1, (p.rollos * (dia - diaJalada > 14 ? 0.1 : 0.5)).ceil());
    if (rollosListos || imp.rollosPorGanar >= minimo) _jalar(dia);
  }

  /// MJ/s (y MJ/s con pujos) con la Plomería dividido entre sin ella.
  (double, double) _aportePlomeria(int ahora) {
    final p = imp.partida;
    final antes = Map.of(p.objetosRollos);
    final mps = imp.mpsSinEfectos(contarAtasco: false), ingreso = _ingresoPorSeg(ahora);
    p.objetosRollos = {
      for (final MapEntry(key: id, value: n) in antes.entries)
        if (!{'tuberia_ancha', 'llave_paso'}.contains(id)) id: n,
    };
    final mps0 = imp.mpsSinEfectos(contarAtasco: false), ingreso0 = _ingresoPorSeg(ahora);
    p.objetosRollos = antes;
    return (mps / max(mps0, 1e-9), ingreso / max(ingreso0, 1e-9));
  }

  /// Multiplicadores de ahora, para comparar casas entre reinados.
  String _desglose() {
    String e(num v) => v.toStringAsExponential(2);
    final p = imp.partida;
    final cimientos = pow(2, imp.nivelLlavero('cimientos')), tuberia = pow(1.5, imp.nivelPlomeria('tuberia_ancha'));
    return 'cagadas x${e(imp.multiplicadorCagadas)} (${imp.cagadas}), logros x${e(imp.multiplicadorLogros)} (${p.logros.length}), '
        'rollos x${e(imp.multiplicadorRollos)} (${p.rollos}), comodidad x${e(imp.multiplicadorComodidad)}, '
        'mudanza x${e(imp.multiplicadorMudanza)} [casa x${e(multiplicadorCasa(p.mudanzas))}, ${imp.llaves} llaves sin gastar, '
        'cimientos x${e(cimientos)}, tubería x${e(tuberia)}], corte x${e(imp.multiplicadorCorte)}, '
        'permanente x${e(imp.multiplicadorPermanente)}, ahorros ${imp.nivelLlavero('ahorros')}, plomería ${p.objetosRollos}, '
        'MJ/s ${e(imp.mpsSinEfectos(contarAtasco: false))}, mjCasa ${e(p.mjCasa)}, mjTotal ${e(p.mjTotal)}, '
        'rollosCasa ${e(imp.rollosCasa)}, edificios ${p.edificios.values.fold(0, (a, b) => a + b)}';
  }

  void _quizasMudarse(int inicio) {
    if (!imp.puedeMudarse(cagadasCasa)) return;
    final dia = inicio ~/ _dia;
    final c = casasVividas.last;
    c.desglose = _desglose();
    final (mps, ingreso) = _aportePlomeria(inicio);
    c
      ..fin = dia
      ..rollos = imp.rollosCasa
      ..plomeriaMps = mps
      ..plomeriaIngreso = ingreso
      ..nivelesPlomeria = imp.partida.objetosRollos.values.fold(0, (a, b) => a + b);
    c.llaves = imp.mudarse();
    c.llavero = _comprarLlavero();
    casasVividas.add(_Casa(imp.partida.mudanzas, dia, imp.partida.abdicaciones));
    c.llavesReinado = imp.partida.llavesGanadas;
    diaJalada = dia;
    cagadasCasa = 0;
  }

  /// Gasta todas las Llaves en [_ordenLlavero] y devuelve lo comprado ("cimientos+2 ...").
  String _comprarLlavero() {
    final compras = <String, int>{};
    for (var k = 0; k < 100; k++) {
      final id = _ordenLlavero.firstWhere(imp.puedeComprarLlavero, orElse: () => '');
      if (id.isEmpty || !imp.comprarLlavero(id)) break;
      compras[id] = (compras[id] ?? 0) + 1;
    }
    return compras.isEmpty ? '-' : compras.entries.map((e) => '${e.key}+${e.value}').join(' ');
  }

  void _quizasAbdicar(int inicio) {
    if (!abdica || !imp.puedeAbdicar(cagadasReinado)) return;
    final dia = inicio ~/ _dia;
    final c = casasVividas.last;
    c.desglose = _desglose();
    c
      ..fin = dia
      ..abdico = true
      ..rollos = imp.rollosCasa
      ..llavesReinado = imp.partida.llavesGanadas;
    imp.abdicar();
    final compras = <String, int>{};
    for (var k = 0; k < 100; k++) {
      final id = _ordenCorte.firstWhere(imp.puedeComprarCorte, orElse: () => '');
      if (id.isEmpty || !imp.comprarCorte(id)) break;
      compras[id] = (compras[id] ?? 0) + 1;
    }
    c
      ..coronas = imp.coronas
      ..corte = compras.isEmpty ? '-' : compras.entries.map((e) => '${e.key}+${e.value}').join(' ')
      ..llavero = _comprarLlavero();
    casasVividas.add(_Casa(imp.partida.mudanzas, dia, imp.partida.abdicaciones));
    diasAbdicacion.add(dia);
    diaJalada = dia;
    cagadasCasa = 0;
    cagadasReinado = 0;
  }

  void correr() {
    final siguienteCagada = <int>[];
    for (var t = 0.0; t < dias * _dia; t += _dia / _cagadasPorDia) {
      siguienteCagada.add((t + _dia / _cagadasPorDia).round());
    }
    var finAnterior = -1;
    for (var d = 0; d < dias; d++) {
      imp.pases++;
      for (final h in _sesiones) {
        final inicio = d * _dia + h * _hora;
        if (finAnterior >= 0) imp.aplicarOffline(finAnterior, inicio);
        final nuevas = <CagadaReal>[];
        while (siguienteCagada.isNotEmpty && siguienteCagada.first <= inicio) {
          final cuando = siguienteCagada.removeAt(0);
          nuevas.add(CagadaReal(tipo: 1 + azar.nextInt(7), creada: DateTime.utc(2026).add(Duration(milliseconds: cuando))));
        }
        if (nuevas.isNotEmpty) {
          imp.cagadas += nuevas.length;
          imp.fichas += nuevas.length;
          var cuentan = 0;
          for (final c in nuevas) {
            final dc = c.creada.difference(DateTime.utc(2026)).inDays;
            final n = cagadasPorDia[dc] ?? 0;
            if (n < 3) cuentan++;
            cagadasPorDia[dc] = n + 1;
          }
          cagadasCandado += cuentan;
          imp.cagadasCandado = cagadasCandado;
          cagadasDesde += cuentan;
          cagadasCasa += cuentan;
          cagadasReinado += cuentan;
          imp.aplicarCagadas(nuevas, inicio);
        }
        _quizasJalar(inicio);
        _quizasMudarse(inicio);
        _quizasAbdicar(inicio);
        _comprarPlomeria(inicio);
        if (nuevas.isNotEmpty) imp.aplicarFrescaHasta(inicio + 3600000);
        for (var s = 0; s < _largoSesion; s++) {
          final ahora = inicio + s * _seg;
          for (var k = 0; k < _toques; k++) {
            imp.pujar(ahora + k * 1000 ~/ _toques);
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
        final mps = imp.mpsSinEfectos();
        final c = casasVividas.last;
        c.pico = max(c.pico, mps);
        if (casasVividas.length > 1 && c.diaPicoAnterior == null && mps >= casasVividas[casasVividas.length - 2].pico) {
          c.diaPicoAnterior = d;
        }
      }
      mpsDiario.add(imp.mpsSinEfectos());
    }
    final c = casasVividas.last;
    final (mps, ingreso) = _aportePlomeria(dias * _dia);
    c
      ..llavesReinado = imp.partida.llavesGanadas
      ..coronas = imp.coronas
      ..rollos = imp.rollosCasa
      ..plomeriaMps = mps
      ..plomeriaIngreso = ingreso
      ..nivelesPlomeria = imp.partida.objetosRollos.values.fold(0, (a, b) => a + b);
  }
}

/// Ajustes de la mudanza y de abdicar por variables (para afinar sin tocar los flags): MR, MRS, MJ, MC, MD, AL, AF, AD.
FlagsImperio _flags() => FlagsImperio(
      mudanzaRollos: double.tryParse(_env['MR'] ?? '') ?? FlagsImperio.porDefecto.mudanzaRollos,
      mudanzaRollosSubida: double.tryParse(_env['MRS'] ?? '') ?? FlagsImperio.porDefecto.mudanzaRollosSubida,
      mudanzaJaladas: int.tryParse(_env['MJ'] ?? '') ?? FlagsImperio.porDefecto.mudanzaJaladas,
      mudanzaCagadas: int.tryParse(_env['MC'] ?? '') ?? FlagsImperio.porDefecto.mudanzaCagadas,
      mudanzaDivisorX: double.tryParse(_env['MD'] ?? '') ?? FlagsImperio.porDefecto.mudanzaDivisorX,
      abdicarLlaves: double.tryParse(_env['AL'] ?? '') ?? FlagsImperio.porDefecto.abdicarLlaves,
      abdicarCoronasFactor: double.tryParse(_env['AF'] ?? '') ?? FlagsImperio.porDefecto.abdicarCoronasFactor,
      abdicarDivisorRollos: double.tryParse(_env['AD'] ?? '') ?? FlagsImperio.porDefecto.abdicarDivisorRollos,
    );

void main() {
  test('mudanzas a lo largo de 300 días', () {
    final flags = _flags();
    final sim = _Simulacion(7, flags.ajustes)..correr();
    final imp = sim.imp;
    String e(num v) => v.toStringAsExponential(2);
    final lineas = <String>[
      'Casas (día de llegada, día de la mudanza, días, jaladas en la casa, rollos de la casa, llaves al irse, Llavero comprado):',
    ];
    for (final c in sim.casasVividas) {
      final dias = (c.fin ?? _dias) - c.dia;
      lineas.add('  ${casaConEmoji(c.mudanzas)}: día ${c.dia + 1} → ${c.fin == null ? 'sigue' : 'día ${c.fin! + 1}'}, $dias d, '
          '${c.jaladas} jaladas, ${e(c.rollos)} rollos, ${c.fin == null ? '-' : '${c.llaves} llaves'}, llavero: ${c.llavero}');
    }
    lineas.add('Pico de MJ/s por casa y días para volver al pico de la anterior (meta: menos de 1/3 de lo que duró esa):');
    for (var i = 0; i < sim.casasVividas.length; i++) {
      final c = sim.casasVividas[i];
      var vuelta = '';
      if (i > 0) {
        final ant = sim.casasVividas[i - 1];
        final meta = ((ant.fin ?? _dias) - ant.dia) / 3;
        vuelta = c.diaPicoAnterior == null
            ? ', no volvió al pico anterior (meta ${meta.toStringAsFixed(0)} d)'
            : ', volvió al pico anterior en ${c.diaPicoAnterior! - c.dia + 1} d (meta ${meta.toStringAsFixed(0)} d)';
      }
      lineas.add('  ${nombreCasa(c.mudanzas)}: pico ${e(c.pico)} MJ/s$vuelta');
    }
    lineas.add('Aporte de la Plomería al irse de cada casa (MJ/s con / sin Tubería ancha y Llave de paso; con pujos):');
    for (final c in sim.casasVividas) {
      lineas.add('  ${nombreCasa(c.mudanzas)}: ${c.nivelesPlomeria} niveles, MJ/s x${c.plomeriaMps.toStringAsFixed(2)}, '
          'ingreso con pujos x${c.plomeriaIngreso.toStringAsFixed(2)}');
    }
    lineas.add('Plomería comprada en toda la simulación: '
        '${sim.plomeriaComprada.entries.map((x) => '${x.key} ${x.value}').join(', ')}');
    lineas.add('MJ/s por día:');
    for (final d in [30, 60, 75, 90, 120, 150, 180, 210, 240, 270, 300]) {
      if (d > sim.mpsDiario.length) break;
      lineas.add('  día $d: ${e(sim.mpsDiario[d - 1])}');
    }
    lineas.add('Al final: ${imp.partida.mudanzas} mudanzas, ${imp.partida.jaladas} jaladas, ${imp.llaves} llaves sin gastar, '
        'llavero ${imp.partida.llavero}, ${e(imp.mjTotal)} MJ en total');
    // ignore: avoid_print
    print(lineas.join('\n'));
    if (_perfilPropio) return;

    final fines = [for (final c in sim.casasVividas) if (c.fin != null) c.fin!];
    expect(fines.length, greaterThanOrEqualTo(3), reason: 'pocas mudanzas en $_dias días');
    expect(fines.first, inInclusiveRange(50, 80), reason: '1.ª mudanza');
    // La última casa puede quedar a medias al final de la simulación: solo cuentan las que se dejaron.
    for (var i = 1; i < sim.casasVividas.length; i++) {
      if (sim.casasVividas[i].fin == null) continue;
      expect(sim.casasVividas[i].diaPicoAnterior, isNotNull, reason: '${nombreCasa(i)} no vuelve al pico de la casa anterior');
    }
  }, skip: _correr ? false : 'Simulación larga: correr con SIM_MUDANZA=1', timeout: const Timeout(Duration(minutes: 15)));

  test('abdicaciones a lo largo de 600 días', () {
    final flags = _flags();
    final sim = _Simulacion(7, flags.ajustes, dias: _diasAbdicar, abdica: true)..correr();
    final imp = sim.imp;
    String e(num v) => v.toStringAsExponential(2);
    String rom(int a) => a <= 0 ? '-' : dinastia(a).split(' ').last;
    final lineas = <String>[
      'Casas (día de llegada → día en que se fue, dinastía, casa, Llaves ganadas en el reinado al irse, Coronas sin gastar, '
          'Corte comprada al abdicar, Llavero):',
    ];
    for (final c in sim.casasVividas) {
      final fin = c.fin == null ? 'sigue' : 'día ${c.fin! + 1}${c.abdico ? ' 👑' : ''}';
      lineas.add('  día ${c.dia + 1} → $fin, dinastía ${rom(c.abdicaciones)}, ${casaConEmoji(c.mudanzas)}, '
          '${c.llavesReinado} llaves, ${c.coronas} coronas, corte: ${c.corte}, llavero: ${c.llavero}');
      if (c.desglose.isNotEmpty) lineas.add('      ${c.desglose}');
    }
    final palacios = <(int, int)>[]; // (abdicaciones, día de llegada al Palacio)
    for (final c in sim.casasVividas) {
      if (c.mudanzas >= flags.ajustes.abdicarMudanzas && !palacios.any((x) => x.$1 == c.abdicaciones)) {
        palacios.add((c.abdicaciones, c.dia));
      }
    }
    lineas.add('Llegada al Palacio por dinastía: '
        '${palacios.map((x) => '${rom(x.$1)}: día ${x.$2 + 1}').join(', ')}');
    lineas.add('Abdicaciones: ${sim.diasAbdicacion.map((d) => 'día ${d + 1}').join(', ')}');
    // Días de cada reinado hasta el Palacio: el I desde el día 1; los siguientes desde la abdicación anterior.
    final reinados = <int>[
      for (final x in palacios)
        if (x.$1 == 0) x.$2 else if (x.$1 - 1 < sim.diasAbdicacion.length) x.$2 - sim.diasAbdicacion[x.$1 - 1],
    ];
    lineas.add('Días hasta el Palacio por reinado: ${[
      for (var i = 0; i < reinados.length; i++)
        '${i + 1}.º: ${reinados[i]}${i == 0 ? '' : ' (${(100 * reinados[i] / reinados.first).round()}% del I)'}',
    ].join(', ')}');
    lineas.add('Al final: ${imp.partida.abdicaciones} abdicaciones, ${imp.partida.coronasGanadas} Coronas ganadas, '
        '${imp.coronas} sin gastar, corte ${imp.partida.corte}, ${imp.partida.mudanzas} mudanzas, x${e(imp.multiplicadorCorte)} '
        'de La Corte, ${e(imp.mjTotal)} MJ en total');
    // ignore: avoid_print
    print(lineas.join('\n'));
    if (_perfilPropio) return;

    expect(palacios, isNotEmpty, reason: 'no llegó al Palacio');
    expect(palacios.first.$2 + 1, inInclusiveRange(230, 300), reason: 'Palacio');
    expect(sim.diasAbdicacion, isNotEmpty, reason: 'no abdicó en $_diasAbdicar días');
    expect(sim.diasAbdicacion.first + 1, inInclusiveRange(300, 420), reason: '1.ª abdicación');
    expect(reinados.length, greaterThanOrEqualTo(2), reason: 'después de abdicar no volvió al Palacio');
    // El reinado II va más rápido por el Maestro de obras (cada casa pide menos), no por una explosión de Rollos.
    expect(reinados[1], lessThanOrEqualTo(reinados.first * .8), reason: 'reinado II: hasta el 80% de los días del I');
    if (reinados.length >= 3) {
      expect(reinados[2], lessThanOrEqualTo(reinados[1]), reason: 'reinado III: no más lento que el II');
    }
  }, skip: _correrAbdicar ? false : 'Simulación larga: correr con SIM_ABDICAR=1', timeout: const Timeout(Duration(minutes: 30)));
}
