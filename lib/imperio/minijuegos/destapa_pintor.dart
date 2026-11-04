// Destapa, el dibujo: un solo CustomPainter para el baño del estadio. El fondo (azulejos, piso, espejo, secador,
// puerta a la tribuna) se graba una vez en un ui.Picture; encima va lo que se mueve: la tribuna, el tubo de luz que
// parpadea, la mosca, los inodoros con su agua, los atascos vivos, el destapador y los efectos.
// La vista le pasa el tiempo con [PintorDestapa.avanzar] y los sucesos con [PintorDestapa.reaccionar].

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../idioma.dart';
import 'destapa_efectos.dart';
import 'destapa_logica.dart';

/// Dibujos (PNG de emoji) que usa el juego. Cualquiera puede faltar: entonces se pinta una forma simple.
class ImagenesDestapa {
  ui.Image? mojon, destapador, patito, celular, cucaracha, corona, sudor, mosca;
}

/// Estado de animación de un inodoro (lo que no es de la lógica: golpes, remolino, entrada a la fila).
class AnimoInodoro {
  AnimoInodoro({bool nuevo = false}) : entrada = nuevo ? 0 : 1;

  /// Centro y tamaño actuales (se acercan al destino cuando la fila se reacomoda).
  double x = -1, u = 0;
  double entrada;
  double golpe = 0, remolino = 0, desborde = 0, nace = 1, hundido = 0, recupera = 0, charco = 1;
  TipoAtasco? sale;
}

class _Hincha {
  _Hincha(this.x, this.fila, this.camisa, this.piel, this.fase);
  final double x, fase;
  final int fila;
  final Color camisa, piel;
}

const _aguaLimpia = Color(0xFF5BC0EB);
const _aguaSucia = Color(0xFF8A6E3B);
const _acento = Color(0xFFFFD60A);
const _rojo = Color(0xFFE5383B);
const _cafe = Color(0xFF3B2412);

/// La letra del tema en Android (sin familia, las pruebas pintan cajitas).
const letraDestapa = 'Roboto';

class PintorDestapa extends CustomPainter {
  PintorDestapa({required this.juego, required this.ef, required this.imgs, required Listenable tic}) : super(repaint: tic) {
    final r = Random(7);
    const camisas = [Color(0xFFE63946), Color(0xFFF1FAEE), Color(0xFF1D5FAD), Color(0xFFFFD60A), Color(0xFF2A9D8F)];
    const pieles = [Color(0xFFF1C27D), Color(0xFFC68642), Color(0xFF8D5524), Color(0xFFFFDBAC)];
    for (var f = 0; f < 3; f++) {
      final n = 11 + f * 2;
      for (var k = 0; k < n; k++) {
        _hinchas.add(_Hincha((k + 0.5 + (r.nextDouble() - 0.5) * 0.5) / n, f, camisas[r.nextInt(camisas.length)],
            pieles[r.nextInt(pieles.length)], r.nextDouble() * 6));
      }
    }
    _pistas = {
      TipoAtasco.gordo: _rotulo(tr('¡DALE DURO!', 'SMASH IT!')),
      TipoAtasco.patito: _rotulo(tr('¡DESLIZA ↑!', 'SWIPE ↑!')),
      TipoAtasco.celular: _rotulo(tr('¡MANTÉN!', 'HOLD!')),
      TipoAtasco.cucaracha: _rotulo(tr('¡APLÁSTALA!', 'SQUASH IT!')),
    };
  }

  final JuegoDestapa juego;
  final EfectosDestapa ef;
  ImagenesDestapa imgs;

  /// Tema oscuro (la vista lo pone en build; cambia los azulejos y la porcelana).
  bool oscuro = false;

  final animos = <AnimoInodoro>[];
  final _hinchas = <_Hincha>[];
  late final Map<TipoAtasco, TextPainter> _pistas;

  /// Tribuna: festeja los combos y abuchea los desbordes (de 1 a 0).
  double celebra = 0, abucheo = 0;

  Size _tam = Size.zero;
  ui.Picture? _fondo;
  bool _fondoOscuro = false;

  final _p = Paint();
  final _t = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final _img = Paint()..filterQuality = FilterQuality.medium;
  final _camino = Path();
  final _camino2 = Path();
  static const _tinteGordo = ColorFilter.mode(Color(0x66401808), BlendMode.srcATop);

  static TextPainter _rotulo(String s) => TextPainter(
        text: TextSpan(text: s, style: const TextStyle(fontFamily: letraDestapa, color: Color(0xFF111111), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        textDirection: TextDirection.ltr,
      )..layout();

  // ---------- Geometría ----------

  double get _yb => _tam.height * 0.84;
  double get _piso => _tam.height * 0.60;
  Rect get puerta => Rect.fromLTRB(_tam.width * 0.05, _tam.height * 0.13, _tam.width * 0.43, _tam.height * 0.47);

  (double, double) _destino(int i, int n) {
    final slot = _tam.width / n;
    return (slot * (i + 0.5), min(0.78 * slot, 0.19 * _tam.height));
  }

  void _sincronizar() {
    while (animos.length < juego.inodoros.length) {
      animos.add(AnimoInodoro(nuevo: animos.isNotEmpty && ef.anima));
    }
    if (_tam == Size.zero) return;
    final n = juego.inodoros.length;
    for (var i = 0; i < animos.length; i++) {
      final a = animos[i];
      if (a.x < 0) {
        final d = _destino(i, n);
        a.x = d.$1;
        a.u = d.$2;
      }
    }
  }

  /// Qué inodoro hay bajo el dedo (por columnas: toda la franja cuenta).
  int inodoroEn(Offset p) {
    final n = juego.inodoros.length;
    if (_tam == Size.zero || n == 0) return -1;
    return (p.dx / (_tam.width / n)).floor().clamp(0, n - 1);
  }

  /// Centro de la boca del inodoro [i] en pantalla.
  Offset boca(int i) {
    if (i < 0 || i >= animos.length) return Offset(_tam.width / 2, _tam.height / 2);
    final a = animos[i];
    return Offset(a.x, _yb - 0.86 * a.u);
  }

  double _u(int i) => i >= 0 && i < animos.length ? animos[i].u : 60;

  Color _colorAgua(Inodoro ino) => Color.lerp(_aguaLimpia, _aguaSucia, ino.tapado ? 0.25 + 0.75 * ino.agua.clamp(0.0, 1.0) : 0)!;

  // ---------- Tiempo y sucesos ----------

  void avanzar(double dt) {
    _sincronizar();
    final n = juego.inodoros.length;
    for (var i = 0; i < animos.length; i++) {
      final a = animos[i];
      if (_tam != Size.zero) {
        final (tx, tu) = _destino(i, n);
        final k = ef.anima ? min(1.0, dt * 6) : 1.0;
        a.x += (tx - a.x) * k;
        a.u += (tu - a.u) * k;
      }
      a.entrada = ef.anima ? min(1, a.entrada + dt * 1.8) : 1;
      a.golpe = max(0, a.golpe - dt * 5);
      a.remolino = max(0, a.remolino - dt * 1.4);
      a.desborde = max(0, a.desborde - dt * 0.8);
      a.nace = min(1, a.nace + dt * 4);
      a.hundido = max(0, a.hundido - dt * 3);
      a.recupera = max(0, a.recupera - dt * 4);
      a.charco = min(1, a.charco + dt * 1.5);
    }
    celebra = max(0, celebra - dt * 0.55);
    abucheo = max(0, abucheo - dt * 0.6);
  }

  void reaccionar(Evento e) {
    _sincronizar();
    final i = e.inodoro;
    final a = i >= 0 && i < animos.length ? animos[i] : null;
    final u = _u(i);
    final b = boca(i);
    final arriba = Offset(b.dx, b.dy - u * 0.75);
    final ino = i >= 0 && i < juego.inodoros.length ? juego.inodoros[i] : null;
    switch (e.suceso) {
      case Suceso.atasco:
        a?.nace = ef.anima ? 0 : 1;
        if (ino != null) ef.salpicar(b, _colorAgua(ino), 6, fuerza: 110, arriba: 120, tam: 4);
        if (e.dorado) ef.salpicar(arriba, _acento, 12, fuerza: 220, arriba: 60, tam: 4, redonda: false, gravedad: 200);
      case Suceso.golpe:
        a?.golpe = 1;
        if (ino != null) ef.salpicar(b, _colorAgua(ino), e.tipo == TipoAtasco.gordo ? 7 : 5, fuerza: 170, arriba: 170, tam: 4.5);
      case Suceso.golpeVacio:
        a?.golpe = 0.7;
        if (e.tipo == TipoAtasco.patito) {
          a?.recupera = 1;
          ef.letrero(tr('¡CUAC!', 'QUACK!'), arriba, const Color(0xFFFFFFFF), tam: 14, dura: 0.6);
        }
      case Suceso.recupera:
        a?.recupera = 1;
      case Suceso.destapado:
        a?.remolino = ef.anima ? 1 : 0;
        a?.sale = e.tipo;
        ef.letrero('+${e.valor}', arriba, e.dorado ? _acento : const Color(0xFFFFFFFF), tam: e.dorado ? 30 : 22);
        ef.salpicar(b, e.dorado ? _acento : const Color(0xFFBFEFFF), e.dorado ? 26 : 14,
            fuerza: 240, arriba: 160, tam: 4, redonda: !e.dorado, gravedad: 400);
        if (e.dorado) ef.destello(_acento, 0.35);
        ef.sacudir(e.tipo == TipoAtasco.gordo ? 6 : 2.5);
        celebra = max(celebra, e.dorado ? 0.8 : 0.3);
        switch (e.tipo) {
          case TipoAtasco.patito:
            final d = puerta.center;
            ef.volar(imgs.patito, b.translate(0, -u * 0.2), Offset((d.dx - b.dx) / 0.9, (d.dy - b.dy) / 0.9 - 200),
                tam: u * 0.46, vgiro: 7, gravedad: 440, total: 0.9, crece: -u * 0.35, color: _acento);
          case TipoAtasco.celular:
            ef.volar(imgs.celular, b.translate(0, -u * 0.25), Offset((b.dx < _tam.width / 2 ? 1 : -1) * 140, -760),
                tam: u * 0.40, vgiro: 9, gravedad: 1300, total: 1.1, color: const Color(0xFF333344));
          case TipoAtasco.cucaracha:
            ef.mancha(b.translate(0, u * 0.1), u * 0.42);
            ef.letrero(tr('¡PLAF!', 'SPLAT!'), arriba, const Color(0xFFFFFFFF), tam: 16, dura: 0.6);
          default:
            break;
        }
      case Suceso.desborde:
        a?.desborde = 1;
        a?.charco = ef.anima ? 0 : 1;
        ef.salpicar(b, _aguaSucia, 26, fuerza: 300, arriba: 180, tam: 6, gravedad: 900);
        ef.sacudir(10);
        ef.destello(_rojo, 0.7);
        ef.letrero(tr('¡SE DESBORDÓ!', 'OVERFLOW!'), arriba, _rojo, tam: 18, fondo: const Color(0xFF111111), dura: 1.2);
        abucheo = 1;
        ef.letrero(tr('¡BUUU!', 'BOOO!'), puerta.center, const Color(0xFFFFFFFF), tam: 20, dura: 1.0);
      case Suceso.hundido:
        a?.hundido = 1;
        if (ino != null) ef.salpicar(b, _colorAgua(ino), 5, fuerza: 120, arriba: 100, tam: 4);
        ef.letrero(tr('¡MANTÉN!', 'HOLD!'), arriba, _acento, tam: 15, dura: 0.7);
      case Suceso.escapa:
        ef.volar(imgs.cucaracha, b.translate(u * 0.45, 0), const Offset(260, -380),
            tam: u * 0.26, vgiro: 12, gravedad: 900, total: 0.9, color: _cafe);
        ef.letrero(tr('¡SE ESCAPÓ!', 'IT GOT AWAY!'), arriba, const Color(0xFFFFFFFF), tam: 16, fondo: const Color(0xFF111111));
        abucheo = max(abucheo, 0.7);
      case Suceso.combo:
        celebra = 1;
        ef.letrero('x${e.valor}', Offset(_tam.width / 2, _tam.height * 0.40), _acento, tam: 44, dura: 1.1);
        ef.destello(_acento, 0.3);
        _confeti(30);
      case Suceso.comboRoto:
        ef.letrero(tr('COMBO PERDIDO', 'COMBO LOST'), Offset(_tam.width / 2, _tam.height * 0.40), const Color(0xFFDDDDDD), tam: 16);
      case Suceso.nuevoInodoro:
        ef.letrero(tr('¡OTRO INODORO!', 'ANOTHER TOILET!'), Offset(_tam.width / 2, _tam.height * 0.40), _acento,
            tam: 20, fondo: const Color(0xFF111111), dura: 1.3);
      case Suceso.prorroga:
        celebra = 1;
        ef.destello(const Color(0xFFFFFFFF), 0.5);
        _confeti(40);
      case Suceso.alerta:
        ef.letrero('!', arriba, _rojo, tam: 26, dura: 0.6);
      case Suceso.fin:
        abucheo = 1;
      case Suceso.glug:
        break;
    }
  }

  void _confeti(int n) {
    final p = Offset(puerta.center.dx, puerta.top + puerta.height * 0.45);
    for (final c in const [Color(0xFFE63946), Color(0xFFFFD60A), Color(0xFF1D5FAD), Color(0xFFFFFFFF)]) {
      ef.salpicar(p, c, n ~/ 4, fuerza: 260, arriba: 220, tam: 5, redonda: false, gravedad: 260, abanico: pi * 1.2);
    }
  }

  // ---------- Pintar ----------

  @override
  void paint(Canvas canvas, Size size) {
    if (size != _tam) {
      _tam = size;
      _fondo?.dispose();
      _fondo = null;
    }
    if (_fondo == null || _fondoOscuro != oscuro) {
      _fondo?.dispose();
      _fondo = _grabarFondo(size);
      _fondoOscuro = oscuro;
    }
    _sincronizar();
    final sac = ef.sacudida;
    canvas.save();
    canvas.translate(sac.dx * 0.4, sac.dy * 0.4);
    canvas.drawPicture(_fondo!);
    _tribuna(canvas);
    _espejo(canvas);
    _tubo(canvas);
    _mosca(canvas);
    canvas.restore();
    canvas.save();
    canvas.translate(sac.dx, sac.dy);
    for (var i = 0; i < juego.inodoros.length && i < animos.length; i++) {
      _charcos(canvas, juego.inodoros[i], animos[i], i);
    }
    _divisiones(canvas);
    for (var i = 0; i < juego.inodoros.length && i < animos.length; i++) {
      _inodoro(canvas, juego.inodoros[i], animos[i], i);
    }
    ef.pintarManchas(canvas);
    canvas.restore();
    ef.pintar(canvas);
    final luz = _brillo();
    if (luz < 0.99) {
      _p.color = Color.fromRGBO(0, 0, 0, (1 - luz) * 0.18);
      canvas.drawRect(Offset.zero & size, _p);
    }
    ef.pintarDestello(canvas, size);
  }

  // Parpadeo del tubo: casi siempre prendido, a ratos baja.
  double _brillo() {
    if (!ef.anima) return 1;
    final h = ((ef.fase * 12).floor() * 2654435761) & 0xFFFF;
    if (h % 29 == 0) return 0.25;
    if (h % 43 == 0) return 0.6;
    return 1;
  }

  ui.Picture _grabarFondo(Size s) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final w = s.width, h = s.height, piso = _piso;
    final p = Paint();
    final pared = oscuro ? const Color(0xFF2B3A3A) : const Color(0xFFDDE9E4);
    final junta = oscuro ? const Color(0xFF1E2828) : const Color(0xFFB9CBC4);
    c.drawRect(Rect.fromLTWH(0, 0, w, piso), p..color = pared);
    // Azulejos con alguno más claro u oscuro.
    final lado = w / 9;
    final r = Random(3);
    for (var y = 0.0; y < piso; y += lado) {
      for (var x = 0.0; x < w; x += lado) {
        final v = r.nextDouble();
        if (v < 0.12) c.drawRect(Rect.fromLTWH(x, y, lado, lado), p..color = Color.lerp(pared, const Color(0xFFFFFFFF), oscuro ? 0.04 : 0.35)!);
        if (v > 0.93) c.drawRect(Rect.fromLTWH(x, y, lado, lado), p..color = Color.lerp(pared, junta, 0.35)!);
      }
    }
    p
      ..color = junta
      ..strokeWidth = 1.5;
    for (var y = 0.0; y < piso; y += lado) {
      c.drawLine(Offset(0, y), Offset(w, y), p);
    }
    for (var x = 0.0; x < w; x += lado) {
      c.drawLine(Offset(x, 0), Offset(x, piso), p);
    }
    // Franja con los colores del equipo encima del zócalo.
    c.drawRect(Rect.fromLTWH(0, piso - lado * 0.55, w, lado * 0.22), p..color = const Color(0xFF1D5FAD));
    c.drawRect(Rect.fromLTWH(0, piso - lado * 0.33, w, lado * 0.12), p..color = const Color(0xFFE63946));
    // Piso con fuga al centro.
    final suelo = oscuro ? const Color(0xFF3A3530) : const Color(0xFFC9C2B6);
    c.drawRect(Rect.fromLTWH(0, piso, w, h - piso), p..color = suelo);
    p
      ..color = oscuro ? const Color(0xFF2C2824) : const Color(0xFFB0A898)
      ..strokeWidth = 1.2;
    final fuga = Offset(w / 2, piso - h * 0.9);
    for (var k = -6; k <= 14; k++) {
      final xb = w / 2 + (k - 4) * w / 6;
      final t = (piso - fuga.dy) / (h - fuga.dy);
      c.drawLine(Offset(fuga.dx + (xb - fuga.dx) * t, piso), Offset(xb, h), p);
    }
    for (var k = 1; k < 8; k++) {
      final y = piso + (h - piso) * pow(k / 8, 1.5);
      c.drawLine(Offset(0, y), Offset(w, y), p);
    }
    c.drawRect(Rect.fromLTWH(0, piso, w, 3), p..color = oscuro ? const Color(0xFF151A1A) : const Color(0xFF8E9C96));
    // Sumidero.
    c.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.965), width: 34, height: 9), p..color = const Color(0xFF6F6A62));
    // Puerta abierta a la tribuna: cielo de noche, reflectores, gradas y cancha.
    final pt = puerta;
    c.save();
    c.clipRect(pt);
    c.drawRect(pt, p..shader = ui.Gradient.linear(pt.topCenter, pt.bottomCenter, const [Color(0xFF0B1630), Color(0xFF2A4A86)]));
    p.shader = null;
    for (final fx in const [0.18, 0.82]) {
      final x = pt.left + pt.width * fx;
      final top = pt.top + pt.height * 0.08;
      c.drawRect(Rect.fromLTWH(x - 2, top, 4, pt.height * 0.35), p..color = const Color(0xFF1B2440));
      final foco = Rect.fromCenter(center: Offset(x, top), width: pt.width * 0.22, height: pt.height * 0.08);
      c.drawCircle(foco.center, pt.width * 0.28,
          p..shader = ui.Gradient.radial(foco.center, pt.width * 0.28, const [Color(0x88FFF6D0), Color(0x00FFF6D0)]));
      p.shader = null;
      c.drawRect(foco, p..color = const Color(0xFFFFF8E0));
    }
    final grada = pt.top + pt.height * 0.40;
    c.drawRect(Rect.fromLTRB(pt.left, grada, pt.right, pt.bottom), p..color = const Color(0xFF232B3E));
    for (var f = 0; f < 4; f++) {
      c.drawRect(Rect.fromLTWH(pt.left, grada + f * pt.height * 0.095, pt.width, 2), p..color = const Color(0xFF39445E));
    }
    final cancha = pt.top + pt.height * 0.80;
    c.drawRect(Rect.fromLTRB(pt.left, cancha, pt.right, pt.bottom), p..color = const Color(0xFF2E8B3A));
    for (var k = 0; k < 6; k += 2) {
      c.drawRect(Rect.fromLTWH(pt.left + k * pt.width / 6, cancha, pt.width / 6, pt.bottom - cancha), p..color = const Color(0xFF339A41));
    }
    c.drawRect(Rect.fromLTWH(pt.left, cancha + 3, pt.width, 2), p..color = const Color(0xCCFFFFFF));
    c.restore();
    // Marco y hoja de la puerta.
    final marco = oscuro ? const Color(0xFF151B1E) : const Color(0xFF55636B);
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = marco;
    c.drawRect(pt.inflate(3), p);
    p.style = PaintingStyle.fill;
    final hoja = Path()
      ..moveTo(pt.left - 6, pt.top - 6)
      ..lineTo(pt.left - w * 0.045, pt.top - 14)
      ..lineTo(pt.left - w * 0.045, pt.bottom + 14)
      ..lineTo(pt.left - 6, pt.bottom + 6)
      ..close();
    c.drawPath(hoja, p..color = oscuro ? const Color(0xFF3A4A70) : const Color(0xFF5677B0));
    // Letrero sobre la puerta.
    final letrero = TextPainter(
      text: TextSpan(text: tr('A LA TRIBUNA', 'TO THE STANDS'), style: const TextStyle(fontFamily: letraDestapa, color: Color(0xFFFFFFFF), fontSize: 9, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final cartel = Rect.fromCenter(center: Offset(pt.center.dx, pt.top - 14), width: letrero.width + 12, height: letrero.height + 4);
    c.drawRect(cartel, p..color = const Color(0xFF1F8A4C));
    letrero.paint(c, Offset(cartel.left + 6, cartel.top + 2));
    // Espejo (el brillo que pasa va aparte).
    final esp = _rectEspejo;
    c.drawRect(esp.inflate(5), p..color = oscuro ? const Color(0xFF6B7680) : const Color(0xFF9AA6AE));
    c.drawRect(esp, p..shader = ui.Gradient.linear(esp.topLeft, esp.bottomRight, oscuro
        ? const [Color(0xFF4C6170), Color(0xFF2E3D48)]
        : const [Color(0xFFD9ECF4), Color(0xFF9FC1D1)]));
    p.shader = null;
    _camino
      ..reset()
      ..moveTo(esp.left + esp.width * 0.10, esp.bottom)
      ..lineTo(esp.left + esp.width * 0.28, esp.top)
      ..lineTo(esp.left + esp.width * 0.34, esp.top)
      ..lineTo(esp.left + esp.width * 0.16, esp.bottom)
      ..close();
    c.drawPath(_camino, p..color = const Color(0x40FFFFFF));
    // Secador de manos.
    final sec = Rect.fromLTWH(w * 0.70, h * 0.335, w * 0.16, h * 0.065);
    c.drawRect(sec, p..color = oscuro ? const Color(0xFF8B969E) : const Color(0xFFCFD6DB));
    c.drawRect(Rect.fromLTWH(sec.left, sec.top, sec.width, 3), p..color = const Color(0xFFFFFFFF));
    c.drawRect(Rect.fromLTWH(sec.center.dx - sec.width * 0.12, sec.bottom, sec.width * 0.24, sec.height * 0.35), p..color = const Color(0xFF6E7880));
    c.drawCircle(Offset(sec.right - 8, sec.top + 9), 3, p..color = _rojo);
    // Pinta de hinchas en la pared.
    final pinta = TextPainter(
      text: TextSpan(text: tr('¡VAMOS!', 'GO TEAM!'), style: TextStyle(fontFamily: letraDestapa, color: const Color(0xFFE63946).withValues(alpha: 0.55), fontSize: 15, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(w * 0.50, h * 0.345);
    c.rotate(-0.12);
    pinta.paint(c, Offset.zero);
    c.restore();
    // Lámpara del tubo (el tubo encendido va aparte).
    c.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.085), width: w * 0.40, height: 9), p..color = const Color(0xFF4A5258));
    return rec.endRecording();
  }

  Rect get _rectEspejo => Rect.fromLTRB(_tam.width * 0.52, _tam.height * 0.135, _tam.width * 0.95, _tam.height * 0.30);

  void _tribuna(Canvas c) {
    final pt = puerta;
    c.save();
    c.clipRect(pt);
    final f = ef.fase;
    final vaiven = ef.anima ? sin(f * 0.4) * 3 : 0.0;
    final grada = pt.top + pt.height * 0.40;
    final fila = pt.height * 0.095;
    final celebrando = celebra > 0.25;
    for (final hc in _hinchas) {
      final radio = fila * (0.26 + hc.fila * 0.04);
      var x = pt.left + hc.x * pt.width + vaiven;
      var y = grada + fila * (hc.fila + 0.62);
      if (ef.anima) {
        y -= (sin(f * (3 + hc.fase * 0.3) + hc.fase * 7) * 0.5 + 0.5) * (0.6 + celebra * 5);
        x += sin(f * 28 + hc.fase * 5) * abucheo * 1.6;
      }
      _p.color = hc.camisa;
      c.drawRect(Rect.fromLTWH(x - radio, y + radio * 0.6, radio * 2, radio * 1.6), _p);
      _p.color = hc.piel;
      c.drawCircle(Offset(x, y), radio, _p);
      if (celebrando && hc.fase > 2.5) {
        _t
          ..color = hc.piel
          ..strokeWidth = max(1.5, radio * 0.5);
        final alto = radio * (1.4 + celebra);
        c.drawLine(Offset(x - radio, y + radio * 0.8), Offset(x - radio * 1.4, y - alto), _t);
        c.drawLine(Offset(x + radio, y + radio * 0.8), Offset(x + radio * 1.4, y - alto), _t);
      }
    }
    // Bandera que ondea.
    final asta = Offset(pt.left + pt.width * 0.62 + vaiven, grada - 2);
    _t
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 1.5;
    c.drawLine(asta, asta.translate(0, -pt.height * 0.22), _t);
    _camino.reset();
    final ancho = pt.width * 0.22, alto = pt.height * 0.09;
    final top = asta.dy - pt.height * 0.22;
    for (var k = 0; k <= 8; k++) {
      final t = k / 8;
      final o = ef.anima ? sin(f * 6 - t * 5) * alto * 0.18 * t : 0;
      final p = Offset(asta.dx + t * ancho, top + o);
      k == 0 ? _camino.moveTo(p.dx, p.dy) : _camino.lineTo(p.dx, p.dy);
    }
    for (var k = 8; k >= 0; k--) {
      final t = k / 8;
      final o = ef.anima ? sin(f * 6 - t * 5) * alto * 0.18 * t : 0;
      _camino.lineTo(asta.dx + t * ancho, top + alto + o);
    }
    _camino.close();
    _p.color = const Color(0xFFE63946);
    c.drawPath(_camino, _p);
    // Flashes de cámaras en la grada.
    if (ef.anima) {
      for (var k = 0; k < 3; k++) {
        final h = (((f * 7).floor() + k * 31) * 2654435761) & 0xFFFF;
        if (h % 4 != 0) continue;
        final px = pt.left + (h % 97) / 97 * pt.width;
        final py = grada + ((h >> 7) % 23) / 23 * pt.height * 0.36;
        _p.color = const Color(0xDDFFFFFF);
        c.drawCircle(Offset(px, py), 2.2, _p);
      }
    }
    // En la prórroga ya hay jugadores en la cancha.
    if (juego.prorroga) {
      final cancha = pt.top + pt.height * 0.86;
      for (var k = 0; k < 6; k++) {
        final x = pt.left + ((ef.anima ? f * (0.05 + k * 0.013) : 0) + k * 0.17) % 1 * pt.width;
        _p.color = k.isEven ? const Color(0xFFE63946) : const Color(0xFFFFFFFF);
        c.drawRect(Rect.fromLTWH(x, cancha + (k % 3) * 3, 3, 5), _p);
      }
    }
    c.restore();
  }

  void _espejo(Canvas c) {
    if (!ef.anima) return;
    final esp = _rectEspejo;
    final t = (ef.fase * 0.22) % 1.6 - 0.3;
    final x = esp.left + t * esp.width;
    c.save();
    c.clipRect(esp);
    _camino2
      ..reset()
      ..moveTo(x, esp.bottom)
      ..lineTo(x + esp.width * 0.18, esp.top)
      ..lineTo(x + esp.width * 0.30, esp.top)
      ..lineTo(x + esp.width * 0.12, esp.bottom)
      ..close();
    _p.color = const Color(0x33FFFFFF);
    c.drawPath(_camino2, _p);
    c.restore();
  }

  void _tubo(Canvas c) {
    final w = _tam.width, h = _tam.height;
    final b = _brillo();
    final tubo = Rect.fromCenter(center: Offset(w * 0.5, h * 0.085 + 6), width: w * 0.35, height: 5);
    _p.color = Color.fromRGBO(255, 250, 225, 0.18 * b);
    c.drawRect(tubo.inflate(8), _p);
    _p.color = Color.lerp(const Color(0xFF8A8F80), const Color(0xFFFFFDF0), b)!;
    c.drawRect(tubo, _p);
  }

  void _mosca(Canvas c) {
    final f = ef.anima ? ef.fase : 0.0;
    final w = _tam.width, h = _tam.height;
    final x = w * (0.55 + 0.36 * sin(f * 0.7));
    final y = h * (0.34 + 0.10 * sin(f * 1.3 + 1));
    final vx = cos(f * 0.7) * 0.7, vy = cos(f * 1.3 + 1) * 1.3 * 0.3;
    final tam = max(14.0, w * 0.04);
    c.save();
    c.translate(x, y);
    c.rotate(atan2(vy, vx) + pi / 2);
    final img = imgs.mosca;
    if (img != null) {
      _img.color = const Color(0xFF000000);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCenter(center: Offset.zero, width: tam, height: tam), _img);
    } else {
      _p.color = const Color(0xFF222222);
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: tam * 0.35, height: tam * 0.5), _p);
    }
    if (ef.anima && (f * 30).floor().isEven) {
      _p.color = const Color(0x55FFFFFF);
      c.drawOval(Rect.fromCenter(center: Offset(-tam * 0.3, -tam * 0.05), width: tam * 0.45, height: tam * 0.25), _p);
      c.drawOval(Rect.fromCenter(center: Offset(tam * 0.3, -tam * 0.05), width: tam * 0.45, height: tam * 0.25), _p);
    }
    c.restore();
  }

  void _divisiones(Canvas c) {
    final color = oscuro ? const Color(0xFF3D4C55) : const Color(0xFF7D8F99);
    for (var i = 0; i + 1 < animos.length; i++) {
      final a = animos[i], b = animos[i + 1];
      if (a.entrada < 1 || b.entrada < 1) continue;
      final x = (a.x + b.x) / 2;
      final u = min(a.u, b.u);
      final top = _yb - 1.45 * u, abajo = _yb - 0.10 * u;
      _p.color = color;
      c.drawRect(Rect.fromLTRB(x - u * 0.035, top, x + u * 0.035, abajo), _p);
      _p.color = const Color(0x33FFFFFF);
      c.drawRect(Rect.fromLTRB(x - u * 0.035, top, x - u * 0.01, abajo), _p);
      _p.color = const Color(0xFF9AA4AA);
      c.drawRect(Rect.fromLTRB(x - u * 0.02, abajo, x + u * 0.02, _yb + 0.04 * u), _p);
    }
  }

  void _charcos(Canvas c, Inodoro ino, AnimoInodoro a, int i) {
    if (ino.charcos == 0) return;
    final u = a.u;
    for (var k = 0; k < ino.charcos; k++) {
      final crece = k == ino.charcos - 1 ? Curves.easeOut.transform(a.charco) : 1.0;
      final x = a.x + (((k * 0.37 + i * 0.21) % 1) - 0.5) * 0.8 * u;
      final y = _yb + 0.05 * u + (k % 2) * 0.05 * u;
      final r = Rect.fromCenter(center: Offset(x, y), width: (0.95 + 0.2 * k) * u * crece, height: 0.17 * u * crece);
      _p.color = const Color(0x997A6234);
      c.drawOval(r, _p);
      _p.color = const Color(0x40FFFFFF);
      c.drawOval(Rect.fromCenter(center: r.center.translate(-r.width * 0.15, -r.height * 0.15), width: r.width * 0.35, height: r.height * 0.25), _p);
    }
  }

  static double _salto(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
  }

  void _inodoro(Canvas c, Inodoro ino, AnimoInodoro a, int i) {
    final u = a.u;
    if (u <= 0) return;
    final f = ef.fase;
    var cx = a.x;
    var dy = 0.0;
    if (a.entrada < 1) dy = -(1 - _salto(a.entrada)) * _tam.height * 0.7;
    final temblor = ino.tapado && ino.agua > 0.6 && ef.anima;
    if (temblor) cx += sin(f * 47 + i * 1.7) * (ino.agua - 0.6) * u * 0.06;
    final dorado = ino.dorado;
    final porcelana = dorado ? const Color(0xFFFFD95A) : (oscuro ? const Color(0xFFDCE2E8) : const Color(0xFFF4F6F8));
    final sombra = dorado ? const Color(0xFFC99A1E) : (oscuro ? const Color(0xFF9AA7B3) : const Color(0xFFC9D2DA));
    final contorno = dorado ? const Color(0xFF8A6410) : (oscuro ? const Color(0xFF2A333A) : const Color(0xFF6B7A88));
    final yr = -0.86 * u;
    c.save();
    c.translate(cx, _yb + dy);
    if (temblor) c.rotate(sin(f * 31 + i) * (ino.agua - 0.6) * 0.05);
    // Brillo rojo de peligro.
    if (ino.tapado && ino.agua >= JuegoDestapa.alertaAgua) {
      _p.color = _rojo.withValues(alpha: ef.anima ? 0.16 + 0.12 * sin(f * 12) : 0.22);
      c.drawOval(Rect.fromCenter(center: Offset(0, yr), width: u * 1.5, height: u * 1.1), _p);
    }
    _p.color = const Color(0x2E000000);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: u * 0.85, height: u * 0.13), _p);
    _t.strokeWidth = max(1.2, u * 0.014);
    _t.color = contorno;
    // Tanque, tapa, palanca y el medidor de agua.
    final tanque = Rect.fromLTRB(-0.37 * u, yr - 0.52 * u, 0.37 * u, yr - 0.06 * u);
    _p.color = porcelana;
    c.drawRect(tanque, _p);
    _p.color = sombra;
    c.drawRect(Rect.fromLTRB(0.25 * u, tanque.top, tanque.right, tanque.bottom), _p);
    _p.color = const Color(0x80FFFFFF);
    c.drawRect(Rect.fromLTRB(-0.31 * u, tanque.top + 0.06 * u, -0.27 * u, tanque.bottom - 0.04 * u), _p);
    c.drawRect(tanque, _t);
    final tapa = Rect.fromLTRB(-0.41 * u, yr - 0.58 * u, 0.41 * u, yr - 0.50 * u);
    _p.color = porcelana;
    c.drawRect(tapa, _p);
    c.drawRect(tapa, _t);
    _p.color = const Color(0xFFB8C2C8);
    c.drawRect(Rect.fromLTRB(-0.33 * u, yr - 0.45 * u, -0.16 * u, yr - 0.41 * u), _p);
    _medidor(c, ino, Rect.fromLTRB(0.08 * u, yr - 0.44 * u, 0.20 * u, yr - 0.14 * u));
    if (dorado) _corona(c, Offset(0, tapa.top - 0.12 * u), u * 0.34);
    // Pie y taza.
    _camino
      ..reset()
      ..moveTo(-0.21 * u, -0.32 * u)
      ..lineTo(0.21 * u, -0.32 * u)
      ..lineTo(0.28 * u, 0)
      ..lineTo(-0.28 * u, 0)
      ..close();
    _p.color = porcelana;
    c.drawPath(_camino, _p);
    _p.color = sombra;
    c.drawRect(Rect.fromLTRB(0.12 * u, -0.32 * u, 0.27 * u, 0), _p);
    c.drawPath(_camino, _t);
    _camino
      ..reset()
      ..moveTo(-0.5 * u, yr)
      ..quadraticBezierTo(-0.5 * u, yr + 0.42 * u, -0.20 * u, -0.30 * u)
      ..lineTo(0.20 * u, -0.30 * u)
      ..quadraticBezierTo(0.5 * u, yr + 0.42 * u, 0.5 * u, yr)
      ..close();
    _p.color = porcelana;
    c.drawPath(_camino, _p);
    c.save();
    c.clipPath(_camino);
    _p.color = sombra;
    c.drawOval(Rect.fromLTRB(0.18 * u, yr, 0.75 * u, -0.1 * u), _p);
    _p.color = const Color(0x66FFFFFF);
    c.drawOval(Rect.fromLTRB(-0.40 * u, yr + 0.12 * u, -0.25 * u, yr + 0.38 * u), _p);
    c.restore();
    c.drawPath(_camino, _t);
    // Borde de atrás, boca y agua.
    final borde = Rect.fromCenter(center: Offset(0, yr), width: u, height: 0.30 * u);
    final hueco = Rect.fromCenter(center: Offset(0, yr + 0.01 * u), width: 0.80 * u, height: 0.21 * u);
    _p.color = porcelana;
    c.drawOval(borde, _p);
    c.drawOval(borde, _t);
    _p.color = const Color(0xFF2E3B44);
    c.drawOval(hueco, _p);
    final agua = ino.agua.clamp(0.0, 1.0);
    final k = 0.35 + 0.65 * agua;
    final colorAgua = _colorAgua(ino);
    final superficie = Rect.fromCenter(center: Offset(0, hueco.center.dy + (1 - k) * 0.03 * u), width: hueco.width * k, height: hueco.height * k);
    _p.color = colorAgua;
    c.drawOval(superficie, _p);
    _p.color = const Color(0x40FFFFFF);
    c.drawOval(Rect.fromCenter(center: superficie.center.translate(-superficie.width * 0.18, -superficie.height * 0.15),
        width: superficie.width * 0.35, height: superficie.height * 0.22), _p);
    if (a.remolino > 0) _remolino(c, a, hueco, u);
    if (ino.tapado && ef.anima && agua > 0.3 && ino.atasco != TipoAtasco.cucaracha) {
      final n = (agua * 6).ceil();
      _t.color = const Color(0xAAFFFFFF);
      for (var b = 0; b < n; b++) {
        final fase = (f * 1.5 + b * 0.37 + i * 0.2) % 1;
        final bx = sin(b * 2.3 + i) * superficie.width * 0.36;
        final by = superficie.center.dy + cos(b * 1.7) * superficie.height * 0.2 - fase * 0.05 * u;
        c.drawCircle(Offset(bx, by), (0.012 + 0.022 * fase) * u, _t);
      }
      _t.color = contorno;
    }
    // El atasco (va dentro de la taza: el labio de adelante lo tapa por abajo).
    final atasco = ino.atasco;
    var tope = superficie.center.dy;
    if (atasco != null && atasco != TipoAtasco.cucaracha) {
      c.save();
      c.clipRect(Rect.fromLTRB(-u, -3 * u, u, superficie.center.dy + 0.04 * u));
      tope = _atasco(c, ino, a, i, Offset(0, superficie.center.dy + 0.03 * u), u);
      c.restore();
    }
    // Labio de adelante.
    _camino
      ..reset()
      ..fillType = PathFillType.evenOdd
      ..addOval(borde)
      ..addOval(hueco);
    c.save();
    c.clipRect(Rect.fromLTRB(-u, yr + 0.005 * u, u, yr + u));
    _p.color = porcelana;
    c.drawPath(_camino, _p);
    c.drawArc(borde, 0, pi, false, _t);
    c.drawArc(hueco, 0, pi, false, _t);
    c.restore();
    _camino.fillType = PathFillType.nonZero;
    // Rebalse: agua por encima del borde y por la taza.
    if (ino.tapado && agua > 0.88 && atasco != TipoAtasco.cucaracha) {
      final g = (agua - 0.88) / 0.12;
      _p.color = colorAgua.withValues(alpha: 0.85 * g);
      c.drawOval(Rect.fromCenter(center: Offset(0, yr), width: u * (0.80 + 0.22 * g), height: u * (0.21 + 0.09 * g)), _p);
      if (ef.anima) {
        for (var d = 0; d < 3; d++) {
          final ph = (f * 1.4 + d * 0.33 + i * 0.1) % 1;
          _p.color = colorAgua.withValues(alpha: 0.9 * g);
          c.drawCircle(Offset((-0.32 + 0.32 * d) * u, yr + 0.15 * u + ph * 0.72 * u), 0.025 * u, _p);
        }
      }
    }
    if (a.desborde > 0) {
      _p.color = _aguaSucia.withValues(alpha: 0.8 * a.desborde);
      c.drawRect(Rect.fromLTRB(-0.44 * u, yr + 0.05 * u, 0.44 * u, -0.02 * u), _p);
      c.drawOval(Rect.fromCenter(center: Offset(0, yr), width: u * 1.05, height: u * 0.32), _p);
    }
    if (atasco == TipoAtasco.cucaracha) tope = _cucaracha(c, ino, Offset(0, yr), u);
    _destapador(c, ino, a, tope, u);
    if (ino.tapado && juego.calentando && ino.golpes == 0 && ef.anima) {
      final ph = (f * 1.2) % 1;
      _t
        ..color = _acento.withValues(alpha: 1 - ph)
        ..strokeWidth = 3;
      c.drawCircle(Offset(0, yr - 0.12 * u), (0.2 + 0.35 * ph) * u, _t);
      _t.strokeWidth = max(1.2, u * 0.014);
    }
    _barra(c, ino, Rect.fromLTWH(-0.30 * u, yr - 0.72 * u, 0.60 * u, max(5.0, 0.055 * u)));
    final pista = ino.primeraVez && ino.tapado ? _pistas[ino.atasco] : null;
    if (pista != null) _pista(c, pista, Offset(0, yr - 0.72 * u - 16));
    c.restore();
  }

  void _medidor(Canvas c, Inodoro ino, Rect r) {
    final agua = ino.tapado ? ino.agua.clamp(0.0, 1.0) : ino.agua.clamp(0.0, 1.0) * 0.5;
    _p.color = const Color(0xFF26323A);
    c.drawRect(r, _p);
    final rojo = agua >= JuegoDestapa.alertaAgua;
    final color = rojo ? _rojo : (agua >= 0.5 ? _acento : const Color(0xFF3BB273));
    final apaga = rojo && ef.anima && (ef.fase * 6).floor().isEven;
    _p.color = apaga ? color.withValues(alpha: 0.45) : color;
    final ins = r.deflate(2);
    c.drawRect(Rect.fromLTRB(ins.left, ins.bottom - ins.height * agua, ins.right, ins.bottom), _p);
  }

  void _corona(Canvas c, Offset centro, double tam) {
    final img = imgs.corona;
    final dy = ef.anima ? sin(ef.fase * 4) * tam * 0.06 : 0.0;
    final r = Rect.fromCenter(center: centro.translate(0, dy), width: tam, height: tam);
    if (img != null) {
      _img.color = const Color(0xFF000000);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r, _img);
    } else {
      _p.color = _acento;
      c.drawRect(r.deflate(tam * 0.2), _p);
    }
    if (ef.anima) {
      for (var k = 0; k < 4; k++) {
        final ph = (ef.fase * 0.9 + k * 0.25) % 1;
        final a = sin(ph * pi);
        final p = centro.translate(sin(k * 2.1) * tam * 1.4, cos(k * 1.3) * tam * 0.9 + tam * 0.8);
        _p.color = Color.fromRGBO(255, 245, 190, a);
        final s = tam * 0.12 * a;
        c.drawRect(Rect.fromCenter(center: p, width: s * 2, height: s * 0.5), _p);
        c.drawRect(Rect.fromCenter(center: p, width: s * 0.5, height: s * 2), _p);
      }
    }
  }

  void _remolino(Canvas c, AnimoInodoro a, Rect hueco, double u) {
    final r = a.remolino;
    c.save();
    c.clipPath(Path()..addOval(hueco));
    _t
      ..color = Color.fromRGBO(255, 255, 255, 0.75 * r)
      ..strokeWidth = max(1.5, u * 0.025);
    final giro = (1 - r) * 14;
    for (var k = 0; k < 3; k++) {
      final esc = 0.35 + k * 0.22;
      c.drawArc(Rect.fromCenter(center: hueco.center, width: hueco.width * esc, height: hueco.height * esc), giro + k * 2.1, 2.4, false, _t);
    }
    final sale = a.sale;
    if (sale == TipoAtasco.normal || sale == TipoAtasco.gordo) {
      final img = imgs.mojon;
      final s = u * (sale == TipoAtasco.gordo ? 0.66 : 0.5) * pow(r, 0.8);
      c.save();
      c.translate(hueco.center.dx, hueco.center.dy - s * 0.3);
      c.rotate(giro * 0.7);
      final dst = Rect.fromCenter(center: Offset.zero, width: s, height: s);
      if (img != null) {
        _img.color = Color.fromRGBO(0, 0, 0, r);
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _img);
      } else {
        _p.color = _aguaSucia.withValues(alpha: r);
        c.drawOval(dst, _p);
      }
      c.restore();
    }
    c.restore();
    _t.color = const Color(0xFF6B7A88);
  }

  /// Dibuja el atasco con su base en [base] y devuelve la altura de su tope (donde pega el destapador).
  double _atasco(Canvas c, Inodoro ino, AnimoInodoro a, int i, Offset base, double u) {
    final t = ino.atasco!;
    final f = ef.anima ? ef.fase : 0.0;
    final g = a.golpe;
    final pop = ef.anima ? _salto(a.nace.clamp(0.0, 1.0)) : 1.0;
    var s = u * switch (t) {
      TipoAtasco.gordo => 0.66,
      TipoAtasco.patito => 0.46,
      TipoAtasco.celular => 0.40,
      _ => 0.50,
    };
    var sx = 1.0, sy = 1.0, giro = 0.0;
    var b = base.translate(0, ino.progreso * 0.16 * s - ino.agua * 0.06 * u);
    if (ef.anima) {
      sx += sin(f * 3 + i) * 0.025;
      sy -= sin(f * 3 + i) * 0.025;
      giro = sin(f * 2 + i * 1.3) * 0.06;
    }
    sx += 0.24 * g + 0.12 * a.recupera;
    sy -= 0.28 * g - 0.10 * a.recupera;
    switch (t) {
      case TipoAtasco.patito:
        if (ef.anima) {
          b = b.translate(0, sin(f * 4 + i) * 0.02 * u);
          giro = sin(f * 3 + i) * 0.18;
        }
      case TipoAtasco.celular:
        giro = 0.35;
        b = b.translate(0, -ino.progreso * 0.22 * u + a.hundido * 0.08 * u);
        if (ef.anima && (f % 1.2) < 0.3) b = b.translate(sin(f * 90) * 0.012 * u, 0);
      case TipoAtasco.gordo:
        if (ef.anima && ino.agua > 0.5) giro += sin(f * 9) * 0.05;
      default:
        break;
    }
    c.save();
    c.translate(b.dx, b.dy);
    c.rotate(giro);
    c.scale(sx * pop, sy * pop);
    final dst = Rect.fromLTWH(-s / 2, -s, s, s);
    final img = switch (t) {
      TipoAtasco.patito => imgs.patito,
      TipoAtasco.celular => imgs.celular,
      _ => imgs.mojon,
    };
    if (img != null) {
      _img
        ..color = const Color(0xFF000000)
        ..colorFilter = t == TipoAtasco.gordo ? _tinteGordo : null;
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _img);
      _img.colorFilter = null;
    } else {
      _p.color = switch (t) {
        TipoAtasco.patito => _acento,
        TipoAtasco.celular => const Color(0xFF333344),
        _ => const Color(0xFF8B5A2B),
      };
      c.drawOval(dst.deflate(s * 0.08), _p);
    }
    if (t == TipoAtasco.normal || t == TipoAtasco.gordo) _cara(c, ino, dst, t == TipoAtasco.gordo);
    c.restore();
    final tope = b.dy - s * sy * pop;
    if (t == TipoAtasco.patito) _flechas(c, Offset(b.dx, tope - 0.05 * u), u);
    if (t == TipoAtasco.celular) _anillo(c, ino, Offset(b.dx, b.dy - s * 0.5), s);
    return tope;
  }

  // Cejas (preocupadas o furiosas), cachetes del gordo y sudor cuando el agua sube.
  void _cara(Canvas c, Inodoro ino, Rect r, bool gordo) {
    final s = r.width;
    Offset p(double fx, double fy) => Offset(r.left + fx * s, r.top + fy * s);
    final preocupado = ino.agua > 0.55;
    if (gordo || preocupado) {
      _t
        ..color = _cafe
        ..strokeWidth = s * 0.05;
      if (gordo) {
        c.drawLine(p(0.20, 0.38), p(0.42, 0.46), _t);
        c.drawLine(p(0.80, 0.38), p(0.58, 0.46), _t);
      } else {
        c.drawLine(p(0.20, 0.45), p(0.40, 0.38), _t);
        c.drawLine(p(0.80, 0.45), p(0.60, 0.38), _t);
      }
    }
    if (gordo) {
      _p.color = const Color(0x66FF3030);
      c.drawOval(Rect.fromCenter(center: p(0.18, 0.72), width: s * 0.14, height: s * 0.08), _p);
      c.drawOval(Rect.fromCenter(center: p(0.82, 0.72), width: s * 0.14, height: s * 0.08), _p);
    }
    if (ino.agua > 0.7) {
      final img = imgs.sudor;
      final ph = ef.anima ? (ef.fase * 1.3) % 1 : 0.3;
      final g = Rect.fromCenter(center: p(0.86, 0.28 + ph * 0.2), width: s * 0.26, height: s * 0.26);
      if (img != null) {
        _img.color = const Color(0xFF000000);
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), g, _img);
      } else {
        _p.color = _aguaLimpia;
        c.drawOval(g.deflate(s * 0.06), _p);
      }
    }
    _t.color = const Color(0xFF6B7A88);
  }

  void _flechas(Canvas c, Offset p, double u) {
    final ph = ef.anima ? (ef.fase * 1.6) % 1 : 0.0;
    for (var k = 0; k < 2; k++) {
      final y = p.dy - k * 0.11 * u - ph * 0.08 * u;
      final a = k == 0 ? 1.0 : 1 - ph;
      _camino2
        ..reset()
        ..moveTo(p.dx - 0.10 * u, y)
        ..lineTo(p.dx, y - 0.08 * u)
        ..lineTo(p.dx + 0.10 * u, y);
      _t
        ..color = Color.fromRGBO(17, 17, 17, a)
        ..strokeWidth = max(4.0, 0.06 * u);
      c.drawPath(_camino2, _t);
      _t
        ..color = _acento.withValues(alpha: a)
        ..strokeWidth = max(2.0, 0.035 * u);
      c.drawPath(_camino2, _t);
    }
    _t
      ..color = const Color(0xFF6B7A88)
      ..strokeWidth = max(1.2, u * 0.014);
  }

  void _anillo(Canvas c, Inodoro ino, Offset centro, double s) {
    final r = Rect.fromCenter(center: centro, width: s * 1.5, height: s * 1.5);
    _t
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = max(3.0, s * 0.09);
    c.drawArc(r, -pi / 2, pi * 2, false, _t);
    if (ino.progreso > 0) {
      _t.color = _acento;
      c.drawArc(r, -pi / 2, pi * 2 * ino.progreso, false, _t);
    }
    _t
      ..color = const Color(0xFF6B7A88)
      ..strokeWidth = max(1.2, s * 0.035);
  }

  /// La cucaracha corre por el borde de adelante; devuelve su tope.
  double _cucaracha(Canvas c, Inodoro ino, Offset centro, double u) {
    final cc = ino.cucaracha.clamp(0.0, 1.0);
    final th = pi - cc * pi;
    final x = cos(th) * u * 0.46, y = centro.dy + sin(th) * u * 0.14;
    final vx = sin(th) * 0.46 * u, vy = -cos(th) * 0.14 * u;
    final s = u * 0.36 * (ef.anima ? _salto(min(1, ino.edad * 4)) : 1);
    // Halo claro debajo para que el bicho se lea sobre la porcelana y el agua.
    _p.color = const Color(0x66FFFFFF);
    c.drawCircle(Offset(x, y - s * 0.25), s * 0.48, _p);
    c.save();
    c.translate(x, y - s * 0.25);
    c.rotate(atan2(vy, vx) + pi / 2 + (ef.anima ? sin(ef.fase * 40) * 0.15 : 0));
    final img = imgs.cucaracha;
    final dst = Rect.fromCenter(center: Offset.zero, width: s, height: s);
    if (img != null) {
      _img.color = const Color(0xFF000000);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _img);
    } else {
      _p.color = _cafe;
      c.drawOval(dst.deflate(s * 0.2), _p);
    }
    c.restore();
    return y - s * 0.6;
  }

  void _destapador(Canvas c, Inodoro ino, AnimoInodoro a, double tope, double u) {
    final g = a.golpe;
    if (g <= 0.02) return;
    final t = ino.atasco ?? a.sale;
    if (t == TipoAtasco.celular || t == TipoAtasco.cucaracha) return;
    final tam = u * 0.62;
    c.save();
    c.translate(0, tope + 0.04 * u - (1 - g) * 0.30 * u);
    c.scale(1 + 0.15 * g, 1 - 0.22 * g);
    c.rotate(-pi / 4);
    final dst = Rect.fromLTWH(-0.2 * tam, -0.8 * tam, tam, tam);
    final img = imgs.destapador;
    final alfa = min(1.0, g * 3);
    if (img != null) {
      _img.color = Color.fromRGBO(0, 0, 0, alfa);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _img);
    } else {
      _p.color = Color.fromRGBO(200, 40, 40, alfa);
      c.drawRect(Rect.fromLTWH(-0.1 * tam, -0.25 * tam, 0.4 * tam, 0.25 * tam), _p);
    }
    c.restore();
  }

  void _barra(Canvas c, Inodoro ino, Rect r) {
    final t = ino.atasco;
    if (t == null || t == TipoAtasco.patito) return;
    _p.color = const Color(0xCC111111);
    c.drawRect(r.inflate(1.5), _p);
    if (t == TipoAtasco.normal || t == TipoAtasco.gordo) {
      final n = ino.requiere;
      final paso = r.width / n;
      for (var k = 0; k < n; k++) {
        _p.color = k < ino.golpes ? _acento : const Color(0xFF3A3F44);
        c.drawRect(Rect.fromLTWH(r.left + k * paso + 0.5, r.top, paso - 1, r.height), _p);
      }
    } else if (t == TipoAtasco.celular) {
      _p.color = _acento;
      c.drawRect(Rect.fromLTWH(r.left, r.top, r.width * ino.progreso, r.height), _p);
    } else {
      _p.color = _rojo;
      c.drawRect(Rect.fromLTWH(r.left, r.top, r.width * (1 - ino.progreso), r.height), _p);
    }
  }

  void _pista(Canvas c, TextPainter tp, Offset centro) {
    final esc = ef.anima ? 1 + sin(ef.fase * 8) * 0.06 : 1.0;
    c.save();
    c.translate(centro.dx, centro.dy);
    c.scale(esc);
    final r = Rect.fromCenter(center: Offset.zero, width: tp.width + 10, height: tp.height + 4);
    _p.color = _acento;
    c.drawRect(r, _p);
    _t
      ..color = const Color(0xFF111111)
      ..strokeWidth = 1.5;
    c.drawRect(r, _t);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(PintorDestapa old) => old != this || old.oscuro != oscuro;
}
