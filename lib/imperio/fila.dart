import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'formato.dart';

/// Una línea de texto que nunca se parte: si no cabe, se encoge.
Widget textoEnUnaLinea(String texto, TextStyle estilo, {Alignment alineacion = Alignment.centerLeft, TextAlign? align}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alineacion,
      child: Text(texto, maxLines: 1, softWrap: false, textAlign: align, style: estilo),
    );

/// Fila de la lista del Imperio (edificio, poceta o candado): emoji, título y detalle, precio a la derecha,
/// cantidad y un extra (la ▼ de mejoras). Los números van siempre en una sola línea: si no caben, se encogen.
class FilaImperio extends StatelessWidget {
  const FilaImperio({
    super.key,
    required this.emoji,
    required this.titulo,
    this.detalle,
    this.derecha,
    this.contador,
    this.extra,
    this.resaltada = false,
    this.apagada = false,
  });

  final String emoji;
  final String titulo;
  final String? detalle;
  final String? derecha;
  final int? contador;
  final Widget? extra;
  final bool resaltada;
  final bool apagada;

  /// Ancho de la columna de la cantidad: cabe "999" o "1,5M" a tamaño 20.
  static const anchoContador = 46.0;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Opacity(
      opacity: apagada ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.tarjeta,
          border: Border.all(color: resaltada ? p.primario : p.borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Row(
          children: [
            Emoji(emoji, tamano: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto), overflow: TextOverflow.ellipsis),
                  if (detalle != null) textoEnUnaLinea(detalle!, numeros(context, tamano: 12, color: p.textoSuave)),
                ],
              ),
            ),
            if (derecha != null) ...[
              const SizedBox(width: 6),
              // El precio puede ser "1,23e21 MjBs": tope de ancho y se encoge antes que partirse.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: textoEnUnaLinea(derecha!, numeros(context, tamano: 13, weight: FontWeight.w800, color: resaltada ? p.texto : p.textoSuave),
                    alineacion: Alignment.centerRight),
              ),
            ],
            if (contador != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: anchoContador,
                child: textoEnUnaLinea(formatoCantidad(contador!, ingles: enIngles), numeros(context, tamano: 20, weight: FontWeight.w900),
                    alineacion: Alignment.centerRight, align: TextAlign.right),
              ),
            ],
            ?extra,
          ],
        ),
      ),
    );
  }
}
