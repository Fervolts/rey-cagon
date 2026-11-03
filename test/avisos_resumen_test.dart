import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/avisos_resumen.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

ResumenAvisos _resumen({int total = 47, int prendidas = 8, Map<String, int>? por}) =>
    ResumenAvisos(total: total, porCategoria: por ?? {'cagadas': 30, 'rachas': 10, 'chat': 7}, prendidas: prendidas, categorias: 8);

final _ahora = DateTime(2026, 5, 20, 12);

Future<void> _montar(WidgetTester tester, Widget hijo, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(MaterialApp(theme: tema(Brightness.light), home: Scaffold(body: ListView(children: [hijo]))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => idioma.value = 'es');

  group('cuándo sale la tarjeta', () {
    test('todas prendidas y 25 o más: sale', () {
      expect(debeMostrarTarjetaAvisos(_resumen(total: 25), null, _ahora), isTrue);
      expect(debeMostrarTarjetaAvisos(_resumen(total: 47), null, _ahora), isTrue);
    });

    test('menos de 25: no sale', () {
      expect(debeMostrarTarjetaAvisos(_resumen(total: 24), null, _ahora), isFalse);
    });

    test('con alguna apagada: no sale', () {
      expect(debeMostrarTarjetaAvisos(_resumen(prendidas: 7), null, _ahora), isFalse);
    });

    test('sin resumen (no hay RPC o no hay red): no sale', () {
      expect(debeMostrarTarjetaAvisos(null, null, _ahora), isFalse);
    });

    test('descartada: vuelve a los 14 días, no antes', () {
      expect(debeMostrarTarjetaAvisos(_resumen(), _ahora.subtract(const Duration(days: 13, hours: 23)), _ahora), isFalse);
      expect(debeMostrarTarjetaAvisos(_resumen(), _ahora.subtract(const Duration(days: 14)), _ahora), isTrue);
    });
  });

  test('lee lo que devuelve push_resumen_mio', () {
    final r = ResumenAvisos.desdeJson({
      'dias': 7,
      'total': 4,
      'por_tipo': {'cagada': 3, 'version': 1},
      'por_categoria': {'otros': 1, 'rachas': 1, 'cagadas': 2},
      'prendidas': 8,
      'categorias': 8,
    })!;
    expect(r.total, 4);
    expect(r.de('cagadas'), 2);
    expect(r.de('retos'), 0);
    expect(r.todasPrendidas, isTrue);
    expect(ResumenAvisos.desdeJson(null), isNull);
    expect(ResumenAvisos.desdeJson({'total': 'x'}), isNull);
  });

  test('el texto lleva los números y la categoría que más manda', () {
    expect(textoTarjetaAvisos(_resumen()), 'Esta semana te llegaron 47 avisos: 30 de cagadas de amigos. Elige cuáles quieres.');
    idioma.value = 'en';
    expect(textoTarjetaAvisos(_resumen()), "This week you got 47 alerts: 30 from friends' poops. Pick the ones you want.");
  });

  testWidgets('sale, anota que la vio y al descartarla se guarda la fecha', (tester) async {
    final eventos = <String>[];
    await _montar(tester, TarjetaOrdenaAvisos(cargar: () async => _resumen(), ahora: () => _ahora, anotar: (e, _) => eventos.add(e)));
    expect(find.byKey(const ValueKey('tarjeta_ordena_avisos')), findsOneWidget);
    expect(find.textContaining('47 avisos'), findsOneWidget);
    expect(eventos, ['avisos_tarjeta_ve']);

    await tester.tap(find.byKey(const ValueKey('tarjeta_avisos_descartar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tarjeta_ordena_avisos')), findsNothing);
    expect(eventos, ['avisos_tarjeta_ve', 'avisos_tarjeta_descarta']);
    expect((await SharedPreferences.getInstance()).getInt(prefTarjetaAvisos), _ahora.millisecondsSinceEpoch);
  });

  testWidgets('descartada hace poco: ni pregunta al servidor', (tester) async {
    var preguntas = 0;
    await _montar(
      tester,
      TarjetaOrdenaAvisos(cargar: () async { preguntas++; return _resumen(); }, ahora: () => _ahora, anotar: (_, _) {}),
      prefs: {prefTarjetaAvisos: _ahora.subtract(const Duration(days: 3)).millisecondsSinceEpoch},
    );
    expect(find.byKey(const ValueKey('tarjeta_ordena_avisos')), findsNothing);
    expect(preguntas, 0);
  });

  testWidgets('sin RPC no sale nada y nada falla', (tester) async {
    await _montar(tester, TarjetaOrdenaAvisos(cargar: () async => throw Exception('no existe'), anotar: (_, _) {}));
    expect(find.byKey(const ValueKey('tarjeta_ordena_avisos')), findsNothing);
    await _montar(tester, TarjetaOrdenaAvisos(cargar: () async => null, anotar: (_, _) {}));
    expect(find.byKey(const ValueKey('tarjeta_ordena_avisos')), findsNothing);
  });

  testWidgets('el botón abre los ajustes y al volver se vuelve a mirar', (tester) async {
    final eventos = <String>[];
    var resumen = _resumen();
    var abiertos = 0;
    await _montar(
      tester,
      TarjetaOrdenaAvisos(
        cargar: () async => resumen,
        ahora: () => _ahora,
        anotar: (e, _) => eventos.add(e),
        abrirAjustes: (_) async {
          abiertos++;
          resumen = _resumen(prendidas: 6);
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tarjeta_avisos_abrir')));
    await tester.pumpAndSettle();
    expect(abiertos, 1);
    expect(eventos, ['avisos_tarjeta_ve', 'avisos_tarjeta_abre']);
    expect(find.byKey(const ValueKey('tarjeta_ordena_avisos')), findsNothing);
  });
}
