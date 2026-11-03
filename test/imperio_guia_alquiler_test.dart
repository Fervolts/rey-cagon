// Guía de los alquileres: la ficha "qué hace" (una vez por alquilable, el ? la reabre, ejemplo con los números del
// jugador), `guia_vista` en la partida (saves viejos cargan) y los empujones (Robot con Atasco largo, Primo, recién alquilado).
// Capturas: CAPTURAS_GUIA=1 flutter test test/imperio_guia_alquiler_test.dart (escribe PNG en build/capturas_guia/).
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/formato.dart';
import 'package:rey_cagon/imperio/guia_alquiler.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/telemetria.dart';
import 'package:rey_cagon/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

const t0 = 1800000000000;
const alquilables = ['robot', 'robot_turbo', 'plomero_horas', 'primo', 'cuadrilla', 'guardia'];

class _Nube extends NubeImperio {
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

/// Imperio con los alquilables abiertos (30 cagadas, ya vio un atasco), algo de producción y mucho saldo.
Imperio _imperio() {
  final imp = Imperio(cagadas: 30, azar: Random(1));
  imp.partida.vioPrimerAtasco = true;
  imp.partida.edificios['arepa'] = 10;
  imp.partida.saldo = 1e15;
  return imp;
}

ControlImperio _control(Telemetria tele) => ControlImperio(nube: _Nube(), telemetria: tele)..imperio = _imperio();

List<(Object?, Object?)> _guia(Telemetria tele) => [
      for (final e in tele.cola)
        if (e['evento'] == 'alquiler_guia') ((e['datos'] as Map)['id'], (e['datos'] as Map)['accion']),
    ];

/// Lo que hace la hoja de Objetos con cada alquilable: el ? y la ficha bajo la fila, reconstruidos con el control.
Widget _hoja(ControlImperio c, {List<String> ids = alquilables, void Function(String id)? alIr}) => MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (context, _) => ListView(
            children: [
              for (final id in ids)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [Text(id), BotonGuiaAlquiler(control: c, id: id)]),
                    GuiaAlquiler(control: c, objeto: objetoPorId(id)!, ahora: t0, alIr: alIr == null ? null : () => alIr(id), precioIr: '5 MJ'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reiniciarGuia();
  });

  group('Ficha', () {
    testWidgets('sale una vez por alquilable y no vuelve después de ENTENDIDO', (t) async {
      t.view.physicalSize = const Size(800, 4000);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final tele = Telemetria(enviar: (_) async => 0);
      final c = _control(tele);
      await t.pumpWidget(_hoja(c));
      await t.pumpAndSettle();
      final vistos = <String>[];
      for (var i = 0; i < alquilables.length; i++) {
        // Una sola ficha a la vez: la primera pendiente del catálogo.
        final abiertas = [for (final id in alquilables) if (find.byKey(Key('guia_ficha_$id')).evaluate().isNotEmpty) id];
        expect(abiertas.length, 1, reason: 'abiertas: $abiertas');
        final id = abiertas.single;
        expect(vistos, isNot(contains(id)));
        vistos.add(id);
        await t.tap(find.byKey(Key('guia_entendido_$id')));
        await t.pumpAndSettle();
        expect(find.byKey(Key('guia_ficha_$id')), findsNothing);
        expect(c.imperio.partida.guiaVista, contains(id));
      }
      expect(vistos.toSet(), alquilables.toSet());
      for (final id in alquilables) {
        expect(find.byKey(Key('guia_ficha_$id')), findsNothing);
      }
      // Otra vez la hoja (como cerrarla y abrirla): nada.
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_hoja(c));
      await t.pumpAndSettle();
      for (final id in alquilables) {
        expect(find.byKey(Key('guia_ficha_$id')), findsNothing);
      }
      final eventos = _guia(tele);
      for (final id in alquilables) {
        expect(eventos.where((e) => e == (id, 'ficha')).length, 1, reason: id);
        expect(eventos.where((e) => e == (id, 'entendido')).length, 1, reason: id);
      }
    });

    testWidgets('el ? la reabre, y otra vez el ? la cierra', (t) async {
      final tele = Telemetria(enviar: (_) async => 0);
      final c = _control(tele);
      c.imperio.partida.guiaVista.addAll(alquilables);
      await t.pumpWidget(_hoja(c, ids: ['primo']));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guia_ficha_primo')), findsNothing);
      await t.tap(find.byKey(const Key('guia_primo')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guia_ficha_primo')), findsOneWidget);
      expect(_guia(tele), [('primo', 'ficha')]);
      await t.tap(find.byKey(const Key('guia_primo')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guia_ficha_primo')), findsNothing);
      // Reabierta y ENTENDIDO: se cierra.
      await t.tap(find.byKey(const Key('guia_primo')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guia_entendido_primo')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guia_ficha_primo')), findsNothing);
      expect(_guia(tele).last, ('primo', 'entendido'));
    });

    testWidgets('el ejemplo del Primo trae el número de ahora: valorPujo x 10 por segundo', (t) async {
      final c = _control(Telemetria(enviar: (_) async => 0));
      c.imperio.partida.guiaVista.addAll(alquilables.where((id) => id != 'primo'));
      final esperado = '+${formatoMj(c.imperio.valorPujo(t0) * pujosPrimo, ingles: false)}';
      expect(c.imperio.valorPujo(t0), greaterThan(0));
      await t.pumpWidget(_hoja(c, ids: ['primo']));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guia_ficha_primo')), findsOneWidget);
      expect(find.textContaining('Puja por ti 10 veces por segundo'), findsOneWidget);
      expect(find.textContaining('Ahora cada primo te daría $esperado'), findsOneWidget);
    });

    testWidgets('ALQUILAR desde la ficha: alquila y la da por vista; sin plata no hay botón', (t) async {
      final tele = Telemetria(enviar: (_) async => 0);
      final c = _control(tele);
      final ido = <String>[];
      await t.pumpWidget(_hoja(c, ids: ['robot'], alIr: ido.add));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guia_ir_robot')));
      await t.pumpAndSettle();
      expect(ido, ['robot']);
      expect(c.imperio.partida.guiaVista, contains('robot'));
      expect(_guia(tele), [('robot', 'ficha'), ('robot', 'ir')]);
      await t.pumpWidget(_hoja(c, ids: ['robot_turbo']));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guia_ficha_robot_turbo')), findsOneWidget);
      expect(find.byKey(const Key('guia_ir_robot_turbo')), findsNothing);
    });

    testWidgets('con movimiento nada no anima', (t) async {
      final c = _control(Telemetria(enviar: (_) async => 0));
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: GuiaAlquiler(control: c, objeto: objetoPorId('robot')!, ahora: t0)),
        ),
      ));
      final ficha = find.byKey(const Key('guia_ficha_robot'));
      expect(ficha, findsOneWidget);
      expect(movimiento(t.element(ficha)), Movimiento.nada);
      expect(find.ancestor(of: ficha, matching: find.byType(TweenAnimationBuilder<double>)), findsNothing);
      await t.pumpAndSettle();
    });

    test('textos de cada alquilable', () {
      final im = _imperio();
      for (final id in alquilables) {
        final x = textosGuia(im, id, t0);
        expect(x.que, isNotEmpty, reason: id);
        expect(x.ejemplo, isNotEmpty, reason: id);
      }
      im.partida.destapes = 7;
      expect(textosGuia(im, 'robot', t0).ejemplo, 'Llevas 7 destapes a mano.');
      expect(textosGuia(im, 'robot_turbo', t0).que, contains('tu producción no baja'));
      expect(textosGuia(im, 'plomero_horas', t0).que, contains('producción x3 por 1 min'));
      expect(textosGuia(im, 'plomero_horas', t0).ejemplo, contains(formatoMj(im.mpsSinEfectos() * 120, ingles: false)));
      final barato = edificioMasBarato(im, t0)!;
      expect(textosGuia(im, 'cuadrilla', t0).ejemplo, contains(barato.nombreEs));
      final g = textosGuia(im, 'guardia', t0);
      expect(g.que, contains('al 100% y hasta 8 h'));
      expect(g.que, contains('${(im.porcentajeOffline * 100).round()}%'));
      expect(g.ejemplo, contains('con Guardia'));
    });
  });

  group('guia_vista en la partida', () {
    test('un save viejo sin guia_vista carga, y la lista va y vuelve', () {
      final viejo = _imperio().partida.toJson()..remove('guia_vista');
      expect(viejo.containsKey('guia_vista'), isFalse);
      final p = Partida.desdeJson(viejo);
      expect(p.guiaVista, isEmpty);
      expect(p.edificios['arepa'], 10);
      p.guiaVista.addAll({'robot', 'empujon_robot'});
      final j = p.toJson();
      expect(j['guia_vista'], unorderedEquals(['robot', 'empujon_robot']));
      expect(Partida.desdeJson(j).guiaVista, {'robot', 'empujon_robot'});
    });

    test('jalar la cadena no la borra', () {
      final im = _imperio();
      im.partida.guiaVista.add('primo');
      im.jalar();
      expect(im.partida.guiaVista, contains('primo'));
    });

    test('marcarGuia la guarda una vez y avisa', () {
      final c = _control(Telemetria(enviar: (_) async => 0));
      var avisos = 0;
      c.addListener(() => avisos++);
      c.marcarGuia('robot');
      c.marcarGuia('robot');
      expect(c.imperio.partida.guiaVista, {'robot'});
      expect(avisos, 1);
    });
  });

  group('Empujones', () {
    test('Robot: Atasco abierto más de 20 s y nunca alquilado', () {
      final im = _imperio();
      final e = EmpujonesAlquiler();
      expect(e.siguiente(im, t0), isNull);
      im.partida.atasco = Atasco('arepa', t0);
      expect(e.siguiente(im, t0 + 19000), isNull);
      final r = e.siguiente(im, t0 + 21000)!;
      expect(r.clave, 'empujon_robot');
      expect(r.id, 'robot');
      expect(r.tienda, isTrue);
      // Ya salió una vez: no otra.
      im.partida.guiaVista.add(r.clave);
      expect(e.siguiente(im, t0 + 60000), isNull);
    });

    test('Robot: no sale si el Robot se alquiló alguna vez', () {
      final im = _imperio();
      im.partida.alquiladosUsados.add('robot');
      im.partida.atasco = Atasco('arepa', t0);
      expect(EmpujonesAlquiler().siguiente(im, t0 + 30000), isNull);
    });

    test('Robot: no sale con el Atasco recién abierto aunque el reloj vaya lejos del inicio', () {
      final im = _imperio();
      im.partida.atasco = Atasco('arepa', t0 + 100000);
      expect(EmpujonesAlquiler().siguiente(im, t0 + 110000), isNull);
    });

    test('Primo: pujando rápido a mano y sin primos', () {
      final im = _imperio();
      final e = EmpujonesAlquiler();
      for (var i = 0; i < 29; i++) {
        e.pujo(t0 + i * 150);
      }
      expect(e.siguiente(im, t0 + 29 * 150), isNull);
      e.pujo(t0 + 29 * 150);
      expect(e.siguiente(im, t0 + 29 * 150)?.clave, 'empujon_primo');
      // Despacio (fuera de la ventana de 5 s): ya no.
      expect(e.siguiente(im, t0 + 20000), isNull);
    });

    test('Recién alquilado: "ya está trabajando", una vez por alquilable', () {
      final im = _imperio();
      final e = EmpujonesAlquiler();
      expect(e.siguiente(im, t0), isNull);
      expect(im.comprarObjeto('cuadrilla', t0), isTrue);
      final r = e.siguiente(im, t0 + 1000)!;
      expect(r.clave, 'trabaja_cuadrilla');
      expect(r.texto, 'Ya está trabajando: míralo en la poceta');
      expect(r.tienda, isFalse);
      im.partida.guiaVista.add(r.clave);
      expect(e.siguiente(im, t0 + 2000), isNull);
      // Lo que ya estaba alquilado al empezar no cuenta como nuevo.
      final im2 = _imperio();
      expect(im2.comprarObjeto('primo', t0), isTrue);
      expect(EmpujonesAlquiler().siguiente(im2, t0 + 1000), isNull);
    });

    testWidgets('la tarjeta se quita tocándola y VER abre lo que toque', (t) async {
      var cerrado = 0, visto = 0;
      final im = _imperio()..partida.atasco = Atasco('arepa', t0);
      final r = EmpujonesAlquiler().siguiente(im, t0 + 25000)!;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TarjetaEmpujon(r, alCerrar: () => cerrado++, alVer: () => visto++))));
      await t.tap(find.byKey(const Key('empujon_ver_robot')));
      expect(visto, 1);
      await t.tap(find.byKey(const Key('empujon_empujon_robot')));
      expect(cerrado, 1);
    });
  });

  group('Capturas', () {
    final capturas = Platform.environment['CAPTURAS_GUIA'] != null;
    testWidgets('fichas y empujones a PNG', (t) async {
      await _cargarLetras();
      t.view.physicalSize = const Size(1080, 3000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = _control(Telemetria(enviar: (_) async => 0));
      c.imperio.partida.destapes = 12;
      final im = c.imperio;
      final llave = GlobalKey();
      Future<void> foto(String nombre, Widget hijo, Brightness brillo) async {
        await t.pumpWidget(MaterialApp(
          theme: _conLetraEnBotones(tema(brillo)),
          home: Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: RepaintBoundary(key: llave, child: hijo)))),
        ));
        await t.runAsync(() async {
          for (final el in find.byType(Image).evaluate()) {
            await precacheImage((el.widget as Image).image, el);
          }
        });
        await t.pumpAndSettle();
        final borde = llave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await t.runAsync(() async {
          final img = await borde.toImage(pixelRatio: 3);
          return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        });
        final f = File('build/capturas_guia/$nombre.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(png!);
      }

      Widget fichas() => Builder(
            builder: (context) => Container(
              color: paleta(context).fondo,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final id in ['primo', 'cuadrilla', 'guardia'])
                    TarjetaGuiaAlquiler(objeto: objetoPorId(id)!, textos: textosGuia(im, id, t0), alEntendido: () {}, alIr: () {}, precioIr: '1,2 MJ'),
                  TarjetaGuiaAlquiler(objeto: objetoPorId('robot')!, textos: textosGuia(im, 'robot', t0), alEntendido: () {}),
                ],
              ),
            ),
          );
      Widget empujones() {
        final e = EmpujonesAlquiler();
        final robot = e.siguiente(_imperio()..partida.atasco = Atasco('arepa', t0), t0 + 25000)!;
        final im2 = _imperio();
        final e2 = EmpujonesAlquiler()..siguiente(im2, t0);
        im2.comprarObjeto('cuadrilla', t0);
        final trabaja = e2.siguiente(im2, t0)!;
        return Builder(
          builder: (context) => Container(
            color: paleta(context).fondo,
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TarjetaEmpujon(robot, alCerrar: () {}, alVer: () {}),
              const SizedBox(height: 8),
              TarjetaEmpujon(trabaja, alCerrar: () {}),
            ]),
          ),
        );
      }

      await foto('fichas_oscuro', fichas(), Brightness.dark);
      await foto('fichas_claro', fichas(), Brightness.light);
      await foto('empujones_oscuro', empujones(), Brightness.dark);
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
