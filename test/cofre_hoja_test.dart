// Hoja del Cofre del Trono: chip con x/3, ABRIR y ✓; la hoja explica la meta, abre y muestra lo que salió.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/cofre.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/telemetria.dart';

class _NubeCofre extends NubeImperio {
  bool abierto = false;

  @override
  Future<EstadoCofre> cofre({bool reclamar = false}) async {
    if (reclamar && !abierto) {
      abierto = true;
      return const EstadoCofre(dias: 3, listo: false, reclamado: true, reclamadoAhora: true, semanasRacha: 2, fichas: 5, ciruelas: 4,
          fichasGanadas: 0, ciruelasGanadas: 4);
    }
    return abierto
        ? const EstadoCofre(dias: 3, listo: false, reclamado: true, semanasRacha: 2, fichas: 5, ciruelas: 4)
        : const EstadoCofre(dias: 3, listo: true, reclamado: false, semanasRacha: 1, fichas: 5, ciruelas: 0);
  }

  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

Widget _app(ControlImperio c) => MaterialApp(
      home: Scaffold(body: Center(child: ListenableBuilder(listenable: c, builder: (_, _) => ChipCofre(control: c, avisar: (_, _) {})))),
    );

void main() {
  test('diasParaLunes', () {
    expect(diasParaLunes(DateTime(2026, 11, 2)), 7); // lunes
    expect(diasParaLunes(DateTime(2026, 11, 8)), 1); // domingo
  });

  testWidgets('chip x/3 abre la hoja con la meta y sin botón activo', (t) async {
    final c = ControlImperio(nube: _NubeCofre(), telemetria: Telemetria(enviar: (_) async => 0))
      ..imperio = Imperio(partida: Partida(edificios: {'dedo': 1}), fichas: 5)
      ..cofre = const EstadoCofre(dias: 1, listo: false, reclamado: false, semanasRacha: 0, fichas: 5, ciruelas: 0);
    await t.pumpWidget(_app(c));
    expect(find.text('1/3'), findsOneWidget);
    await t.tap(find.byKey(const Key('chip_cofre')));
    await t.pumpAndSettle();
    expect(find.textContaining('Llevas 1 de 3'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('abrir_cofre'))).onPressed, isNull);
  });

  testWidgets('listo: ABRIR, se abre y muestra el premio; el chip queda en ✓', (t) async {
    final c = ControlImperio(nube: _NubeCofre(), telemetria: Telemetria(enviar: (_) async => 0))
      ..imperio = Imperio(partida: Partida(edificios: {'dedo': 1}), fichas: 5)
      ..cofre = const EstadoCofre(dias: 3, listo: true, reclamado: false, semanasRacha: 1, fichas: 5, ciruelas: 0);
    await t.pumpWidget(_app(c));
    expect(find.text('ABRIR'), findsOneWidget);
    await t.tap(find.byKey(const Key('chip_cofre')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('abrir_cofre')));
    await t.pumpAndSettle();
    expect(find.text('¡ABRISTE EL COFRE!'), findsOneWidget);
    expect(find.text('+4 Ciruelas'), findsOneWidget);
    expect(find.textContaining('Fichas estaban llenas'), findsOneWidget);
    expect(find.text('2 semanas seguidas'), findsOneWidget);
    await t.tap(find.byType(FilledButton));
    await t.pumpAndSettle();
    expect(find.text('✓'), findsOneWidget);
  });
}
