import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/flags.dart';
import 'package:rey_cagon/imperio/telemetria.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Telemetria', () {
    test('la cola se queda con los 500 más nuevos', () async {
      final t = Telemetria(enviar: (_) async => 0, azar: Random(1));
      for (var i = 0; i < 520; i++) {
        t.registrar('logro', {'n': i});
      }
      await t.guardar();
      expect(t.pendientes, Telemetria.maxCola);
      expect((t.cola.first['datos'] as Map)['n'], 20);
      expect((t.cola.last['datos'] as Map)['n'], 519);
    });

    test('manda en lotes de 100 y vacía la cola', () async {
      final lotes = <int>[];
      final t = Telemetria(enviar: (l) async {
        lotes.add(l.length);
        return l.length;
      });
      for (var i = 0; i < 250; i++) {
        t.registrar('pujo_x', {'n': i});
      }
      await t.vaciar();
      expect(lotes, [100, 100, 50]);
      expect(t.pendientes, 0);
      final p = await SharedPreferences.getInstance();
      expect(jsonDecode(p.getString(Telemetria.clavePrefs)!), isEmpty);
    });

    test('si falla un lote, se queda con lo que no salió', () async {
      var llamadas = 0;
      final t = Telemetria(enviar: (l) async {
        if (++llamadas == 2) throw Exception('sin red');
        return l.length;
      });
      for (var i = 0; i < 250; i++) {
        t.registrar('logro', {'n': i});
      }
      await t.vaciar();
      expect(t.pendientes, 150);
      expect((t.cola.first['datos'] as Map)['n'], 100);
      await t.vaciar();
      expect(t.pendientes, 0);
    });

    test('lo guardado sobrevive a otro arranque y va delante', () async {
      final a = Telemetria(enviar: (_) async => throw Exception('sin red'));
      a.registrar('sesion_inicio', {'cagadas': 3});
      await a.vaciar();
      final enviados = <String>[];
      final b = Telemetria(enviar: (l) async {
        enviados.addAll([for (final e in l) e['evento'] as String]);
        return l.length;
      });
      b.registrar('sesion_fin', {'segundos': 10});
      await b.vaciar();
      expect(enviados, ['sesion_inicio', 'sesion_fin']);
    });

    test('forma del evento, nombres malos fuera, datos limpios', () async {
      final t = Telemetria(enviar: (_) async => 0, reloj: () => 1234, version: '1.0.0+1');
      t.registrar('Mal-Nombre');
      t.registrar('offline', {'ganado': double.nan, 'tope_lleno': true, 'segundos': double.infinity});
      t.registrar('error', {'donde': 'x' * 5000});
      t.registrar('error', {'lista': List.generate(40, (i) => 'y' * 200)});
      expect(t.pendientes, 3);
      final e = t.cola.first;
      expect(e['evento'], 'offline');
      expect(e['ms'], 1234);
      expect(e['version'], '1.0.0+1');
      expect(e['sesion'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(e['datos'], {'ganado': null, 'tope_lleno': true, 'segundos': null});
      expect((t.cola[1]['datos'] as Map)['donde'], hasLength(200));
      expect(t.cola[2]['datos'], {'recortado': true});
      expect(() => jsonEncode(t.cola), returnsNormally);
    });
  });

  group('FlagsImperio', () {
    Map<String, Object?> f(Object? valor, [String? variante]) => {'valor': valor, 'variante': variante};

    test('sin nada da los defaults del catálogo', () {
      final d = FlagsImperio.desdeJson(null);
      expect(d.activo, true);
      expect(d.doradoIntervaloMin, [5, 15]);
      expect(d.offlinePorcentaje, 0.25);
      expect(d.offlineTopeH, 2);
      expect(d.precioCrecimiento, 1.15);
      expect(d.precioGuantes, 100);
      expect(d.precioFaja, 500);
      expect(d.cagadaBonoPct, 2);
      expect(d.variantes, isEmpty);
    });

    test('lee valores y variantes', () {
      final x = FlagsImperio.desdeJson({
        'imperio_activo': f(false),
        'dorado_intervalo_min': f([3, 9], 'rapido'),
        'offline_porcentaje': f(0.3, 'base'),
        'precio_crecimiento': f('1.12'),
        'precio_faja': f(400),
      });
      expect(x.activo, false);
      expect(x.doradoIntervaloMin, [3, 9]);
      expect(x.offlinePorcentaje, 0.3);
      expect(x.precioCrecimiento, 1.12);
      expect(x.precioFaja, 400);
      expect(x.variantes, {'dorado_intervalo_min': 'rapido', 'offline_porcentaje': 'base'});
    });

    test('tipos malos caen al default y los números se recortan', () {
      final x = FlagsImperio.desdeJson({
        'imperio_activo': f('no'),
        'dorado_intervalo_min': f([0, 999]),
        'offline_porcentaje': f(7),
        'offline_tope_h': f({'h': 2}),
        'precio_crecimiento': f(0.5),
        'precio_guantes': f(double.nan),
        'cagada_bono_pct': f(-3),
        'basura': 'texto',
      });
      expect(x.activo, true);
      expect(x.doradoIntervaloMin, [1, 120]);
      expect(x.offlinePorcentaje, 1);
      expect(x.offlineTopeH, 2);
      expect(x.precioCrecimiento, 1.01);
      expect(x.precioGuantes, 100);
      expect(x.cagadaBonoPct, 0);
      expect(FlagsImperio.desdeJson({'dorado_intervalo_min': f([20, 10])}).doradoIntervaloMin, [10, 20]);
      expect(FlagsImperio.desdeJson({'dorado_intervalo_min': f([5])}).doradoIntervaloMin, [5, 15]);
    });

    test('cargar guarda copia y la usa si no hay red', () async {
      final bien = await FlagsImperio.cargar(usuario: 'u1', pedir: () async => {'precio_guantes': f(150)});
      expect(bien.precioGuantes, 150);
      final sinRed = await FlagsImperio.cargar(usuario: 'u1', pedir: () async => throw Exception('sin red'));
      expect(sinRed.precioGuantes, 150);
      final otro = await FlagsImperio.cargar(usuario: 'u2', pedir: () async => throw Exception('sin red'));
      expect(otro.precioGuantes, 100);
    });
  });
}
