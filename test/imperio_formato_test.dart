import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/formato.dart';

void main() {
  test('formatoMj español', () {
    expect(formatoMj(0), '0');
    expect(formatoMj(0.1), '0,1');
    expect(formatoMj(12.5), '12,5');
    expect(formatoMj(12), '12');
    expect(formatoMj(99.96), '100');
    expect(formatoMj(999), '999');
    expect(formatoMj(999.4), '999');
    expect(formatoMj(1000), '1 K');
    expect(formatoMj(1500), '1,5 K');
    expect(formatoMj(15000), '15 K');
    expect(formatoMj(1e6), '1 M');
    expect(formatoMj(1.234e9), '1,23 B');
    expect(formatoMj(1e12), '1 T');
    expect(formatoMj(1e15), '1 Qa');
    expect(formatoMj(1e18), '1 Qi');
    expect(formatoMj(999999), '1 M');
    expect(formatoMj(1e21), '1e21');
    expect(formatoMj(1.234e21), '1,23e21');
  });

  test('formatoMj inglés', () {
    expect(formatoMj(12.5, ingles: true), '12.5');
    expect(formatoMj(1.234e9, ingles: true), '1.23 B');
    expect(formatoMj(1.234e21, ingles: true), '1.23e21');
  });

  test('monedaPara', () {
    expect(monedaPara('VE', ingles: false).abreviatura, 'MjBs');
    expect(monedaPara('ve', ingles: false).nombre, 'Mojolívares');
    expect(monedaPara('MX', ingles: false).nombre, 'Mojopesos');
    expect(monedaPara('ES', ingles: false).abreviatura, 'Mj€');
    expect(monedaPara('DE', ingles: false).nombre, 'Mojeuros');
    expect(monedaPara('PE', ingles: false).abreviatura, 'MjS/');
    expect(monedaPara('US', ingles: false).nombre, 'Mojonólares');
    expect(monedaPara(null, ingles: false).nombre, 'Mojonólares');
    expect(monedaPara('VE', ingles: true).nombre, 'Poopbucks');
    expect(monedaPara('VE', ingles: true).abreviatura, 'PB');
  });
}
