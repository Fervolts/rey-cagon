// Fusión real: geometría de pantalla, efectos (partículas, textos flotantes, sacudida, destellos, mojones que se van
// por el desagüe) y el CustomPainter del baño. Las partículas salen de un pool fijo; los Paint se crean una vez.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../animaciones.dart';
import '../../idioma.dart';
import 'memoria_logica.dart';

/// Pasa del mundo de la lógica (x a la derecha, y hacia abajo, borde de la poceta en y = 0) a la pantalla.
class GeoFusion {
  GeoFusion._(this.s, this.cx, this.y0, this.size);

  /// Espacio reservado arriba para el HUD y abajo de margen, en píxeles.
  static const double arriba = 58, abajo = 8;

  /// Lo que se ve del mundo: desde la tapa del tanque hasta el piso, y de la palanca al borde de la poceta.
  static const double mundoArriba = -118, mundoAbajo = 150, mundoAncho = 128;

  factory GeoFusion.de(Size size) {
    const alto = mundoAbajo - mundoArriba;
    final s = max(0.5, min((size.width - 16) / mundoAncho, (size.height - arriba - abajo) / alto));
    final extra = max(0.0, (size.height - arriba - abajo - alto * s) / 2);
    return GeoFusion._(s, size.width / 2, arriba + extra - mundoArriba * s, size);
  }

  final double s, cx, y0;
  final Size size;

  Offset p(double x, double y) => Offset(cx + x * s, y0 + y * s);
  double xMundo(double dx) => (dx - cx) / s;
  double yMundo(double dy) => (dy - y0) / s;

  /// Zona del tanque y la palanca (para tocarla).
  bool enTanque(Offset local) {
    final x = xMundo(local.dx), y = yMundo(local.dy);
    return x >= -66 && x <= 50 && y >= -120 && y <= -48;
  }
}

/// Archivos de assets/emoji que dibuja el juego.
const Map<String, String> archivosFusion = {
  'poo': 'pile_of_poo',
  'corona': 'crown',
  'lentes': 'sunglasses',
  'mosca': 'fly',
  'sudor': 'sweat_droplets',
  'ciclon': 'cyclone',
};

final Map<String, Future<ui.Image>> _cargas = {};

/// Carga una vez cada imagen; si falla, la próxima llamada lo reintenta.
Future<ui.Image> imagenFusion(String clave) => _cargas[clave] ??= () async {
      try {
        final datos = await rootBundle.load('assets/emoji/${archivosFusion[clave]}.png');
        return await decodeImageFromList(datos.buffer.asUint8List());
      } catch (_) {
        _cargas.remove(clave);
        rethrow;
      }
    }();

// ---------------------------------------------------------------------------------------------------------------
// Colores por nivel

/// Tinte por nivel (índice = nivel): (rojo, verde, azul, mezcla, ganancia). null = el PNG tal cual.
const List<(double, double, double, double, double)?> _tintes = [
  null,
  (1.0, 0.80, 0.55, 0.75, 2.3), // 1 bolita: clarita
  (0.80, 0.36, 0.26, 0.75, 2.2), // 2 frijolito: rojizo
  null, // 3 mojoncito: el de siempre
  (0.62, 0.36, 0.25, 0.70, 1.9), // 4 mojón: más oscuro
  (0.95, 0.60, 0.34, 0.75, 2.1), // 5 lentes: caramelo
  (0.70, 0.40, 0.22, 0.75, 2.0), // 6 bigote: castaño
  (0.50, 0.30, 0.18, 0.80, 1.9), // 7 gordo: chocolate
  (1.05, 0.82, 0.24, 0.85, 2.5), // 8 dorado
  (0.95, 0.30, 0.22, 0.75, 2.1), // 9 Rey: rojo vino
];

ColorFilter? _filtroDe(int nivel) {
  final t = _tintes[nivel];
  if (t == null) return null;
  final (r, g, b, a, k) = t;
  List<double> fila(double c, int i) {
    final base = [a * c * k * 0.3, a * c * k * 0.59, a * c * k * 0.11];
    base[i] += 1 - a;
    return [...base, 0, 0];
  }

  return ColorFilter.matrix([...fila(r, 0), ...fila(g, 1), ...fila(b, 2), 0, 0, 0, 1, 0]);
}

/// Color del cuerpo del PNG después del tinte (para párpados y trozos).
Color _cuerpoDe(int nivel) {
  const r0 = 151.0, g0 = 87.0, b0 = 71.0;
  final t = _tintes[nivel];
  if (t == null) return const Color(0xFF975747);
  final (r, g, b, a, k) = t;
  final l = 0.3 * r0 + 0.59 * g0 + 0.11 * b0;
  int c(double orig, double tinte) => ((1 - a) * orig + a * tinte * k * l).clamp(0, 255).round();
  return Color.fromARGB(255, c(r0, r), c(g0, g), c(b0, b));
}

final List<ColorFilter?> _filtros = List.generate(nivelMaximo + 1, _filtroDe);
final List<Color> coloresNivel = List.generate(nivelMaximo + 1, _cuerpoDe);

// ---------------------------------------------------------------------------------------------------------------
// Efectos

class FlotanteFusion {
  FlotanteFusion(this.x, this.y, this.relleno, this.borde, this.dur, this.escala);
  final double x, y, dur, escala;
  final TextPainter relleno, borde;
  double t = 0;
}

/// Mojón que ya no está en la física pero se sigue viendo: se lo traga el remolino o se hunde en la descarga final.
class FantasmaFusion {
  FantasmaFusion(this.x, this.y, this.nivel, this.hundir, this.dur, this.giro);
  final double x, y, dur, giro;
  final int nivel;
  final bool hundir;
  double t = 0;
}

class EfectosFusion {
  EfectosFusion({this.mov = Movimiento.completo});
  Movimiento mov;

  static const int maxParticulas = 280;
  final _x = Float32List(maxParticulas), _y = Float32List(maxParticulas);
  final _vx = Float32List(maxParticulas), _vy = Float32List(maxParticulas);
  final _vida = Float32List(maxParticulas), _dur = Float32List(maxParticulas), _tam = Float32List(maxParticulas);
  final _color = Uint32List(maxParticulas);
  final _tipo = Uint8List(maxParticulas);
  int _cursor = 0;

  final _rng = Random(11);
  double tiempo = 0;
  double sacudida = 0;
  Color colorFlash = const Color(0x00FFFFFF);
  double flash = 0;
  final List<FlotanteFusion> flotantes = [];
  final List<FantasmaFusion> fantasmas = [];

  /// Balanceo de la garra (resorte), en radianes.
  double balanceo = 0;
  double _vBalanceo = 0, _apunteAntes = 0;

  int _cuantas(int n) => switch (mov) {
        Movimiento.nada => 0,
        Movimiento.simple => (n / 3).ceil(),
        Movimiento.completo => n,
      };

  void _particula(int tipo, double x, double y, double vx, double vy, double dur, double tam, Color color) {
    final i = _cursor;
    _cursor = (_cursor + 1) % maxParticulas;
    _tipo[i] = tipo;
    _x[i] = x;
    _y[i] = y;
    _vx[i] = vx;
    _vy[i] = vy;
    _vida[i] = dur;
    _dur[i] = dur;
    _tam[i] = tam;
    _color[i] = color.toARGB32();
  }

  /// Salpicón de agua hacia arriba.
  void salpicar(double x, double y, int n, {double fuerza = 1}) {
    for (var i = 0; i < _cuantas(n); i++) {
      final a = -pi / 2 + (_rng.nextDouble() - 0.5) * 2.0;
      final v = (40 + _rng.nextDouble() * 70) * fuerza;
      _particula(0, x, y, cos(a) * v, sin(a) * v, 0.5 + _rng.nextDouble() * 0.4, 0.8 + _rng.nextDouble() * 1.1,
          _rng.nextBool() ? const Color(0xFF8ED8F2) : const Color(0xFFD9F4FF));
    }
  }

  /// Estallido de fusión: trozos del color del nivel y chispas.
  void estallido(double x, double y, int nivel, double radio) {
    final n = 6 + nivel * 2;
    final cuerpo = coloresNivel[nivel];
    for (var i = 0; i < _cuantas(n); i++) {
      final a = _rng.nextDouble() * pi * 2;
      final v = 50 + _rng.nextDouble() * 60 + nivel * 6;
      _particula(2, x + cos(a) * radio * 0.6, y + sin(a) * radio * 0.6, cos(a) * v, sin(a) * v - 30, 0.45 + _rng.nextDouble() * 0.3,
          0.9 + _rng.nextDouble() * (0.6 + nivel * 0.12), cuerpo);
    }
    chispas(x, y, 4 + nivel, nivel >= 8 ? const Color(0xFFFFD60A) : Colors.white, radio: radio);
  }

  void chispas(double x, double y, int n, Color color, {double radio = 4}) {
    for (var i = 0; i < _cuantas(n); i++) {
      final a = _rng.nextDouble() * pi * 2;
      final v = 30 + _rng.nextDouble() * 80;
      _particula(1, x + cos(a) * radio * 0.4, y + sin(a) * radio * 0.4, cos(a) * v, sin(a) * v, 0.35 + _rng.nextDouble() * 0.35,
          1.0 + _rng.nextDouble() * 1.4, color);
    }
  }

  /// Texto que sube y se desvanece. El TextPainter se arma una sola vez, al nacer.
  void texto(double x, double y, String s, Color color, {double tam = 15, double dur = 0.9, double escala = 1}) {
    if (flotantes.length >= 14) flotantes.removeAt(0);
    final estilo = TextStyle(fontFamily: 'Roboto', fontSize: tam, fontWeight: FontWeight.w900, height: 1, letterSpacing: 0.5);
    final relleno = TextPainter(text: TextSpan(text: s, style: estilo.copyWith(color: color)), textDirection: TextDirection.ltr)
      ..layout();
    final borde = TextPainter(
      text: TextSpan(
        text: s,
        style: estilo.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF2B1A12),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    flotantes.add(FlotanteFusion(x, y, relleno, borde, dur, escala));
  }

  void sacudir(double px) {
    if (mov != Movimiento.completo) return;
    sacudida = max(sacudida, px);
  }

  void destellar(Color color, double fuerza) {
    if (mov == Movimiento.nada) return;
    colorFlash = color;
    flash = max(flash, fuerza);
  }

  void tragar(double x, double y, int nivel, {double retraso = 0}) {
    if (fantasmas.length > 60) return;
    fantasmas.add(FantasmaFusion(x, y, nivel, false, 0.9 + retraso, _rng.nextBool() ? 1 : -1)..t = -retraso);
  }

  void hundir(double x, double y, int nivel) {
    if (fantasmas.length > 60) return;
    fantasmas.add(FantasmaFusion(x, y, nivel, true, 0.55, 0));
  }

  void avanzar(double dt, double apunte) {
    tiempo += dt;
    for (var i = 0; i < maxParticulas; i++) {
      if (_vida[i] <= 0) continue;
      _vida[i] -= dt;
      final g = switch (_tipo[i]) { 1 => 40.0, _ => 300.0 };
      _vy[i] += g * dt;
      if (_tipo[i] == 1) {
        _vx[i] *= 0.92;
        _vy[i] *= 0.92;
      }
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
    }
    for (final f in flotantes) {
      f.t += dt;
    }
    flotantes.removeWhere((f) => f.t >= f.dur);
    for (final f in fantasmas) {
      f.t += dt;
    }
    fantasmas.removeWhere((f) => f.t >= f.dur);
    sacudida = max(0, sacudida - dt * 40);
    flash = max(0, flash - dt * 3);

    // La garra se balancea al moverla: resorte amortiguado.
    if (dt > 0) {
      final vel = (apunte - _apunteAntes) / dt;
      _vBalanceo += (-(vel * 0.0022).clamp(-0.5, 0.5) - balanceo) * 60 * dt - _vBalanceo * 8 * dt;
      balanceo = (balanceo + _vBalanceo * dt).clamp(-0.45, 0.45);
    }
    _apunteAntes = apunte;
    if (mov == Movimiento.nada) balanceo = 0;
  }

  int get vivas {
    var n = 0;
    for (var i = 0; i < maxParticulas; i++) {
      if (_vida[i] > 0) n++;
    }
    return n;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Pintor

double _easeOutBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  final u = t - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
}

class PintorFusion extends CustomPainter {
  PintorFusion({
    required this.j,
    required this.ef,
    required this.oscuro,
    required this.imagenes,
    required this.mov,
    required Listenable repintar,
  }) : super(repaint: repintar);

  final JuegoFusion j;
  final EfectosFusion ef;
  final bool oscuro;
  final Map<String, ui.Image> imagenes;
  final Movimiento mov;

  // Paint reutilizados (nunca se crean por cuadro).
  static final _relleno = Paint()..isAntiAlias = true;
  static final _trazo = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _img = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;
  static final _sombreado = Paint();
  static final _capaAlfa = Paint();

  // Cosas que dependen solo del tamaño: se arman una vez por tamaño.
  static Size? _tamCache;
  static bool? _oscuroCache;
  static late Path _interior, _exterior, _pedestal;
  static late Shader _sombraPared, _interiorShader, _porcelana, _lampara, _vineta, _agua, _tanqueShader;
  static final Map<String, TextPainter> _textos = {};

  static const _src = Rect.fromLTWH(0, 0, 256, 256);

  void _prepararCache(GeoFusion g) {
    if (_tamCache == g.size && _oscuroCache == oscuro) return;
    _tamCache = g.size;
    _oscuroCache = oscuro;
    final s = g.s;
    _interior = Path();
    final c = contornoPoceta(tramos: 40);
    _interior.moveTo(g.p(c.first.$1, c.first.$2).dx, g.p(c.first.$1, c.first.$2).dy);
    for (final (x, y) in c.skip(1)) {
      final o = g.p(x, y);
      _interior.lineTo(o.dx, o.dy);
    }
    _interior.close();

    _exterior = Path()
      ..moveTo(g.p(-58, -2).dx, g.p(-58, -2).dy)
      ..lineTo(g.p(-58, 40).dx, g.p(-58, 40).dy)
      ..arcTo(Rect.fromCenter(center: g.p(0, 40), width: 116 * s, height: 176 * s), pi, -pi, false)
      ..lineTo(g.p(58, -2).dx, g.p(58, -2).dy)
      ..close();

    _pedestal = Path()
      ..moveTo(g.p(-27, 100).dx, g.p(-27, 100).dy)
      ..lineTo(g.p(27, 100).dx, g.p(27, 100).dy)
      ..quadraticBezierTo(g.p(28, 130).dx, g.p(28, 130).dy, g.p(38, 149).dx, g.p(38, 149).dy)
      ..lineTo(g.p(-38, 149).dx, g.p(-38, 149).dy)
      ..quadraticBezierTo(g.p(-28, 130).dx, g.p(-28, 130).dy, g.p(-27, 100).dx, g.p(-27, 100).dy)
      ..close();

    _sombraPared = ui.Gradient.linear(Offset(0, 0), Offset(0, g.p(0, 40).dy),
        oscuro ? const [Color(0xFF223047), Color(0xFF172231)] : const [Color(0xFFCDEBE4), Color(0xFFA6D3C9)]);
    _interiorShader = ui.Gradient.linear(g.p(0, 0), g.p(0, 120), oscuro ? const [Color(0xFFB8C6CF), Color(0xFF8197A4)] : const [Color(0xFFE9F1F4), Color(0xFFB4C9D3)]);
    _porcelana = ui.Gradient.linear(g.p(-58, 0), g.p(58, 0),
        oscuro ? const [Color(0xFFA9B6BF), Color(0xFFE2E9EE), Color(0xFF8C9AA5)] : const [Color(0xFFD9E2E8), Color(0xFFFFFFFF), Color(0xFFC3CFD8)], const [0, 0.42, 1]);
    _tanqueShader = ui.Gradient.linear(g.p(-46, 0), g.p(46, 0),
        oscuro ? const [Color(0xFF9FAEB8), Color(0xFFDCE4EA), Color(0xFF8A99A4)] : const [Color(0xFFD4DEE5), Color(0xFFFFFFFF), Color(0xFFBFCCD5)], const [0, 0.4, 1]);
    _lampara = ui.Gradient.radial(g.p(-30, -150), 230 * s,
        oscuro ? const [Color(0x55FFE6A0), Color(0x00FFE6A0)] : const [Color(0x66FFFFFF), Color(0x00FFFFFF)]);
    _vineta = ui.Gradient.radial(Offset(g.size.width / 2, g.size.height / 2), g.size.longestSide * 0.62,
        const [Color(0x00FF2020), Color(0x00FF2020), Color(0xCCE01010)], const [0, 0.55, 1]);
    _agua = ui.Gradient.linear(g.p(0, 84), g.p(0, 122),
        oscuro ? const [Color(0xFF3F8FB0), Color(0xFF235A78)] : const [Color(0xFF8DD8EE), Color(0xFF4EA9CB)]);
  }

  TextPainter _texto(String s, double tam, Color color, {FontWeight peso = FontWeight.w900}) {
    final clave = '$s|${tam.toStringAsFixed(1)}|${color.toARGB32()}|${peso.value}';
    return _textos[clave] ??= TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Roboto', fontSize: tam, fontWeight: peso, color: color, height: 1, letterSpacing: 0.8)),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = GeoFusion.de(size);
    _prepararCache(g);
    final t = ef.tiempo;

    _fondo(canvas, g, t);

    canvas.save();
    if (ef.sacudida > 0) {
      canvas.translate(sin(t * 61) * ef.sacudida, cos(t * 53) * ef.sacudida * 0.7);
    }
    _tanque(canvas, g, t);
    _poceta(canvas, g);
    _aguaAtras(canvas, g, t);
    _remolino(canvas, g, t);
    _guia(canvas, g);
    _mojones(canvas, g, t);
    _fantasmas(canvas, g, t);
    _aguaDelante(canvas, g, t);
    _linea(canvas, g, t);
    _mosca(canvas, g, t);
    _garra(canvas, g, t);
    _particulas(canvas, g);
    _flotantes(canvas, g);
    canvas.restore();

    if (ef.flash > 0) {
      _relleno.color = ef.colorFlash.withValues(alpha: (ef.flash * 0.55).clamp(0.0, 0.55));
      canvas.drawRect(Offset.zero & size, _relleno);
    }
    final cuenta = j.cuentaDesborde;
    if (cuenta > 0 || j.fase == FaseFusion.desbordado) {
      final f = j.fase == FaseFusion.desbordado ? 1.0 : (cuenta / segundosDesborde).clamp(0.0, 1.0);
      final pulso = mov == Movimiento.nada ? 1.0 : 0.7 + 0.3 * sin(t * 14);
      _sombreado
        ..shader = _vineta
        ..color = Color.fromRGBO(0, 0, 0, (0.35 + 0.65 * f) * pulso);
      canvas.drawRect(Offset.zero & size, _sombreado);
    }
  }

  // ----- Fondo: pared de azulejos, guardaescoba, piso, lámpara.
  void _fondo(Canvas c, GeoFusion g, double t) {
    final w = g.size.width, h = g.size.height, s = g.s;
    final yRiel = g.p(0, 40).dy, yPiso = g.p(0, 148).dy;
    _sombreado
      ..shader = _sombraPared
      ..color = const Color(0xFF000000);
    c.drawRect(Rect.fromLTWH(0, 0, w, yRiel), _sombreado);

    // Azulejos con parallax según hacia dónde apuntas.
    final lado = 13 * s;
    final dx = mov == Movimiento.completo ? (-j.apunte * 0.10 * s + sin(t * 0.35) * 2) : 0.0;
    _relleno.color = oscuro ? const Color(0x14FFFFFF) : const Color(0x1C0E5A55);
    var fila = 0;
    for (var y = yRiel - lado; y > -lado; y -= lado, fila++) {
      final x0 = (dx % (lado * 2)) - lado * 2 + (fila.isOdd ? lado : 0);
      for (var x = x0; x < w + lado; x += lado * 2) {
        c.drawRect(Rect.fromLTWH(x, y, lado, lado), _relleno);
      }
    }
    _trazo
      ..strokeWidth = 1
      ..color = oscuro ? const Color(0x22000000) : const Color(0x22FFFFFF);
    for (var y = yRiel - lado; y > -lado; y -= lado) {
      c.drawLine(Offset(0, y), Offset(w, y), _trazo);
    }
    for (var x = (dx % lado) - lado; x < w + lado; x += lado) {
      c.drawLine(Offset(x, 0), Offset(x, yRiel), _trazo);
    }

    // Manchas viejas en la pared.
    _relleno.color = oscuro ? const Color(0x10000000) : const Color(0x128A6A3A);
    c.drawOval(Rect.fromCenter(center: g.p(52 + dx / s * 0.4, -20), width: 18 * s, height: 11 * s), _relleno);
    c.drawOval(Rect.fromCenter(center: g.p(-56 + dx / s * 0.4, 18), width: 12 * s, height: 16 * s), _relleno);

    // Lámpara que titila un poquito.
    final titila = mov == Movimiento.nada ? 1.0 : 0.85 + 0.15 * sin(t * 2.3) * sin(t * 7.1);
    _sombreado
      ..shader = _lampara
      ..color = Color.fromRGBO(0, 0, 0, titila);
    c.drawRect(Rect.fromLTWH(0, 0, w, yPiso), _sombreado);

    // Pared baja y guardaescoba.
    _relleno.color = oscuro ? const Color(0xFF0F3439) : const Color(0xFF3E8A86);
    c.drawRect(Rect.fromLTRB(0, yRiel, w, yPiso), _relleno);
    _trazo
      ..strokeWidth = 1
      ..color = oscuro ? const Color(0x22FFFFFF) : const Color(0x22000000);
    for (var x = (dx * 0.6 % (8 * s)) - 8 * s; x < w + 8 * s; x += 8 * s) {
      c.drawLine(Offset(x, yRiel + 3 * s), Offset(x, yPiso), _trazo);
    }
    _relleno.color = oscuro ? const Color(0xFF1E5258) : const Color(0xFFF2EEE4);
    c.drawRect(Rect.fromLTRB(0, yRiel - 1.5 * s, w, yRiel + 3 * s), _relleno);
    _relleno.color = oscuro ? const Color(0x33000000) : const Color(0x22000000);
    c.drawRect(Rect.fromLTRB(0, yRiel + 3 * s, w, yRiel + 4 * s), _relleno);

    // Piso con perspectiva.
    _relleno.color = oscuro ? const Color(0xFF2A2622) : const Color(0xFFD9CFC0);
    c.drawRect(Rect.fromLTRB(0, yPiso, w, h), _relleno);
    _trazo.color = oscuro ? const Color(0x33000000) : const Color(0x26000000);
    for (var i = -8; i <= 8; i++) {
      c.drawLine(Offset(w / 2 + i * 14 * s, yPiso), Offset(w / 2 + i * 30 * s, h + 30), _trazo);
    }
    for (var k = 1; k < 5; k++) {
      final y = yPiso + (h - yPiso) * (k * k) / 20;
      c.drawLine(Offset(0, y), Offset(w, y), _trazo);
    }
    _relleno.color = oscuro ? const Color(0x55000000) : const Color(0x33000000);
    c.drawRect(Rect.fromLTRB(0, yPiso, w, yPiso + 2), _relleno);

    // Tubo de agua detrás del tanque.
    final tubo = Rect.fromLTRB(g.p(42, -64).dx, g.p(42, -64).dy, g.p(46, -64).dx, yPiso);
    _relleno.color = oscuro ? const Color(0xFF6D7C86) : const Color(0xFFAEBBC4);
    c.drawRect(tubo.translate(4 * s, 0), _relleno);
    _relleno.color = oscuro ? const Color(0xFF4E5A62) : const Color(0xFF8796A0);
    c.drawRect(Rect.fromLTWH(tubo.left + 3 * s, g.p(0, 60).dy, 6 * s, 3 * s), _relleno);
  }

  // ----- Tanque: ventana con la próxima pieza, barra de la palanca y palanca.
  void _tanque(Canvas c, GeoFusion g, double t) {
    final s = g.s;
    final cuerpo = Rect.fromLTRB(g.p(-46, -110).dx, g.p(-46, -110).dy, g.p(46, -50).dx, g.p(46, -50).dy);
    _sombreado
      ..shader = _tanqueShader
      ..color = const Color(0xFF000000);
    c.drawRect(cuerpo, _sombreado);
    _trazo
      ..strokeWidth = max(1.0, 0.45 * s)
      ..color = const Color(0xFF7D8E9A);
    c.drawRect(cuerpo, _trazo);
    final tapa = Rect.fromLTRB(g.p(-49, -116).dx, g.p(-49, -116).dy, g.p(49, -109).dx, g.p(49, -109).dy);
    c.drawRect(tapa, _sombreado);
    c.drawRect(tapa, _trazo);

    // Ventana "SIGUE".
    final ventana = Rect.fromLTRB(g.p(-17, -104).dx, g.p(-17, -104).dy, g.p(17, -71).dx, g.p(17, -71).dy);
    _relleno.color = oscuro ? const Color(0xFF15202A) : const Color(0xFF26343F);
    c.drawRect(ventana, _relleno);
    _trazo.color = const Color(0xFF3B4A55);
    c.drawRect(ventana, _trazo);
    final rotulo = _texto(tr('SIGUE', 'NEXT'), max(7.0, 3.0 * s), const Color(0xFFFFD60A));
    rotulo.paint(c, Offset(ventana.center.dx - rotulo.width / 2, ventana.top + 1.2 * s));
    final sig = j.siguiente;
    final rSig = min(radioDe(sig) * 1.05, 10.0);
    _dibujarMojon(c, g, 0, -85 + (10 - rSig) * 0.3, rSig, sig, id: -1, ojos: true, mirada: const Offset(0, 1), t: t);

    // Barra de carga: 10 segmentos.
    final lista = j.palancaLista && j.fase == FaseFusion.jugando;
    final pulso = lista && mov != Movimiento.nada ? 0.5 + 0.5 * sin(t * 10) : 1.0;
    const x0 = -38.0, x1 = 38.0, ancho = (x1 - x0) / cargaPalanca;
    if (lista) {
      _relleno.color = const Color(0xFFFFD60A).withValues(alpha: 0.25 + 0.35 * pulso);
      c.drawRect(Rect.fromLTRB(g.p(x0 - 2, -68).dx, g.p(0, -68).dy, g.p(x1 + 2, -55).dx, g.p(0, -55).dy), _relleno);
    }
    for (var i = 0; i < cargaPalanca; i++) {
      final r = Rect.fromLTRB(g.p(x0 + i * ancho + 0.6, -66).dx, g.p(0, -66).dy, g.p(x0 + (i + 1) * ancho - 0.6, -58).dx, g.p(0, -58).dy);
      final lleno = i < j.carga;
      _relleno.color = lleno
          ? (lista ? Color.lerp(const Color(0xFFFFD60A), Colors.white, pulso * 0.5)! : const Color(0xFFFFD60A))
          : const Color(0x33203038);
      c.drawRect(r, _relleno);
      _trazo
        ..strokeWidth = 1
        ..color = const Color(0x66203038);
      c.drawRect(r, _trazo);
    }

    // Palanca cromada a la izquierda del tanque.
    final pivote = g.p(-46, -99);
    var angulo = 0.0;
    if (j.desdePalanca < 0.6) {
      angulo = -0.9 * (1 - j.desdePalanca / 0.6);
    } else if (lista && mov != Movimiento.nada) {
      angulo = sin(t * 12) * 0.16;
    }
    c.save();
    c.translate(pivote.dx, pivote.dy);
    c.rotate(angulo);
    if (lista) {
      _relleno.color = const Color(0xFFFFD60A).withValues(alpha: 0.30 + 0.4 * pulso);
      c.drawCircle(Offset(-13 * s, 0), 7.5 * s, _relleno);
    }
    _relleno.color = oscuro ? const Color(0xFF8E9BA4) : const Color(0xFF9AA8B2);
    c.drawRect(Rect.fromLTRB(-13 * s, -1.2 * s, 0, 1.2 * s), _relleno);
    _relleno.color = oscuro ? const Color(0xFFCAD4DA) : const Color(0xFFE8EEF2);
    c.drawCircle(Offset(-13 * s, 0), 3.6 * s, _relleno);
    _trazo
      ..strokeWidth = max(1.0, 0.4 * s)
      ..color = const Color(0xFF6C7C88);
    c.drawCircle(Offset(-13 * s, 0), 3.6 * s, _trazo);
    c.restore();
    _relleno.color = const Color(0xFF7D8E9A);
    c.drawRect(Rect.fromCenter(center: pivote, width: 3 * s, height: 5 * s), _relleno);
    if (lista) {
      final jala = _texto(tr('¡JALA!', 'PULL!'), max(8.0, 3.4 * s), const Color(0xFF2B1A12));
      final centro = g.p(-56, -87) + Offset(0, mov == Movimiento.nada ? 0 : sin(t * 8) * 2);
      final caja = Rect.fromCenter(center: centro, width: jala.width + 8, height: jala.height + 6);
      _relleno.color = const Color(0xFFFFD60A);
      c.drawRect(caja, _relleno);
      _trazo
        ..strokeWidth = 1.5
        ..color = const Color(0xFF2B1A12);
      c.drawRect(caja, _trazo);
      jala.paint(c, centro - Offset(jala.width / 2, jala.height / 2));
    }

    // Tubo del tanque a la poceta.
    _relleno.color = oscuro ? const Color(0xFF8E9BA4) : const Color(0xFFC5D0D8);
    c.drawRect(Rect.fromLTRB(g.p(-5, -50).dx, g.p(0, -50).dy, g.p(5, -47).dx, g.p(0, -47).dy), _relleno);
  }

  // ----- Poceta de frente, cortada: pedestal, porcelana, interior, borde.
  void _poceta(Canvas c, GeoFusion g) {
    final s = g.s;
    _relleno.color = oscuro ? const Color(0x55000000) : const Color(0x33000000);
    c.drawOval(Rect.fromCenter(center: g.p(0, 149), width: 92 * s, height: 7 * s), _relleno);
    _sombreado
      ..shader = _porcelana
      ..color = const Color(0xFF000000);
    c.drawPath(_pedestal, _sombreado);
    _trazo
      ..strokeWidth = max(1.0, 0.45 * s)
      ..color = const Color(0xFF7D8E9A);
    c.drawPath(_pedestal, _trazo);
    c.drawPath(_exterior, _sombreado);
    c.drawPath(_exterior, _trazo);
    _sombreado.shader = _interiorShader;
    c.drawPath(_interior, _sombreado);
    // Sombra interna en el fondo de la taza.
    _relleno.color = const Color(0x1A1E3A4A);
    c.drawOval(Rect.fromCenter(center: g.p(0, 112), width: 40 * s, height: 12 * s), _relleno);
    // Borde (aro) de la poceta.
    final aro = Rect.fromLTRB(g.p(-62, -6).dx, g.p(0, -6).dy, g.p(62, 3).dx, g.p(0, 3).dy);
    _sombreado.shader = _porcelana;
    c.drawRect(aro, _sombreado);
    c.drawRect(aro, _trazo);
    _relleno.color = const Color(0x99FFFFFF);
    c.drawRect(Rect.fromLTRB(aro.left + 2, aro.top + 1.5, aro.right - 2, aro.top + 1.5 + 0.9 * s), _relleno);
  }

  double _agitacion() {
    var a = j.peligro * 0.4;
    if (j.cuentaDesborde > 0) a = max(a, 0.6 + j.cuentaDesborde / segundosDesborde);
    if (j.temblando) a = max(a, 1.2);
    if (j.desdePalanca < 1.2 || j.desdeDescargaReal < 1.8) a = max(a, 1.4);
    return mov == Movimiento.nada ? 0 : a;
  }

  static const double _yAgua = 86;

  Path _superficie(GeoFusion g, double t, {required bool cerrar}) {
    final a = 0.6 + 2.6 * _agitacion();
    final p = Path();
    for (var x = -56.0; x <= 56.0; x += 4) {
      final y = _yAgua + sin(x * 0.23 + t * 3.1) * a * 0.55 + sin(x * 0.09 - t * 2.2) * a * 0.45;
      final o = g.p(x, y);
      if (x == -56) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    if (cerrar) {
      p
        ..lineTo(g.p(56, 130).dx, g.p(56, 130).dy)
        ..lineTo(g.p(-56, 130).dx, g.p(-56, 130).dy)
        ..close();
    }
    return p;
  }

  void _aguaAtras(Canvas c, GeoFusion g, double t) {
    c.save();
    c.clipPath(_interior);
    _sombreado
      ..shader = _agua
      ..color = const Color(0xFF000000);
    c.drawPath(_superficie(g, t, cerrar: true), _sombreado);
    // Burbujas que suben.
    if (mov != Movimiento.nada) {
      _trazo
        ..strokeWidth = 1
        ..color = const Color(0x99FFFFFF);
      for (var i = 0; i < 7; i++) {
        final x = -36 + i * 12 + sin(t * 1.3 + i * 1.7) * 3;
        final y = 118 - ((t * 9 + i * 5.3) % (118 - _yAgua));
        c.drawCircle(g.p(x, y), (0.7 + (i % 3) * 0.35) * g.s, _trazo);
      }
    }
    c.restore();
  }

  void _remolino(Canvas c, GeoFusion g, double t) {
    double f = 0;
    if (j.desdePalanca < 1.2) f = sin(j.desdePalanca / 1.2 * pi);
    if (j.desdeDescargaReal < 1.8) f = max(f, sin(j.desdeDescargaReal / 1.8 * pi) * 1.3);
    if (f <= 0.01) return;
    c.save();
    c.clipPath(_interior);
    final centro = g.p(0, 104);
    final ciclon = imagenes['ciclon'];
    if (ciclon != null) {
      c.save();
      c.translate(centro.dx, centro.dy);
      c.rotate(-t * 9);
      final lado = 70 * g.s * f;
      _img
        ..colorFilter = null
        ..color = Color.fromRGBO(255, 255, 255, (0.55 * f).clamp(0.0, 0.8));
      c.drawImageRect(ciclon, _src, Rect.fromCenter(center: Offset.zero, width: lado, height: lado), _img);
      c.restore();
    }
    _trazo
      ..strokeWidth = 1.6 * g.s
      ..color = Colors.white.withValues(alpha: (0.75 * f).clamp(0.0, 0.9));
    for (var k = 0; k < 3; k++) {
      final p = Path();
      for (var i = 0; i <= 30; i++) {
        final th = i / 30 * pi * 3.2;
        final r = (2 + th * 4.2) * f;
        final a = th - t * 8 + k * pi * 2 / 3;
        final o = centro + Offset(cos(a) * r * g.s, sin(a) * r * g.s * 0.55);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      c.drawPath(p, _trazo);
    }
    c.restore();
  }

  // ----- Guía punteada desde la garra hasta donde va a caer.
  void _guia(Canvas c, GeoFusion g) {
    if (j.fase != FaseFusion.jugando) return;
    final r = radioDe(j.actual);
    final x = j.apunte;
    final yFin = j.alturaDeCaida(x, r);
    if (!yFin.isFinite) return;
    final listo = j.puedeSoltar;
    _relleno.color = oscuro ? const Color(0xCCFFFFFF) : const Color(0xCC2B1A12);
    final alfaBase = listo ? 1.0 : 0.35;
    for (var y = yColgado + r + 3; y < yFin - 1; y += 4.2) {
      _relleno.color = _relleno.color.withValues(alpha: 0.75 * alfaBase);
      c.drawCircle(g.p(x, y), 0.7 * g.s, _relleno);
    }
    _trazo
      ..strokeWidth = max(1.0, 0.45 * g.s)
      ..color = (oscuro ? Colors.white : const Color(0xFF2B1A12)).withValues(alpha: 0.45 * alfaBase);
    c.drawCircle(g.p(x, yFin), r * g.s, _trazo);
  }

  // ----- Los mojones en la poceta.
  void _mojones(Canvas c, GeoFusion g, double t) {
    final caer = j.cayendo;
    final objetivo = caer != null ? Offset(caer.x, caer.y) : Offset(j.apunte, yColgado);
    final peligro = j.peligro;
    final perdio = j.fase == FaseFusion.desbordado;
    for (final m in j.mojones) {
      if (!m.vivo) continue;
      final pop = m.deFusion && m.edad < 0.25 && mov != Movimiento.nada ? 1 + 0.32 * sin(m.edad / 0.25 * pi) : 1.0;
      final cg = (m.carga * 0.35).clamp(0.0, 1.0);
      final golpe = mov == Movimiento.nada ? 0.0 : m.golpe;
      var sy = (1 - 0.22 * golpe - 0.11 * cg) * pop;
      var sx = (1 + 0.18 * golpe + 0.07 * cg) * pop;
      if (m.nivel == 7) sx *= 1.1;
      // Mientras cae se estira un poquito.
      if (m == caer && mov != Movimiento.nada) {
        final v = (m.vy / 420).clamp(0.0, 1.0);
        sy *= 1 + 0.14 * v;
        sx *= 1 - 0.08 * v;
      }
      var rot = ((m.id * 37) % 11 - 5) * 0.025;
      if (mov != Movimiento.nada) rot += (m.vx * 0.0016).clamp(-0.25, 0.25);
      var dx = 0.0;
      final arriba = m.y - m.r < lineaDesborde + 14;
      if (mov == Movimiento.completo && (peligro > 0.55 || j.temblando)) {
        dx = sin(t * 47 + m.id * 1.3) * 0.35 * (j.temblando ? 1 : peligro);
      }
      var mirada = objetivo - Offset(m.x, m.y);
      final d = mirada.distance;
      mirada = d > 1 ? mirada / d : Offset.zero;
      if (m == caer) mirada = const Offset(0, 1);
      final miedo = perdio || (peligro > 0.6 && arriba) || (m == caer && m.vy > 200);
      _dibujarMojon(c, g, m.x + dx, m.y, m.r, m.nivel,
          sx: sx, sy: sy, rot: rot, id: m.id, mirada: mirada, miedo: miedo, sudor: peligro > 0.5 && arriba, t: t);
      if ((perdio || j.cuentaDesborde > 0) && m.y - m.r < lineaDesborde && m.edad > 1) {
        _trazo
          ..strokeWidth = 2
          ..color = const Color(0xFFFF3B30).withValues(alpha: perdio ? 1 : 0.5 + 0.5 * sin(t * 14).abs());
        c.drawCircle(g.p(m.x, m.y), m.r * g.s + 3, _trazo);
      }
    }
  }

  void _fantasmas(Canvas c, GeoFusion g, double t) {
    for (final f in ef.fantasmas) {
      if (f.t < 0) {
        _dibujarMojon(c, g, f.x, f.y, radioDe(f.nivel), f.nivel, id: f.nivel, t: t, mirada: const Offset(0, 1), miedo: true);
        continue;
      }
      final u = (f.t / f.dur).clamp(0.0, 1.0);
      if (f.hundir) {
        final y = f.y + u * u * 30;
        _dibujarMojon(c, g, f.x, y, radioDe(f.nivel) * (1 - u * 0.5), f.nivel,
            alfa: 1 - u, id: f.nivel, t: t, mirada: const Offset(0, 1), sx: 1 - u * 0.2, sy: 1 + u * 0.3);
      } else {
        // Espiral hacia el desagüe.
        const cx = 0.0, cy = 104.0;
        final a0 = atan2(f.y - cy, f.x - cx);
        final r0 = sqrt((f.x - cx) * (f.x - cx) + (f.y - cy) * (f.y - cy));
        final a = a0 + f.giro * u * 7;
        final r = r0 * (1 - u);
        _dibujarMojon(c, g, cx + cos(a) * r, cy + sin(a) * r * 0.7, radioDe(f.nivel) * (1 - u * 0.75), f.nivel,
            rot: f.giro * u * 9, alfa: 1 - u * u, id: f.nivel, t: t, mirada: Offset(cos(a + 1), sin(a + 1)), miedo: true);
      }
    }
  }

  void _aguaDelante(Canvas c, GeoFusion g, double t) {
    c.save();
    c.clipPath(_interior);
    final sup = _superficie(g, t, cerrar: true);
    _relleno.color = oscuro ? const Color(0x5530759A) : const Color(0x4D5CC4E4);
    c.drawPath(sup, _relleno);
    _trazo
      ..strokeWidth = max(1.0, 0.5 * g.s)
      ..color = const Color(0xB3FFFFFF);
    c.drawPath(_superficie(g, t, cerrar: false), _trazo);
    c.restore();
  }

  // ----- Línea roja de desborde.
  void _linea(Canvas c, GeoFusion g, double t) {
    final pel = j.peligro;
    final cuenta = j.cuentaDesborde;
    final pulso = cuenta > 0 && mov != Movimiento.nada ? 0.5 + 0.5 * sin(t * 16) : 0.0;
    _trazo
      ..strokeWidth = (1.2 + 0.4 * pel + 1.6 * pulso) * max(1.0, g.s * 0.5)
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFFFF3B30).withValues(alpha: (0.35 + 0.65 * max(pel, cuenta > 0 ? 1 : 0)).clamp(0.0, 1.0));
    for (var x = -mitadAncho; x < mitadAncho; x += 6) {
      c.drawLine(g.p(x, lineaDesborde), g.p(min(x + 3.5, mitadAncho), lineaDesborde), _trazo);
    }
    _trazo.strokeCap = StrokeCap.round;
  }

  // ----- Una mosca que da vueltas cerca del borde: algo siempre se mueve.
  void _mosca(Canvas c, GeoFusion g, double t) {
    final mosca = imagenes['mosca'];
    if (mosca == null || mov == Movimiento.nada) return;
    final x = sin(t * 0.9) * 46 + sin(t * 2.7) * 6;
    final y = -16 + sin(t * 1.7) * 7 + cos(t * 3.9) * 3;
    final lado = 8 * g.s;
    c.save();
    final o = g.p(x, y);
    c.translate(o.dx, o.dy);
    c.rotate(cos(t * 0.9) * 0.5);
    if (cos(t * 0.9) < 0) c.scale(-1, 1);
    _img
      ..colorFilter = null
      ..color = const Color(0xFFFFFFFF);
    c.drawImageRect(mosca, _src, Rect.fromCenter(center: Offset.zero, width: lado, height: lado), _img);
    c.restore();
  }

  // ----- Riel, garra y el mojón colgado.
  void _garra(Canvas c, GeoFusion g, double t) {
    final s = g.s;
    final yRiel = -45.0;
    _relleno.color = oscuro ? const Color(0xFF7C8A94) : const Color(0xFF9AA8B2);
    c.drawRect(Rect.fromLTRB(g.p(-56, yRiel - 1.2).dx, g.p(0, yRiel - 1.2).dy, g.p(56, yRiel + 1.2).dx, g.p(0, yRiel + 1.2).dy), _relleno);
    if (j.fase != FaseFusion.jugando) return;
    final x = j.apunte;
    final r = radioDe(j.actual);
    final espera = j.esperaFraccion;
    final carro = g.p(x, yRiel);
    _relleno.color = const Color(0xFF3B4A55);
    c.drawRect(Rect.fromCenter(center: carro, width: 12 * s, height: 5 * s), _relleno);
    _relleno.color = const Color(0xFFFFD60A);
    c.drawRect(Rect.fromCenter(center: carro, width: 8 * s, height: 1.6 * s), _relleno);

    c.save();
    c.translate(carro.dx, carro.dy);
    c.rotate(ef.balanceo);
    final largo = (yColgado - yRiel) * s;
    final yCubo = largo - r * s - 2.2 * s;
    _trazo
      ..strokeWidth = max(1.0, 0.55 * s)
      ..color = const Color(0xFF3B4A55);
    c.drawLine(Offset(0, 2.5 * s), Offset(0, yCubo), _trazo);
    // Brazos de la garra: abiertos mientras recarga.
    final abre = espera > 0 ? 1.0 : 0.0;
    _trazo.strokeWidth = max(1.2, 0.9 * s);
    for (final lado in const [-1.0, 1.0]) {
      final p = Path()
        ..moveTo(0, yCubo)
        ..quadraticBezierTo(lado * (r + 3 + abre * 4) * s, yCubo + 1 * s, lado * (r * 0.7 + abre * 5) * s, yCubo + (r * 0.9 + 2) * s);
      c.drawPath(p, _trazo);
    }
    _relleno.color = const Color(0xFF3B4A55);
    c.drawCircle(Offset(0, yCubo), 1.8 * s, _relleno);
    c.restore();

    // El mojón colgado aparece con un rebote.
    final aparece = mov == Movimiento.nada ? 1.0 : _easeOutBack((1 - espera).clamp(0.0, 1.0));
    if (aparece > 0.02) {
      final o = Offset(sin(-ef.balanceo) * (yColgado - yRiel), cos(ef.balanceo) * (yColgado - yRiel));
      final miedo = j.peligro > 0.6;
      _dibujarMojon(c, g, x + o.dx, yRiel + o.dy, r * aparece, j.actual,
          rot: ef.balanceo * 0.8, id: -2, mirada: const Offset(0, 1), miedo: miedo, t: t, sudor: miedo);
    }
  }

  void _particulas(Canvas c, GeoFusion g) {
    if (mov == Movimiento.nada) return;
    final s = g.s;
    for (var i = 0; i < EfectosFusion.maxParticulas; i++) {
      final v = ef._vida[i];
      if (v <= 0) continue;
      final f = (v / ef._dur[i]).clamp(0.0, 1.0);
      final o = g.p(ef._x[i], ef._y[i]);
      final color = Color(ef._color[i]);
      final tam = ef._tam[i] * s;
      switch (ef._tipo[i]) {
        case 1:
          _relleno.color = color.withValues(alpha: f);
          final l = tam * (0.5 + f);
          c.drawRect(Rect.fromCenter(center: o, width: l * 0.45, height: l * 1.6), _relleno);
          c.drawRect(Rect.fromCenter(center: o, width: l * 1.6, height: l * 0.45), _relleno);
        default:
          _relleno.color = color.withValues(alpha: min(1.0, f * 1.6));
          c.drawCircle(o, tam * (0.6 + 0.4 * f), _relleno);
      }
    }
  }

  void _flotantes(Canvas c, GeoFusion g) {
    for (final f in ef.flotantes) {
      final u = (f.t / f.dur).clamp(0.0, 1.0);
      final sube = mov == Movimiento.nada ? 0.0 : u * 16;
      final o = g.p(f.x, f.y - sube);
      final escala = f.escala * (mov == Movimiento.nada ? 1 : (u < 0.15 ? 0.6 + u / 0.15 * 0.5 : 1.1 - min(0.1, (u - 0.15))));
      final alfa = u > 0.7 ? 1 - (u - 0.7) / 0.3 : 1.0;
      c.save();
      c.translate(o.dx, o.dy);
      c.scale(escala);
      if (alfa < 1) c.saveLayer(null, _capaAlfa..color = Color.fromRGBO(0, 0, 0, alfa));
      final off = Offset(-f.relleno.width / 2, -f.relleno.height / 2);
      f.borde.paint(c, off);
      f.relleno.paint(c, off);
      if (alfa < 1) c.restore();
      c.restore();
    }
  }

  // ----- Un mojón: PNG con tinte, ojos que miran, accesorios por nivel.
  void _dibujarMojon(
    Canvas c,
    GeoFusion g,
    double x,
    double y,
    double r,
    int nivel, {
    double sx = 1,
    double sy = 1,
    double rot = 0,
    double alfa = 1,
    int id = 0,
    Offset mirada = Offset.zero,
    bool miedo = false,
    bool sudor = false,
    bool ojos = true,
    required double t,
  }) {
    if (r <= 0.05) return;
    final R = r * g.s;
    final k = R / 118;
    final o = g.p(x, y);
    c.save();
    c.translate(o.dx, o.dy);
    if (rot != 0) c.rotate(rot);
    if (sx != 1 || sy != 1) {
      // Aplastado desde abajo: la base no se mueve.
      c.translate(0, R * (1 - sy));
      c.scale(sx, sy);
    }

    // Rey: capa roja detrás y aura.
    if (nivel == nivelMaximo) {
      _relleno.color = const Color(0xFFFFD60A).withValues(alpha: 0.22 * alfa);
      c.drawCircle(Offset(0, -6 * k), R * 1.32, _relleno);
      _relleno.color = const Color(0xFFB3122C).withValues(alpha: alfa);
      final capa = Path()
        ..moveTo(-70 * k, -40 * k)
        ..quadraticBezierTo(-150 * k, 60 * k, -128 * k, 112 * k)
        ..lineTo(128 * k, 112 * k)
        ..quadraticBezierTo(150 * k, 60 * k, 70 * k, -40 * k)
        ..close();
      c.drawPath(capa, _relleno);
      _relleno.color = Colors.white.withValues(alpha: alfa);
      c.drawRect(Rect.fromLTRB(-128 * k, 100 * k, 128 * k, 114 * k), _relleno);
    } else if (nivel == 8) {
      _relleno.color = const Color(0xFFFFD60A).withValues(alpha: 0.18 * alfa);
      c.drawCircle(Offset(0, 4 * k), R * 1.25, _relleno);
    }

    final poo = imagenes['poo'];
    if (poo != null) {
      _img
        ..colorFilter = _filtros[nivel]
        ..color = Color.fromRGBO(255, 255, 255, alfa);
      c.drawImageRect(poo, _src, Rect.fromLTWH(-128 * k, -140 * k, 256 * k, 256 * k), _img);
    } else {
      _relleno.color = coloresNivel[nivel].withValues(alpha: alfa);
      c.drawOval(Rect.fromCenter(center: Offset(0, 60 * k), width: 230 * k, height: 110 * k), _relleno);
      c.drawOval(Rect.fromCenter(center: Offset(0, 0), width: 180 * k, height: 100 * k), _relleno);
      c.drawOval(Rect.fromCenter(center: Offset(0, -60 * k), width: 120 * k, height: 80 * k), _relleno);
    }

    if (ojos && R > 3) {
      final parpadea = mov != Movimiento.nada && ((t + id * 0.37) % 3.7) < 0.12;
      if (nivel == 5) {
        _lentes(c, k, alfa);
      } else {
        for (final ex in const [-44.0, 43.0]) {
          final centro = Offset(ex * k, 17 * k);
          final ojo = Rect.fromCenter(center: centro, width: 76 * k, height: (miedo ? 64 : 58) * k);
          if (parpadea) {
            _relleno.color = coloresNivel[nivel].withValues(alpha: alfa);
            c.drawOval(ojo, _relleno);
            _trazo
              ..strokeWidth = max(0.8, 6 * k)
              ..color = const Color(0xFF2B1A12).withValues(alpha: alfa);
            c.drawLine(Offset(ojo.left + 8 * k, centro.dy), Offset(ojo.right - 8 * k, centro.dy), _trazo);
            continue;
          }
          _relleno.color = Colors.white.withValues(alpha: alfa);
          c.drawOval(ojo, _relleno);
          _trazo
            ..strokeWidth = max(0.6, 4 * k)
            ..color = const Color(0xFF2B1A12).withValues(alpha: alfa * 0.8);
          c.drawOval(ojo, _trazo);
          final rp = (miedo ? 10.0 : 15.5) * k;
          final pupila = centro + Offset(mirada.dx * 15 * k, mirada.dy * 11 * k);
          _relleno.color = const Color(0xFF2B1A12).withValues(alpha: alfa);
          c.drawCircle(pupila, rp, _relleno);
          _relleno.color = Colors.white.withValues(alpha: alfa);
          c.drawCircle(pupila + Offset(-rp * 0.35, -rp * 0.35), rp * 0.35, _relleno);
        }
      }
    }

    switch (nivel) {
      case 6:
        _bigote(c, k, alfa);
      case 7:
        _relleno.color = const Color(0xFFFF7FA0).withValues(alpha: 0.55 * alfa);
        c.drawCircle(Offset(-80 * k, 52 * k), 15 * k, _relleno);
        c.drawCircle(Offset(80 * k, 52 * k), 15 * k, _relleno);
      case 8:
        if (mov != Movimiento.nada) {
          for (var i = 0; i < 3; i++) {
            final a = t * 2.2 + i * 2.09;
            final p = Offset(cos(a) * 128 * k, sin(a) * 100 * k);
            final l = (10 + 6 * sin(t * 6 + i)) * k;
            _relleno.color = Colors.white.withValues(alpha: alfa);
            c.drawRect(Rect.fromCenter(center: p, width: l * 0.5, height: l * 2), _relleno);
            c.drawRect(Rect.fromCenter(center: p, width: l * 2, height: l * 0.5), _relleno);
          }
        }
      case nivelMaximo:
        _corona(c, k, alfa, t);
    }

    if (sudor) {
      final gota = imagenes['sudor'];
      final balanceo = mov == Movimiento.nada ? 0.0 : sin(t * 9 + id) * 6 * k;
      if (gota != null) {
        _img
          ..colorFilter = null
          ..color = Color.fromRGBO(255, 255, 255, alfa);
        c.drawImageRect(gota, _src, Rect.fromCenter(center: Offset(96 * k, -88 * k + balanceo), width: 80 * k, height: 80 * k), _img);
      } else {
        _relleno.color = const Color(0xFF8ED8F2).withValues(alpha: alfa);
        c.drawCircle(Offset(96 * k, -88 * k + balanceo), 14 * k, _relleno);
      }
    }
    c.restore();
  }

  void _lentes(Canvas c, double k, double alfa) {
    final lentes = imagenes['lentes'];
    if (lentes != null) {
      final f = 1.0 * k;
      _img
        ..colorFilter = null
        ..color = Color.fromRGBO(255, 255, 255, alfa);
      c.drawImageRect(lentes, _src, Rect.fromLTWH(-127 * f, 17 * k - 124 * f, 256 * f, 256 * f), _img);
    } else {
      _relleno.color = const Color(0xFF14181C).withValues(alpha: alfa);
      c.drawRect(Rect.fromCenter(center: Offset(-44 * k, 17 * k), width: 84 * k, height: 50 * k), _relleno);
      c.drawRect(Rect.fromCenter(center: Offset(43 * k, 17 * k), width: 84 * k, height: 50 * k), _relleno);
      c.drawRect(Rect.fromCenter(center: Offset(0, 6 * k), width: 40 * k, height: 8 * k), _relleno);
    }
  }

  void _bigote(Canvas c, double k, double alfa) {
    _relleno.color = const Color(0xFF1E120C).withValues(alpha: alfa);
    for (final lado in const [-1.0, 1.0]) {
      final p = Path()
        ..moveTo(0, 50 * k)
        ..quadraticBezierTo(lado * 28 * k, 34 * k, lado * 58 * k, 52 * k)
        ..quadraticBezierTo(lado * 76 * k, 60 * k, lado * 84 * k, 42 * k)
        ..quadraticBezierTo(lado * 82 * k, 70 * k, lado * 56 * k, 70 * k)
        ..quadraticBezierTo(lado * 26 * k, 70 * k, 0, 62 * k)
        ..close();
      c.drawPath(p, _relleno);
    }
  }

  void _corona(Canvas c, double k, double alfa, double t) {
    final corona = imagenes['corona'];
    final brinco = mov == Movimiento.nada ? 0.0 : sin(t * 3) * 3 * k;
    if (corona != null) {
      final f = 0.62 * k;
      c.save();
      c.translate(0, -96 * k + brinco);
      c.rotate(-0.12);
      _img
        ..colorFilter = null
        ..color = Color.fromRGBO(255, 255, 255, alfa);
      c.drawImageRect(corona, _src, Rect.fromLTWH(-128 * f, -239 * f, 256 * f, 256 * f), _img);
      c.restore();
    } else {
      _relleno.color = const Color(0xFFFFD60A).withValues(alpha: alfa);
      final p = Path()
        ..moveTo(-60 * k, -100 * k)
        ..lineTo(-60 * k, -150 * k)
        ..lineTo(-30 * k, -120 * k)
        ..lineTo(0, -160 * k)
        ..lineTo(30 * k, -120 * k)
        ..lineTo(60 * k, -150 * k)
        ..lineTo(60 * k, -100 * k)
        ..close();
      c.drawPath(p, _relleno);
    }
  }

  @override
  bool shouldRepaint(PintorFusion old) =>
      old.j != j || old.ef != ef || old.oscuro != oscuro || old.imagenes != imagenes || old.mov != mov;
}
