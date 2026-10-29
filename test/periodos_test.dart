import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/periodos.dart';

void main() {
  // Miércoles 28 de octubre de 2026, 23:30 en Caracas (03:30 UTC del jueves).
  final ahora = DateTime.utc(2026, 10, 29, 3, 30);

  test('la semana cierra el lunes a medianoche de Caracas', () {
    expect(cierreDe('week', ahora), DateTime.utc(2026, 11, 2, 4));
  });

  test('el mes y el año cierran el día 1 a medianoche de Caracas', () {
    expect(cierreDe('month', ahora), DateTime.utc(2026, 11, 1, 4));
    expect(cierreDe('year', ahora), DateTime.utc(2027, 1, 1, 4));
    expect(cierreDe('month', DateTime.utc(2026, 12, 31, 12)), DateTime.utc(2027, 1, 1, 4));
  });

  test('el domingo en la noche todavía es la misma semana', () {
    // Domingo 1 de noviembre, 23:59 en Caracas.
    expect(cierreDe('week', DateTime.utc(2026, 11, 2, 3, 59)), DateTime.utc(2026, 11, 2, 4));
  });

  test('texto de lo que falta', () {
    expect(cuantoFalta(const Duration(days: 3, hours: 4, minutes: 10)), '3 d 4 h');
    expect(cuantoFalta(const Duration(hours: 5, minutes: 12)), '5 h 12 min');
    expect(cuantoFalta(const Duration(seconds: 20)), '1 min');
  });
}
