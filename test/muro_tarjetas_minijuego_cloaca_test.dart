// Tarjetas del muro: récord de minijuego (con puesto, autor, juego cerrado) y mi Cloaca (unirse, miembro, llena).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/cloaca.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/imperio/formato.dart';
import 'package:rey_cagon/imperio/minijuegos/tarjeta_muro.dart';
import 'package:rey_cagon/tema.dart';

class _Nube extends NubeCloacas {
  _Nube({this.miaId});

  final String? miaId;
  final unidas = <int>[];

  @override
  Future<EstadoCloaca> mia() async => EstadoCloaca.desdeJson(miaId == null
      ? const <String, dynamic>{}
      : {
          'cloaca': {'id': miaId, 'nombre': 'Otra', 'emoji': '🚽', 'codigo': 'ABC123', 'miembros': const []}
        });

  @override
  Future<ResultadoCloaca> unirmeDesdeMuro(int muroId) async {
    unidas.add(muroId);
    return const ResultadoCloaca(ok: false, motivo: 'llena');
  }
}

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: tema(Brightness.light), home: Scaffold(body: Center(child: hijo))));
  await tester.pump();
}

const _cloaca = {
  'tipo': 'mi_cloaca',
  'cloaca_id': 'c9',
  'nombre': 'Los Destapados',
  'emoji': '🐀',
  'puesto': 3,
  'miembros': 4,
  'max': 6,
  'cagaron_hoy': 3,
  'bono': 0.15,
};

void main() {
  setUp(() => idioma.value = 'es');
  tearDown(() {
    nubeCloacas = const NubeCloacas();
    olvidarMiaMuro();
  });

  test('conMiles pone punto en español y coma en inglés', () {
    expect(conMiles(0), '0');
    expect(conMiles(999), '999');
    expect(conMiles(1240), '1.240');
    expect(conMiles(1240, ingles: true), '1,240');
    expect(conMiles(1234567), '1.234.567');
    expect(conMiles(-1240), '-1.240');
  });

  test('motivo publicacion tiene texto propio', () {
    expect(textoMotivoCloaca('publicacion'), 'Esa publicación ya no está o venció.');
  });

  group('TarjetaMinijuego', () {
    testWidgets('de otro, con puesto: invita a ganarle', (tester) async {
      await _montar(tester, const TarjetaMinijuego({'tipo': 'minijuego', 'juego': 'tuberia', 'puntos': 1240, 'puesto': 2}));
      expect(find.text('TUBERÍA EXPRESS'), findsOneWidget);
      expect(find.text('NUEVO RÉCORD'), findsOneWidget);
      expect(find.text('1.240 pts'), findsOneWidget);
      expect(find.text('#2 entre sus amigos'), findsOneWidget);
      expect(find.text('JUGAR Y GANARLE'), findsOneWidget);
    });

    testWidgets('mía, sin puesto: solo JUGAR', (tester) async {
      await _montar(tester, const TarjetaMinijuego({'tipo': 'minijuego', 'juego': 'destapa', 'puntos': 80}, mia: true));
      expect(find.text('80 pts'), findsOneWidget);
      expect(find.byKey(const Key('tarjeta_minijuego_puesto')), findsNothing);
      expect(find.text('JUGAR'), findsOneWidget);
    });

    testWidgets('mía, con puesto: entre tus amigos', (tester) async {
      await _montar(tester, const TarjetaMinijuego({'tipo': 'minijuego', 'juego': 'memoria', 'puntos': 5, 'puesto': 1}, mia: true));
      expect(find.text('#1 entre tus amigos'), findsOneWidget);
    });

    testWidgets('juego que no está abierto: sin botón', (tester) async {
      await _montar(tester, const TarjetaMinijuego({'tipo': 'minijuego', 'juego': 'viejo', 'puntos': 10}));
      expect(find.text('MINIJUEGO'), findsOneWidget);
      expect(find.byKey(const Key('tarjeta_minijuego_jugar')), findsNothing);
    });
  });

  group('TarjetaMiCloacaMuro', () {
    testWidgets('sin Cloaca y con cupo: UNIRME llama al servidor y explica el motivo', (tester) async {
      final nube = _Nube();
      nubeCloacas = nube;
      await _montar(tester, const TarjetaMiCloacaMuro(_cloaca, muroId: 42));
      await tester.pump();
      expect(find.text('LOS DESTAPADOS'), findsOneWidget);
      expect(find.text('#3 en la liga esta semana'), findsOneWidget);
      expect(find.text('4/6 miembros · 3 cagaron hoy'), findsOneWidget);
      expect(find.text('+15% de producción'), findsOneWidget);
      expect(find.text('quedan 2 cupos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tarjeta_cloaca_unirme')));
      await tester.pump();
      await tester.pump();
      expect(nube.unidas, [42]);
      expect(find.text('Esa Cloaca está llena.'), findsOneWidget);
    });

    testWidgets('miembro de esa Cloaca: Tu Cloaca, sin UNIRME', (tester) async {
      nubeCloacas = _Nube(miaId: 'c9');
      await _montar(tester, const TarjetaMiCloacaMuro(_cloaca, muroId: 42));
      await tester.pump();
      expect(find.text('Tu Cloaca'), findsOneWidget);
      expect(find.byKey(const Key('tarjeta_cloaca_unirme')), findsNothing);
    });

    testWidgets('en otra Cloaca: ve los cupos pero no UNIRME', (tester) async {
      nubeCloacas = _Nube(miaId: 'c1');
      await _montar(tester, const TarjetaMiCloacaMuro(_cloaca, muroId: 42));
      await tester.pump();
      expect(find.text('quedan 2 cupos'), findsOneWidget);
      expect(find.byKey(const Key('tarjeta_cloaca_unirme')), findsNothing);
    });

    testWidgets('llena y sin puesto: Llena, sin UNIRME', (tester) async {
      nubeCloacas = _Nube();
      await _montar(tester, TarjetaMiCloacaMuro({..._cloaca, 'miembros': 6, 'puesto': null}, muroId: 42));
      await tester.pump();
      expect(find.text('Llena'), findsOneWidget);
      expect(find.byKey(const Key('tarjeta_cloaca_puesto')), findsNothing);
      expect(find.byKey(const Key('tarjeta_cloaca_unirme')), findsNothing);
    });
  });
}
