// Pop-up de la racha del Imperio: barra de 30 días, el premio de hoy en grande, lo que viene y RECLAMAR.

import 'package:flutter/material.dart';

import '../emoji.dart';
import '../genero.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'control.dart';
import 'motor.dart';
import 'racha_imperio.dart';

/// Nombre del logro en el idioma y género del jugador.
/// Los que dicen "Rey"/"King" salen como "Reina"/"Queen" para ellas.
String nombreLogro(Logro l) => tr(
    segun(l.nombreEs, l.nombreEs.replaceFirst(RegExp(r'^Rey\b'), 'Reina')),
    segun(l.nombreEn, l.nombreEn.replaceFirst(RegExp(r'^King\b'), 'Queen').replaceFirst(RegExp(r'\bking$'), 'queen')));

/// "15 min", "1 h".
String _tiempo(int minutos) => minutos < 60 ? '$minutos min' : '${minutos ~/ 60} h';

/// Partes del premio para la casilla: (emoji, texto corto).
List<(String, String)> partesPremio(PremioRacha p) => [
      if (p.minutos > 0) ('⏰', _tiempo(p.minutos)),
      for (final MapEntry(key: id, value: n) in p.objetos.entries) (objetoPorId(id)?.emoji ?? '❓', n > 1 ? 'x$n' : ''),
      if (p.ficha) ('🎟️', '1'),
      if (p.ciruelas > 0) ('🫐', '${p.ciruelas}'),
      if (p.logro != null) ('🏆', ''),
    ];

/// El premio en palabras: "30 min de producción", "1 Ficha + 3 Ciruelas".
String textoPremio(PremioRacha p) {
  final partes = <String>[
    if (p.minutos > 0) tr('${_tiempo(p.minutos)} de producción', '${_tiempo(p.minutos)} of production'),
    for (final MapEntry(key: id, value: n) in p.objetos.entries)
      if (objetoPorId(id) case final o?) '${n > 1 ? '$n ' : ''}${tr(o.nombreEs, o.nombreEn)}',
    if (p.ficha) tr('1 Ficha', '1 Token'),
    if (p.ciruelas > 0) tr('${p.ciruelas} ${p.ciruelas == 1 ? 'Ciruela' : 'Ciruelas'}', '${p.ciruelas} ${p.ciruelas == 1 ? 'Plum' : 'Plums'}'),
    if (p.logro != null)
      if (logroPorId(p.logro!) case final l?) tr('logro "${nombreLogro(l)}"', '"${nombreLogro(l)}" achievement'),
  ];
  return partes.join(' + ');
}

/// Abre el pop-up (centrado, fondo oscurecido). Se puede reclamar desde aquí si hoy toca.
Future<void> mostrarHojaRacha(BuildContext context, ControlImperio control, void Function(String emoji, String texto) avisar) {
  control.anotar('racha_abre');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (contexto) => Dialog(
      backgroundColor: paleta(contexto).fondo,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: const BorderSide(color: acento, width: 2)),
      child: ListenableBuilder(
        listenable: control,
        builder: (context, _) => HojaRacha(control: control, avisar: avisar),
      ),
    ),
  );
}

class HojaRacha extends StatefulWidget {
  const HojaRacha({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  State<HojaRacha> createState() => _HojaRachaState();
}

class _HojaRachaState extends State<HojaRacha> {
  bool _ocupado = false;

  Future<void> _reclamar() async {
    setState(() => _ocupado = true);
    try {
      final r = await widget.control.reclamarRacha();
      if (!r.ya) {
        final extra = r.ciruelasGanadas > 0 && !r.ficha && premioDia(r.dia).ficha
            ? tr(' (Fichas llenas: te dimos Ciruelas)', ' (Tokens full: you got Plums)')
            : '';
        widget.avisar('🔥', tr('Día ${r.dia}: ${textoPremio(premioDia(r.dia))}$extra', 'Day ${r.dia}: ${textoPremio(premioDia(r.dia))}$extra'));
      }
    } catch (e) {
      widget.avisar('💩', textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final estado = widget.control.racha ?? const EstadoRacha(1, false, 0);
    final hoy = premioDia(estado.dia);
    final hechos = estado.previos + (estado.reclamado ? 1 : 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('RACHA DIARIA', 'DAILY STREAK'),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.2, color: p.textoSuave)),
              ),
              InkResponse(
                onTap: () => Navigator.pop(context),
                radius: 20,
                child: Icon(Icons.close, size: 22, color: p.textoSuave),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // El día grande, como en cualquier juego: 🔥 12
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Emoji('🔥', tamano: 44),
              const SizedBox(width: 8),
              Text(tr('Día ${estado.dia}', 'Day ${estado.dia}'),
                  key: const Key('racha_dia'), style: numeros(context, tamano: 34, weight: FontWeight.w900, color: p.texto)),
              Text(' /$diasRacha', style: numeros(context, tamano: 16, weight: FontWeight.w800, color: p.textoSuave)),
            ],
          ),
          const SizedBox(height: 12),
          _barra(context, estado, hechos),
          const SizedBox(height: 16),
          _premioHoy(context, hoy, estado),
          const SizedBox(height: 14),
          Text(tr('LO QUE VIENE', 'COMING UP'),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2, color: p.textoSuave)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 1; i <= 5; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(child: _proximo(context, (estado.dia - 1 + i) % diasRacha + 1)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: estado.reclamado
                ? OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('VUELVE MAÑANA', 'COME BACK TOMORROW'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                  )
                : FilledButton(
                    key: const Key('boton_reclamar'),
                    onPressed: _ocupado ? null : _reclamar,
                    child: Text(tr('RECLAMAR', 'CLAIM'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                  ),
          ),
          const SizedBox(height: 8),
          Text(tr('Si se te pasa un día, vuelves al día 1.', 'Miss a day and you go back to day 1.'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textoSuave)),
        ],
      ),
    );
  }

  /// 30 rayitas: hechas en acento, hoy con borde, las metas (Ficha y trofeo) marcadas debajo.
  Widget _barra(BuildContext context, EstadoRacha e, int hechos) {
    final p = paleta(context);
    return Column(
      children: [
        Row(
          children: [
            for (var d = 1; d <= diasRacha; d++) ...[
              if (d > 1) const SizedBox(width: 2),
              Expanded(
                child: Container(
                  height: d == e.dia ? 14 : 10,
                  decoration: BoxDecoration(
                    color: d <= hechos ? acento : p.tarjeta,
                    border: Border.all(color: d == e.dia ? acento : p.borde),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var d = 1; d <= diasRacha; d++)
                  if (premioDia(d).ficha || premioDia(d).logro != null)
                    Positioned(
                      left: (d - 0.5) / diasRacha * c.maxWidth - 9,
                      child: Opacity(opacity: d <= hechos ? 0.4 : 1, child: Emoji(premioDia(d).logro != null ? '🏆' : '🎟️', tamano: 18)),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// La tarjeta grande con el premio de hoy.
  Widget _premioHoy(BuildContext context, PremioRacha hoy, EstadoRacha e) {
    final p = paleta(context);
    final listo = e.reclamado;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: listo ? p.tarjeta : acento,
        border: Border.all(color: acento, width: 2),
        borderRadius: BorderRadius.circular(radio),
      ),
      child: Column(
        children: [
          Text(listo ? tr('YA RECLAMASTE HOY', 'CLAIMED TODAY') : tr('PREMIO DE HOY', "TODAY'S PRIZE"),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2, color: listo ? p.textoSuave : acentoTexto)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (emoji, texto) in partesPremio(hoy)) ...[
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Emoji(emoji, tamano: 48)),
                  if (texto.isNotEmpty)
                    Text(texto, style: numeros(context, tamano: 22, weight: FontWeight.w900, color: listo ? p.texto : acentoTexto)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(textoPremio(hoy),
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: listo ? p.texto : acentoTexto)),
        ],
      ),
    );
  }

  /// Casilla chica de un día que viene.
  Widget _proximo(BuildContext context, int d) {
    final p = paleta(context);
    final partes = partesPremio(premioDia(d));
    return Container(
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr('Día $d', 'Day $d'), style: numeros(context, tamano: 10, weight: FontWeight.w800, color: p.textoSuave)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (emoji, texto) in partes.take(2)) ...[
                  Emoji(emoji, tamano: 22),
                  if (texto.isNotEmpty) Text(texto, style: numeros(context, tamano: 11, weight: FontWeight.w900, color: p.texto)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
