import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/animaciones.dart' show Movimiento, movimientoElegido;
import 'package:rey_cagon/imperio/estilos.dart' show movimientoNinguno;
import 'package:rey_cagon/imperio/ranking_amigos.dart';
import 'package:rey_cagon/movimientos_avatar.dart';
import 'package:rey_cagon/perfil.dart' show leerImperioPerfil;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('movimientos del avatar', () {
    test('ids', () {
      expect(animDe(null), isNull);
      expect(animDe(movimientoNinguno), isNull);
      expect(animDe('mov_inventado'), isNull);
      expect(animDe('mov_bailar'), AnimAvatar.bailar);
    });

    test('nada: nunca se anima', () {
      for (final a in AnimAvatar.values) {
        expect(comoAnimar('mov_${a.name}', Movimiento.nada), isNull, reason: a.name);
      }
    });

    test('completo: todo, sin reducir', () {
      expect(comoAnimar('mov_temblar', Movimiento.completo), (anim: AnimAvatar.temblar, reducida: false, fija: false));
      expect(comoAnimar('mov_brillo', Movimiento.completo), (anim: AnimAvatar.brillo, reducida: false, fija: false));
      expect(comoAnimar(null, Movimiento.completo), isNull);
    });

    test('simple: solo los baratos, reducidos; brillo fijo', () {
      for (final a in [AnimAvatar.respirar, AnimAvatar.rebotar, AnimAvatar.saludar, AnimAvatar.flotar]) {
        expect(comoAnimar('mov_${a.name}', Movimiento.simple), (anim: a, reducida: true, fija: false), reason: a.name);
      }
      for (final a in [AnimAvatar.temblar, AnimAvatar.girar, AnimAvatar.bailar]) {
        expect(comoAnimar('mov_${a.name}', Movimiento.simple), isNull, reason: a.name);
      }
      expect(comoAnimar('mov_brillo', Movimiento.simple)?.fija, isTrue);
    });

    test('simple es más lento', () {
      for (final a in AnimAvatar.values) {
        expect(duracionDe(a, reducida: true) > duracionDe(a), isTrue, reason: a.name);
      }
    });

    test('en t = 0 está en reposo (salvo flotar y el halo del brillo)', () {
      for (final a in AnimAvatar.values) {
        final p = poseDe(a, 0);
        expect(p.dy.abs() < 1e-9 && p.angulo.abs() < 1e-9 && p.giroY.abs() < 1e-9, isTrue, reason: a.name);
        expect((p.escala - 1).abs() < 1e-9, isTrue, reason: a.name);
      }
    });

    test('la versión reducida se mueve menos', () {
      for (final a in [AnimAvatar.rebotar, AnimAvatar.flotar, AnimAvatar.bailar, AnimAvatar.respirar]) {
        double maximo(bool reducida) {
          var m = 0.0;
          for (var i = 0; i <= 100; i++) {
            final p = poseDe(a, i / 100, reducida: reducida);
            m = [m, p.dx.abs(), p.dy.abs(), p.angulo.abs(), (p.escala - 1).abs()].reduce((x, y) => x > y ? x : y);
          }
          return m;
        }

        expect(maximo(true) < maximo(false), isTrue, reason: a.name);
      }
    });
  });

  group('ranking del Imperio', () {
    final fila = {
      'user_id': 'u1',
      'username': 'alguien',
      'avatar': '💩',
      'mj_total': 1500.5,
      'rollos': 3,
      'jaladas': 2,
      'yo': false,
      'movimiento': 'mov_flotar',
      'puesto': 7,
    };

    test('lee una fila de la RPC nueva', () {
      final f = filasRanking([fila]).single;
      expect(f.userId, 'u1');
      expect(f.nombre, 'alguien');
      expect(f.mj, 1500.5);
      expect(f.rollos, 3);
      expect(f.jaladas, 2);
      expect(f.puesto, 7);
      expect(f.movimiento, 'mov_flotar');
      expect(f.yo, isFalse);
      expect(f.mapa['avatar'], '💩');
    });

    test('la RPC vieja: sin puesto, sin jaladas, números como int', () {
      final filas = filasRanking([
        {'user_id': 'a', 'username': 'a', 'mj_total': 10, 'rollos': null, 'yo': true},
        {'user_id': 'b', 'username': 'b', 'mj_total': 5, 'rollos': 4},
      ]);
      expect(filas.map((f) => f.puesto), [1, 2]);
      expect(filas.first.mj, 10.0);
      expect(filas.first.rollos, 0);
      expect(filas.first.jaladas, 0);
      expect(filas.first.yo, isTrue);
      expect(filas.first.movimiento, isNull);
    });

    test('orden local por rollos renumera', () {
      final filas = filasRanking([
        {'user_id': 'a', 'mj_total': 100, 'rollos': 1, 'puesto': 1},
        {'user_id': 'b', 'mj_total': 50, 'rollos': 5, 'puesto': 2},
        {'user_id': 'c', 'mj_total': 80, 'rollos': 1, 'puesto': 3},
      ], ordenLocal: 'rollos');
      expect(filas.map((f) => f.userId), ['b', 'a', 'c']);
      expect(filas.map((f) => f.puesto), [1, 2, 3]);
    });

    test('respuesta rara no rompe', () {
      expect(filasRanking(null), isEmpty);
      expect(filasRanking('x'), isEmpty);
      expect(filasRanking([1, null, fila]).length, 1);
    });

    test('falta la función en el servidor', () {
      expect(faltaFuncion(const PostgrestException(message: 'no existe', code: 'PGRST202')), isTrue);
      expect(faltaFuncion(const PostgrestException(message: 'no existe', code: '42883')), isTrue);
      expect(faltaFuncion(const PostgrestException(message: 'otra cosa', code: '42501')), isFalse);
      expect(faltaFuncion(Exception('red')), isFalse);
    });
  });

  group('tarjeta del Imperio en el perfil', () {
    test('lee imperio_perfil', () {
      final d = leerImperioPerfil({'mj_total': 2e6, 'rollos': 2, 'jaladas': 1, 'mps': 12.5});
      expect(d, (mj: 2e6, rollos: 2, jaladas: 1, mps: 12.5));
    });

    test('null o nunca jugó', () {
      expect(leerImperioPerfil(null), isNull);
      expect(leerImperioPerfil([]), isNull);
      expect(leerImperioPerfil({'mj_total': 0, 'jaladas': 0, 'rollos': 0, 'mps': 0}), isNull);
    });
  });

  group('ConMovimiento', () {
    Widget app(String? mov) => MaterialApp(home: Center(child: ConMovimiento(movimiento: mov, tamano: 40, child: const SizedBox(width: 40, height: 40))));

    tearDown(() => movimientoElegido.value = 'auto');

    testWidgets('anima con completo y se suelta al salir', (t) async {
      movimientoElegido.value = 'completo';
      await t.pumpWidget(app('mov_bailar'));
      expect(t.hasRunningAnimations, isTrue);
      expect(find.byType(Transform), findsWidgets);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('con nada no hay animación ni capa', (t) async {
      movimientoElegido.value = 'nada';
      await t.pumpWidget(app('mov_bailar'));
      expect(t.hasRunningAnimations, isFalse);
      expect(find.descendant(of: find.byType(ConMovimiento), matching: find.byType(RepaintBoundary)), findsNothing);
    });

    testWidgets('cambiar el nivel en vivo para la animación', (t) async {
      movimientoElegido.value = 'completo';
      await t.pumpWidget(app('mov_girar'));
      expect(t.hasRunningAnimations, isTrue);
      movimientoElegido.value = 'simple';
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
    });
  });
}
