import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/accesorios.dart';
import 'package:rey_cagon/imperio/flags.dart';
import 'package:rey_cagon/imperio/hallaca.dart';
import 'package:rey_cagon/imperio/motor.dart';

const hora = 3600 * 1000;
final retreteDesde = DateTime.parse('2026-11-19T00:00:00-04:00').millisecondsSinceEpoch;
final retreteHasta = DateTime.parse('2026-11-20T00:00:00-04:00').millisecondsSinceEpoch;
final navidadDesde = DateTime.parse('2026-12-01T00:00:00-04:00').millisecondsSinceEpoch;

// Mismo valor que inserta la migración 20261106140000_imperio_temporadas.sql.
const flag2026 = [
  {'id': 'dia_retrete', 'desde': '2026-11-19T00:00:00-04:00', 'hasta': '2026-11-20T00:00:00-04:00', 'x': 3},
  {'id': 'navidad', 'desde': '2026-12-01T00:00:00-04:00', 'hasta': '2027-01-01T00:00:00-04:00', 'x': 1},
];

void main() {
  final lista = leerTemporadas(flag2026);

  group('leer el flag', () {
    test('las dos temporadas de 2026', () {
      expect(lista.map((t) => (t.id, t.x)), [('dia_retrete', 3.0), ('navidad', 1.0)]);
      expect(lista.first.hasta - lista.first.desde, 24 * hora);
    });

    test('entradas malas se saltan y x se recorta', () {
      final l = leerTemporadas([
        {'id': 'Mal Id', 'desde': '2026-11-19T00:00:00Z', 'hasta': '2026-11-20T00:00:00Z'},
        {'id': 'al_reves', 'desde': '2026-11-20T00:00:00Z', 'hasta': '2026-11-19T00:00:00Z'},
        {'id': 'sin_fecha', 'desde': 'ayer', 'hasta': '2026-11-19T00:00:00Z'},
        'basura',
        {'id': 'loca', 'desde': '2026-11-19T00:00:00Z', 'hasta': '2026-11-20T00:00:00Z', 'x': 1000},
        {'id': 'menos', 'desde': '2026-11-19T00:00:00Z', 'hasta': '2026-11-20T00:00:00Z', 'x': 0.2},
        {'id': 'texto', 'desde': '2026-11-19T00:00:00Z', 'hasta': '2026-11-20T00:00:00Z', 'x': '3'},
      ]);
      expect(l.map((t) => (t.id, t.x)), [('loca', 10.0), ('menos', 1.0), ('texto', 1.0)]);
      expect(leerTemporadas(null), isEmpty);
      expect(leerTemporadas({'id': 'x'}), isEmpty);
    });

    test('FlagsImperio pasa las temporadas a los ajustes', () {
      final f = FlagsImperio.desdeJson({
        'temporadas': {'valor': flag2026},
      });
      expect(f.ajustes.temporadas, lista);
      expect(FlagsImperio.desdeJson(const {}).ajustes.temporadas, isEmpty);
    });
  });

  group('rango y multiplicador', () {
    test('activa en [desde, hasta), hora de Caracas', () {
      expect(temporadaActiva(lista, temporadaDiaRetrete, retreteDesde - 1), isFalse);
      expect(temporadaActiva(lista, temporadaDiaRetrete, retreteDesde), isTrue);
      expect(temporadaActiva(lista, temporadaDiaRetrete, retreteHasta - 1), isTrue);
      expect(temporadaActiva(lista, temporadaDiaRetrete, retreteHasta), isFalse);
      // 18 nov 23:30 en Caracas ya es 19 nov en UTC: todavía no.
      expect(temporadaActiva(lista, temporadaDiaRetrete, DateTime.parse('2026-11-19T03:30:00Z').millisecondsSinceEpoch), isFalse);
      expect(temporadaActiva(lista, temporadaNavidad, navidadDesde + 10 * 24 * hora), isTrue);
      expect(temporadaActiva(lista, temporadaNavidad, retreteDesde), isFalse);
    });

    test('multiplicador: el mayor de las activas, 1 fuera', () {
      expect(multiplicadorTemporada(lista, retreteDesde + hora), 3);
      expect(multiplicadorTemporada(lista, navidadDesde + hora), 1);
      expect(multiplicadorTemporada(lista, retreteDesde - hora), 1);
      final pisadas = [...lista, Temporada('otra', retreteDesde, retreteHasta, 2)];
      expect(multiplicadorTemporada(pisadas, retreteDesde + hora), 3);
    });

    test('en rango: promedio pesado por el tiempo', () {
      expect(multiplicadorEnRango(lista, retreteDesde - hora, retreteDesde + hora), closeTo(2, 1e-9));
      expect(multiplicadorEnRango(lista, retreteDesde + hora, retreteDesde + 3 * hora), closeTo(3, 1e-9));
      expect(multiplicadorEnRango(lista, retreteHasta - hora, retreteHasta + 3 * hora), closeTo(1.5, 1e-9));
      expect(multiplicadorEnRango(lista, retreteDesde + hora, retreteDesde + hora), 3);
      expect(multiplicadorEnRango(const [], 0, hora), 1);
    });
  });

  group('motor', () {
    Imperio nuevo() => Imperio(ajustes: Ajustes(temporadas: lista))..partida.edificios['ciruela'] = 10;

    test('mps x3 solo el Día Mundial del Retrete', () {
      final imp = nuevo();
      final fuera = imp.mps(retreteDesde - hora);
      expect(fuera, greaterThan(0));
      expect(imp.mps(retreteDesde + hora), closeTo(fuera * 3, 1e-9));
      expect(imp.mps(navidadDesde + hora), closeTo(fuera, 1e-9));
      expect(imp.enTemporada(temporadaDiaRetrete, retreteDesde), isTrue);
      expect(imp.enTemporada(temporadaNavidad, retreteDesde), isFalse);
      // Sin el flag no hay temporada aunque sea 19 nov.
      final sinFlag = Imperio()..partida.edificios['ciruela'] = 10;
      expect(sinFlag.mps(retreteDesde + hora), closeTo(fuera, 1e-9));
      expect(sinFlag.enTemporada(temporadaDiaRetrete, retreteDesde + hora), isFalse);
    });

    test('offline: x3 por la parte que cayó en la temporada', () {
      final base = nuevo().aplicarOffline(retreteDesde - 3 * hora, retreteDesde - hora).ganado;
      final mitad = nuevo().aplicarOffline(retreteDesde - hora, retreteDesde + hora).ganado;
      final dentro = nuevo().aplicarOffline(retreteDesde + hora, retreteDesde + 3 * hora).ganado;
      expect(base, greaterThan(0));
      expect(mitad, closeTo(base * 2, 1e-6));
      expect(dentro, closeTo(base * 3, 1e-6));
    });

    test('jugar ese día da el logro dia_retrete; fuera de fecha no', () {
      final fuera = nuevo();
      fuera.tick(retreteDesde - hora, 1);
      expect(fuera.partida.temporadas, isEmpty);
      expect(fuera.tieneLogro('dia_retrete'), isFalse);
      final imp = nuevo();
      final nuevos = imp.tick(retreteDesde + hora, 1);
      expect(imp.partida.temporadas, contains(temporadaDiaRetrete));
      expect(nuevos.map((l) => l.id), contains('dia_retrete'));
      expect(imp.tieneLogro('dia_retrete'), isTrue);
      // Tick de 0 s (app en pausa) no cuenta como jugar.
      final quieto = nuevo()..tick(retreteDesde + hora, 0);
      expect(quieto.partida.temporadas, isEmpty);
    });

    test('Partida guarda las temporadas jugadas', () {
      final p = Partida(temporadas: {temporadaDiaRetrete});
      expect(Partida.desdeJson(p.toJson()).temporadas, {temporadaDiaRetrete});
      expect(Partida().toJson().containsKey('temporadas'), isFalse);
      expect(Partida.desdeJson(Partida().toJson()).temporadas, isEmpty);
    });
  });

  group('aspecto', () {
    test('gorro de Santa en el catálogo de premios, valor corto', () {
      final g = exclusivos.where((d) => d.emoji == gorroSanta).single;
      expect(g.ranura, 'sombrero');
      expect(gorroSanta.runes.length, 1);
      expect(desbloqueos.any((d) => d.emoji == gorroSanta), isFalse);
    });

    testWidgets('hallaca dorada y gorro de Santa se dibujan', (t) async {
      await t.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [HallacaDorada(tamano: 60), IconoAccesorio(gorroSanta, tamano: 40), IconoAccesorio('🧢', tamano: 40)]),
      ));
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(2));
      expect(t.getSize(find.byType(HallacaDorada)), const Size(60, 60));
      expect(t.takeException(), isNull);
    });
  });
}
