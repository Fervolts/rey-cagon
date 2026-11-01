import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/imperio/barra.dart';
import 'package:rey_cagon/imperio/cadena.dart';
import 'package:rey_cagon/imperio/cartera.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/fila.dart';
import 'package:rey_cagon/imperio/formato.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/tarjeta_cartera.dart';
import 'package:rey_cagon/tema.dart';

const int t0 = 1800000000000;

/// Partida con La cadena del trono comprada y [mj] ganados en la vida.
Imperio _conCadena({double mj = 4e10}) {
  final im = Imperio();
  im.partida
    ..mjTotal = mj
    ..saldo = 1e9
    ..edificios = {'dedo': 30, 'bano': 12}
    ..mejoras = {'cadena_trono'}
    ..inventario = {'destapador': 2}
    ..efectos = {'pujo_loco': t0 + 60000, 'cagada_fresca': t0 + 60000, 'fiebre_trono': t0 + 60000}
    ..logros = {'primer_pujo'}
    ..pujos = 500
    ..pujosRecientes = [t0, t0 + 1]
    ..segPartida = 3600;
  return im;
}

const _listo = EstadoCadena(cagadas: 5, necesarias: 5, jaladas: 0);

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: tema(Brightness.light),
    home: Scaffold(body: hijo),
  ));
  await tester.pump();
}

Widget _barra(BotonJalar b) => Align(
      alignment: Alignment.bottomCenter,
      child: BarraImperio(jalar: b, moneda: 'MjBs', alObjetos: () {}, alJalar: () {}, alSala: () {}),
    );

void main() {
  setUp(() => idioma.value = 'es');

  group('rollos', () {
    test('piso((mjTotal / 1e10) ^ 0,5)', () {
      final a = Ajustes.porDefecto;
      expect(rollosPorMj(0, a), 0);
      expect(rollosPorMj(9.99e9, a), 0);
      expect(rollosPorMj(1e10, a), 1);
      expect(rollosPorMj(4e10, a), 2);
      expect(rollosPorMj(8.99e10, a), 2);
      expect(rollosPorMj(9e10, a), 3);
      expect(mjParaRollos(3, a), closeTo(9e10, 1));
    });

    test('jalar da los totales menos los que ya tienes', () {
      final im = _conCadena(mj: 9e10);
      im.partida.rollos = 1;
      expect(im.rollosTotales, 3);
      expect(im.rollosPorGanar, 2);
      expect(im.mjParaSiguienteRollo, closeTo(16e10 - 9e10, 1));
      im.partida.rollos = 5; // más rollos que los que dan los MJ: nunca negativo
      expect(im.rollosPorGanar, 0);
    });

    test('cada rollo suma 4% a toda la producción', () {
      final im = Imperio();
      expect(im.multiplicadorRollos, 1);
      im.partida.rollos = 25;
      expect(im.multiplicadorRollos, closeTo(2, 1e-9));
    });
  });

  group('jalar', () {
    test('se va la corrida y se quedan rollos, jaladas, mjTotal, logros y estadísticas', () {
      final im = _conCadena();
      final ganados = im.jalar();
      final p = im.partida;
      expect(ganados, 2);
      expect(p.rollos, 2);
      expect(p.jaladas, 1);
      expect(p.saldo, 0);
      expect(p.edificios, isEmpty);
      expect(p.mejoras, isEmpty);
      expect(p.inventario, isEmpty);
      expect(p.pujosRecientes, isEmpty);
      expect(p.segPartida, 0);
      expect(p.efectos.keys, unorderedEquals(['cagada_fresca', 'fiebre_trono']));
      expect(p.mjTotal, 4e10);
      expect(p.logros, contains('primer_pujo'));
      expect(p.pujos, 500);
      // Sin MJ nuevos no hay más rollos.
      expect(im.rollosPorGanar, 0);
    });

    test('puedeJalar pide la mejora, las cagadas y al menos un rollo', () {
      expect(Imperio().puedeJalar(10, 5), isFalse);
      final im = _conCadena();
      expect(im.puedeJalar(4, 5), isFalse);
      expect(im.puedeJalar(5, 5), isTrue);
      im.partida.mjTotal = 1e9;
      expect(im.puedeJalar(5, 5), isFalse);
    });

    test('La cadena del trono pide Baño x10 y cuesta 7e8; después de jalar no se vuelve a vender', () {
      final im = Imperio(cagadas: 1000); // el Baño tiene candado de cagadas reales
      im.partida
        ..saldo = 1e12
        ..edificios = {'bano': 9};
      expect(im.comprarMejora('cadena_trono'), isFalse);
      im.partida.edificios['bano'] = 10;
      expect(im.comprarMejora('cadena_trono'), isTrue);
      expect(im.saldo, closeTo(1e12 - 7e8, 1));
      im.partida.mjTotal = 1e11;
      im.jalar();
      im.partida
        ..saldo = 1e12
        ..edificios = {'bano': 50};
      expect(im.comprarMejora('cadena_trono'), isFalse);
      expect(im.cadenaDesbloqueada, isTrue);
    });

    test('JSON ida y vuelta conserva rollos y jaladas', () {
      final im = _conCadena();
      im.jalar();
      final otra = Imperio.desdeJson(im.partida.toJson());
      expect(otra.partida.rollos, 2);
      expect(otra.partida.jaladas, 1);
    });
  });

  test('usarCopiaLocal: manda la copia que jaló más veces aunque tenga menos MJ', () {
    expect(usarCopiaLocal(mjLocal: 10, mjServidor: 1e6, servidorVacio: false, jaladasLocal: 2, jaladasServidor: 1), isTrue);
    expect(usarCopiaLocal(mjLocal: 1e9, mjServidor: 10, servidorVacio: false, jaladasLocal: 1, jaladasServidor: 2), isFalse);
    expect(usarCopiaLocal(mjLocal: 11, mjServidor: 10, servidorVacio: false, jaladasLocal: 1, jaladasServidor: 1), isTrue);
  });

  group('botonJalar', () {
    test('estados en orden', () {
      expect(botonJalar(Imperio(), _listo).estado, EstadoJalar.oculto);
      final im = _conCadena();
      expect(botonJalar(im, null).estado, EstadoJalar.pronto);
      final faltan = botonJalar(im, const EstadoCadena(cagadas: 2, necesarias: 5, jaladas: 0));
      expect(faltan.estado, EstadoJalar.faltanCagadas);
      expect(faltan.cagadas, 3);
      expect(faltan.nota('MjBs'), 'FALTAN 3 CAGADAS');
      expect(botonJalar(im, const EstadoCadena(cagadas: 4, necesarias: 5, jaladas: 0)).nota('MjBs'), 'FALTA 1 CAGADA');
      final listo = botonJalar(im, _listo);
      expect(listo.estado, EstadoJalar.listo);
      expect(listo.encendido, isTrue);
      expect(listo.nota('MjBs'), '+2');
      im.partida.mjTotal = 5e9;
      final sinMj = botonJalar(im, _listo);
      expect(sinMj.estado, EstadoJalar.faltanMj);
      expect(sinMj.mj, closeTo(5e9, 1));
    });

    test('porcentajeRollos', () {
      expect(porcentajeRollos(0, 0.04), '+0%');
      expect(porcentajeRollos(3, 0.04), '+12%');
      expect(porcentajeRollos(1, 0.025), '+2,5%');
    });
  });

  group('botón JALAR en la barra', () {
    testWidgets('no sale sin La cadena del trono (y no deja hueco)', (tester) async {
      await _montar(tester, _barra(botonJalar(Imperio(), _listo)));
      expect(find.byKey(const Key('boton_jalar')), findsNothing);
      expect(find.text('TIENDA'), findsOneWidget);
      expect(find.text('SALA'), findsOneWidget);
      // Dos botones: cada uno ocupa la mitad.
      expect(tester.getSize(find.ancestor(of: find.text('TIENDA'), matching: find.byType(Expanded))).width, closeTo(147, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sale con la mejora comprada', (tester) async {
      await _montar(tester, _barra(botonJalar(_conCadena(), _listo)));
      expect(find.byKey(const Key('boton_jalar')), findsOneWidget);
      expect(find.text('JALAR'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sigue saliendo después de jalar (la mejora ya no está)', (tester) async {
      final im = _conCadena();
      im.jalar();
      expect(im.mejoraComprada('cadena_trono'), isFalse);
      await _montar(tester, _barra(botonJalar(im, const EstadoCadena(cagadas: 0, necesarias: 5, jaladas: 1))));
      expect(find.byKey(const Key('boton_jalar')), findsOneWidget);
      expect(find.text('FALTAN 5 CAGADAS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('números en una línea', () {
    test('formatoCantidad', () {
      expect(formatoCantidad(100), '100');
      expect(formatoCantidad(999), '999');
      expect(formatoCantidad(1000), '1K');
      expect(formatoCantidad(1500), '1,5K');
      expect(formatoCantidad(1999), '1,9K');
      expect(formatoCantidad(15000), '15K');
      expect(formatoCantidad(250000), '250K');
      expect(formatoCantidad(1500000), '1,5M');
      expect(formatoCantidad(1500, ingles: true), '1.5K');
    });

    testWidgets('FilaImperio a 320 px: cantidad, precio y detalle no se parten', (tester) async {
      await _montar(
        tester,
        ListView(
          padding: const EdgeInsets.all(13),
          children: [
            for (final n in [100, 999, 1500, 250000])
              FilaImperio(
                emoji: '🚽',
                titulo: 'Baño con nombre larguísimo que no cabe',
                detalle: '+1,23e21 /s c/u · 4,56e21 /pujo',
                derecha: '1,23e21 MjBs',
                contador: n,
                extra: const Icon(Icons.expand_more, size: 18),
              ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      for (final t in ['100', '999', '1,5K', '250K']) {
        expect(find.text(t), findsOneWidget);
        expect(tester.getSize(find.text(t)).height, lessThan(30), reason: '$t en una línea');
      }
      // Precio y detalle: una sola línea cada uno (FittedBox los encoge en vez de partirlos).
      for (final r in tester.renderObjectList<RenderParagraph>(find.text('1,23e21 MjBs'))) {
        expect(r.size.height, lessThan(20));
      }
      for (final r in tester.renderObjectList<RenderParagraph>(find.text('+1,23e21 /s c/u · 4,56e21 /pujo'))) {
        expect(r.size.height, lessThan(18));
      }
    });
  });

  group('cartera', () {
    testWidgets('TarjetaCartera a 320 px con 1e15 no se desborda', (tester) async {
      await _montar(
        tester,
        const Padding(
          padding: EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220, // ancho de una burbuja del chat a 320 px
              child: TarjetaCartera({'tipo': 'cartera', 'saldo': 1e15, 'mps': 1e15, 'pujo': 1e15, 'mj_total': 1e21, 'jaladas': 9, 'rollos': 1e12}),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ESTADO DE CUENTA'), findsOneWidget);
    });

    testWidgets('TarjetaCartera con basura no revienta', (tester) async {
      await _montar(tester, const TarjetaCartera({'tipo': 'cartera', 'saldo': 'x', 'mps': -5, 'pujo': null}));
      expect(tester.takeException(), isNull);
    });

    testWidgets('HistoriaCartera con números enormes no se desborda', (tester) async {
      final im = _conCadena(mj: 1e24);
      im.partida.saldo = 1e15;
      im.partida.rollos = 123456789;
      im.partida.jaladas = 27;
      await _montar(
        tester,
        FittedBox(
          child: SizedBox(
            width: HistoriaCartera.ancho,
            height: HistoriaCartera.alto,
            child: HistoriaCartera(DatosCartera.de(im, t0)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
