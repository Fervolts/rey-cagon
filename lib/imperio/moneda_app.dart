import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../idioma.dart';
import 'formato.dart';

Moneda? _cache;
bool? _cacheIngles;

/// Moneda según el idioma de la app y el país del teléfono. Se guarda hasta que cambie el idioma.
Moneda monedaActual() {
  final ingles = enIngles;
  if (_cache == null || _cacheIngles != ingles) {
    _cache = monedaPara(PlatformDispatcher.instance.locale.countryCode, ingles: ingles);
    _cacheIngles = ingles;
  }
  return _cache!;
}

/// Icono de la moneda del Imperio (billete con mojón). Va al lado de los montos en vez de la abreviatura.
/// [tamano] es el ancho; el billete es apaisado (alto = 0,62 del ancho).
class IconoMoneda extends StatelessWidget {
  const IconoMoneda({super.key, this.tamano = 16});

  final double tamano;

  static const altoBillete = .62;

  @override
  Widget build(BuildContext context) => Image.asset('assets/img/billete.png',
      width: tamano, height: tamano * altoBillete, filterQuality: FilterQuality.medium, semanticLabel: monedaActual().nombre);
}

/// Monto con el icono de la moneda al lado, en una sola línea: si no cabe, se encoge.
Widget montoMj(String numero, TextStyle estilo, {Alignment alineacion = Alignment.centerLeft}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alineacion,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(numero, maxLines: 1, softWrap: false, style: estilo),
        SizedBox(width: (estilo.fontSize ?? 14) * .25),
        IconoMoneda(tamano: (estilo.fontSize ?? 14) * 1.5),
      ]),
    );
