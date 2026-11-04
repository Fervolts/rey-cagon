// Pausa a mano de los alquileres que solo trabajan con la app abierta (Primo pujador, Cuadrilla del barrio, Plomero
// por horas). Su tiempo corre igual con la app cerrada; para no perderlo, el jugador los pausa antes de salir.
// No se pausan solos: aquí van el aviso de la primera vez, la hoja de la ficha y la línea del resumen offline.

import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'control.dart';
import 'motor.dart';

/// Clave en [Partida.guiaVista] cuando el jugador marcó "No volver a mostrar" en el aviso de la pausa.
const claveAvisoPausa = 'aviso_pausa';

/// Lo que explica el aviso y la hoja: por qué y cuándo pausarlo.
String textoSoloAbierta() => tr('Solo trabaja con la app abierta, pero su tiempo corre aunque la cierres. Páusalo antes de salir y '
    'síguelo al volver: no pierdes nada.', 'It only works with the app open, but its time runs even when you close it. Pause it before '
    'leaving and resume it when you are back: you lose nothing.');

String _reloj(Duration d) {
  final s = max(0, (d.inMilliseconds / 1000).ceil());
  String dos(int n) => n.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${dos(s % 3600 ~/ 60)}:${dos(s % 60)}' : '${s ~/ 60}:${dos(s % 60)}';
}

/// Lo que dice el resumen "MIENTRAS NO ESTABAS" por cada alquiler que corrió con la app cerrada sin trabajar.
List<String> lineasCorridos(List<(String, int)> corridos) => [
      for (final (id, ms) in corridos)
        if (objetoPorId(id) case final o?)
          tr('⏳ ${o.nombreEs} corrió ${(ms / 60000).round()} min con la app cerrada sin trabajar. Páusalo antes de salir.',
              '⏳ ${o.nombreEn} ran ${(ms / 60000).round()} min with the app closed, doing nothing. Pause it before leaving.'),
    ];

Future<T?> _hoja<T>(BuildContext context, Widget Function(BuildContext context, Paleta p) cuerpo) => showDialog<T>(
      context: context,
      builder: (context) {
        final p = paleta(context);
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: p.bordeFuerte)),
          backgroundColor: p.tarjeta,
          child: Padding(padding: const EdgeInsets.all(20), child: cuerpo(context, p)),
        );
      },
    );

/// La primera vez que alquila uno de [alquileresSoloAbierta]: explica que corre con la app cerrada y que se pausa a
/// mano. Sale cada vez hasta que marque "No volver a mostrar".
Future<void> avisarSoloAbierta(BuildContext context, ControlImperio control, Objeto o) async {
  if (!alquileresSoloAbierta.contains(o.id) || control.imperio.partida.guiaVista.contains(claveAvisoPausa)) return;
  var noMas = false;
  await _hoja<void>(
    context,
    (context, p) => StatefulBuilder(
      builder: (context, refrescar) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Emoji(o.emoji, tamano: 48)),
          const SizedBox(height: 10),
          Text(tr('OJO AL SALIR', 'MIND WHEN YOU LEAVE'),
              textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.6, color: p.texto)),
          const SizedBox(height: 10),
          Text(textoSoloAbierta(), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.4, color: p.texto)),
          const SizedBox(height: 6),
          Text(tr('Lo pausas tocando su ficha junto a la poceta o aquí en la tienda.', 'Pause it by tapping its chip by the toilet or here in the shop.'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.textoSuave)),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('aviso_pausa_no_mas'),
            onTap: () => refrescar(() => noMas = !noMas),
            child: Row(children: [
              Checkbox(value: noMas, onChanged: (v) => refrescar(() => noMas = v ?? false)),
              Expanded(child: Text(tr('No volver a mostrar', 'Don\'t show again'), style: TextStyle(color: p.texto))),
            ]),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('aviso_pausa_ok'),
              onPressed: () => Navigator.pop(context),
              child: Text(tr('ENTENDIDO', 'GOT IT'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
            ),
          ),
        ],
      ),
    ),
  );
  if (noMas) control.marcarGuia(claveAvisoPausa);
}

/// Pausa o sigue [id] y devuelve el aviso corto de lo hecho (null si no se pudo).
(String, String)? alternarPausa(ControlImperio control, String id) {
  final o = objetoPorId(id);
  if (o == null) return null;
  final nombre = tr(o.nombreEs, o.nombreEn);
  if (control.imperio.enPausa(id) != null) {
    if (!control.reanudarAlquiler(id)) return null;
    HapticFeedback.selectionClick();
    return (o.emoji, tr('$nombre sigue trabajando', '$nombre is back to work'));
  }
  if (!control.pausarAlquiler(id)) return null;
  HapticFeedback.selectionClick();
  final queda = control.imperio.enPausa(id) ?? Duration.zero;
  return (o.emoji, tr('$nombre en pausa: le quedan ${_reloj(queda)} guardados', '$nombre paused: ${_reloj(queda)} saved'));
}

/// La hoja de una ficha pausable: qué hace, cuánto le queda y PAUSAR o SEGUIR. [avisar] muestra el aviso de lo hecho.
Future<void> abrirPausaAlquiler(BuildContext context, ControlImperio control, String id, void Function(String emoji, String texto) avisar) {
  final o = objetoPorId(id)!;
  return _hoja<void>(
    context,
    (context, p) => ListenableBuilder(
      listenable: control,
      builder: (context, _) {
        final im = control.imperio;
        final ahora = control.ahora;
        final pausa = im.enPausa(id);
        final activo = im.alquiladoActivo(id, ahora);
        final queda = pausa ?? Duration(milliseconds: max(0, (im.partida.alquilados[id] ?? ahora) - ahora));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Emoji(o.emoji, tamano: 36),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(o.nombreEs, o.nombreEn), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: p.texto))),
            ]),
            const SizedBox(height: 8),
            Text(tr(o.descEs, o.descEn), style: TextStyle(fontSize: 13, color: p.textoSuave)),
            const SizedBox(height: 10),
            Text(
                pausa != null
                    ? tr('En pausa: le quedan ${_reloj(queda)}', 'Paused: ${_reloj(queda)} left')
                    : activo
                        ? tr('Trabajando: le quedan ${_reloj(queda)}', 'Working: ${_reloj(queda)} left')
                        : tr('Se acabó', 'It ended'),
                key: const Key('pausa_estado'),
                style: numeros(context, tamano: 14, weight: FontWeight.w900, color: pausa != null ? p.texto : acento)),
            if (im.alquilerIndefinido(id))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('∞ En pausa no se renueva ni se cobra.', '∞ While paused it neither renews nor charges.'),
                    style: TextStyle(fontSize: 12, color: p.textoSuave)),
              ),
            const SizedBox(height: 10),
            Text(textoSoloAbierta(), style: TextStyle(fontSize: 13, height: 1.35, color: p.texto)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('CERRAR', 'CLOSE'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              if (pausa != null || activo) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const Key('pausa_alternar'),
                      onPressed: () {
                        final hecho = alternarPausa(control, id);
                        Navigator.pop(context);
                        if (hecho != null) avisar(hecho.$1, hecho.$2);
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(pausa != null ? Icons.play_arrow : Icons.pause, size: 18),
                        const SizedBox(width: 4),
                        Text(pausa != null ? tr('SEGUIR', 'RESUME') : tr('PAUSAR', 'PAUSE'),
                            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
          ],
        );
      },
    ),
  );
}
