import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'emoji.dart';
import 'main.dart' show db;
import 'tema.dart';

/// Cagadas que pide la hoja secreta de Tips. Early birds: por ahora 0 (todos la ven);
/// después sube a 10.
const minimoSecreto = 0;

const _etiquetas = {
  1: 'Destructiva',
  2: 'Dolorosa',
  3: 'Meh, dolió',
  4: 'Normal',
  5: 'Rica',
  6: 'Placentera',
  7: 'Celestial',
};

/// Imagen de la escala: mojón carbonizado en 1, con alas en 7 y 💩 normal en el medio.
Widget iconoPlacer(int valor, {double tamano = 32}) {
  if (valor <= 1) return Image.asset('assets/img/mojon_carbonizado.png', width: tamano, height: tamano);
  if (valor >= 7) return Image.asset('assets/img/mojon_angel.png', width: tamano, height: tamano);
  return Emoji('💩', tamano: tamano * .8);
}

const destructivas = ['dolorosa', 'sangrante', 'ardiente'];
const placenteras = ['virtuosa', 'placentera', 'liberadora'];

/// Respuesta de la pregunta secreta.
typedef Calificacion = ({int? placer, Set<String> etiquetas});

/// La pregunta secreta después de cada cagada. null si la cierra sin responder.
Future<Calificacion?> preguntarPlacer(BuildContext context) => showModalBottomSheet<Calificacion>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _Pregunta(),
    );

class _Pregunta extends StatefulWidget {
  const _Pregunta();

  @override
  State<_Pregunta> createState() => _PreguntaState();
}

class _PreguntaState extends State<_Pregunta> {
  int? _placer;
  final _etiquetas = <String>{};

  Widget _chips(List<String> cuales) => Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final e in cuales)
            FilterChip(
              label: Text(e.toUpperCase()),
              selected: _etiquetas.contains(e),
              onSelected: (si) => setState(() => si ? _etiquetas.add(e) : _etiquetas.remove(e)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final respondio = _placer != null || _etiquetas.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Rotulo('Pregunta secreta'),
            const SizedBox(height: 8),
            Center(child: MojonDelMomento(placer: _placer, etiquetas: _etiquetas, tamano: 110)),
            const SizedBox(height: 12),
            Text('¿Lo disfrutaste?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            Text('Del 1 al 7, ¿cuánto?', textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var v = 1; v <= 7; v++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: (v == _placer ? FilledButton.new : OutlinedButton.new)(
                        onPressed: () => setState(() => _placer = v),
                        style: ButtonStyle(
                          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
                          minimumSize: const WidgetStatePropertyAll(Size.zero),
                        ),
                        child: Column(
                          children: [
                            if (v == 1 || v == 7) iconoPlacer(v, tamano: 30) else const SizedBox(height: 30),
                            Text('$v', style: numeros(context, tamano: 16, weight: FontWeight.w800, color: v == _placer ? p.sobrePrimario : null)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('DESTRUCTIVA', style: numeros(context, tamano: 10, color: p.textoSuave)),
                const Spacer(),
                Text('CELESTIAL', style: numeros(context, tamano: 10, color: p.textoSuave)),
              ],
            ),
            const SizedBox(height: 14),
            const Rotulo('Lo malo'),
            const SizedBox(height: 6),
            _chips(destructivas),
            const SizedBox(height: 12),
            const Rotulo('Lo bueno'),
            const SizedBox(height: 6),
            _chips(placenteras),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: respondio ? () => Navigator.pop(context, (placer: _placer, etiquetas: _etiquetas)) : null,
              child: const Text('LISTO'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Me reservo el comentario')),
          ],
        ),
      ),
    );
  }
}

/// El 💩 de la pregunta: cara del meme, o enojado con rayos si fue destructiva. El 1 lo
/// carboniza y el 7 le pone alas. Lo malo: 💦 (dolorosa), rojo y 🩸 (sangrante), 🔥 (ardiente).
/// Lo bueno: aureola (virtuosa), ✨ (placentera), flota (liberadora). Con las tres buenas
/// brilla como oro; con las tres malas se vuelve demonio (cuernos, brillo rojo, tiembla).
class MojonDelMomento extends StatefulWidget {
  const MojonDelMomento({super.key, required this.placer, required this.etiquetas, this.tamano = 96});

  final int? placer;
  final Set<String> etiquetas;
  final double tamano;

  @override
  State<MojonDelMomento> createState() => _MojonDelMomentoState();
}

class _MojonDelMomentoState extends State<MojonDelMomento> with SingleTickerProviderStateMixin {
  late final _reloj = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tamano;
    final e = widget.etiquetas;
    final oro = placenteras.every(e.contains);
    final infierno = destructivas.every(e.contains);
    final malas = destructivas.where(e.contains).length;
    final buenas = placenteras.where(e.contains).length;
    // La nota manda: con 4 o más la cara no se enoja aunque marque algo malo. Sin nota,
    // deciden las etiquetas.
    final destructiva = widget.placer != null ? widget.placer! <= 3 : malas > buenas;
    return AnimatedBuilder(
      animation: _reloj,
      builder: (context, _) {
        final v = _reloj.value;
        // Cara según cómo le fue: enojado con rayos si fue destructiva, la del meme si no.
        // 1: carbonizado, cuerpo negro con la cara como brasas y echando humo.
        final cara = widget.placer == 1
            ? 'assets/img/mojon_carbonizado_cara.png'
            : destructiva
                ? 'assets/img/mojon_enojado.png'
                : 'assets/img/mojon_meme.png';
        Widget mojon = Image.asset(cara, width: t, height: t);
        if (e.contains('sangrante')) {
          mojon = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFFF6B6B), BlendMode.modulate), child: mojon);
        }
        if (oro) mojon = efectoAvatar(mojon, 2, v * 3);
        final temblor = infierno ? math.sin(v * math.pi * 40) * 5 : e.contains('dolorosa') ? math.sin(v * math.pi * 24) * 2 : 0.0;
        // Liberadora: se eleva y flota, liviano.
        final flota = e.contains('liberadora') ? -t * .12 + math.sin(v * 2 * math.pi) * t * .06 : 0.0;
        return SizedBox(
          width: t * 1.7,
          height: t * 1.5,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Las tres malas: modo demonio, con un brillo rojo que late detrás.
              if (infierno)
                Positioned(
                  top: t * .2,
                  child: Container(
                    width: t * 1.3,
                    height: t * 1.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        const Color(0xFFE0261A).withValues(alpha: .35 + .3 * math.sin(v * 2 * math.pi * 2).abs()),
                        const Color(0x00E0261A),
                      ]),
                    ),
                  ),
                ),
              if (widget.placer == 1)
                // Humo saliendo por un lado, para no tapar los rayos.
                Positioned(
                  top: t * .2 - 10 * v,
                  right: t * .05,
                  child: Opacity(opacity: 1 - v * .7, child: Transform.rotate(angle: -math.pi / 3, child: Emoji('💨', tamano: t * .5))),
                ),
              if (e.contains('ardiente'))
                Positioned(
                  top: -t * .1,
                  child: Transform.scale(scaleY: 1 + .06 * math.sin(v * 2 * math.pi * 3), child: Emoji('🔥', tamano: t * 1.1)),
                ),
              // 7: alas. El ala de Fluent es derecha (hombro a la izquierda); la izquierda va volteada.
              if (widget.placer == 7) ...[
                Positioned(
                  left: 0,
                  top: t * .2 + flota,
                  child: Transform.flip(flipX: true, child: Emoji('🪽', tamano: t * .7)),
                ),
                Positioned(right: 0, top: t * .2 + flota, child: Emoji('🪽', tamano: t * .7)),
              ],
              Positioned(top: t * .3 + flota, child: Transform.translate(offset: Offset(temblor, 0), child: mojon)),
              if (infierno)
                Positioned(
                  top: t * .12 + flota,
                  child: Transform.translate(
                    offset: Offset(temblor, 0),
                    child: Image.asset('assets/img/cuernos.png', width: t * .85),
                  ),
                ),
              if (destructiva)
                Positioned(
                  top: -t * .12 + 3 * math.sin(v * 2 * math.pi * 4),
                  child: Image.asset('assets/img/rayos.png', width: t * .9),
                ),
              if (e.contains('virtuosa'))
                Positioned(
                  top: t * .12 + flota,
                  child: Container(
                    width: t * .6,
                    height: t * .16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.elliptical(t * .3, t * .08)),
                      border: Border.all(color: acento, width: t * .045),
                      boxShadow: [BoxShadow(color: acento.withValues(alpha: .7), blurRadius: 10)],
                    ),
                  ),
                ),
              if (e.contains('placentera'))
                for (final (i, (dx, dy)) in const [(-.75, -.6), (.8, -.4), (-.7, .7), (.75, .75)].indexed)
                  Align(
                    alignment: Alignment(dx, dy),
                    child: Opacity(
                      opacity: .5 + .5 * math.sin(v * 2 * math.pi + i),
                      child: Emoji('✨', tamano: t * .26),
                    ),
                  ),
              if (e.contains('dolorosa')) Positioned(right: t * .2, top: t * .25, child: Emoji('💦', tamano: t * .32)),
              if (e.contains('sangrante'))
                Positioned(
                  left: t * .35,
                  top: t * 1.05 + 6 * v,
                  child: Opacity(opacity: 1 - v * .6, child: Emoji('🩸', tamano: t * .26)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Ranking secreto: placenteras contra destructivas.
class TablaPlacer extends StatefulWidget {
  const TablaPlacer({super.key, this.version = 0, required this.periodo, required this.soloSiguiendo, required this.onTap});

  final int version;
  final String periodo;
  final bool soloSiguiendo;
  final ValueChanged<String> onTap;

  @override
  State<TablaPlacer> createState() => _TablaPlacerState();
}

class _TablaPlacerState extends State<TablaPlacer> {
  List<Map<String, dynamic>>? _filas;
  bool _placenteras = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(TablaPlacer viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.version != widget.version || viejo.periodo != widget.periodo || viejo.soloSiguiendo != widget.soloSiguiendo) {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    try {
      final r = await db.rpc('ranking_placer', params: {'period': widget.periodo, 'solo_siguiendo': widget.soloSiguiendo});
      if (mounted) setState(() => _filas = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _filas = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    if (filas == null) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    final p = paleta(context);
    final campo = _placenteras ? 'placenteras' : 'destructivas';
    final orden = [...filas]..sort((a, b) => (b[campo] as int).compareTo(a[campo] as int));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, icon: iconoPlacer(7, tamano: 22), label: const Text('PLACENTERAS')),
            ButtonSegment(value: false, icon: iconoPlacer(1, tamano: 22), label: const Text('DESTRUCTIVAS')),
          ],
          selected: {_placenteras},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _placenteras = s.first),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde)),
          child: Column(
            children: [
              for (final (i, f) in orden.indexed)
                InkWell(
                  onTap: () => widget.onTap(f['user_id']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: p.borde))),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text((i + 1).toString().padLeft(2, '0'),
                              style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.textoSuave)),
                        ),
                        const SizedBox(width: 8),
                        Avatar(f, tamano: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f['username'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w700, color: p.texto)),
                              Text(
                                f['promedio'] == null ? 'Sin calificar' : 'Promedio ${f['promedio']} · ${_etiqueta(f['promedio'])}',
                                style: TextStyle(fontSize: 12, color: p.textoSuave),
                              ),
                            ],
                          ),
                        ),
                        _Conteo(icono: iconoPlacer(7, tamano: 20), valor: f['placenteras'], fuerte: _placenteras),
                        const SizedBox(width: 10),
                        _Conteo(icono: iconoPlacer(1, tamano: 20), valor: f['destructivas'], fuerte: !_placenteras),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Desliza → para volver.',
            style: TextStyle(fontSize: 12, color: p.textoSuave)),
      ],
    );
  }

  String _etiqueta(Object promedio) => _etiquetas[(num.parse('$promedio')).round().clamp(1, 7)]!;
}

class _Conteo extends StatelessWidget {
  const _Conteo({required this.icono, required this.valor, required this.fuerte});

  final Widget icono;
  final Object? valor;
  final bool fuerte;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: fuerte ? 1 : .45,
        child: Row(
          children: [
            icono,
            const SizedBox(width: 2),
            Text('$valor', style: numeros(context, tamano: fuerte ? 18 : 14, weight: FontWeight.w800)),
          ],
        ),
      );
}

/// Esquina doblada al final de Tips. Al arrastrarla hacia arriba se pasa la página y aparece
/// el mojón que desbloquea el ranking secreto.
class HojaSecreta extends StatefulWidget {
  const HojaSecreta({super.key, this.onDescubierta});

  /// Se llama al cerrar las felicidades: la hoja ya no tiene que volver a salir.
  final VoidCallback? onDescubierta;

  @override
  State<HojaSecreta> createState() => _HojaSecretaState();
}

class _HojaSecretaState extends State<HojaSecreta> with SingleTickerProviderStateMixin {
  static const _minima = 52.0;
  double _doblez = _minima;
  late final _vuelta = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void dispose() {
    _vuelta.dispose();
    super.dispose();
  }

  Future<void> _soltar(double alto) async {
    if (_doblez < 150) {
      setState(() => _doblez = _minima);
      return;
    }
    // Pasa la página: la esquina crece hasta tapar todo y se abre el secreto.
    final desde = _doblez;
    void crecer() => setState(() => _doblez = desde + (alto * 2 - desde) * Curves.easeIn.transform(_vuelta.value));
    _vuelta.addListener(crecer);
    await _vuelta.forward();
    _vuelta.removeListener(crecer);
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const _Felicidades(),
    ));
    final yo = db.auth.currentUser?.id;
    if (yo != null) await db.from('profiles').update({'placer_desbloqueado': true}).eq('id', yo).catchError((_) => null);
    widget.onDescubierta?.call();
    if (!mounted) return;
    _vuelta.reset();
    setState(() => _doblez = _minima);
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height;
    // Zona de toque de 72 px; el doblez crece hacia arriba y a la izquierda, fuera de ella.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Arrastre vertical y no pan: así le gana al scroll de la lista de Tips.
      onVerticalDragUpdate: (d) => setState(() => _doblez = (_doblez - d.delta.dy).clamp(_minima, alto)),
      onVerticalDragEnd: (_) => _soltar(alto),
      child: SizedBox(
        width: 72,
        height: 72,
        child: OverflowBox(
          alignment: Alignment.bottomRight,
          minWidth: 0,
          minHeight: 0,
          maxWidth: _doblez,
          maxHeight: _doblez,
          child: CustomPaint(size: Size.square(_doblez), painter: _Doblez(paleta(context))),
        ),
      ),
    );
  }
}

/// Esquina de hoja doblada: debajo se ve café y encima el reverso del papel, curvo.
class _Doblez extends CustomPainter {
  _Doblez(this.p);

  final Paleta p;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final debajo = Path()
      ..moveTo(s, 0)
      ..lineTo(s, s)
      ..lineTo(0, s)
      ..close();
    canvas.drawPath(debajo, Paint()..color = const Color(0xFF5A3418));
    // El reverso sale del doblez hacia la esquina contraria, con la punta un poco enrollada.
    final reverso = Path()
      ..moveTo(s, 0)
      ..quadraticBezierTo(s * .45, s * .2, s * .12, s * .12)
      ..quadraticBezierTo(s * .2, s * .45, 0, s)
      ..close();
    canvas.drawShadow(reverso, Colors.black, 4, false);
    canvas.drawPath(
      reverso,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, p.suave, p.bordeFuerte],
          stops: const [0, .55, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_Doblez viejo) => true;
}

/// El mojón que se acerca a la pantalla y felicita.
class _Felicidades extends StatefulWidget {
  const _Felicidades();

  @override
  State<_Felicidades> createState() => _FelicidadesState();
}

class _FelicidadesState extends State<_Felicidades> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            // Se acerca desde lejos con rebote y tiembla un poco al llegar.
            final cerca = Curves.elasticOut.transform((v / .7).clamp(0, 1));
            final tiembla = v > .55 ? math.sin(v * 60) * .05 * (1 - v) : 0.0;
            final globo = ((v - .55) / .3).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                for (final (i, (dx, dy)) in const [(-.7, -.5), (.75, -.35), (-.6, .45), (.65, .5), (0.0, -.75)].indexed)
                  Align(
                    alignment: Alignment(dx, dy),
                    child: Opacity(
                      opacity: globo,
                      child: Transform.rotate(angle: i * .7 + v * 2, child: const Emoji('✨', tamano: 44)),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(0, -40 * globo),
                  child: Transform.rotate(
                    angle: tiembla,
                    child: Transform.scale(scale: .1 + cerca * 1.0, child: Emoji('💩', tamano: ancho * .55)),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, .62),
                  child: Opacity(
                    opacity: globo,
                    child: Transform.scale(
                      scale: .8 + .2 * globo,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 2)),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('¡FELICIDADES!',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black)),
                            SizedBox(height: 4),
                            Text('Descubriste el secreto.\nAhora puedes ver el secreto de los demás.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black)),
                            SizedBox(height: 8),
                            Text('Ve al ranking y desliza ←', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Pista del lado secreto en el ranking: flecha grande que empuja hacia la izquierda.
class PistaSecreta extends StatefulWidget {
  const PistaSecreta({super.key});

  @override
  State<PistaSecreta> createState() => _PistaSecretaState();
}

class _PistaSecretaState extends State<PistaSecreta> with SingleTickerProviderStateMixin {
  late final _reloj = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Row(
      children: [
        AnimatedBuilder(
          animation: _reloj,
          builder: (context, hijo) {
            final v = Curves.easeInOut.transform(_reloj.value < .5 ? _reloj.value * 2 : 2 - _reloj.value * 2);
            return Transform.translate(offset: Offset(-14 * v, 0), child: hijo);
          },
          child: const Icon(Icons.arrow_back_rounded, size: 64, color: acento),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DESLIZA', style: numeros(context, tamano: 12, weight: FontWeight.w800, color: p.textoSuave)
                  .copyWith(letterSpacing: 2)),
              Text('(es un secreto... que tu mamá vende empanadas...)',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.textoSuave)),
            ],
          ),
        ),
      ],
    );
  }
}
