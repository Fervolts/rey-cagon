import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'fila.dart' show textoEnUnaLinea;
import 'formato.dart';
import 'moneda_app.dart';

double _num(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : 0;

// Presumir la cartera es un estado de cuenta de banco de mentira: el "Banco del Trono". Aquí van las piezas de
// papel (borde dentado, perforado, guía de puntos, código de barras) que comparten la tarjeta del chat,
// la hoja de opciones y la imagen para historias (cartera.dart).

/// Tinta del papel del banco (casi negro, no puro).
const tintaBanco = Color(0xFF171513);

/// Papel del estado de cuenta en la imagen para historias (crema, como papel térmico viejo).
const papelBanco = Color(0xFFF6F1E4);

/// Cabecera del banco: tinta con letras de acento en claro; acento con letras de tinta en oscuro
/// (en oscuro la tinta se pierde contra el fondo).
(Color fondo, Color letra) cabeceraBanco(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? (acento, acentoTexto) : (tintaBanco, acento);

/// Número de cuenta de mentira: 4 cifras estables sacadas de [semilla] (el id del usuario).
String cuentaDe(String? semilla) {
  var h = 7;
  for (final c in (semilla ?? '').codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return (h % 10000).toString().padLeft(4, '0');
}

/// Número de cuenta enmascarado como en el banco: "**** **** 4821".
String cuentaEnmascarada(String cuatro) => '**** **** $cuatro';

/// Papel con el borde de abajo (y opcionalmente el de arriba) dentado, como un recibo arrancado.
class PapelDentado extends StatelessWidget {
  const PapelDentado({super.key, required this.color, required this.child, this.borde, this.arriba = false, this.diente = 10});

  final Color color;
  final Color? borde;
  final bool arriba;
  final double diente;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final alto = diente / 2;
    return CustomPaint(
      painter: _Dentado(color, borde, arriba, diente),
      child: Padding(padding: EdgeInsets.only(top: arriba ? alto : 0, bottom: alto), child: child),
    );
  }
}

class _Dentado extends CustomPainter {
  _Dentado(this.color, this.borde, this.arriba, this.diente);

  final Color color;
  final Color? borde;
  final bool arriba;
  final double diente;

  @override
  void paint(Canvas canvas, Size s) {
    final alto = diente / 2;
    final n = (s.width / diente).round().clamp(1, 1000);
    final paso = s.width / n;
    final camino = Path();
    if (arriba) {
      camino.moveTo(0, alto);
      for (var i = 0; i < n; i++) {
        camino.lineTo(i * paso + paso / 2, 0);
        camino.lineTo((i + 1) * paso, alto);
      }
    } else {
      camino.moveTo(0, 0);
      camino.lineTo(s.width, 0);
    }
    camino.lineTo(s.width, s.height - alto);
    for (var i = n; i > 0; i--) {
      camino.lineTo(i * paso - paso / 2, s.height);
      camino.lineTo((i - 1) * paso, s.height - alto);
    }
    camino.close();
    canvas.drawPath(camino, Paint()..color = color);
    if (borde != null) {
      canvas.drawPath(camino, Paint()
        ..color = borde!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_Dentado o) => o.color != color || o.borde != borde || o.arriba != arriba || o.diente != diente;
}

/// Línea perforada (rayitas), horizontal o vertical. Ocupa todo el ancho (o alto) que le den.
class LineaPerforada extends StatelessWidget {
  const LineaPerforada({super.key, required this.color, this.vertical = false});

  final Color color;
  final bool vertical;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: vertical ? const Size(1, double.infinity) : const Size(double.infinity, 1),
        painter: _Rayitas(color, vertical),
      );
}

class _Rayitas extends CustomPainter {
  _Rayitas(this.color, this.vertical);

  final Color color;
  final bool vertical;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    final largo = vertical ? s.height : s.width;
    for (var x = 0.0; x < largo; x += 7) {
      final fin = (x + 4).clamp(0, largo).toDouble();
      canvas.drawRect(vertical ? Rect.fromLTRB(0, x, 1, fin) : Rect.fromLTRB(x, 0, fin, 1), p);
    }
  }

  @override
  bool shouldRepaint(_Rayitas o) => o.color != color || o.vertical != vertical;
}

class _Guia extends CustomPainter {
  _Guia(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    for (var x = 1.0; x < s.width - 1; x += 3.5) {
      canvas.drawRect(Rect.fromLTWH(x, s.height - 1, 1, 1), p);
    }
  }

  @override
  bool shouldRepaint(_Guia o) => o.color != color;
}

/// Renglón del estado de cuenta: concepto a la izquierda, puntos guía y el monto a la derecha.
/// El monto nunca se parte: si no cabe, se encoge. El concepto se corta con "…".
class RenglonBanco extends StatelessWidget {
  const RenglonBanco(this.concepto, this.valor, {super.key, required this.estiloConcepto, required this.estiloValor, this.emoji, this.valorWidget});

  final String concepto;
  final String valor;
  final TextStyle estiloConcepto, estiloValor;
  final String? emoji;

  /// En vez de [valor] como texto (por ejemplo un monto con el billete).
  final Widget? valorWidget;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final tamano = (estiloConcepto.fontSize ?? 12) + 3;
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (emoji != null) ...[Emoji(emoji!, tamano: tamano), const SizedBox(width: 4)],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * .5 - (emoji == null ? 0 : tamano + 4)),
            child: Text(concepto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloConcepto),
          ),
          Expanded(child: SizedBox(height: 10, child: CustomPaint(painter: _Guia((estiloConcepto.color ?? tintaBanco).withValues(alpha: .45))))),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * .44),
            child: valorWidget ?? textoEnUnaLinea(valor, estiloValor, alineacion: Alignment.centerRight),
          ),
        ]);
      });
}

/// Código de barras de adorno. Las barras salen de [semilla]: el mismo número da siempre el mismo código.
class CodigoBarras extends StatelessWidget {
  const CodigoBarras({super.key, required this.semilla, required this.color, this.alto = 40});

  final int semilla;
  final Color color;
  final double alto;

  @override
  Widget build(BuildContext context) => SizedBox(height: alto, width: double.infinity, child: CustomPaint(painter: _Barras(semilla, color)));
}

class _Barras extends CustomPainter {
  _Barras(this.semilla, this.color);

  final int semilla;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color;
    var r = (semilla & 0x7fffffff) | 1;
    int siguiente(int n) {
      r = (r * 1103515245 + 12345) & 0x7fffffff;
      return r % n;
    }

    const u = 1.2;
    var x = 0.0;
    while (true) {
      final barra = (1 + siguiente(3)) * u;
      if (x + barra > s.width) break;
      canvas.drawRect(Rect.fromLTWH(x, 0, barra, s.height), p);
      x += barra + (1 + siguiente(2)) * u;
    }
  }

  @override
  bool shouldRepaint(_Barras o) => o.semilla != semilla || o.color != color;
}

/// La tarjeta "estado de cuenta" del chat. Los números los pone el servidor (`validar_mensaje`, rama 'cartera')
/// desde la fila `imperio` del usuario: saldo, mps, pujo, mj_total, jaladas y rollos.
/// Ningún número se parte: si no cabe, se encoge.
class TarjetaCartera extends StatelessWidget {
  const TarjetaCartera(this.t, {super.key});

  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final (fondoCab, letraCab) = cabeceraBanco(context);
    String mj(Object? v) => formatoMj(_num(v), ingles: enIngles);
    final rollos = _num(t['rollos']);
    final jaladas = _num(t['jaladas']);
    final total = _num(t['mj_total']);
    final concepto = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textoSuave, letterSpacing: .5);
    final valor = numeros(context, tamano: 12, weight: FontWeight.w800);
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 10, color: p.textoSuave, letterSpacing: 1);
    Widget renglon(String c, String v, {String? emoji}) =>
        Padding(padding: const EdgeInsets.only(top: 3), child: RenglonBanco(c, v, estiloConcepto: concepto, estiloValor: valor, emoji: emoji));
    return PapelDentado(
      color: p.tarjeta,
      borde: p.bordeFuerte,
      diente: 9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(1, 1, 1, 0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: fondoCab,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(children: [
              const Emoji('🏛️', tamano: 16),
              const SizedBox(width: 6),
              Expanded(
                child: textoEnUnaLinea(tr('BANCO DEL TRONO', 'BANK OF THE THRONE'),
                    TextStyle(color: letraCab, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('ESTADO DE CUENTA', 'ACCOUNT STATEMENT'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13, color: p.texto)),
              textoEnUnaLinea('${tr('CTA.', 'ACCT.')} **** **** ****', mono),
              const SizedBox(height: 6),
              LineaPerforada(color: p.bordeFuerte),
              const SizedBox(height: 3),
              renglon('MJ/S', mj(t['mps'])),
              renglon(tr('MJ/PUJO', 'MJ/TAP'), mj(t['pujo'])),
              if (rollos > 0) renglon(tr('ROLLOS', 'ROLLS'), mj(rollos)),
              if (jaladas > 0) renglon(tr('JALADAS', 'FLUSHES'), formatoCantidad(jaladas.toInt(), ingles: enIngles)),
              if (total > 0) renglon(tr('GANADO', 'EARNED'), mj(total)),
              const SizedBox(height: 7),
              LineaPerforada(color: p.bordeFuerte),
              const SizedBox(height: 6),
              Text(tr('SALDO DISPONIBLE', 'AVAILABLE BALANCE'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: concepto.copyWith(fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  color: acento,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  child: montoMj(mj(t['saldo']), numeros(context, tamano: 22, weight: FontWeight.w900, color: acentoTexto)),
                ),
              ),
              const SizedBox(height: 8),
              CodigoBarras(semilla: _num(t['saldo']).round() ^ _num(t['mj_total']).round(), color: p.texto.withValues(alpha: .8), alto: 18),
            ]),
          ),
        ]),
      ),
    );
  }
}
