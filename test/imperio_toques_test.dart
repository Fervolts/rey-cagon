import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/imperio/bano.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/vitrina.dart';

const _amplio = 218.0; // piso de más de un teléfono normal con la escena llenando la zona

void main() {
  group('Bano.objetoEn', () {
    const conTodo = EstadoBano(bidet: 2, papel: true, matica: true, arepa: 1, planta: 1, claseMedia: 8);

    test('piso amplio: bidet, tobo, bombillo, reactor y lo de la pared', () {
      expect(Bano.objetoEn(conTodo, const Offset(100, 270), _amplio), 'bidet');
      expect(Bano.objetoEn(conTodo, const Offset(-104, 294), _amplio), 'tobo');
      expect(Bano.objetoEn(conTodo, Bano.bombillo, _amplio), 'bombillo');
      expect(Bano.objetoEn(conTodo, const Offset(112, 150), _amplio), 'reactor');
      expect(Bano.objetoEn(conTodo, const Offset(74, 140), _amplio), 'papel');
      expect(Bano.objetoEn(conTodo, const Offset(80, 30), _amplio), 'ventana');
      expect(Bano.objetoEn(conTodo, const Offset(-145, 60), _amplio), 'espejo');
      expect(Bano.objetoEn(conTodo, const Offset(-145, 150), _amplio), 'lavamanos');
      expect(Bano.objetoEn(conTodo, Bano.cuadro, _amplio), 'cuadro');
      expect(Bano.objetoEn(conTodo, const Offset(174, 30), _amplio), 'ducha');
      expect(Bano.objetoEn(const EstadoBano(claseMedia: 3), Bano.cuadro, _amplio), isNull, reason: 'el cuadro sale con la mejora 4');
    });

    test('la poceta no es una cosa: ahí solo se puja', () {
      expect(Bano.objetoEn(conTodo, const Offset(0, 150), _amplio), isNull);
      expect(Bano.objetoEn(conTodo, const Offset(-40, 200), _amplio), isNull);
    });

    test('lo que no está comprado no se toca', () {
      const vacio = EstadoBano();
      expect(Bano.objetoEn(vacio, const Offset(100, 270), _amplio), isNull);
      expect(Bano.objetoEn(vacio, const Offset(112, 150), _amplio), isNull);
      expect(Bano.objetoEn(vacio, const Offset(74, 140), _amplio), isNull, reason: 'sin papel comprado no hay rollo');
      expect(Bano.objetoEn(vacio, const Offset(-104, 294), _amplio), 'tobo', reason: 'el tobo siempre está');
    });

    test('sin piso de más el bidet queda arriba, en la franja de piso', () {
      expect(Bano.objetoEn(conTodo, const Offset(100, 250), 0), 'bidet');
      expect(Bano.objetoEn(conTodo, const Offset(100, 290), 0), isNull);
    });

    test('el bidet nunca se monta en el reactor ni en la poceta', () {
      for (final suelo in [0.0, 60.0, _amplio, 400.0]) {
        final caja = Bano.cajaBidet(Bano.lugares(conTodo, suelo));
        expect(caja.overlaps(Bano.reactor), isFalse, reason: 'suelo $suelo');
        expect(caja.overlaps(const Rect.fromLTRB(-56, 86, 56, 216)), isFalse, reason: 'suelo $suelo');
      }
    });

    test('el chorro del bidet no sube hasta el reactor', () {
      for (final suelo in [0.0, 60.0, _amplio, 400.0]) {
        final l = Bano.lugares(conTodo, suelo);
        final pico = Bano.chorroBidet(l).dy - Bano.altoChorro(l, conTodo, 200);
        expect(pico, greaterThan(Bano.reactor.bottom), reason: 'suelo $suelo');
      }
      final sinPlanta = Bano.lugares(const EstadoBano(bidet: 2), _amplio);
      expect(Bano.altoChorro(sinPlanta, const EstadoBano(bidet: 2), 70), 70, reason: 'sin reactor sube lo que quiera');
    });
  });

  group('toques y logros escondidos', () {
    test('toques va y vuelve por JSON', () {
      final p = Partida(toques: {'bidet': 3, 'cucaracha': 1});
      final otra = Partida.desdeJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(otra.toques, {'bidet': 3, 'cucaracha': 1});
      expect(Partida.desdeJson({}).toques, isEmpty, reason: 'partidas viejas sin la clave');
    });

    test('espantar 10 veces a la cucaracha da Cazacucarachas', () {
      final imp = Imperio();
      for (var i = 0; i < 9; i++) {
        expect(imp.tocarObjeto('cucaracha').map((l) => l.id), isNot(contains('cucaracha_cazador')));
      }
      expect(imp.tocarObjeto('cucaracha').map((l) => l.id), contains('cucaracha_cazador'));
      expect(imp.tieneLogro('cucaracha_cazador'), isTrue);
      expect(imp.tocarObjeto('cucaracha'), isEmpty, reason: 'no se gana dos veces');
    });

    test('cada escondido sale con su toque', () {
      final casos = {'bidet_en_la_cara': ('bidet', 5), 'bombillo_quemado': ('bombillo', 20), 'corneta_camion': ('camion', 5), 'arepa_voladora': ('arepa', 12)};
      for (final MapEntry(key: logro, value: (cosa, veces)) in casos.entries) {
        final imp = Imperio();
        for (var i = 1; i < veces; i++) {
          imp.tocarObjeto(cosa);
        }
        expect(imp.tieneLogro(logro), isFalse, reason: logro);
        imp.tocarObjeto(cosa);
        expect(imp.tieneLogro(logro), isTrue, reason: logro);
      }
    });

    test('Metiche: 6 cosas distintas; lo desconocido no cuenta', () {
      final imp = Imperio();
      expect(imp.tocarObjeto('poceta'), isEmpty);
      expect(imp.partida.toques, isEmpty);
      for (final c in ['bidet', 'tobo', 'espejo', 'ventana', 'papel']) {
        imp.tocarObjeto(c);
      }
      expect(imp.tieneLogro('metiche'), isFalse);
      imp.tocarObjeto('reactor');
      expect(imp.tieneLogro('metiche'), isTrue);
    });

    test('los toques sobreviven a la jalada', () {
      final imp = Imperio();
      imp.tocarObjeto('arepa');
      imp.jalar();
      expect(imp.partida.toques['arepa'], 1);
    });

    test('hay 8 escondidos, ids únicos', () {
      expect(logros.where((l) => l.oculto).length, 8);
      expect(logros.map((l) => l.id).toSet().length, logros.length);
    });
  });

  group('vitrina del Imperio', () {
    test('los escondidos no salen hasta ganarlos; cuentan como secretos por encontrar', () {
      final ocultos = {for (final l in logros) if (l.oculto) 'imperio:${l.id}'};
      final sinNada = trofeosImperio({});
      expect(sinNada.where((t) => ocultos.contains(t.clave)), isEmpty);
      expect(sinNada.length, logros.length - 8);
      expect(secretosImperioPorEncontrar({}), 8);

      final conUno = trofeosImperio({'metiche'});
      expect(conUno.where((t) => t.clave == 'imperio:metiche').single.ganado, isTrue);
      expect(secretosImperioPorEncontrar({'metiche'}), 7);
    });
  });
}
