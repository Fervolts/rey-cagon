// Tienda del Imperio: saldo de Ciruelas 🫐, objetos (los pone pantalla.dart con [arriba]), ofertas de Ciruelas
// (efectos al instante) y estéticas del baño (solo suerte).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'ciruelas.dart';
import 'control.dart';
import 'saldo_fijo.dart';
import 'esteticas.dart';

/// "+4%".
String pctSuerte(double bono) => '+${(bono * 100).round()}%';

/// Lo que va arriba de las ofertas (los objetos), con el [avisar] de la hoja.
typedef ArribaTienda = Widget Function(BuildContext context, void Function(String emoji, String texto) avisar);

/// Abre la tienda. Los avisos de lo que se compra salen dentro de la hoja (el aviso de la pantalla queda tapado por ella).
/// [arriba] va antes de las ofertas.
Future<void> abrirTiendaCiruelas(BuildContext context, ControlImperio control, {ArribaTienda? arriba}) {
  control.anotar('tienda_ciruelas_abre');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => _ConAvisos(
      hijo: (avisar) => ListenableBuilder(
        listenable: control,
        builder: (context, _) => TiendaCiruelas(control: control, avisar: avisar, arriba: arriba),
      ),
    ),
  );
}

/// La hoja con su propio aviso arriba: aparece al comprar, alquilar o cuando no se puede (y dice por qué), y vibra.
class _ConAvisos extends StatefulWidget {
  const _ConAvisos({required this.hijo});
  final Widget Function(void Function(String emoji, String texto) avisar) hijo;

  @override
  State<_ConAvisos> createState() => _ConAvisosState();
}

class _ConAvisosState extends State<_ConAvisos> {
  (String, String)? _aviso;
  int _n = 0;
  Timer? _timer;

  void _avisar(String emoji, String texto) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _aviso = (emoji, texto);
      _n++;
    });
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _aviso = null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final a = _aviso;
    final quieto = movimiento(context) == Movimiento.nada;
    return Stack(
      children: [
        widget.hijo(_avisar),
        if (a != null)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_n),
                tween: Tween(begin: quieto ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 180),
                builder: (context, v, hijo) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -12 * (1 - v)), child: hijo)),
                child: GestureDetector(
                  key: const Key('aviso_tienda'),
                  onTap: () => setState(() => _aviso = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: p.fondo, border: Border.all(color: p.primario), borderRadius: BorderRadius.circular(radio)),
                    child: Row(
                      children: [
                        Emoji(a.$1, tamano: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text(a.$2, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class TiendaCiruelas extends StatefulWidget {
  const TiendaCiruelas({super.key, required this.control, required this.avisar, this.arriba});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  /// Lo que va entre el saldo y las ofertas (los objetos).
  final ArribaTienda? arriba;

  @override
  State<TiendaCiruelas> createState() => _TiendaCiruelasState();
}

class _TiendaCiruelasState extends State<TiendaCiruelas> {
  String? _ocupado; // id de lo que se está comprando

  Future<void> _comprar(String id, Future<bool> Function() compra, String emoji, String hecho) async {
    setState(() => _ocupado = id);
    try {
      final ok = await compra();
      widget.avisar(ok ? emoji : '🫐', ok ? hecho : tr('No te alcanzan las Ciruelas.', 'Not enough Plums.'));
    } catch (e) {
      widget.avisar('💩', textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = widget.control.imperio;
    return SafeArea(
      // El saldo queda fijo arriba; solo baja la lista.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaldoFijo(control: widget.control),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Emoji('🫐', tamano: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('${im.ciruelas} Ciruelas', '${im.ciruelas} Plums'),
                                key: const Key('saldo_ciruelas'), style: numeros(context, tamano: 22, weight: FontWeight.w900)),
                            Text(
                                tr('Salen de vez en cuando al pujar, al cagar de verdad y en la racha.',
                                    'They drop now and then when you push, when you really poop and in the streak.'),
                                style: TextStyle(fontSize: 12, color: p.textoSuave)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.arriba case final arriba?) ...[const SizedBox(height: 16), arriba(context, widget.avisar)],
                  const SizedBox(height: 16),
                  Rotulo(tr('Ofertas de Ciruelas', 'Plum deals')),
                  const SizedBox(height: 8),
                  for (final o in ofertasCiruela)
                    _fila(
                      context,
                      emoji: o.emoji,
                      titulo: tr(o.nombreEs, o.nombreEn),
                      detalle: o.id == 'congelador'
                          ? '${tr(o.descEs, o.descEn)} · ${widget.control.congeladores}/$maxCongeladores'
                          : tr(o.descEs, o.descEn),
                      precio: o.precio,
                      boton: _boton(
                        context,
                        o.id == 'congelador' && widget.control.congeladores >= maxCongeladores ? tr('LLENO', 'FULL') : tr('COMPRAR', 'BUY'),
                        _ocupado == null && im.ciruelas >= o.precio && !(o.id == 'congelador' && widget.control.congeladores >= maxCongeladores)
                            ? () => _comprar(o.id, () => widget.control.gastarCiruelas(o.id), o.emoji,
                                tr('${o.nombreEs}: listo', '${o.nombreEn}: done'))
                            : null,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Rotulo(tr('Tu baño de lujo', 'Your luxury bathroom'))),
                      Text(tr('${pctSuerte(im.bonoSuerte)} de suerte ', '${pctSuerte(im.bonoSuerte)} luck '),
                          key: const Key('suerte_total'), style: numeros(context, tamano: 13, weight: FontWeight.w900)),
                      const Emoji('🫐', tamano: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Solo se ven bonitas y suben la suerte de que caigan Ciruelas.', 'They only look nice and raise your luck for Plums.'),
                      style: TextStyle(fontSize: 12, color: p.textoSuave)),
                  const SizedBox(height: 8),
                  for (final e in esteticas)
                    _fila(
                      context,
                      emoji: e.emoji,
                      titulo: tr(e.nombreEs, e.nombreEn),
                      detalle: tr('${pctSuerte(e.bono)} de suerte', '${pctSuerte(e.bono)} luck'),
                      precio: im.esteticas.contains(e.id) ? null : e.precio,
                      boton: im.esteticas.contains(e.id)
                          ? Text(tr('COMPRADA', 'OWNED'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8, color: p.textoSuave))
                          : _boton(
                              context,
                              tr('COMPRAR', 'BUY'),
                              _ocupado == null && im.ciruelas >= e.precio
                                  ? () => _comprar(e.id, () => widget.control.comprarEstetica(e.id), e.emoji,
                                      tr('${e.nombreEs}: ${pctSuerte(e.bono)} de suerte', '${e.nombreEn}: ${pctSuerte(e.bono)} luck'))
                                  : null,
                            ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boton(BuildContext context, String texto, VoidCallback? alTocar) =>
      FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: alTocar, child: Text(texto));

  Widget _fila(BuildContext context, {required String emoji, required String titulo, required String detalle, int? precio, required Widget boton}) {
    final p = paleta(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Row(
        children: [
          Emoji(emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                Text(detalle, style: TextStyle(fontSize: 12, color: p.textoSuave)),
                if (precio != null)
                  Row(
                    children: [
                      Text('$precio ', style: numeros(context, tamano: 13, weight: FontWeight.w800)),
                      const Emoji('🫐', tamano: 14),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          boton,
        ],
      ),
    );
  }
}
