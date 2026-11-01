// Hoja de la racha del Imperio: cuadrícula de 30 días y botón RECLAMAR.

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
String nombreLogro(Logro l) =>
    l.id == 'constancia' ? tr(segun('Rey de la constancia', 'Reina de la constancia'), segun('King of consistency', 'Queen of consistency')) : tr(l.nombreEs, l.nombreEn);

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

/// Abre la hoja. Se puede reclamar desde aquí si hoy toca.
Future<void> mostrarHojaRacha(BuildContext context, ControlImperio control, void Function(String emoji, String texto) avisar) {
  control.anotar('racha_abre');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => ListenableBuilder(
      listenable: control,
      builder: (context, _) => HojaRacha(control: control, avisar: avisar),
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Emoji('🔥', tamano: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('RACHA DEL IMPERIO', 'EMPIRE STREAK'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.6, color: p.texto)),
                      Text(tr('Día ${estado.dia} de $diasRacha', 'Day ${estado.dia} of $diasRacha'),
                          key: const Key('racha_dia'), style: numeros(context, tamano: 13, color: p.textoSuave)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                tr('Entra cada día y reclama. Si se te pasa un día, vuelves al día 1.',
                    'Come back every day and claim. Miss a day and you go back to day 1.'),
                style: TextStyle(fontSize: 12, color: p.textoSuave)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 6,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (var d = 1; d <= diasRacha; d++) _casilla(context, d, estado)],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
              child: Text(
                  estado.reclamado
                      ? tr('Hoy te llevaste: ${textoPremio(hoy)}', 'Today you got: ${textoPremio(hoy)}')
                      : tr('Hoy toca: ${textoPremio(hoy)}', 'Today: ${textoPremio(hoy)}'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: estado.reclamado
                  ? OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('VUELVE MAÑANA', 'COME BACK TOMORROW'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    )
                  : FilledButton(
                      key: const Key('boton_reclamar'),
                      onPressed: _ocupado ? null : _reclamar,
                      child: Text(tr('RECLAMAR', 'CLAIM'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.8)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _casilla(BuildContext context, int d, EstadoRacha e) {
    final p = paleta(context);
    final hecho = d <= e.previos || (d == e.dia && e.reclamado);
    final esHoy = d == e.dia;
    final partes = partesPremio(premioDia(d));
    final fondo = esHoy && !hecho ? acento : p.tarjeta;
    final tinta = esHoy && !hecho ? acentoTexto : p.texto;
    return Opacity(
      opacity: hecho ? 0.45 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: fondo,
          border: Border.all(color: esHoy ? acento : (hecho ? p.borde : p.bordeFuerte)),
          borderRadius: BorderRadius.circular(radio),
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$d', style: numeros(context, tamano: 10, weight: FontWeight.w900, color: tinta)),
            if (hecho)
              Icon(Icons.check, size: 18, color: p.texto)
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (emoji, texto) in partes.take(2)) ...[
                      Emoji(emoji, tamano: 14),
                      if (texto.isNotEmpty) Text(texto, style: numeros(context, tamano: 9, weight: FontWeight.w800, color: tinta)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
