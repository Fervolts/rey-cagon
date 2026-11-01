// El baño del Imperio: la escena alrededor de la poceta.
//
// Arranca destartalado (cerámica partida, mancha de humedad, bombillo pelado, periódico en un clavo, tobo con agua)
// y cada adorno arregla algo que se ve. Los edificios ponen cosas que hacen algo (frasco de ciruelas, budare, poceta
// extra) y el edificio más alto cambia el ambiente (baño público, camión por la ventana, tubos, cloaca, fase 2).
//
// [EstadoBano] es puro: sale de las mejoras y los edificios, y se compara por valor. [FondoBano] dibuja lo que no se
// mueve (un CustomPainter y unos pocos emojis quietos) y solo se repinta cuando cambia el estado, no en cada tick.
// Lo que se mueve (parpadeo, gota, café, dedos...) va en poceta.dart.

import 'dart:math';

import 'package:flutter/material.dart';

import '../emoji.dart';

/// El edificio más alto que tienes: cambia el ambiente del baño.
enum AmbienteBano { casa, publico, camion, planta, cloaca, granja, mina, templo, volcan, laxante, agujero }

/// Color de los dedos: la mejor mejora comprada.
enum ColorDedo { piel, latex, acero, oro }

/// Forma de los dedos: ambidiestros (unos al revés), dedo del pie (uno sí, uno no), mano entera.
enum FormaDedo { normal, ambidiestro, pie, mano }

const _niveles = [1, 5, 10, 25, 50, 100, 150, 200];

// Edificio que pone cada ambiente, del más alto al más bajo.
const _ambientes = [
  ('agujero', AmbienteBano.agujero),
  ('laxante_tiempo', AmbienteBano.laxante),
  ('volcan', AmbienteBano.volcan),
  ('templo', AmbienteBano.templo),
  ('mina', AmbienteBano.mina),
  ('granja', AmbienteBano.granja),
  ('cloaca', AmbienteBano.cloaca),
  ('planta', AmbienteBano.planta),
  ('camion', AmbienteBano.camion),
  ('bano', AmbienteBano.publico),
];

/// Qué hay en el baño. Puro: sin Flutter de por medio, se compara por valor.
@immutable
class EstadoBano {
  const EstadoBano({
    this.bombillo = false,
    this.papel = false,
    this.forro = false,
    this.alfombra = false,
    this.cortina = false,
    this.matica = false,
    this.ceramica = false,
    this.pintura = false,
    this.tanque = 0,
    this.valvula = 0,
    this.iman = false,
    this.brillo = false,
    this.lavanda = false,
    this.colorDedo = ColorDedo.piel,
    this.formaDedo = FormaDedo.normal,
    this.adornoDedo,
    this.ciruela = 0,
    this.ciruelaVerde = false,
    this.ciruelaNuclear = false,
    this.cafe = 0,
    this.arepa = 0,
    this.arepaBrillo = false,
    this.inodoro = 0,
    this.ambiente = AmbienteBano.casa,
  });

  /// Sale de lo comprado: [comprada] dice si una mejora está comprada y [cantidad] cuántos hay de un edificio.
  factory EstadoBano.desde({required bool Function(String id) comprada, required int Function(String id) cantidad}) {
    int nivel(String e) => _niveles.where((n) => comprada('${e}_$n')).length;
    final ciruelas = cantidad('ciruela'), nCiruela = nivel('ciruela');
    var ambiente = AmbienteBano.casa;
    for (final (id, a) in _ambientes) {
      if (cantidad(id) > 0) {
        ambiente = a;
        break;
      }
    }
    return EstadoBano(
      bombillo: comprada('adorno_bombillo'),
      papel: comprada('adorno_papel'),
      forro: comprada('adorno_forro'),
      alfombra: comprada('adorno_alfombra'),
      cortina: comprada('adorno_cortina'),
      matica: comprada('adorno_matica'),
      ceramica: comprada('adorno_ceramica'),
      pintura: comprada('adorno_pintura'),
      tanque: comprada('tanque_8') ? 2 : (comprada('tanque_4') ? 1 : 0),
      valvula: comprada('valvula_75') ? 2 : (comprada('valvula_50') ? 1 : 0),
      iman: comprada('iman'),
      brillo: comprada('brillo'),
      lavanda: comprada('lavanda'),
      colorDedo: comprada('dedo_200')
          ? ColorDedo.oro
          : (comprada('dedo_acero') || comprada('dedo_100'))
              ? ColorDedo.acero
              : (comprada('guantes') || comprada('dedo_5'))
                  ? ColorDedo.latex
                  : ColorDedo.piel,
      formaDedo: comprada('dedo_150')
          ? FormaDedo.mano
          : comprada('dedo_50')
              ? FormaDedo.pie
              : comprada('dedo_25')
                  ? FormaDedo.ambidiestro
                  : FormaDedo.normal,
      adornoDedo: comprada('dedo_200') ? '👑' : (comprada('dedo_10') ? '💍' : (comprada('faja') ? '🩲' : null)),
      ciruela: ciruelas == 0 ? 0 : 1 + (nCiruela >= 3 ? 1 : 0) + (nCiruela >= 5 ? 1 : 0),
      ciruelaVerde: comprada('ciruela_150'),
      ciruelaNuclear: comprada('ciruela_200'),
      cafe: cantidad('cafe') == 0 ? 0 : 1 + nivel('cafe'),
      arepa: cantidad('arepa') == 0 ? 0 : 1 + (comprada('arepa_10') ? 1 : 0) + (comprada('arepa_50') ? 1 : 0),
      arepaBrillo: comprada('arepa_200'),
      inodoro: cantidad('inodoro') == 0 ? 0 : (comprada('inodoro_200') ? 2 : 1),
      ambiente: ambiente,
    );
  }

  // Adornos: cada uno arregla algo.
  final bool bombillo, papel, forro, alfombra, cortina, matica, ceramica, pintura;

  /// Mejoras de la poceta: tanque (0 tobo, 1 pipote, 2 pipote grande), válvula (0 gotea, 1 cromada, 2 dorada).
  final int tanque, valvula;
  final bool iman, brillo, lavanda;

  final ColorDedo colorDedo;
  final FormaDedo formaDedo;

  /// Lo único que lleva puesto el dedo (🩲, 💍 o 👑), o nada.
  final String? adornoDedo;

  /// Ciruelas en la repisa: 0 nada, 1 unas sueltas, 2 frasco, 3 frasco grande.
  final int ciruela;
  final bool ciruelaVerde, ciruelaNuclear;

  /// Café: 0 nada; si no, 1 + mejoras compradas (el chorro engorda).
  final int cafe;

  /// Arepa: 0 nada, 1 una en el budare, 2 dos, 3 budare grande.
  final int arepa;
  final bool arepaBrillo;

  /// Poceta extra al fondo: 0 nada, 1 normal, 2 de oro.
  final int inodoro;
  final AmbienteBano ambiente;

  /// Lo que lleva la taza del chorro de café.
  String get objetoCafe => cafe >= 7 ? '💉' : (cafe >= 6 ? '🫖' : '☕');

  Object get _clave => (
        bombillo, papel, forro, alfombra, cortina, matica, ceramica, pintura, tanque, valvula, iman, brillo, lavanda,
        colorDedo, formaDedo, adornoDedo, ciruela, ciruelaVerde, ciruelaNuclear, cafe, arepa, arepaBrillo, inodoro, ambiente,
      );

  @override
  bool operator ==(Object other) => other is EstadoBano && other._clave == _clave;

  @override
  int get hashCode => _clave.hashCode;
}

/// Medidas de la escena. Las x son relativas al centro (cx); las y, absolutas desde arriba.
abstract final class Bano {
  static const alto = 280.0;
  static const piso = 192.0; // donde la pared se junta con el piso
  static const banda = 60.0; // pintura arriba, cerámica abajo
  static const azulejo = 22.0;
  static const ventana = Rect.fromLTRB(40, 12, 118, 62);
  static const lavamanos = -145.0; // centro del lavamanos
  static const grifo = Offset(-137, 110); // donde gotea
  static const repisa = Rect.fromLTRB(-112, 72, -62, 76);
  static const frasco = Offset(-87, 54);
  static const bombillo = Offset(-28, 34);
  static const papel = Offset(74, 140);
  static const tobo = Offset(88, 236);
  static const matica = Offset(160, 246);
  static const inodoro = Offset(108, 162);
  static const letrero = Offset(108, 100);
  static const budare = Offset(-128, 258);
  static const rejilla = Offset(-58, 266);
  static const lavanda = Offset(-122, 104);
  static const destellos = [Offset(-130, 42), Offset(26, 72), Offset(-62, 182)];
}

/// Lo quieto de la escena: el fondo pintado y los emojis que no se mueven. Ponerlo dentro de un RepaintBoundary.
class FondoBano extends StatelessWidget {
  const FondoBano({super.key, required this.estado});

  final EstadoBano estado;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final cx = caja.maxWidth / 2;
      final e = estado;
      Widget en(Offset o, double tam, Widget hijo) => Positioned(left: cx + o.dx - tam / 2, top: o.dy - tam / 2, width: tam, height: tam, child: hijo);
      final v = Bano.ventana.shift(Offset(cx, 0)).deflate(3);
      final hijos = <Widget>[
        Positioned.fill(child: CustomPaint(painter: PintorBano(e), isComplex: true, willChange: false)),
        // Lo que se ve por la ventana.
        if (e.ambiente == AmbienteBano.camion)
          Positioned.fromRect(rect: v, child: const ClipRect(child: Align(alignment: Alignment(.2, 1.6), child: Emoji('🚛', tamano: 44)))),
        if (e.ambiente == AmbienteBano.volcan)
          Positioned.fromRect(rect: v, child: const ClipRect(child: Align(alignment: Alignment(0, 1.4), child: Emoji('🌋', tamano: 44)))),
        if (e.ambiente == AmbienteBano.agujero)
          Positioned.fromRect(rect: v, child: const ClipRect(child: Align(alignment: Alignment(.3, 0), child: Emoji('🌌', tamano: 40)))),
        if (!e.bombillo) en(Bano.bombillo, 24, const RotatedBox(quarterTurns: 2, child: Emoji('💡', tamano: 24))),
        if (e.papel) en(Bano.papel, 24, const Emoji('🧻', tamano: 24)),
        if (e.tanque == 0) en(Bano.tobo, 36, const Emoji('🪣', tamano: 36)),
        if (e.matica) en(Bano.matica, 40, const Emoji('🪴', tamano: 40)),
        if (e.lavanda) en(Bano.lavanda, 20, const Emoji('🪻', tamano: 20)),
        ..._repisa(e, en),
        if (e.inodoro > 0)
          en(
            Bano.inodoro,
            44,
            Image.asset('assets/emoji/toilet.png',
                width: 44,
                height: 44,
                filterQuality: FilterQuality.medium,
                color: e.inodoro == 2 ? const Color(0xFFF2C230).withValues(alpha: .6) : null,
                colorBlendMode: BlendMode.srcATop),
          ),
        if (_letrero(e) case final l?) en(Bano.letrero, 26, Emoji(l, tamano: 26)),
      ];
      return Stack(clipBehavior: Clip.hardEdge, children: hijos);
    });
  }

  static String? _letrero(EstadoBano e) => switch (e.ambiente) {
        AmbienteBano.publico => '🚻',
        AmbienteBano.granja => '🌱',
        AmbienteBano.mina => '⛏️',
        AmbienteBano.templo => '🛕',
        AmbienteBano.laxante => '⏳',
        _ => null,
      };

  static List<Widget> _repisa(EstadoBano e, Widget Function(Offset, double, Widget) en) {
    if (e.ciruela == 0) return const [];
    Widget fruta(double tam) {
      final img = Image.asset('assets/emoji/blueberries.png',
          width: tam,
          height: tam,
          filterQuality: FilterQuality.medium,
          color: e.ciruelaVerde ? const Color(0xFF5BD14B).withValues(alpha: .55) : null,
          colorBlendMode: BlendMode.srcATop);
      return img;
    }

    final f = Bano.frasco;
    return [
      if (e.ciruela == 1) ...[en(f + const Offset(-8, 8), 18, fruta(18)), en(f + const Offset(9, 9), 16, fruta(16))],
      if (e.ciruela >= 2) ...[
        en(f + Offset(-2, e.ciruela == 3 ? -2 : 2), e.ciruela == 3 ? 36 : 30, Emoji('🫙', tamano: e.ciruela == 3 ? 36 : 30)),
        en(f + Offset(0, e.ciruela == 3 ? -19 : -11), 18, fruta(18)),
        en(f + const Offset(17, 10), 15, fruta(15)),
      ],
      if (e.ciruelaNuclear) en(f + const Offset(-16, -6), 14, const Emoji('☢️', tamano: 14)),
    ];
  }
}

/// El fondo pintado. Solo se repinta si cambia el [EstadoBano].
class PintorBano extends CustomPainter {
  PintorBano(this.estado);

  final EstadoBano estado;

  @override
  bool shouldRepaint(PintorBano old) => old.estado != estado;

  @override
  void paint(Canvas canvas, Size size) {
    final e = estado;
    final w = size.width, cx = w / 2;
    final pincel = Paint()..isAntiAlias = true;
    Rect r(double l, double t, double ri, double b) => Rect.fromLTRB(cx + l, t, cx + ri, b);

    _banda(canvas, size, cx);
    _azulejos(canvas, size, cx);
    _piso(canvas, size, cx);
    _ventana(canvas, cx);

    // Moldura entre la pintura y la cerámica.
    pincel.color = e.ambiente == AmbienteBano.templo
        ? const Color(0xFFD4A72C)
        : (e.pintura ? const Color(0xFFF4F1E8) : const Color(0xFF8E846C));
    canvas.drawRect(Rect.fromLTWH(0, Bano.banda - 2, w, 3), pincel);

    if (e.ambiente == AmbienteBano.templo) _columnas(canvas, cx);
    if (e.ambiente == AmbienteBano.planta) _tubos(canvas, size, cx);
    if (e.ambiente == AmbienteBano.publico) _urinario(canvas, cx);
    if (e.ambiente == AmbienteBano.camion) {
      // La manguera del camión entra por la ventana al tanque.
      final p = Path()
        ..moveTo(cx + 52, 58)
        ..cubicTo(cx + 46, 74, cx + 30, 70, cx + 34, 92);
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF2F4A33));
    }

    _lavamanos(canvas, cx);
    _repisa(canvas, cx);
    if (!e.papel) _periodico(canvas, cx);
    if (e.papel) {
      pincel.color = const Color(0xFFB9C0C6);
      canvas.drawRect(r(Bano.papel.dx - 13, Bano.papel.dy - 15, Bano.papel.dx + 13, Bano.papel.dy - 12), pincel);
    }
    if (e.tanque > 0) _pipote(canvas, cx);
    if (e.alfombra) _alfombra(canvas, cx);
    _cortina(canvas, size, cx);
    if (e.arepa > 0) _budare(canvas, cx);
    if (e.ambiente == AmbienteBano.cloaca) _rejilla(canvas, cx);
    if (e.ambiente == AmbienteBano.publico) {
      // Placa del letrero damas/caballeros.
      final placa = Rect.fromCenter(center: Offset(cx + Bano.letrero.dx, Bano.letrero.dy), width: 34, height: 34);
      canvas.drawRect(placa, Paint()..color = const Color(0xFFF7F7F2));
      canvas.drawRect(placa, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF5A5A5A));
    }
    _bombillo(canvas, cx);

    // Tinte del ambiente y la penumbra sin bombillo.
    final tinte = switch (e.ambiente) {
      AmbienteBano.volcan => const Color(0xFFFF5A1F).withValues(alpha: .10),
      AmbienteBano.laxante => const Color(0xFF8A4FFF).withValues(alpha: .10),
      AmbienteBano.agujero => const Color(0xFF3A1A6B).withValues(alpha: .16),
      _ => null,
    };
    if (tinte != null) canvas.drawRect(Offset.zero & size, Paint()..color = tinte);
    if (!e.bombillo) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x24000000));
  }

  // Pintura de arriba: sucia y pelada, o nueva.
  void _banda(Canvas canvas, Size size, double cx) {
    final e = estado;
    final banda = Rect.fromLTWH(0, 0, size.width, Bano.banda);
    final base = switch (e.ambiente) {
      AmbienteBano.mina => const Color(0xFF6B5E52),
      AmbienteBano.agujero => const Color(0xFF1B1033),
      AmbienteBano.templo => const Color(0xFFE9D9A6),
      _ => e.pintura ? const Color(0xFF6FA89C) : const Color(0xFF9A9A80),
    };
    canvas.drawRect(banda, Paint()..color = base);
    if (e.ambiente == AmbienteBano.mina) {
      final roca = Paint()..color = const Color(0xFF574B40);
      for (var i = 0; i < 14; i++) {
        final x = (i * 53.0 + 17) % size.width, y = 8.0 + (i * 23) % 44;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 26 + (i % 3) * 8, height: 12 + (i % 2) * 6), roca);
      }
    }
    if (e.ambiente == AmbienteBano.agujero) {
      final estrella = Paint()..color = Colors.white;
      for (var i = 0; i < 26; i++) {
        canvas.drawCircle(Offset((i * 37.0 + 11) % size.width, 4.0 + (i * 19) % 52), i % 4 == 0 ? 1.4 : .8, estrella);
      }
    }
    if (!e.pintura && e.ambiente != AmbienteBano.agujero && e.ambiente != AmbienteBano.mina) {
      // Pintura pelada: parches claros con borde.
      final claro = Paint()..color = const Color(0xFFB5B39A);
      final borde = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x667C7A62);
      for (final (x, y, s) in const [(14.0, 20.0, 1.0), (-118.0, 12.0, .8), (150.0, 30.0, .9)]) {
        final p = Path()
          ..moveTo(cx + x, y)
          ..lineTo(cx + x + 14 * s, y - 6 * s)
          ..lineTo(cx + x + 26 * s, y + 2 * s)
          ..lineTo(cx + x + 20 * s, y + 12 * s)
          ..lineTo(cx + x + 6 * s, y + 10 * s)
          ..close();
        canvas.drawPath(p, claro);
        canvas.drawPath(p, borde);
      }
    }
    if (!e.ceramica) {
      // Mancha de humedad que baja del techo: borde irregular y dos chorreaditos.
      final c = Offset(cx - 66, 0);
      final mancha = Path()
        ..moveTo(c.dx - 46, 0)
        ..cubicTo(c.dx - 48, 14, c.dx - 30, 20, c.dx - 32, 30)
        ..cubicTo(c.dx - 30, 40, c.dx - 12, 36, c.dx - 8, 30)
        ..cubicTo(c.dx + 2, 42, c.dx + 18, 34, c.dx + 20, 24)
        ..cubicTo(c.dx + 34, 26, c.dx + 44, 12, c.dx + 40, 0)
        ..close();
      canvas.drawPath(mancha, Paint()..color = const Color(0x2E5A3A12));
      canvas.drawOval(Rect.fromCenter(center: c + const Offset(-6, 6), width: 52, height: 30), Paint()..color = const Color(0x1F5A3A12));
      final chorro = Paint()..color = const Color(0x265A3A12);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - 22, 30, 4, 18), const Radius.circular(2)), chorro);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx + 8, 32, 3, 11), const Radius.circular(2)), chorro);
    }
  }

  void _azulejos(Canvas canvas, Size size, double cx) {
    final e = estado;
    final zona = Rect.fromLTRB(0, Bano.banda, size.width, Bano.piso);
    final limpia = e.ceramica;
    canvas.drawRect(zona, Paint()..color = limpia ? const Color(0xFFEEF2F4) : const Color(0xFFD6CCAF));
    final junta = Paint()
      ..strokeWidth = 1
      ..color = limpia ? const Color(0xFFC3CDD3) : const Color(0xFF9F947A);
    const a = Bano.azulejo;
    for (var y = Bano.piso; y > Bano.banda; y -= a) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), junta);
    }
    var x0 = cx + a / 2;
    while (x0 > 0) {
      x0 -= a;
    }
    for (var x = x0; x < size.width; x += a) {
      canvas.drawLine(Offset(x, Bano.banda), Offset(x, Bano.piso), junta);
    }
    Rect celda(double dx, double fila) => Rect.fromLTWH(cx + a / 2 + dx * a, Bano.piso - (fila + 1) * a, a, a);
    if (limpia) {
      // Una hilera de azulejos de color, a la altura del asiento.
      final franja = Paint()..color = const Color(0xFF4C7FB0);
      canvas.drawRect(Rect.fromLTRB(0, Bano.piso - 3 * a, size.width, Bano.piso - 3 * a + 6), franja);
      return;
    }
    // Sucia: un azulejo que falta, dos partidos y moho en las juntas de abajo.
    final falta = celda(-5, 1);
    canvas.drawRect(falta, Paint()..color = const Color(0xFF8A8070));
    final punto = Paint()..color = const Color(0xFF6E6558);
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(falta.topLeft + Offset(4 + (i * 7) % 15, 4 + (i * 5) % 14), 1.2, punto);
    }
    final grieta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF5F5646);
    for (final c in [celda(-4, 4), celda(2, 4), celda(5, 2)]) {
      canvas.drawPath(
          Path()
            ..moveTo(c.left + 2, c.top + 3)
            ..lineTo(c.left + 9, c.top + 10)
            ..lineTo(c.left + 7, c.top + 15)
            ..lineTo(c.right - 2, c.bottom - 2),
          grieta);
    }
    canvas.drawRect(Rect.fromLTRB(0, Bano.piso - a, size.width, Bano.piso), Paint()..color = const Color(0x1A3A4A1A));
  }

  // Piso en perspectiva: cuadros que se achican hacia la pared.
  void _piso(Canvas canvas, Size size, double cx) {
    final e = estado;
    final h = size.height;
    const fuga = -260.0;
    final a = e.ceramica ? const Color(0xFFE4E7EA) : const Color(0xFFB4A88F);
    final b = e.ceramica ? const Color(0xFFB7C0C8) : const Color(0xFF8A7F69);
    final filas = [Bano.piso, 200.0, 210.0, 222.0, 237.0, 256.0, h];
    double xEn(double xb, double y) => cx + (xb - cx) * (y - fuga) / (h - fuga);
    final pincel = Paint()..isAntiAlias = false;
    for (var f = 0; f < filas.length - 1; f++) {
      final y0 = filas[f], y1 = filas[f + 1];
      for (var c = -8; c < 8; c++) {
        final xb0 = cx + c * 46.0, xb1 = xb0 + 46;
        pincel.color = (c + f).isEven ? a : b;
        canvas.drawPath(
            Path()
              ..moveTo(xEn(xb0, y0), y0)
              ..lineTo(xEn(xb1, y0), y0)
              ..lineTo(xEn(xb1, y1), y1)
              ..lineTo(xEn(xb0, y1), y1)
              ..close(),
            pincel);
      }
    }
    // Zócalo.
    canvas.drawRect(Rect.fromLTWH(0, Bano.piso - 1, size.width, 3), Paint()..color = e.ceramica ? const Color(0xFF8E9AA4) : const Color(0xFF5E5545));
    if (!e.ceramica) {
      final grieta = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF4E4536);
      canvas.drawPath(
          Path()
            ..moveTo(cx - 170, 270)
            ..lineTo(cx - 150, 262)
            ..lineTo(cx - 146, 252)
            ..lineTo(cx - 128, 246),
          grieta);
      canvas.drawPath(
          Path()
            ..moveTo(cx + 120, 276)
            ..lineTo(cx + 132, 266)
            ..lineTo(cx + 150, 263),
          grieta);
    }
  }

  void _ventana(Canvas canvas, double cx) {
    final e = estado;
    final v = Bano.ventana.shift(Offset(cx, 0));
    final dentro = v.deflate(3);
    final cielo = switch (e.ambiente) {
      AmbienteBano.volcan => const Color(0xFFE2572B),
      AmbienteBano.laxante => const Color(0xFF6E4BC2),
      AmbienteBano.agujero => const Color(0xFF07060F),
      AmbienteBano.mina => const Color(0xFF2A2622),
      _ => const Color(0xFF8EC5E8),
    };
    canvas.drawRect(dentro, Paint()..color = cielo);
    canvas.save();
    canvas.clipRect(dentro);
    switch (e.ambiente) {
      case AmbienteBano.casa || AmbienteBano.publico || AmbienteBano.camion || AmbienteBano.planta || AmbienteBano.cloaca:
        // Nube y el barrio de enfrente.
        final nube = Paint()..color = Colors.white;
        canvas.drawCircle(dentro.topLeft + const Offset(18, 12), 6, nube);
        canvas.drawCircle(dentro.topLeft + const Offset(26, 10), 8, nube);
        canvas.drawCircle(dentro.topLeft + const Offset(34, 13), 5, nube);
        final casa = Paint()..color = const Color(0xFFC98B5E);
        final casa2 = Paint()..color = const Color(0xFFB0725A);
        for (var i = 0; i < 6; i++) {
          final x = dentro.left + i * 14.0 - 4, alto = 10.0 + (i * 7) % 12;
          canvas.drawRect(Rect.fromLTRB(x, dentro.bottom - alto, x + 15, dentro.bottom), i.isEven ? casa : casa2);
        }
        if (e.ambiente == AmbienteBano.planta) {
          final fab = Paint()..color = const Color(0xFF5C6670);
          canvas.drawRect(Rect.fromLTRB(dentro.left + 46, dentro.bottom - 26, dentro.left + 52, dentro.bottom), fab);
          canvas.drawRect(Rect.fromLTRB(dentro.left + 30, dentro.bottom - 16, dentro.left + 66, dentro.bottom), fab);
        }
      case AmbienteBano.granja:
        canvas.drawOval(Rect.fromLTRB(dentro.left - 20, dentro.bottom - 22, dentro.left + 50, dentro.bottom + 20), Paint()..color = const Color(0xFF6DBE5C));
        canvas.drawOval(Rect.fromLTRB(dentro.left + 26, dentro.bottom - 16, dentro.right + 24, dentro.bottom + 24), Paint()..color = const Color(0xFF4FA048));
      case AmbienteBano.mina:
        canvas.drawCircle(dentro.center, 7, Paint()..color = const Color(0x55FFC94A));
        canvas.drawCircle(dentro.center, 3, Paint()..color = const Color(0xFFFFD86B));
      case AmbienteBano.templo:
        canvas.drawRect(dentro, Paint()..color = const Color(0xFFF7C66B));
        canvas.drawCircle(dentro.bottomCenter + const Offset(0, -6), 12, Paint()..color = const Color(0xFFFFE9A8));
      case AmbienteBano.volcan:
        canvas.drawRect(Rect.fromLTRB(dentro.left, dentro.bottom - 8, dentro.right, dentro.bottom), Paint()..color = const Color(0xFFFF9F1C));
      case AmbienteBano.laxante:
        final anillo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFC9B6FF);
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(dentro.center, i * 7.0, anillo);
        }
      case AmbienteBano.agujero:
        final estrella = Paint()..color = Colors.white;
        for (var i = 0; i < 12; i++) {
          canvas.drawCircle(dentro.topLeft + Offset((i * 23.0) % dentro.width, (i * 13.0) % dentro.height), .9, estrella);
        }
    }
    canvas.restore();
    // Marco y rejas (aquí todas las ventanas tienen rejas).
    final marco = e.pintura ? const Color(0xFFF4F4F0) : const Color(0xFF8B5A3C);
    canvas.drawRect(
        v.deflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = marco);
    if (e.ambiente != AmbienteBano.camion && e.ambiente != AmbienteBano.volcan && e.ambiente != AmbienteBano.agujero) {
      final reja = Paint()
        ..strokeWidth = 2
        ..color = const Color(0xFF3A3A3A);
      for (var i = 1; i <= 3; i++) {
        final x = v.left + v.width * i / 4;
        canvas.drawLine(Offset(x, v.top + 3), Offset(x, v.bottom - 3), reja);
      }
    }
    // Repisa de la ventana.
    canvas.drawRect(Rect.fromLTRB(v.left - 3, v.bottom, v.right + 3, v.bottom + 3), Paint()..color = marco);
  }

  void _columnas(Canvas canvas, double cx) {
    final oro = Paint()..color = const Color(0xFFD4A72C);
    final raya = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFFA7801A);
    for (final x in const [-196.0, 128.0]) {
      final c = Rect.fromLTRB(cx + x, 0, cx + x + 14, Bano.piso);
      canvas.drawRect(c, oro);
      canvas.drawLine(Offset(c.left + 5, 8), Offset(c.left + 5, Bano.piso - 8), raya);
      canvas.drawLine(Offset(c.left + 9, 8), Offset(c.left + 9, Bano.piso - 8), raya);
      canvas.drawRect(Rect.fromLTRB(c.left - 3, 0, c.right + 3, 6), oro);
      canvas.drawRect(Rect.fromLTRB(c.left - 3, Bano.piso - 6, c.right + 3, Bano.piso), oro);
    }
  }

  void _tubos(Canvas canvas, Size size, double cx) {
    final tubo = Paint()..color = const Color(0xFF8A949C);
    final sombra = Paint()..color = const Color(0xFF5E676E);
    canvas.drawRect(Rect.fromLTRB(cx + 56, 78, size.width, 86), tubo);
    canvas.drawRect(Rect.fromLTRB(cx + 56, 84, size.width, 86), sombra);
    canvas.drawRect(Rect.fromLTRB(cx + 48, 78, cx + 56, 98), tubo);
    canvas.drawRect(Rect.fromLTRB(cx + 132, 0, cx + 140, 78), tubo);
    // Manómetro.
    final m = Offset(cx + 136, 34);
    canvas.drawCircle(m, 8, Paint()..color = const Color(0xFFF2F2EE));
    canvas.drawCircle(
        m,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF5E676E));
    canvas.drawLine(m, m + const Offset(4, -4), Paint()
      ..strokeWidth = 1.5
      ..color = const Color(0xFFD03A2F));
  }

  void _urinario(Canvas canvas, double cx) {
    final cuerpo = Path()
      ..moveTo(cx - 108, 104)
      ..lineTo(cx - 88, 104)
      ..lineTo(cx - 90, 140)
      ..quadraticBezierTo(cx - 98, 150, cx - 106, 140)
      ..close();
    canvas.drawPath(cuerpo, Paint()..color = const Color(0xFFF4F4F0));
    canvas.drawPath(
        cuerpo,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF8E9399));
    canvas.drawRect(Rect.fromLTRB(cx - 100, 92, cx - 96, 104), Paint()..color = const Color(0xFFB9C0C6));
  }

  void _lavamanos(Canvas canvas, double cx) {
    final e = estado;
    final sx = cx + Bano.lavamanos;
    // Espejo.
    final espejo = Rect.fromLTRB(sx - 26, 26, sx + 26, 90);
    canvas.drawRect(espejo, Paint()..color = const Color(0xFFCFE3EA));
    canvas.drawPath(
        Path()
          ..moveTo(espejo.left + 10, espejo.bottom)
          ..lineTo(espejo.left + 30, espejo.top)
          ..lineTo(espejo.left + 40, espejo.top)
          ..lineTo(espejo.left + 20, espejo.bottom)
          ..close(),
        Paint()..color = const Color(0x66FFFFFF));
    canvas.drawRect(
        espejo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = e.iman ? const Color(0xFFD4A72C) : const Color(0xFF8D949A));
    // Pedestal y poceta del lavamanos.
    final loza = Paint()..color = const Color(0xFFF2F2EE);
    final linea = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9C9A92);
    final pie = Path()
      ..moveTo(sx - 7, 130)
      ..lineTo(sx + 7, 130)
      ..lineTo(sx + 11, 202)
      ..lineTo(sx - 11, 202)
      ..close();
    canvas.drawPath(pie, loza);
    canvas.drawPath(pie, linea);
    final taza = Path()
      ..moveTo(sx - 30, 114)
      ..lineTo(sx + 30, 114)
      ..quadraticBezierTo(sx + 28, 134, sx, 136)
      ..quadraticBezierTo(sx - 28, 134, sx - 30, 114)
      ..close();
    canvas.drawPath(taza, loza);
    canvas.drawPath(taza, linea);
    canvas.drawRect(Rect.fromLTRB(sx - 32, 112, sx + 32, 117), loza);
    canvas.drawRect(Rect.fromLTRB(sx - 32, 112, sx + 32, 117), linea);
    // Grifo: oxidado, cromado o dorado.
    final metal = Paint()
      ..color = switch (e.valvula) {
        2 => const Color(0xFFE0B02A),
        1 => const Color(0xFFC9CED3),
        _ => const Color(0xFF8C7B6A),
      };
    canvas.drawRect(Rect.fromLTRB(sx - 3, 100, sx + 3, 112), metal);
    canvas.drawRect(Rect.fromLTRB(sx - 3, 100, sx + 11, 105), metal);
    canvas.drawRect(Rect.fromLTRB(sx - 6, 97, sx + 6, 100), metal);
    if (e.valvula == 0) {
      // Óxido y la mancha de la gota en la loza.
      canvas.drawCircle(Offset(sx + 9, 116), 3, Paint()..color = const Color(0x66A0702A));
    }
  }

  void _repisa(Canvas canvas, double cx) {
    final r = Bano.repisa.shift(Offset(cx, 0));
    final madera = Paint()..color = const Color(0xFF8A6A48);
    canvas.drawRect(r, madera);
    canvas.drawRect(Rect.fromLTRB(r.left + 6, r.bottom, r.left + 9, r.bottom + 8), madera);
    canvas.drawRect(Rect.fromLTRB(r.right - 9, r.bottom, r.right - 6, r.bottom + 8), madera);
  }

  // Sin porta-rollo: periódico ensartado en un clavo.
  void _periodico(Canvas canvas, double cx) {
    final c = Offset(cx + Bano.papel.dx, Bano.papel.dy);
    canvas.save();
    canvas.translate(c.dx, c.dy - 14);
    canvas.rotate(.12);
    final hoja = Rect.fromLTWH(-11, 0, 22, 28);
    canvas.drawRect(hoja.shift(const Offset(3, 2)), Paint()..color = const Color(0xFFC8C4B8));
    canvas.drawRect(hoja, Paint()..color = const Color(0xFFE2DED2));
    final letra = Paint()
      ..strokeWidth = 1.4
      ..color = const Color(0xFF8F8B80);
    canvas.drawRect(Rect.fromLTWH(-8, 4, 16, 4), Paint()..color = const Color(0xFF6E6A60));
    for (var y = 11.0; y < 26; y += 3.5) {
      canvas.drawLine(Offset(-8, y), Offset(y > 20 ? 2 : 8, y), letra);
    }
    canvas.restore();
    canvas.drawCircle(c + const Offset(0, -12), 2, Paint()..color = const Color(0xFF4A4A4A));
  }

  void _pipote(Canvas canvas, double cx) {
    final grande = estado.tanque == 2;
    final c = Offset(cx + Bano.tobo.dx + (grande ? 4 : 0), Bano.tobo.dy);
    final ancho = grande ? 42.0 : 32.0, alto = grande ? 58.0 : 44.0;
    final cuerpo = Rect.fromLTRB(c.dx - ancho / 2, c.dy + 16 - alto, c.dx + ancho / 2, c.dy + 16);
    canvas.drawRect(cuerpo, Paint()..color = const Color(0xFF2F6FB5));
    final aro = Paint()..color = const Color(0xFF24588F);
    for (final f in const [.12, .5, .88]) {
      canvas.drawRect(Rect.fromLTWH(cuerpo.left, cuerpo.top + cuerpo.height * f - 2, cuerpo.width, 4), aro);
    }
    canvas.drawRect(Rect.fromLTWH(cuerpo.left + 5, cuerpo.top + 4, 4, cuerpo.height - 8), Paint()..color = const Color(0x44FFFFFF));
    canvas.drawOval(Rect.fromLTWH(cuerpo.left, cuerpo.top - 4, cuerpo.width, 8), Paint()..color = const Color(0xFF3B80C9));
    if (grande) {
      // Llavecita abajo.
      canvas.drawRect(Rect.fromLTWH(cuerpo.left - 6, cuerpo.bottom - 14, 7, 4), Paint()..color = const Color(0xFFC9CED3));
    }
  }

  // Alfombra en U al pie de la poceta.
  void _alfombra(Canvas canvas, double cx) {
    const centro = -4.0;
    final exterior = RRect.fromRectAndCorners(Rect.fromLTRB(cx + centro - 56, 200, cx + centro + 56, 244),
        bottomLeft: const Radius.circular(22), bottomRight: const Radius.circular(22));
    final hueco = Path()..addOval(Rect.fromCenter(center: Offset(cx + centro, 200), width: 54, height: 22));
    final forma = Path.combine(PathOperation.difference, Path()..addRRect(exterior), hueco);
    canvas.drawPath(forma, Paint()..color = const Color(0xFF5B8F7B));
    canvas.drawPath(
        forma,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF8CC0AA));
  }

  void _cortina(Canvas canvas, Size size, double cx) {
    final e = estado;
    final izq = cx + 150;
    if (izq > size.width - 6) return;
    // Tubo.
    canvas.drawRect(Rect.fromLTRB(izq - 4, 8, size.width, 11), Paint()..color = const Color(0xFF9AA1A7));
    final tela = Rect.fromLTRB(izq, 11, size.width, Bano.piso + 6);
    if (e.cortina) {
      canvas.drawRect(tela, Paint()..color = const Color(0xFFF6E3EA));
      final petalo = Paint()..color = const Color(0xFFE77FA5);
      final centro = Paint()..color = const Color(0xFFF7C948);
      for (var y = tela.top + 16; y < tela.bottom - 8; y += 30) {
        for (var x = tela.left + ((y ~/ 30).isEven ? 10 : 22); x < tela.right - 4; x += 26) {
          for (var k = 0; k < 5; k++) {
            final ang = k * 2 * pi / 5;
            canvas.drawCircle(Offset(x + cos(ang) * 4, y + sin(ang) * 4), 3, petalo);
          }
          canvas.drawCircle(Offset(x, y), 2, centro);
        }
      }
    } else {
      // Plástico viejo, rajado abajo y con un gancho suelto.
      final p = Path()
        ..moveTo(tela.left, tela.top + 6)
        ..lineTo(tela.right, tela.top)
        ..lineTo(tela.right, tela.bottom)
        ..lineTo(tela.left + 20, tela.bottom)
        ..lineTo(tela.left + 12, tela.bottom - 30)
        ..lineTo(tela.left + 6, tela.bottom - 4)
        ..lineTo(tela.left, tela.bottom - 4)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xCCDDE5E2));
      canvas.drawCircle(Offset(tela.left + 3, tela.top + 2), 2.5, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF6E767C));
    }
    final pliegue = Paint()
      ..strokeWidth = 1
      ..color = e.cortina ? const Color(0x33A0506E) : const Color(0x33506068);
    for (var x = tela.left + 9; x < tela.right; x += 12) {
      canvas.drawLine(Offset(x, tela.top + 4), Offset(x, tela.bottom - 6), pliegue);
    }
  }

  void _budare(Canvas canvas, double cx) {
    final grande = estado.arepa >= 3;
    final c = Offset(cx + Bano.budare.dx, Bano.budare.dy);
    final rx = grande ? 34.0 : 27.0;
    // Hornilla con brasas y el budare encima.
    canvas.drawRect(Rect.fromCenter(center: c + const Offset(0, 9), width: rx * 1.4, height: 8), Paint()..color = const Color(0xFF3E3A36));
    final brasa = Paint()..color = const Color(0xFFE2572B);
    for (var i = -2; i <= 2; i++) {
      canvas.drawCircle(c + Offset(i * rx * .25, 9), 1.6, brasa);
    }
    canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: 12), Paint()..color = const Color(0xFF1E1C1A));
    canvas.drawOval(Rect.fromCenter(center: c + const Offset(0, -1), width: rx * 1.7, height: 8), Paint()..color = const Color(0xFF34302C));
    canvas.drawRect(Rect.fromLTWH(c.dx + rx - 2, c.dy - 2, 14, 4), Paint()..color = const Color(0xFF1E1C1A));
  }

  void _rejilla(Canvas canvas, double cx) {
    final c = Offset(cx + Bano.rejilla.dx, Bano.rejilla.dy);
    final r = Rect.fromCenter(center: c, width: 40, height: 12);
    canvas.drawOval(r, Paint()..color = const Color(0xFF151413));
    final barra = Paint()
      ..strokeWidth = 2
      ..color = const Color(0xFF6E737A);
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(c + Offset(i * 7.0, -5), c + Offset(i * 7.0, 5), barra);
    }
    canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF6E737A));
  }

  void _bombillo(Canvas canvas, double cx) {
    final b = Offset(cx + Bano.bombillo.dx, Bano.bombillo.dy);
    final cable = Paint()
      ..strokeWidth = 1.5
      ..color = const Color(0xFF2A2A2A);
    if (!estado.bombillo) {
      // Pelado, colgando del cable.
      canvas.drawLine(Offset(b.dx, 0), b + const Offset(0, -12), cable);
      return;
    }
    // Lámpara con su luz cálida.
    canvas.drawCircle(b + const Offset(0, 16), 70, Paint()..color = const Color(0x1AFFD27A));
    canvas.drawCircle(b + const Offset(0, 10), 34, Paint()..color = const Color(0x1FFFD27A));
    canvas.drawLine(Offset(b.dx, 0), b + const Offset(0, -12), cable);
    final pantalla = Path()
      ..moveTo(b.dx - 9, b.dy - 12)
      ..lineTo(b.dx + 9, b.dy - 12)
      ..lineTo(b.dx + 19, b.dy + 4)
      ..lineTo(b.dx - 19, b.dy + 4)
      ..close();
    canvas.drawOval(Rect.fromCenter(center: b + const Offset(0, 5), width: 14, height: 8), Paint()..color = const Color(0xFFFFE9A8));
    canvas.drawPath(pantalla, Paint()..color = const Color(0xFFF2E6C9));
    canvas.drawPath(
        pantalla,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFB59E6E));
  }
}

/// La tela peluda del forro, dibujada ENCIMA de la poceta (la imagen no se toca). [lado] es el de toilet.png.
class PintorForro extends CustomPainter {
  const PintorForro();

  @override
  bool shouldRepaint(PintorForro old) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width;
    final tela = Paint()..color = const Color(0xFFF3A6C4);
    final pelo = Paint()..color = const Color(0xFFE584AC);
    // Funda del asiento (vista de lado) y de la tapa del tanque.
    for (final r in [Rect.fromLTRB(l * .08, l * .435, l * .63, l * .525), Rect.fromLTRB(l * .615, l * .045, l * .89, l * .12)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)), tela);
      for (var x = r.left + 3; x < r.right - 2; x += 4.5) {
        canvas.drawCircle(Offset(x, r.top + 1), 1.8, tela);
        canvas.drawCircle(Offset(x + 2, r.bottom - 1), 1.8, tela);
        canvas.drawCircle(Offset(x + 1, r.center.dy + ((x ~/ 4.5).isEven ? -1.5 : 1.5)), 1, pelo);
      }
    }
  }
}
