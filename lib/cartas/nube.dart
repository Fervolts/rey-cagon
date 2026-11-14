// Lo que la colección y las misiones piden al servidor. Todo pasa por conReintento.
import 'package:flutter/foundation.dart';

import '../main.dart' show conReintento, db;

typedef Mision = ({int id, String clave, bool rara, int meta, int progreso});
typedef Misiones = ({DateTime proximo, bool cobrada, List<Mision> lista});
typedef Sobre = ({int id, String tipo, String origen});
typedef MiCarta = ({int n, int copias, int nivel, int gastadas});
typedef EstadoCartas = ({DateTime proximo, List<Sobre> sobres, Map<int, MiCarta> cartas, List<int> ultimas});
typedef CartaAbierta = ({int n, bool nueva, int copias, int nivel});
typedef SobreAbierto = ({String tipo, List<CartaAbierta> cartas});

/// Sube cada vez que cambian los sobres (cobrar misiones, abrir, mejorar): el lado secreto se recarga.
final cartasCambiaron = ValueNotifier<int>(0);

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime _fecha(Object? v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now().add(const Duration(hours: 24));

Misiones misionesDe(Map<String, dynamic> j) => (
      proximo: _fecha(j['proximo']),
      cobrada: j['cobrada'] == true,
      lista: [
        for (final m in (j['misiones'] as List? ?? const []).cast<Map<String, dynamic>>())
          (id: _int(m['id']), clave: '${m['clave']}', rara: m['rara'] == true, meta: _int(m['meta']), progreso: _int(m['progreso'])),
      ],
    );

MiCarta _miCarta(Map<String, dynamic> c) =>
    (n: _int(c['n']), copias: _int(c['copias']), nivel: _int(c['nivel']), gastadas: _int(c['gastadas']));

EstadoCartas estadoDe(Map<String, dynamic> j) => (
      proximo: _fecha(j['proximo']),
      sobres: [
        for (final s in (j['sobres'] as List? ?? const []).cast<Map<String, dynamic>>())
          (id: _int(s['id']), tipo: '${s['tipo']}', origen: '${s['origen']}'),
      ],
      cartas: {
        for (final c in (j['cartas'] as List? ?? const []).cast<Map<String, dynamic>>()) _int(c['n']): _miCarta(c),
      },
      ultimas: [for (final n in (j['ultimas'] as List? ?? const [])) _int(n)],
    );

Future<Map<String, dynamic>> _rpc(String nombre, [Map<String, dynamic>? params]) async =>
    Map<String, dynamic>.from(await conReintento(() => db.rpc(nombre, params: params)) as Map);

/// Las 3 misiones de hoy (el servidor las sortea si faltan).
Future<Misiones> misionesHoy() async => misionesDe(await _rpc('misiones_hoy'));

/// Cobra el sobre de las misiones. Errores del servidor: no_hechas, ya_cobrada.
Future<Sobre> cobrarMisiones() async {
  final s = Map<String, dynamic>.from((await _rpc('misiones_cobrar'))['sobre'] as Map);
  cartasCambiaron.value++;
  return (id: _int(s['id']), tipo: '${s['tipo']}', origen: 'misiones');
}

/// Racha de días seguidos y cagadas de los últimos 7 días.
Future<({int racha, int semana})> tronoResumen() async {
  final j = await _rpc('trono_resumen');
  return (racha: _int(j['racha']), semana: _int(j['semana']));
}

/// Colección propia; crea el sobre del día si falta. Error sin_secreto si no encontró el lado secreto.
Future<EstadoCartas> estadoCartas() async => estadoDe(await _rpc('cartas_estado'));

/// Abre un sobre. Abrirlo otra vez devuelve lo mismo.
Future<SobreAbierto> abrirSobre(int id) async {
  final j = await _rpc('cartas_abrir', {'p_sobre': id});
  return (
    tipo: '${j['tipo']}',
    cartas: [
      for (final c in (j['cartas'] as List? ?? const []).cast<Map<String, dynamic>>())
        (n: _int(c['n']), nueva: c['nueva'] == true, copias: _int(c['copias']), nivel: _int(c['nivel'])),
    ],
  );
}

/// Sube una carta un nivel. Errores: sin_repetidas, nivel_max.
Future<MiCarta> mejorarCarta(int n) async {
  final c = _miCarta(await _rpc('cartas_mejorar', {'p_n': n}));
  cartasCambiaron.value++;
  return c;
}
