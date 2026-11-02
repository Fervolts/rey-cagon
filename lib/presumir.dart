import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'chat.dart' show nombreSala;
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'imperio/catalogo.dart' as imperio show logros;
import 'imperio/formato.dart' show formatoMj;
import 'imperio/hoja_racha.dart' show nombreLogro;
import 'peso.dart';
import 'racha.dart';
import 'tema.dart';
import 'tipos.dart';

/// Las tarjetas de presumir del chat, cada una con su objeto: el hito es un periódico, el
/// desbloqueo una vitrina con etiqueta de precio, la cagada una muestra de laboratorio, la racha
/// un anuncio de juego (tipo MOBA), el logro del Imperio una placa con trofeo y la jalada un medidor.
/// Son objetos físicos: mismos colores en tema claro y oscuro. La cartera va aparte (tarjeta_cartera.dart).

const _tinta = Color(0xFF171513);
const _serif = 'serif';
const _mono = 'monospace';

/// La tarjeta propia de [t] o null si el tipo no es de aquí. [perfil] y [hora] (del mensaje) los usa la racha.
Widget? tarjetaPresumir(Map<String, dynamic> t, {Map<String, dynamic>? perfil, DateTime? hora}) {
  int entero(Object? v) => v is num ? v.toInt() : 0;
  return switch (t['tipo']) {
    'hito' => TarjetaTitular(n: entero(t['n']), reina: t['reina'] == true),
    'desbloqueo' => TarjetaVitrina.de('${t['emoji']}', minimo: t['minimo'] is num ? entero(t['minimo']) : null),
    'cagada' => TarjetaMuestra(n: entero(t['n']), mojon: t['mojon'] as int?, peso: t['peso'] as int?),
    'racha' => TarjetaRacha(n: entero(t['n']), perfil: perfil, hora: hora),
    'logro_imperio' => TarjetaPlaca(id: '${t['id']}'),
    'jalada' => TarjetaContador(n: entero(t['n']), rollos: ((t['rollos'] as num?) ?? 0).toDouble()),
    _ => null,
  };
}

/// Pregunta antes de mandar al chat, con la tarjeta tal cual saldrá.
Future<bool> preguntarPresumir(BuildContext context, {required String titulo, required Widget tarjeta, required String boton}) async {
  final p = paleta(context);
  final si = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5)),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tarjeta,
          const SizedBox(height: 12),
          Text(tr('Así sale en $nombreSala. ¿Lo presumes?', 'This is how it shows in $nombreSala. Show it off?'),
              style: TextStyle(color: p.textoSuave, fontSize: 13)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(boton)),
      ],
    ),
  );
  return si == true;
}

/// Las preguntas de cada presumir que sale solo (al llegar a un hito, desbloquear o ganar un logro).
Future<bool> preguntarHito(BuildContext context, int n) => preguntarPresumir(context,
    titulo: tr('¡PAREN LAS PRENSAS!', 'STOP THE PRESSES!'),
    tarjeta: TarjetaTitular(n: n, reina: miGenero == 'mujer'),
    boton: tr('PUBLICAR', 'PRINT IT'));

Future<bool> preguntarDesbloqueo(BuildContext context, Desbloqueo d) => preguntarPresumir(context,
    titulo: tr('Recién llegado a tu vitrina', 'Just arrived in your window'),
    tarjeta: TarjetaVitrina(emoji: d.emoji, nombre: d.nombre, ranura: d.ranura, minimo: d.minimo),
    boton: tr('EXHIBIR', 'DISPLAY IT'));

Future<bool> preguntarLogroImperio(BuildContext context, String id) => preguntarPresumir(context,
    titulo: tr('Placa grabada', 'Plaque engraved'), tarjeta: TarjetaPlaca(id: id), boton: tr('COLGARLA', 'HANG IT UP'));

/// La hoja de PRESUMIR del chat: laboratorio (última cagada), hemeroteca (hitos) y vitrina
/// (desbloqueos). Devuelve la tarjeta a mandar o null.
Future<Map<String, dynamic>?> elegirPresumir(BuildContext context,
    {Map<String, dynamic>? ultima, required int total, required Iterable<int> hitos, required Iterable<Desbloqueo> mios}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 0, 16, 16)),
        children: [
          Text(tr('PRESUMIR', 'SHOW OFF'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(tr('Escoge qué sale en $nombreSala', 'Pick what goes up in $nombreSala'),
              style: TextStyle(color: paleta(context).textoSuave, fontSize: 13)),
          if (ultima != null) ...[
            const SizedBox(height: 16),
            Rotulo(tr('Laboratorio', 'Lab')),
            const SizedBox(height: 6),
            _Tocable(
              onTap: () => Navigator.pop(context, {'tipo': 'cagada', 'id': ultima['id']}),
              child: _EtiquetaMuestra(mojon: ultima['tipo'] as int?, n: total),
            ),
          ],
          if (hitos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Rotulo(tr('Hemeroteca', 'Newspaper archive')),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in hitos)
                _Tocable(onTap: () => Navigator.pop(context, {'tipo': 'hito', 'n': h}), child: _Recorte(h)),
            ]),
          ],
          if (mios.isNotEmpty) ...[
            const SizedBox(height: 16),
            Rotulo(tr('Vitrina', 'Shop window')),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 10, children: [
              for (final d in mios)
                _Tocable(onTap: () => Navigator.pop(context, {'tipo': 'desbloqueo', 'emoji': d.emoji}), child: _Etiqueta(d)),
            ]),
          ],
          if (ultima == null && hitos.isEmpty && mios.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Todavía no tienes nada que presumir. ¡A cagar!', 'Nothing to show off yet. Go drop a deuce!')),
            ),
        ],
      ),
    ),
  );
}

class _Tocable extends StatelessWidget {
  const _Tocable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radio), child: child),
      );
}

// ───────────────────────────── HITO: periódico ─────────────────────────────

const _papelPeriodico = Color(0xFFF3EEE2);

/// Hito del chat: la portada extra de "El Diario del Trono".
class TarjetaTitular extends StatelessWidget {
  const TarjetaTitular({super.key, required this.n, this.reina = false});

  final int n;
  final bool reina;

  @override
  Widget build(BuildContext context) {
    const chico = TextStyle(fontFamily: _mono, fontSize: 9, color: _tinta, letterSpacing: .5);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(color: _papelPeriodico, border: Border.all(color: _tinta), borderRadius: BorderRadius.circular(radio)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(tr('AÑO I · Nº $n', 'VOL. I · No. $n'), style: chico),
          const Spacer(),
          Text(tr('EDICIÓN EXTRA', 'EXTRA EDITION'), style: chico.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 2),
        FittedBox(
          child: Text(tr('El Diario del Trono', 'The Throne Times'),
              style: const TextStyle(fontFamily: _serif, fontSize: 24, fontWeight: FontWeight.w900, color: _tinta, height: 1.1)),
        ),
        const SizedBox(height: 3),
        Container(height: 3, color: _tinta),
        const SizedBox(height: 2),
        Container(height: 1, color: _tinta),
        const SizedBox(height: 8),
        Text(tr('¡LLEGÓ A $n CAGADAS!', 'HITS $n POOPS!'),
            style: const TextStyle(fontFamily: _serif, fontSize: 25, fontWeight: FontWeight.w900, color: _tinta, height: 1.05)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFDCD5C3), border: Border.all(color: _tinta)),
            child: const Emoji('👑', tamano: 40),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                reina ? tr('Arrodíllense ante la reina', 'Bow down to the queen') : tr('Arrodíllense ante el rey', 'Bow down to the king'),
                style: const TextStyle(fontFamily: _serif, fontStyle: FontStyle.italic, fontSize: 14, color: _tinta, height: 1.15),
              ),
              const SizedBox(height: 6),
              for (final f in const [10, 8, 9]) ...[_Renglon(f), const SizedBox(height: 4)],
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// Una línea de texto de relleno del periódico (gris, [lleno] de 10).
class _Renglon extends StatelessWidget {
  const _Renglon(this.lleno);

  final int lleno;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(flex: lleno, child: Container(height: 4, color: const Color(0xFFB9B2A2))),
        Expanded(flex: 10 - lleno + 1, child: const SizedBox()),
      ]);
}

/// Recorte de periódico para la hemeroteca de la hoja PRESUMIR.
class _Recorte extends StatelessWidget {
  const _Recorte(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(color: _papelPeriodico, border: Border.all(color: _tinta), borderRadius: BorderRadius.circular(radio)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('EL DIARIO', 'THE TIMES'), style: const TextStyle(fontFamily: _serif, fontSize: 9, fontWeight: FontWeight.w900, color: _tinta)),
          Container(height: 2, color: _tinta, margin: const EdgeInsets.symmetric(vertical: 3)),
          Text('$n', style: const TextStyle(fontFamily: _serif, fontSize: 28, fontWeight: FontWeight.w900, color: _tinta, height: 1)),
          Text(tr('CAGADAS', 'POOPS'), style: const TextStyle(fontFamily: _serif, fontSize: 11, fontWeight: FontWeight.w700, color: _tinta)),
          const SizedBox(height: 4),
          const _Renglon(9),
        ]),
      );
}

// ───────────────────────────── DESBLOQUEO: vitrina ─────────────────────────────

const _vidrio = Color(0xFFD6ECEF);

String _seccion(String ranura) => switch (ranura) {
      'mascota' => tr('Mascotas', 'Pets'),
      'sombrero' => tr('Sombreros', 'Hats'),
      'lentes' => tr('Lentes', 'Eyewear'),
      'avatar' => tr('Disfraces', 'Costumes'),
      _ => tr('Novedades', 'New arrivals'),
    };

/// Desbloqueo de ropa o accesorio: la pieza en la vitrina de la tienda, con su etiqueta de precio
/// (el precio son cagadas).
class TarjetaVitrina extends StatelessWidget {
  const TarjetaVitrina({super.key, required this.emoji, required this.nombre, required this.ranura, required this.minimo});

  /// Desde la tarjeta guardada en el chat (solo trae el emoji y a veces el mínimo).
  factory TarjetaVitrina.de(String emoji, {int? minimo}) {
    final d = desbloqueos.where((x) => x.emoji == emoji).firstOrNull;
    return TarjetaVitrina(emoji: emoji, nombre: d?.nombre ?? '', ranura: d?.ranura ?? '', minimo: minimo ?? d?.minimo ?? 0);
  }

  final String emoji;
  final String nombre;
  final String ranura;
  final int minimo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _tinta, border: Border.all(color: _tinta), borderRadius: BorderRadius.circular(radio)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 24, child: CustomPaint(painter: _Toldo())),
        Container(
          height: 128,
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          color: _vidrio,
          child: Stack(children: [
            const Positioned.fill(child: CustomPaint(painter: _Reflejo())),
            Align(
              alignment: const Alignment(-.25, .2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Emoji(emoji, tamano: 58),
                const SizedBox(height: 2),
                Container(width: 78, height: 8, color: const Color(0xFF8E8A80)),
                Container(width: 92, height: 6, color: const Color(0xFF5E5A52)),
              ]),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: acento,
                child: Text(tr('NUEVO', 'NEW'),
                    style: TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
              ),
            ),
            Positioned(right: 10, top: 26, child: Transform.rotate(angle: .2, child: _Precio(minimo))),
          ]),
        ),
        Container(height: 4, margin: const EdgeInsets.symmetric(horizontal: 8), color: const Color(0xFF8E8A80)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('RECIÉN LLEGADO A LA VITRINA', 'NOW IN THE WINDOW'),
                style: TextStyle(fontFamily: _mono, color: acento, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(nombre.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1, height: 1.1)),
            Text(tr('Sección ${_seccion(ranura).toLowerCase()} · talla única', '${_seccion(ranura)} section · one size fits all'),
                style: const TextStyle(color: Color(0xFFB5B1A8), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

/// El toldo de rayas de la tienda, con flecos cuadrados abajo.
class _Toldo extends CustomPainter {
  const _Toldo();

  @override
  void paint(Canvas canvas, Size size) {
    const ancho = 22.0;
    final cuerpo = size.height - 7;
    final amarillo = Paint()..color = acento;
    final blanco = Paint()..color = const Color(0xFFF7F3E8);
    for (var i = 0; i * ancho < size.width; i++) {
      final x = i * ancho;
      final pintura = i.isEven ? amarillo : blanco;
      canvas.drawRect(Rect.fromLTWH(x, 0, ancho, cuerpo), pintura);
      canvas.drawRect(Rect.fromLTWH(x + 3, cuerpo, ancho - 6, 7), pintura);
    }
    canvas.drawRect(Rect.fromLTWH(0, cuerpo - 1, size.width, 1), Paint()..color = _tinta.withValues(alpha: .35));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// El brillo diagonal del vidrio.
class _Reflejo extends CustomPainter {
  const _Reflejo();

  @override
  void paint(Canvas canvas, Size size) {
    final brillo = Paint()..color = Colors.white.withValues(alpha: .55);
    void franja(double x, double ancho) => canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + ancho, size.height)
          ..lineTo(x + ancho + size.height * .6, 0)
          ..lineTo(x + size.height * .6, 0)
          ..close(),
        brillo);
    franja(size.width * .55, 18);
    franja(size.width * .55 + 26, 6);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// La etiqueta de precio colgando: punta a la izquierda con su hueco y el cordón.
class _Precio extends StatelessWidget {
  const _Precio(this.minimo);

  final int minimo;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: const _FormaEtiqueta(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 10, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('PRECIO', 'PRICE'), style: TextStyle(fontFamily: _mono, fontSize: 8, color: acentoTexto, letterSpacing: 1)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$minimo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: acentoTexto, height: 1)),
              const SizedBox(width: 3),
              const Emoji('💩', tamano: 16),
            ]),
          ]),
        ),
      );
}

class _FormaEtiqueta extends CustomPainter {
  const _FormaEtiqueta({this.hilo = true});

  /// El hilo que la cuelga del vidrio; en la lista de la hoja va sin hilo.
  final bool hilo;

  @override
  void paint(Canvas canvas, Size size) {
    final punta = size.height / 2;
    final forma = Path()
      ..moveTo(0, punta)
      ..lineTo(12, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(12, size.height)
      ..close();
    canvas.drawPath(forma, Paint()..color = acento);
    canvas.drawPath(
        forma,
        Paint()
          ..color = _tinta
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    canvas.drawRect(Rect.fromCenter(center: Offset(10, punta), width: 4, height: 4), Paint()..color = _vidrio);
    if (!hilo) return;
    canvas.drawLine(Offset(10, punta), Offset(-14, -18), Paint()
      ..color = _tinta
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Etiqueta de precio chica para la vitrina de la hoja PRESUMIR.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.d);

  final Desbloqueo d;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: const _FormaEtiqueta(hilo: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 10, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Emoji(d.emoji, tamano: 22),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(d.nombre, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: acentoTexto)),
              Text(tr('${d.minimo} cagadas', '${d.minimo} poops'),
                  style: TextStyle(fontFamily: _mono, fontSize: 10, color: acentoTexto)),
            ]),
          ]),
        ),
      );
}

// ───────────────────────────── CAGADA: muestra de laboratorio ─────────────────────────────

const _verdeLab = Color(0xFF1E3A2F);

/// La cagada presumida: etiqueta de muestra del laboratorio del trono.
class TarjetaMuestra extends StatelessWidget {
  const TarjetaMuestra({super.key, required this.n, this.mojon, this.peso});

  final int n;
  final int? mojon;
  final int? peso;

  @override
  Widget build(BuildContext context) {
    final pesoTexto = pesos[peso]?.$2 ?? tr('Sin pesar', 'Not weighed');
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFFAFAF5), border: Border.all(color: _verdeLab, width: 1.5), borderRadius: BorderRadius.circular(radio)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: _verdeLab,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Text(tr('LAB. DEL TRONO', 'THRONE LAB'),
                style: const TextStyle(fontFamily: _mono, color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.5)),
            const Spacer(),
            Text(tr('MUESTRA #$n', 'SAMPLE #$n'),
                style: TextStyle(fontFamily: _mono, color: acento, fontWeight: FontWeight.w700, fontSize: 11)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            _Frasco(mojon: mojon, tamano: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                _Dato(tr('TIPO', 'TYPE'), (tipos[mojon]?.$2 ?? '?').toUpperCase()),
                _Dato(tr('PESO', 'WEIGHT'), pesoTexto.toUpperCase()),
                _Dato(tr('ESTADO', 'STATUS'), tr('ANALIZADA', 'ANALYZED'), ultimo: true),
              ]),
            ),
          ]),
        ),
        Container(
          color: const Color(0xFFE9E7DD),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(tr('NO APTA PARA CONSUMO HUMANO', 'NOT FIT FOR HUMAN CONSUMPTION'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: _mono, fontSize: 9, color: Color(0xFFB3261E), letterSpacing: 1, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// El frasco de muestra: tapa oscura y el mojón adentro.
class _Frasco extends StatelessWidget {
  const _Frasco({required this.mojon, required this.tamano});

  final int? mojon;
  final double tamano;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: tamano + 10, height: tamano * .22, color: _verdeLab),
        Container(
          width: tamano + 18,
          height: tamano + 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFE3F0EA), border: Border.all(color: _verdeLab, width: 2)),
          child: Emoji(tipoEmoji(mojon), tamano: tamano),
        ),
      ]);
}

class _Dato extends StatelessWidget {
  const _Dato(this.campo, this.valor, {this.ultimo = false});

  final String campo;
  final String valor;
  final bool ultimo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(border: ultimo ? null : const Border(bottom: BorderSide(color: Color(0xFFCBD5CF)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 58,
            child: Text(campo, style: const TextStyle(fontFamily: _mono, fontSize: 10, color: Color(0xFF5F6B64), height: 1.5)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontFamily: _mono, fontSize: 13, color: _tinta, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// La muestra chica de la hoja PRESUMIR.
class _EtiquetaMuestra extends StatelessWidget {
  const _EtiquetaMuestra({required this.mojon, required this.n});

  final int? mojon;
  final int n;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: const Color(0xFFFAFAF5), border: Border.all(color: _verdeLab, width: 1.5), borderRadius: BorderRadius.circular(radio)),
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          _Frasco(mojon: mojon, tamano: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('MI ÚLTIMA MUESTRA', 'MY LATEST SAMPLE'),
                  style: const TextStyle(fontFamily: _mono, fontSize: 10, color: Color(0xFF5F6B64), letterSpacing: 1)),
              Text((tipos[mojon]?.$2 ?? '?').toUpperCase(),
                  style: const TextStyle(fontFamily: _mono, fontSize: 14, color: _tinta, fontWeight: FontWeight.w700)),
            ]),
          ),
          Text('#$n', style: const TextStyle(fontFamily: _mono, fontSize: 12, color: _verdeLab, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ───────────────────────────── RACHA: anuncio de juego (tipo MOBA) ─────────────────────────────

const _oroClaro = Color(0xFFFFF1B0);
const _nocheMoba = Color(0xFF0B0A10);
const _nocheMobaAlta = Color(0xFF1C1428);

/// Mojones de la fila de "kills": los del día encendidos, el resto apagados.
const _ranuras = 6;

/// Gris para los mojones apagados.
const _gris = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// El color que brilla de la racha (el más claro: el rojo oscuro de RAMPAGE no alumbra).
Color _brilloRacha(List<Color> colores) => colores.last.computeLuminance() < .1 ? colores.first : colores.last;

/// "2 cagadas hoy · 20:51" (sin hora si no se sabe).
String _lineaRacha(int n, DateTime? hora) {
  final base = n == 1 ? tr('1 cagada hoy', '1 poop today') : tr('$n cagadas hoy', '$n poops today');
  if (hora == null) return base;
  final h = hora.toLocal();
  return '$base · ${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
}

/// Rectángulo con las esquinas cortadas a [corte].
Path _chaflan(Rect r, double corte) => Path()
  ..moveTo(r.left + corte, r.top)
  ..lineTo(r.right - corte, r.top)
  ..lineTo(r.right, r.top + corte)
  ..lineTo(r.right, r.bottom - corte)
  ..lineTo(r.right - corte, r.bottom)
  ..lineTo(r.left + corte, r.bottom)
  ..lineTo(r.left, r.bottom - corte)
  ..lineTo(r.left, r.top + corte)
  ..close();

Shader _oroShader(Rect r) => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_oroClaro, _bronce, _bronceOscuro, _bronce, _oroClaro],
      stops: [0, .3, .55, .8, 1],
    ).createShader(r);

/// Fondo del anuncio: noche, brillo del color de la racha, rayas de velocidad y marco de oro con esquinas cortadas.
class _MarcoMoba extends CustomPainter {
  const _MarcoMoba(this.brillo, {this.corte = 10, this.centroBrillo = const Alignment(.3, -.2), this.rayas = 16});

  final Color brillo;
  final double corte;
  final Alignment centroBrillo;
  final int rayas;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final borde = _chaflan(r.deflate(.75), corte);
    canvas.save();
    canvas.clipPath(borde);
    canvas.drawRect(
        r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_nocheMobaAlta, _nocheMoba]).createShader(r));
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(center: centroBrillo, radius: .8, colors: [brillo.withValues(alpha: .38), brillo.withValues(alpha: 0)])
            .createShader(r),
    );
    // Rayas de velocidad, inclinadas como la letra.
    final raya = Paint()
      ..color = Colors.white.withValues(alpha: .05)
      ..strokeWidth = 1;
    final paso = size.width / rayas;
    for (var i = 0; i <= rayas + 4; i++) {
      final x = i * paso;
      canvas.drawLine(Offset(x, 0), Offset(x - size.height * .45, size.height), raya);
    }
    canvas.restore();
    canvas.drawPath(borde, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = _oroShader(r));
    canvas.drawPath(
      _chaflan(r.deflate(4), math.max(0, corte - 2.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _bronce.withValues(alpha: .35),
    );
    // Picos de oro arriba y abajo, al centro.
    final m = size.width / 2;
    final pico = Paint()..shader = _oroShader(r);
    canvas.drawPath(Path()..moveTo(m - 12, 0)..lineTo(m + 12, 0)..lineTo(m, 5)..close(), pico);
    canvas.drawPath(Path()..moveTo(m - 12, size.height)..lineTo(m + 12, size.height)..lineTo(m, size.height - 5)..close(), pico);
  }

  @override
  bool shouldRepaint(covariant _MarcoMoba old) => old.brillo != brillo || old.corte != corte || old.centroBrillo != centroBrillo;
}

/// El retrato del que la hizo en marco de héroe: oro con esquinas cortadas y brillo detrás.
class _Retrato extends StatelessWidget {
  const _Retrato({required this.tamano, required this.brillo, required this.child});

  final double tamano;
  final Color brillo;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: tamano,
        height: tamano,
        child: CustomPaint(
          painter: _MarcoRetrato(brillo),
          child: Padding(padding: EdgeInsets.all(tamano * .12), child: FittedBox(child: child)),
        ),
      );
}

class _MarcoRetrato extends CustomPainter {
  const _MarcoRetrato(this.brillo);

  final Color brillo;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final corte = size.width * .2;
    final marco = _chaflan(r.deflate(1), corte);
    canvas.drawPath(
      marco,
      Paint()..shader = RadialGradient(colors: [brillo.withValues(alpha: .55), _nocheMoba], stops: const [0, 1]).createShader(r),
    );
    canvas.drawPath(marco, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.width / 30)
      ..shader = _oroShader(r));
    canvas.drawPath(
      _chaflan(r.deflate(size.width * .07), corte * .7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _oroClaro.withValues(alpha: .4),
    );
  }

  @override
  bool shouldRepaint(covariant _MarcoRetrato old) => old.brillo != brillo;
}

/// El nombre de la racha como anuncio: itálica gruesa, borde negro, degradado y brillo.
class _NombreRacha extends StatelessWidget {
  const _NombreRacha(this.texto, {required this.colores, required this.tamano});

  final String texto;
  final List<Color> colores;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final brillo = _brilloRacha(colores);
    final base = TextStyle(fontSize: tamano, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: .5, height: 1.05);
    return Padding(
      // La itálica se sale por la derecha: aire para que no se corte.
      padding: EdgeInsets.only(right: tamano * .15),
      child: Stack(children: [
        Text(texto,
            maxLines: 1,
            softWrap: false,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = tamano / 6
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.black,
              shadows: [Shadow(color: brillo, blurRadius: tamano * .7), Shadow(color: brillo.withValues(alpha: .6), blurRadius: tamano * .25)],
            )),
        ShaderMask(
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(colores.first, Colors.white, .65)!, ...colores],
            stops: const [0, .45, 1],
          ).createShader(r),
          child: Text(texto, maxLines: 1, softWrap: false, style: base.copyWith(color: Colors.white)),
        ),
      ]),
    );
  }
}

/// La fila de "kills": [n] mojones encendidos de 6 y los demás apagados; pasado el 6, "+k".
class _Kills extends StatelessWidget {
  const _Kills({required this.n, required this.brillo, required this.tamano});

  final int n;
  final Color brillo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final extra = n - _ranuras;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < _ranuras; i++) ...[
        if (i > 0) SizedBox(width: tamano * .14),
        _Ranura(encendida: i < n, brillo: brillo, tamano: tamano),
      ],
      if (extra > 0) ...[
        SizedBox(width: tamano * .2),
        Text('+$extra',
            style: TextStyle(
                color: _oroClaro, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: tamano * .6, shadows: [Shadow(color: brillo, blurRadius: 8)])),
      ],
    ]);
  }
}

class _Ranura extends StatelessWidget {
  const _Ranura({required this.encendida, required this.brillo, required this.tamano});

  final bool encendida;
  final Color brillo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final mojon = Emoji('💩', tamano: tamano * .72);
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radio),
        border: Border.all(color: encendida ? brillo : Colors.white.withValues(alpha: .16)),
        gradient: encendida
            ? RadialGradient(colors: [brillo.withValues(alpha: .6), brillo.withValues(alpha: .08)])
            : LinearGradient(colors: [Colors.black.withValues(alpha: .35), Colors.black.withValues(alpha: .35)]),
      ),
      child: encendida ? mojon : Opacity(opacity: .28, child: ColorFiltered(colorFilter: _gris, child: mojon)),
    );
  }
}

/// Racha del día en el chat: anuncio de juego con el retrato, el nombre enorme y la fila de kills.
/// [perfil] (avatar del que cagó) y [hora] son opcionales: sin perfil sale el emoji del nivel.
class TarjetaRacha extends StatelessWidget {
  const TarjetaRacha({super.key, required this.n, this.perfil, this.hora});

  final int n;
  final Map<String, dynamic>? perfil;
  final DateTime? hora;

  @override
  Widget build(BuildContext context) {
    final (colores, emojiNivel) = estiloRacha(n);
    final brillo = _brilloRacha(colores);
    return CustomPaint(
      painter: _MarcoMoba(brillo),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Row(children: [
          _Retrato(
            tamano: 64,
            brillo: brillo,
            child: perfil != null ? Avatar(perfil!, tamano: 56) : Emoji(emojiNivel, tamano: 48),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tr('RACHA DE HOY', "TODAY'S STREAK"),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(fontFamily: _mono, color: _bronce, fontWeight: FontWeight.w700, fontSize: 9, letterSpacing: 3)),
              SizedBox(
                height: 36,
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _NombreRacha(nombreRacha(n) ?? tr('RACHA', 'STREAK'), colores: colores, tamano: 30),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _Kills(n: n, brillo: brillo, tamano: 22)),
              const SizedBox(height: 6),
              Text(_lineaRacha(n, hora),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: _mono, color: Colors.white.withValues(alpha: .75), fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// La imagen 9:16 de la racha para historias: el mismo anuncio en grande.
/// Los tamaños los fija quien la usa (racha.dart).
class HistoriaRacha extends StatelessWidget {
  const HistoriaRacha({super.key, required this.n, this.foto, this.letrero, this.usuario, this.lugar, this.hora});

  final int n;

  /// Otro letrero para el nombre; sin él, el de la tarjeta del chat.
  final Widget? letrero;

  /// El avatar del usuario; sin él, el emoji del nivel.
  final Widget? foto;
  final String? usuario;
  final String? lugar;
  final DateTime? hora;

  @override
  Widget build(BuildContext context) {
    final (colores, emojiNivel) = estiloRacha(n);
    final brillo = _brilloRacha(colores);
    const blanco = Colors.white;
    return CustomPaint(
      painter: _MarcoMoba(brillo, corte: 18, centroBrillo: const Alignment(0, -.25), rayas: 14),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 26),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: acento,
          child: Text(tr('REY CAGÓN', 'KING OF THE THRONE'),
              style: TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 14)),
        ),
        const Spacer(),
        Text(tr('RACHA DE HOY', "TODAY'S STREAK"),
            style: const TextStyle(fontFamily: _mono, color: _bronce, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 6)),
        const SizedBox(height: 14),
        _Retrato(tamano: 150, brillo: brillo, child: foto ?? Emoji(emojiNivel, tamano: 110)),
        const SizedBox(height: 18),
        SizedBox(
          height: 78,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: FittedBox(child: letrero ?? _NombreRacha(nombreRacha(n) ?? tr('RACHA', 'STREAK'), colores: colores, tamano: 60)),
          ),
        ),
        const SizedBox(height: 16),
        FittedBox(child: _Kills(n: n, brillo: brillo, tamano: 38)),
        const SizedBox(height: 12),
        Text(_lineaRacha(n, hora),
            style: TextStyle(fontFamily: _mono, color: blanco.withValues(alpha: .8), fontSize: 15, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (usuario != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('@$usuario',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: blanco, fontWeight: FontWeight.w900, fontSize: 20)),
          ),
        if (lugar != null) Text(lugar!, textAlign: TextAlign.center, style: TextStyle(color: blanco.withValues(alpha: .6), fontSize: 13)),
        Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(26, 12, 26, 0),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, _bronce, Colors.transparent])),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 12, 26, 22),
          child: Row(children: [
            const Emoji('🚽', tamano: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('¿Tú cuántas llevas?', 'How many have you done?'),
                    style: const TextStyle(color: blanco, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(tr('Bájala en Google Play · Rey Cagón', 'Get it on Google Play · King of the Throne'),
                    style: TextStyle(color: blanco.withValues(alpha: .7), fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────────── LOGRO DEL IMPERIO: trofeo con placa ─────────────────────────────

const _madera = Color(0xFF3B2A1C);
const _bronce = Color(0xFFD9B44A);
const _bronceOscuro = Color(0xFF7A5A14);

/// Logro del Imperio: el trofeo sobre su base y la placa de bronce grabada.
class TarjetaPlaca extends StatelessWidget {
  const TarjetaPlaca({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l = imperio.logros.where((x) => x.id == id).firstOrNull;
    final nombre = l == null ? tr('Logro del Imperio', 'Empire achievement') : nombreLogro(l);
    final desc = l == null ? tr('Desbloqueado en el Imperio', 'Unlocked in the Empire') : tr(l.descEs, l.descEn);
    const grabado = Color(0xFF3A2A08);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: _madera, border: Border.all(color: _tinta), borderRadius: BorderRadius.circular(radio)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Emoji('🏆', tamano: 54),
        Container(width: 56, height: 8, color: _tinta),
        Container(width: 76, height: 10, color: const Color(0xFF0E0B08)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: _bronce, border: Border.all(color: _bronceOscuro, width: 2)),
          child: Stack(fit: StackFit.passthrough, children: [
            for (final a in const [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
              Positioned.fill(
                child: Align(
                  alignment: a,
                  child: Container(width: 5, height: 5, margin: const EdgeInsets.all(4), color: _bronceOscuro),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(children: [
                Text(tr('IMPERIO DEL TRONO', 'EMPIRE OF THE THRONE'),
                    style: const TextStyle(fontFamily: _serif, fontSize: 9, letterSpacing: 3, color: _bronceOscuro, fontWeight: FontWeight.w700)),
                Container(height: 1, width: 60, color: _bronceOscuro, margin: const EdgeInsets.symmetric(vertical: 4)),
                Text(nombre.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: _serif, fontSize: 18, fontWeight: FontWeight.w900, color: grabado, height: 1.1, letterSpacing: .5)),
                const SizedBox(height: 4),
                Text(desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: _serif, fontStyle: FontStyle.italic, fontSize: 12, color: grabado, height: 1.2)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────────── JALADA: medidor de agua ─────────────────────────────

const _pizarra = Color(0xFF263238);

/// 1ST, 2ND, 3RD, 4TH, 11TH, 21ST...
String _ordinal(int v) {
  final sufijo = (v % 100 >= 11 && v % 100 <= 13) ? 'TH' : switch (v % 10) { 1 => 'ST', 2 => 'ND', 3 => 'RD', _ => 'TH' };
  return '$v$sufijo';
}

/// Jalada de la cadena: el medidor de agua del baño, con su contador de rueditas.
class TarjetaContador extends StatelessWidget {
  const TarjetaContador({super.key, required this.n, required this.rollos});

  final int n;
  final double rollos;

  @override
  Widget build(BuildContext context) {
    final cifras = '$n'.padLeft(5, '0').split('');
    const gris = Color(0xFF90A4AE);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: _pizarra, border: Border.all(color: _tinta), borderRadius: BorderRadius.circular(radio)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Emoji('💧', tamano: 16),
          const SizedBox(width: 6),
          Text(tr('MEDIDOR DE JALADAS', 'FLUSH METER'),
              style: const TextStyle(fontFamily: _mono, color: Colors.white, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const Spacer(),
          const Emoji('🚽', tamano: 22),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFF11181C), border: Border.all(color: gris)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < cifras.length; i++)
              Container(
                width: 32,
                height: 42,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.center,
                color: i == cifras.length - 1 ? const Color(0xFFB71C1C) : const Color(0xFF000000),
                child: Text(cifras[i], style: const TextStyle(fontFamily: _mono, color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Text(tr('$nª JALADA DE LA CADENA', '${_ordinal(n)} FLUSH OF THE CHAIN'),
            textAlign: TextAlign.center, style: const TextStyle(fontFamily: _mono, color: gris, fontSize: 10, letterSpacing: 2)),
        Container(height: 1, color: gris.withValues(alpha: .4), margin: const EdgeInsets.symmetric(vertical: 8)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Emoji('🧻', tamano: 22),
          const SizedBox(width: 8),
          Text('+${formatoMj(rollos, ingles: enIngles)}',
              style: TextStyle(color: acento, fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(width: 6),
          Text(tr('Rollos de Oro', 'Golden Rolls'), style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      ]),
    );
  }
}

// ───────────────────────────── LOGRO SECRETO: expediente desclasificado ─────────────────────────────

const _manila = Color(0xFFE6C88E);
const _manilaOscuro = Color(0xFF6B4F1D);

/// El contenido del toast de logro secreto: un expediente que acaban de desclasificar,
/// con renglones tachados de negro. Va dentro de un SnackBar con fondo [colorExpediente].
const colorExpediente = _manila;
const bordeExpediente = _manilaOscuro;

class AvisoExpediente extends StatelessWidget {
  const AvisoExpediente({super.key, required this.emoji, required this.nombre});

  final String emoji;
  final String nombre;

  @override
  Widget build(BuildContext context) {
    const rojo = Color(0xFFB3261E);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Emoji('🔒', tamano: 14),
        const SizedBox(width: 6),
        Text(tr('EXPEDIENTE', 'FILE'),
            style: const TextStyle(fontFamily: _mono, fontSize: 10, color: _manilaOscuro, letterSpacing: 2, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(tr('ALTO SECRETO', 'TOP SECRET'),
            style: const TextStyle(
                fontFamily: _mono, fontSize: 10, color: rojo, decoration: TextDecoration.lineThrough, decorationColor: rojo, decorationThickness: 2)),
        const SizedBox(width: 6),
        Text(tr('DESCLASIFICADO', 'DECLASSIFIED'),
            style: const TextStyle(fontFamily: _mono, fontSize: 10, color: rojo, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFF5E6C4), border: Border.all(color: _manilaOscuro)),
          child: Emoji(emoji, tamano: 30),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('LOGRO SECRETO', 'SECRET ACHIEVEMENT'),
                style: const TextStyle(fontFamily: _mono, fontSize: 10, color: _manilaOscuro, letterSpacing: 1.5)),
            Text(nombre, style: const TextStyle(color: _tinta, fontWeight: FontWeight.w900, fontSize: 16, height: 1.15)),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(flex: 5, child: Container(height: 7, color: _tinta)),
              const SizedBox(width: 5),
              Expanded(flex: 2, child: Container(height: 7, color: _tinta)),
              const SizedBox(width: 5),
              Expanded(flex: 3, child: Container(height: 7, color: _tinta)),
            ]),
          ]),
        ),
      ]),
    ]);
  }
}
