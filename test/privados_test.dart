import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/privados.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  const a = '0a1b2c3d-0000-4000-8000-000000000001';
  const b = 'ff00ee11-0000-4000-8000-000000000002';

  group('salaDm', () {
    test('es la misma sin importar quién la abre', () {
      expect(salaDm(a, b), 'dm:$a:$b');
      expect(salaDm(b, a), 'dm:$a:$b');
    });

    test('va en minúsculas, igual que public.dm_sala()', () {
      expect(salaDm(b.toUpperCase(), a), 'dm:$a:$b');
    });

    test('esSalaDm', () {
      expect(esSalaDm(salaDm(a, b)), isTrue);
      expect(esSalaDm('global'), isFalse);
      expect(esSalaDm('cloaca:1'), isFalse);
    });
  });

  group('otroDeSala', () {
    test('da el otro lado de la pareja', () {
      expect(otroDeSala(salaDm(a, b), a), b);
      expect(otroDeSala(salaDm(a, b), b), a);
    });

    test('null si no estoy en ella o no es dm', () {
      expect(otroDeSala(salaDm(a, b), 'otro'), isNull);
      expect(otroDeSala('global', a), isNull);
      expect(otroDeSala('dm:$a', a), isNull);
      expect(otroDeSala('dm:$a:$a', a), isNull);
      expect(otroDeSala('dm:$a:$b:x', a), isNull);
    });
  });

  group('privadoSinLeer', () {
    test('solo si el último es del otro y más nuevo que el visto', () {
      expect(privadoSinLeer(ultimo: 10, autor: b, yo: a, visto: 9), isTrue);
      expect(privadoSinLeer(ultimo: 10, autor: b, yo: a, visto: 10), isFalse);
      expect(privadoSinLeer(ultimo: 10, autor: a, yo: a, visto: 0), isFalse);
      expect(privadoSinLeer(ultimo: 10, autor: null, yo: a, visto: 0), isFalse);
    });
  });

  test('clavePrivadoVisto', () => expect(clavePrivadoVisto('dm:x:y'), 'privado_visto_dm:x:y'));

  group('faltaPrivados', () {
    test('la RPC o la columna no existen', () {
      expect(faltaPrivados(const PostgrestException(message: 'x', code: 'PGRST202')), isTrue);
      expect(faltaPrivados(const PostgrestException(message: 'x', code: '42883')), isTrue);
      expect(faltaPrivados(const PostgrestException(message: 'x', code: '42703')), isTrue);
    });

    test('otros errores no apagan los privados', () {
      expect(faltaPrivados(const PostgrestException(message: 'x', code: '42501')), isFalse);
      expect(faltaPrivados(Exception('red')), isFalse);
    });
  });

  test('errorPrivado: la base no deja escribir', () {
    expect(errorPrivado(const PostgrestException(message: 'new row violates row-level security policy', code: '42501')),
        'Esta persona no recibe tus mensajes ahora.');
  });

  test('horaPrivado: hora si es de hoy, día y mes si no', () {
    final hoy = DateTime(2026, 11, 4, 18);
    expect(horaPrivado(DateTime(2026, 11, 4, 9, 5).toUtc().toIso8601String(), ahora: hoy), '09:05');
    expect(horaPrivado(DateTime(2026, 11, 2, 9, 5).toUtc().toIso8601String(), ahora: hoy), '2/11');
  });
}
