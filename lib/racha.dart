import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'nuclear.dart';
import 'tema.dart';

/// Rachas del día al estilo del anunciador de DotA. Siempre en inglés, en los dos idiomas: es el chiste.
/// Desde la segunda cagada del día el servidor también la manda al chat general (trigger cagadas_racha).
String? nombreRacha(int n) => switch (n) {
      < 2 => null,
      2 => 'DOUBLE POOP!',
      3 => 'TRIPLE POOP!',
      4 => 'ULTRA POOP!',
      5 => 'RAMPAGE!',
      _ => 'HEXA POOP!',
    };

/// Colores del texto y emoji que vuela, por nivel.
(List<Color>, String) estiloRacha(int n) => switch (n) {
      2 => (const [Color(0xFFFFE259), Color(0xFFFF9F1C)], '💩'),
      3 => (const [Color(0xFFFFB347), Color(0xFFFF3B30)], '💩'),
      4 => (const [Color(0xFFFF6FD8), Color(0xFF7B2FF7)], '🔥'),
      5 => (const [Color(0xFFFF3B30), Color(0xFF5A0000)], '💀'),
      _ => (const [amarilloNuclear, verdeNuclear], '☢️'),
    };

/// Desde TRIPLE la racha se queda en pantalla con COMPARTIR.
const rachaCompartible = 3;

/// Desde la sexta del día: HEXA POOP, con explosión nuclear (lib/nuclear.dart) y alerta para todos.
const rachaHexa = 6;

/// El anuncio a pantalla completa. La doble se cierra sola; desde la triple espera a que
/// la comparta o siga. [perfil] (fila con username y avatar) y [lugar] ("#2 de la semana")
/// van en la imagen para historias.
Future<void> mostrarRacha(BuildContext context, int n, {Map<String, dynamic>? perfil, String? lugar}) async {
  if (nombreRacha(n) == null) return;
  HapticFeedback.heavyImpact();
  final modo = movimiento(context);
  // El audio del anunciador va aquí cuando exista.
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Material(type: MaterialType.transparency, child: _Anuncio(n, perfil: perfil, lugar: lugar, modo: modo)),
  );
}

class _Anuncio extends StatefulWidget {
  const _Anuncio(this.n, {this.perfil, this.lugar, this.modo = Movimiento.completo});

  final int n;
  final Map<String, dynamic>? perfil;
  final String? lugar;
  // Solo la HEXA lo respeta: con nada sale quieta, con simple solo destello y texto.
  final Movimiento modo;

  @override
  State<_Anuncio> createState() => _AnuncioState();
}

class _AnuncioState extends State<_Anuncio> with TickerProviderStateMixin {
  late final _compartible = widget.n >= rachaCompartible;
  late final _hexa = widget.n >= rachaHexa;
  late final _bestia = _hexa && widget.modo == Movimiento.completo;
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: _hexa ? 3600 : 2600))
    ..forward(from: _hexa && widget.modo == Movimiento.nada ? 1 : 0).whenComplete(() {
      if (!_compartible) _cerrar();
    });
  // HEXA completa: el texto no deja de temblar y el teléfono retumba con la explosión.
  AnimationController? _tiembla;
  final _retumbos = Retumbos();
  final _azar = math.Random();
  late final _particulas = [
    for (var i = 0; i < 18; i++) (angulo: i / 18 * 2 * math.pi + _azar.nextDouble() * .3, distancia: 140 + _azar.nextDouble() * 160, giro: _azar.nextDouble() * 4 - 2),
  ];
  // Los que quedan regados por la pantalla cuando la racha se queda: (x, y) en fracción, tamaño y giro.
  late final _regados = [
    for (var i = 0; i < 14; i++)
      (x: _azar.nextDouble(), y: _azar.nextDouble() * .62, tamano: 26 + _azar.nextDouble() * 22, giro: _azar.nextDouble() * 1.4 - .7, opacidad: .35 + _azar.nextDouble() * .5),
  ];
  final _historia = GlobalKey();
  var _cerrado = false;
  var _compartiendo = false;

  void _cerrar() {
    if (_cerrado || !mounted) return;
    _cerrado = true;
    Navigator.pop(context);
  }

  /// Un toque: la doble se cierra; la compartible salta al final de la animación y,
  /// ya quieta, se cierra.
  void _tocar() {
    if (_compartible && _c.isAnimating) {
      _c.value = 1;
    } else {
      _cerrar();
    }
  }

  Future<void> _compartir() async {
    if (_compartiendo) return;
    setState(() => _compartiendo = true);
    try {
      final caja = _historia.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final imagen = await caja.toImage(pixelRatio: 3);
      final png = (await imagen.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      imagen.dispose();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: 'rey-cagon-racha.png')],
        fileNameOverrides: ['rey-cagon-racha.png'],
        text: tr('${nombreRacha(widget.n)} ¿Tú cuántas llevas? https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon',
            '${nombreRacha(widget.n)} How many have you done? https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon'),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('No se pudo compartir', 'Could not share'))));
      }
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_bestia) {
      _c.addListener(() => _retumbos.seguir(_c.value));
      _tiembla = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _tiembla?.dispose();
    super.dispose();
  }

  /// Avance de 0 a 1 dentro del tramo [a, b] de la animación.
  double _tramo(double a, double b, [Curve curva = Curves.linear]) => curva.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final nombre = nombreRacha(widget.n)!;
    final (colores, emoji) = estiloRacha(widget.n);
    final rampage = widget.n >= 5;
    final pantalla = MediaQuery.sizeOf(context);
    return GestureDetector(
      onTap: _tocar,
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _tiembla]),
        builder: (context, _) {
          final entrada = _tramo(0, .28, Curves.elasticOut);
          // La compartible no se desvanece: se queda con sus botones.
          final salida = _compartible ? 0.0 : _tramo(.85, 1);
          final quieta = _compartible ? _tramo(.6, .85) : 0.0;
          final temblor = _hexa && !_bestia ? 0.0 : math.max((1 - _tramo(.08, .45)) * (rampage ? 14 : 8), _bestia ? 3.0 : 0.0);
          final fase = _c.value * 120 + (_tiembla?.value ?? 0) * 2 * math.pi * 9;
          final dx = math.sin(fase) * temblor;
          final dy = math.cos(fase * .8) * temblor * .6;
          // La HEXA trae su propio destello blanco dentro de la explosión.
          final destello = _hexa ? 0.0 : 1 - _tramo(0, .12);
          final vuelo = _tramo(.05, .7, Curves.easeOutCubic);
          return Opacity(
            opacity: 1 - salida,
            // La HEXA completa sacude la pantalla entera.
            child: Transform.translate(offset: _bestia ? sacudidaNuclear(_c.value, fuerza: 22) : Offset.zero, child: Stack(
              alignment: Alignment.center,
              children: [
                // La imagen para historias se arma fuera de la pantalla para poder capturarla.
                if (_compartible)
                  Positioned(
                    left: -2 * _Historia.ancho - pantalla.width,
                    top: 0,
                    child: RepaintBoundary(
                      key: _historia,
                      child: _Historia(n: widget.n, perfil: widget.perfil, lugar: widget.lugar),
                    ),
                  ),
                Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .72 + .2 * quieta))),
                if (_compartible)
                  Positioned.fill(
                    child: Opacity(
                      opacity: quieta,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -.08),
                            radius: .8,
                            colors: [colores.last.withValues(alpha: .45), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_hexa) Positioned.fill(child: Explosion(t: _c.value, modo: widget.modo)),
                Positioned.fill(child: ColoredBox(color: colores.first.withValues(alpha: destello * .55))),
                if (_compartible)
                  for (final (i, r) in _regados.indexed)
                    Positioned(
                      left: r.x * pantalla.width - r.tamano / 2,
                      top: 40 + r.y * pantalla.height,
                      child: Opacity(
                        opacity: r.opacidad * quieta,
                        child: Transform.rotate(angle: r.giro, child: Emoji(_hexa ? const ['💩', '☢️', '💥'][i % 3] : emoji, tamano: r.tamano)),
                      ),
                    ),
                // Emojis que salen disparados desde el centro. La HEXA ya los tira con la explosión.
                if (!_hexa)
                  for (final p in _particulas)
                  Transform.translate(
                    offset: Offset(math.cos(p.angulo), math.sin(p.angulo)) * p.distancia * vuelo,
                    child: Transform.rotate(
                      angle: p.giro * vuelo * math.pi,
                      child: Opacity(opacity: (1 - vuelo).clamp(0.0, 1.0), child: Emoji(emoji, tamano: 40)),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(
                    scale: 3 - 2 * entrada,
                    child: Transform.rotate(
                      angle: -.06,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Letrero(nombre, colores: colores, tamano: _hexa ? 70 : rampage ? 64 : 52),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.n} POOPS TODAY',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: _tramo(.25, .4)),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_compartible)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 32 + MediaQuery.paddingOf(context).bottom,
                    child: IgnorePointer(
                      ignoring: quieta < 1,
                      child: Opacity(
                        opacity: quieta,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: acento,
                                foregroundColor: acentoTexto,
                                minimumSize: const Size.fromHeight(56),
                                textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16),
                              ),
                              onPressed: _compartiendo ? null : _compartir,
                              icon: _compartiendo
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: acentoTexto))
                                  : const Icon(Icons.ios_share),
                              label: Text(tr('COMPARTIR', 'SHARE')),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: .4)),
                                minimumSize: const Size.fromHeight(56),
                                textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16),
                              ),
                              onPressed: _cerrar,
                              child: Text(tr('SEGUIR CAGANDO', 'KEEP POOPING')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            )),
          );
        },
      ),
    );
  }
}

/// La imagen 9:16 para historias que se manda al compartir.
class _Historia extends StatelessWidget {
  const _Historia({required this.n, this.perfil, this.lugar});

  static const ancho = 360.0;
  static const alto = 640.0;

  final int n;
  final Map<String, dynamic>? perfil;
  final String? lugar;

  @override
  Widget build(BuildContext context) {
    final (colores, _) = estiloRacha(n);
    final nombre = perfil?['username'] as String?;
    final gris = Colors.white.withValues(alpha: .75);
    return SizedBox(
      width: ancho,
      height: alto,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0A09),
          gradient: RadialGradient(
            center: const Alignment(0, -.25),
            radius: .75,
            colors: [colores.last.withValues(alpha: .5), const Color(0xFF0B0A09)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: acento,
                child: Text(tr('REY CAGÓN', 'KING OF THE THRONE'),
                    style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 14)),
              ),
              const Spacer(flex: 3),
              if (perfil != null) Avatar(perfil!, tamano: 150) else const Emoji('💩', tamano: 150),
              const Spacer(flex: 2),
              Transform.rotate(
                angle: -.07,
                child: _Letrero(nombreRacha(n)!, colores: colores, tamano: 60),
              ),
              const SizedBox(height: 18),
              if (nombre != null)
                Text('@$nombre',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
              const SizedBox(height: 6),
              Text(
                [tr('$n cagadas hoy', '$n poops today'), ?lugar].join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(color: gris, fontSize: 14, letterSpacing: .5),
              ),
              const Spacer(flex: 3),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: .25))),
                child: Row(
                  children: [
                    const Emoji('🚽', tamano: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('¿Tú cuántas llevas?', 'How many have you done?'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(tr('Bájala en Google Play', 'Get it on Google Play'), style: TextStyle(color: gris, fontSize: 12)),
                          Text('Rey Cagón · King of the Throne', style: TextStyle(color: gris, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Texto grueso con borde negro, degradado y brillo, como el de los juegos.
class _Letrero extends StatelessWidget {
  const _Letrero(this.texto, {required this.colores, required this.tamano});

  final String texto;
  final List<Color> colores;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: tamano, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 1, height: 1);
    return FittedBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            Text(
              texto,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = tamano / 7
                  ..color = Colors.black,
                shadows: [Shadow(color: colores.last, blurRadius: 28)],
              ),
            ),
            ShaderMask(
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colores,
              ).createShader(r),
              child: Text(texto, style: base.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
