// Personalizar el baño (se abre con el Templo del Trono): ocultar cosas, cuántos dedos se ven y qué ambiente.
// Solo visual: no cambia la producción. Se guarda en `Partida.vista` y viaja a la nube con la partida.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'bano.dart';
import 'catalogo.dart';
import 'control.dart';
import 'poceta.dart';
import 'tarjeta_bano.dart' show presumirBano;

/// Edificio que da cada ambiente (para el emoji y el nombre del botón). La casa no tiene.
const _edificioDe = {
  AmbienteBano.publico: 'bano',
  AmbienteBano.mina: 'mina',
  AmbienteBano.templo: 'templo',
  AmbienteBano.volcan: 'volcan',
  AmbienteBano.laxante: 'laxante_tiempo',
  AmbienteBano.agujero: 'agujero',
};

/// Emoji y nombre de un ambiente.
(String, String) nombreAmbiente(AmbienteBano a) {
  final e = _edificioDe[a] == null ? null : edificioPorId(_edificioDe[a]!);
  if (e == null) return ('🚽', tr('Casa', 'Home'));
  return (e.emoji, tr(e.nombreEs, e.nombreEn));
}

/// Abre la hoja. Al cerrarla guarda la partida.
Future<void> abrirPersonalizar(BuildContext context, ControlImperio control) async {
  control.anotar('personalizar_abre');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    // Con su propio Scaffold para que los avisos (al compartir el baño) salgan encima de la hoja y no detrás.
    builder: (_) => FractionallySizedBox(
      heightFactor: .92,
      child: ScaffoldMessenger(
        child: Scaffold(backgroundColor: paleta(context).fondo, body: Personalizar(control: control)),
      ),
    ),
  );
  unawaited(control.guardarTodo());
}

class Personalizar extends StatefulWidget {
  const Personalizar({super.key, required this.control});

  final ControlImperio control;

  @override
  State<Personalizar> createState() => _PersonalizarState();
}

class _PersonalizarState extends State<Personalizar> {
  Map<String, dynamic> get _vista => widget.control.imperio.partida.vista;

  Set<String> get _ocultos => {for (final x in (_vista['ocultos'] as List?) ?? const []) '$x'};

  void _cambiar(void Function(Map<String, dynamic> v) cambio) {
    setState(() => cambio(_vista));
  }

  void _ver(String id, bool ver) => _cambiar((v) {
        final o = _ocultos;
        ver ? o.remove(id) : o.add(id);
        if (o.isEmpty) {
          v.remove('ocultos');
        } else {
          v['ocultos'] = o.toList()..sort();
        }
      });

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = widget.control.imperio;
    // Lo que tienes, sin ocultar nada: de aquí salen los interruptores.
    final todo = EstadoBano.desde(comprada: im.mejoraComprada, cantidad: im.cantidad, esteticas: im.esteticas);
    final bano = EstadoBano.desde(comprada: im.mejoraComprada, cantidad: im.cantidad, esteticas: im.esteticas, vista: _vista);
    final cosas = [for (final o in ocultablesBano) if (o.tiene(todo)) o];
    final ocultos = _ocultos;
    final topeDedos = min(im.cantidad('dedo'), Poceta.topeDedos);
    final dedos = min(topeDedos, (_vista['dedos'] as int?) ?? topeDedos);
    final ambientes = EstadoBano.ambientesDesbloqueados(im.cantidad);
    final elegido = _vista['ambiente'] as String?;
    final tocado = _vista.isNotEmpty;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                const Emoji('🎨', tamano: 26),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('Personalizar el baño', 'Customize the bathroom'), style: numeros(context, tamano: 18, weight: FontWeight.w900))),
                TextButton(
                  key: const Key('personalizar_todo'),
                  onPressed: tocado ? () => _cambiar((v) => v.clear()) : null,
                  child: Text(tr('VER TODO', 'SHOW ALL')),
                ),
              ],
            ),
          ),
          // Vista previa en vivo (no se toca).
          Container(
            height: Bano.altura(bano),
            decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: p.bordeFuerte))),
            child: ClipRect(
              child: IgnorePointer(
                child: Poceta(
                  alTocar: () => (texto: '', epico: false, contado: true),
                  mps: 0,
                  bano: bano,
                  dedos: dedos,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Text(tr('Solo cambia cómo se ve. Lo que produces sigue igual.', 'Only changes the look. Your production stays the same.'),
                    style: TextStyle(fontSize: 12, color: p.textoSuave)),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const Key('personalizar_compartir'),
                  onPressed: () => presumirBano(context, widget.control),
                  child: TextoConEmojis(tr('📸 COMPARTIR MI BAÑO', '📸 SHARE MY BATHROOM')),
                ),
                const SizedBox(height: 14),
                _titulo(context, tr('AMBIENTE', 'SCENE')),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ficha(context, '✨', tr('El más alto', 'Highest'), elegido == null, () => _cambiar((v) => v.remove('ambiente')),
                        key: const Key('ambiente_auto')),
                    for (final a in ambientes)
                      _ficha(context, nombreAmbiente(a).$1, nombreAmbiente(a).$2, elegido == a.name, () => _cambiar((v) => v['ambiente'] = a.name),
                          key: Key('ambiente_${a.name}')),
                  ],
                ),
                if (topeDedos > 0) ...[
                  const SizedBox(height: 18),
                  _titulo(context, tr('DEDOS A LA VISTA', 'FINGERS ON SHOW')),
                  Row(
                    children: [
                      const Emoji('👆', tamano: 22),
                      Expanded(
                        child: Slider(
                          key: const Key('personalizar_dedos'),
                          value: dedos.toDouble(),
                          max: topeDedos.toDouble(),
                          divisions: max(topeDedos, 1),
                          label: '$dedos',
                          onChanged: (x) => _cambiar((v) => x.round() >= topeDedos ? v.remove('dedos') : v['dedos'] = x.round()),
                        ),
                      ),
                      SizedBox(width: 44, child: Text('$dedos', textAlign: TextAlign.end, style: numeros(context, tamano: 16, weight: FontWeight.w800))),
                    ],
                  ),
                ],
                if (cosas.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _titulo(context, tr('QUÉ SE VE', "WHAT'S SHOWN")),
                  for (final o in cosas)
                    _fila(context, o.emoji, tr(o.es, o.en), !ocultos.contains(o.id), (ver) => _ver(o.id, ver), key: Key('ver_${o.id}')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto, style: numeros(context, tamano: 12, weight: FontWeight.w800, color: paleta(context).textoSuave)),
      );

  // Botón cuadrado de ambiente: el elegido va en acento.
  Widget _ficha(BuildContext context, String emoji, String texto, bool si, VoidCallback alTocar, {Key? key}) {
    final p = paleta(context);
    return Material(
      key: key,
      color: si ? acento : p.tarjeta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: si ? acentoTexto : p.borde)),
      child: InkWell(
        onTap: alTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Emoji(emoji, tamano: 20),
              const SizedBox(width: 6),
              Text(texto, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: si ? acentoTexto : p.texto)),
            ]),
          ),
        ),
      ),
    );
  }

  // Fila con interruptor cuadrado. Toda la fila se puede tocar.
  Widget _fila(BuildContext context, String emoji, String texto, bool ver, ValueChanged<bool> cambiar, {Key? key}) {
    final p = paleta(context);
    return Semantics(
      key: key,
      toggled: ver,
      label: texto,
      child: InkWell(
        onTap: () => cambiar(!ver),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borde))),
          child: Row(
            children: [
              Opacity(opacity: ver ? 1 : .35, child: Emoji(emoji, tamano: 22)),
              const SizedBox(width: 12),
              Expanded(child: Text(texto, style: TextStyle(fontSize: 14, color: ver ? p.texto : p.textoSuave))),
              _Interruptor(ver),
            ],
          ),
        ),
      ),
    );
  }
}

// Interruptor cuadrado: borde de 1px y una pieza que se corre; encendido en acento.
class _Interruptor extends StatelessWidget {
  const _Interruptor(this.si);

  final bool si;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final mov = movimiento(context) != Movimiento.completo;
    return AnimatedContainer(
      duration: mov ? Duration.zero : const Duration(milliseconds: 120),
      width: 44,
      height: 24,
      padding: const EdgeInsets.all(3),
      alignment: si ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: si ? acento : p.tarjeta,
        borderRadius: BorderRadius.circular(radio),
        border: Border.all(color: si ? acentoTexto : p.bordeFuerte),
      ),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: si ? acentoTexto : p.textoSuave, borderRadius: BorderRadius.circular(radio)),
      ),
    );
  }
}
