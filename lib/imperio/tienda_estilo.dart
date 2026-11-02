// Tienda de estilo del Imperio: temas de la app, efectos del botón CAGUÉ y movimientos del avatar (lib/imperio/estilos.dart).
// Se compran una vez y se quedan para siempre. El tema y el efecto se eligen en el teléfono; el movimiento va al perfil
// (lo ven todos).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../efecto_cague.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'control.dart';
import 'estilos.dart';
import 'estilos_mios.dart';
import 'formato.dart';
import 'moneda_app.dart';
import 'saldo_fijo.dart';

String _mj(double v) => formatoMj(v, ingles: enIngles);

/// Abre la tienda de estilo.
Future<void> abrirTiendaEstilo(BuildContext context, ControlImperio control) {
  control.anotar('estilo_abre');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => ListenableBuilder(
      listenable: Listenable.merge([control, estilosComprados, efectoElegido, movimientoElegidoAvatar, estiloTema, temaElegido]),
      builder: (context, _) => TiendaEstilo(control: control),
    ),
  );
}

class TiendaEstilo extends StatefulWidget {
  const TiendaEstilo({super.key, required this.control});

  final ControlImperio control;

  @override
  State<TiendaEstilo> createState() => _TiendaEstiloState();
}

class _TiendaEstiloState extends State<TiendaEstilo> {
  String? _ocupado; // id de lo que se está comprando o poniendo
  (String, String)? _aviso;
  int _nAviso = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _avisar(String emoji, String texto) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _aviso = (emoji, texto);
      _nAviso++;
    });
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _aviso = null);
    });
  }

  String _porQueNo(Estilo e, String falta) => switch (falta) {
        'mj' => tr('Te faltan ${_mj(widget.control.precioEstilo(e) - widget.control.imperio.saldo)} MJ.',
            'You need ${_mj(widget.control.precioEstilo(e) - widget.control.imperio.saldo)} more MJ.'),
        'rollos' => tr('Te faltan Rollos de Oro: necesitas ${e.rollos}.', 'Not enough Golden Rolls: you need ${e.rollos}.'),
        _ => tr('Necesitas ${e.cagadas} cagadas reales.', 'You need ${e.cagadas} real poops.'),
      };

  Future<void> _comprar(Estilo e) async {
    final falta = widget.control.faltaParaEstilo(e, widget.control.imperio.cagadas);
    if (falta != null) return _avisar(e.emoji, _porQueNo(e, falta));
    setState(() => _ocupado = e.id);
    try {
      await widget.control.comprarEstilo(e);
      _avisar(e.emoji, tr('${e.nombreEs}: es tuyo. Toca USAR.', '${e.nombreEn}: it is yours. Tap USE.'));
    } catch (err) {
      _avisar('💩', textoError(err));
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  Future<void> _usar(Estilo e) async {
    setState(() => _ocupado = e.id);
    try {
      switch (e.tipo) {
        case TipoEstilo.tema:
          await elegirEstiloTema(e.id);
        case TipoEstilo.efecto:
          await elegirEfecto(e.id);
          // Una muestra en el centro de la pantalla.
          if (mounted) {
            final t = MediaQuery.sizeOf(context);
            lanzarEfectoCague(context, boton: Rect.fromCenter(center: Offset(t.width / 2, t.height * .6), width: 80, height: 80), id: e.id);
          }
        case TipoEstilo.movimiento:
          await guardarMovimiento(e.id);
      }
      widget.control.anotar('estilo_usa', {'id': e.id});
      _avisar(e.emoji, tr('${e.nombreEs}: puesto', '${e.nombreEn}: on'));
    } catch (err) {
      _avisar('💩', textoError(err));
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final a = _aviso;
    final quieto = movimiento(context) == Movimiento.nada;
    return Stack(
      children: [
        SafeArea(
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
                          const Emoji('🎨', tamano: 36),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Tienda de estilo', 'Style shop'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.texto)),
                                Text(
                                    tr('Solo se ven bonitos. Se compran una vez y no se pierden al jalar la cadena.',
                                        'They only look nice. Buy once, keep them even after you flush.'),
                                    style: TextStyle(fontSize: 12, color: p.textoSuave)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      _seccion(context, TipoEstilo.tema, tr('Temas', 'Themes'),
                          tr('Cambian los colores de toda la app.', 'They change the colors of the whole app.')),
                      _seccion(context, TipoEstilo.efecto, tr('Efectos de CAGUÉ', 'CAGUÉ effects'),
                          tr('Salen al apretar CAGUÉ. Solo los ves tú.', 'They play when you press CAGUÉ. Only you see them.')),
                      _seccion(context, TipoEstilo.movimiento, tr('Movimientos', 'Moves'),
                          tr('Tu avatar se mueve en el perfil, el ranking y el chat. Lo ven todos.',
                              'Your avatar moves on your profile, the ranking and the chat. Everyone sees it.')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (a != null)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_nAviso),
                tween: Tween(begin: quieto ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 180),
                builder: (context, v, hijo) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -12 * (1 - v)), child: hijo)),
                child: GestureDetector(
                  key: const Key('aviso_estilo'),
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

  Widget _seccion(BuildContext context, TipoEstilo tipo, String titulo, String detalle) {
    final p = paleta(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Rotulo(titulo),
        const SizedBox(height: 4),
        Text(detalle, style: TextStyle(fontSize: 12, color: p.textoSuave)),
        const SizedBox(height: 8),
        for (final e in estilosDe(tipo)) _fila(context, e),
      ],
    );
  }

  Widget _fila(BuildContext context, Estilo e) {
    final p = paleta(context);
    final mio = tengoEstilo(e.id);
    final enUso = estiloEnUso(e.tipo) == e.id;
    final libre = _ocupado == null;
    final Widget boton;
    if (enUso) {
      boton = Text(tr('EN USO', 'ON'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8, color: p.textoSuave));
    } else if (mio) {
      boton = _boton(tr('USAR', 'USE'), libre ? () => _usar(e) : null);
    } else {
      boton = _boton(tr('COMPRAR', 'BUY'), libre ? () => _comprar(e) : null);
    }
    return Container(
      key: Key('estilo_${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: p.tarjeta, border: Border.all(color: enUso ? p.primario : p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Row(
        children: [
          Emoji(e.emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(e.nombreEs, e.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                if (!mio) _precio(context, e),
                if (mio && e.tipo == TipoEstilo.tema) _muestra(e.id),
              ],
            ),
          ),
          const SizedBox(width: 8),
          boton,
        ],
      ),
    );
  }

  /// MJ, Rollos y el mínimo de cagadas que pide (lo que no pide no sale).
  Widget _precio(BuildContext context, Estilo e) {
    final estilo = numeros(context, tamano: 13, weight: FontWeight.w800);
    final suave = numeros(context, tamano: 12, color: paleta(context).textoSuave);
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (e.mj > 0) montoMj(_mj(widget.control.precioEstilo(e)), estilo),
        if (e.rollos > 0) Row(mainAxisSize: MainAxisSize.min, children: [Text('${e.rollos} ', style: estilo), const Emoji('🧻', tamano: 14)]),
        if (e.cagadas > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('mín. ${e.cagadas} ', 'min. ${e.cagadas} '), style: suave),
            const Emoji('💩', tamano: 14),
          ]),
      ],
    );
  }

  /// Cuadritos con el fondo y el acento del tema.
  Widget _muestra(String id) {
    final m = muestraDeTema(id);
    Widget cuadro(Color c) => Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(top: 4, right: 4),
        decoration: BoxDecoration(color: c, border: Border.all(color: m.borde)));
    return Row(children: [cuadro(m.fondo), cuadro(m.tarjeta), cuadro(m.acento)]);
  }

  Widget _boton(String texto, VoidCallback? alTocar) =>
      FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: alTocar, child: Text(texto));
}
