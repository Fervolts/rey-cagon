import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'animaciones.dart';

/// Lado más largo de la imagen que se comparte. 1920 alcanza para una historia de Instagram.
const _ladoMaximo = 1920.0;

/// Captura el RepaintBoundary de [boundary] y lo comparte fuera de la app con [texto].
///
/// Pensado para gastar poca memoria: mientras el usuario está en WhatsApp o en el editor
/// de historias de Instagram, Android mata primero a la app que más RAM ocupa en segundo
/// plano, y al volver arranca de cero (eso se ve como "la app se cerró").
/// - pixelRatio con tope: el lado largo no pasa de 1920 px, y en teléfonos con poca RAM
///   (los mismos que usan animaciones simples) no pasa de 2x.
/// - La imagen de la GPU se libera apenas se codifica el PNG.
/// - El PNG va a un archivo temporal y se comparte por ruta (no se manda el PNG entero
///   por el canal de plataforma como con XFile.fromData).
///
/// Devuelve false si no se pudo capturar o compartir; true si se abrió el selector.
Future<bool> compartirImagen(BuildContext context, GlobalKey boundary,
    {required String nombre, required String texto, double pixelRatio = 3}) async {
  try {
    // Que el último frame esté pintado antes de capturar (con tope: si no llega frame, se sigue igual).
    await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 300), onTimeout: () {});
    final caja = boundary.currentContext?.findRenderObject();
    if (caja is! RenderRepaintBoundary || !caja.hasSize) return false;
    var ratio = pixelRatio;
    if (movimientoDelTelefono == Movimiento.simple) ratio = math.min(ratio, 2);
    final lado = math.max(caja.size.width, caja.size.height);
    if (lado > 0) ratio = math.min(ratio, _ladoMaximo / lado);

    final imagen = await caja.toImage(pixelRatio: ratio);
    ByteData? datos;
    try {
      datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      imagen.dispose();
    }
    if (datos == null) return false;

    // Fuera de cacheDir/share_plus: share_plus rechaza archivos dentro de su propia carpeta.
    final carpeta = Directory('${Directory.systemTemp.path}/compartir');
    await carpeta.create(recursive: true);
    final archivo = File('${carpeta.path}/$nombre');
    await archivo.writeAsBytes(datos.buffer.asUint8List(), flush: true);
    datos = null;

    final r = await SharePlus.instance.share(ShareParams(
      files: [XFile(archivo.path, mimeType: 'image/png', name: nombre)],
      text: texto,
    ));
    return r.status != ShareResultStatus.unavailable;
  } catch (_) {
    return false;
  }
}
