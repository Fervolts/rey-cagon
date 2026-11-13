// Guardado en la nube del Imperio: si no sube, jalar no toca la partida; dos guardados a la vez no pierden lo último.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/telemetria.dart';

class _Nube extends NubeImperio {
  /// Si no es null, el primer guardado espera a que se complete.
  Completer<void>? bloqueo;
  bool falla = false;
  final List<Map<String, dynamic>> guardados = [];
  int jaladas = 0;

  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async {
    guardados.add(estado);
    final b = bloqueo;
    bloqueo = null;
    if (b != null) await b.future;
    if (falla) throw StateError('sin red');
    return ResultadoGuardar(mjTotal: mjTotal, recortado: false, guardado: DateTime.now());
  }

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');

  @override
  Future<int> jalar() async => ++jaladas;

  @override
  Future<int> usarFichas(String que) async => 5;
}

ControlImperio _control(_Nube nube) =>
    ControlImperio(nube: nube, telemetria: Telemetria(enviar: (_) async => 0))..imperio = Imperio(partida: Partida(edificios: {'dedo': 1}));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('si el guardado falla, jalar lanza y no toca la partida', () async {
    final nube = _Nube()..falla = true;
    final c = _control(nube);
    final antes = c.imperio.partida.jaladas;
    await expectLater(c.jalarCadena(), throwsA(isA<StateError>()));
    expect(nube.jaladas, 0);
    expect(c.imperio.partida.jaladas, antes);
    expect(c.jalando, isFalse);
    c.dispose();
  });

  test('un guardado pedido mientras otro vuela se repite con lo nuevo', () async {
    final bloqueo = Completer<void>();
    final nube = _Nube()..bloqueo = bloqueo;
    final c = _control(nube);
    final jalar = c.jalarCadena();
    await Future<void>.delayed(Duration.zero);
    expect(nube.guardados, hasLength(1));
    // Mientras sube el primero: usar Fichas cambia la partida y pide guardar (se suma al que vuela).
    expect(await c.usarFichas('tanque_extra'), isTrue);
    expect(nube.guardados, hasLength(1));
    // Suelta el primero: se repite con el tanque extra y recién ahí se jala.
    bloqueo.complete();
    await jalar;
    expect(nube.jaladas, 1);
    expect(nube.guardados.first['horas_extra_tanque'], 0);
    expect(nube.guardados[1]['horas_extra_tanque'], 1);
    c.dispose();
  });
}
