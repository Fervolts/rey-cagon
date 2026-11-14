import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/cartas/logica.dart';

void main() {
  test('costo de cada nivel suma 15 repetidas hasta rainbow', () {
    expect(costoMejora(0), 1);
    expect(costoMejora(4), 5);
    expect([for (var n = 0; n < nivelMax; n++) costoMejora(n)].reduce((a, b) => a + b), 15);
  });

  test('repetidas disponibles nunca negativas', () {
    expect(repetidasDisponibles(1, 0), 0);
    expect(repetidasDisponibles(5, 1), 3);
    expect(repetidasDisponibles(2, 3), 0);
  });

  test('puede mejorar igual que el servidor', () {
    expect(puedeMejorar(nivel: 0, copias: 1, gastadas: 0), isFalse);
    expect(puedeMejorar(nivel: 0, copias: 2, gastadas: 0), isTrue);
    expect(puedeMejorar(nivel: 1, copias: 3, gastadas: 1), isFalse);
    expect(puedeMejorar(nivel: 1, copias: 4, gastadas: 1), isTrue);
    expect(puedeMejorar(nivel: 5, copias: 99, gastadas: 0), isFalse);
    // 16 copias alcanzan justo para rainbow.
    var nivel = 0, gastadas = 0;
    while (puedeMejorar(nivel: nivel, copias: 16, gastadas: gastadas)) {
      gastadas += costoMejora(nivel);
      nivel++;
    }
    expect(nivel, nivelMax);
  });

  test('logros de colección', () {
    expect(logrosDeColeccion(distintas: 9, nivelMasAlto: 3), isEmpty);
    expect(logrosDeColeccion(distintas: 30, nivelMasAlto: 4), {'cartas_10', 'cartas_30', 'carta_dorada'});
    expect(logrosDeColeccion(distintas: 128, nivelMasAlto: 5, abrioSobreRey: true),
        {'cartas_10', 'cartas_30', 'cartas_64', 'cartas_100', 'cartas_128', 'carta_dorada', 'carta_rainbow', 'sobre_rey'});
  });

  test('sobres', () {
    expect(cartasDelSobre('normal'), 3);
    expect(cartasDelSobre('plata'), 4);
    expect(cartasDelSobre('rey'), 5);
    for (final t in ['normal', 'plata', 'oro', 'rey']) {
      expect(porcentajesDelSobre(t).reduce((a, b) => a + b), 100);
    }
  });

  test('horas hasta el próximo', () {
    final ahora = DateTime(2026, 1, 1, 15, 10);
    expect(horasHasta(DateTime(2026, 1, 2), ahora), 9);
    expect(horasHasta(DateTime(2026, 1, 1, 15, 40), ahora), 1);
    expect(horasHasta(DateTime(2026, 1, 1, 15), ahora), 0);
  });
}
