// Recorrido guiado de la primera vez y "¿Qué hago ahora?" (recorrido.dart, que_hago.dart).
// Capturas: CAPTURAS_RECORRIDO=1 flutter test test/imperio_recorrido_test.dart (escribe PNG en build/capturas_recorrido/).
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/pantalla.dart';
import 'package:rey_cagon/imperio/que_hago.dart';
import 'package:rey_cagon/imperio/recorrido.dart';
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
/// salga el aviso de lo ganado sin jugar (ese diálogo va antes que el recorrido y tiene su propia prueba).
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

Future<void> _desmontar(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

final _tarjeta = find.byKey(const Key('recorrido_tarjeta'));

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

      // Solo edificios (lo que usa el recorrido): el de menor retorno entre los edificios.
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

    test('veterano con todo: el dorado manda sobre comprar y el recorrido trae todos los pasos', () {
      final im = _veterano();
      im.partida.dorado = const DoradoVisible(t0, t0 + 60000, .5, .5);
      expect(queHagoAhora(im, t0, cadenaLista: true).id, 'dorado');
      im.partida.atasco = Atasco(im.partida.edificios.keys.first, t0);
      expect(queHagoAhora(im, t0, cadenaLista: true).id, 'destapar');

      final pasos = pasosRecorrido(im, t0, jalarVisible: true, cadenaLista: true);
      expect([for (final p in pasos) p.id], ['poceta', 'saldo', 'edificios', 'mejoras', 'atascos', 'dorado', 'objetos', 'que_hago', 'cadena', 'mudanza']);
      final cadena = pasos[pasos.length - 2];
      expect(cadena.objetivo, const Key('boton_jalar'));
      expect(cadena.texto, contains('Tienes 10 Rollos de Oro'));
      expect(cadena.texto, contains('Si jalas ahora ganas'));
      expect(cadena.texto, isNot(contains('cagadas reales')));
      expect(pasos[4].objetivo, const Key('tarjeta_atasco'));
      expect(pasos[5].objetivo, const Key('mojon_dorado'));
      // Plomería y Mudanza: después de la primera jalada, al final; apunta a la tira si se ve, si no a la tienda.
      expect(pasos.last.texto, contains('Plomería'));
      expect(pasos.last.texto, contains('Casa'));
      expect(pasos.last.objetivo, const Key('boton_tienda'));
      expect(pasosRecorrido(im, t0, tiraMudanza: true).last.objetivo, const Key('tira_mudanza'));
      im.partida.jaladas = 0;
      expect([for (final p in pasosRecorrido(im, t0)) p.id], isNot(contains('mudanza')));
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
      expect(s.ir, DestinoQueHago.tienda);
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

    test('jugador nuevo: solo lo abierto (poceta, saldo, edificios, dorado y el ?)', () {
      final pasos = pasosRecorrido(_nuevo(), t0);
      final ids = [for (final p in pasos) p.id];
      expect(ids, containsAllInOrder(['poceta', 'saldo', 'edificios', 'dorado', 'que_hago']));
      expect(ids, isNot(contains('atascos')));
      expect(ids, isNot(contains('objetos')));
      expect(ids, isNot(contains('cadena')));
      expect(pasos.length, inInclusiveRange(5, 6));
      expect(pasos[1].texto, contains('compra un edificio'));
    });

    test('duraciones y porcentajes cortos', () {
      expect(duracionCorta(40), '40 s');
      expect(duracionCorta(720), '12 min');
      expect(duracionCorta(3 * 3600), '3 h');
      expect(duracionCorta(2 * 86400), '2 d');
      expect(pctRollos(10, 0.02), '+20%');
    });
  });

  group('Recorrido en la pantalla', () {
    testWidgets('sale una vez: SALTAR lo marca visto y no vuelve, ni al recargar', (t) async {
      final (c, tele, enviados) = await _montar(t, _estado(_nuevo()));
      expect(_tarjeta, findsOneWidget);
      expect(find.byKey(const Key('boton_que_hago')), findsOneWidget);
      await t.tap(find.byKey(const Key('recorrido_saltar')));
      await _esperar(t);
      expect(_tarjeta, findsNothing);
      expect(c.imperio.partida.guiaVista, contains(claveRecorrido));
      expect(_eventos(enviados, tele, 'imperio_recorrido', 'paso'), [('poceta', 'ver'), ('poceta', 'saltar')]);
      await _esperar(t, 20);
      expect(_tarjeta, findsNothing);
      final guardado = _estado(c.imperio);
      await _desmontar(t);

      await _montar(t, guardado);
      expect(_tarjeta, findsNothing);
      await _desmontar(t);
    });

    testWidgets('sale una vez: al terminar (LISTO) no vuelve', (t) async {
      final (c, tele, enviados) = await _montar(t, _estado(_nuevo()));
      final n = pasosRecorrido(c.imperio, c.ahora).length;
      for (var i = 0; i < n; i++) {
        expect(_tarjeta, findsOneWidget);
        expect(find.text('${i + 1}/$n'), findsOneWidget);
        await t.tap(find.byKey(const Key('recorrido_siguiente')));
        await _esperar(t, 3);
      }
      expect(_tarjeta, findsNothing);
      expect(c.imperio.partida.guiaVista, contains(claveRecorrido));
      final ev = _eventos(enviados, tele, 'imperio_recorrido', 'paso');
      expect(ev.last.$2, 'fin');
      expect(ev.where((e) => e.$2 == 'ver').length, n);
      await _esperar(t, 20);
      expect(_tarjeta, findsNothing);
      await _desmontar(t);
    });

    testWidgets('se salta los pasos cerrados (nuevo) y el veterano termina en la cadena y la mudanza', (t) async {
      var (c, tele, enviados) = await _montar(t, _estado(_nuevo()));
      final vistos = <Object?>[];
      while (_tarjeta.evaluate().isNotEmpty) {
        await t.tap(find.byKey(const Key('recorrido_siguiente')));
        await _esperar(t, 3);
      }
      for (final e in _eventos(enviados, tele, 'imperio_recorrido', 'paso')) {
        if (e.$2 == 'ver') vistos.add(e.$1);
      }
      expect(vistos, containsAllInOrder(['poceta', 'saldo', 'edificios', 'dorado', 'que_hago']));
      expect(vistos, isNot(contains('atascos')));
      expect(vistos, isNot(contains('objetos')));
      expect(vistos, isNot(contains('cadena')));
      await _desmontar(t);

      (c, tele, enviados) = await _montar(t, _estado(_veterano(), cagadas: 30));
      expect(_tarjeta, findsOneWidget);
      vistos.clear();
      while (_tarjeta.evaluate().isNotEmpty) {
        await t.tap(find.byKey(const Key('recorrido_siguiente')));
        await _esperar(t, 3);
      }
      for (final e in _eventos(enviados, tele, 'imperio_recorrido', 'paso')) {
        if (e.$2 == 'ver') vistos.add(e.$1);
      }
      expect(vistos, containsAllInOrder(['poceta', 'saldo', 'edificios', 'mejoras', 'atascos', 'dorado', 'objetos', 'que_hago', 'cadena', 'mudanza']));
      expect(vistos.last, 'mudanza');
      // Cada paso se ve una sola vez: que salga un atasco o el dorado a mitad no lo devuelve al principio.
      expect(vistos.toSet().length, vistos.length);
      await _desmontar(t);
    });

    testWidgets('no arranca con un diálogo abierto; sale al cerrarlo', (t) async {
      final nav = GlobalKey<NavigatorState>();
      final espera = Completer<void>();
      await _montar(t, _estado(_nuevo()), nav: nav, espera: espera);
      expect(_tarjeta, findsNothing);
      nav.currentState!.push(DialogRoute<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('hola'))));
      await _esperar(t, 3);
      espera.complete();
      await _esperar(t, 20);
      expect(find.text('hola'), findsOneWidget);
      expect(_tarjeta, findsNothing);
      nav.currentState!.pop();
      await _esperar(t, 20);
      expect(_tarjeta, findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('¿Qué hago? abre la hoja, IR la cierra y desde ahí se repite el recorrido', (t) async {
      final (c, tele, enviados) = await _montar(t, _estado(_nuevo()));
      await t.tap(find.byKey(const Key('recorrido_saltar')));
      await _esperar(t);
      expect(_tarjeta, findsNothing);

      await t.tap(find.byKey(const Key('boton_que_hago')));
      await _esperar(t);
      expect(find.byKey(const Key('hoja_que_hago')), findsOneWidget);
      final s = queHagoAhora(c.imperio, c.ahora);
      expect(_eventos(enviados, tele, 'imperio_que_hago', 'sugerencia'), [(s.id, 'abrir')]);
      await t.tap(find.byKey(const Key('que_hago_ir')));
      await _esperar(t);
      expect(find.byKey(const Key('hoja_que_hago')), findsNothing);
      expect(_eventos(enviados, tele, 'imperio_que_hago', 'sugerencia').last, (s.id, 'ir'));

      await t.tap(find.byKey(const Key('boton_que_hago')));
      await _esperar(t);
      await t.tap(find.byKey(const Key('que_hago_recorrido')));
      await _esperar(t);
      expect(find.byKey(const Key('hoja_que_hago')), findsNothing);
      expect(_tarjeta, findsOneWidget);
      expect(find.text('1/${pasosRecorrido(c.imperio, c.ahora).length}'), findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('un JSON viejo sin las claves nuevas carga y muestra el recorrido', (t) async {
      // Guardado de antes: sin guia_vista ni nada de esta versión, pero con la guía de alquileres vista en otro caso.
      final viejo = Partida.desdeJson({'saldo': 120.0, 'edificios': {edificios.first.id: 2}});
      expect(viejo.guiaVista, isEmpty);
      expect(viejo.edificios[edificios.first.id], 2);
      final conGuia = Partida.desdeJson({'saldo': 1.0, 'guia_vista': ['primo']});
      expect(conGuia.guiaVista, {'primo'});

      final (c, _, _) = await _montar(t, {'saldo': 120.0, 'edificios': {edificios.first.id: 2}, 'guia_vista': ['primo']});
      expect(c.imperio.partida.edificios[edificios.first.id], 2);
      expect(_tarjeta, findsOneWidget);
      await _desmontar(t);
    });
  });

  group('Capturas', () {
    final capturas = Platform.environment['CAPTURAS_RECORRIDO'] != null;
    testWidgets('pasos del recorrido y la hoja a PNG', (t) async {
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
        final f = File('build/capturas_recorrido/$nombre.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(png!);
      }

      Future<void> siguiente([int veces = 1]) async {
        for (var i = 0; i < veces; i++) {
          await t.tap(find.byKey(const Key('recorrido_siguiente')));
          await _esperar(t, 4);
        }
      }

      for (final (brillo, sufijo) in [(Brightness.dark, 'oscuro'), (Brightness.light, 'claro')]) {
        final estilo = _conLetraEnBotones(tema(brillo));
        // Nuevo: la poceta y los edificios.
        await _montar(t, _estado(_nuevo()), tema: estilo, foto: llave);
        await foto('poceta_$sufijo');
        await siguiente(2);
        await foto('edificios_$sufijo');
        await t.tap(find.byKey(const Key('recorrido_saltar')));
        await _esperar(t);
        await t.tap(find.byKey(const Key('boton_que_hago')));
        await _esperar(t);
        await foto('que_hago_$sufijo');
        await _desmontar(t);

        // Veterano: la cadena al final, con sus números.
        final (c, _, _) = await _montar(t, _estado(_veterano(), cagadas: 30), tema: estilo, foto: llave);
        await siguiente(pasosRecorrido(c.imperio, c.ahora).length - 1);
        await foto('cadena_$sufijo');
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
