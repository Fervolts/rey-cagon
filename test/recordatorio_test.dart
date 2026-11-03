import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/recordatorio.dart';

void main() {
  test('de 7:30 a 23:29 no es de noche', () {
    expect(salidaDeNoche(DateTime(2026, 5, 3, 7, 30)), isNull);
    expect(salidaDeNoche(DateTime(2026, 5, 3, 14, 0)), isNull);
    expect(salidaDeNoche(DateTime(2026, 5, 3, 23, 29)), isNull);
  });

  test('desde las 23:30 sale a las 7:30 del día siguiente', () {
    expect(salidaDeNoche(DateTime(2026, 5, 3, 23, 30)), DateTime(2026, 5, 4, 7, 30));
    expect(salidaDeNoche(DateTime(2026, 5, 3, 23, 59)), DateTime(2026, 5, 4, 7, 30));
  });

  test('de madrugada sale a las 7:30 del mismo día', () {
    expect(salidaDeNoche(DateTime(2026, 5, 4, 0, 10)), DateTime(2026, 5, 4, 7, 30));
    expect(salidaDeNoche(DateTime(2026, 5, 4, 7, 29)), DateTime(2026, 5, 4, 7, 30));
  });

  test('cambia de mes y de año', () {
    expect(salidaDeNoche(DateTime(2026, 4, 30, 23, 45)), DateTime(2026, 5, 1, 7, 30));
    expect(salidaDeNoche(DateTime(2026, 12, 31, 23, 30)), DateTime(2027, 1, 1, 7, 30));
  });
}
