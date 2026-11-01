// Cofre del Trono 🎁: meta semanal de 3 días con cagada real (lunes a domingo, hora local). Lo cuenta y lo paga el servidor
// (`imperio_cofre`); aquí, la lógica de la semana (para tests y para mostrar) y el chip del Imperio.

import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'control.dart';
import 'formato.dart';
import 'nube.dart';

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

/// Días que faltan para el lunes que viene (1 si hoy es domingo).
int diasParaLunes(DateTime hoy) => DateTime.daysPerWeek - (hoy.weekday - DateTime.monday);

/// Chip 🎁 de la cabecera del Imperio: x/3, ABRIR cuando está listo, ✓ cuando ya se abrió. Al tocarlo abre la hoja
/// del Cofre ([abrirHojaCofre]), que explica la meta y es donde se abre.
class ChipCofre extends StatelessWidget {
  const ChipCofre({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = control.cofre;
    if (c == null) return const SizedBox.shrink();
    final texto = c.reclamado ? '✓' : c.listo ? tr('ABRIR', 'OPEN') : '${c.dias.clamp(0, c.meta)}/${c.meta}';
    return GestureDetector(
      key: const Key('chip_cofre'),
      onTap: () => abrirHojaCofre(context, control, avisar),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: c.listo ? acento : p.tarjeta,
          border: Border.all(color: c.listo ? acento : p.borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Emoji('🎁', tamano: 16),
              const SizedBox(width: 5),
              Text(texto,
                  style: numeros(context,
                      tamano: 13, weight: FontWeight.w800, color: c.listo ? Colors.black : c.reclamado ? p.textoSuave : null)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja del Cofre del Trono: qué pide, cuánto llevas, qué trae, el botón para abrirlo y lo que salió.
Future<void> abrirHojaCofre(BuildContext context, ControlImperio control, void Function(String emoji, String texto) avisar) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => HojaCofre(control: control, avisar: avisar),
  );
}

class HojaCofre extends StatefulWidget {
  const HojaCofre({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  State<HojaCofre> createState() => _HojaCofreState();
}

class _HojaCofreState extends State<HojaCofre> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _abriendo = false;

  /// Lo que salió al abrirlo en esta hoja.
  EstadoCofre? _premio;
  String? _error;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _abrir() async {
    if (_abriendo) return;
    setState(() {
      _abriendo = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    final m = movimiento(context);
    _anim.duration = Duration(milliseconds: m == Movimiento.completo ? 900 : 250);
    final animacion = m == Movimiento.nada ? Future<void>.value() : _anim.forward(from: 0).orCancel.catchError((_) {});
    try {
      final r = await widget.control.reclamarCofre();
      await animacion;
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _premio = r);
      if (r == null) widget.avisar('🎁', tr('Ese Cofre ya estaba abierto.', 'That Chest was already open.'));
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
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
    final premio = _premio;
    final dias = c.dias.clamp(0, c.meta);
    final faltan = diasParaLunes(DateTime.now());
    final simple = movimiento(context) != Movimiento.completo;

    Widget regalo(Widget child) => AnimatedBuilder(
          animation: _anim,
          child: child,
          builder: (context, child) {
            final t = _anim.value;
            if (t == 0) return child!;
            final escala = 1 + 0.2 * sin(pi * t);
            final giro = simple ? 0.0 : 0.18 * sin(pi * 8 * t) * (1 - t);
            return Transform.rotate(angle: giro, child: Transform.scale(scale: escala, child: child));
          },
        );

    Widget linea(String emoji, String texto, {bool fuerte = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Emoji(emoji, tamano: fuerte ? 22 : 18),
            const SizedBox(width: 8),
            Expanded(child: Text(texto, style: numeros(context, tamano: fuerte ? 16 : 13, weight: fuerte ? FontWeight.w800 : FontWeight.w500))),
          ]),
        );

    final List<Widget> cuerpo;
    if (premio != null) {
      // Lo que salió, grande.
      cuerpo = [
        const Center(child: Emoji('✨', tamano: 72)),
        const SizedBox(height: 8),
        Text(tr('¡ABRISTE EL COFRE!', 'CHEST OPENED!'), textAlign: TextAlign.center, style: numeros(context, tamano: 20, weight: FontWeight.w900)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
          child: Column(children: [
            if (premio.fichasGanadas > 0) linea('🎟️', tr('+${premio.fichasGanadas} Fichas', '+${premio.fichasGanadas} Tokens'), fuerte: true),
            if (premio.ciruelasGanadas > 0) linea('🫐', tr('+${premio.ciruelasGanadas} Ciruelas', '+${premio.ciruelasGanadas} Plums'), fuerte: true),
            linea('⏰', tr('+${formatoMj(widget.control.premioCofreMj, ingles: enIngles)} MJ (1 h de producción)',
                '+${formatoMj(widget.control.premioCofreMj, ingles: enIngles)} MJ (1 h of production)'), fuerte: true),
            if (premio.semanasRacha > 1) linea('🔥', tr('${premio.semanasRacha} semanas seguidas', '${premio.semanasRacha} weeks in a row')),
          ]),
        ),
        if (premio.fichasGanadas < 2 && premio.ciruelasGanadas > 0) ...[
          const SizedBox(height: 6),
          Text(tr('Tus Fichas estaban llenas: te tocaron Ciruelas.', 'Your Tokens were full: you got Plums instead.'),
              textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Text(tr('El lunes empieza otro Cofre.', 'A new Chest starts on Monday.'), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('A la poceta, digo, al Imperio', 'Back to the Empire'))),
      ];
    } else {
      cuerpo = [
        Row(children: [
          regalo(Opacity(opacity: c.reclamado ? 0.4 : 1, child: const Emoji('🎁', tamano: 48))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Rotulo(tr('Cofre del Trono', 'Throne Chest')),
              const SizedBox(height: 4),
              Text(
                tr('Caga de verdad ${c.meta} días distintos esta semana (de lunes a domingo) y ábrelo.',
                    'Really poop on ${c.meta} different days this week (Monday to Sunday) and open it.'),
                style: TextStyle(color: p.textoSuave, fontSize: 13),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        // Un cuadro por día de la meta.
        Row(children: [
          for (var i = 0; i < c.meta; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i < dias ? acento : p.tarjeta,
                  border: Border.all(color: i < dias ? acento : p.borde),
                  borderRadius: BorderRadius.circular(radio),
                ),
                child: i < dias ? const Emoji('💩', tamano: 20) : Text('${i + 1}', style: numeros(context, tamano: 13, color: p.textoSuave)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Text(
          c.reclamado
              ? tr('Ya lo abriste esta semana. Nuevo Cofre en $faltan ${faltan == 1 ? 'día' : 'días'} (el lunes).',
                  'You already opened it this week. New Chest in $faltan ${faltan == 1 ? 'day' : 'days'} (Monday).')
              : c.listo
                  ? tr('¡Meta cumplida! Ábrelo.', 'Goal reached! Open it.')
                  : tr('Llevas $dias de ${c.meta}. Te faltan ${c.meta - dias}.', '$dias of ${c.meta} so far. ${c.meta - dias} to go.'),
          style: numeros(context, tamano: 13, weight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ADENTRO', 'INSIDE'), style: numeros(context, tamano: 11, weight: FontWeight.w700, color: p.textoSuave)),
            const SizedBox(height: 4),
            linea('🎟️', tr('+2 Fichas (si no caben, 2 Ciruelas por cada una)', '+2 Tokens (if they don\'t fit, 2 Plums each)')),
            linea('⏰', tr('1 h de producción del Imperio', '1 h of Empire production')),
            linea('🔥', tr('Ábrelo todas las semanas para sumar semanas seguidas', 'Open it every week to stack weeks in a row')),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('abrir_cofre'),
          onPressed: c.listo && !_abriendo ? _abrir : null,
          child: Text(_abriendo
              ? tr('Abriendo...', 'Opening...')
              : c.reclamado
                  ? tr('Ya abierto ✓', 'Already opened ✓')
                  : c.listo
                      ? tr('ABRIR COFRE', 'OPEN CHEST')
                      : tr('Faltan ${c.meta - dias} ${c.meta - dias == 1 ? 'día' : 'días'}', '${c.meta - dias} ${c.meta - dias == 1 ? 'day' : 'days'} to go')),
        ),
      ];
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cuerpo),
      ),
    );
  }
}
