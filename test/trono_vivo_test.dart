import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart';
import 'package:rey_cagon/emoji.dart';
import 'package:rey_cagon/logros.dart';
import 'package:rey_cagon/tema.dart';
import 'package:rey_cagon/trono_vivo.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Las piezas vivas del TRONO, cada una con un ganar falso (no toca la base).

final _ganadas = <String>[];
Future<void> _ganar(BuildContext context, String clave) async => _ganadas.add(clave);

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: tema(Brightness.light), home: Scaffold(body: Center(child: hijo))));
}

Finder _emoji(String e) => find.byWidgetPredicate((w) => w is Emoji && w.emoji == e);

void main() {
  setUp(() {
    _ganadas.clear();
    movimientoElegido.value = 'completo';
  });
  tearDown(() => movimientoElegido.value = 'auto');

  test('los secretos nuevos están en el catálogo', () {
    final claves = logrosSecretos.map((l) => l.clave).toSet();
    expect(claves, containsAll(['trono_mosca', 'trono_pujo', 'trono_golpe', 'trono_desvelo', 'trono_filosofo']));
    expect(claves.length, logrosSecretos.length, reason: 'claves repetidas');
  });

  test('frases: primera según hora o cuenta, al menos 10 distintas y fijas en el día', () {
    final madrugada = frasesDelTrono(DateTime(2026, 11, 1, 3, 10), 0);
    expect(madrugada.first, contains('3 de la mañana'));
    expect(madrugada.toSet().length, madrugada.length);
    expect(madrugada.length, greaterThanOrEqualTo(10));
    expect(frasesDelTrono(DateTime(2026, 11, 1, 15), 5).first, contains('RAMPAGE'));
    expect(frasesDelTrono(DateTime(2026, 11, 1, 9), 2), frasesDelTrono(DateTime(2026, 11, 1, 20), 2));
  });

  testWidgets('título: 7 toques seguidos es golpe de estado, 6 no', (tester) async {
    await _montar(tester, const TituloTrono(texto: 'Rey Cagón', ganar: _ganar));
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('Rey Cagón'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));
    expect(_ganadas, isEmpty);
    expect(_emoji('👑'), findsNothing);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Rey Cagón'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_emoji('👑'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(_ganadas, ['trono_golpe']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('frase: tocar pasa a la siguiente; 10 leídas es filósofo', (tester) async {
    await _montar(tester, FraseDelTrono(hoy: 0, ahora: () => DateTime(2026, 11, 1, 10), ganar: _ganar));
    final frases = frasesDelTrono(DateTime(2026, 11, 1, 10), 0);
    expect(find.text(frases[0]), findsOneWidget);
    for (var i = 1; i < 9; i++) {
      await tester.tap(find.byType(FraseDelTrono));
      await tester.pumpAndSettle();
      expect(find.text(frases[i]), findsOneWidget);
    }
    expect(_ganadas, isEmpty);
    await tester.tap(find.byType(FraseDelTrono));
    await tester.pumpAndSettle();
    expect(_ganadas, ['trono_filosofo']);
  });

  testWidgets('frase: a las 3 am gana insomnio, a otra hora no', (tester) async {
    await _montar(tester, FraseDelTrono(hoy: 1, ahora: () => DateTime(2026, 11, 1, 14), ganar: _ganar));
    await tester.pump();
    expect(_ganadas, isEmpty);
    await _montar(tester, FraseDelTrono(key: UniqueKey(), hoy: 0, ahora: () => DateTime(2026, 11, 1, 3, 5), ganar: _ganar));
    await tester.pump();
    expect(_ganadas, ['trono_desvelo']);
  });

  Widget boton(List<int> toques) => GestureDetector(onTap: () => toques.add(1), child: const SizedBox(width: 200, height: 200, child: ColoredBox(color: Colors.white)));

  testWidgets('mosca: aparece, vuela sin tapar el botón y aplastarla no toca el botón', (tester) async {
    final toques = <int>[];
    await _montar(tester, ZonaMosca(ganar: _ganar, aparece: const Duration(seconds: 1), child: boton(toques)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_emoji('🪰'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_emoji('🪰'), findsOneWidget);
    final centro = tester.getCenter(find.byType(ZonaMosca));
    // Una vuelta entera: la caja que se toca de la mosca nunca entra al círculo del botón.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final caja = tester.getRect(find.ancestor(of: _emoji('🪰'), matching: find.byType(SizedBox)).first);
      final cerca = Offset((centro.dx - centro.dx.clamp(caja.left, caja.right)), (centro.dy - centro.dy.clamp(caja.top, caja.bottom)));
      expect(cerca.distance, greaterThan(100), reason: 'cuadro $i');
    }
    await tester.tap(_emoji('🪰'));
    await tester.pump();
    expect(_emoji('💥'), findsOneWidget);
    expect(_ganadas, ['trono_mosca']);
    expect(toques, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(_emoji('💥'), findsNothing);
    expect(_emoji('🪰'), findsNothing);
  });

  testWidgets('mosca: con movimiento nada se queda quieta (no hay animación corriendo)', (tester) async {
    movimientoElegido.value = 'nada';
    await _montar(tester, ZonaMosca(ganar: _ganar, aparece: const Duration(seconds: 1), child: boton([])));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_emoji('🪰'), findsOneWidget);
    final antes = tester.getCenter(_emoji('🪰'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(_emoji('🪰')), antes);
  });

  testWidgets('mosca: en una pestaña escondida del IndexedStack no aparece', (tester) async {
    await _montar(tester, IndexedStack(index: 1, children: [ZonaMosca(ganar: _ganar, aparece: const Duration(seconds: 1), child: boton([])), const SizedBox()]));
    await tester.pump(const Duration(seconds: 3));
    expect(find.descendant(of: find.byType(ZonaMosca), matching: _emoji('🪰'), skipOffstage: false), findsNothing);
  });

  // Igual que el botón CAGUÉ: el toque normal cuenta; el que terminó en pujo, no.
  Widget conPujo(List<int> cagadas, List<int> pujos) {
    var pujo = false;
    return GestureDetector(
      onTapDown: (_) => pujo = false,
      onTap: () {
        if (pujo) return;
        cagadas.add(1);
      },
      child: Pujo(
        ganar: _ganar,
        alPujar: () {
          pujo = true;
          pujos.add(1);
        },
        child: const SizedBox(width: 200, height: 200, child: ColoredBox(color: Colors.white)),
      ),
    );
  }

  testWidgets('pujo: 3 segundos apretado es pujo eterno y no registra; un toque normal sí', (tester) async {
    final cagadas = <int>[], pujos = <int>[];
    await _montar(tester, conPujo(cagadas, pujos));
    await tester.tap(find.byType(Pujo));
    await tester.pump();
    expect(cagadas, [1]);

    final corto = await tester.startGesture(tester.getCenter(find.byType(Pujo)));
    await tester.pump(const Duration(seconds: 2));
    await corto.up();
    await tester.pump();
    expect(pujos, isEmpty);
    expect(cagadas, [1, 1]);

    final largo = await tester.startGesture(tester.getCenter(find.byType(Pujo)));
    await tester.pump(duracionPujo + const Duration(milliseconds: 100));
    expect(pujos, [1]);
    await largo.up();
    await tester.pump();
    expect(cagadas, [1, 1], reason: 'el pujo no registra cagada');
    await tester.pump(const Duration(seconds: 2));
    expect(_ganadas, ['trono_pujo']);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('pujo: si el dedo se mueve, se cancela', (tester) async {
    final pujos = <int>[];
    await _montar(tester, conPujo([], pujos));
    final g = await tester.startGesture(tester.getCenter(find.byType(Pujo)));
    await tester.pump(const Duration(seconds: 1));
    await g.moveBy(const Offset(0, 40));
    await tester.pump(duracionPujo);
    await g.up();
    await tester.pump();
    expect(pujos, isEmpty);
    expect(_ganadas, isEmpty);
  });
}
