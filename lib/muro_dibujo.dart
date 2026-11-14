import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tema.dart';

// Topes del dibujo. Iguales a public.dibujo_invalido() (la última está en
// supabase/migrations/20261116120000_muro_dibujo_v2.sql): si se cambia uno, se cambia allá también.
const maxTrazos = 400;
const maxNumerosPorTrazo = 4000;
const maxNumerosTotal = 30000;
const ladoDibujo = 1000;

/// Los 16 colores del Paint de siempre. En el formato v1 el color era el índice en esta lista.
const coloresPaint = <Color>[
  Color(0xFF000000), Color(0xFF808080), Color(0xFF800000), Color(0xFF808000),
  Color(0xFF008000), Color(0xFF008080), Color(0xFF000080), Color(0xFF800080),
  Color(0xFFFFFFFF), Color(0xFFC0C0C0), Color(0xFFFF0000), Color(0xFFFFFF00),
  Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
];

/// Grosor de cada tamaño (g = 1..8) en unidades del lienzo de 1000. Los cuatro de v1 (4, 10, 22, 44) son los pares.
const grosores = <double>[2, 4, 7, 10, 15, 22, 32, 44];

/// Cómo se pinta un trazo. El nombre es el que va en el JSON (`h`), no se renombra.
enum Herramienta { pincel, plumon, spray, borrador, sello }

/// 0xRRGGBB → "rrggbb".
String aHex(int rgb) => (rgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

/// Color sin alfa (0xRRGGBB).
int rgbDe(Color c) => c.toARGB32() & 0xFFFFFF;

Color colorDe(int rgb) => Color(0xFF000000 | rgb);

class Trazo {
  Trazo(this.c, this.g, {this.h = Herramienta.pincel, List<int>? p}) : p = p ?? [];

  /// 0xRRGGBB. El borrador no lo usa: pinta del color del fondo (así el balde lo sigue).
  final int c;

  /// Tamaño 1..8 (ver [grosores]).
  final int g;
  final Herramienta h;

  /// x, y, x, y… en 0..1000. El sello lleva un solo punto.
  final List<int> p;

  // Forma ya armada en unidades del lienzo; se alarga cuando el editor agrega puntos, nunca se rehace.
  Path? _forma;
  var _hechos = 0;
  math.Random? _azar;

  double get ancho => grosores[g - 1];

  Map<String, dynamic> aJson() => {'c': aHex(c), 'g': g, 'h': h.name, 'p': p};

  Path _armar() {
    final f = _forma ??= Path();
    if (h == Herramienta.sello) {
      final s = ancho * 2 + 24;
      if (_hechos == 0) f.addPath(_caca.transform((Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(p[0] * 1.0, p[1] * 1.0, 0)).storage), Offset.zero);
    } else if (h == Herramienta.spray) {
      // Puntitos fijos: la semilla sale del primer punto, así el mismo dibujo se ve igual en todos los teléfonos.
      final azar = _azar ??= math.Random(p[0] * 1009 + p[1]);
      final r = ancho * 1.5 + 6, lado = math.max(2.0, ancho / 5);
      for (var i = _hechos; i + 1 < p.length; i += 2) {
        for (var n = 0; n < 5 + g; n++) {
          final a = azar.nextDouble() * 2 * math.pi, d = r * math.sqrt(azar.nextDouble());
          f.addRect(Rect.fromCenter(center: Offset(p[i] + d * math.cos(a), p[i + 1] + d * math.sin(a)), width: lado, height: lado));
        }
      }
    } else {
      if (_hechos == 0) f.moveTo(p[0].toDouble(), p[1].toDouble());
      for (var i = math.max(_hechos, 2); i + 1 < p.length; i += 2) {
        f.lineTo(p[i].toDouble(), p[i + 1].toDouble());
      }
    }
    _hechos = p.length;
    return f;
  }

  /// Pinta el trazo en unidades del lienzo (el lienzo ya viene escalado). [pincel] se reusa entre trazos.
  void pintar(Canvas canvas, Paint pincel, int fondo) {
    final color = colorDe(h == Herramienta.borrador ? fondo : c);
    final plumon = h == Herramienta.plumon;
    pincel
      ..color = plumon ? color.withAlpha(150) : color
      ..strokeWidth = ancho
      ..strokeCap = plumon ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = plumon ? StrokeJoin.bevel : StrokeJoin.round
      ..style = PaintingStyle.fill;
    if (p.isEmpty) return;
    final forma = _hechos == p.length ? _forma! : _armar();
    if (h == Herramienta.spray || h == Herramienta.sello) return canvas.drawPath(forma, pincel);
    if (p.length == 2) {
      final o = Offset(p[0].toDouble(), p[1].toDouble());
      return plumon ? canvas.drawRect(Rect.fromCenter(center: o, width: ancho, height: ancho), pincel) : canvas.drawCircle(o, ancho / 2, pincel);
    }
    canvas.drawPath(forma, pincel..style = PaintingStyle.stroke);
  }
}

/// La 💩 del sello: tres pisos y la punta, en una caja de 1×1 centrada en el punto.
final _caca = Path()
  ..addOval(Rect.fromCenter(center: const Offset(0, 0.3), width: 1, height: 0.38))
  ..addOval(Rect.fromCenter(center: const Offset(0, 0.04), width: 0.78, height: 0.32))
  ..addOval(Rect.fromCenter(center: const Offset(0, -0.2), width: 0.52, height: 0.28))
  ..moveTo(-0.16, -0.28)
  ..quadraticBezierTo(0.02, -0.4, 0.1, -0.5)
  ..quadraticBezierTo(0.2, -0.38, 0.18, -0.26)
  ..close();

class Dibujo {
  Dibujo({this.fondo = 0xFFFFFF, List<Trazo>? trazos}) : trazos = trazos ?? [];

  /// 0xRRGGBB.
  int fondo;
  final List<Trazo> trazos;

  int get numeros => trazos.fold(0, (s, t) => s + t.p.length);

  /// Siempre en v2. Los v1 que llegan de la base se leen igual (ver [deJson]).
  Map<String, dynamic> aJson() => {'v': 2, 'fondo': aHex(fondo), 'trazos': [for (final t in trazos) t.aJson()]};

  /// Lee lo que viene de la base (v1 o v2). Null si no cumple las reglas (así un dato raro no rompe el feed).
  static Dibujo? deJson(Object? j) {
    if (dibujoInvalido(j) != null) return null;
    final m = j as Map;
    List<int> puntos(Map t) => [for (final n in t['p'] as List) n as int];
    if (m['v'] == 1) {
      return Dibujo(
        fondo: rgbDe(coloresPaint[m['fondo'] as int]),
        trazos: [for (final t in m['trazos'] as List) Trazo(rgbDe(coloresPaint[t['c'] as int]), (t['g'] as int) * 2, p: puntos(t))],
      );
    }
    return Dibujo(
      fondo: int.parse(m['fondo'] as String, radix: 16),
      trazos: [
        for (final t in m['trazos'] as List)
          Trazo(int.parse(t['c'] as String, radix: 16), t['g'] as int, h: Herramienta.values.byName(t['h'] as String), p: puntos(t)),
      ],
    );
  }
}

final _hex = RegExp(r'^[0-9a-f]{6}$');

/// Lo mismo que public.dibujo_invalido(): el motivo, o null si está bien. Acepta v1 (colores por índice,
/// grosor 1..4) y v2 (colores "rrggbb", grosor 1..8, herramienta `h`; el sello con un solo punto).
String? dibujoInvalido(Object? d) {
  bool entero(Object? x, int max, [int min = 0]) => x is int && x >= min && x <= max;
  bool hex(Object? x) => x is String && _hex.hasMatch(x);
  if (d is! Map) return 'no es un objeto';
  final claves = d.keys.map((k) => '$k').toList()..sort();
  if (claves.join(',') != 'fondo,trazos,v') return 'claves de más o de menos';
  final v1 = d['v'] == 1;
  if (!v1 && d['v'] != 2) return 'versión desconocida';
  if (v1 ? !entero(d['fondo'], 15) : !hex(d['fondo'])) return 'fondo fuera de rango';
  final trazos = d['trazos'];
  if (trazos is! List) return 'trazos no es una lista';
  if (trazos.isEmpty || trazos.length > maxTrazos) return 'entre 1 y $maxTrazos trazos';
  var total = 0;
  for (final t in trazos) {
    if (t is! Map) return 'trazo que no es objeto';
    final ct = t.keys.map((k) => '$k').toList()..sort();
    if (ct.join(',') != (v1 ? 'c,g,p' : 'c,g,h,p')) return 'trazo con claves de más o de menos';
    if (v1 ? !entero(t['c'], 15) : !hex(t['c'])) return 'color fuera de rango';
    if (!entero(t['g'], v1 ? 4 : 8, 1)) return 'grosor fuera de rango';
    if (!v1 && !Herramienta.values.any((h) => h.name == t['h'])) return 'herramienta desconocida';
    final p = t['p'];
    if (p is! List) return 'puntos no es una lista';
    if (p.length < 2 || p.length > maxNumerosPorTrazo || p.length.isOdd || (t['h'] == 'sello' && p.length != 2)) {
      return 'trazo con número de puntos inválido';
    }
    total += p.length;
    if (total > maxNumerosTotal) return 'demasiados puntos';
    if (p.any((n) => !entero(n, ladoDibujo))) return 'coordenada fuera de rango';
  }
  return null;
}

/// Pinta un dibujo al tamaño que le den (siempre cuadrado). Cada trazo guarda su forma: pintar de nuevo no la rehace.
class PintorDibujo extends CustomPainter {
  PintorDibujo(this.dibujo, {this.version = 0});

  final Dibujo dibujo;

  /// Sube cada vez que el dibujo cambia por dentro (el editor lo muta en el sitio).
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / ladoDibujo;
    canvas.drawRect(Offset.zero & size, Paint()..color = colorDe(dibujo.fondo));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k);
    final pincel = Paint();
    for (final t in dibujo.trazos) {
      t.pintar(canvas, pincel, dibujo.fondo);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorDibujo viejo) => viejo.dibujo != dibujo || viejo.version != version;
}

/// Un dibujo ya hecho, cuadrado y a todo el ancho que le den.
class VistaDibujo extends StatelessWidget {
  const VistaDibujo(this.dibujo, {super.key});

  final Dibujo dibujo;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: paleta(context).borde)),
          child: RepaintBoundary(child: CustomPaint(painter: PintorDibujo(dibujo))),
        ),
      );
}

/// El color que se ve en (x, y) del lienzo de 1000: el del trazo de más arriba que pase por ahí, o el fondo. Para el 💧.
int colorEn(Dibujo d, int x, int y) {
  final o = Offset(x.toDouble(), y.toDouble());
  Offset punto(List<int> p, int i) => Offset(p[i].toDouble(), p[i + 1].toDouble());
  for (final t in d.trazos.reversed) {
    final p = t.p;
    if (p.isEmpty) continue;
    final cerca = switch (t.h) {
      Herramienta.sello => (punto(p, 0) - o).distance <= (t.ancho * 2 + 24) / 2,
      Herramienta.spray => [for (var i = 0; i + 1 < p.length; i += 2) punto(p, i)].any((q) => (q - o).distance <= t.ancho * 1.5 + 6),
      _ => [for (var i = 0; i + 1 < p.length; i += 2) i == 0 ? (punto(p, 0), punto(p, 0)) : (punto(p, i - 2), punto(p, i))]
          .any((s) => _distancia(o, s.$1, s.$2) <= t.ancho / 2 + 4),
    };
    if (cerca) return t.h == Herramienta.borrador ? d.fondo : t.c;
  }
  return d.fondo;
}

double _distancia(Offset o, Offset a, Offset b) {
  final ab = b - a, largo = ab.distanceSquared;
  if (largo == 0) return (o - a).distance;
  final k = (((o - a).dx * ab.dx + (o - a).dy * ab.dy) / largo).clamp(0.0, 1.0);
  return (o - (a + ab * k)).distance;
}
