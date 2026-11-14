import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/cartas/catalogo.dart';
import 'package:rey_cagon/emoji.dart';

void main() {
  test('128 cartas en orden', () {
    expect(cartas.length, 128);
    for (var i = 0; i < cartas.length; i++) {
      expect(cartas[i].n, i + 1);
      expect(carta(i + 1), same(cartas[i]));
    }
  });

  test('rarezas por rango: 64 comunes, 36 raras, 20 épicas, 8 legendarias', () {
    Rareza esperada(int n) => n <= 64
        ? Rareza.comun
        : n <= 100
            ? Rareza.rara
            : n <= 120
                ? Rareza.epica
                : Rareza.legendaria;
    for (final c in cartas) {
      expect(c.rareza, esperada(c.n), reason: 'carta ${c.n}');
    }
    final cuenta = {for (final r in Rareza.values) r: cartas.where((c) => c.rareza == r).length};
    expect(cuenta, {Rareza.comun: 64, Rareza.rara: 36, Rareza.epica: 20, Rareza.legendaria: 8});
  });

  test('emojis únicos (también sin el selector FE0F)', () {
    final vistos = <String>{};
    for (final c in cartas) {
      expect(vistos.add(c.emoji.replaceAll('\u{FE0F}', '')), isTrue, reason: 'repetido ${c.emoji} en la carta ${c.n}');
    }
  });

  test('textos no vacíos y frases de 70 caracteres o menos', () {
    for (final c in cartas) {
      for (final t in [c.emoji, c.nombreEs, c.nombreEn, c.fraseEs, c.fraseEn]) {
        expect(t.trim(), isNotEmpty, reason: 'carta ${c.n}');
      }
      expect(c.fraseEs.length, lessThanOrEqualTo(70), reason: 'carta ${c.n}: ${c.fraseEs}');
      expect(c.fraseEn.length, lessThanOrEqualTo(70), reason: 'carta ${c.n}: ${c.fraseEn}');
    }
  });

  test('cada emoji tiene su PNG', () {
    for (final c in cartas) {
      expect(tieneEmoji(c.emoji), isTrue, reason: 'carta ${c.n}: ${c.emoji} sin PNG en lib/emoji.dart');
    }
    // Y cada archivo del mapa de lib/emoji.dart existe en assets/emoji/.
    final fuente = File('lib/emoji.dart').readAsStringSync();
    final archivos = RegExp(r"^  '[^']+': '(\w+)',", multiLine: true).allMatches(fuente).map((m) => m[1]!).toList();
    expect(archivos.length, greaterThan(128));
    for (final a in archivos) {
      expect(File('assets/emoji/$a.png').existsSync(), isTrue, reason: 'falta assets/emoji/$a.png');
    }
  });
}
