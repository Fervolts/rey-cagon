// Tienda: los avisos de comprar, alquilar o "por qué no" salen dentro de la hoja, no tapados por ella.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/telemetria.dart';
import 'package:rey_cagon/imperio/tienda_ciruelas.dart';

class _Nube extends NubeImperio {
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

void main() {
  testWidgets('el aviso sale en la hoja y se va solo', (t) async {
    final c = ControlImperio(nube: _Nube(), telemetria: Telemetria(enviar: (_) async => 0))..imperio = Imperio(partida: Partida(edificios: {'dedo': 1}));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => abrirTiendaCiruelas(context, c,
                arriba: (_, avisar) => TextButton(key: const Key('probar'), onPressed: () => avisar('💸', 'Te faltan 5 MJ'), child: const Text('x'))),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('aviso_tienda')), findsNothing);
    await t.tap(find.byKey(const Key('probar')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('aviso_tienda')), findsOneWidget);
    expect(find.text('Te faltan 5 MJ'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('aviso_tienda')), findsNothing);
  });
}
