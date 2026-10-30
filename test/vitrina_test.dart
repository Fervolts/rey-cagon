import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/logros.dart';
import 'package:rey_cagon/vitrina.dart';

typedef Cagada = ({DateTime cuando, int? tipo, int? peso});

Cagada c(int anio, int mes, int dia, int hora, [int minuto = 0, int? tipo, int? peso]) =>
    (cuando: DateTime(anio, mes, dia, hora, minuto), tipo: tipo, peso: peso);

List<Trofeo> calcular(List<Cagada> cagadas, {Set<String> claves = const {}, bool lado = false, bool verLado = true, int victorias = 0}) =>
    trofeos(
      cagadas: cagadas,
      total: cagadas.length,
      victorias: victorias,
      favorito: null,
      claves: claves,
      ladoSecreto: lado,
      verLadoSecreto: verLado,
    );

bool ganado(List<Trofeo> lista, String clave) => lista.firstWhere((t) => t.clave == clave).ganado;
Set<String> secretos(List<Trofeo> lista) => {for (final t in lista) if (t.grupo == Grupo.secreto) t.clave};

void main() {
  test('sin cagadas: todos los normales con candado y ningún secreto', () {
    final lista = calcular([]);
    expect(lista.where((t) => t.grupo != Grupo.secreto).length, 22);
    expect(lista.any((t) => t.ganado), isFalse);
    expect(secretos(lista), isEmpty);
    expect(secretosPorEncontrar(lista), logrosSecretos.length);
  });

  test('rachas por día: 3 en un día gana DOUBLE y TRIPLE, no ULTRA', () {
    // Martes 6 de octubre de 2026.
    final lista = calcular([c(2026, 10, 6, 8), c(2026, 10, 6, 9), c(2026, 10, 6, 10)]);
    expect(ganado(lista, 'racha'), isTrue);
    expect(ganado(lista, 'triple'), isTrue);
    expect(ganado(lista, 'ultra'), isFalse);
    expect(secretos(lista), isNot(contains('hexa')));
  });

  test('6 en un día destapa el secreto HEXA', () {
    final lista = calcular([for (var h = 7; h < 13; h++) c(2026, 10, 6, h, 5)]);
    expect(ganado(lista, 'rampage'), isTrue);
    expect(secretos(lista), contains('hexa'));
  });

  test('horas y fechas raras: 11:11, 3:33, 1 de enero y viernes 13', () {
    final lista = calcular([
      c(2026, 10, 6, 11, 11),
      c(2026, 10, 7, 3, 33),
      c(2027, 1, 1, 10),
      c(2026, 11, 13, 10), // viernes 13 de noviembre de 2026
    ]);
    expect(secretos(lista), containsAll(['hora_1111', 'hora_333', 'ano_nuevo', 'viernes_13']));
    expect(secretosPorEncontrar(lista), logrosSecretos.length - 4);
  });

  test('un 13 que no es viernes o las 11:12 no cuentan', () {
    final lista = calcular([c(2026, 10, 13, 11, 12)]); // martes 13
    expect(secretos(lista), isEmpty);
  });

  test('hazañas de horario: madrugador, nocturno, sobremesa, oficinista, finde, reloj suizo', () {
    final lista = calcular([
      c(2026, 10, 3, 2), // sábado, 2 am
      c(2026, 10, 4, 5), // domingo, 5 am
      for (var d = 5; d <= 9; d++) c(2026, 10, d, 12, 30), // lun a vie, 12:30
      for (var d = 12; d <= 16; d++) c(2026, 10, d, 10), // lun a vie, 10 am
    ]);
    expect(ganado(lista, 'nocturno'), isTrue);
    expect(ganado(lista, 'madrugador'), isTrue);
    expect(ganado(lista, 'finde'), isTrue);
    expect(ganado(lista, 'almuerzo'), isTrue);
    expect(ganado(lista, 'oficinista'), isTrue);
    expect(ganado(lista, 'puntual'), isTrue);
    expect(ganado(lista, 'semana'), isTrue); // del sábado 3 al viernes 9 son 7 seguidos
    expect(ganado(lista, 'mes'), isFalse);
  });

  test('coleccionista y peso pluma', () {
    final lista = calcular([
      for (var t = 1; t <= 7; t++) c(2026, 10, t, 8, 0, t, 1),
      for (var d = 8; d <= 10; d++) c(2026, 10, d, 8, 0, 1, 1),
    ]);
    expect(ganado(lista, 'coleccionista'), isTrue);
    expect(ganado(lista, 'pluma'), isTrue);
    expect(ganado(lista, 'ballena'), isFalse);
  });

  test('mes perfecto: todos los días de febrero', () {
    final lista = calcular([for (var d = 1; d <= 28; d++) c(2026, 2, d, 9)]);
    expect(ganado(lista, 'mes'), isTrue);
    expect(ganado(lista, 'semana'), isTrue);
  });

  test('los secretos de eventos salen de las claves guardadas', () {
    final lista = calcular([], claves: {'psst_meon', 'corona'});
    expect(secretos(lista), {'psst_meon', 'corona'});
  });

  test('el lado secreto no se le enseña a quien no lo tiene', () {
    expect(secretos(calcular([], lado: true)), contains('placer_lado'));
    expect(secretos(calcular([], lado: true, verLado: false)), isNot(contains('placer_lado')));
    expect(secretos(calcular([], claves: {'placer_lado'}, verLado: false)), isEmpty);
  });

  test('los secretos ganados son trofeos ganados del grupo Secretos', () {
    final lista = calcular([c(2026, 10, 6, 11, 11)]);
    final t = lista.firstWhere((t) => t.clave == 'hora_1111');
    expect(t.ganado, isTrue);
    expect(t.grupo, Grupo.secreto);
  });
}
