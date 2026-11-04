// Cloacas 🚽: lo que responde el servidor (cloaca_mia, cloaca_ranking y las acciones), los textos de cada motivo,
// sacar el código de una invitación y el bono de producción en el Imperio.
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/cloaca.dart';
import 'package:rey_cagon/idioma.dart';
import 'package:rey_cagon/imperio/control.dart';
import 'package:rey_cagon/imperio/motor.dart';
import 'package:rey_cagon/imperio/nube.dart';
import 'package:rey_cagon/imperio/telemetria.dart';

class _Nube extends NubeImperio {
  @override
  Future<void> guardarLocal(String userId, Map<String, dynamic> estado, double mjTotal, double mps) async {}

  @override
  Future<ResultadoGuardar> guardar(Map<String, dynamic> estado, double mjTotal, double mps, {int? version}) async => throw StateError('sin red');

  @override
  Future<CargaImperio> cargar() async => throw StateError('sin red');
}

class _NubeCloacas extends NubeCloacas {
  _NubeCloacas(this.respuesta);

  Object respuesta;

  @override
  Future<double> bono() async {
    final r = respuesta;
    if (r is Exception) throw r;
    return r as double;
  }

  @override
  Future<EstadoCloaca> mia() async => const EstadoCloaca();
}

Map<String, dynamic> _mia() => {
      'cloaca': {
        'id': 'c1',
        'nombre': 'Los Tapados',
        'emoji': '🚽',
        'codigo': '278QX9',
        'dueno': 'u1',
        'soy_dueno': true,
        'sala': 'cloaca:c1',
        'puntos': 57,
        'puesto': 1,
        'bono': 0.1,
        'miembros': [
          {
            'user_id': 'u1',
            'username': 'ana',
            'avatar': '🦨',
            'dueno': true,
            'unido': '2026-11-02T10:00:00+00:00',
            'cagadas': 4,
            'pts_cagadas': 40,
            'pts_imperio': 7,
            'puntos': 47,
            'cago_hoy': true,
          },
          {'user_id': 'u2', 'username': 'beto', 'dueno': false, 'cagadas': 1, 'pts_cagadas': 10, 'pts_imperio': 0, 'puntos': 10, 'cago_hoy': false},
        ],
      },
      'premios': [
        {'id': '5b0c1e2a-0000-4000-8000-000000000003', 'semana': '2026-10-26', 'rollos': 2},
        {'id': '5b0c1e2a-0000-4000-8000-000000000004', 'semana': '2026-10-19', 'rollos': 2},
      ],
      'semana': '2026-11-02',
      'cierra': '2026-11-09T04:00:00+00:00',
      'max': 25,
      'premio': 2,
      'bono_por': 0.05,
      'bono_tope': 0.5,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => idioma.value = 'es');

  group('EstadoCloaca', () {
    test('con Cloaca: todos los campos', () {
      final e = EstadoCloaca.desdeJson(_mia());
      final c = e.cloaca!;
      expect(c.id, 'c1');
      expect(c.nombre, 'Los Tapados');
      expect(c.emoji, '🚽');
      expect(c.codigo, '278QX9');
      expect(c.sala, 'cloaca:c1');
      expect(c.soyDueno, isTrue);
      expect(c.puntos, 57);
      expect(c.puesto, 1);
      expect(c.bono, 0.1);
      expect(c.miembros, hasLength(2));
      expect(c.cagaronHoy, 1);
      final ana = c.miembros.first;
      expect(ana.username, 'ana');
      expect(ana.avatar, '🦨');
      expect(ana.dueno, isTrue);
      expect(ana.unido, DateTime.utc(2026, 11, 2, 10));
      expect((ana.cagadas, ana.ptsCagadas, ana.ptsImperio, ana.puntos), (4, 40, 7, 47));
      expect(ana.cagoHoy, isTrue);
      expect(c.miembros.last.avatar, isNull);
      expect(e.premios.map((p) => p.id), ['5b0c1e2a-0000-4000-8000-000000000003', '5b0c1e2a-0000-4000-8000-000000000004']);
      expect(e.rollosPorCobrar, 4);
      expect(e.semana, '2026-11-02');
      expect(e.cierra, DateTime.utc(2026, 11, 9, 4));
      expect((e.max, e.premio, e.bonoPor, e.bonoTope), (25, 2, 0.05, 0.5));
    });

    test('sin Cloaca, sin sesión (null) o con números como texto', () {
      final sin = EstadoCloaca.desdeJson({'cloaca': null, 'premios': [], 'semana': '2026-11-02', 'max': 30});
      expect(sin.cloaca, isNull);
      expect(sin.premios, isEmpty);
      expect(sin.max, 30);
      expect(sin.premio, premioRollosDefecto);
      final nada = EstadoCloaca.desdeJson(null);
      expect(nada.cloaca, isNull);
      expect(nada.cierra, isNull);
      expect((nada.max, nada.bonoPor, nada.bonoTope), (maxMiembrosDefecto, bonoPorMiembroDefecto, bonoTopeDefecto));
      final texto = EstadoCloaca.desdeJson({
        'cloaca': {'id': 'c9', 'nombre': 'X', 'emoji': '', 'codigo': 'AAAAA2', 'puntos': '12', 'bono': '0.15', 'puesto': null},
      });
      expect(texto.cloaca!.puntos, 12);
      expect(texto.cloaca!.bono, 0.15);
      expect(texto.cloaca!.puesto, isNull);
      expect(texto.cloaca!.emoji, '💩');
      expect(texto.cloaca!.sala, 'cloaca:c9');
      expect(texto.cloaca!.miembros, isEmpty);
    });
  });

  group('RankingCloacas', () {
    test('filas, la mía y la ganadora de la semana pasada', () {
      final r = RankingCloacas.desdeJson({
        'semana': '2026-11-02',
        'cierra': '2026-11-09T04:00:00+00:00',
        'filas': [
          {'id': 'c1', 'nombre': 'Los Tapados', 'emoji': '🚽', 'puntos': 57, 'miembros': 3, 'puesto': 1, 'mia': true},
          {'id': 'c2', 'nombre': 'Otra', 'emoji': '🐀', 'puntos': 20, 'miembros': 2, 'puesto': 2, 'mia': false},
        ],
        'anterior': {'semana': '2026-10-26', 'nombre': 'Los Tapados', 'emoji': '🚽', 'puntos': 57, 'miembros': 3},
      });
      expect(r.filas.map((f) => f.puesto), [1, 2]);
      expect(r.filas.first.mia, isTrue);
      expect(r.filas.last.mia, isFalse);
      expect(r.filas.last.emoji, '🐀');
      expect(r.cierra, DateTime.utc(2026, 11, 9, 4));
      expect(r.anterior!.nombre, 'Los Tapados');
      expect(r.anterior!.puntos, 57);
      expect(r.anterior!.semana, '2026-10-26');
    });

    test('vacío', () {
      final r = RankingCloacas.desdeJson({'semana': '2026-11-02', 'filas': [], 'anterior': null});
      expect(r.filas, isEmpty);
      expect(r.anterior, isNull);
      expect(RankingCloacas.desdeJson(null).filas, isEmpty);
    });
  });

  group('ResultadoCloaca y motivos', () {
    test('crear bien y mal', () {
      final ok = ResultadoCloaca.desdeJson({'ok': true, 'id': 'c1', 'codigo': '278QX9'});
      expect((ok.ok, ok.id, ok.codigo), (true, 'c1', '278QX9'));
      final mal = ResultadoCloaca.desdeJson({'ok': false, 'motivo': 'nombre', 'texto': 'No se permiten enlaces.'});
      expect(mal.ok, isFalse);
      expect(textoMotivoCloaca(mal.motivo, texto: mal.texto), 'No se permiten enlaces.');
      final cobro = ResultadoCloaca.desdeJson({'ok': true, 'rollos': 2});
      expect(cobro.rollos, 2);
      expect(ResultadoCloaca.desdeJson(null).ok, isFalse);
    });

    test('cada motivo tiene su texto y el desconocido uno genérico', () {
      const motivos = [
        'codigo', 'emoji', 'expulsado', 'llena', 'muchos_cambios', 'no_dueno', 'no_existe', 'no_miembro', //
        'nombre_usado', 'nombre', 'sin_cloaca', 'sin_imperio', 'sin_sesion', 'ya_tienes',
      ];
      final generico = textoMotivoCloaca('otra_cosa');
      for (final m in motivos) {
        expect(textoMotivoCloaca(m), isNot(generico), reason: m);
      }
      expect(textoMotivoCloaca(null), generico);
    });

    test('en inglés el texto del nombre no se usa (viene en español)', () {
      idioma.value = 'en';
      expect(textoMotivoCloaca('nombre', texto: 'No se permiten enlaces.'), contains('not allowed'));
    });
  });

  group('codigoDeTexto', () {
    test('el código solo, en minúsculas o con espacios', () {
      expect(codigoDeTexto('278QX9'), '278QX9');
      expect(codigoDeTexto('  278qx9 '), '278QX9');
      expect(codigoDeTexto('abcdef'), 'ABCDEF');
    });

    test('dentro de la invitación', () {
      final c = Cloaca.desdeJson({'id': 'c1', 'nombre': 'Los Tapados', 'emoji': '🚽', 'codigo': '278QX9'});
      expect(codigoDeTexto(textoInvitacion(c)), '278QX9');
      idioma.value = 'en';
      expect(codigoDeTexto(textoInvitacion(c)), '278QX9');
      expect(codigoDeTexto('Únete a CLOACA ya. Código: K7MNP2'), 'K7MNP2');
    });

    test('nada que parezca un código', () {
      expect(codigoDeTexto(''), isNull);
      expect(codigoDeTexto('hola'), isNull);
      expect(codigoDeTexto('CLOACA IMPERIO'), isNull);
      expect(codigoDeTexto('ABC12'), isNull);
      expect(codigoDeTexto('ABCDEF12'), isNull);
    });
  });

  group('bono de la Cloaca en el Imperio', () {
    test('sube la producción y tiene tope de x2', () {
      final i = Imperio(partida: Partida(edificios: {'dedo': 10}));
      final base = i.multiplicadorPermanente;
      final mps = i.mpsSinEfectos();
      expect(i.multiplicadorCloaca, 1);
      i.bonoCloaca = 0.25;
      expect(i.multiplicadorCloaca, 1.25);
      expect(i.multiplicadorPermanente, closeTo(base * 1.25, 1e-9));
      expect(i.mpsSinEfectos(), closeTo(mps * 1.25, 1e-9));
      i.bonoCloaca = 5;
      expect(i.multiplicadorCloaca, 2);
      i.bonoCloaca = -1;
      expect(i.multiplicadorCloaca, 1);
    });

    test('el bono no se guarda en la partida', () {
      final i = Imperio(partida: Partida(edificios: {'dedo': 1}));
      final antes = i.toJson().toString();
      i.bonoCloaca = 0.3;
      expect(i.toJson().toString(), antes);
    });

    test('el control lo pide al servidor y sin red lo deja como estaba', () async {
      final nube = _NubeCloacas(0.15);
      final c = ControlImperio(nube: _Nube(), telemetria: Telemetria(enviar: (_) async => 0))
        ..imperio = Imperio(partida: Partida(edificios: {'dedo': 1}))
        ..nubeCloaca = nube;
      await c.cargarCloaca();
      expect(c.imperio.bonoCloaca, 0.15);
      nube.respuesta = Exception('sin red');
      await c.cargarCloaca();
      expect(c.imperio.bonoCloaca, 0.15);
      c.dispose();
    });
  });

  test('textoBono', () {
    expect(textoBono(0.05), '+5%');
    expect(textoBono(0.5), '+50%');
    expect(textoBono(0), '+0%');
  });
}
