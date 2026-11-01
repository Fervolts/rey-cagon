import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/emoji.dart';

void main() {
  test('los emojis salen como widget y el texto queda solo', () {
    final partes = spansConEmojis('🐞 La app se cierra 👍🏽 ok 🇻🇪 © 2026');
    final widgets = partes.whereType<WidgetSpan>().length;
    final texto = partes.whereType<TextSpan>().map((s) => s.text).join('|');
    expect(widgets, 3);
    expect(texto, ' La app se cierra | ok | © 2026');
  });

  test('sin emojis queda un solo tramo', () {
    final partes = spansConEmojis('hola mundo');
    expect(partes, hasLength(1));
    expect((partes.single as TextSpan).text, 'hola mundo');
  });
}
