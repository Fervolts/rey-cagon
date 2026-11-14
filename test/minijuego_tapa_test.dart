// Con un minijuego encima, el Imperio de abajo no avisa (no reconstruye pantallas detrás del juego).
// El guardado diferido no se prueba aquí: el bucle mide el tiempo con un Stopwatch real, no con el reloj falso.
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/telemetria.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nube sin red.
class _Nube extends NubeImperio {
  _Nube(this.estado);
  final Map<String, dynamic> estado;
  @override
  Future<Map<String, dynamic>?> cargarLocal(String userId) async => {'estado': estado, 'mjTotal': 0.0};
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}
  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async => throw StateError('sin red');
  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'http://localhost:1',
        publishableKey: 'x',
        authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), detectSessionInUri: false));
  });

  testWidgets('jugandoMinijuego: sin avisos mientras se juega; al soltar avisa una vez y sigue a 10 por segundo', (t) async {
    final im = Imperio(cagadas: 30);
    final nube = _Nube({...im.toJson(), 'ultima_vez': DateTime.now().millisecondsSinceEpoch, '_cagadas': 30});
    final c = ControlImperio(nube: nube, telemetria: Telemetria(enviar: (_) async => 0), pedirFlags: () async => throw StateError('sin red'), leerBuild: () async => 1);
    await t.runAsync(c.iniciar);
    c.visible = true;
    var avisos = 0;
    c.addListener(() => avisos++);

    await t.pump(const Duration(seconds: 1));
    expect(avisos, greaterThanOrEqualTo(9)); // 10 por segundo sin minijuego

    c.jugandoMinijuego(true);
    avisos = 0;
    for (var i = 0; i < 120; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(avisos, 0);

    c.jugandoMinijuego(false);
    expect(avisos, 1);
    await t.pump(const Duration(seconds: 1));
    expect(avisos, greaterThanOrEqualTo(10)); // vuelve a 10 por segundo

    c.visible = false;
    c.dispose();
  });
}
