import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'animaciones.dart';
import 'emoji.dart';
import 'tema.dart';

/// Cagada fresca: cada cagada real da x2 de producción en el Imperio por [duracionFresca]
/// desde la hora de la cagada. El motor del Imperio lee [frescaHasta]; null = sin bono.
final frescaHasta = ValueNotifier<DateTime?>(null);

const duracionFresca = Duration(hours: 1);

Timer? _vence;

/// ¿Hay bono ahora?
bool get frescaVigente {
  final h = frescaHasta.value;
  return h != null && h.isAfter(DateTime.now());
}

/// Pone el bono a partir de la hora de [cagada] (null o ya vencida = sin bono) y programa
/// que se limpie solo al vencer.
void ponerFresca(DateTime? cagada, {DateTime? ahora}) {
  _vence?.cancel();
  _vence = null;
  final hasta = cagada?.toLocal().add(duracionFresca);
  final queda = hasta?.difference(ahora ?? DateTime.now());
  if (hasta == null || queda == null || queda <= Duration.zero) {
    frescaHasta.value = null;
    return;
  }
  frescaHasta.value = hasta;
  _vence = Timer(queda, () {
    if (frescaHasta.value == hasta) frescaHasta.value = null;
  });
}

/// Al abrir o volver a la app: la última cagada propia manda (también cuenta la del widget
/// de la pantalla de inicio y deshacer una cagada quita su bono). Sin red se queda lo que había.
Future<void> cargarFresca([SupabaseClient? cliente]) async {
  try {
    final db = cliente ?? Supabase.instance.client;
    final yo = db.auth.currentUser?.id;
    if (yo == null) return ponerFresca(null);
    final fila = await db.from('cagadas').select('created_at').eq('user_id', yo).order('created_at', ascending: false).limit(1).maybeSingle();
    final cuando = fila == null ? null : DateTime.tryParse('${fila['created_at']}');
    ponerFresca(cuando);
  } catch (_) {}
}

/// Tras un CAGUÉ que el servidor aceptó.
void frescaTrasCagar() => ponerFresca(DateTime.now());

/// El 🏭 de la barra. Con cagada fresca se ve apurado: late y tiembla, brilla, echa candela
/// y lleva el chip x2. Ya dentro del Imperio ([activo]) solo late suave.
class IconoImperio extends StatefulWidget {
  const IconoImperio({super.key, required this.activo});

  final bool activo;

  @override
  State<IconoImperio> createState() => _IconoImperioState();
}

class _IconoImperioState extends State<IconoImperio> with SingleTickerProviderStateMixin {
  // Un ciclo = dos latidos rápidos y una pausa corta, como corazón apurado.
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    frescaHasta.addListener(_cambio);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sincronizar();
  }

  // Solo corre el reloj mientras haya bono y se pueda animar.
  void _sincronizar() {
    final anima = frescaVigente && movimiento(context) != Movimiento.nada;
    if (anima && !_c.isAnimating) _c.repeat();
    if (!anima && _c.isAnimating) _c.stop();
  }

  void _cambio() {
    if (!mounted) return;
    _sincronizar();
    setState(() {});
  }

  @override
  void dispose() {
    frescaHasta.removeListener(_cambio);
    _c.dispose();
    super.dispose();
  }

  /// Escala del latido en el punto [t] del ciclo: pum-pum y descanso.
  static double _latido(double t) {
    double golpe(double centro) => math.max(0, 1 - ((t - centro) / .09).abs());
    return 1 + .2 * golpe(.1) + .14 * golpe(.32);
  }

  @override
  Widget build(BuildContext context) {
    const fabrica = Emoji('🏭', tamano: 24);
    if (!frescaVigente) return fabrica;
    final modo = movimiento(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final quieto = modo == Movimiento.nada;
        final latido = quieto ? 1.0 : _latido(t);
        // Tiembla solo con movimiento completo y si todavía no entró.
        final tiembla = modo == Movimiento.completo && !widget.activo;
        final giro = tiembla ? math.sin(t * 2 * math.pi * 6) * .11 : 0.0;
        final dx = tiembla ? math.sin(t * 2 * math.pi * 9) * 1.2 : 0.0;
        final brillo = quieto ? .7 : .45 + .55 * (latido - 1) / .2;
        // La candela parpadea a destiempo.
        final llama = quieto ? 1.0 : .85 + .25 * math.sin(t * 2 * math.pi * 3).abs();
        return SizedBox(
          width: 24,
          height: 24,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            // Resplandor detrás de la fábrica.
            Positioned(
              left: -10,
              top: -10,
              right: -10,
              bottom: -10,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [
                      const Color(0xFFFF7A00).withValues(alpha: .55 * brillo),
                      acento.withValues(alpha: .25 * brillo),
                      Colors.transparent,
                    ], stops: const [0, .45, 1]),
                  ),
                ),
              ),
            ),
            for (final (x, retraso) in const [(-9.0, 0.0), (7.0, .5)])
              Positioned(
                left: 12 + x - 6,
                bottom: -4,
                child: Transform.scale(
                  scale: quieto ? 1 : .8 + .35 * math.sin((t + retraso) * 2 * math.pi * 2).abs() * llama,
                  alignment: Alignment.bottomCenter,
                  child: const Emoji('🔥', tamano: 12),
                ),
              ),
            Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.rotate(angle: giro, child: Transform.scale(scale: latido, child: fabrica)),
            ),
            Positioned(
              right: -14,
              top: -9,
              child: Transform.rotate(
                angle: -.12,
                child: Transform.scale(
                  scale: quieto ? 1 : 1 + (latido - 1) * .6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: acento,
                      border: Border.all(color: acentoTexto),
                      borderRadius: BorderRadius.circular(radio),
                    ),
                    child: const Text('x2',
                        style: TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, fontSize: 10, height: 1.1, fontStyle: FontStyle.italic)),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
