// Regalos 🎁: lo que responde el servidor, los topes, los MJ del Rollo, los logros, el control con una nube falsa,
// la hoja de abrir y las tarjetas del chat ('regalo' y la genérica 'imperio').
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/regalos.dart';
import 'package:rey_cagon/imperio/regalos_datos.dart';
import 'package:rey_cagon/imperio/telemetria.dart';

class _Nube extends NubeImperio {
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

class _NubeRegalos extends NubeRegalos {
  _NubeRegalos(this.respuesta);

  Object? respuesta;
  final abiertos = <String>[];

  @override
  Future<EstadoRegalos> pendientes() async => EstadoRegalos.desdeJson({
        'dados': 10,
        'regalos': [
          {'id': 'g1', 'de': 'u1', 'de_nombre': 'ana', 'creado': '2026-11-02T12:00:00Z'},
        ],
      });

  @override
  Future<ResultadoRegalo> abrir(String id) async {
    abiertos.add(id);
    final r = respuesta;
    if (r is Exception) throw r;
    return ResultadoRegalo.desdeJson(r);
  }
}

Map<String, dynamic> _estado({int abiertos = 0, int enviados = 0, List<String> regalados = const [], int n = 2}) => {
      'activo': true,
      'minutos': 30,
      'tope_abrir': 5,
      'tope_envios': 5,
      'abiertos_hoy': abiertos,
      'enviados_hoy': enviados,
      'regalados_hoy': regalados,
      'dados': 3,
      'regalos': [
        for (var i = 1; i <= n; i++) {'id': 'g$i', 'de': 'u$i', 'de_nombre': 'amigo$i', 'creado': '2026-11-02T1$i:00:00Z'},
      ],
    };

Imperio _imperio() => Imperio(partida: Partida(edificios: {'ciruela': 10}));

ControlImperio _control(_NubeRegalos nube, {Telemetria? tele}) => ControlImperio(nube: _Nube(), telemetria: tele ?? Telemetria(enviar: (_) async => 0))
  ..imperio = _imperio()
  ..nubeRegalos = nube
  ..regalos = EstadoRegalos.desdeJson(_estado());

void main() {
  group('mjDeRegalo', () {
    test('minutos de producción más 13', () {
      expect(Imperio.mjDeRegalo(30, 2), 30 * 60 * 2 + 13);
      expect(Imperio.mjDeRegalo(1, 0), 13);
    });
    test('tope de 60 minutos y 0 minutos no da nada', () {
      expect(Imperio.mjDeRegalo(500, 1), 60 * 60 + 13);
      expect(Imperio.mjDeRegalo(0, 100), 0);
      expect(Imperio.mjDeRegalo(-5, 100), 0);
    });
    test('MJ/s raro cuenta como 0', () {
      expect(Imperio.mjDeRegalo(30, double.nan), 13);
      expect(Imperio.mjDeRegalo(30, double.infinity), 13);
      expect(Imperio.mjDeRegalo(30, -4), 13);
    });
    test('abrirRegalo suma a la partida lo mismo que devuelve', () {
      final i = _imperio();
      final antes = i.saldo;
      final mj = i.abrirRegalo(30);
      expect(mj, Imperio.mjDeRegalo(30, i.mpsSinEfectos(contarAtasco: false)));
      expect(mj, greaterThan(13));
      expect(i.saldo, closeTo(antes + mj, 1e-6));
    });
  });

  group('EstadoRegalos', () {
    test('desdeJson con valores y topes', () {
      final e = EstadoRegalos.desdeJson(_estado(abiertos: 1, enviados: 2, regalados: ['b']));
      expect(e.minutos, 30);
      expect(e.abrirQuedan, 4);
      expect(e.enviosQuedan, 3);
      expect(e.dados, 3);
      expect(e.regalos.map((r) => r.id), ['g1', 'g2']);
      expect(e.regalos.first.deNombre, 'amigo1');
      expect(e.puedeAbrir, isTrue);
      expect(e.puedeRegalarA('b'), isFalse);
      expect(e.puedeRegalarA('c'), isTrue);
    });
    test('sin datos: valores por defecto; fuera de rango: recortados', () {
      final vacio = EstadoRegalos.desdeJson(const {});
      expect(vacio.activo, isTrue);
      expect(vacio.minutos, minutosRegaloDefecto);
      expect(vacio.topeAbrir, topeRegalosDefecto);
      expect(vacio.puedeAbrir, isFalse);
      final raro = EstadoRegalos.desdeJson({'minutos': 900, 'tope_abrir': 0, 'tope_envios': '99', 'abiertos_hoy': 7, 'regalos': ['x', 3]});
      expect(raro.minutos, 60);
      expect(raro.topeAbrir, 1);
      expect(raro.topeEnvios, 10);
      expect(raro.abrirQuedan, 0);
      expect(raro.regalos, isEmpty);
    });
    test('apagado: no se abre ni se regala', () {
      final e = EstadoRegalos.desdeJson({..._estado(), 'activo': false});
      expect(e.puedeAbrir, isFalse);
      expect(e.puedeRegalarA('c'), isFalse);
    });
    test('tope de abrir y de enviar', () {
      expect(EstadoRegalos.desdeJson(_estado(abiertos: 5)).puedeAbrir, isFalse);
      expect(EstadoRegalos.desdeJson(_estado(enviados: 5)).puedeRegalarA('c'), isFalse);
    });
    test('trasAbrir cuenta y quita; sinRegalo solo quita', () {
      final e = EstadoRegalos.desdeJson(_estado());
      final a = e.trasAbrir('g1');
      expect(a.abiertosHoy, 1);
      expect(a.regalos.map((r) => r.id), ['g2']);
      final s = e.sinRegalo('g2');
      expect(s.abiertosHoy, 0);
      expect(s.regalos.map((r) => r.id), ['g1']);
    });
    test('trasRegalar: tope, amigo y dados (el del servidor si es mayor)', () {
      final e = EstadoRegalos.desdeJson(_estado());
      final r = e.trasRegalar('c', 8);
      expect(r.enviadosHoy, 1);
      expect(r.puedeRegalarA('c'), isFalse);
      expect(r.dados, 8);
      expect(e.trasRegalar('c', 0).dados, 4);
    });
  });

  test('ResultadoRegalo.desdeJson', () {
    final ok = ResultadoRegalo.desdeJson({'ok': true, 'id': 7, 'minutos': 30, 'mutuo': true, 'en_chat': true, 'dados': '2'});
    expect(ok.ok, isTrue);
    expect(ok.id, '7');
    expect(ok.minutos, 30);
    expect(ok.mutuo, isTrue);
    expect(ok.enChat, isTrue);
    expect(ok.dados, 2);
    final no = ResultadoRegalo.desdeJson({'ok': false, 'motivo': 'ya_hoy'});
    expect(no.ok, isFalse);
    expect(no.motivo, 'ya_hoy');
    expect(ResultadoRegalo.desdeJson(null).ok, isFalse);
    expect(ResultadoRegalo.desdeJson({'ok': true, 'minutos': 999}).minutos, 60);
  });

  test('textoMotivoRegalo: cada motivo tiene texto y lo desconocido cae en el genérico', () {
    final generico = textoMotivoRegalo('otra_cosa');
    for (final m in ['no_amigos', 'ya_hoy', 'tope_envios', 'tope_recibidos', 'tope_abrir', 'ya_abierto', 'vencido', 'no_existe', 'apagado']) {
      expect(textoMotivoRegalo(m), isNot(generico), reason: m);
    }
    expect(textoMotivoRegalo(null), generico);
  });

  group('logros de regalos', () {
    test('están en el catálogo; el mutuo es oculto', () {
      final ids = {for (final l in logros) l.id: l};
      expect(ids.keys, containsAll(['regalo_primero', 'regalo_diez', 'regalo_mutuo']));
      expect(ids['regalo_mutuo']!.oculto, isTrue);
      expect(ids['regalo_primero']!.oculto, isFalse);
    });
    test('según lo que contó el servidor, y una sola vez', () {
      final i = _imperio();
      expect(i.logrosDeRegalos(), isEmpty);
      expect(i.logrosDeRegalos(dados: 1).map((l) => l.id), ['regalo_primero']);
      expect(i.logrosDeRegalos(dados: 1), isEmpty);
      expect(i.logrosDeRegalos(dados: 12).map((l) => l.id), ['regalo_diez']);
      expect(i.logrosDeRegalos(mutuo: true).map((l) => l.id), ['regalo_mutuo']);
      expect(i.logrosDeRegalos(dados: 20, mutuo: true), isEmpty);
    });
    test('la revisión normal de logros no los da sola', () {
      final i = _imperio();
      i.revisarLogros();
      expect(i.tieneLogro('regalo_primero') || i.tieneLogro('regalo_diez') || i.tieneLogro('regalo_mutuo'), isFalse);
    });
  });

  group('ControlImperio.abrirRegalo', () {
    test('ok: suma los MJ, quita el Rollo, cuenta el tope, da el mutuo y lo anota', () async {
      final tele = Telemetria(enviar: (_) async => 0);
      final nube = _NubeRegalos({'ok': true, 'minutos': 30, 'mutuo': true});
      final c = _control(nube, tele: tele);
      final antes = c.imperio.saldo;
      final g = c.regalos!.regalos.first;
      final (r, mj) = await c.abrirRegalo(g);
      expect(r.ok, isTrue);
      expect(nube.abiertos, ['g1']);
      expect(mj, greaterThan(13));
      expect(c.imperio.saldo, closeTo(antes + mj, 1e-6));
      expect(c.regalos!.regalos.map((x) => x.id), ['g2']);
      expect(c.regalos!.abiertosHoy, 1);
      expect(c.logrosNuevos.map((l) => l.id), contains('regalo_mutuo'));
      expect(tele.cola.map((e) => e['evento']), contains('imperio_regalo_abre'));
    });
    test('ya_abierto: se quita sin contar y no da MJ', () async {
      final c = _control(_NubeRegalos({'ok': false, 'motivo': 'ya_abierto'}));
      final antes = c.imperio.saldo;
      final (r, mj) = await c.abrirRegalo(c.regalos!.regalos.first);
      expect(r.motivo, 'ya_abierto');
      expect(mj, 0);
      expect(c.imperio.saldo, antes);
      expect(c.regalos!.regalos.map((x) => x.id), ['g2']);
      expect(c.regalos!.abiertosHoy, 0);
    });
    test('tope_abrir: el Rollo se queda para mañana', () async {
      final c = _control(_NubeRegalos({'ok': false, 'motivo': 'tope_abrir'}));
      final (_, mj) = await c.abrirRegalo(c.regalos!.regalos.first);
      expect(mj, 0);
      expect(c.regalos!.regalos.length, 2);
    });
    test('sin red: lanza y no toca nada', () async {
      final c = _control(_NubeRegalos(Exception('sin red')));
      final antes = c.imperio.saldo;
      await expectLater(c.abrirRegalo(c.regalos!.regalos.first), throwsException);
      expect(c.imperio.saldo, antes);
      expect(c.regalos!.regalos.length, 2);
    });
    test('regaloHecho pone los topes al día', () {
      final c = _control(_NubeRegalos(null));
      c.regaloHecho('b', const ResultadoRegalo(ok: true, dados: 4));
      expect(c.regalos!.enviadosHoy, 1);
      expect(c.regalos!.puedeRegalarA('b'), isFalse);
      c.regaloHecho('c', const ResultadoRegalo(ok: false, motivo: 'ya_hoy'));
      expect(c.regalos!.enviadosHoy, 1);
    });
    test('cargarRegalos trae los pendientes', () async {
      final c = _control(_NubeRegalos(null))..regalos = null;
      await c.cargarRegalos();
      expect(c.regalos!.regalos.map((x) => x.id), ['g1']);
      expect(hayRegalos(c), isTrue);
    });
  });

  group('pantalla', () {
    Widget app(Widget hijo) => MaterialApp(home: Scaffold(body: Center(child: hijo)));

    testWidgets('chip ×N abre la hoja; ABRIR muestra el premio y quita el Rollo', (t) async {
      final c = _control(_NubeRegalos({'ok': true, 'minutos': 30}));
      await t.pumpWidget(app(ListenableBuilder(listenable: c, builder: (_, _) => ChipRegalos(control: c, avisar: (_, _) {}))));
      expect(find.text('×2'), findsOneWidget);
      await t.tap(find.byKey(const Key('chip_regalos')));
      await t.pumpAndSettle();
      expect(find.text('De amigo1'), findsOneWidget);
      await t.tap(find.byKey(const Key('abrir_regalo_g1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('premio_regalo')), findsOneWidget);
      expect(find.textContaining('del regalo de amigo1'), findsOneWidget);
      expect(find.text('De amigo1'), findsNothing);
      expect(find.text('×1'), findsOneWidget);
    });

    testWidgets('con el tope de hoy lleno, ABRIR sale apagado', (t) async {
      final c = _control(_NubeRegalos(null))..regalos = EstadoRegalos.desdeJson(_estado(abiertos: 5));
      await t.pumpWidget(app(ListenableBuilder(listenable: c, builder: (_, _) => ChipRegalos(control: c, avisar: (_, _) {}))));
      await t.tap(find.byKey(const Key('chip_regalos')));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.byKey(const Key('abrir_regalo_g1'))).onPressed, isNull);
      expect(find.text(textoMotivoRegalo('tope_abrir')), findsOneWidget);
    });

    testWidgets('sin Rollos el chip no sale', (t) async {
      final c = _control(_NubeRegalos(null))..regalos = EstadoRegalos.desdeJson(_estado(n: 0));
      await t.pumpWidget(app(ChipRegalos(control: c, avisar: (_, _) {})));
      expect(find.byKey(const Key('chip_regalos')), findsNothing);
      expect(hayRegalos(c), isFalse);
    });
  });

  group('tarjetas del chat', () {
    Widget app(Widget hijo) => MaterialApp(home: Scaffold(body: Center(child: hijo)));
    const t = {'tipo': 'regalo', 'id': 'g1', 'de': 'u1', 'para': 'u2', 'de_nombre': 'ana', 'para_nombre': 'beto'};

    testWidgets('regalo para mí y sin abrir: sale ABRIR', (tester) async {
      await tester.pumpWidget(app(TarjetaRegalo(t, yo: 'u2', sinAbrir: (_) async => true)));
      await tester.pump();
      expect(find.text('REGALO'), findsOneWidget);
      expect(find.byKey(const Key('abrir_regalo_chat')), findsOneWidget);
    });

    testWidgets('regalo ya abierto o de otro: sin ABRIR', (tester) async {
      await tester.pumpWidget(app(TarjetaRegalo(t, yo: 'u2', sinAbrir: (_) async => false)));
      await tester.pump();
      expect(find.byKey(const Key('abrir_regalo_chat')), findsNothing);
      var preguntado = false;
      await tester.pumpWidget(app(TarjetaRegalo(t, key: const Key('otra'), yo: 'u9', sinAbrir: (_) async => preguntado = true)));
      await tester.pump();
      expect(preguntado, isFalse);
      expect(find.byKey(const Key('abrir_regalo_chat')), findsNothing);
    });

    testWidgets('regalo sin nombres: texto genérico', (tester) async {
      await tester.pumpWidget(app(TarjetaRegalo(const {'tipo': 'regalo', 'id': 'g1'}, yo: 'u2', sinAbrir: (_) async => true)));
      await tester.pump();
      expect(find.text('REGALO'), findsOneWidget);
      expect(find.byKey(const Key('abrir_regalo_chat')), findsNothing);
    });

    testWidgets('imperio: título en mayúsculas, línea, y sin datos no revienta', (tester) async {
      await tester.pumpWidget(app(const TarjetaImperio({'tipo': 'imperio', 'emoji': '🏛️', 'titulo': 'Mudanza', 'linea': 'Se mudó de casa'})));
      expect(find.textContaining('MUDANZA', findRichText: true), findsOneWidget);
      expect(find.textContaining('Se mudó de casa', findRichText: true), findsOneWidget);
      await tester.pumpWidget(app(const TarjetaImperio({'tipo': 'imperio'})));
      expect(find.textContaining('IMPERIO', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
