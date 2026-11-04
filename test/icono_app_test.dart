import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/icono_app.dart';

void main() {
  test('sin nada solo el normal', () {
    expect(iconosGanados(datosIconoVacios), {'normal'});
  });

  test('cada requisito abre su ícono', () {
    expect(iconosGanados((cagadas: 99, abdicaciones: 0, mejorRacha: 6, premioCloaca: false)), {'normal'});
    expect(iconosGanados((cagadas: 100, abdicaciones: 0, mejorRacha: 0, premioCloaca: false)), {'normal', 'dorado'});
    expect(iconosGanados((cagadas: 0, abdicaciones: 1, mejorRacha: 0, premioCloaca: false)), {'normal', 'corona'});
    expect(iconosGanados((cagadas: 0, abdicaciones: 0, mejorRacha: 7, premioCloaca: false)), {'normal', 'noche'});
    expect(iconosGanados((cagadas: 0, abdicaciones: 0, mejorRacha: 0, premioCloaca: true)), {'normal', 'cloaca'});
  });

  test('si se pierde el desbloqueo, el puesto se queda disponible', () {
    final g = iconosGanados(datosIconoVacios);
    expect(iconoDisponible('cloaca', g, 'cloaca'), isTrue);
    expect(iconoDisponible('cloaca', g, 'normal'), isFalse);
    expect(iconoDisponible('normal', g, 'cloaca'), isTrue);
  });

  test('racha de días seguidos', () {
    final d = DateTime(2026, 11, 1, 10);
    expect(mejorRachaDias([]), 0);
    expect(mejorRachaDias([for (var i = 0; i < 7; i++) d.add(Duration(days: i))]), 7);
    expect(mejorRachaDias([d, d.add(const Duration(hours: 2)), d.add(const Duration(days: 3))]), 1);
  });

  test('alias únicos y ids que existen como recursos', () {
    expect({for (final i in iconosApp) i.alias}.length, iconosApp.length);
    expect(iconosApp.map((i) => i.id), ['normal', 'dorado', 'corona', 'noche', 'cloaca']);
  });
}
