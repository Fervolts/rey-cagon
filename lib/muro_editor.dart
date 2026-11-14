import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloaca.dart' show nubeCloacas;
import 'emoji.dart';
import 'icono_app.dart' show mejorRachaDias;
import 'idioma.dart';
import 'main.dart';
import 'muro_dibujo.dart';
import 'tema.dart';
import 'vitrina.dart' show cagadasPropias;

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: TextoConEmojis(texto)));

/// Escribir un post: texto opcional (hasta 500) y un dibujo opcional. Devuelve true si se publicó.
class PantallaPublicar extends StatefulWidget {
  const PantallaPublicar({super.key});

  @override
  State<PantallaPublicar> createState() => _PantallaPublicarState();
}

class _PantallaPublicarState extends State<PantallaPublicar> {
  final _texto = TextEditingController();
  Dibujo? _dibujo;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _texto.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  bool get _listo => !_enviando && (_texto.text.trim().isNotEmpty || _dibujo != null);

  Future<void> _dibujar() async {
    final d = await abrirEditorDibujo(context, inicial: _dibujo);
    if (d != null && mounted) setState(() => _dibujo = d);
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      final texto = _texto.text.trim();
      await db.from('muro').insert({'texto': texto.isEmpty ? null : texto, 'dibujo': _dibujo?.aJson()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso(context, textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('PUBLICAR', 'POST')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(key: const Key('muro_enviar'), onPressed: _listo ? _enviar : null, child: Text(tr('PUBLICAR', 'POST'))),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _texto,
          maxLength: 500,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(hintText: tr('¿Qué hay en la pared hoy?', "What's on the wall today?")),
        ),
        const SizedBox(height: 8),
        if (_dibujo != null) ...[
          VistaDibujo(_dibujo!),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _dibujar, child: Text(tr('EDITAR DIBUJO', 'EDIT DRAWING')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _dibujo = null), child: Text(tr('QUITAR', 'REMOVE')))),
          ]),
        ] else
          OutlinedButton.icon(
            key: const Key('muro_dibujar'),
            onPressed: _dibujar,
            icon: const Emoji('🎨', tamano: 20),
            label: Text(tr('DIBUJAR', 'DRAW')),
          ),
        const SizedBox(height: 12),
        Text(tr('Links, teléfonos y correos no entran.', "Links, phone numbers and emails don't get in."), style: TextStyle(color: p.textoSuave, fontSize: 12)),
      ]),
    );
  }
}

/// Abre el editor. Devuelve el dibujo al tocar LISTO, o null si se cierra.
Future<Dibujo?> abrirEditorDibujo(BuildContext context, {Dibujo? inicial}) =>
    Navigator.push<Dibujo>(context, MaterialPageRoute(builder: (_) => EditorDibujo(inicial: inicial)));

/// Paquetes de colores que se ganan. Solo se esconden en la app: el servidor acepta cualquier "rrggbb".
typedef PaquetesColor = ({bool oro, bool cloaca});

/// Se puede cambiar en las pruebas.
Future<PaquetesColor> Function() cargarPaquetesColor = _paquetesDeLaNube;

Future<PaquetesColor> _paquetesDeLaNube() async {
  var oro = false, cloaca = false;
  try {
    final uid = db.auth.currentUser?.id;
    if (uid != null) oro = mejorRachaDias((await cagadasPropias(uid)).map((c) => c.cuando)) >= 30;
  } catch (_) {}
  try {
    final puesto = (await nubeCloacas.mia()).cloaca?.puesto;
    cloaca = puesto != null && puesto <= 10;
  } catch (_) {}
  return (oro: oro, cloaca: cloaca);
}

class _Paquete {
  const _Paquete(this.es, this.en, this.colores, {this.gana});

  final String es, en;
  final List<int> colores;

  /// Si se gana: cuál de [PaquetesColor] lo abre y cómo se gana.
  final ({bool Function(PaquetesColor) abierto, String es, String en})? gana;
}

final _paquetes = <_Paquete>[
  _Paquete('BÁSICA', 'BASIC', [for (final c in coloresPaint) rgbDe(c)]),
  const _Paquete('CAFÉS', 'BROWNS', [
    0xF3E3C7, 0xE6C79C, 0xD9A77A, 0xC08552, 0xA0673A, 0x8D5524, 0x7A4A1F, 0x653A17, 0x4A2A10, 0x3A2008, 0x2A1705, 0xC9B458, //
  ]),
  const _Paquete('NEÓN', 'NEON', [
    0xFF2BD6, 0xFF3B3B, 0xFF8A00, 0xFFF200, 0x7CFF00, 0x00FFB2, 0x00E5FF, 0x2979FF, 0x7C4DFF, 0xB300FF, 0x0A0A0A, 0xFFFFFF, //
  ]),
  const _Paquete('PASTEL', 'PASTEL', [
    0xFFD1DC, 0xFFB3BA, 0xFFDFBA, 0xFFFFBA, 0xBAFFC9, 0xBAE1FF, 0xC9C9FF, 0xE0BBE4, 0xD4F0F0, 0xFCE1E4, 0xE8DFF5, 0xF1F0E8, //
  ]),
  _Paquete('ORO', 'GOLD', [0xFFF3B0, 0xFFD60A, 0xE0A800, 0xB38F00, 0x7A5C00],
      gana: (abierto: (p) => p.oro, es: 'Se gana con racha de 30 días', en: 'Earned with a 30-day streak')),
  _Paquete('CLOACA', 'SEWER', [0x3B4A3A, 0x5B7052, 0x8C9A5A, 0x2E3B2E, 0x1B241B],
      gana: (abierto: (p) => p.cloaca, es: 'Tu cloaca en el top 10 de la liga', en: 'Your sewer in the league top 10')),
];

const _recientesDeFabrica = [0xE53935, 0xFFD60A, 0x2196F3, 0x2E9D5A, 0xEC4F9C, 0xFFFFFF, 0x000000, 0x8D5524];
const _claveRecientes = 'muro_colores';

/// Qué hace el dedo en el lienzo. Los cinco primeros dejan un trazo con su [Herramienta].
enum _Util { pincel, plumon, spray, borrador, balde, gotero, sello }

/// Un paso que se puede deshacer: un trazo nuevo o un cambio de fondo.
class _Paso {
  _Paso.trazo(Trazo this.trazo) : antes = 0, despues = 0;
  _Paso.fondo(this.antes, this.despues) : trazo = null;

  final Trazo? trazo;
  final int antes, despues;
}

/// Editor del dibujo: pincel, plumón, spray, borrador, balde, cuentagotas y sello, con deshacer y rehacer.
class EditorDibujo extends StatefulWidget {
  const EditorDibujo({super.key, this.inicial});

  final Dibujo? inicial;

  @override
  State<EditorDibujo> createState() => _EditorDibujoState();
}

class _EditorDibujoState extends State<EditorDibujo> {
  // Copia: los trazos se comparten (no se tocan), la lista y el fondo no.
  late final Dibujo _d = Dibujo(fondo: widget.inicial?.fondo ?? 0xFFFFFF, trazos: [...?widget.inicial?.trazos]);
  final _hechos = <_Paso>[], _deshechos = <_Paso>[];
  var _version = 0;
  var _util = _Util.pincel, _previa = _Util.pincel;
  var _g = 3, _color = 0x000000;
  var _recientes = [..._recientesDeFabrica];
  Trazo? _actual;
  Future<PaquetesColor>? _ganados;

  @override
  void initState() {
    super.initState();
    _hechos.addAll(_d.trazos.map(_Paso.trazo));
    _leerRecientes();
  }

  Future<void> _leerRecientes() async {
    try {
      final guardados = (await SharedPreferences.getInstance()).getStringList(_claveRecientes);
      final r = [for (final h in guardados ?? const <String>[]) if (RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) int.parse(h, radix: 16)];
      if (r.isNotEmpty && mounted) setState(() => _recientes = r.take(8).toList());
    } catch (_) {}
  }

  void _usar(int c) {
    if (_recientes.firstOrNull == c) return;
    _recientes = [c, ..._recientes.where((x) => x != c)].take(8).toList();
    final guardar = [for (final r in _recientes) aHex(r)];
    unawaited(SharedPreferences.getInstance().then((p) => p.setStringList(_claveRecientes, guardar)).catchError((_) => true));
  }

  bool get _lleno => _d.trazos.length >= maxTrazos || _d.numeros + 2 > maxNumerosTotal;
  double get _uso => _d.numeros / maxNumerosTotal;

  void _hacer(_Paso p) {
    _hechos.add(p);
    _deshechos.clear();
  }

  void _aplicar(_Paso p, {required bool rehacer}) {
    final t = p.trazo;
    if (t == null) {
      _d.fondo = rehacer ? p.despues : p.antes;
    } else if (rehacer) {
      _d.trazos.add(t);
    } else {
      _d.trazos.remove(t);
    }
    (rehacer ? _hechos : _deshechos).add(p);
    setState(() => _version++);
  }

  void _deshacer() => _aplicar(_hechos.removeLast(), rehacer: false);
  void _rehacer() => _aplicar(_deshechos.removeLast(), rehacer: true);

  (int, int) _punto(Offset o, double lado) =>
      ((o.dx / lado * ladoDibujo).round().clamp(0, ladoDibujo), (o.dy / lado * ladoDibujo).round().clamp(0, ladoDibujo));

  void _abajo(Offset o, double lado) {
    final (x, y) = _punto(o, lado);
    switch (_util) {
      case _Util.gotero:
        setState(() {
          _color = colorEn(_d, x, y);
          _util = _previa;
        });
      case _Util.balde:
        if (_d.fondo == _color) return;
        _hacer(_Paso.fondo(_d.fondo, _color));
        _d.fondo = _color;
        _usar(_color);
        setState(() => _version++);
      default:
        if (_lleno) return;
        final h = Herramienta.values.byName(_util.name);
        final t = Trazo(_color, _g, h: h, p: [x, y]);
        _d.trazos.add(t);
        _hacer(_Paso.trazo(t));
        if (h != Herramienta.borrador) _usar(_color);
        _actual = h == Herramienta.sello ? null : t;
        setState(() => _version++);
    }
  }

  void _seguir(Offset o, double lado) {
    final t = _actual;
    if (t == null || t.p.length + 2 > maxNumerosPorTrazo || _d.numeros + 2 > maxNumerosTotal) return;
    final (x, y) = _punto(o, lado);
    final dx = x - t.p[t.p.length - 2], dy = y - t.p[t.p.length - 1];
    final paso = t.h == Herramienta.spray ? math.max(3.0, t.ancho / 2) : 3.0;
    if (dx * dx + dy * dy < paso * paso) return;
    t.p.addAll([x, y]);
    setState(() => _version++);
  }

  Future<void> _limpiar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(tr('¿Borrar todo el dibujo?', 'Clear the whole drawing?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('CANCELAR', 'CANCEL'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('BORRAR', 'CLEAR'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _d.trazos.clear();
    _d.fondo = 0xFFFFFF;
    _hechos.clear();
    _deshechos.clear();
    setState(() => _version++);
  }

  void _elegirUtil(_Util u) => setState(() {
        if (u == _Util.gotero && _util != _Util.gotero) _previa = _util;
        _util = u;
      });

  Future<void> _abrirColores() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _HojaColor(
          color: _color,
          recientes: _recientes,
          ganados: _ganados ??= cargarPaquetesColor(),
          alElegir: (c) => setState(() => _color = c),
          alGotero: () => _elegirUtil(_Util.gotero),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final aviso = _lleno
        ? tr('Se acabó la tinta: deshaz algo para seguir.', 'Out of ink: undo something to keep going.')
        : _uso >= 0.7 || _d.trazos.length >= 320
            ? tr('Tinta usada: ${(_uso * 100).round()}%', 'Ink used: ${(_uso * 100).round()}%')
            : null;
    const iconos = {
      _Util.pincel: Icon(Icons.brush),
      _Util.plumon: Icon(Icons.edit),
      _Util.spray: Icon(Icons.grain),
      _Util.borrador: Icon(Icons.auto_fix_normal),
      _Util.balde: Icon(Icons.format_color_fill),
      _Util.gotero: Emoji('💧', tamano: 22),
      _Util.sello: Emoji('💩', tamano: 22),
    };
    final nombres = {
      _Util.pincel: tr('Pincel', 'Brush'),
      _Util.plumon: tr('Plumón', 'Marker'),
      _Util.spray: 'Spray',
      _Util.borrador: tr('Borrador', 'Eraser'),
      _Util.balde: tr('Balde', 'Fill'),
      _Util.gotero: tr('Cuentagotas', 'Eyedropper'),
      _Util.sello: tr('Sello', 'Stamp'),
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: tr('Cerrar', 'Close'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(tr('DIBUJAR', 'DRAW')),
        actions: [
          IconButton(tooltip: tr('Deshacer', 'Undo'), icon: const Icon(Icons.undo), onPressed: _hechos.isEmpty ? null : _deshacer),
          IconButton(tooltip: tr('Rehacer', 'Redo'), icon: const Icon(Icons.redo), onPressed: _deshechos.isEmpty ? null : _rehacer),
          IconButton(tooltip: tr('Borrar todo', 'Clear all'), icon: const Icon(Icons.delete_outline), onPressed: _d.trazos.isEmpty ? null : _limpiar),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('dibujo_listo'),
              onPressed: _d.trazos.isEmpty ? null : () => Navigator.pop(context, _d),
              child: Text(tr('LISTO', 'DONE')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final lado = math.min(c.maxWidth, c.maxHeight);
                return Center(
                  child: Container(
                    key: const Key('lienzo'),
                    width: lado,
                    height: lado,
                    decoration: BoxDecoration(border: Border.all(color: p.bordeFuerte)),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (d) => _abajo(d.localPosition, lado),
                      onPanUpdate: (d) => _seguir(d.localPosition, lado),
                      onPanEnd: (_) => _actual = null,
                      onPanCancel: () => _actual = null,
                      child: RepaintBoundary(child: CustomPaint(painter: PintorDibujo(_d, version: _version), size: Size.square(lado))),
                    ),
                  ),
                );
              }),
            ),
            if (aviso != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(aviso, style: TextStyle(color: p.textoSuave, fontSize: 12))),
            const SizedBox(height: 8),
            Row(children: [
              for (final u in _Util.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _Boton(key: Key('util_${u.name}'), tooltip: nombres[u], activo: _util == u, onTap: () => _elegirUtil(u), child: iconos[u]!),
                  ),
                ),
            ]),
            Row(children: [
              Container(width: 6, height: 6, color: p.texto),
              Expanded(
                child: Slider(
                  key: const Key('dibujo_tamano'),
                  value: _g.toDouble(),
                  min: 1,
                  max: grosores.length.toDouble(),
                  divisions: grosores.length - 1,
                  onChanged: (v) => setState(() => _g = v.round()),
                ),
              ),
              Container(width: 22, height: 22, color: p.texto),
            ]),
            Row(children: [
              GestureDetector(
                key: const Key('color_actual'),
                onTap: _abrirColores,
                child: Container(
                  width: 96,
                  height: 52,
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: colorDe(_color), border: Border.all(color: p.bordeFuerte, width: 2)),
                  child: Text('#${aHex(_color)}', style: TextStyle(color: _contraste(_color), fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _Muestras(_recientes, clave: 'reciente', alTocar: (c) => setState(() => _color = c))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Emoji('💧', tamano: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(tr('= cuentagotas: tocas el dibujo y agarras ese color.', '= eyedropper: tap the drawing and grab that color.'),
                    style: TextStyle(color: p.textoSuave, fontSize: 12)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

Color _contraste(int rgb) => colorDe(rgb).computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// Fila de cuadritos de color (los recientes).
class _Muestras extends StatelessWidget {
  const _Muestras(this.colores, {required this.clave, required this.alTocar});

  final List<int> colores;
  final String clave;
  final ValueChanged<int> alTocar;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 8; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: i >= colores.length
                  ? const SizedBox()
                  : GestureDetector(
                      key: Key('$clave$i'),
                      onTap: () => alTocar(colores[i]),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(decoration: BoxDecoration(color: colorDe(colores[i]), border: Border.all(color: paleta(context).borde))),
                      ),
                    ),
            ),
          ),
      ]);
}

/// Hoja de colores: LIBRE (cuadro, tono y hex) y los paquetes; los que se ganan salen con candado hasta ganarlos.
class _HojaColor extends StatefulWidget {
  const _HojaColor({required this.color, required this.recientes, required this.ganados, required this.alElegir, required this.alGotero});

  final int color;
  final List<int> recientes;
  final Future<PaquetesColor> ganados;
  final ValueChanged<int> alElegir;
  final VoidCallback alGotero;

  @override
  State<_HojaColor> createState() => _HojaColorState();
}

class _HojaColorState extends State<_HojaColor> {
  late var _hsv = HSVColor.fromColor(colorDe(widget.color));
  late final _hex = TextEditingController(text: aHex(widget.color));
  var _pestana = 0; // 0 = LIBRE, luego los de [_paquetes].
  PaquetesColor? _abiertos;

  @override
  void initState() {
    super.initState();
    widget.ganados.then((g) {
      if (mounted) setState(() => _abiertos = g);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  int get _rgb => rgbDe(_hsv.toColor());

  void _libre(HSVColor h) {
    setState(() => _hsv = h);
    _hex.text = aHex(_rgb);
    widget.alElegir(_rgb);
  }

  void _elegirYCerrar(int c) {
    widget.alElegir(c);
    Navigator.pop(context);
  }

  bool _abierto(_Paquete q) => q.gana == null || (_abiertos != null && q.gana!.abierto(_abiertos!));

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final rotulo = TextStyle(color: p.textoSuave, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1);
    return Container(
      decoration: BoxDecoration(color: p.tarjeta, border: Border(top: BorderSide(color: p.acento, width: 3))),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i <= _paquetes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _Boton(
                      activo: _pestana == i,
                      onTap: () => setState(() => _pestana = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (i > 0 && !_abierto(_paquetes[i - 1])) const Padding(padding: EdgeInsets.only(right: 4), child: Emoji('🔒', tamano: 14)),
                          Text(i == 0 ? tr('LIBRE', 'FREE') : tr(_paquetes[i - 1].es, _paquetes[i - 1].en)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (_pestana == 0) ..._libreVista(p) else _paqueteVista(_paquetes[_pestana - 1], p),
            const SizedBox(height: 12),
            Text(tr('RECIENTES', 'RECENT'), style: rotulo),
            const SizedBox(height: 4),
            _Muestras(widget.recientes, clave: 'hoja_reciente', alTocar: _elegirYCerrar),
          ]),
        ),
      ),
    );
  }

  List<Widget> _libreVista(Paleta p) => [
        LayoutBuilder(builder: (context, c) {
          const alto = 170.0;
          final ancho = c.maxWidth;
          void tocar(Offset o) => _libre(_hsv.withSaturation((o.dx / ancho).clamp(0.0, 1.0)).withValue(1 - (o.dy / alto).clamp(0.0, 1.0)));
          return GestureDetector(
            onPanDown: (d) => tocar(d.localPosition),
            onPanUpdate: (d) => tocar(d.localPosition),
            child: SizedBox(
              width: ancho,
              height: alto,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor())),
                const Positioned.fill(
                  child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, Color(0x00FFFFFF)]))),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Colors.black]),
                    ),
                  ),
                ),
                Positioned(
                  left: _hsv.saturation * ancho - 7,
                  top: (1 - _hsv.value) * alto - 7,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(border: Border.all(color: _contraste(_rgb), width: 2)),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          void tocar(Offset o) => _libre(_hsv.withHue((o.dx / c.maxWidth).clamp(0.0, 1.0) * 359.9));
          return GestureDetector(
            onPanDown: (d) => tocar(d.localPosition),
            onPanUpdate: (d) => tocar(d.localPosition),
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                border: Border.all(color: p.borde),
                gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor()]),
              ),
              alignment: Alignment((_hsv.hue / 180) - 1, 0),
              child: Container(width: 6, color: Colors.white, foregroundDecoration: BoxDecoration(border: Border.all(color: Colors.black))),
            ),
          );
        }),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('hoja_hex'),
              controller: _hex,
              maxLength: 7,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 30, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(prefixText: '#', counterText: ''),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]'))],
              onChanged: (t) {
                final h = t.replaceAll('#', '').toLowerCase();
                if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(h)) return;
                final c = int.parse(h, radix: 16);
                setState(() => _hsv = HSVColor.fromColor(colorDe(c)));
                widget.alElegir(c);
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 52, height: 52, decoration: BoxDecoration(color: _hsv.toColor(), border: Border.all(color: p.bordeFuerte, width: 2))),
          const SizedBox(width: 8),
          _Boton(
            key: const Key('hoja_gotero'),
            tooltip: tr('Cuentagotas', 'Eyedropper'),
            ancho: 52,
            activo: false,
            onTap: () {
              Navigator.pop(context);
              widget.alGotero();
            },
            child: const Emoji('💧', tamano: 24),
          ),
        ]),
      ];

  Widget _paqueteVista(_Paquete q, Paleta p) {
    final gana = q.gana;
    if (gana != null && !_abierto(q)) {
      return CustomPaint(
        painter: _Rayado(p.bordeFuerte),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            const Emoji('🔒', tamano: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(q.es, q.en), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(_abiertos == null ? '…' : tr(gana.es, gana.en), style: TextStyle(color: p.textoSuave)),
              ]),
            ),
          ]),
        ),
      );
    }
    final basica = identical(q, _paquetes.first);
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < q.colores.length; i++)
          GestureDetector(
            key: basica ? Key('color$i') : null,
            onTap: () => _elegirYCerrar(q.colores[i]),
            child: DecoratedBox(decoration: BoxDecoration(color: colorDe(q.colores[i]), border: Border.all(color: p.borde))),
          ),
      ],
    );
  }
}

/// Borde de rayitas para los paquetes con candado.
class _Rayado extends CustomPainter {
  const _Rayado(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const raya = 6.0, hueco = 4.0;
    void linea(Offset a, Offset b) {
      final largo = (b - a).distance, dir = (b - a) / largo;
      for (var d = 0.0; d < largo; d += raya + hueco) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + raya, largo), pincel);
      }
    }

    final r = Offset.zero & size;
    linea(r.topLeft, r.topRight);
    linea(r.topRight, r.bottomRight);
    linea(r.bottomRight, r.bottomLeft);
    linea(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_Rayado viejo) => viejo.color != color;
}

/// Botón cuadrado de 44 de alto; el activo va en amarillo.
class _Boton extends StatelessWidget {
  const _Boton({super.key, required this.activo, required this.onTap, required this.child, this.ancho, this.tooltip});

  final bool activo;
  final VoidCallback onTap;
  final Widget child;
  final double? ancho;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final tinta = activo ? p.acentoTexto : p.texto;
    final boton = Material(
      color: activo ? p.acento : p.tarjeta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: activo ? p.acento : p.borde)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IconTheme(
          data: IconThemeData(color: tinta, size: 22),
          child: DefaultTextStyle(
            style: TextStyle(color: tinta, fontWeight: FontWeight.w700, fontSize: 12),
            child: SizedBox(width: ancho, height: 44, child: Center(widthFactor: 1, child: child)),
          ),
        ),
      ),
    );
    return tooltip == null ? boton : Tooltip(message: tooltip, child: boton);
  }
}
