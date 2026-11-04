import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/alquilados.dart';

void main() {
  test('un corte: dice qué, por qué y cómo prenderlo', () {
    final a = avisoAlquilerCortado([('robot', 100.0, 40.0)]);
    expect(a.titulo, isNotEmpty);
    final t = a.lineas.join('\n');
    expect(t, contains('Robot destapador'));
    expect(t, contains('100'));
    expect(t, contains('40'));
    expect(t, contains('Indefinido'));
  });

  test('saldo alcanza: dice que ya no se puede renovar', () {
    final a = avisoAlquilerCortado([('robot', 10.0, 40.0)]);
    expect(a.lineas.join('\n'), contains('Ya no se puede renovar'));
  });

  test('varios cortes: una línea por cada uno', () {
    final a = avisoAlquilerCortado([('robot', 100.0, 40.0), ('robot', 5.0, 1.0)]);
    expect(a.lineas.first, contains('2 alquileres'));
    expect(a.lineas.length, 4);
  });
}
