// Movimientos del avatar comprados en la tienda de estilo del Imperio (ids mov_* de lib/imperio/estilos.dart).
// Se guardan en profiles.movimiento (null = quieto); el servidor solo deja poner uno comprado (trigger validar_movimiento).
// ConMovimiento anima cualquier avatar: un AnimationController por avatar animado, solo mientras está en pantalla.
//
// No confundir con elegirMovimiento de lib/animaciones.dart: ese es el nivel de animaciones de la app.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'imperio/estilos.dart' show movimientoNinguno;
import 'main.dart' show conReintento, db;
import 'tema.dart' show radio, acento;

/// Pone el movimiento del avatar del usuario. 'mov_ninguno' se guarda como null (quieto).
Future<void> ponerMovimientoAvatar(String id) async {
  final yo = db.auth.currentUser!.id;
  await conReintento(() => db.from('profiles').update({'movimiento': id == movimientoNinguno ? null : id}).eq('id', yo));
}

/// Las animaciones que sabe hacer ConMovimiento.
enum AnimAvatar { respirar, rebotar, saludar, temblar, girar, flotar, bailar, brillo }

const Map<String, AnimAvatar> _porId = {
  'mov_respirar': AnimAvatar.respirar,
  'mov_rebotar': AnimAvatar.rebotar,
  'mov_saludar': AnimAvatar.saludar,
  'mov_temblar': AnimAvatar.temblar,
  'mov_girar': AnimAvatar.girar,
  'mov_flotar': AnimAvatar.flotar,
  'mov_bailar': AnimAvatar.bailar,
  'mov_brillo': AnimAvatar.brillo,
};

/// La animación de un id de movimiento, o null (quieto, desconocido o null).
AnimAvatar? animDe(String? id) => id == null ? null : _porId[id];

/// Las que se animan en el nivel simple (en versión reducida). Temblar, girar y bailar se quedan quietas;
/// el brillo sale fijo, sin latir.
const animadasEnSimple = {AnimAvatar.respirar, AnimAvatar.rebotar, AnimAvatar.saludar, AnimAvatar.flotar};

/// Cómo se anima [id] con el nivel [nivel]: null = quieto. [reducida] = menos amplitud y más lento.
/// [fija] = solo el brillo dibujado, sin AnimationController.
({AnimAvatar anim, bool reducida, bool fija})? comoAnimar(String? id, Movimiento nivel) {
  final a = animDe(id);
  if (a == null || nivel == Movimiento.nada) return null;
  if (nivel == Movimiento.completo) return (anim: a, reducida: false, fija: false);
  if (a == AnimAvatar.brillo) return (anim: a, reducida: true, fija: true);
  if (!animadasEnSimple.contains(a)) return null;
  return (anim: a, reducida: true, fija: false);
}

/// Cuánto dura una vuelta de cada animación (en simple, un 50% más lenta).
Duration duracionDe(AnimAvatar a, {bool reducida = false}) {
  final ms = switch (a) {
    AnimAvatar.respirar => 2400,
    AnimAvatar.rebotar => 1400,
    AnimAvatar.saludar => 2000,
    AnimAvatar.temblar => 2200,
    AnimAvatar.girar => 4000,
    AnimAvatar.flotar => 3200,
    AnimAvatar.bailar => 1200,
    AnimAvatar.brillo => 1800,
  };
  return Duration(milliseconds: reducida ? ms * 3 ~/ 2 : ms);
}

/// Pose del avatar en el punto [t] (0..1) de la vuelta. dx, dy en fracciones del tamaño; angulo y giroY en radianes;
/// halo es la opacidad del borde del brillo (0 sin borde). En t = 0 todas están en reposo o casi.
typedef PoseAvatar = ({double dx, double dy, double escala, double angulo, double giroY, double halo});

const PoseAvatar poseQuieta = (dx: 0, dy: 0, escala: 1, angulo: 0, giroY: 0, halo: 0);

PoseAvatar poseDe(AnimAvatar a, double t, {bool reducida = false}) {
  final k = reducida ? .5 : 1.0;
  final onda = math.sin(t * 2 * math.pi);
  switch (a) {
    case AnimAvatar.respirar:
      // Sube y baja la escala como un pecho: 1 → 1.06 → 1.
      return (dx: 0, dy: 0, escala: 1 + .06 * k * (1 - math.cos(t * 2 * math.pi)) / 2, angulo: 0, giroY: 0, halo: 0);
    case AnimAvatar.rebotar:
      // Un salto en la primera mitad, quieto en la segunda; se aplasta un poco al caer.
      if (t >= .5) return poseQuieta;
      final u = t / .5;
      final alto = 4 * u * (1 - u);
      return (dx: 0, dy: -.14 * k * alto, escala: 1 + .04 * k * (alto - .5).abs() - .02 * k, angulo: 0, giroY: 0, halo: 0);
    case AnimAvatar.saludar:
      // Tres meneos en el primer 60% de la vuelta, luego descansa.
      if (t >= .6) return poseQuieta;
      final u = t / .6;
      return (dx: 0, dy: 0, escala: 1, angulo: .22 * k * math.sin(u * 3 * 2 * math.pi) * (1 - u), giroY: 0, halo: 0);
    case AnimAvatar.temblar:
      // Pujo: ráfaga de temblor en el primer 35%, un poquito más chico (aprieta) y luego suelta.
      if (t >= .35) return poseQuieta;
      final u = t / .35;
      final fuerza = math.sin(u * math.pi);
      return (dx: .035 * k * fuerza * math.sin(u * 22 * 2 * math.pi), dy: 0, escala: 1 - .05 * k * fuerza, angulo: 0, giroY: 0, halo: 0);
    case AnimAvatar.girar:
      // Una vuelta sobre sí mismo (eje vertical) en el primer 30%, con freno al final.
      if (t >= .3) return poseQuieta;
      final u = Curves.easeInOut.transform(t / .3);
      return (dx: 0, dy: 0, escala: 1, angulo: 0, giroY: u * 2 * math.pi, halo: 0);
    case AnimAvatar.flotar:
      final c = math.cos(t * 2 * math.pi);
      return (dx: .02 * k * c, dy: -.07 * k * (1 - c) / 2, escala: 1, angulo: .04 * k * onda, giroY: 0, halo: 0);
    case AnimAvatar.bailar:
      // Lado a lado con inclinación y dos brincos por vuelta.
      final brinco = math.sin(t * 2 * 2 * math.pi).abs();
      return (dx: .08 * k * onda, dy: -.06 * k * brinco, escala: 1, angulo: -.2 * k * onda, giroY: 0, halo: 0);
    case AnimAvatar.brillo:
      // El borde late entre medio y lleno; el avatar se infla apenas.
      final luz = (1 - math.cos(t * 2 * math.pi)) / 2;
      return (dx: 0, dy: 0, escala: 1 + .03 * k * luz, angulo: 0, giroY: 0, halo: .35 + .65 * luz);
  }
}

/// Envuelve un avatar y lo anima según [movimiento] (id mov_* o null). Respeta movimiento(context).
/// [semilla] desfasa la vuelta para que una lista no se mueva sincronizada. [tamano] es el lado del avatar (sin él se
/// mide con un LayoutBuilder en cada cuadro).
class ConMovimiento extends StatefulWidget {
  const ConMovimiento({super.key, required this.movimiento, required this.child, this.semilla = 0, this.tamano});

  final String? movimiento;
  final Widget child;
  final int semilla;
  final double? tamano;

  @override
  State<ConMovimiento> createState() => _ConMovimientoState();
}

class _ConMovimientoState extends State<ConMovimiento> with SingleTickerProviderStateMixin {
  AnimationController? _reloj;
  ({AnimAvatar anim, bool reducida, bool fija})? _plan;

  @override
  void initState() {
    super.initState();
    movimientoElegido.addListener(_cambioDeNivel);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustar();
  }

  // Cambiaron el nivel de animaciones en Ajustes: los avatares que ya están en pantalla se ajustan sin esperar.
  void _cambioDeNivel() {
    if (!mounted) return;
    setState(_ajustar);
  }

  @override
  void didUpdateWidget(ConMovimiento viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.movimiento != widget.movimiento) _ajustar();
  }

  void _ajustar() {
    final plan = comoAnimar(widget.movimiento, movimiento(context));
    final antes = _plan;
    _plan = plan;
    if (plan == null || plan.fija) {
      _reloj?.stop();
      return;
    }
    if (antes != null && antes.anim == plan.anim && antes.reducida == plan.reducida && (_reloj?.isAnimating ?? false)) return;
    final reloj = _reloj ??= AnimationController(vsync: this);
    reloj.duration = duracionDe(plan.anim, reducida: plan.reducida);
    reloj.value = (widget.semilla.abs() % 997) / 997;
    reloj.repeat();
  }

  @override
  void dispose() {
    movimientoElegido.removeListener(_cambioDeNivel);
    _reloj?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    if (plan == null) return widget.child;
    // El avatar se pinta una vez en su capa; cada cuadro solo se mueve la capa.
    final hijo = RepaintBoundary(child: widget.child);
    if (plan.fija) return _conPose(poseDe(plan.anim, .5, reducida: true), hijo);
    return AnimatedBuilder(
      animation: _reloj!,
      child: hijo,
      builder: (context, hijo) => _conPose(poseDe(plan.anim, _reloj!.value, reducida: plan.reducida), hijo!),
    );
  }

  Widget _conPose(PoseAvatar pose, Widget hijo) {
    final t = widget.tamano;
    if (t != null) return _posar(pose, hijo, t);
    return LayoutBuilder(builder: (context, c) => _posar(pose, hijo, c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 32.0));
  }

  Widget _posar(PoseAvatar pose, Widget hijo, double lado) {
    final m = Matrix4.identity()
      ..translateByDouble(pose.dx * lado, pose.dy * lado, 0, 1)
      ..scaleByDouble(pose.escala, pose.escala, 1, 1)
      ..rotateZ(pose.angulo);
    if (pose.giroY != 0) {
      m
        ..setEntry(3, 2, .002)
        ..rotateY(pose.giroY);
    }
    final movido = Transform(transform: m, alignment: pose.angulo != 0 ? Alignment.bottomCenter : Alignment.center, child: hijo);
    if (pose.halo <= 0) return movido;
    final borde = math.max(1.5, lado * .05);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -lado * .1,
          top: -lado * .1,
          right: -lado * .1,
          bottom: -lado * .1,
          child: IgnorePointer(
            child: Opacity(
              opacity: pose.halo.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radio),
                  border: Border.all(color: acento, width: borde),
                ),
              ),
            ),
          ),
        ),
        movido,
      ],
    );
  }
}
