import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/estado.dart';

void main() {
  group('usarCopiaLocal', () {
    test('sin copia local manda el servidor', () {
      expect(usarCopiaLocal(mjLocal: null, mjServidor: 0, servidorVacio: true), isFalse);
      expect(usarCopiaLocal(mjLocal: null, mjServidor: 500, servidorVacio: false), isFalse);
    });
    test('servidor vacío: manda la local aunque tenga menos', () {
      expect(usarCopiaLocal(mjLocal: 10, mjServidor: 999, servidorVacio: true), isTrue);
    });
    test('local con más MJ gana; con menos pierde', () {
      expect(usarCopiaLocal(mjLocal: 1001, mjServidor: 1000, servidorVacio: false), isTrue);
      expect(usarCopiaLocal(mjLocal: 999, mjServidor: 1000, servidorVacio: false), isFalse);
    });
    test('empate: gana el servidor', () {
      expect(usarCopiaLocal(mjLocal: 1000, mjServidor: 1000, servidorVacio: false), isFalse);
    });
  });

  group('inicioOffline', () {
    const ahora = 1800000000000;
    test('sin marcas válidas: null', () {
      expect(inicioOffline([], ahora), isNull);
      expect(inicioOffline([null, 0, -5], ahora), isNull);
    });
    test('toma la más reciente e ignora null y 0', () {
      expect(inicioOffline([ahora - 9000, null, ahora - 3000, 0, ahora - 6000], ahora), ahora - 3000);
    });
    test('una marca del futuro se recorta a ahora', () {
      expect(inicioOffline([ahora - 1000, ahora + 60000], ahora), ahora);
    });
  });

  group('aceptarRecorte', () {
    test('el servidor recorta: baja mjTotal y el saldo no lo pasa', () {
      final p = Partida.desdeJson(null)
        ..mjTotal = 5000
        ..saldo = 4000;
      aceptarRecorte(p, 3000);
      expect(p.mjTotal, 3000);
      expect(p.saldo, 3000);
    });
    test('recorte que no toca el saldo lo deja igual', () {
      final p = Partida.desdeJson(null)
        ..mjTotal = 5000
        ..saldo = 1000;
      aceptarRecorte(p, 3000);
      expect(p.mjTotal, 3000);
      expect(p.saldo, 1000);
    });
    test('si el servidor tiene igual o más, no cambia nada', () {
      final p = Partida.desdeJson(null)
        ..mjTotal = 5000
        ..saldo = 4000;
      aceptarRecorte(p, 5000);
      aceptarRecorte(p, 9000);
      expect(p.mjTotal, 5000);
      expect(p.saldo, 4000);
    });
  });
}
