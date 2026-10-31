// Formato de números y nombre de la moneda del Imperio. Dart puro (sin Flutter) para poder probarlo.

/// Moneda que se muestra. Internamente siempre es la misma (`mj`): solo cambia el nombre.
class Moneda {
  const Moneda(this.nombre, this.abreviatura);

  final String nombre;
  final String abreviatura;
}

const _monedaIngles = Moneda('Poopbucks', 'PB');
const _monedaDefecto = Moneda('Mojonólares', 'Mj\$');

const _porPais = {
  'VE': Moneda('Mojolívares', 'MjBs'),
  'CO': Moneda('Mojopesos', 'Mj\$'),
  'MX': Moneda('Mojopesos', 'Mj\$'),
  'AR': Moneda('Mojopesos', 'Mj\$'),
  'CL': Moneda('Mojopesos', 'Mj\$'),
  'UY': Moneda('Mojopesos', 'Mj\$'),
  'DO': Moneda('Mojopesos', 'Mj\$'),
  'CU': Moneda('Mojopesos', 'Mj\$'),
  'PE': Moneda('Mojosoles', 'MjS/'),
  'GT': Moneda('Mojetzales', 'MjQ'),
  'PY': Moneda('Mojoraníes', 'MjG'),
  'BO': Moneda('Mojobolivianos', 'MjBs'),
  'CR': Moneda('Mojolones', 'Mj₡'),
  'SV': Moneda('Mojolones', 'Mj₡'),
  'HN': Moneda('Mojempiras', 'MjL'),
  'NI': Moneda('Mojórdobas', 'MjC\$'),
};

const _zonaEuro = {
  'ES', 'AD', 'AT', 'BE', 'HR', 'CY', 'EE', 'FI', 'FR', 'DE', 'GR', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'MC', 'ME', 'NL', 'PT', 'SM', 'SK', 'SI',
  'VA', 'BG',
};

const _monedaEuro = Moneda('Mojeuros', 'Mj€');

/// Moneda para el [pais] (código ISO de 2 letras, mayúsculas o minúsculas, puede ser null).
/// En inglés siempre Poopbucks. País desconocido en español: Mojonólares.
Moneda monedaPara(String? pais, {required bool ingles}) {
  if (ingles) return _monedaIngles;
  final p = pais?.toUpperCase();
  if (p == null) return _monedaDefecto;
  if (_zonaEuro.contains(p)) return _monedaEuro;
  return _porPais[p] ?? _monedaDefecto;
}

const _sufijos = ['K', 'M', 'B', 'T', 'Qa', 'Qi'];

String _recortar(String s) {
  if (!s.contains('.')) return s;
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// Número corto: "12,5", "999", "1,23 M", "15 K", "1,23e21". Coma decimal en español, punto en inglés.
String formatoMj(double v, {bool ingles = false}) {
  String fin(String s) => ingles ? s : s.replaceAll('.', ',');
  if (v.isNaN) return '0';
  if (v.isInfinite) return v < 0 ? '-∞' : '∞';
  if (v < 1000) {
    // Menos de 100: un decimal solo si lo tiene. De 100 a 999: entero.
    if (v < 100) return fin(_recortar(v.toStringAsFixed(1)));
    return v.round().toString();
  }
  var exp = 0;
  var x = v;
  while (x >= 1000 && exp < _sufijos.length) {
    x /= 1000;
    exp++;
  }
  if (x >= 1000) {
    // Más allá de Qi: notación científica.
    final cientifico = v.toStringAsExponential(2).split('e');
    final mant = _recortar(cientifico[0]);
    return fin('${mant}e${int.parse(cientifico[1])}');
  }
  var t = _recortar(x.toStringAsFixed(2));
  // 999,999 K redondea a 1000: sube de sufijo.
  if (t == '1000' && exp < _sufijos.length) {
    t = '1';
    exp++;
    if (exp > _sufijos.length) return fin('1e${(exp * 3)}');
  }
  return fin('$t ${_sufijos[exp - 1]}');
}
