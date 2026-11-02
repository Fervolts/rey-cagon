// Temporadas del Imperio: las enciende el servidor con el flag `temporadas` de `imperio_flags`
// (lista de {id, desde, hasta, x}; desde y hasta en ISO 8601 con zona). El teléfono aplica una temporada solo si el
// flag la trae Y la hora (reloj corregido con el servidor) cae en [desde, hasta). Dart puro para poder probarlo.

/// Día Mundial del Retrete (19 nov, hora de Caracas): producción x3 y el logro `dia_retrete`.
const String temporadaDiaRetrete = 'dia_retrete';

/// Navidad (diciembre, hora de Caracas): el mojón dorado sale como hallaca dorada.
const String temporadaNavidad = 'navidad';

/// Tope del multiplicador que acepta el teléfono (el servidor recorta igual en imperio_guardar).
const double topeMultiplicadorTemporada = 10;

final RegExp _idValido = RegExp(r'^[a-z0-9_]{1,40}$');

class Temporada {
  final String id;

  /// Inicio y fin en ms epoch: activa en [desde, hasta).
  final int desde, hasta;

  /// Multiplica la producción del Imperio mientras dura (1 = solo aspecto).
  final double x;

  const Temporada(this.id, this.desde, this.hasta, [this.x = 1]);

  bool activa(int ahora) => ahora >= desde && ahora < hasta;

  /// Una entrada del flag, o null si viene mal (id raro, fechas sin parsear o al revés). x se recorta a [1, 10].
  static Temporada? desdeJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'], d = _fecha(v['desde']), h = _fecha(v['hasta']), x = v['x'];
    if (id is! String || !_idValido.hasMatch(id) || d == null || h == null || h <= d) return null;
    final n = x is num && x.isFinite ? x.toDouble().clamp(1.0, topeMultiplicadorTemporada).toDouble() : 1.0;
    return Temporada(id, d, h, n);
  }

  static int? _fecha(Object? v) => v is String ? DateTime.tryParse(v)?.millisecondsSinceEpoch : null;

  @override
  bool operator ==(Object other) => other is Temporada && other.id == id && other.desde == desde && other.hasta == hasta && other.x == x;

  @override
  int get hashCode => Object.hash(id, desde, hasta, x);
}

/// Lee el valor del flag `temporadas`. Lo que no sea lista queda en [], las entradas malas se saltan.
List<Temporada> leerTemporadas(Object? valor) {
  if (valor is! List) return const [];
  return [for (final v in valor) ?Temporada.desdeJson(v)];
}

/// Las temporadas activas en [ahora].
Iterable<Temporada> temporadasActivas(List<Temporada> lista, int ahora) => lista.where((t) => t.activa(ahora));

/// Si la temporada [id] está activa en [ahora].
bool temporadaActiva(List<Temporada> lista, String id, int ahora) => lista.any((t) => t.id == id && t.activa(ahora));

/// Multiplicador de producción en [ahora]: el mayor de las activas (si se pisan dos no se multiplican), 1 sin ninguna.
double multiplicadorTemporada(List<Temporada> lista, int ahora) {
  var x = 1.0;
  for (final t in lista) {
    if (t.activa(ahora) && t.x > x) x = t.x;
  }
  return x;
}

/// Multiplicador promedio entre [desde] y [hasta] (ms), pesado por el tiempo de cada tramo. Para lo offline: si
/// estuviste fuera 2 h y 1 h cayó en el x3, da 2. Con el rango vacío da el de [desde].
double multiplicadorEnRango(List<Temporada> lista, int desde, int hasta) {
  if (hasta <= desde) return multiplicadorTemporada(lista, desde);
  final cortes = <int>{desde, hasta};
  for (final t in lista) {
    if (t.desde > desde && t.desde < hasta) cortes.add(t.desde);
    if (t.hasta > desde && t.hasta < hasta) cortes.add(t.hasta);
  }
  final orden = cortes.toList()..sort();
  var suma = 0.0;
  for (var i = 0; i + 1 < orden.length; i++) {
    suma += (orden[i + 1] - orden[i]) * multiplicadorTemporada(lista, orden[i]);
  }
  return suma / (hasta - desde);
}
