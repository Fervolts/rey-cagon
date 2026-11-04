// Sala de juegos: lógica pura de los 3 minijuegos, cuenta del premio, JSON del servidor, control con nube falsa,
// logros de la Sala, PNG de los emojis de Memoria y la Sala (3 abiertos, 8 PRÓXIMAMENTE).
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/catalogo.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/minijuegos/datos.dart';
import 'package:rey_cagon/imperio/minijuegos/destapa_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/estadisticas.dart';
import 'package:rey_cagon/imperio/minijuegos/memoria_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/tuberia_logica.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/sala.dart';
import 'package:rey_cagon/imperio/telemetria.dart';

class _Nube extends NubeImperio {
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

class _NubeMj extends NubeMinijuegos {
  _NubeMj(this.respuesta);
  Object respuesta;
  final llamadas = <String>[];

  @override
  Future<ResumenMinijuegos> resumen() async {
    if (respuesta is Exception) throw respuesta as Exception;
    return const ResumenMinijuegos(ganadosHoy: 4, juegos: {'tuberia': ResumenJuego(record: 700, partidas: 30, semana: 700)});
  }

  @override
  Future<ResultadoMinijuego> guardar(String juego, int puntos, int duracionMs) async {
    llamadas.add('$juego:$puntos');
    final r = respuesta;
    if (r is Exception) throw r;
    return ResultadoMinijuego.desdeJson(r as Map<String, dynamic>);
  }
}

ControlImperio _control(_NubeMj nube) => ControlImperio(nube: _Nube(), telemetria: Telemetria(enviar: (_) async => 0))
  ..imperio = Imperio(partida: Partida(edificios: {'ciruela': 10}))
  ..nubeMinijuegos = nube;

void main() {
  setUp(estadisticasMinijuegos.clear);

  group('minutosDePartida', () {
    test('proporcional a la meta, mínimo 1, tope del máximo', () {
      expect(minutosDePartida(puntos: 300, meta: 600), 5);
      expect(minutosDePartida(puntos: 1, meta: 600), 1);
      expect(minutosDePartida(puntos: 5000, meta: 600), 10);
    });
    test('0 puntos o nada que dar hoy no premia; respeta lo que queda del día', () {
      expect(minutosDePartida(puntos: 0, meta: 600), 0);
      expect(minutosDePartida(puntos: 600, meta: 600, restanHoy: 0), 0);
      expect(minutosDePartida(puntos: 600, meta: 600, restanHoy: 3), 3);
    });
  });

  group('JSON del servidor', () {
    test('resumen', () {
      final r = ResumenMinijuegos.desdeJson({
        'activo': true,
        'minutos_max': 10,
        'tope_dia': 30,
        'tope_partidas': 20,
        'ganados_hoy': 25,
        'partidas_hoy': 3,
        'juegos': {'destapa': {'record': 40, 'partidas': 2, 'semana': 40}},
      });
      expect(r.restanHoy, 5);
      expect(r.puedeDarHoy, 5);
      expect(r.juegos['destapa']!.record, 40);
    });
    test('apagado o sin partidas no puede dar', () {
      expect(ResumenMinijuegos.desdeJson({'activo': false}).puedeDarHoy, 0);
      expect(const ResumenMinijuegos(partidasHoy: 20).puedeDarHoy, 0);
    });
    test('resultado', () {
      final r = ResultadoMinijuego.desdeJson({'ok': true, 'minutos': 7, 'puntos': 400, 'record': 400, 'nuevo_record': true});
      expect(r.ok, isTrue);
      expect(r.minutos, 7);
      expect(r.nuevoRecord, isTrue);
      expect(ResultadoMinijuego.desdeJson({'ok': false, 'motivo': 'invalida'}).minutos, 0);
      expect(textoMotivoMinijuego('invalida'), isNotNull);
      expect(textoMotivoMinijuego(null), isNull);
    });
  });

  group('Tubería', () {
    test('sin tocar acaba chocando y los puntos son metros', () {
      final j = JuegoTuberia(azar: Random(1));
      for (var i = 0; i < 6000 && !j.terminado; i++) {
        j.avanzar(0.016);
      }
      expect(j.terminado, isTrue);
      expect(j.puntos, greaterThan(10));
    });
    test('toque cambia de carril y termina sin efecto', () {
      final j = JuegoTuberia(azar: Random(2));
      expect(j.carril, 0);
      j.toque();
      expect(j.carril, 1);
      j.toque();
      expect(j.carril, 0);
      expect(j.toques, 2);
    });
    test('la velocidad sube y no pasa del máximo', () {
      final j = JuegoTuberia(azar: Random(3));
      final v0 = j.velocidad;
      j.avanzar(2);
      expect(j.velocidad, greaterThanOrEqualTo(v0));
      expect(j.velocidad, lessThanOrEqualTo(JuegoTuberia.velocidadMaxima));
    });
    test('un bot que esquiva los codos llega lejos', () {
      final j = JuegoTuberia(azar: Random(4));
      for (var i = 0; i < 3000 && !j.terminado; i++) {
        // Se pone en el carril contrario al del próximo codo cercano.
        final prox = j.codos.where((c) => c.distancia > j.distancia - 1).toList()..sort((a, b) => a.distancia.compareTo(b.distancia));
        if (prox.isNotEmpty && prox.first.carril == j.carril && prox.first.distancia - j.distancia < 6) j.toque();
        j.avanzar(0.016);
      }
      expect(j.puntos, greaterThan(100));
    });
  });

  group('Destapa', () {
    test('toque justo en el pulso es perfecto y suma', () {
      final j = JuegoDestapa();
      j.avanzar(JuegoDestapa.entrada);
      expect(j.toque(), Golpe.perfecto);
      expect(j.puntos, JuegoDestapa.puntosPerfecto);
    });
    test('toque suelto es fallo; 3 fallos terminan', () {
      final j = JuegoDestapa();
      for (var i = 0; i < JuegoDestapa.fallosMaximos; i++) {
        expect(j.terminado, isFalse);
        expect(j.toque(), Golpe.fallo);
      }
      expect(j.terminado, isTrue);
      expect(j.toque(), Golpe.fallo);
      expect(j.fallos, JuegoDestapa.fallosMaximos);
    });
    test('dejar pasar los pulsos cuenta como fallo', () {
      final j = JuegoDestapa();
      for (var i = 0; i < 2000 && !j.terminado; i++) {
        j.avanzar(0.05);
      }
      expect(j.terminado, isTrue);
      expect(j.puntos, 0);
    });
    test('jugador perfecto destapa inodoros y el compás se acelera', () {
      final j = JuegoDestapa();
      j.avanzar(JuegoDestapa.entrada);
      final c0 = j.compas;
      for (var i = 0; i < 30; i++) {
        expect(j.toque(), Golpe.perfecto);
        j.avanzar(j.compas);
      }
      expect(j.inodoros, greaterThan(0));
      expect(j.compas, lessThan(c0));
      expect(j.fallos, 0);
    });
    test('segundo toque sobre el mismo pulso es fallo', () {
      final j = JuegoDestapa();
      j.avanzar(JuegoDestapa.entrada);
      j.toque();
      expect(j.toque(), Golpe.fallo);
    });
  });

  group('Memoria', () {
    test('puntaje: parejas, rapidez, errores, nunca negativo', () {
      expect(puntajeNivel(pares: 6, segundos: 0, errores: 0), 6 * 100 + 6 * 50);
      expect(puntajeNivel(pares: 6, segundos: 999, errores: 0), 600);
      expect(puntajeNivel(pares: 6, segundos: 999, errores: 2), 550);
      expect(puntajeNivel(pares: 6, segundos: 999, errores: 100), 0);
    });
    test('mazo: cada emoji dos veces y sin repetir parejas distintas', () {
      for (final n in nivelesMemoria) {
        final j = JuegoMemoria(n, azar: Random(5));
        expect(j.cartas.length, n.cartas);
        final cuenta = <String, int>{};
        for (final c in j.cartas) {
          cuenta[c.emoji] = (cuenta[c.emoji] ?? 0) + 1;
        }
        expect(cuenta.values.every((v) => v == 2), isTrue);
      }
    });
    test('error bloquea y voltea de nuevo; acierto deja hecha la pareja', () {
      final j = JuegoMemoria(nivelesMemoria[0], azar: Random(6));
      final a = 0;
      final b = List.generate(j.cartas.length, (i) => i).firstWhere((i) => i != a && j.cartas[i].emoji != j.cartas[a].emoji);
      final par = List.generate(j.cartas.length, (i) => i).firstWhere((i) => i != a && j.cartas[i].emoji == j.cartas[a].emoji);
      expect(j.toca(a), isTrue);
      expect(j.toca(a), isFalse);
      expect(j.toca(b), isTrue);
      expect(j.errores, 1);
      expect(j.bloqueado, isTrue);
      expect(j.toca(par), isFalse);
      j.avanzar(JuegoMemoria.esperaFallo + 0.1);
      expect(j.bloqueado, isFalse);
      expect(j.cartas[a].estado, EstadoCarta.oculta);
      expect(j.toca(a), isTrue);
      expect(j.toca(par), isTrue);
      expect(j.parejas, 1);
      expect(j.cartas[a].estado, EstadoCarta.hecha);
      expect(j.toca(-1), isFalse);
      expect(j.toca(999), isFalse);
    });
    test('partida de tres niveles perfecta suma los tres', () {
      final p = PartidaMemoria(azar: Random(7));
      for (var n = 0; n < 3; n++) {
        expect(p.nivel, n);
        final j = p.juego;
        for (final e in {...j.cartas.map((c) => c.emoji)}) {
          final ids = [for (var i = 0; i < j.cartas.length; i++) if (j.cartas[i].emoji == e) i];
          j.toca(ids[0]);
          j.toca(ids[1]);
        }
        expect(j.terminado, isTrue);
        expect(p.terminada, n == 2);
        if (n < 2) expect(p.siguiente(), isTrue);
      }
      expect(p.puntos, greaterThan(0));
      expect(p.siguiente(), isFalse);
      expect(p.erroresTotal, 0);
    });
    test('los PNG de los emojis existen y están en emoji.dart', () {
      final src = File('lib/emoji.dart').readAsStringSync();
      final mapa = {for (final m in RegExp(r"'([^']+)':\s*'([a-z0-9_\-]+)'").allMatches(src)) m.group(1)!: m.group(2)!};
      for (final e in emojisMemoria) {
        final f = mapa[e];
        expect(f, isNotNull, reason: 'falta $e en emoji.dart');
        expect(File('assets/emoji/$f.png').existsSync(), isTrue, reason: 'falta PNG de $e');
      }
      expect(emojisMemoria.toSet().length, emojisMemoria.length);
    });
  });

  group('Control', () {
    test('partida con premio suma MJ como regalo y actualiza el resumen', () async {
      final nube = _NubeMj({'ok': true, 'minutos': 5, 'puntos': 300, 'record': 300, 'nuevo_record': true, 'ganados_hoy': 5, 'tope_dia': 30, 'partidas_hoy': 1, 'tope_partidas': 20});
      final c = _control(nube);
      final antes = c.imperio.saldo;
      final esperado = Imperio.mjDeRegalo(5, c.imperio.mpsSinEfectos(contarAtasco: false));
      final (r, mj) = await c.terminarMinijuego('tuberia', 300, 40000);
      expect(r.ok, isTrue);
      expect(mj, esperado);
      expect(c.imperio.saldo, greaterThan(antes));
      expect(c.minijuegos!.ganadosHoy, 5);
      expect(recordMinijuego('tuberia'), 300);
      expect(partidasMinijuego('tuberia'), 1);
      expect(nube.llamadas, ['tuberia:300']);
    });
    test('rechazo y sin red no dan nada', () async {
      for (final r in <Object>[
        {'ok': false, 'motivo': 'invalida'},
        {'ok': false, 'motivo': 'apagado'},
        {'ok': false, 'motivo': 'tope_partidas'},
        Exception('sin red'),
      ]) {
        final c = _control(_NubeMj(r));
        final antes = c.imperio.saldo;
        final (res, mj) = await c.terminarMinijuego('destapa', 50, 30000);
        expect(res.ok, isFalse);
        expect(mj, 0);
        expect(c.imperio.saldo, antes);
      }
    });
    test('cargarMinijuegos llena el global y no lanza sin red', () async {
      final c = _control(_NubeMj({}));
      await c.cargarMinijuegos();
      expect(c.minijuegos!.restanHoy, 26);
      expect(recordMinijuego('tuberia'), 700);
      final f = _control(_NubeMj(Exception('x')));
      await f.cargarMinijuegos();
      expect(f.minijuegos, isNull);
    });
  });

  group('Logros de la Sala', () {
    Logro l(String id) => logros.firstWhere((x) => x.id == id);
    test('sin datos del servidor no se gana ninguno', () {
      final i = Imperio(partida: Partida(edificios: {'ciruela': 10}));
      for (final id in ['tuberia_300', 'tuberia_25', 'destapa_60', 'destapa_25', 'memoria_1800', 'memoria_10']) {
        expect(l(id).condicion(i.partida, 0), isFalse, reason: id);
      }
    });
    test('con récord y partidas sí', () {
      final i = Imperio(partida: Partida(edificios: {'ciruela': 10}));
      estadisticasMinijuegos['tuberia'] = const EstadisticaJuego(record: 300, partidas: 25);
      estadisticasMinijuegos['memoria'] = const EstadisticaJuego(record: 1800, partidas: 3);
      expect(l('tuberia_300').condicion(i.partida, 0), isTrue);
      expect(l('tuberia_25').condicion(i.partida, 0), isTrue);
      expect(l('memoria_1800').condicion(i.partida, 0), isTrue);
      expect(l('memoria_10').condicion(i.partida, 0), isFalse);
      expect(l('destapa_60').condicion(i.partida, 0), isFalse);
    });
  });

  group('Sala', () {
    testWidgets('abre 3 juegos y deja 8 en PRÓXIMAMENTE', (t) async {
      final c = _control(_NubeMj({}));
      await t.binding.setSurfaceSize(const Size(500, 2400));
      await t.pumpWidget(MaterialApp(home: PantallaSala(control: c)));
      await t.pump();
      for (final id in juegosAbiertos) {
        expect(find.byKey(Key('sala_abierto_$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('sala_abierto_tuberia')).evaluate().length, 1);
      expect(find.textContaining('PRÓXIMAMENTE'), findsNWidgets(8));
      await t.binding.setSurfaceSize(null);
    });
  });
}
