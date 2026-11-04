// Sala de juegos: lógica pura de Tubería y Destapa (Memoria va en memoria_test.dart), cuenta del premio, JSON del servidor,
// control con nube falsa, logros de la Sala y la Sala (3 abiertos, 8 PRÓXIMAMENTE).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/minijuegos/datos.dart';
import 'package:rey_cagon/imperio/minijuegos/destapa_logica.dart';
import 'package:rey_cagon/imperio/minijuegos/estadisticas.dart';
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
    test('sin tocar el Atasco lo alcanza y los puntos son metros', () {
      final j = JuegoTuberia(azar: Random(1));
      for (var i = 0; i < 60 * 600 && !j.terminado; i++) {
        j.avanzar(1 / 60);
      }
      expect(j.terminado, isTrue);
      expect(j.puntos, greaterThan(10));
      expect(j.puntos, greaterThanOrEqualTo(j.distancia.floor()));
    });
    test('mantener pesa, soltar aligera', () {
      final j = JuegoTuberia(azar: Random(2));
      j.presionado = true;
      expect(j.pesado, isTrue);
      j.presionado = false;
      expect(j.pesado, isFalse);
    });
    test('cortar termina por tiempo', () {
      final j = JuegoTuberia(azar: Random(3));
      j.avanzar(2);
      j.cortar();
      expect(j.terminado, isTrue);
      expect(j.tomarSucesos().where((s) => s.tipo == TipoSuceso.atrapado).single.valor, 1);
    });
    test('pesado en bajada y liviano en subida respeta el tope de puntos por segundo', () {
      final j = JuegoTuberia(azar: Random(4));
      for (var i = 0; i < 60 * 300 && !j.terminado; i++) {
        j.presionado = j.enSuelo ? j.pendiente(j.x) < 0 : j.vy < 0;
        j.avanzar(1 / 60);
        expect(j.velocidad, lessThanOrEqualTo(JuegoTuberia.velocidadMaxima + 1e-6));
        expect(j.puntos, lessThanOrEqualTo(((j.tiempo + 1) * JuegoTuberia.pps).floor()));
      }
      expect(j.distancia, greaterThan(100));
    });
  });

  group('Destapa', () {
    int techo(double t) => min(JuegoDestapa.topePuntos, (t.floor() + 1) * JuegoDestapa.puntosPorSegundo);
    void golpe(JuegoDestapa j, int i) {
      j.bajar(i);
      j.soltar(i);
    }

    test('tocar un inodoro limpio no suma', () {
      final j = JuegoDestapa(semilla: 1, calentar: false);
      expect(j.inodoros[0].tapado, isFalse);
      golpe(j, 0);
      expect(j.puntos, 0);
      expect(j.tomarEventos().any((e) => e.suceso == Suceso.golpeVacio), isTrue);
    });
    test('un atasco normal sale con 5 golpes y suma dentro del techo', () {
      final j = JuegoDestapa(semilla: 1, calentar: false);
      j.tapar(0, TipoAtasco.normal);
      for (var k = 0; k < JuegoDestapa.golpesNormal - 1; k++) {
        golpe(j, 0);
      }
      expect(j.inodoros[0].tapado, isTrue);
      golpe(j, 0);
      expect(j.inodoros[0].tapado, isFalse);
      expect(j.puntos, JuegoDestapa.puntosBase(TipoAtasco.normal));
      expect(j.puntos, lessThanOrEqualTo(techo(j.tiempo)));
    });
    test('sin jugar se desborda 3 veces y termina con 0 puntos', () {
      final j = JuegoDestapa(semilla: 3);
      for (var k = 0; k < 60 * 600 && !j.terminado; k++) {
        j.avanzar(1 / 60);
      }
      expect(j.terminado, isTrue);
      expect(j.pitazoFinal, isFalse);
      expect(j.desbordes, JuegoDestapa.vidas);
      expect(j.puntos, 0);
      expect(j.tiempo, greaterThan(JuegoDestapa.calentamiento));
    });
    test('al terminar ya no acepta golpes', () {
      final j = JuegoDestapa(semilla: 4, calentar: false);
      for (var k = 0; k < 60 * 600 && !j.terminado; k++) {
        j.avanzar(1 / 60);
      }
      final p = j.puntos;
      j.tapar(0, TipoAtasco.normal);
      for (var k = 0; k < 20; k++) {
        golpe(j, 0);
      }
      expect(j.puntos, p);
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
