// Fase 2, carril B: semana del Cofre, Congelador en la racha, Fichas (motor, control y hoja).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/cofre.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/fichas.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/racha_imperio.dart';
import 'package:rey_cagon/imperio/telemetria.dart';

/// Nube de mentira: Fichas en memoria, mismos precios y topes que `imperio_usar_fichas`.
class _NubeFalsa extends NubeImperio {
  _NubeFalsa(this.fichas);
  int fichas;
  int congeladores = 0;
  bool tanque = false;
  final llamadas = <String>[];

  @override
  Future<int> usarFicha() async {
    llamadas.add('cagada_fresca');
    if (fichas < 1) return -1;
    return fichas -= 1;
  }

  @override
  Future<int> usarFichas(String que) async {
    llamadas.add(que);
    final precio = {'sin_espera': 1, 'tanque_extra': 2, 'congelador': 3}[que]!;
    if (que == 'congelador' && congeladores >= 2) return -2;
    if (que == 'tanque_extra' && tanque) return -2;
    if (fichas < precio) return -1;
    if (que == 'congelador') congeladores++;
    if (que == 'tanque_extra') tanque = true;
    return fichas -= precio;
  }

  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

ControlImperio _control(_NubeFalsa nube, {Map<String, int>? esperas}) => ControlImperio(
      nube: nube,
      telemetria: Telemetria(enviar: (_) async => 0),
    )..imperio = Imperio(partida: Partida(edificios: {'templo': 1}, esperas: esperas), fichas: nube.fichas);

void main() {
  group('semana del Cofre', () {
    test('lunesDe da el lunes a las 0:00, también el domingo y el lunes mismo', () {
      expect(lunesDe(DateTime(2026, 11, 4, 15, 30)), DateTime(2026, 11, 2)); // miércoles
      expect(lunesDe(DateTime(2026, 11, 8, 23, 59)), DateTime(2026, 11, 2)); // domingo
      expect(lunesDe(DateTime(2026, 11, 2)), DateTime(2026, 11, 2)); // lunes
      expect(lunesDe(DateTime(2027, 1, 1)), DateTime(2026, 12, 28)); // cruza el año
    });

    test('diasConCagada cuenta días distintos solo dentro de la semana', () {
      final lunes = DateTime(2026, 11, 2);
      final cagadas = [
        DateTime(2026, 11, 1, 23, 59), // domingo anterior: no
        DateTime(2026, 11, 2, 0, 0),
        DateTime(2026, 11, 2, 18, 0), // mismo día: cuenta una vez
        DateTime(2026, 11, 5, 7, 0),
        DateTime(2026, 11, 8, 23, 59),
        DateTime(2026, 11, 9, 0, 0), // lunes siguiente: no
      ];
      expect(diasConCagada(cagadas, lunes), 3);
      expect(diasConCagada([], lunes), 0);
    });

    test('siguienteSemanasRacha: +1 si se abrió la semana anterior, si no 1', () {
      final lunes = DateTime(2026, 11, 9);
      expect(siguienteSemanasRacha(null, 0, lunes), 1);
      expect(siguienteSemanasRacha(DateTime(2026, 11, 2), 3, lunes), 4);
      expect(siguienteSemanasRacha(DateTime(2026, 10, 26), 3, lunes), 1); // se saltó una semana
    });

    test('textoPremioCofre', () {
      expect(textoPremioCofre(2, 0, 1), '+2 Fichas · 1 h de producción');
      expect(textoPremioCofre(1, 2, 3), '+1 Fichas · +2 Ciruelas · 1 h de producción · 3 semanas seguidas');
    });
  });

  group('Congelador en la racha', () {
    test('congeladoresAGastar: solo si alcanzan para todos los días que faltaron', () {
      expect(congeladoresAGastar(0, 2), 0);
      expect(congeladoresAGastar(1, 0), 0);
      expect(congeladoresAGastar(1, 1), 1);
      expect(congeladoresAGastar(2, 2), 2);
      expect(congeladoresAGastar(3, 2), 0);
    });

    test('estadoRacha: con congelador la racha sigue; sin él vuelve a 1', () {
      final hoy = DateTime(2026, 11, 10);
      final hace3 = DateTime(2026, 11, 7); // faltaron 2 días
      expect(estadoRacha(5, hace3, hoy).dia, 1);
      final con2 = estadoRacha(5, hace3, hoy, congeladores: 2);
      expect((con2.dia, con2.congelar, con2.reclamado), (6, 2, false));
      expect(estadoRacha(5, hace3, hoy, congeladores: 1).dia, 1);
      // Ayer: sigue sin gastar nada.
      final ayer = estadoRacha(5, DateTime(2026, 11, 9), hoy, congeladores: 2);
      expect((ayer.dia, ayer.congelar), (6, 0));
      // Día 30 + congelador: da la vuelta a 1 como siempre.
      expect(estadoRacha(diasRacha, DateTime(2026, 11, 8), hoy, congeladores: 1).dia, 1);
    });
  });

  group('motor', () {
    const t = 1800000000000;

    test('esperasActivas ordena de la más larga a la más corta y quitarEspera la borra', () {
      final im = Imperio(partida: Partida(esperas: {'ambientador': t + 60000, 'hab_chorro': t + 600000, 'viejo': t - 1}));
      expect(im.esperasActivas(t).keys.toList(), ['hab_chorro', 'ambientador']);
      expect(im.esperasActivas(t)['ambientador'], 60000);
      expect(im.quitarEspera('viejo', t), isFalse);
      expect(im.quitarEspera('ambientador', t), isTrue);
      expect(im.esperaRestante('ambientador', t), isNull);
      expect(im.quitarEspera('ambientador', t), isFalse);
    });

    test('aplicarPremioCofre da 1 h de producción', () {
      final im = Imperio(partida: Partida(edificios: {'templo': 1}));
      final antes = im.saldo;
      final mj = im.aplicarPremioCofre(t);
      expect(mj, closeTo(3600 * im.mpsSinEfectos(contarAtasco: false), 1e-6));
      expect(mj, greaterThan(0));
      expect(im.saldo - antes, closeTo(mj, 1e-6));
    });

    test('Tanque extra suma 1 h al tope offline y sobrevive al JSON', () {
      final base = Imperio().topeOffline;
      final p = Partida(horasExtraTanque: 1);
      expect(Imperio(partida: p).topeOffline, base + const Duration(hours: 1));
      expect(Partida.desdeJson(p.toJson()).horasExtraTanque, 1);
    });

    test('JSON viejo sin horas_extra_tanque carga con 0', () {
      final j = Partida(edificios: {'templo': 2}).toJson()..remove('horas_extra_tanque');
      final p = Partida.desdeJson(j);
      expect(p.horasExtraTanque, 0);
      expect(p.edificios['templo'], 2);
    });
  });

  group('control', () {
    test('usarFichas: Sin espera borra la espera; sin espera activa no llama al servidor', () async {
      final nube = _NubeFalsa(3);
      final c = _control(nube, esperas: {'ambientador': DateTime.now().millisecondsSinceEpoch + 3600000});
      expect(await c.usarFichas('sin_espera', espera: 'otra'), isFalse);
      expect(nube.llamadas, isEmpty);
      expect(await c.usarFichas('sin_espera', espera: 'ambientador'), isTrue);
      expect(c.imperio.esperaRestante('ambientador', c.ahora), isNull);
      expect(c.imperio.fichas, 2);
    });

    test('usarFichas: Tanque extra una vez y Congelador hasta 2', () async {
      final nube = _NubeFalsa(5);
      final c = _control(nube);
      expect(await c.usarFichas('tanque_extra'), isTrue);
      expect((c.tanqueExtra, c.imperio.partida.horasExtraTanque, c.imperio.fichas), (true, 1, 3));
      expect(await c.usarFichas('tanque_extra'), isFalse); // ya lo tiene
      expect(await c.usarFichas('congelador'), isTrue);
      expect((c.congeladores, c.imperio.fichas), (1, 0));
      expect(await c.usarFichas('congelador'), isFalse); // no alcanza
      expect(c.congeladores, 1);
    });

    test('usarFichaFresca activa la Cagada fresca', () async {
      final c = _control(_NubeFalsa(1));
      expect(await c.usarFichaFresca(), isTrue);
      expect(c.imperio.fichas, 0);
      expect(c.imperio.efectosActivos(c.ahora).any((e) => e.id == 'cagada_fresca'), isTrue);
      expect(await c.usarFichaFresca(), isFalse);
    });
  });

  testWidgets('hoja de Fichas: saldo, Sin espera elige la espera y Congelador lleno se apaga', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final nube = _NubeFalsa(4);
    final c = _control(nube, esperas: {'ambientador': DateTime.now().millisecondsSinceEpoch + 3600000})..congeladores = 2;
    final avisos = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(listenable: c, builder: (_, _) => HojaFichas(control: c, avisar: (_, t) => avisos.add(t))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('4/5 Fichas'), findsOneWidget);
    for (final id in usosFichas.keys) {
      expect(find.byKey(Key('ficha_$id')), findsOneWidget);
    }
    // Congelador lleno: botón LLENO apagado.
    final lleno = tester.widget<FilledButton>(find.descendant(of: find.byKey(const Key('ficha_congelador')), matching: find.byType(FilledButton)));
    expect(lleno.onPressed, isNull);

    expect(find.byKey(const Key('espera_ambientador')), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const Key('ficha_sin_espera')), matching: find.byType(FilledButton)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('espera_ambientador')), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const Key('espera_ambientador')), matching: find.byType(FilledButton)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(nube.llamadas, ['sin_espera']);
    expect(c.imperio.fichas, 3);
    expect(find.byKey(const Key('espera_ambientador')), findsNothing);
    expect(avisos.single, contains('sin espera'));
    c.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
