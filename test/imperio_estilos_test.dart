// Tienda de estilo del Imperio: catálogo de Dart contra la migración, gratis por tipo y temas con colores.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/estilos.dart';
import 'package:rey_cagon/imperio/flags.dart';
import 'package:rey_cagon/tema.dart';

final _migracion = File('supabase/migrations/20261106120000_imperio_estilos.sql').readAsStringSync();

/// Filas `('id', 'tipo', mj, rollos, cagadas)` del insert del catálogo.
List<(String, String, double, int, int)> _filasSql() => [
      for (final m in RegExp(r"\('(\w+)', '(\w+)', ([\de.]+), (\d+), (\d+)\)").allMatches(_migracion))
        (m.group(1)!, m.group(2)!, double.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!)),
    ];

void main() {
  test('el catálogo de Dart y el de la base son iguales', () {
    final sql = _filasSql();
    expect(sql.length, estilos.length);
    for (final (id, tipo, mj, rollos, cagadas) in sql) {
      final e = estiloPorId(id);
      expect(e, isNotNull, reason: '$id está en la base y no en Dart');
      expect((e!.tipo.name, e.mj, e.rollos, e.cagadas), (tipo, mj, rollos, cagadas), reason: id);
    }
  });

  test('ids únicos', () {
    expect(estilos.map((e) => e.id).toSet().length, estilos.length);
  });

  test('un solo gratis por tipo, y es el de fábrica', () {
    for (final tipo in TipoEstilo.values) {
      final gratis = estilosDe(tipo).where((e) => e.gratis).toList();
      expect(gratis.length, 1, reason: tipo.name);
      expect(gratis.single.id, switch (tipo) {
        TipoEstilo.tema => temaClasico,
        TipoEstilo.efecto => efectoNinguno,
        TipoEstilo.movimiento => movimientoNinguno,
      });
    }
  });

  test('tieneEstilo: los gratis siempre, los demás si se compraron', () {
    expect(tieneEstilo({}, temaClasico), isTrue);
    expect(tieneEstilo({}, efectoNinguno), isTrue);
    expect(tieneEstilo({}, 'tema_oro'), isFalse);
    expect(tieneEstilo({'tema_oro'}, 'tema_oro'), isTrue);
    expect(tieneEstilo({'no_existe'}, 'no_existe'), isFalse);
  });

  test('cada tema de pago tiene colores, y el texto contrasta con el acento', () {
    final pagos = estilosDe(TipoEstilo.tema).where((e) => !e.gratis).map((e) => e.id).toSet();
    expect(temasConColores.toSet(), pagos);
    for (final id in [temaClasico, ...pagos]) {
      final p = muestraDeTema(id);
      // Contraste WCAG del texto sobre el acento (botones) y del texto sobre el fondo.
      double contraste(Color a, Color b) {
        final (x, y) = (a.computeLuminance(), b.computeLuminance());
        return (max(x, y) + .05) / (min(x, y) + .05);
      }

      expect(contraste(p.acento, p.acentoTexto), greaterThanOrEqualTo(4.5), reason: '$id acento');
      expect(contraste(p.fondo, p.texto), greaterThanOrEqualTo(4.5), reason: '$id texto');
      expect(brilloDeEstilo(id), id == temaClasico ? isNull : isA<Brightness>());
    }
  });

  test('flag del precio: por defecto 1 y en la migración', () {
    expect(FlagsImperio.porDefecto.estiloPrecioMult, 1);
    expect(_migracion, contains("('estilo_precio_mult', '1'"));
  });
}
