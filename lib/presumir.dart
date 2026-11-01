import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'chat.dart' show nombreSala;
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'imperio/catalogo.dart' as imperio show logros;
import 'imperio/formato.dart' show formatoMj;
import 'peso.dart';
import 'racha.dart';
import 'tema.dart';
import 'tipos.dart';

/// Las tarjetas de presumir del chat, cada una con su objeto: el hito es un periódico, el
/// desbloqueo una vitrina con etiqueta de precio, la cagada una muestra de laboratorio, la racha
/// una hoja de calendario, el logro del Imperio una placa con trofeo y la jalada un medidor.
/// Son objetos físicos: mismos colores en tema claro y oscuro. La cartera va aparte (tarjeta_cartera.dart).

const _tinta = Color(0xFF171513);
const _serif = 'serif';
const _mono = 'monospace';

/// La tarjeta propia de [t] o null si el tipo no es de aquí.
Widget? tarjetaPresumir(Map<String, dynamic> t) {
  int entero(Object? v) => v is num ? v.toInt() : 0;
  return switch (t['tipo']) {
    'hito' => TarjetaTitular(n: entero(t['n']), reina: t['reina'] == true),
    'desbloqueo' => TarjetaVitrina.de('${t['emoji']}', minimo: t['minimo'] is num ? entero(t['minimo']) : null),
    'cagada' => TarjetaMuestra(n: entero(t['n']), mojon: t['mojon'] as int?, peso: t['peso'] as int?),
    'racha' => TarjetaCalendario(n: entero(t['n'])),
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
                    style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
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
                style: const TextStyle(fontFamily: _mono, color: acento, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
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
            Text(tr('PRECIO', 'PRICE'), style: const TextStyle(fontFamily: _mono, fontSize: 8, color: acentoTexto, letterSpacing: 1)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$minimo', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: acentoTexto, height: 1)),
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
              Text(d.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: acentoTexto)),
              Text(tr('${d.minimo} cagadas', '${d.minimo} poops'),
                  style: const TextStyle(fontFamily: _mono, fontSize: 10, color: acentoTexto)),
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
                style: const TextStyle(fontFamily: _mono, color: acento, fontWeight: FontWeight.w700, fontSize: 11)),
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

// ───────────────────────────── RACHA: hoja de calendario ─────────────────────────────

const _rojoCalendario = Color(0xFFD7263D);
const _papelCalendario = Color(0xFFFFFDF8);

/// Racha del día: la hoja del calendario de hoy, con las rayitas contadas y fuego abajo.
class TarjetaCalendario extends StatelessWidget {
  const TarjetaCalendario({super.key, required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    final colores = estiloRacha(n).$1;
    return Container(
      decoration: BoxDecoration(color: _papelCalendario, border: Border.all(color: _tinta), borderRadius: BorderRadius.circular(radio)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const _Anillas(),
        Container(
          color: _rojoCalendario,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(tr('HOY', 'TODAY'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 6, fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(children: [
            Text('$n', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: _rojoCalendario, height: 1)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('CAGADAS EN UN DÍA', 'POOPS IN ONE DAY'),
                    style: const TextStyle(color: _tinta, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 4),
                Container(
                  color: _tinta,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: ShaderMask(
                    shaderCallback: (r) => LinearGradient(colors: colores).createShader(r),
                    child: Text(nombreRacha(n) ?? '',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(height: 20, width: double.infinity, child: CustomPaint(painter: _Rayitas(n))),
              ]),
            ),
          ]),
        ),
        Container(
          color: const Color(0xFF2A0D05),
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < 7; i++) Emoji(i.isEven ? '🔥' : estiloRacha(n).$2, tamano: i.isEven ? 18 : 14),
          ]),
        ),
      ]),
    );
  }
}

/// El lomo con las anillas del calendario.
class _Anillas extends StatelessWidget {
  const _Anillas({this.alto = 12});

  final double alto;

  @override
  Widget build(BuildContext context) => Container(
        height: alto,
        color: _tinta,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < 8; i++) Container(width: alto * .5, height: alto * .5, color: const Color(0xFF9A968C)),
        ]),
      );
}

/// Las rayitas del preso, de cinco en cinco (la quinta cruza).
class _Rayitas extends CustomPainter {
  const _Rayitas(this.n, {this.centrado = false});

  final int n;
  final bool centrado;

  @override
  void paint(Canvas canvas, Size size) {
    final lapiz = Paint()
      ..color = _tinta
      ..strokeWidth = size.height / 9
      ..strokeCap = StrokeCap.square;
    final paso = size.height * .3;
    var x = 0.0;
    if (centrado) {
      // Ancho de las rayitas dibujadas, del primer palo al último.
      final grupos = (n + 4) ~/ 5;
      final ultimo = n - (grupos - 1) * 5;
      final ancho = (grupos - 1) * paso * 5.4 + (math.min(4, ultimo) - 1) * paso;
      x = math.max(0, (size.width - ancho) / 2);
    }
    for (var g = 0; g * 5 < n; g++) {
      final enGrupo = math.min(5, n - g * 5);
      final inicio = x;
      for (var i = 0; i < math.min(4, enGrupo); i++) {
        canvas.drawLine(Offset(x, size.height * .1), Offset(x, size.height * .9), lapiz);
        x += paso;
      }
      if (enGrupo == 5) canvas.drawLine(Offset(inicio - paso * .4, size.height * .8), Offset(x - paso * .6, size.height * .2), lapiz);
      x += paso * 1.4;
      if (x > size.width) break;
    }
  }

  @override
  bool shouldRepaint(covariant _Rayitas old) => old.n != n || old.centrado != centrado;
}

/// La imagen 9:16 de la racha para historias: hoja grande del calendario con fuego.
/// Los tamaños los fija quien la usa (racha.dart).
class HistoriaCalendario extends StatelessWidget {
  const HistoriaCalendario({super.key, required this.n, this.foto, this.letrero, this.usuario, this.lugar});

  final int n;

  /// El nombre de la racha con su letrero de juego (racha.dart); sin él, texto con degradado.
  final Widget? letrero;

  /// El avatar del usuario (o un mojón).
  final Widget? foto;
  final String? usuario;
  final String? lugar;

  @override
  Widget build(BuildContext context) {
    final (colores, emojiNivel) = estiloRacha(n);
    const blanco = Colors.white;
    return ColoredBox(
      color: const Color(0xFF1A0703),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: acento,
          child: Text(tr('REY CAGÓN', 'KING OF THE THRONE'),
              style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 14)),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 26),
            decoration: BoxDecoration(color: _papelCalendario, border: Border.all(color: _tinta, width: 2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _Anillas(alto: 18),
              Container(
                color: _rojoCalendario,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('HOY', 'TODAY'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: blanco, fontWeight: FontWeight.w900, letterSpacing: 10, fontSize: 20)),
              ),
              const SizedBox(height: 10),
              Center(child: SizedBox(width: 80, height: 80, child: FittedBox(child: foto ?? const Emoji('💩', tamano: 80)))),
              Text('$n', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 100, fontWeight: FontWeight.w900, color: _rojoCalendario, height: 1)),
              Text(tr('CAGADAS EN UN DÍA', 'POOPS IN ONE DAY'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _tinta, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                color: _tinta,
                height: 54,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: FittedBox(
                  child: letrero ??
                      ShaderMask(
                        shaderCallback: (r) => LinearGradient(colors: colores).createShader(r),
                        child: Text(' ${nombreRacha(n) ?? ''} ',
                            style: const TextStyle(color: blanco, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 34)),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: SizedBox(width: 160, height: 30, child: CustomPaint(painter: _Rayitas(n, centrado: true)))),
              const Spacer(),
              if (usuario != null)
                Text('@$usuario',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _tinta, fontWeight: FontWeight.w900, fontSize: 20)),
              if (lugar != null)
                Text(lugar!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B6559), fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                color: const Color(0xFF2A0D05),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (var i = 0; i < 7; i++) Emoji(i.isEven ? '🔥' : emojiNivel, tamano: i.isEven ? 26 : 18),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 20),
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
    final nombre = l == null ? tr('Logro del Imperio', 'Empire achievement') : tr(l.nombreEs, l.nombreEn);
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
              style: const TextStyle(color: acento, fontWeight: FontWeight.w900, fontSize: 22)),
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
