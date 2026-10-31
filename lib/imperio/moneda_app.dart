import 'dart:ui';

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
