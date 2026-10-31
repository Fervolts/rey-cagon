import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../chat.dart' show aceptoReglas, nombreSala;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show db, textoError;
import '../tema.dart';
import 'control.dart';
import 'fila.dart' show textoEnUnaLinea;
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';

// Compartir cartera: el estado de cuenta del Imperio en el chat (los números los pone el servidor)
// o como imagen para historias (los números salen de esta partida).

/// Lo que sale en la imagen para historias. Se arma de la partida al abrir la hoja.
class DatosCartera {
  const DatosCartera({
    required this.saldo,
    required this.mps,
    required this.pujo,
    required this.mjTotal,
    required this.rollos,
    required this.jaladas,
    this.edificio,
    this.cantidad = 0,
  });

  factory DatosCartera.de(Imperio im, int ahora) {
    Edificio? mayor;
    for (final e in edificios) {
      if (im.cantidad(e.id) > 0) mayor = e;
    }
    return DatosCartera(
      saldo: im.saldo,
      mps: im.mps(ahora),
      pujo: im.valorPujo(ahora),
      mjTotal: im.partida.mjTotal,
      rollos: im.partida.rollos,
      jaladas: im.partida.jaladas,
      edificio: mayor,
      cantidad: mayor == null ? 0 : im.cantidad(mayor.id),
    );
  }

  final double saldo, mps, pujo, mjTotal;
  final int rollos, jaladas;

  /// El edificio más avanzado que tiene (el último del catálogo con al menos una unidad).
  final Edificio? edificio;
  final int cantidad;
}

const _yaPresumio = 'Espera un rato para volver a presumir tu cartera';
const _sinImperio = 'Todavía no tienes Imperio';

/// Hoja con las dos formas de presumir la cartera: EN EL CHAT y FUERA DE LA APP.
Future<void> compartirCartera(BuildContext context, ControlImperio c) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
      builder: (context) => _HojaCartera(c, DatosCartera.de(c.imperio, DateTime.now().millisecondsSinceEpoch)),
    );

class _HojaCartera extends StatefulWidget {
  const _HojaCartera(this.c, this.datos);

  final ControlImperio c;
  final DatosCartera datos;

  @override
  State<_HojaCartera> createState() => _HojaCarteraState();
}

class _HojaCarteraState extends State<_HojaCartera> {
  final _historia = GlobalKey();
  bool _ocupado = false;

  void _aviso(ScaffoldMessengerState? m, String texto) => m
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _alChat() async {
    if (_ocupado) return;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    if (!await aceptoReglas(context) || !mounted) return;
    setState(() => _ocupado = true);
    try {
      // El servidor lee la fila guardada: primero se guarda lo de ahora.
      await widget.c.guardarParaCartera();
      await db.from('mensajes').insert({
        'sala': 'global',
        'tarjeta': {'tipo': 'cartera'},
      });
      widget.c.compartioCartera('chat');
      nav.pop();
      _aviso(mensajero, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
    } catch (e) {
      final mensaje = e is PostgrestException ? e.message : null;
      _aviso(
        mensajero,
        mensaje == _yaPresumio
            ? tr('Ya la presumiste hace poco. Espera unos minutos.', 'You just showed it off. Wait a few minutes.')
            : mensaje == _sinImperio
                ? tr('Tu Imperio todavía no está guardado. Prueba en un rato.', "Your Empire isn't saved yet. Try again in a while.")
                : textoError(e),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _fuera() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      final caja = _historia.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final imagen = await caja.toImage(pixelRatio: 3);
      final png = (await imagen.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      imagen.dispose();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: 'rey-cagon-cartera.png')],
        fileNameOverrides: ['rey-cagon-cartera.png'],
        text: tr('Mi Imperio en Rey Cagón. ¿Tú cuánto tienes? https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon',
            'My Empire in King of the Throne. How much do you have? https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon'),
      ));
      widget.c.compartioCartera('fuera');
    } catch (_) {
      _aviso(mensajero, tr('No se pudo compartir', 'Could not share'));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    Widget opcion(String emoji, String titulo, String texto, VoidCallback alTocar) => InkWell(
          onTap: _ocupado ? null : alTocar,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
            child: Row(children: [
              Emoji(emoji, tamano: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: p.texto)),
                  Text(texto, style: TextStyle(fontSize: 12, color: p.textoSuave)),
                ]),
              ),
            ]),
          ),
        );
    final ancho = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        // La imagen para historias se arma fuera de la pantalla para poder capturarla.
        Positioned(
          left: -2 * HistoriaCartera.ancho - ancho,
          top: 0,
          child: RepaintBoundary(key: _historia, child: HistoriaCartera(widget.datos)),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('PRESUMIR CARTERA', 'SHOW OFF YOUR WALLET'),
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 16, color: p.texto)),
                const SizedBox(height: 12),
                opcion('🚽', tr('EN EL CHAT', 'IN THE CHAT'), tr('Tu estado de cuenta en $nombreSala', 'Your account statement in $nombreSala'), _alChat),
                opcion('📱', tr('FUERA DE LA APP', 'OUTSIDE THE APP'), tr('Imagen para historias', 'Image for your stories'), _fuera),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// La imagen para historias (360x640, como la de la racha): saldo grande, MJ/s, MJ/pujo, lo ganado,
/// rollos, jaladas y el edificio más alto.
class HistoriaCartera extends StatelessWidget {
  const HistoriaCartera(this.d, {super.key});

  static const ancho = 360.0;
  static const alto = 640.0;

  final DatosCartera d;

  @override
  Widget build(BuildContext context) {
    String mj(double v) => formatoMj(v, ingles: enIngles);
    final gris = Colors.white.withValues(alpha: .75);
    final blanco = numeros(context, tamano: 18, weight: FontWeight.w900, color: Colors.white);
    final etiqueta = TextStyle(color: gris, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800);
    Widget dato(String titulo, String valor) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: .25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: etiqueta),
              const SizedBox(height: 2),
              textoEnUnaLinea(valor, blanco),
            ]),
          ),
        );
    final e = d.edificio;
    return SizedBox(
      width: ancho,
      height: alto,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0A09),
          gradient: RadialGradient(
            center: const Alignment(0, -.35),
            radius: .75,
            colors: [acento.withValues(alpha: .35), const Color(0xFF0B0A09)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: acento,
                child: Text(tr('REY CAGÓN', 'KING OF THE THRONE'),
                    style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 14)),
              ),
              const Spacer(flex: 2),
              const IconoMoneda(tamano: 160),
              const SizedBox(height: 14),
              Text(tr('ESTADO DE CUENTA', 'ACCOUNT STATEMENT'), style: etiqueta.copyWith(fontSize: 13, letterSpacing: 3)),
              const SizedBox(height: 4),
              montoMj(mj(d.saldo), numeros(context, tamano: 44, weight: FontWeight.w900, color: acento), alineacion: Alignment.center),
              const SizedBox(height: 16),
              Row(children: [dato('MJ/S', mj(d.mps)), const SizedBox(width: 8), dato(tr('MJ/PUJO', 'MJ/TAP'), mj(d.pujo))]),
              const SizedBox(height: 8),
              Row(children: [
                dato(tr('GANADOS EN TOTAL', 'EARNED IN TOTAL'), mj(d.mjTotal)),
                const SizedBox(width: 8),
                dato(tr('ROLLOS · JALADAS', 'ROLLS · FLUSHES'), '${mj(d.rollos.toDouble())} · ${d.jaladas}'),
              ]),
              if (e != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: .25))),
                  child: Row(children: [
                    Emoji(e.emoji, tamano: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr(e.nombreEs, e.nombreEn).toUpperCase(),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Text('x${formatoCantidad(d.cantidad, ingles: enIngles)}', maxLines: 1, softWrap: false, style: blanco),
                  ]),
                ),
              ],
              const Spacer(flex: 3),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: .25))),
                child: Row(
                  children: [
                    const Emoji('🚽', tamano: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('¿Tú cuánto tienes?', 'How much do you have?'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(tr('Bájala en Google Play', 'Get it on Google Play'), style: TextStyle(color: gris, fontSize: 12)),
                          Text('Rey Cagón · King of the Throne', style: TextStyle(color: gris, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
