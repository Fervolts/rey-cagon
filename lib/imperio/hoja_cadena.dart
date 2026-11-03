import 'dart:async';

import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'cadena.dart';
import 'control.dart';
import 'decision.dart';
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';

// La hoja de la Cadena 🚽 (capa 1 de la escalera): la tarjeta DEJAS / RECIBES con el botón JALAR (o lo que falta) y,
// debajo, la PLOMERÍA 🔧, que se paga con Rollos de Oro. La abren el botón JALAR de la barra y la palanca de la poceta.

/// Aviso corto de la pantalla del Imperio (emoji, texto).
typedef AvisarCadena = void Function(String emoji, String texto);

BoxDecoration _caja(BuildContext context, {Color? borde}) {
  final p = paleta(context);
  return BoxDecoration(color: p.tarjeta, border: Border.all(color: borde ?? p.borde), borderRadius: BorderRadius.circular(radio));
}

/// "1:05:09" o "4:07".
String _cuenta(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 31);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// Abre la hoja de la Cadena. Anota `cadena_abre` una sola vez (el JALAR de adentro ya no lo repite).
Future<void> abrirHojaCadena(BuildContext context, ControlImperio control, AvisarCadena avisar) {
  control.abrirCadena(botonJalar(control.imperio, control.cadena).encendido);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (hoja) => ListenableBuilder(
      listenable: control,
      builder: (hoja, _) => _HojaCadena(
        control: control,
        avisar: avisar,
        // JALAR cierra la hoja y sigue con el contexto de la pantalla (confirmar, remolino, resultado).
        alJalar: () {
          Navigator.pop(hoja);
          unawaited(jalarLaCadena(context, control, avisar: avisar, anotar: false));
        },
      ),
    ),
  );
}

class _HojaCadena extends StatelessWidget {
  const _HojaCadena({required this.control, required this.avisar, required this.alJalar});

  final ControlImperio control;
  final AvisarCadena avisar;
  final VoidCallback alJalar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final boton = botonJalar(im, control.cadena);
    final listo = boton.encendido;
    final rollos = listo ? boton.rollos : im.rollosPorGanar;
    final pct = im.ajustes.rolloPct;
    final suave = TextStyle(fontSize: 12, color: p.textoSuave);
    final ahora = control.ahora;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Rotulo(tr('Cadena', 'Chain'))),
                  const Emoji('🚽', tamano: 16),
                ],
              ),
              const SizedBox(height: 8),
              TarjetaDecision(
                key: const Key('decision_cadena'),
                lista: listo,
                dejas: tr('Tu saldo, cagadores y mejoras', 'Your balance, poopers and upgrades'),
                recibes: tr('+$rollos Rollos de Oro: ${porcentajeRollos(rollos, pct)} de producción hasta la mudanza',
                    '+$rollos Golden Rolls: ${porcentajeRollos(rollos, pct)} production until you move'),
                cabeza: Row(
                  children: [
                    const Emoji('🧻', tamano: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          tr('Tienes ${im.partida.rollos} Rollos de Oro: ${porcentajeRollos(im.partida.rollos, pct)} de producción',
                              'You have ${im.partida.rollos} Golden Rolls: ${porcentajeRollos(im.partida.rollos, pct)} production'),
                          style: TextStyle(fontWeight: FontWeight.w900, color: p.texto)),
                    ),
                  ],
                ),
                hijos: [
                  if (!listo && boton.visible) ...[
                    const SizedBox(height: 10),
                    Text(boton.aviso(monedaActual().abreviatura),
                        key: const Key('cadena_falta'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.texto)),
                  ],
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const Key('cadena_jalar'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: listo && !control.jalando && !control.mudando ? alJalar : null,
                    child: Text(control.jalando ? tr('JALANDO...', 'FLUSHING...') : tr('JALAR', 'FLUSH')),
                  ),
                ],
              ),
              if (im.objetosRollosAbiertos) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Rotulo(tr('Plomería', 'Plumbing'))),
                    const Emoji('🔧', tamano: 16),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    tr('Se paga con Rollos de Oro y dura hasta la mudanza: las jaladas no la borran. '
                            'Cada Rollo que gastas deja de darte ${porcentajeRollos(1, pct)}.',
                        'Paid with Golden Rolls and lasts until you move: flushes don\'t reset it. '
                            'Each Roll you spend stops giving you ${porcentajeRollos(1, pct)}.'),
                    style: suave),
                const SizedBox(height: 8),
                for (final r in objetosRollos) _filaRollos(context, p, im, r, ahora),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _comprarRollos(ObjetoRollos r) {
    if (control.comprarObjetoRollos(r.id)) avisar(r.emoji, tr('${r.nombreEs}: listo', '${r.nombreEn}: done'));
  }

  Widget _filaRollos(BuildContext context, Paleta p, Imperio im, ObjetoRollos r, int ahora) {
    final tiene = im.tieneObjetoRollos(r.id);
    final nivel = im.nivelPlomeria(r.id);
    final tope = r.id != 'cadena_reserva' && nivel >= r.limite;
    final espera = r.id == 'cadena_reserva' ? im.esperaCadena(ahora) : null;
    final pendiente = r.id == 'cadena_reserva' && tiene > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: _caja(context),
      child: Row(
        children: [
          Emoji(r.emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(r.nombreEs, r.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                Text(tr(r.descEs, r.descEn), style: TextStyle(fontSize: 12, color: p.textoSuave)),
                const SizedBox(height: 2),
                Text(
                    pendiente
                        ? tr('Lista para tu próxima jalada', 'Ready for your next flush')
                        : espera != null
                            ? tr('Otra en ${_cuenta(espera)}', 'Another in ${_cuenta(espera)}')
                            : '$nivel/${r.limite}',
                    style: numeros(context, tamano: 11, color: p.textoSuave)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: Key('pagar_rollos_${r.id}'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 44)),
            onPressed: im.puedeComprarObjetoRollos(r.id, ahora) ? () => _comprarRollos(r) : null,
            child: tope
                ? Text(tr('MÁX', 'MAX'), style: numeros(context, tamano: 13, weight: FontWeight.w900))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${formatoMj(im.precioObjetoRollos(r.id), ingles: enIngles)} ',
                          style: numeros(context, tamano: 13, weight: FontWeight.w900)),
                      const Emoji('🧻', tamano: 18),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
