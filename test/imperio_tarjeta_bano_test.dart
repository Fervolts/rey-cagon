// Tarjeta "foto del baño" del chat: lo que arma el servidor, que se dibuje igual que en la partida y que aguante basura.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/bano.dart';
import 'package:rey_cagon/imperio/catalogo.dart';
import 'package:rey_cagon/imperio/esteticas.dart';
import 'package:rey_cagon/imperio/estado.dart';
import 'package:rey_cagon/imperio/poceta.dart';
import 'package:rey_cagon/imperio/tarjeta_bano.dart';

final _migracion = File('supabase/migrations/20261101160000_imperio_tarjeta_bano.sql').readAsStringSync();

// Lo que llega al chat: la tarjeta pasa por JSON.
Map<String, dynamic> _porJson(Map<String, dynamic> t) => jsonDecode(jsonEncode(t)) as Map<String, dynamic>;

// Lo que dibuja la pestaña con esa partida.
({EstadoBano bano, int dedos}) _dePartida(Partida p, Set<String> est) {
  int cantidad(String id) => p.edificios[id] ?? 0;
  final bano = EstadoBano.desde(comprada: p.mejoras.contains, cantidad: cantidad, esteticas: est, vista: p.vista);
  final tope = cantidad('dedo') < Poceta.topeDedos ? cantidad('dedo') : Poceta.topeDedos;
  final elegido = p.vista['dedos'] as int?;
  return (bano: bano, dedos: elegido == null || elegido > tope ? tope : elegido);
}

Future<void> _pintar(WidgetTester tester, Map<String, dynamic> t) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [TarjetaBano(t)]))));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  final todo = {for (final e in edificios) e.id: 40};
  final todasMejoras = {for (final m in mejoras) m.id};
  final todasEsteticas = {for (final e in esteticas) e.id};

  group('tarjetaBano (copia de la migración)', () {
    test('los edificios y la expresión de mejoras son los mismos que en el .sql', () {
      final arr = RegExp(r"where x\.k = any \(array\[([^\]]*)\]\)").firstMatch(_migracion)!.group(1)!;
      final ids = RegExp(r"'(\w+)'").allMatches(arr).map((m) => m.group(1)).toList();
      expect(ids, edificiosTarjetaBano);
      expect(_migracion, contains("'$mejorasTarjetaBano'"));
      expect(_migracion, contains("'^est_[a-z0-9_]{1,40}\$'"));
      expect(_migracion, contains("'^[a-z0-9_]{1,40}\$'"));
      expect(_migracion, contains("'^[a-z]{1,20}\$'"));
      expect(_migracion, contains('Espera un rato para volver a presumir tu baño'));
    });

    test('los edificios que viajan son de verdad del catálogo', () {
      final catalogo = {for (final e in edificios) e.id};
      expect(catalogo.containsAll(edificiosTarjetaBano), isTrue);
    });

    test('pasan todos los ids que dibujan algo', () {
      final ocultables = {for (final o in ocultablesBano) o.id};
      for (final id in ocultables) {
        expect(RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(id), isTrue, reason: id);
      }
      for (final id in todasEsteticas) {
        expect(RegExp(r'^est_[a-z0-9_]{1,40}$').hasMatch(id), isTrue, reason: id);
      }
      for (final a in AmbienteBano.values) {
        expect(RegExp(r'^[a-z]{1,20}$').hasMatch(a.name), isTrue, reason: a.name);
      }
    });

    test('no lleva saldo ni nada fuera de lo que dibuja', () {
      final p = Partida(edificios: {'dedo': 3, 'templo': 1}, mejoras: {'dedo_5', 'iman'});
      final t = tarjetaBano({...p.toJson(), 'saldo': 999, 'nombre': 'x'}, {'est_tobo', 'trampa'});
      expect(t.keys.toSet(), {'tipo', 'mudanzas', 'edificios', 'mejoras', 'esteticas', 'vista'});
      expect(t['tipo'], 'bano');
      expect(t['mudanzas'], 0);
      expect(t['edificios'], {'dedo': 3, 'templo': 1});
      expect(t['esteticas'], ['est_tobo']);
    });

    test('lo que venga mal se limpia', () {
      final t = tarjetaBano({
        'edificios': {'dedo': 'x', 'cafe': 2.7, 'templo': 0, 'mina': true, 'secreto': 5, 'agujero': 5e9},
        'mejoras': ['iman', 'IMAN', 'iman', 7, null, 'bano_1', 'cosa_rara'],
        'vista': {'ocultos': ['camion', 3, 'MAL!', null], 'dedos': 99.6, 'ambiente': 'Templo!'},
      }, ['est_tobo', 'est_tobo', 3, null]);
      expect(t['edificios'], {'cafe': 2, 'agujero': 1000000});
      expect(t['mejoras'], ['bano_1', 'iman']);
      expect(t['esteticas'], ['est_tobo']);
      expect(t['vista'], {
        'ocultos': ['3', 'camion'],
        'dedos': 24,
      });
      expect(tarjetaBano('basura', const []), {'tipo': 'bano', 'mudanzas': 0, 'edificios': {}, 'mejoras': [], 'esteticas': [], 'vista': {}});
    });
  });

  group('ida y vuelta', () {
    test('la tarjeta dibuja el mismo baño que la partida', () {
      final casos = <(Partida, Set<String>)>[
        (Partida(), const {}),
        (Partida(edificios: {...todo}, mejoras: {...todasMejoras}), todasEsteticas),
        (Partida(edificios: {'dedo': 7, 'bano': 2, 'cloaca': 1}, mejoras: {'dedo_5', 'adorno_alfombra'}), {'est_tobo'}),
        (
          Partida(edificios: {...todo}, mejoras: {...todasMejoras}, vista: {
            'ocultos': [for (final o in ocultablesBano) o.id, ...todasEsteticas]..sort(),
            'dedos': 3,
          }),
          todasEsteticas
        ),
        for (final a in AmbienteBano.values)
          (Partida(edificios: {...todo}, mejoras: {...todasMejoras}, vista: {'ambiente': a.name, 'dedos': 0}), todasEsteticas),
      ];
      for (final (p, est) in casos) {
        final esperado = _dePartida(p, est);
        final t = _porJson(tarjetaBano(jsonDecode(jsonEncode(p.toJson())), est));
        final (:bano, :dedos, :mudanzas) = banoDeTarjeta(t);
        expect(bano, esperado.bano, reason: '${p.vista}');
        expect(dedos, esperado.dedos, reason: '${p.vista}');
        expect(mudanzas, p.mudanzas);
      }
    });

    test('vacía o con basura dibuja el baño básico', () {
      final basico = EstadoBano.desde(comprada: (_) => false, cantidad: (_) => 0);
      for (final t in <Map<String, dynamic>>[
        {'tipo': 'bano'},
        {'tipo': 'bano', 'edificios': 'x', 'mejoras': 3, 'esteticas': {'a': 1}, 'vista': []},
        {'tipo': 'bano', 'edificios': {'dedo': -4}, 'mejoras': [null], 'vista': {'ocultos': 'camion', 'dedos': 'x', 'ambiente': 3}},
      ]) {
        final r = banoDeTarjeta(t);
        expect(r.bano, basico);
        expect(r.dedos, 0);
        expect(r.mudanzas, 0);
      }
    });

    test('la casa viaja en la tarjeta (y lo que venga mal es el Rancho)', () {
      expect(tarjetaBano({'mudanzas': 3}, const [])['mudanzas'], 3);
      expect(tarjetaBano({'mudanzas': -2}, const [])['mudanzas'], 0);
      expect(tarjetaBano({'mudanzas': 'x'}, const [])['mudanzas'], 0);
      expect(banoDeTarjeta({'tipo': 'bano', 'mudanzas': 2}).mudanzas, 2);
      expect(banoDeTarjeta({'tipo': 'bano', 'mudanzas': 'x'}).mudanzas, 0);
    });
  });

  group('TarjetaBano', () {
    final llena = _porJson(tarjetaBano(
        Partida(edificios: {...todo}, mejoras: {...todasMejoras}, vista: {'ambiente': 'templo', 'dedos': 12}).toJson(), todasEsteticas));

    testWidgets('llena, vacía y con basura se dibujan sin romper', (tester) async {
      for (final t in <Map<String, dynamic>>[
        llena,
        {'tipo': 'bano'},
        {'tipo': 'bano', 'edificios': [1, 2], 'mejoras': {'x': 1}, 'esteticas': 'est_tobo', 'vista': 'nada'},
        {'tipo': 'bano', 'edificios': {'templo': 'mucho', 'cloaca': 1e300}, 'vista': {'dedos': double.nan}},
      ]) {
        await _pintar(tester, t);
        expect(tester.takeException(), isNull);
        expect(find.byType(Poceta), findsOneWidget);
        expect(find.textContaining('Mi baño'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no pasa del ancho de una burbuja y no anima', (tester) async {
      await _pintar(tester, llena);
      expect(tester.getSize(find.byType(TarjetaBano).first).width, lessThanOrEqualTo(800));
      final foto = tester.getSize(find.byType(AspectRatio).first);
      expect(foto.width, lessThanOrEqualTo(TarjetaBano.anchoMaximo));
      expect(tester.widget<Poceta>(find.byType(Poceta)).activo, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('al tocarla se abre en grande y la X la cierra', (tester) async {
      await _pintar(tester, llena);
      await tester.tap(find.byType(TarjetaBano));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tarjeta_bano_cerrar')), findsOneWidget);
      expect(find.byType(Poceta), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('tarjeta_bano_cerrar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tarjeta_bano_cerrar')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
