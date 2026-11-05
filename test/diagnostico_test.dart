import 'package:flutter_test/flutter_test.dart';
import 'package:rey_cagon/diagnostico.dart';

void main() {
  test('liviano: Android Go o menos de 3 GB', () {
    expect(esLiviano(ramBaja: true, ramMb: 8000), isTrue);
    expect(esLiviano(ramBaja: false, ramMb: 1900), isTrue);
    expect(esLiviano(ramBaja: false, ramMb: 3800), isFalse);
    expect(esLiviano(ramBaja: false), isFalse);
    expect(esLiviano(ramBaja: false, ramMb: 0), isFalse);
  });

  test('resumirPila: arriba + las de la app, sin el número de cuadro', () {
    final pila = [
      '#0      State.setState (package:flutter/src/widgets/framework.dart:1219:9)',
      for (var i = 1; i < 30; i++) '#$i      Algo.cosa$i (package:flutter/src/x.dart:$i:1)',
      '#30     _VistaMemoria._tick (package:rey_cagon/imperio/minijuegos/memoria_vista.dart:120:7)',
    ].join('\n');
    final r = resumirPila(pila);
    expect(r.length, 7);
    expect(r.first, 'State.setState (package:flutter/src/widgets/framework.dart:1219:9)');
    expect(r.last, contains('memoria_vista.dart:120'));
    expect(resumirPila(null), isEmpty);
  });

  test('resumirPila: sin símbolos se guarda la cabecera tal cual', () {
    final pila = [
      '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***',
      "pid: 123, tid: 456, name 1.ui",
      "build_id: 'abc'",
      'isolate_dso_base: 7a00000000, vm_dso_base: 7a00000000',
      '#00 abs 0000007a9b4c3e2f virt 00000000003c3e2f _kDartIsolateSnapshotInstructions+0x2f3e2f',
    ].join('\n');
    final r = resumirPila(pila);
    expect(r.length, 5);
    expect(r[2], "build_id: 'abc'");
  });

  test('salidasNuevas: solo después de la última, la más nueva primero, con tope', () {
    final s = [for (var i = 1; i <= 8; i++) <String, Object?>{'razon': 'r$i', 'cuando': i * 1000}];
    final n = salidasNuevas(s, 2000);
    expect(n.length, 5);
    expect(n.first['cuando'], 8000);
    expect(salidasNuevas(s, 9000), isEmpty);
  });

  test('partidaCortada: cruza con la primera salida después de empezar', () {
    final partida = <String, Object?>{'juego': 'memoria', 'ms': 10000, 'foto': {'libre_mb': 120}};
    final salidas = [
      <String, Object?>{'razon': 'usuario', 'cuando': 5000},
      <String, Object?>{'razon': 'poca_memoria', 'cuando': 70000, 'pss_mb': 300},
      <String, Object?>{'razon': 'crash', 'cuando': 90000},
    ];
    final d = partidaCortada(partida, salidas, 100000);
    expect(d['juego'], 'memoria');
    expect(d['razon'], 'poca_memoria');
    expect(d['segundos'], 60);
    expect(d['pss_mb'], 300);
    expect(d['hace_s'], 90);
    final sin = partidaCortada(partida, const [], 100000);
    expect(sin.containsKey('razon'), isFalse);
  });

  test('FiltroErrores: un error por tipo y primera línea, con tope', () {
    final f = FiltroErrores(tope: 2);
    expect(f.deja('StateError', ['a']), isTrue);
    expect(f.deja('StateError', ['a']), isFalse);
    expect(f.deja('StateError', ['b']), isTrue);
    expect(f.deja('RangeError', ['c']), isFalse);
  });
}
