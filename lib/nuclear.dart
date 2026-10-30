import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show db;
import 'perfil.dart' show PantallaPerfil;

/// HEXA POOP (6 cagadas en un día): la explosión nuclear y la alerta que le llega a todos.
/// El servidor anota cada HEXA en `hazanas` (trigger cagadas_hazana). Al abrir o volver a la
/// app se buscan las de otros de las últimas 48 h que este teléfono no ha visto y explota una vez.

const amarilloNuclear = Color(0xFFF4FF3A);
const verdeNuclear = Color(0xFF3DDC00);

/// Una HEXA de otro: su perfil (para el Avatar) y cuántas hizo ese día.
typedef Hazana = ({Map<String, dynamic> perfil, int n});

const _claveVista = 'hazana_vista';
const _columnas = 'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

Future<void>? _enCurso;

/// Lo que dure la revisión y la alerta (o nada si no hay). Los otros avisos al abrir esperan esto
/// para no salir encima de la explosión.
Future<void> esperarExplosion() => _enCurso ?? Future.value();

/// Busca HEXA POOP de otros sin ver y, si hay, muestra la alerta. Si ya hay una revisión en curso,
/// devuelve esa: abrir y volver a la app al mismo tiempo no explota dos veces.
Future<void> revisarHazanas(BuildContext context) =>
    _enCurso ??= _revisar(context).catchError((_) {}).whenComplete(() => _enCurso = null);

Future<void> _revisar(BuildContext context) async {
  final yo = db.auth.currentUser?.id;
  if (yo == null) return;
  final List<Hazana> lista;
  try {
    final prefs = await SharedPreferences.getInstance();
    final vista = prefs.getInt(_claveVista) ?? 0;
    final desde = DateTime.now().toUtc().subtract(const Duration(hours: 48)).toIso8601String();
    // Las de gente bloqueada (en cualquier dirección) no llegan: lo filtra la política de la tabla.
    final filas = await db
        .from('hazanas')
        .select('id, user_id, n, profiles($_columnas)')
        .eq('tipo', 'hexa')
        .neq('user_id', yo)
        .gt('id', vista)
        .gt('created_at', desde)
        .order('id', ascending: false)
        .limit(20);
    if (filas.isEmpty) return;
    // Se marca vista antes de explotar: si cierran la app a mitad, no vuelve a salir.
    await prefs.setInt(_claveVista, filas.map((f) => (f['id'] as num).toInt()).reduce(math.max));
    final vistos = <String>{};
    lista = [
      for (final f in filas)
        if (f['profiles'] is Map && vistos.add(f['user_id'] as String))
          (perfil: Map<String, dynamic>.from(f['profiles'] as Map), n: (f['n'] as num?)?.toInt() ?? 6),
    ];
  } catch (_) {
    return;
  }
  if (lista.isEmpty || !context.mounted) return;
  final id = await mostrarAlertaNuclear(context, lista);
  if (id != null && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: id)));
  }
}

/// La alerta a pantalla completa. Devuelve el id del perfil que quieren ver, o null si cerraron.
Future<String?> mostrarAlertaNuclear(BuildContext context, List<Hazana> hazanas) {
  final modo = movimiento(context);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Material(type: MaterialType.transparency, child: AlertaNuclear(hazanas: hazanas, modo: modo)),
  );
}

/// Avance de 0 a 1 de [t] dentro del tramo [a, b].
double _tramo(double t, double a, double b, [Curve curva = Curves.linear]) => curva.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Sacudida de pantalla que se apaga en la primera mitad de la explosión.
Offset sacudidaNuclear(double t, {double fuerza = 18}) {
  final a = (1 - _tramo(t, 0, .5)) * fuerza;
  return Offset(math.sin(t * 150) * a, math.cos(t * 113) * a * .7);
}

/// Golpes del teléfono durante la explosión. Van por tramos de la animación (sin Timers): se
/// llama con el avance en cada cuadro y suena al pasar cada marca.
class Retumbos {
  Retumbos([this.marcas = const [0, .04, .1, .18, .28, .4, .55]]);

  final List<double> marcas;
  var _siguiente = 0;

  void seguir(double t) {
    var golpe = false;
    while (_siguiente < marcas.length && t >= marcas[_siguiente]) {
      _siguiente++;
      golpe = true;
    }
    if (golpe) HapticFeedback.heavyImpact();
  }
}

/// Dónde está el casquete del hongo cuando ya creció [crece] (0 a 1).
Rect _casquete(Size s, double crece) {
  final base = math.min(s.width, s.height * .7);
  return Rect.fromCenter(
    center: Offset(s.width / 2, s.height * .68 - s.height * .38 * crece),
    width: base * (.18 + .58 * crece),
    height: base * (.12 + .24 * crece),
  );
}

/// La explosión: destello blanco, ondas de choque, bola de fuego que sube y se vuelve hongo,
/// y 💩☢️💥 volando. [t] va de 0 a 1 y lo maneja quien la usa. Con [Movimiento.simple] solo
/// queda el destello; con [Movimiento.nada], nada.
class Explosion extends StatelessWidget {
  const Explosion({super.key, required this.t, this.modo = Movimiento.completo});

  final double t;
  final Movimiento modo;

  static const _tipos = ['💩', '☢️', '💥'];
  static final _restos = () {
    final azar = math.Random(6);
    return [
      for (var i = 0; i < 18; i++)
        (vx: azar.nextDouble() * 2 - 1, vy: -(.6 + azar.nextDouble() * .9), giro: azar.nextDouble() * 6 - 3, tamano: 22 + azar.nextDouble() * 22, emoji: _tipos[i % 3]),
    ];
  }();

  @override
  Widget build(BuildContext context) {
    if (modo == Movimiento.nada) return const SizedBox.expand();
    final destello = t < .03 ? 1.0 : 1 - _tramo(t, .03, .22);
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, caja) {
        final s = caja.biggest;
        final suelo = Offset(s.width / 2, s.height * .68);
        final crece = _tramo(t, .02, .55, Curves.easeOutCubic);
        final cap = _casquete(s, crece);
        final vuelo = _tramo(t, .03, .85);
        final encima = _tramo(t, .35, .5);
        Widget en(Offset p, double tamano, Widget hijo) => Positioned(left: p.dx - tamano / 2, top: p.dy - tamano / 2, child: hijo);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (modo == Movimiento.completo) ...[
              Positioned.fill(child: CustomPaint(painter: _PintorHongo(t))),
              for (final r in _restos)
                en(
                  suelo + Offset(r.vx * s.width * .55 * vuelo, r.vy * s.height * .75 * vuelo + s.height * .9 * vuelo * vuelo),
                  r.tamano,
                  Opacity(
                    opacity: 1 - _tramo(t, .6, .9),
                    child: Transform.rotate(angle: r.giro * vuelo, child: Emoji(r.emoji, tamano: r.tamano)),
                  ),
                ),
              // Los que se quedan montados en el hongo.
              if (encima > 0)
                for (var i = 0; i < 5; i++)
                  en(
                    Offset(cap.center.dx + (i - 2) * cap.width * .19, cap.top + cap.height * .1 + math.sin(t * 20 + i) * 3),
                    30,
                    Opacity(opacity: encima, child: Emoji(_tipos[i % 3], tamano: 30)),
                  ),
            ],
            if (destello > 0) Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: destello))),
          ],
        );
      }),
    );
  }
}

class _PintorHongo extends CustomPainter {
  _PintorHongo(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    final crece = _tramo(t, .02, .55, Curves.easeOutCubic);
    final enfria = _tramo(t, .5, 1);
    final base = math.min(s.width, s.height * .7);
    final suelo = Offset(s.width / 2, s.height * .68);
    final cap = _casquete(s, crece);
    // Del blanco del estallido al rojo y humo cuando se enfría.
    final caliente = Color.lerp(const Color(0xFFFFF8C9), amarilloNuclear, enfria)!;
    final medio = Color.lerp(const Color(0xFFFF9F1C), const Color(0xFFE85D04), enfria)!;
    final frio = Color.lerp(const Color(0xFFD62828), const Color(0xFF3A1A12), enfria)!;

    // Brillo verde radiactivo detrás de todo.
    final halo = Rect.fromCircle(center: cap.center, radius: base * (.3 + .6 * crece));
    canvas.drawRect(
      Offset.zero & s,
      Paint()..shader = RadialGradient(colors: [verdeNuclear.withValues(alpha: .5 * crece), verdeNuclear.withValues(alpha: 0)]).createShader(halo),
    );

    // Ondas de choque desde el suelo.
    final lado = math.max(s.width, s.height);
    for (var i = 0; i < 3; i++) {
      final o = _tramo(t, i * .06, i * .06 + .45, Curves.easeOutQuad);
      if (o <= 0 || o >= 1) continue;
      canvas.drawOval(
        Rect.fromCenter(center: suelo, width: lado * 1.6 * o, height: lado * .7 * o),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 22 * (1 - o)
          ..color = (i == 1 ? verdeNuclear : Colors.white).withValues(alpha: (1 - o) * .85),
      );
    }

    // La bola de fuego del principio, antes de que suba el hongo.
    final bola = 1 - _tramo(t, .1, .3);
    if (bola > 0) {
      final r = base * (.05 + .2 * _tramo(t, 0, .12, Curves.easeOut));
      final centro = suelo.translate(0, -r * .5);
      canvas.drawCircle(
        centro,
        r,
        Paint()
          ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: bola), amarilloNuclear.withValues(alpha: bola), medio.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: centro, radius: r)),
      );
    }

    // Falda de polvo en el suelo.
    final falda = Rect.fromCenter(center: suelo, width: base * (.3 + .9 * crece), height: base * (.06 + .1 * crece));
    canvas.drawOval(falda, Paint()..shader = RadialGradient(colors: [medio, frio.withValues(alpha: .8), frio.withValues(alpha: 0)]).createShader(falda));

    // Tallo.
    final abajo = base * (.12 + .06 * crece);
    final arriba = base * (.05 + .03 * crece);
    final tope = cap.center.dy + cap.height * .2;
    final mitad = (suelo.dy + tope) / 2;
    final tallo = Path()
      ..moveTo(suelo.dx - abajo / 2, suelo.dy)
      ..quadraticBezierTo(suelo.dx - arriba * .4, mitad, suelo.dx - arriba / 2, tope)
      ..lineTo(suelo.dx + arriba / 2, tope)
      ..quadraticBezierTo(suelo.dx + arriba * .4, mitad, suelo.dx + abajo / 2, suelo.dy)
      ..close();
    canvas.drawPath(
      tallo,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [caliente, medio, frio]).createShader(tallo.getBounds()),
    );

    // Anillo a media altura del tallo.
    if (crece > .3) {
      final y = suelo.dy - (suelo.dy - tope) * .55;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(suelo.dx, y), width: arriba * 3.2, height: arriba * .9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = arriba * .35
          ..color = medio.withValues(alpha: _tramo(crece, .3, .6)),
      );
    }

    // Casquete: la sombra de abajo, el cuerpo y los bultos de nube arriba.
    canvas.drawOval(cap.translate(0, cap.height * .18), Paint()..color = frio);
    canvas.drawOval(
      cap,
      Paint()
        ..shader = RadialGradient(center: const Alignment(0, -.3), radius: .7, colors: [caliente, medio, frio], stops: const [0, .55, 1]).createShader(cap),
    );
    for (var i = 0; i < 5; i++) {
      final centro = Offset(cap.left + cap.width * (.15 + .175 * i), cap.top + cap.height * .32);
      final r = cap.height * (.32 + .08 * math.sin(i * 1.7 + t * 6));
      canvas.drawCircle(
        centro,
        r,
        Paint()..shader = RadialGradient(colors: [caliente, medio.withValues(alpha: .9)]).createShader(Rect.fromCircle(center: centro, radius: r)),
      );
    }
    canvas.drawOval(
      cap.inflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = verdeNuclear.withValues(alpha: .6 * crece),
    );
  }

  @override
  bool shouldRepaint(_PintorHongo viejo) => viejo.t != t;
}

/// "☢️ ALERTA NUCLEAR ☢️" con la explosión detrás, el Avatar de quien la logró y sus botones.
/// Varias juntas: una sola explosión con la lista. Un toque salta la animación.
class AlertaNuclear extends StatefulWidget {
  const AlertaNuclear({super.key, required this.hazanas, this.modo = Movimiento.completo});

  final List<Hazana> hazanas;
  final Movimiento modo;

  @override
  State<AlertaNuclear> createState() => _AlertaNuclearState();
}

class _AlertaNuclearState extends State<AlertaNuclear> with TickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  AnimationController? _tiembla;
  final _retumbos = Retumbos();

  bool get _completo => widget.modo == Movimiento.completo;

  @override
  void initState() {
    super.initState();
    if (widget.modo == Movimiento.nada) {
      _c.value = 1;
    } else {
      _c.forward();
    }
    if (_completo) {
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

  void _tocar() {
    if (_c.isAnimating) _c.value = 1;
  }

  void _cerrar([String? id]) => Navigator.of(context).pop(id);

  @override
  Widget build(BuildContext context) {
    // showGeneralDialog no trae Material: sin él los InkWell revientan y el texto sale subrayado.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tocar,
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _tiembla]),
        builder: (context, _) {
          final t = _c.value;
          final texto = switch (widget.modo) {
            Movimiento.completo => _tramo(t, .3, .45),
            Movimiento.simple => _tramo(t, .08, .2),
            Movimiento.nada => 1.0,
          };
          final fase = (_tiembla?.value ?? 0) * 2 * math.pi;
          final tiembla = _completo ? Offset(math.sin(fase * 11) * 2.5, math.cos(fase * 7) * 1.5) : Offset.zero;
          return Transform.translate(
            offset: _completo ? sacudidaNuclear(t) : Offset.zero,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      gradient: RadialGradient(center: Alignment(0, -.3), radius: .9, colors: [Color(0x553DDC00), Colors.black]),
                    ),
                  ),
                ),
                Positioned.fill(child: Explosion(t: t, modo: widget.modo)),
                SafeArea(
                  child: IgnorePointer(
                    ignoring: texto < 1,
                    child: Opacity(
                      opacity: texto,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Transform.translate(offset: tiembla, child: const _Franja()),
                            const Spacer(),
                            _panel(tiembla),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _panel(Offset tiembla) {
    final hazanas = widget.hazanas;
    final una = hazanas.length == 1;
    const blanco = TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2);
    final suave = TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 13);
    String usuario(Hazana h) => '@${h.perfil['username'] ?? '?'}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .8), border: Border.all(color: verdeNuclear)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (una) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(border: Border.all(color: amarilloNuclear)),
                child: Avatar(hazanas.first.perfil, tamano: 88),
              ),
            ),
            const SizedBox(height: 12),
            Transform.translate(
              offset: tiembla,
              child: Text(
                usuario(hazanas.first),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: amarilloNuclear, fontWeight: FontWeight.w900, fontSize: 26),
              ),
            ),
            const SizedBox(height: 4),
            Text(tr('logró HEXA POOP', 'pulled off a HEXA POOP'), textAlign: TextAlign.center, style: blanco.copyWith(fontSize: 16)),
            const SizedBox(height: 4),
            Text(tr('${hazanas.first.n} cagadas en un día', '${hazanas.first.n} poops in one day'), textAlign: TextAlign.center, style: suave),
          ] else ...[
            Text(tr('${hazanas.length} HEXA POOP EN 48 H', '${hazanas.length} HEXA POOPS IN 48 H'), textAlign: TextAlign.center, style: blanco.copyWith(color: amarilloNuclear)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final h in hazanas)
                    InkWell(
                      onTap: () => _cerrar(h.perfil['id'] as String?),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: .15)))),
                        child: Row(
                          children: [
                            Avatar(h.perfil, tamano: 36),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(usuario(h), maxLines: 1, overflow: TextOverflow.ellipsis, style: blanco.copyWith(letterSpacing: 0, fontSize: 16)),
                            ),
                            Text(tr('${h.n} hoy', '${h.n} that day'), style: suave),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: .6)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (una) ...[
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: amarilloNuclear,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(52),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 15),
                    ),
                    onPressed: () => _cerrar(hazanas.first.perfil['id'] as String?),
                    child: Text(tr('VER PERFIL', 'SEE PROFILE')),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: .4)),
                    minimumSize: const Size.fromHeight(52),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 15),
                  ),
                  onPressed: _cerrar,
                  child: Text(tr('CERRAR', 'CLOSE')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cinta de peligro amarilla y negra con "☢️ ALERTA NUCLEAR ☢️".
class _Franja extends StatelessWidget {
  const _Franja();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _PintorFranjas(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Emoji('☢️', tamano: 24),
                const SizedBox(width: 8),
                Text(
                  tr('ALERTA NUCLEAR', 'NUCLEAR ALERT'),
                  style: const TextStyle(color: amarilloNuclear, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 18),
                ),
                const SizedBox(width: 8),
                const Emoji('☢️', tamano: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PintorFranjas extends CustomPainter {
  const _PintorFranjas();

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = amarilloNuclear);
    final negro = Paint()..color = Colors.black;
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    for (var x = -s.height; x < s.width; x += 28) {
      canvas.drawPath(
        Path()
          ..moveTo(x, s.height)
          ..lineTo(x + 14, s.height)
          ..lineTo(x + 14 + s.height, 0)
          ..lineTo(x + s.height, 0)
          ..close(),
        negro,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorFranjas viejo) => false;
}
