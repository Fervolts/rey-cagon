// La escalera de capas (hojas de la Cadena y la Mudanza), los dedos de la primera vez (dedo.dart) y "¿Qué hago ahora?"
// (que_hago.dart, hoja_que_hago.dart).
// Capturas: CAPTURAS_DEDO=1 flutter test test/imperio_dedo_test.dart (escribe PNG en build/capturas_dedo/).
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/barra.dart';
import 'package:rey_cagon/imperio/cadena.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/dedo.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/mudanza.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/pantalla.dart';
import 'package:rey_cagon/imperio/que_hago.dart';
import 'package:rey_cagon/imperio/telemetria.dart';
import 'package:rey_cagon/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const t0 = 1800000000000;

/// Nube sin red: carga [estado] del teléfono y no guarda nada.
class _Nube extends NubeImperio {
  _Nube(this.estado, [this.espera]);
  final Map<String, dynamic> estado;

  /// Si está, la carga espera a que se complete (para abrir un diálogo antes de que la pantalla cargue).
  final Completer<void>? espera;
  @override
  Future<Map<String, dynamic>?> cargarLocal(String userId) async {
    await espera?.future;
    return {'estado': estado, 'mjTotal': 0.0};
  }
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}
  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async => throw StateError('sin red');
  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

/// Jugador nuevo: sin cagadas (todo lo de candado cerrado), sin edificios.
Imperio _nuevo() => Imperio(azar: Random(1));

/// Veterano: 30 cagadas, ya vio atascos, jaló 3 veces, tiene Rollos, edificios, mejoras y una historia enorme de MJ.
Imperio _veterano() {
  final im = Imperio(cagadas: 30, azar: Random(1));
  final p = im.partida;
  p.vioPrimerAtasco = true;
  p.jaladas = 3;
  p.rollos = 10;
  p.mjTotal = 1e15;
  for (final e in edificios.where((e) => e.fase1).take(5)) {
    p.edificios[e.id] = 25;
  }
  p.saldo = 1e9;
  for (final m in im.mejorasDisponibles().take(3)) {
    p.mejoras.add(m.id);
  }
  return im;
}

/// Estado guardado como lo deja el control (con `_cagadas`, que no va en la partida). Guardado recién, para que no
/// salga el aviso de lo ganado sin jugar (ese diálogo va antes que los dedos y tiene su propia prueba).
Map<String, dynamic> _estado(Imperio im, {int cagadas = 0}) =>
    {...im.toJson(), 'ultima_vez': DateTime.now().millisecondsSinceEpoch, '_cagadas': cagadas};

List<(Object?, Object?)> _eventos(List<Map<String, Object?>> enviados, Telemetria tele, String evento, String campo) => [
      for (final e in [...enviados, ...tele.cola])
        if (e['evento'] == evento) ((e['datos'] as Map)[campo], (e['datos'] as Map)['accion']),
    ];

/// Monta la pantalla del Imperio con [estado] y deja que cargue. Devuelve el control y la telemetría capturada.
Future<(ControlImperio, Telemetria, List<Map<String, Object?>>)> _montar(WidgetTester t, Map<String, dynamic> estado,
    {GlobalKey<NavigatorState>? nav, Completer<void>? espera, ThemeData? tema, Key? foto}) async {
  final enviados = <Map<String, Object?>>[];
  final tele = Telemetria(enviar: (lote) async {
    enviados.addAll(lote);
    return lote.length;
  });
  final c = ControlImperio(
      nube: _Nube(estado, espera), telemetria: tele, pedirFlags: () async => throw StateError('sin red'), leerBuild: () async => 1);
  await t.pumpWidget(MaterialApp(
    navigatorKey: nav,
    theme: tema,
    builder: foto == null ? null : (context, hijo) => RepaintBoundary(key: foto, child: hijo),
    home: PantallaImperio(activo: true, control: c),
  ));
  await _esperar(t);
  return (c, tele, enviados);
}

Future<void> _esperar(WidgetTester t, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Espera (hasta 6 s de juego) a que salga un dedo: los avisos de la carga van antes.
Future<void> _hastaDedo(WidgetTester t) async {
  for (var i = 0; i < 60 && find.byKey(const Key('dedo')).evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _desmontar(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

/// Hay algún widget con una llave que empieza por [prefijo] (filas de la Plomería, del Llavero...).
Finder _conPrefijo(String prefijo) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefijo));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'http://localhost:1',
        publishableKey: 'x',
        authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), detectSessionInUri: false));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('¿Qué hago ahora? (pura)', () {
    test('atasco abierto: destapar; con dos o más y el Robot abierto, el Robot', () {
      final im = _veterano();
      final id = im.partida.edificios.keys.first;
      im.partida.atasco = Atasco(id, t0);
      final s = queHagoAhora(im, t0);
      expect(s.id, 'destapar');
      expect(s.objetivo, id);
      expect(s.ir, DestinoQueHago.cerrar);

      final otro = im.partida.edificios.keys.elementAt(1);
      im.partida.atascos = [Atasco(id, t0), Atasco(otro, t0)];
      expect(im.objetoAbierto('robot'), isTrue);
      final r = queHagoAhora(im, t0);
      expect(r.id, 'robot');
      expect(r.ir, DestinoQueHago.tienda);
      expect(r.texto, contains('2'));
    });

    test('nada comprable y nada que entre solo: pujar, con los toques que faltan', () {
      final im = _nuevo();
      expect(im.mps(t0), 0);
      final s = queHagoAhora(im, t0);
      expect(s.id, 'pujar');
      expect(s.ir, DestinoQueHago.cerrar);
      expect(s.texto, contains('toques'));
      expect(s.objetivo, isNotNull);
    });

    test('no alcanza pero algo entra solo: esperar lo que falta para la mejor compra', () {
      final im = _nuevo();
      // El primero que produce solo (el Dedo suma por pujo, no por segundo).
      final e = edificios.firstWhere((e) {
        final prueba = _nuevo()..partida.edificios[e.id] = 1;
        return prueba.mps(t0) > 0;
      });
      im.partida.edificios[e.id] = 3;
      im.partida.saldo = 0;
      expect(im.mps(t0), greaterThan(0));
      final s = queHagoAhora(im, t0);
      expect(s.id, 'esperar');
      final meta = mejorCompra(im, t0)!;
      expect(s.objetivo, meta.id);
      expect(s.segundos, (meta.precio / im.mps(t0)).ceil());
      expect(s.texto, contains('Puja o espera'));
    });

    test('edificio con mejor retorno: el que alcanza y se paga más rápido', () {
      final im = _nuevo();
      im.partida.edificios[edificios.first.id] = 3;
      im.partida.saldo = 1e30;
      final todas = comprasPosibles(im, t0);
      expect(todas.length, greaterThan(1));
      final mejor = todas.reduce((a, b) => a.retorno <= b.retorno ? a : b);
      final s = queHagoAhora(im, t0);
      expect(s.objetivo, mejor.id);
      expect(s.id, mejor.esEdificio ? 'edificio' : 'mejora');
      expect(s.ir, DestinoQueHago.edificios);

      // Solo edificios: el de menor retorno entre los edificios.
      final soloE = mejorCompra(im, t0, soloEdificios: true)!;
      expect(soloE.esEdificio, isTrue);
      for (final c in comprasPosibles(im, t0, soloEdificios: true)) {
        expect(soloE.retorno, lessThanOrEqualTo(c.retorno));
      }
      // Probar las compras no cambia la partida.
      expect(im.partida.edificios, {edificios.first.id: 3});
      expect(im.partida.mejoras, isEmpty);
    });

    test('con poca plata sale el edificio barato que alcanza, no el caro', () {
      final im = _nuevo();
      final e = edificios.first;
      im.partida.saldo = im.precioEdificio(e.id, t0);
      final s = queHagoAhora(im, t0);
      expect(s.id, 'edificio');
      expect(s.objetivo, e.id);
    });

    test('cadena que conviene: jalar antes que comprar, solo con la cadena lista', () {
      final im = _veterano();
      final j = cuentaJalar(im);
      expect(j.nuevos, greaterThan(0));
      expect(j.salto, greaterThanOrEqualTo(saltoRollosConviene));
      final s = queHagoAhora(im, t0, cadenaLista: true);
      expect(s.id, 'jalar');
      expect(s.ir, DestinoQueHago.jalar);
      expect(s.texto, contains('Rollos de Oro'));
      // Sin la cadena lista (faltan cagadas reales) no la sugiere.
      expect(queHagoAhora(im, t0).id, isNot('jalar'));
    });

    test('cadena que no conviene: pocos rollos nuevos no tapan la compra', () {
      final im = _veterano();
      im.partida.rollos = 1000000;
      im.partida.rollosGastados = 0;
      expect(jalarConviene(im, cadenaLista: true), isFalse);
      expect(queHagoAhora(im, t0, cadenaLista: true).id, isNot('jalar'));
    });

    test('veterano con todo: el dorado manda sobre comprar y el atasco sobre el dorado', () {
      final im = _veterano();
      im.partida.dorado = const DoradoVisible(t0, t0 + 60000, .5, .5);
      expect(queHagoAhora(im, t0, cadenaLista: true).id, 'dorado');
      im.partida.atasco = Atasco(im.partida.edificios.keys.first, t0);
      expect(queHagoAhora(im, t0, cadenaLista: true).id, 'destapar');
    });

    test('mudanza lista: mudarse va antes que jalar; sin requisitos, nunca', () {
      final im = _veterano();
      final s = queHagoAhora(im, t0, cadenaLista: true, mudanzaLista: true);
      expect(s.id, 'mudanza');
      expect(s.ir, DestinoQueHago.mudanza);
      expect(s.titulo, contains('Casa'));
      expect(s.texto, contains('x3'));
      expect(queHagoAhora(im, t0, cadenaLista: true).id, 'jalar');
    });

    test('Plomería: sugiere el nivel que rinde aun gastando Rollos; sin Rollos, no', () {
      final im = _veterano();
      im.partida.rollos = 100;
      final pl = plomeriaConviene(im, t0);
      expect(pl, isNotNull);
      expect(pl!.salto, greaterThanOrEqualTo(saltoPlomeriaConviene));
      final s = queHagoAhora(im, t0);
      expect(s.id, 'plomeria');
      expect(s.ir, DestinoQueHago.jalar);
      expect(s.texto, contains('Cadena'));
      expect(s.objetivo, pl.objeto.id);
      // La prueba deshace la compra.
      expect(im.partida.rollos, 100);
      expect(im.partida.objetosRollos, isEmpty);
      im.partida.rollos = 1;
      expect(plomeriaConviene(im, t0), isNull);
      // Antes de la primera jalada la Plomería está cerrada.
      im.partida
        ..rollos = 100
        ..jaladas = 0;
      expect(plomeriaConviene(im, t0), isNull);
    });

    test('duraciones y porcentajes cortos', () {
      expect(duracionCorta(40), '40 s');
      expect(duracionCorta(720), '12 min');
      expect(duracionCorta(3 * 3600), '3 h');
      expect(duracionCorta(2 * 86400), '2 d');
      expect(pctRollos(10, 0.02), '+20%');
    });
  });

  group('Escalera en la pantalla', () {
    testWidgets('¿Qué hago? abre la hoja e IR la cierra', (t) async {
      final (c, tele, enviados) = await _montar(t, _estado(_nuevo()));
      await t.tap(find.byKey(const Key('boton_que_hago')));
      await _esperar(t);
      expect(find.byKey(const Key('hoja_que_hago')), findsOneWidget);
      final s = queHagoAhora(c.imperio, c.ahora);
      expect(_eventos(enviados, tele, 'imperio_que_hago', 'sugerencia'), [(s.id, 'abrir')]);
      await t.tap(find.byKey(const Key('que_hago_ir')));
      await _esperar(t);
      expect(find.byKey(const Key('hoja_que_hago')), findsNothing);
      expect(_eventos(enviados, tele, 'imperio_que_hago', 'sugerencia').last, (s.id, 'ir'));
      await _desmontar(t);
    });

    testWidgets('un JSON viejo sin las claves nuevas carga', (t) async {
      // Guardado de antes: sin guia_vista ni nada de esta versión, pero con la guía de alquileres vista en otro caso.
      final viejo = Partida.desdeJson({'saldo': 120.0, 'edificios': {edificios.first.id: 2}});
      expect(viejo.guiaVista, isEmpty);
      expect(viejo.edificios[edificios.first.id], 2);
      final conGuia = Partida.desdeJson({'saldo': 1.0, 'guia_vista': ['primo']});
      expect(conGuia.guiaVista, {'primo'});

      final (c, _, _) = await _montar(t, {'saldo': 120.0, 'edificios': {edificios.first.id: 2}, 'guia_vista': ['primo']});
      expect(c.imperio.partida.edificios[edificios.first.id], 2);
      expect(find.byKey(const Key('boton_mudanza')), findsNothing);
      await _desmontar(t);
    });

    testWidgets('JALAR abre la hoja de la Cadena: tarjeta, lo que falta y la Plomería; la TIENDA ya no la trae', (t) async {
      final (_, tele, enviados) = await _montar(t, _estado(_veterano(), cagadas: 30));
      await t.tap(find.byKey(const Key('boton_jalar')));
      await _esperar(t);
      expect(find.byKey(const Key('decision_cadena')), findsOneWidget);
      // Sin red no se sabe cuántas cagadas reales lleva: sale lo que falta y el JALAR de adentro apagado.
      expect(find.byKey(const Key('cadena_falta')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('cadena_jalar'))).onPressed, isNull);
      expect(_conPrefijo('pagar_rollos_'), findsWidgets);
      expect(_eventos(enviados, tele, 'cadena_abre', 'puede').length, 1);
      Navigator.of(t.element(find.byKey(const Key('decision_cadena')))).pop();
      await _esperar(t);
      expect(find.byKey(const Key('decision_cadena')), findsNothing);

      await t.tap(find.byKey(const Key('boton_tienda')));
      await _esperar(t);
      expect(_conPrefijo('pagar_rollos_'), findsNothing);
      expect(_conPrefijo('llavero_'), findsNothing);
      expect(t.takeException(), isNull);
      await _desmontar(t);
    });

    testWidgets('MUDANZA no sale al jugador nuevo; descubierta sale con su hoja y deja de brillar al abrirla', (t) async {
      await _montar(t, _estado(_nuevo()));
      expect(find.byKey(const Key('boton_mudanza')), findsNothing);
      await _desmontar(t);

      final im = _veterano();
      im.partida.guiaVista.add(claveMudanzaVista);
      final (c, _, _) = await _montar(t, _estado(im, cagadas: 30));
      expect(find.byKey(const Key('boton_mudanza')), findsOneWidget);
      expect(mudanzaResaltada(c), isTrue);
      await t.tap(find.byKey(const Key('boton_mudanza')));
      await _esperar(t);
      expect(find.byKey(const Key('decision_mudanza')), findsOneWidget);
      expect(find.byKey(const Key('mudarse')), findsOneWidget);
      // La capa 3 (🔒 ???) se asoma después de la primera mudanza.
      expect(find.byKey(const Key('capa_3_candado')), findsNothing);
      expect(_conPrefijo('llavero_'), findsWidgets);
      expect(c.imperio.partida.guiaVista, contains(claveMudanzaAbierta));
      expect(mudanzaResaltada(c), isFalse);
      expect(t.takeException(), isNull);
      await _desmontar(t);
    });

    testWidgets('la primera vez que se descubre: marca la clave y avisa "Ya no cabes"', (t) async {
      final im = _veterano();
      im.partida.mudanzas = 1;
      final (c, _, _) = await _montar(t, _estado(im, cagadas: 30));
      expect(c.imperio.partida.guiaVista, contains(claveMudanzaVista));
      // El aviso va a la cola (detrás de los logros del veterano).
      final aviso = find.textContaining('Ya no cabes en esta casa', findRichText: true);
      for (var i = 0; i < 600 && aviso.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(aviso, findsOneWidget);
      await t.tap(find.byKey(const Key('boton_mudanza')));
      await _esperar(t);
      expect(find.byKey(const Key('capa_3_candado')), findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('la barra con sus 5 botones cabe en 360 dp', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 360,
              child: BarraImperio(
                  jalar: const BotonJalar(EstadoJalar.listo, rollos: 12),
                  moneda: 'MjBs',
                  alObjetos: () {},
                  alJalar: () {},
                  alSala: () {},
                  alEdificios: () {},
                  mudanza: true,
                  mudanzaResaltada: true,
                  alMudanza: () {}),
            ),
          ),
        ),
      ));
      await t.pump();
      for (final k in ['boton_edificios', 'boton_tienda', 'boton_jalar', 'boton_mudanza']) {
        expect(find.byKey(Key(k)), findsOneWidget);
      }
      expect(find.text('SALA'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('Dedos (pura)', () {
    test('nuevo: la poceta; vista, nada hasta que alcance un cagador', () {
      final im = _nuevo();
      final d = siguienteDedo(im, t0, cajonAbierto: false);
      expect(d?.paso, 'poceta');
      expect(d?.objetivo, const Key('dedo_poceta'));
      // Con el cajón abierto no se señala la poceta (queda tapada).
      expect(siguienteDedo(im, t0, cajonAbierto: true), isNull);
      im.partida.guiaVista.add(claveDedo('poceta'));
      expect(siguienteDedo(im, t0, cajonAbierto: false), isNull);
    });

    test('alcanza el primer cagador: CAGADORES con el cajón cerrado, la fila con el cajón abierto', () {
      final im = _nuevo();
      final e = edificios.first;
      im.partida.saldo = im.precioEdificioVarios(e.id, 1, t0) * 2;
      im.partida.mjTotal = im.partida.saldo;
      expect(primerEdificioComprable(im, t0)?.id, e.id);
      final cerrado = siguienteDedo(im, t0, cajonAbierto: false);
      expect(cerrado?.paso, 'cagadores');
      expect(cerrado?.objetivo, const Key('boton_edificios'));
      final abierto = siguienteDedo(im, t0, cajonAbierto: true);
      expect(abierto?.paso, 'cagadores_fila');
      expect(abierto?.objetivo, Key('fila_${e.id}'));
      // Comprado uno: ya no.
      im.partida.edificios[e.id] = 1;
      im.partida.guiaVista.add(claveDedo('mejora'));
      im.partida.guiaVista.add(claveDedo('mejora_flecha'));
      im.partida.guiaVista.add(claveDedo('mejora_comprar'));
      expect(siguienteDedo(im, t0, cajonAbierto: false), isNull);
      expect(siguienteDedo(im, t0, cajonAbierto: true), isNull);
    });

    test('la primera mejora: CAGADORES, la flecha de su fila y su botón', () {
      final im = _nuevo();
      im.partida.edificios[edificios.first.id] = 1;
      im.partida.saldo = 1e12;
      im.partida.mjTotal = 1e12;
      final m = primeraMejoraComprable(im)!;
      final clave = m.edificio ?? 'poceta';
      expect(siguienteDedo(im, t0, cajonAbierto: false)?.paso, 'mejora');
      final flecha = siguienteDedo(im, t0, cajonAbierto: true);
      expect(flecha?.paso, 'mejora_flecha');
      expect(flecha?.objetivo, Key('flecha_$clave'));
      final comprar = siguienteDedo(im, t0, cajonAbierto: true, abiertos: {clave});
      expect(comprar?.paso, 'mejora_comprar');
      expect(comprar?.objetivo, Key('comprar_mejora_${m.id}'));
      im.partida.mejoras.add(m.id);
      expect(siguienteDedo(im, t0, cajonAbierto: true, abiertos: {clave}), isNull);
    });

    test('la Cadena abierta: JALAR (si se ve); la Mudanza descubierta: MUDANZA', () {
      final im = _nuevo();
      im.partida.edificios[edificios.first.id] = 1;
      im.partida.mejoras.add('cadena_trono');
      expect(im.cadenaDesbloqueada, isTrue);
      expect(siguienteDedo(im, t0, cajonAbierto: false), isNull);
      final j = siguienteDedo(im, t0, cajonAbierto: false, jalarVisible: true);
      expect(j?.paso, 'jalar');
      expect(j?.objetivo, const Key('boton_jalar'));
      im.partida.guiaVista.add(claveDedo('jalar'));
      final m = siguienteDedo(im, t0, cajonAbierto: false, jalarVisible: true, mudanza: true);
      expect(m?.paso, 'mudanza');
      expect(m?.objetivo, const Key('boton_mudanza'));
    });

    test('veterano: ningún dedo de la corrida (ya jaló); solo la Mudanza si la descubre', () {
      final im = _veterano();
      im.partida.mejoras.clear();
      im.partida.edificios.clear();
      im.partida.mjTotal = 0;
      for (final abierto in [false, true]) {
        expect(siguienteDedo(im, t0, cajonAbierto: abierto, jalarVisible: true), isNull);
      }
      expect(siguienteDedo(im, t0, cajonAbierto: false, jalarVisible: true, mudanza: true)?.paso, 'mudanza');
      im.partida.mudanzas = 1;
      expect(siguienteDedo(im, t0, cajonAbierto: false, jalarVisible: true, mudanza: true), isNull);
    });
  });

  group('Dedos en la pantalla', () {
    testWidgets('nuevo: el dedo de la poceta sale una vez, el toque pasa de largo y lo quita, y no vuelve', (t) async {
      final (c, tele, enviados) = await _montar(t, _estado(_nuevo()));
      expect(find.byKey(const Key('dedo')), findsOneWidget);
      expect(find.textContaining('Toca para pujar', findRichText: true), findsOneWidget);
      expect(c.imperio.partida.guiaVista, contains(claveDedo('poceta')));
      expect(_eventos(enviados, tele, 'imperio_dedo', 'paso'), [('poceta', 'ver')]);

      final antes = c.imperio.mjTotal;
      await t.tap(find.byKey(const Key('dedo_poceta')));
      await _esperar(t);
      expect(c.imperio.mjTotal, greaterThan(antes), reason: 'el toque llega a la poceta');
      expect(find.byKey(const Key('dedo')), findsNothing);
      expect(_eventos(enviados, tele, 'imperio_dedo', 'paso'), [('poceta', 'ver'), ('poceta', 'toque')]);
      await _esperar(t, 20);
      expect(find.byKey(const Key('dedo')), findsNothing);
      expect(t.takeException(), isNull);
      await _desmontar(t);
    });

    testWidgets('alcanza el primer cagador: dedo en CAGADORES y, abierto el cajón, en la fila', (t) async {
      final im = _nuevo();
      im.partida.guiaVista.add(claveDedo('poceta'));
      // Los ajustes de la pantalla escalan los precios: sobra para el primero con cualquier escala.
      im.partida.saldo = edificios.first.precioBase * 100;
      im.partida.mjTotal = im.partida.saldo;
      final (_, tele, enviados) = await _montar(t, _estado(im));
      await _hastaDedo(t);
      expect(find.byKey(const Key('dedo')), findsOneWidget);
      await t.tap(find.byKey(const Key('boton_edificios')));
      await _esperar(t);
      await _hastaDedo(t);
      expect(find.byKey(Key('fila_${edificios.first.id}')), findsOneWidget);
      expect(find.byKey(const Key('dedo')), findsOneWidget);
      expect(_eventos(enviados, tele, 'imperio_dedo', 'paso'), [('cagadores', 'ver'), ('cagadores', 'toque'), ('cagadores_fila', 'ver')]);
      expect(t.takeException(), isNull);
      await _desmontar(t);
    });

    testWidgets('con otra pantalla encima no sale; al volver, sí', (t) async {
      final nav = GlobalKey<NavigatorState>();
      final espera = Completer<void>();
      final (c, tele, enviados) = await _montar(t, _estado(_nuevo()), nav: nav, espera: espera);
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('encima')))));
      await _esperar(t);
      espera.complete();
      await _esperar(t, 20);
      expect(c.cargando, isFalse);
      expect(_eventos(enviados, tele, 'imperio_dedo', 'paso'), isEmpty);
      nav.currentState!.pop();
      await _esperar(t);
      expect(find.byKey(const Key('dedo')), findsOneWidget);
      expect(_eventos(enviados, tele, 'imperio_dedo', 'paso'), [('poceta', 'ver')]);
      await _desmontar(t);
    });

    testWidgets('veterano: ningún dedo', (t) async {
      final (_, tele, enviados) = await _montar(t, _estado(_veterano(), cagadas: 30));
      await _esperar(t, 20);
      expect(find.byKey(const Key('dedo')), findsNothing);
      expect(_eventos(enviados, tele, 'imperio_dedo', 'paso'), isEmpty);
      await _desmontar(t);
    });
  });

  group('Capturas', () {
    final capturas = Platform.environment['CAPTURAS_DEDO'] != null;
    testWidgets('hojas de la escalera a PNG', (t) async {
      await _cargarLetras();
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final llave = GlobalKey();

      Future<void> foto(String nombre) async {
        await t.runAsync(() async {
          for (final el in find.byType(Image).evaluate()) {
            await precacheImage((el.widget as Image).image, el);
          }
        });
        await _esperar(t, 5);
        final borde = llave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await t.runAsync(() async {
          final img = await borde.toImage(pixelRatio: 3);
          return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        });
        final f = File('build/capturas_dedo/$nombre.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(png!);
      }

      Future<void> cerrarHoja(Key dentro) async {
        Navigator.of(t.element(find.byKey(dentro))).pop();
        await _esperar(t);
      }

      for (final (brillo, sufijo) in [(Brightness.dark, 'oscuro'), (Brightness.light, 'claro')]) {
        final estilo = _conLetraEnBotones(tema(brillo));
        // Nuevo: la pantalla de entrada y el ¿Qué hago?.
        await _montar(t, _estado(_nuevo()), tema: estilo, foto: llave);
        await foto('nuevo_$sufijo');
        await t.tap(find.byKey(const Key('boton_que_hago')));
        await _esperar(t);
        await foto('que_hago_$sufijo');
        await _desmontar(t);

        // El dedo del primer cagador, con el cajón cerrado.
        final listo = _nuevo();
        listo.partida.guiaVista.add(claveDedo('poceta'));
        listo.partida.saldo = listo.precioEdificioVarios(edificios.first.id, 1, t0) * 2;
        listo.partida.mjTotal = listo.partida.saldo;
        await _montar(t, _estado(listo), tema: estilo, foto: llave);
        await foto('dedo_cagadores_$sufijo');
        await _desmontar(t);

        // Veterano con la mudanza descubierta: la barra de 5, la Cadena y la Mudanza.
        final im = _veterano();
        im.partida.guiaVista.add(claveMudanzaVista);
        await _montar(t, _estado(im, cagadas: 30), tema: estilo, foto: llave);
        await foto('veterano_$sufijo');
        await t.tap(find.byKey(const Key('boton_jalar')));
        await _esperar(t);
        await foto('cadena_$sufijo');
        await cerrarHoja(const Key('decision_cadena'));
        await t.tap(find.byKey(const Key('boton_mudanza')));
        await _esperar(t);
        await foto('mudanza_$sufijo');
        await cerrarHoja(const Key('decision_mudanza'));
        await _desmontar(t);
      }
    }, skip: !capturas);
  });
}

/// Los botones del tema no dicen familia y en las pruebas eso sale en bloques: en las capturas van con la cargada.
ThemeData _conLetraEnBotones(ThemeData t) {
  ButtonStyle? conLetra(ButtonStyle? s) =>
      s?.copyWith(textStyle: WidgetStatePropertyAll((s.textStyle?.resolve({}) ?? const TextStyle()).copyWith(fontFamily: 'Roboto')));
  return t.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: conLetra(t.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: conLetra(t.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: conLetra(t.textButtonTheme.style)),
  );
}

/// Letras de verdad para las capturas (en las pruebas todo sale en bloques): Arial del sistema si está.
Future<void> _cargarLetras() async {
  const rutas = ['/System/Library/Fonts/Supplemental/Arial.ttf', '/System/Library/Fonts/Supplemental/Arial Bold.ttf'];
  final carga = FontLoader('Roboto');
  var alguna = false;
  for (final r in rutas) {
    final f = File(r);
    if (!f.existsSync()) continue;
    alguna = true;
    carga.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  if (alguna) await carga.load();
  try {
    final emojis = await rootBundle.load('assets/fonts/NotoEmojiNuevos.ttf');
    await (FontLoader('EmojiNuevos')..addFont(Future.value(emojis))).load();
  } catch (_) {}
}
