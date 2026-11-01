import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/motor.dart';

// Borrar la cagada real (calendario) quita su Cagada fresca; lo comprado con Ciruelas encima se queda.
void main() {
  const h = 3600000;
  const t0 = 1000000000000;
  bool fresca(Imperio imp, int ahora) => imp.efectosActivos(ahora).any((e) => e.id == 'cagada_fresca');

  test('sin cagada anterior: el bono se va', () {
    final imp = Imperio()..aplicarFrescaHasta(t0 + h);
    expect(fresca(imp, t0 + 60000), isTrue);
    expect(imp.recortarFresca(t0 + h, 0, t0 + 60000), isTrue);
    expect(fresca(imp, t0 + 60000), isFalse);
  });

  test('con cagada anterior todavía fresca: baja hasta su fin', () {
    final imp = Imperio()..aplicarFrescaHasta(t0 + h);
    expect(imp.recortarFresca(t0 + h, t0 + h ~/ 2, t0 + 60000), isTrue);
    expect(fresca(imp, t0 + h ~/ 2 - 1), isTrue);
    expect(fresca(imp, t0 + h ~/ 2 + 1), isFalse);
  });

  test('lo comprado con Ciruelas se queda', () {
    final imp = Imperio()..aplicarFrescaHasta(t0 + h);
    imp.activarCagadaFresca(t0 + 60000); // +1 h encima: hasta t0 + 2 h
    expect(imp.recortarFresca(t0 + h, 0, t0 + 60000), isTrue);
    // Le quedaba 1 h comprada: ahora vence 1 h después de "ahora".
    expect(fresca(imp, t0 + 60000 + h - 1000), isTrue);
    expect(fresca(imp, t0 + 60000 + h + 1000), isFalse);
  });

  test('si ya venció sola no toca nada', () {
    final imp = Imperio()..aplicarFrescaHasta(t0 + h);
    expect(imp.recortarFresca(t0 + h, 0, t0 + h), isFalse);
  });
}
