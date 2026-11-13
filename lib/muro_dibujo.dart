import 'package:flutter/material.dart';

import 'idioma.dart';
import 'tema.dart';

// Topes del dibujo. Iguales a public.dibujo_invalido() en supabase/migrations/20261114120000_muro.sql:
// si se cambia uno, se cambia allá también.
const maxTrazos = 400;
const maxNumerosPorTrazo = 4000;
const maxNumerosTotal = 30000;
const ladoDibujo = 1000;

/// Los 16 colores del Paint de siempre: fila de arriba oscuros, fila de abajo claros.
const coloresPaint = <Color>[
  Color(0xFF000000), Color(0xFF808080), Color(0xFF800000), Color(0xFF808000),
  Color(0xFF008000), Color(0xFF008080), Color(0xFF000080), Color(0xFF800080),
  Color(0xFFFFFFFF), Color(0xFFC0C0C0), Color(0xFFFF0000), Color(0xFFFFFF00),
  Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
];

/// Grosor de cada pincel (1 a 4) en unidades del lienzo de 1000.
const grosores = <double>[4, 10, 22, 44];

class Trazo {
  Trazo(this.c, this.g, [List<int>? p]) : p = p ?? [];

  int c;
  final int g;

  /// x, y, x, y… en 0..1000.
  final List<int> p;

  Map<String, dynamic> aJson() => {'c': c, 'g': g, 'p': p};
}

class Dibujo {
  Dibujo({this.fondo = 8, List<Trazo>? trazos}) : trazos = trazos ?? [];

  int fondo;
  final List<Trazo> trazos;

  int get numeros => trazos.fold(0, (s, t) => s + t.p.length);

  Map<String, dynamic> aJson() => {'v': 1, 'fondo': fondo, 'trazos': [for (final t in trazos) t.aJson()]};

  /// Lee lo que viene de la base. Null si no cumple las reglas (así un dato raro no rompe el feed).
  static Dibujo? deJson(Object? j) {
    if (dibujoInvalido(j) != null) return null;
    final m = j as Map;
    return Dibujo(
      fondo: m['fondo'] as int,
      trazos: [for (final t in m['trazos'] as List) Trazo(t['c'] as int, t['g'] as int, [for (final n in t['p'] as List) n as int])],
    );
  }
}

/// Lo mismo que public.dibujo_invalido(): el motivo, o null si está bien.
String? dibujoInvalido(Object? d) {
  bool entero(Object? x, int max, [int min = 0]) => x is int && x >= min && x <= max;
  if (d is! Map) return 'no es un objeto';
  final claves = d.keys.map((k) => '$k').toList()..sort();
  if (claves.join(',') != 'fondo,trazos,v') return 'claves de más o de menos';
  if (d['v'] != 1) return 'versión desconocida';
  if (!entero(d['fondo'], 15)) return 'fondo fuera de rango';
  final trazos = d['trazos'];
  if (trazos is! List) return 'trazos no es una lista';
  if (trazos.isEmpty || trazos.length > maxTrazos) return 'entre 1 y $maxTrazos trazos';
  var total = 0;
  for (final t in trazos) {
    if (t is! Map) return 'trazo que no es objeto';
    final ct = t.keys.map((k) => '$k').toList()..sort();
    if (ct.join(',') != 'c,g,p') return 'trazo con claves de más o de menos';
    if (!entero(t['c'], 15)) return 'color fuera de rango';
    if (!entero(t['g'], 4, 1)) return 'grosor fuera de rango';
    final p = t['p'];
    if (p is! List) return 'puntos no es una lista';
    if (p.length < 2 || p.length > maxNumerosPorTrazo || p.length.isOdd) return 'trazo con número de puntos inválido';
    total += p.length;
    if (total > maxNumerosTotal) return 'demasiados puntos';
    if (p.any((n) => !entero(n, ladoDibujo))) return 'coordenada fuera de rango';
  }
  return null;
}

/// Pinta un dibujo al tamaño que le den (siempre cuadrado).
class PintorDibujo extends CustomPainter {
  PintorDibujo(this.dibujo, {this.version = 0});

  final Dibujo dibujo;

  /// Sube cada vez que el dibujo cambia por dentro (el editor lo muta en el sitio).
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / ladoDibujo;
    canvas.drawRect(Offset.zero & size, Paint()..color = coloresPaint[dibujo.fondo]);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final t in dibujo.trazos) {
      final pincel = Paint()
        ..color = coloresPaint[t.c]
        ..strokeWidth = grosores[t.g - 1] * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (t.p.length == 2) {
        canvas.drawCircle(Offset(t.p[0] * k, t.p[1] * k), pincel.strokeWidth / 2, pincel..style = PaintingStyle.fill);
        continue;
      }
      final camino = Path()..moveTo(t.p[0] * k, t.p[1] * k);
      for (var i = 2; i + 1 < t.p.length; i += 2) {
        camino.lineTo(t.p[i] * k, t.p[i + 1] * k);
      }
      canvas.drawPath(camino, pincel);
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
          child: CustomPaint(painter: PintorDibujo(dibujo)),
        ),
      );
}

/// Abre el editor tipo Paint. Devuelve el dibujo, o null si se cancela.
Future<Dibujo?> abrirEditorDibujo(BuildContext context, {Dibujo? inicial}) =>
    Navigator.push<Dibujo>(context, MaterialPageRoute(builder: (_) => EditorDibujo(inicial: inicial)));

enum _Herramienta { pincel, borrador, fondo }

class EditorDibujo extends StatefulWidget {
  const EditorDibujo({super.key, this.inicial});

  final Dibujo? inicial;

  @override
  State<EditorDibujo> createState() => _EditorDibujoState();
}

class _EditorDibujoState extends State<EditorDibujo> {
  late final Dibujo _d;

  /// Trazos del borrador: cambian con el fondo.
  final _borrador = <Trazo>{};
  var _version = 0;
  var _color = 0;
  var _grosor = 2;
  var _herramienta = _Herramienta.pincel;
  Trazo? _actual;

  @override
  void initState() {
    super.initState();
    final i = widget.inicial;
    _d = i == null ? Dibujo() : Dibujo(fondo: i.fondo, trazos: [for (final t in i.trazos) Trazo(t.c, t.g, [...t.p])]);
  }

  double get _uso => _d.numeros / maxNumerosTotal;
  bool get _lleno => _d.trazos.length >= maxTrazos || _d.numeros + 2 > maxNumerosTotal;

  (int, int) _punto(Offset local, double lado) {
    int c(double v) => (v / lado * ladoDibujo).round().clamp(0, ladoDibujo);
    return (c(local.dx), c(local.dy));
  }

  void _empezar(Offset local, double lado) {
    if (_herramienta == _Herramienta.fondo || _lleno) return;
    final (x, y) = _punto(local, lado);
    final borra = _herramienta == _Herramienta.borrador;
    final t = Trazo(borra ? _d.fondo : _color, _grosor, [x, y]);
    if (borra) _borrador.add(t);
    setState(() {
      _d.trazos.add(t);
      _actual = t;
      _version++;
    });
  }

  void _seguir(Offset local, double lado) {
    final t = _actual;
    if (t == null) return;
    // Pasado el tope el trazo se queda como está: el servidor no aceptaría más.
    if (t.p.length + 2 > maxNumerosPorTrazo || _d.numeros + 2 > maxNumerosTotal) return;
    final (x, y) = _punto(local, lado);
    final dx = x - t.p[t.p.length - 2], dy = y - t.p[t.p.length - 1];
    if (dx * dx + dy * dy < 9) return; // menos de 3 unidades: no gasta puntos
    setState(() {
      t.p.addAll([x, y]);
      _version++;
    });
  }

  void _cambiarFondo(int c) => setState(() {
        _d.fondo = c;
        for (final t in _borrador) {
          t.c = c;
        }
        _version++;
      });

  void _deshacer() {
    if (_d.trazos.isEmpty) return;
    setState(() {
      _borrador.remove(_d.trazos.removeLast());
      _version++;
    });
  }

  Future<void> _limpiar() async {
    if (_d.trazos.isEmpty) return;
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Borrar todo el dibujo?', 'Clear the whole drawing?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCELAR', 'CANCEL'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('BORRAR', 'CLEAR'))),
        ],
      ),
    );
    if (si != true || !mounted) return;
    setState(() {
      _d.trazos.clear();
      _borrador.clear();
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('DIBUJAR', 'DRAW')),
        actions: [
          IconButton(tooltip: tr('Deshacer', 'Undo'), onPressed: _d.trazos.isEmpty ? null : _deshacer, icon: const Icon(Icons.undo)),
          IconButton(tooltip: tr('Borrar todo', 'Clear all'), onPressed: _d.trazos.isEmpty ? null : _limpiar, icon: const Icon(Icons.delete_outline)),
          TextButton(
            onPressed: _d.trazos.isEmpty ? null : () => Navigator.pop(context, _d),
            child: Text(tr('LISTO', 'DONE')),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          // Sin scroll: arrastrar en el lienzo siempre pinta, nunca mueve la pantalla.
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final lado = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
                return Center(
                  child: Container(
                    key: const Key('lienzo'),
                    width: lado,
                    height: lado,
                    decoration: BoxDecoration(border: Border.all(color: p.bordeFuerte)),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (e) => _empezar(e.localPosition, lado),
                      onPanUpdate: (e) => _seguir(e.localPosition, lado),
                      onPanEnd: (_) => _actual = null,
                      onPanCancel: () => _actual = null,
                      child: CustomPaint(painter: PintorDibujo(_d, version: _version)),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            if (_uso >= 0.7 || _d.trazos.length >= maxTrazos * 0.8)
              Text(
                _lleno
                    ? tr('Se acabó la tinta: deshaz algo para seguir.', 'Out of ink: undo something to keep going.')
                    : tr('Tinta usada: ${(_uso * 100).round()}%', 'Ink used: ${(_uso * 100).round()}%'),
                style: TextStyle(color: _lleno ? p.texto : p.textoSuave, fontSize: 12, fontWeight: _lleno ? FontWeight.w700 : null),
              ),
            const SizedBox(height: 8),
            Row(children: [
              for (final (h, icono, es, en) in [
                (_Herramienta.pincel, Icons.brush, 'PINCEL', 'BRUSH'),
                (_Herramienta.borrador, Icons.auto_fix_normal, 'BORRADOR', 'ERASER'),
                (_Herramienta.fondo, Icons.format_color_fill, 'FONDO', 'FILL'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Boton(
                      activo: _herramienta == h,
                      onTap: () => setState(() => _herramienta = h),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(icono, size: 16),
                        const SizedBox(width: 4),
                        Flexible(child: Text(tr(es, en), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              for (var g = 1; g <= 4; g++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Boton(
                    activo: _grosor == g,
                    onTap: () => setState(() => _grosor = g),
                    ancho: 44,
                    child: Builder(builder: (c) => Container(width: 4.0 + g * 5, height: 4.0 + g * 5, color: IconTheme.of(c).color)),
                  ),
                ),
              const Spacer(),
              // Color elegido: fondo y pincel, como el cuadrito doble del Paint.
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(children: [
                  Positioned(right: 0, bottom: 0, child: _Muestra(coloresPaint[_d.fondo], 28, p.bordeFuerte)),
                  Positioned(left: 0, top: 0, child: _Muestra(coloresPaint[_color], 28, p.bordeFuerte)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            for (final fila in [0, 8])
              Row(children: [
                for (var i = fila; i < fila + 8; i++)
                  Expanded(
                    child: GestureDetector(
                      key: Key('color$i'),
                      onTap: () {
                        if (_herramienta == _Herramienta.fondo) return _cambiarFondo(i);
                        setState(() {
                          _color = i;
                          if (_herramienta == _Herramienta.borrador) _herramienta = _Herramienta.pincel;
                        });
                      },
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: coloresPaint[i],
                            border: Border.all(
                              color: (_herramienta == _Herramienta.fondo ? _d.fondo : _color) == i ? p.acento : p.bordeFuerte,
                              width: (_herramienta == _Herramienta.fondo ? _d.fondo : _color) == i ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _Muestra extends StatelessWidget {
  const _Muestra(this.color, this.lado, this.borde);

  final Color color, borde;
  final double lado;

  @override
  Widget build(BuildContext context) =>
      Container(width: lado, height: lado, decoration: BoxDecoration(color: color, border: Border.all(color: borde)));
}

class _Boton extends StatelessWidget {
  const _Boton({required this.activo, required this.onTap, required this.child, this.ancho});

  final bool activo;
  final VoidCallback onTap;
  final Widget child;
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Material(
      color: activo ? p.acento : p.tarjeta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radio),
        side: BorderSide(color: activo ? p.acento : p.bordeFuerte),
      ),
      child: InkWell(
        onTap: onTap,
        child: IconTheme(
          data: IconThemeData(color: activo ? p.acentoTexto : p.texto),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: activo ? p.acentoTexto : p.texto),
            child: SizedBox(width: ancho, height: 44, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
