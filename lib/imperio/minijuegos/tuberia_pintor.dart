// Pintor de Tubería Express: un solo CustomPainter que dibuja el mundo de lado. Capas: fondo de la zona (gradiente,
// patrón lejano y capa media con parallax, cosas que se mueven aunque estés quieto), loma trasera, ladera de lodo,
// rollos, cucarachas, el Atasco, el mojón con su cara, partículas, textos y los avisos encima (fiebre, Atasco cerca,
// destello, tira del Atasco a la izquierda y pistas de los primeros segundos). Lo repinta el Ticker por `repaint`.
// Los Paint son estáticos; los patrones (azulejos, ladrillos, ciudad) se graban una vez por tamaño en un Picture.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../idioma.dart';
import 'tuberia_efectos.dart';
import 'tuberia_logica.dart';

/// PNGs de los emojis que usa el juego; los llena la vista cuando terminan de cargar.
class ImagenesTuberia {
  ui.Image? mojon, rollo, cucaracha, rata, inodoro, banera, chispas;
}

/// Qué tan cerca está el Atasco: 0 lejos, 1 encima.
double cercaniaAtasco(double separacion) => (1 - (separacion - 2) / 14).clamp(0.0, 1.0);

class _ColoresZona {
  const _ColoresZona(this.cielo, this.labio, this.cuerpoArriba, this.cuerpoAbajo);
  final List<Color> cielo;
  final Color labio, cuerpoArriba, cuerpoAbajo;
}

const _zonas = [
  _ColoresZona([Color(0xFFE3F3F5), Color(0xFFB4DCE3), Color(0xFF8FC6D0)], Color(0xFFF4F1EA), Color(0xFF8A5A36), Color(0xFF4A2C18)),
  _ColoresZona([Color(0xFF2E434B), Color(0xFF1B2A30), Color(0xFF121C21)], Color(0xFF9C7B4F), Color(0xFF6B4A2E), Color(0xFF2A1A0F)),
  _ColoresZona([Color(0xFF45322A), Color(0xFF2A1D16), Color(0xFF160F0B)], Color(0xFF8FD14F), Color(0xFF4B4A22), Color(0xFF1A1708)),
  _ColoresZona([Color(0xFF0B1433), Color(0xFF23306B), Color(0xFF5A3F72)], Color(0xFF7FD3E6), Color(0xFF2F4C5C), Color(0xFF0E1A22)),
  _ColoresZona([Color(0xFF2A6660), Color(0xFF1D4B47), Color(0xFF0C2423)], Color(0xFFA6F0C6), Color(0xFF3E6B4F), Color(0xFF13261C)),
];

class PintorTuberia extends CustomPainter {
  PintorTuberia({
    required this.juego,
    required this.efectos,
    required this.anim,
    required this.camara,
    required this.imagenes,
    required this.oscuro,
    required this.mov,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final JuegoTuberia juego;
  final EfectosTuberia efectos;
  final AnimMojon anim;
  final CamaraTuberia camara;
  final ImagenesTuberia imagenes;
  final bool oscuro;
  final Movimiento mov;

  // ---------------------------------------------------------------- pinturas (una vez)
  static final _p = Paint()..isAntiAlias = true;
  static final _pTrazo = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _pImg = Paint()..filterQuality = FilterQuality.medium;
  static final _pImgFondo = Paint()
    ..filterQuality = FilterQuality.low
    ..color = const Color(0x55FFFFFF);
  static final _pDorado = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = const ColorFilter.mode(Color(0xFFFFC21A), BlendMode.modulate);
  static final _pBrillo = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  static final _pBrilloChico = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  static final _pSuelo = Paint();
  static final _pAtasco = Paint();
  static final _pVineta = Paint();
  static final _pCapa = Paint();
  static final _suelo = Path();
  static final _labio = Path();
  static final _loma = Path();
  static final _borde = Path();
  static final _tmp = Path();

  static Size _tamPatrones = Size.zero;
  static final _patrones = <int, ui.Picture>{};
  static final _textos = <String, TextPainter>{};

  // Transformación mundo -> pantalla (se calcula al empezar cada paint).
  double _ppm = 30, _ox = 0, _oy = 0, _w = 0, _h = 0;
  double _sx(double x) => _ox + x * _ppm;
  double _sy(double y) => _oy - y * _ppm;

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    if (_w <= 0 || _h <= 0) return;
    if (_tamPatrones != size) {
      for (final p in _patrones.values) {
        p.dispose();
      }
      _patrones.clear();
      _tamPatrones = size;
    }
    final j = juego;
    final cam = camara;
    final d = efectos.desplazamiento;
    final ppm0 = _w / 14;
    _ppm = ppm0 * cam.zoom;
    _ox = _w * cam.focoX - cam.x * _ppm + d.dx;
    _oy = _h * 0.61 + cam.y * _ppm + d.dy;
    final t = efectos.fase;
    final c = cercaniaAtasco(j.separacion);

    // Zona que se ve (y mezcla con la siguiente en los últimos 35 m).
    final zx = max(0.0, cam.x);
    final z = JuegoTuberia.zonaEn(zx) % JuegoTuberia.zonas;
    final u = zx % JuegoTuberia.metrosZona;
    final mezcla = u > JuegoTuberia.metrosZona - 35 ? (u - (JuegoTuberia.metrosZona - 35)) / 35 : 0.0;
    final zSig = (z + 1) % JuegoTuberia.zonas;

    // ---- fondo
    final par = mov == Movimiento.nada ? 0.0 : cam.x * ppm0;
    _fondo(canvas, z, par, t);
    if (mezcla > 0) {
      if (mov == Movimiento.nada) {
        if (mezcla > 0.5) _fondo(canvas, zSig, par, t);
      } else {
        canvas.saveLayer(Offset.zero & size, _pCapa..color = Color.fromRGBO(0, 0, 0, mezcla));
        _fondo(canvas, zSig, par, t);
        canvas.restore();
      }
    }
    if (oscuro) canvas.drawRect(Offset.zero & size, _p..color = const Color(0x40000000));

    final col = _zonas[z];
    final colSig = _zonas[zSig];
    final labio = Color.lerp(col.labio, colSig.labio, mezcla)!;
    final arriba = Color.lerp(col.cuerpoArriba, colSig.cuerpoArriba, mezcla)!;
    final abajo = Color.lerp(col.cuerpoAbajo, colSig.cuerpoAbajo, mezcla)!;

    _lomaTrasera(canvas, cam, abajo, arriba);
    _ladera(canvas, j, labio, arriba, abajo);
    _cucarachas(canvas, j, t);
    _rollos(canvas, j, t);
    _mojon(canvas, j, t, c);
    _atasco(canvas, j, t);
    _particulas(canvas);
    _textosFlotantes(canvas);

    // ---- encima
    if (j.enFiebre && mov != Movimiento.nada) {
      final pulso = 0.75 + 0.25 * sin(t * 9);
      _pVineta.shader = ui.Gradient.radial(Offset(_w / 2, _h / 2), _h * 0.62,
          [const Color(0x00FFD60A), Color.fromRGBO(255, 200, 20, 0.42 * pulso)], const [0.55, 1]);
      canvas.drawRect(Offset.zero & size, _pVineta);
    }
    if (c > 0.35) {
      final a = ((c - 0.35) / 0.65).clamp(0.0, 1.0);
      final latido = mov == Movimiento.nada ? 1.0 : 0.8 + 0.2 * sin(t * (6 + 6 * a));
      _pVineta.shader = ui.Gradient.linear(Offset.zero, Offset(_w * 0.7, 0),
          [Color.fromRGBO(120, 30, 10, 0.55 * a * latido), const Color(0x00781E0A)]);
      canvas.drawRect(Offset.zero & size, _pVineta);
    }
    if (efectos.destello > 0) {
      final cd = efectos.colorDestello;
      canvas.drawRect(Offset.zero & size, _p..color = cd.withValues(alpha: (efectos.destello * 0.4).clamp(0.0, 0.4)));
    }
    _tiraAtasco(canvas, j, c, t);
    _pistas(canvas, j, t);
  }

  // ================================================================ fondos

  void _fondo(Canvas canvas, int z, double par, double t) {
    final col = _zonas[z];
    _p.shader = ui.Gradient.linear(Offset.zero, Offset(0, _h), col.cielo, const [0, 0.55, 1]);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, _h), _p);
    _p.shader = null;
    switch (z) {
      case 0:
        _bano(canvas, par, t);
      case 1:
        _desague(canvas, par, t);
      case 2:
        _cloaca(canvas, par, t);
      case 3:
        _rio(canvas, par, t);
      default:
        _planta(canvas, par, t);
    }
  }

  void _patron(Canvas canvas, int z, double periodo, double desp, void Function(Canvas c, double ancho) grabar) {
    var pic = _patrones[z];
    final ancho = (_w / periodo).ceil() * periodo + periodo;
    if (pic == null) {
      final rec = ui.PictureRecorder();
      grabar(Canvas(rec), ancho);
      pic = rec.endRecording();
      _patrones[z] = pic;
    }
    canvas.save();
    canvas.translate(-(desp % periodo), 0);
    canvas.drawPicture(pic);
    canvas.restore();
  }

  // Baño: azulejos, una franja azul, bañera e inodoro desteñidos y burbujas de jabón que suben.
  void _bano(Canvas canvas, double par, double t) {
    const lado = 46.0;
    _patron(canvas, 0, lado * 2, par * 0.12, (cv, ancho) {
      final p = Paint();
      for (var fy = 0.0; fy < _h; fy += lado) {
        for (var fx = 0.0; fx < ancho; fx += lado) {
          final k = ((fx / lado).round() + (fy / lado).round()) % 2;
          if (k == 0) cv.drawRect(Rect.fromLTWH(fx, fy, lado, lado), p..color = const Color(0x0A003040));
          cv.drawRect(Rect.fromLTWH(fx + 4, fy + 4, lado * 0.35, 3), p..color = const Color(0x55FFFFFF));
        }
      }
      final franja = (_h * 0.30 / lado).round() * lado;
      cv.drawRect(Rect.fromLTWH(0, franja, ancho, lado * 0.5), p..color = const Color(0xFF5FA8B8));
      cv.drawRect(Rect.fromLTWH(0, franja + lado * 0.5, ancho, 3), p..color = const Color(0xFF3F8797));
      p
        ..color = const Color(0xBFFFFFFF)
        ..strokeWidth = 2;
      for (var fy = 0.0; fy < _h; fy += lado) {
        cv.drawLine(Offset(0, fy), Offset(ancho, fy), p);
      }
      for (var fx = 0.0; fx < ancho; fx += lado) {
        cv.drawLine(Offset(fx, 0), Offset(fx, _h), p);
      }
    });
    // Capa media: bañera e inodoro desteñidos.
    final img = [imagenes.banera, imagenes.inodoro];
    const paso = 300.0;
    final desp = par * 0.32;
    final i0 = (desp / paso).floor();
    for (var i = i0; i < i0 + (_w / paso).ceil() + 2; i++) {
      final im = img[i.abs() % 2];
      if (im == null) continue;
      final x = i * paso - desp;
      final tam = i.isEven ? 190.0 : 150.0;
      canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
          Rect.fromLTWH(x, _h * 0.47 - tam, tam, tam), _pImgFondo);
    }
    if (mov == Movimiento.nada) return;
    // Burbujas de jabón.
    _pTrazo
      ..strokeWidth = 1.6
      ..color = const Color(0xB0FFFFFF);
    for (var i = 0; i < 9; i++) {
      final r = 6.0 + (i * 37 % 11);
      final y = _h - ((t * (22 + i * 3) + i * 131) % (_h + 60));
      final x = ((i * 97 - par * 0.2) % (_w + 40) + _w + 40) % (_w + 40) - 20 + sin(t * 1.3 + i) * 10;
      canvas.drawCircle(Offset(x, y), r, _pTrazo);
      canvas.drawCircle(Offset(x - r * 0.35, y - r * 0.35), r * 0.22, _p..color = const Color(0xCCFFFFFF));
    }
  }

  // Desagüe: tubos de cobre finos al fondo, gruesos con bridas adelante y gotas que caen.
  void _desague(Canvas canvas, double par, double t) {
    final dLejos = par * 0.14;
    const cobre = Color(0xFF7A4A2C);
    const cobreLuz = Color(0xFFB87A50);
    for (final (y, g) in [(_h * 0.16, 8.0), (_h * 0.30, 6.0)]) {
      canvas.drawRect(Rect.fromLTWH(0, y, _w, g), _p..color = cobre.withValues(alpha: 0.55));
      canvas.drawRect(Rect.fromLTWH(0, y + 1, _w, 1.5), _p..color = cobreLuz.withValues(alpha: 0.5));
    }
    const pasoV = 170.0;
    for (var i = (dLejos / pasoV).floor(); i < (dLejos + _w) / pasoV + 1; i++) {
      final x = i * pasoV - dLejos;
      canvas.drawRect(Rect.fromLTWH(x, 0, 9, _h * 0.55), _p..color = cobre.withValues(alpha: 0.45));
      canvas.drawRect(Rect.fromLTWH(x + 2, 0, 2, _h * 0.55), _p..color = cobreLuz.withValues(alpha: 0.35));
    }
    // Tubo grueso con bridas.
    final dMedio = par * 0.34;
    final yt = _h * 0.40;
    canvas.drawRect(Rect.fromLTWH(0, yt, _w, 28), _p..color = const Color(0xFF8E5532));
    canvas.drawRect(Rect.fromLTWH(0, yt + 4, _w, 5), _p..color = const Color(0xFFD4925F));
    canvas.drawRect(Rect.fromLTWH(0, yt + 22, _w, 6), _p..color = const Color(0xFF5A3018));
    const pasoB = 150.0;
    final i0 = (dMedio / pasoB).floor();
    for (var i = i0; i < i0 + (_w / pasoB).ceil() + 2; i++) {
      final x = i * pasoB - dMedio;
      canvas.drawRect(Rect.fromLTWH(x - 6, yt - 6, 12, 40), _p..color = const Color(0xFF6E3F22));
      canvas.drawRect(Rect.fromLTWH(x - 4, yt - 4, 3, 36), _p..color = const Color(0xFFC88A58));
      if (i.isEven) {
        // Bajante desde arriba.
        canvas.drawRect(Rect.fromLTWH(x + 50, 0, 20, yt), _p..color = const Color(0xFF7E4A2B));
        canvas.drawRect(Rect.fromLTWH(x + 54, 0, 4, yt), _p..color = const Color(0xFFC88A58));
      }
      if (mov == Movimiento.nada) continue;
      // Gota que cae de la brida.
      final ciclo = (t * 0.9 + i * 0.37) % 1.0;
      final yg = yt + 34 + ciclo * ciclo * _h * 0.5;
      _gota(canvas, Offset(x, yg), 4.5, const Color(0xCC7FC8E0));
    }
  }

  // Cloaca: ladrillos, arcos oscuros con ojos que brillan y ratas caminando.
  void _cloaca(Canvas canvas, double par, double t) {
    const alto = 22.0, largo = 50.0;
    _patron(canvas, 2, largo * 2, par * 0.12, (cv, ancho) {
      final p = Paint()..strokeWidth = 2;
      var fila = 0;
      for (var fy = 0.0; fy < _h; fy += alto, fila++) {
        final off = fila.isEven ? 0.0 : largo / 2;
        for (var fx = -largo; fx < ancho; fx += largo) {
          final k = ((fx + off) * 7 + fy * 13).abs().round() % 5;
          cv.drawRect(Rect.fromLTWH(fx + off + 1, fy + 1, largo - 2, alto - 2), p..color = Color.fromRGBO(120, 70, 45, 0.10 + k * 0.03));
          cv.drawRect(Rect.fromLTWH(fx + off + 3, fy + 3, largo - 8, 2), p..color = const Color(0x18FFFFFF));
        }
        cv.drawLine(Offset(0, fy), Offset(ancho, fy), p..color = const Color(0x55000000));
      }
    });
    final dMedio = par * 0.34;
    const paso = 230.0;
    final i0 = (dMedio / paso).floor();
    for (var i = i0; i < i0 + (_w / paso).ceil() + 2; i++) {
      final x = i * paso - dMedio;
      final arco = Rect.fromLTWH(x, _h * 0.24, 150, _h * 0.6);
      _tmp
        ..reset()
        ..moveTo(arco.left, arco.bottom)
        ..lineTo(arco.left, arco.top + 75)
        ..arcToPoint(Offset(arco.right, arco.top + 75), radius: const Radius.circular(75))
        ..lineTo(arco.right, arco.bottom)
        ..close();
      canvas.drawPath(_tmp, _p..color = const Color(0xD0080504));
      _pTrazo
        ..strokeWidth = 9
        ..color = const Color(0xFF5A4030);
      canvas.drawPath(_tmp, _pTrazo);
      // Ojos que brillan adentro.
      final abiertos = mov == Movimiento.nada || sin(t * 0.9 + i * 2.1) > -0.55;
      final ox = x + 45 + (i * 29 % 50), oy = arco.top + 120 + (i * 41 % 80);
      if (abiertos) {
        _pBrilloChico.color = const Color(0xAAC8FF5A);
        canvas.drawCircle(Offset(ox, oy), 7, _pBrilloChico);
        canvas.drawCircle(Offset(ox + 18, oy), 7, _pBrilloChico);
        canvas.drawOval(Rect.fromCenter(center: Offset(ox, oy), width: 9, height: 6), _p..color = const Color(0xFFDFFF7A));
        canvas.drawOval(Rect.fromCenter(center: Offset(ox + 18, oy), width: 9, height: 6), _p);
        canvas.drawRect(Rect.fromCenter(center: Offset(ox, oy), width: 1.6, height: 5), _p..color = const Color(0xFF101005));
        canvas.drawRect(Rect.fromCenter(center: Offset(ox + 18, oy), width: 1.6, height: 5), _p);
      } else {
        _pTrazo
          ..strokeWidth = 1.5
          ..color = const Color(0x88C8FF5A);
        canvas.drawLine(Offset(ox - 4, oy), Offset(ox + 4, oy), _pTrazo);
        canvas.drawLine(Offset(ox + 14, oy), Offset(ox + 22, oy), _pTrazo);
      }
    }
    // Ratas caminando por la repisa.
    final rata = imagenes.rata;
    final yRepisa = _h * 0.5;
    canvas.drawRect(Rect.fromLTWH(0, yRepisa, _w, 8), _p..color = const Color(0xFF3A2A20));
    canvas.drawRect(Rect.fromLTWH(0, yRepisa, _w, 2), _p..color = const Color(0xFF6A5040));
    if (rata != null && mov != Movimiento.nada) {
      for (var i = 0; i < 2; i++) {
        final ciclo = _w + 160;
        final x = ((i * ciclo / 2 - t * (34 + i * 9) - par * 0.34) % ciclo + ciclo) % ciclo - 80;
        final salto = (sin(t * 14 + i) * 2).abs();
        canvas.drawImageRect(rata, Rect.fromLTWH(0, 0, rata.width.toDouble(), rata.height.toDouble()),
            Rect.fromLTWH(x, yRepisa - 40 - salto, 42, 42), _pImg);
      }
    }
  }

  // Río de la ciudad: estrellas, edificios con ventanas, un puente con faroles.
  void _rio(Canvas canvas, double par, double t) {
    if (mov != Movimiento.nada) {
      for (var i = 0; i < 26; i++) {
        final x = (i * 151.3) % _w, y = (i * 67.7) % (_h * 0.3);
        final b = 0.35 + 0.35 * sin(t * (1 + i % 3) + i);
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), _p..color = Color.fromRGBO(255, 255, 230, b));
      }
    }
    const periodo = 420.0;
    _patron(canvas, 3, periodo, par * 0.10, (cv, ancho) {
      final p = Paint();
      var x = 0.0;
      var k = 0;
      while (x < ancho) {
        final an = 38.0 + (k * 37 % 40);
        final al = 90.0 + (k * 53 % 150);
        final base = _h * 0.50;
        cv.drawRect(Rect.fromLTWH(x, base - al, an, al + _h * 0.5), p..color = const Color(0xFF151C3E));
        for (var wy = base - al + 8; wy < base - 6; wy += 13) {
          for (var wx = x + 5; wx < x + an - 6; wx += 9) {
            final h = ((wx * 13 + wy * 7) % 10).round();
            if (h < 4) cv.drawRect(Rect.fromLTWH(wx, wy, 4, 6), p..color = const Color(0xFFFFD873));
          }
        }
        x += an + 6;
        k++;
      }
    });
    // Puente.
    final dMedio = par * 0.34;
    final yp = _h * 0.36;
    canvas.drawRect(Rect.fromLTWH(0, yp, _w, 16), _p..color = const Color(0xFF1A1F3A));
    canvas.drawRect(Rect.fromLTWH(0, yp - 10, _w, 2), _p..color = const Color(0xFF2A3156));
    const paso = 260.0;
    final i0 = (dMedio / paso).floor();
    for (var i = i0; i < i0 + (_w / paso).ceil() + 2; i++) {
      final x = i * paso - dMedio;
      _pTrazo
        ..strokeWidth = 12
        ..color = const Color(0xFF1A1F3A);
      canvas.drawArc(Rect.fromLTWH(x, yp + 8, paso, 220), pi, pi, false, _pTrazo);
      canvas.drawRect(Rect.fromLTWH(x - 9, yp, 18, _h * 0.5), _p..color = const Color(0xFF161A33));
      for (final lx in [x + paso * 0.25, x + paso * 0.75]) {
        canvas.drawRect(Rect.fromLTWH(lx - 1.5, yp - 30, 3, 30), _p..color = const Color(0xFF2A3156));
        final parpadeo = mov == Movimiento.nada ? 1.0 : 0.85 + 0.15 * sin(t * 3 + lx);
        _pBrillo.color = Color.fromRGBO(255, 214, 120, 0.55 * parpadeo);
        canvas.drawCircle(Offset(lx, yp - 32), 14, _pBrillo);
        canvas.drawCircle(Offset(lx, yp - 32), 4, _p..color = const Color(0xFFFFE6A0));
      }
    }
  }

  // Planta de tratamiento: tanques, tubos con válvulas y burbujas.
  void _planta(Canvas canvas, double par, double t) {
    final dLejos = par * 0.14;
    const paso = 240.0;
    for (var i = (dLejos / paso).floor(); i < (dLejos + _w) / paso + 1; i++) {
      final x = i * paso - dLejos;
      final r = Rect.fromLTWH(x, _h * 0.14, 130, _h * 0.42);
      canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(40), topRight: const Radius.circular(40)),
          _p..color = const Color(0xFF16413A));
      canvas.drawRect(Rect.fromLTWH(x + 14, r.top + 30, 10, r.height - 30), _p..color = const Color(0x2AFFFFFF));
      canvas.drawRect(Rect.fromLTWH(x, r.top + r.height * 0.45, 130, 6), _p..color = const Color(0xFF0F302A));
      for (var ly = r.top + 30; ly < r.bottom; ly += 14) {
        canvas.drawRect(Rect.fromLTWH(x + 104, ly, 14, 2), _p..color = const Color(0xFF2A6158));
      }
    }
    final dMedio = par * 0.34;
    final yt = _h * 0.44;
    canvas.drawRect(Rect.fromLTWH(0, yt, _w, 20), _p..color = const Color(0xFF4F7F70));
    canvas.drawRect(Rect.fromLTWH(0, yt + 3, _w, 4), _p..color = const Color(0xFF8CC2AE));
    const pasoV = 200.0;
    final i0 = (dMedio / pasoV).floor();
    for (var i = i0; i < i0 + (_w / pasoV).ceil() + 2; i++) {
      final x = i * pasoV - dMedio;
      canvas.drawRect(Rect.fromLTWH(x - 4, yt - 26, 8, 26), _p..color = const Color(0xFF4F7F70));
      final giro = mov == Movimiento.nada ? 0.0 : t * 0.6 + i;
      _pTrazo
        ..strokeWidth = 4
        ..color = const Color(0xFFD9534F);
      canvas.drawCircle(Offset(x, yt - 30), 12, _pTrazo);
      _pTrazo.strokeWidth = 2.5;
      for (var k = 0; k < 3; k++) {
        final a = giro + k * pi / 3;
        canvas.drawLine(Offset(x + cos(a) * 12, yt - 30 + sin(a) * 12), Offset(x - cos(a) * 12, yt - 30 - sin(a) * 12), _pTrazo);
      }
    }
    if (mov == Movimiento.nada) return;
    for (var i = 0; i < 12; i++) {
      final r = 3.0 + (i * 7 % 6);
      final y = _h - ((t * (30 + i * 4) + i * 97) % (_h * 0.8));
      final x = ((i * 83 - par * 0.25) % _w + _w) % _w + sin(t * 2 + i) * 6;
      canvas.drawCircle(Offset(x, y), r, _p..color = const Color(0x55A6F0C6));
      canvas.drawCircle(Offset(x - r * 0.3, y - r * 0.3), r * 0.3, _p..color = const Color(0x99FFFFFF));
    }
  }

  // ================================================================ mundo

  void _lomaTrasera(Canvas canvas, CamaraTuberia cam, Color abajo, Color arriba) {
    final f = mov == Movimiento.nada ? 0.0 : 0.55;
    final base = _h * 0.56 + cam.y * _ppm * 0.55 + 1.6 * _ppm;
    _loma
      ..reset()
      ..moveTo(0, _h);
    for (var px = 0.0; px <= _w + 8; px += 8) {
      final wx = (px - _w * cam.focoX) / _ppm + cam.x * f;
      final y = 1.6 * sin(wx * 0.19) + 0.9 * sin(wx * 0.43 + 1.3) + 0.4 * sin(wx * 0.91);
      _loma.lineTo(px, base - y * _ppm);
    }
    _loma
      ..lineTo(_w, _h)
      ..close();
    canvas.drawPath(_loma, _p..color = Color.lerp(abajo, arriba, 0.35)!.withValues(alpha: 0.75));
  }

  void _ladera(Canvas canvas, JuegoTuberia j, Color labio, Color arriba, Color abajo) {
    _suelo
      ..reset()
      ..moveTo(-4, _h + 4);
    _labio.reset();
    var tope = _h;
    for (var px = -4.0; px <= _w + 8; px += 5) {
      final wx = (px - _ox) / _ppm;
      final sy = _sy(j.altura(wx));
      tope = min(tope, sy);
      _suelo.lineTo(px, sy);
      if (px < -3) {
        _labio.moveTo(px, sy);
      } else {
        _labio.lineTo(px, sy);
      }
    }
    _suelo
      ..lineTo(_w + 8, _h + 4)
      ..close();
    _pSuelo.shader = ui.Gradient.linear(Offset(0, tope), Offset(0, max(tope + 1, _h)), [arriba, abajo]);
    canvas.drawPath(_suelo, _pSuelo);
    // Estratos.
    _pTrazo
      ..strokeWidth = 2
      ..color = const Color(0x22000000);
    for (final k in [0.8, 1.9, 3.3]) {
      canvas.save();
      canvas.translate(0, k * _ppm);
      canvas.drawPath(_labio, _pTrazo);
      canvas.restore();
    }
    // Piedritas y grumos.
    final x0 = ((-_ox) / _ppm).floor() - 1, x1 = ((_w - _ox) / _ppm).ceil() + 1;
    for (var i = x0; i <= x1; i++) {
      final h1 = _hash(i), h2 = _hash(i + 7919);
      final wx = i + h1;
      final hondo = 0.5 + h2 * 3.0;
      final sx = _sx(wx), sy = _sy(j.altura(wx) - hondo);
      canvas.drawCircle(Offset(sx, sy), 1.5 + h2 * 3, _p..color = Color.lerp(arriba, labio, 0.25)!.withValues(alpha: 0.35));
    }
    // Labio: banda gruesa, brillo encima.
    _pTrazo
      ..strokeWidth = max(4, 0.22 * _ppm)
      ..color = labio;
    canvas.drawPath(_labio, _pTrazo);
    canvas.save();
    canvas.translate(0, -_pTrazo.strokeWidth * 0.35);
    _pTrazo
      ..strokeWidth = 1.5
      ..color = const Color(0x88FFFFFF);
    canvas.drawPath(_labio, _pTrazo);
    canvas.restore();
  }

  static double _hash(int i) {
    final s = sin(i * 12.9898) * 43758.5453;
    return s - s.floorToDouble();
  }

  void _rollos(Canvas canvas, JuegoTuberia j, double t) {
    final im = imagenes.rollo;
    final tam = 1.05 * _ppm;
    for (final r in j.rollos) {
      if (r.agarrado) continue;
      final sx = _sx(r.x);
      if (sx < -tam || sx > _w + tam) continue;
      final bob = mov == Movimiento.nada ? 0.0 : sin(t * 3 + r.x) * 0.1;
      final sy = _sy(r.y + bob);
      final centro = Offset(sx, sy);
      if (r.dorado) {
        _pBrillo.color = Color.fromRGBO(255, 210, 40, 0.55 + 0.25 * sin(t * 8));
        canvas.drawCircle(centro, tam * 0.75, _pBrillo);
      }
      final dst = Rect.fromCenter(center: centro, width: tam, height: tam);
      if (im != null) {
        canvas.save();
        canvas.translate(sx, sy);
        if (mov != Movimiento.nada) canvas.rotate(sin(t * 2 + r.x) * 0.15);
        canvas.translate(-sx, -sy);
        canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, r.dorado ? _pDorado : _pImg);
        canvas.restore();
      } else {
        canvas.drawRect(dst.deflate(tam * 0.15), _p..color = r.dorado ? const Color(0xFFFFC21A) : const Color(0xFFF5F5F0));
      }
      if (r.dorado && imagenes.chispas != null && mov != Movimiento.nada) {
        final ch = imagenes.chispas!;
        final a = t * 2.5;
        canvas.drawImageRect(ch, Rect.fromLTWH(0, 0, ch.width.toDouble(), ch.height.toDouble()),
            Rect.fromCenter(center: centro + Offset(cos(a), sin(a)) * tam * 0.6, width: tam * 0.45, height: tam * 0.45), _pImg);
      }
    }
  }

  void _cucarachas(Canvas canvas, JuegoTuberia j, double t) {
    final im = imagenes.cucaracha;
    final tam = 0.95 * _ppm;
    for (final cu in j.cucarachas) {
      final sx0 = _sx(cu.x);
      if (sx0 < -tam * 2 || sx0 > _w + tam * 2) continue;
      final pend = atan(j.pendiente(cu.x));
      if (cu.viva) {
        final pasito = mov == Movimiento.nada ? 0.0 : sin(t * 2.2 + cu.fase) * 0.12;
        final gy = j.altura(cu.x + pasito);
        _cuerpoCucaracha(canvas, im, _sx(cu.x + pasito), _sy(gy) - tam * 0.32, -pend + (mov == Movimiento.nada ? 0 : sin(t * 22 + cu.fase) * 0.07),
            tam, 1, 1, 1);
      } else if (cu.aplastada) {
        final dt = j.tiempo - cu.muerte;
        if (dt > 3) continue;
        final a = dt < 2 ? 1.0 : 3 - dt;
        final gy = j.altura(cu.x);
        canvas.save();
        canvas.translate(_sx(cu.x), _sy(gy));
        canvas.rotate(-pend);
        canvas.drawOval(Rect.fromCenter(center: Offset(0, -2), width: tam * 1.7, height: tam * 0.32),
            _p..color = Color.fromRGBO(96, 128, 40, 0.75 * a));
        canvas.restore();
        _cuerpoCucaracha(canvas, im, _sx(cu.x), _sy(gy) - tam * 0.06, -pend, tam, 1.35, 0.22, a);
      } else {
        final dt = j.tiempo - cu.muerte;
        if (dt > 1.4) continue;
        final x = cu.x + 5 * dt, y = j.altura(cu.x) + 0.4 + 7 * dt - 9 * dt * dt;
        _cuerpoCucaracha(canvas, im, _sx(x), _sy(y), dt * 14, tam, 1, 1, (1.4 - dt) / 1.4);
      }
    }
  }

  void _cuerpoCucaracha(Canvas canvas, ui.Image? im, double x, double y, double giro, double tam, double ex, double ey, double alfa) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(giro);
    canvas.scale(ex, ey);
    // De perfil: la cabeza (arriba en el PNG) mira a la izquierda, hacia el que viene.
    canvas.rotate(-pi / 2);
    final dst = Rect.fromCenter(center: Offset.zero, width: tam, height: tam);
    if (im != null) {
      final pi_ = alfa >= 1 ? _pImg : (_pCapa..color = Color.fromRGBO(255, 255, 255, alfa.clamp(0.0, 1.0)));
      canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, pi_);
    } else {
      canvas.drawOval(dst.deflate(tam * 0.2), _p..color = Color.fromRGBO(90, 50, 40, alfa));
    }
    canvas.restore();
  }

  void _atasco(Canvas canvas, JuegoTuberia j, double t) {
    final ax = _sx(j.atascoX);
    if (ax < -60) return;
    final quieto = mov == Movimiento.nada;
    double borde(double y) => ax + (quieto ? 0 : sin(y * 0.035 + t * 4) * 7 + sin(y * 0.011 - t * 2.3) * 11);
    _tmp
      ..reset()
      ..moveTo(-20, -20);
    _borde.reset();
    for (var y = -20.0; y <= _h + 20; y += 14) {
      final x = borde(y);
      _tmp.lineTo(x, y);
      if (y < -19) {
        _borde.moveTo(x, y);
      } else {
        _borde.lineTo(x, y);
      }
    }
    _tmp
      ..lineTo(-20, _h + 20)
      ..close();
    _pAtasco.shader = ui.Gradient.linear(Offset(ax - 200, 0), Offset(ax, 0), const [Color(0xFF2E1B0E), Color(0xFF6B4226)]);
    canvas.drawPath(_tmp, _pAtasco);
    _pTrazo
      ..strokeWidth = 6
      ..color = const Color(0xFFA0703F);
    canvas.drawPath(_borde, _pTrazo);
    // Grumos en el borde.
    for (var k = 0; k < 6; k++) {
      final y = (k * 0.17 + 0.08) * _h + (quieto ? 0 : sin(t * 3 + k) * 6);
      canvas.drawCircle(Offset(borde(y) - 4, y), 7 + (k % 3) * 3, _p..color = const Color(0xFF7E5232));
    }
    // Cara furiosa a la altura del suelo.
    final e = _ppm;
    final cy = _sy(j.altura(j.atascoX) + 2.4);
    final cx = ax - 1.0 * e;
    final mira = 0.08 * e;
    for (final dx in [-0.75 * e, 0.0]) {
      final o = Offset(cx + dx, cy);
      canvas.drawCircle(o, 0.36 * e, _p..color = const Color(0xFFFFF4E0));
      canvas.drawCircle(o + Offset(mira, 0.05 * e), 0.17 * e, _p..color = const Color(0xFFD7261E));
      canvas.drawCircle(o + Offset(mira, 0.05 * e), 0.07 * e, _p..color = const Color(0xFF200505));
    }
    _pTrazo
      ..strokeWidth = 0.16 * e
      ..color = const Color(0xFF1E0F06);
    canvas.drawLine(Offset(cx - 1.15 * e, cy - 0.55 * e), Offset(cx - 0.45 * e, cy - 0.3 * e), _pTrazo);
    canvas.drawLine(Offset(cx - 0.3 * e, cy - 0.3 * e), Offset(cx + 0.4 * e, cy - 0.6 * e), _pTrazo);
    final abre = quieto ? 0.3 : 0.25 + 0.2 * (0.5 + 0.5 * sin(t * 9));
    final boca = Rect.fromCenter(center: Offset(cx - 0.35 * e, cy + 0.85 * e), width: 1.2 * e, height: abre * e + 0.15 * e);
    canvas.drawRect(boca, _p..color = const Color(0xFF1A0503));
    for (var k = 0; k < 4; k++) {
      final x = boca.left + boca.width * (k + 0.5) / 4;
      _tmp
        ..reset()
        ..moveTo(x - 0.12 * e, boca.top)
        ..lineTo(x + 0.12 * e, boca.top)
        ..lineTo(x, boca.top + 0.2 * e)
        ..close();
      canvas.drawPath(_tmp, _p..color = const Color(0xFFF2EAD0));
    }
  }

  // ================================================================ mojón

  void _mojon(Canvas canvas, JuegoTuberia j, double t, double c) {
    final a = anim;
    final tam = 1.55 * _ppm;
    final bx = _sx(j.x), by = _sy(j.y);
    // Sombra en el suelo al volar.
    if (!j.enSuelo) {
      final h = max(0.0, j.alturaSobreSuelo);
      final k = 1 / (1 + h * 0.3);
      canvas.drawOval(Rect.fromCenter(center: Offset(bx, _sy(j.altura(j.x))), width: tam * 0.9 * k, height: tam * 0.2 * k),
          _p..color = Color.fromRGBO(0, 0, 0, 0.3 * k));
    }
    if (j.enFiebre && mov != Movimiento.nada) {
      _pBrillo.color = Color.fromRGBO(255, 200, 30, 0.5 + 0.2 * sin(t * 12));
      canvas.drawCircle(Offset(bx, by - tam * 0.42), tam * 0.75, _pBrillo);
    }
    // Rayas de velocidad.
    final v = j.velocidad;
    if (v > 8.5 && mov != Movimiento.nada) {
      final al = ((v - 8.5) / 4.3).clamp(0.0, 1.0);
      _pTrazo
        ..strokeWidth = 2.5
        ..color = Color.fromRGBO(255, 255, 255, 0.55 * al);
      canvas.save();
      canvas.translate(bx, by - tam * 0.4);
      canvas.rotate(-a.inclinacion);
      for (var k = 0; k < 3; k++) {
        final y = (k - 1) * tam * 0.22;
        final largo = tam * (0.5 + 0.4 * ((t * 7 + k * 0.37) % 1.0));
        canvas.drawLine(Offset(-tam * 0.55, y), Offset(-tam * 0.55 - largo, y), _pTrazo);
      }
      canvas.restore();
    }

    canvas.save();
    canvas.translate(bx, by);
    canvas.rotate(-a.inclinacion);
    if (a.giroExtra > 0) {
      canvas.translate(0, -tam * 0.45);
      canvas.rotate(-(1 - a.giroExtra) * 2 * pi);
      canvas.translate(0, tam * 0.45);
    }
    final ap = a.aplaste;
    canvas.scale(1 + 0.75 * ap, 1 - ap);
    final im = imagenes.mojon;
    final dst = Rect.fromLTWH(-tam / 2, -0.96 * tam, tam, tam);
    if (im != null) {
      canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, _pImg);
    } else {
      canvas.drawOval(Rect.fromLTWH(-tam * 0.45, -tam * 0.85, tam * 0.9, tam * 0.85), _p..color = const Color(0xFF975747));
    }
    _cara(canvas, j, tam, t, c);
    canvas.restore();
  }

  Offset _o(double u, double v, double tam) => Offset((u - 0.5) * tam, (v - 0.96) * tam);

  void _cara(Canvas canvas, JuegoTuberia j, double tam, double t, double c) {
    final a = anim;
    const piel = Color(0xFF9A5A48);
    const pupila = Color(0xFF3B2523);
    final ojos = [_o(0.328, 0.605, tam), _o(0.668, 0.605, tam)];
    final rOjo = 0.135 * tam;
    final volando = !j.enSuelo && j.alturaSobreSuelo > 2.2;
    final pujando = a.pujo > 0.5;
    final asustado = a.susto > 0.5 && !pujando;

    if (a.mareo > 0) {
      for (final o in ojos) {
        canvas.drawCircle(o, rOjo, _p..color = const Color(0xFFF6F2F0));
        _pTrazo
          ..strokeWidth = 0.045 * tam
          ..color = pupila;
        final r = rOjo * 0.55;
        canvas.drawLine(o + Offset(-r, -r), o + Offset(r, r), _pTrazo);
        canvas.drawLine(o + Offset(-r, r), o + Offset(r, -r), _pTrazo);
      }
    } else if (a.alegria > 0 && !pujando) {
      for (final o in ojos) {
        canvas.drawCircle(o, rOjo * 1.04, _p..color = piel);
        _pTrazo
          ..strokeWidth = 0.05 * tam
          ..color = pupila;
        canvas.drawArc(Rect.fromCircle(center: o + Offset(0, rOjo * 0.3), radius: rOjo * 0.6), pi * 1.1, pi * 0.8, false, _pTrazo);
      }
    } else {
      // Pupilas que miran hacia donde va (en coordenadas del mojón, que está girado).
      final ang = a.inclinacion;
      final mx = a.mirarX * cos(ang) - a.mirarY * sin(ang);
      final my = -(a.mirarX * sin(ang) + a.mirarY * cos(ang));
      final grande = asustado ? 0.055 : 0.072;
      for (final o in ojos) {
        canvas.drawCircle(o, rOjo, _p..color = const Color(0xFFF6F2F0));
        final pc = o + Offset(mx, my) * (0.04 * tam);
        canvas.drawCircle(pc, grande * tam, _p..color = pupila);
        canvas.drawCircle(pc + Offset(-0.02 * tam, -0.022 * tam), 0.02 * tam, _p..color = const Color(0xFFFFFFFF));
        // Párpado: parpadeo o media asta al pujar.
        final lid = max(a.cerrado, pujando ? 0.42 * a.pujo : 0.0);
        if (lid > 0.02) {
          canvas.save();
          _tmp
            ..reset()
            ..addOval(Rect.fromCircle(center: o, radius: rOjo * 1.03));
          canvas.clipPath(_tmp);
          canvas.drawRect(Rect.fromLTWH(o.dx - rOjo * 1.1, o.dy - rOjo * 1.1, rOjo * 2.2, rOjo * 2.2 * lid), _p..color = piel);
          canvas.restore();
        }
      }
    }

    // Cejas.
    if (pujando || asustado) {
      _pTrazo
        ..strokeWidth = 0.055 * tam
        ..color = const Color(0xFF4A2418);
      final s = pujando ? 1.0 : -1.0; // pujando: bravas (bajan al centro); asustado: preocupadas (suben al centro)
      final l = ojos[0], r = ojos[1];
      final yb = -rOjo * 1.35;
      canvas.drawLine(l + Offset(-rOjo * 0.9, yb - s * 0.035 * tam), l + Offset(rOjo * 0.8, yb + s * 0.035 * tam), _pTrazo);
      canvas.drawLine(r + Offset(-rOjo * 0.8, yb + s * 0.035 * tam), r + Offset(rOjo * 0.9, yb - s * 0.035 * tam), _pTrazo);
    }

    // Boca.
    final boca = _o(0.498, 0.838, tam);
    if (pujando) {
      canvas.drawOval(Rect.fromCenter(center: boca, width: 0.29 * tam, height: 0.15 * tam), _p..color = piel);
      final r = Rect.fromCenter(center: boca, width: 0.27 * tam, height: 0.085 * tam);
      canvas.drawRect(r, _p..color = const Color(0xFF3A1010));
      canvas.drawRect(r.deflate(0.012 * tam), _p..color = const Color(0xFFF6F0E6));
      _pTrazo
        ..strokeWidth = 0.012 * tam
        ..color = const Color(0xFF5A3030);
      canvas.drawLine(Offset(r.left, boca.dy), Offset(r.right, boca.dy), _pTrazo);
      for (var k = 1; k < 4; k++) {
        final x = r.left + r.width * k / 4;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), _pTrazo);
      }
    } else if (volando || a.mareo > 0 || asustado) {
      canvas.drawOval(Rect.fromCenter(center: boca, width: 0.29 * tam, height: 0.15 * tam), _p..color = piel);
      final abre = asustado ? 0.08 : 0.13;
      canvas.drawOval(Rect.fromCenter(center: boca, width: 0.11 * tam, height: abre * tam), _p..color = const Color(0xFF3A1010));
    }

    // Sudor.
    if ((pujando || asustado) && mov != Movimiento.nada) {
      final ciclo = (t * 1.6) % 1.0;
      final o = _o(0.80, 0.38, tam) + Offset(0, ciclo * 0.18 * tam);
      _gota(canvas, o, 0.045 * tam, Color.fromRGBO(140, 210, 255, 1 - ciclo * 0.7));
    }
  }

  void _gota(Canvas canvas, Offset c, double r, Color color) {
    _tmp
      ..reset()
      ..moveTo(c.dx, c.dy - r * 2.2)
      ..quadraticBezierTo(c.dx + r * 1.1, c.dy - r * 0.6, c.dx + r, c.dy)
      ..arcToPoint(Offset(c.dx - r, c.dy), radius: Radius.circular(r))
      ..quadraticBezierTo(c.dx - r * 1.1, c.dy - r * 0.6, c.dx, c.dy - r * 2.2)
      ..close();
    canvas.drawPath(_tmp, _p..color = color);
  }

  // ================================================================ partículas y textos

  void _particulas(Canvas canvas) {
    for (final p in efectos.particulas) {
      if (!p.viva) continue;
      final al = (1 - p.vida / p.total).clamp(0.0, 1.0);
      final x = _sx(p.x), y = _sy(p.y);
      final s = max(1.5, p.tam * _ppm);
      _p.color = p.color.withValues(alpha: p.color.a * al);
      switch (p.forma) {
        case FormaParticula.cuadro:
          canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: s, height: s), _p);
        case FormaParticula.gota:
          canvas.drawCircle(Offset(x, y), s * 0.5, _p);
        case FormaParticula.papel:
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(p.giro);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 1.4, height: s * 0.6 * cos(p.giro * 1.7).abs() + 1), _p);
          canvas.restore();
        case FormaParticula.chispa:
          _pTrazo
            ..strokeWidth = max(1.5, s * 0.35)
            ..color = _p.color;
          canvas.drawLine(Offset(x, y), Offset(x - p.vx * 0.035 * _ppm, y + p.vy * 0.035 * _ppm), _pTrazo);
      }
    }
  }

  void _textosFlotantes(Canvas canvas) {
    for (final tf in efectos.textos) {
      final u = (tf.vida / tf.total).clamp(0.0, 1.0);
      final sube = 46 * (1 - pow(1 - u, 3));
      final esc = u < 0.12 ? 0.5 + u / 0.12 * 0.75 : (u < 0.25 ? 1.25 - (u - 0.12) / 0.13 * 0.25 : 1.0);
      final x = _sx(tf.x), y = _sy(tf.y) - sube;
      final w = tf.borde.width, h = tf.borde.height;
      final desvanece = u > 0.7;
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(esc);
      if (desvanece) {
        canvas.saveLayer(Rect.fromLTWH(-w, -h, w * 2, h * 2), _pCapa..color = Color.fromRGBO(0, 0, 0, (1 - u) / 0.3));
      }
      tf.borde.paint(canvas, Offset(-w / 2, -h / 2));
      tf.relleno.paint(canvas, Offset(-tf.relleno.width / 2, -tf.relleno.height / 2));
      if (desvanece) canvas.restore();
      canvas.restore();
    }
  }

  // ================================================================ avisos

  TextPainter _texto(String s, double tam, Color color, {FontWeight peso = FontWeight.w900}) {
    final clave = '$s|$tam|${color.toARGB32()}';
    final hecho = _textos[clave];
    if (hecho != null) return hecho;
    if (_textos.length > 120) _textos.clear();
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: tam, fontWeight: peso, color: color, letterSpacing: 1, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    return _textos[clave] = tp;
  }

  void _tiraAtasco(Canvas canvas, JuegoTuberia j, double c, double t) {
    final ancho = 6 + 22 * c;
    final col = Color.lerp(const Color(0xFF6B4226), const Color(0xFFE5482E), c)!;
    final pulso = c > 0.6 && mov != Movimiento.nada ? 0.75 + 0.25 * sin(t * 12) : 1.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, ancho, _h), _p..color = col.withValues(alpha: 0.9 * pulso));
    canvas.drawRect(Rect.fromLTWH(ancho, 0, 2, _h), _p..color = const Color(0xFF1E0F06));
    final sep = max(0, j.separacion).floor();
    if (sep > 24 && c < 0.05) return;
    final rotulo = _texto(tr('ATASCO', 'CLOG'), 10, const Color(0xFFFFFFFF));
    final metros = _texto('$sep m', 16, const Color(0xFFFFFFFF));
    final bw = max(rotulo.width, metros.width) + 14;
    final bh = rotulo.height + metros.height + 14;
    final r = Rect.fromLTWH(ancho + 6, _h * 0.62, bw, bh);
    canvas.drawRect(r, _p..color = Color.lerp(const Color(0xE0201008), const Color(0xF0B0261A), c)!);
    _pTrazo
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFFFFFFFF);
    canvas.drawRect(r, _pTrazo);
    _pTrazo.strokeCap = StrokeCap.round;
    rotulo.paint(canvas, Offset(r.left + 7, r.top + 6));
    metros.paint(canvas, Offset(r.left + 7, r.top + 8 + rotulo.height));
  }

  void _pistas(Canvas canvas, JuegoTuberia j, double t) {
    if (j.tiempo > 16 || !j.vivo) return;
    String? s;
    final p = j.pendiente(j.x + 0.5);
    if (j.enSuelo && !j.pesado && p < -0.15) s = tr('MANTÉN', 'HOLD');
    if (j.enSuelo && j.pesado && p > 0.2) s = tr('SUELTA', 'RELEASE');
    if (s == null) return;
    final tp = _texto(s, 22, const Color(0xFF171513));
    final x = _sx(j.x), y = _sy(j.y) - 2.6 * _ppm + (mov == Movimiento.nada ? 0 : sin(t * 8) * 4);
    final r = Rect.fromCenter(center: Offset(x, y), width: tp.width + 22, height: tp.height + 14);
    canvas.drawRect(r, _p..color = const Color(0xFFFFD60A));
    _pTrazo
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFF171513);
    canvas.drawRect(r, _pTrazo);
    _pTrazo.strokeCap = StrokeCap.round;
    tp.paint(canvas, Offset(r.left + 11, r.top + 7));
    _tmp
      ..reset()
      ..moveTo(x - 7, r.bottom)
      ..lineTo(x + 7, r.bottom)
      ..lineTo(x, r.bottom + 8)
      ..close();
    canvas.drawPath(_tmp, _p..color = const Color(0xFF171513));
  }

  @override
  bool shouldRepaint(PintorTuberia old) =>
      old.juego != juego || old.oscuro != oscuro || old.mov != mov || old.imagenes != imagenes || old.efectos != efectos;
}
