import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/novedades.dart';

void main() {
  test('historial de novedades bien formado', () {
    expect(historialNovedades, isNotEmpty);
    expect(historialNovedades.first.version, '2.19.2');
    for (var i = 0; i < historialNovedades.length; i++) {
      final v = historialNovedades[i];
      expect(v.novedades, isNotEmpty, reason: v.version);
      for (final n in v.novedades) {
        expect(n.$1.trim(), isNotEmpty);
        expect(n.$2.trim(), isNotEmpty);
        expect(n.$3.trim(), isNotEmpty);
      }
      if (i > 0) {
        expect(compararVersiones(historialNovedades[i - 1].version, v.version), greaterThan(0), reason: v.version);
      }
    }
  });
}
