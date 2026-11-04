import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/push.dart';

void main() {
  group('payload del aviso local', () {
    test('un privado lleva tipo y sala de ida y vuelta', () {
      const sala = 'dm:0a1b2c3d-0000-4000-8000-000000000001:ff00ee11-0000-4000-8000-000000000002';
      final payload = payloadDeAviso({'tipo': 'dm', 'sala': sala, 'envio': '42'});
      expect(payload, isNotNull);
      expect(datosDeAviso(payload), {'tipo': 'dm', 'sala': sala, 'envio': '42'});
    });

    test('sin datos no hay payload', () {
      expect(payloadDeAviso({}), isNull);
    });

    test('los recordatorios (sin payload) y lo que no se entiende dan null', () {
      expect(datosDeAviso(null), isNull);
      expect(datosDeAviso(''), isNull);
      expect(datosDeAviso('no es json'), isNull);
      expect(datosDeAviso('[1, 2]'), isNull);
      expect(datosDeAviso('"dm"'), isNull);
    });
  });
}
