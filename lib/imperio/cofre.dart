// Cofre del Trono 🎁: meta semanal de 3 días con cagada real (lunes a domingo, hora local). Lo cuenta y lo paga el servidor
// (`imperio_cofre`); aquí, la lógica de la semana (para tests y para mostrar) y el chip del Imperio.

import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'control.dart';

/// Días con cagada que pide el Cofre.
const int metaCofre = 3;

/// Lunes (a las 0:00) de la semana de [d], en la misma zona que [d].
DateTime lunesDe(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Días distintos con al menos una cagada ([locales], en hora local) en la semana que empieza en [lunes].
int diasConCagada(Iterable<DateTime> locales, DateTime lunes) {
  final fin = DateTime(lunes.year, lunes.month, lunes.day + 7);
  final dias = <DateTime>{
    for (final c in locales)
      if (!c.isBefore(lunes) && c.isBefore(fin)) DateTime(c.year, c.month, c.day),
  };
  return dias.length;
}

/// Racha de semanas al abrir el Cofre de la semana [lunes]: +1 si el último se abrió la semana anterior, si no 1.
/// Igual que `imperio_cofre` en el servidor.
int siguienteSemanasRacha(DateTime? cofreSemana, int semanasRacha, DateTime lunes) {
  if (cofreSemana == null) return 1;
  final anterior = DateTime(lunes.year, lunes.month, lunes.day - 7);
  return _mismoDia(cofreSemana, anterior) ? semanasRacha + 1 : 1;
}

/// "+2 Fichas · 1 h de producción" (y "· 3 semanas seguidas" si viene de racha).
String textoPremioCofre(int fichas, int ciruelas, int semanas) => [
      if (fichas > 0) tr('+$fichas Fichas', '+$fichas Tokens'),
      if (ciruelas > 0) tr('+$ciruelas Ciruelas', '+$ciruelas Plums'),
      tr('1 h de producción', '1 h of production'),
      if (semanas > 1) tr('$semanas semanas seguidas', '$semanas weeks in a row'),
    ].join(' · ');

/// Chip 🎁 x/3 de la cabecera del Imperio. Listo para abrir: borde de acento; al tocarlo se sacude y se abre.
class ChipCofre extends StatefulWidget {
  const ChipCofre({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  State<ChipCofre> createState() => _ChipCofreState();
}

class _ChipCofreState extends State<ChipCofre> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  bool _abriendo = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _tocar() async {
    final c = widget.control.cofre;
    if (c == null || _abriendo) return;
    if (!c.listo) {
      widget.avisar(
          '🎁',
          c.reclamado
              ? tr('Ya abriste el Cofre del Trono de esta semana. El lunes empieza otro.',
                  'You already opened this week\'s Throne Chest. A new one starts on Monday.')
              : tr('Cofre del Trono: caga de verdad $metaCofre días esta semana (llevas ${c.dias}) y ábrelo: +2 Fichas y 1 h de producción.',
                  'Throne Chest: really poop on $metaCofre days this week (${c.dias} so far) and open it: +2 Tokens and 1 h of production.'));
      return;
    }
    setState(() => _abriendo = true);
    final m = movimiento(context);
    _anim.duration = Duration(milliseconds: m == Movimiento.completo ? 600 : 200);
    final animacion = m == Movimiento.nada ? Future<void>.value() : _anim.forward(from: 0).orCancel.catchError((_) {});
    try {
      final r = await widget.control.reclamarCofre();
      await animacion;
      if (r != null) {
        widget.avisar('🎁', tr('Cofre del Trono: ', 'Throne Chest: ') + textoPremioCofre(r.fichasGanadas, r.ciruelasGanadas, r.semanasRacha));
      }
    } catch (e) {
      widget.avisar('💩', textoError(e));
    } finally {
      if (mounted) {
        _anim.reset();
        setState(() => _abriendo = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = widget.control.cofre;
    if (c == null) return const SizedBox.shrink();
    final simple = movimiento(context) != Movimiento.completo;
    final chip = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: c.listo ? acento : p.borde), borderRadius: BorderRadius.circular(radio)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Emoji('🎁', tamano: 16),
            const SizedBox(width: 5),
            Text(c.reclamado ? tr('LISTO', 'DONE') : '${c.dias.clamp(0, c.meta)}/${c.meta}',
                style: numeros(context, tamano: 13, weight: FontWeight.w800, color: c.reclamado ? p.textoSuave : null)),
          ],
        ),
      ),
    );
    return GestureDetector(
      key: const Key('chip_cofre'),
      onTap: _tocar,
      child: AnimatedBuilder(
        animation: _anim,
        child: chip,
        builder: (context, child) {
          final t = _anim.value;
          if (t == 0) return child!;
          // Simple: solo un brinco de tamaño. Completo: además se sacude.
          final escala = 1 + 0.15 * sin(pi * t);
          final giro = simple ? 0.0 : 0.12 * sin(pi * 6 * t) * (1 - t);
          return Transform.rotate(angle: giro, child: Transform.scale(scale: escala, child: child));
        },
      ),
    );
  }
}
