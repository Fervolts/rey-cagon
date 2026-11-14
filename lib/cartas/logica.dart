// Reglas de la colección sin Flutter: niveles, repetidas y logros. Las mismas que aplica el servidor.

/// Nivel más alto: rainbow.
const nivelMax = 5;

/// Repetidas que cuesta subir desde [nivel] al siguiente (de 0 a 1 cuesta 1, de 4 a 5 cuesta 5).
int costoMejora(int nivel) => nivel + 1;

/// Repetidas que todavía se pueden gastar: las copias menos la original menos lo ya gastado.
int repetidasDisponibles(int copias, int gastadas) {
  final r = copias - 1 - gastadas;
  return r < 0 ? 0 : r;
}

/// Si alcanza para subir un nivel.
bool puedeMejorar({required int nivel, required int copias, required int gastadas}) =>
    nivel < nivelMax && repetidasDisponibles(copias, gastadas) >= costoMejora(nivel);

/// Metas de "cartas distintas" para los logros de colección, en orden.
const metasColeccion = [10, 30, 64, 100, 128];

/// Claves de logro que corresponden a la colección: distintas, dorada, rainbow y sobre del rey abierto.
Set<String> logrosDeColeccion({required int distintas, required int nivelMasAlto, bool abrioSobreRey = false}) => {
      for (final m in metasColeccion)
        if (distintas >= m) 'cartas_$m',
      if (nivelMasAlto >= 4) 'carta_dorada',
      if (nivelMasAlto >= nivelMax) 'carta_rainbow',
      if (abrioSobreRey) 'sobre_rey',
    };

/// Cuántas cartas trae cada tipo de sobre.
int cartasDelSobre(String tipo) => switch (tipo) {
      'plata' => 4,
      'oro' || 'rey' => 5,
      _ => 3,
    };

/// Probabilidad de cada rareza (común, rara, épica, legendaria) por tipo de sobre, en porcentaje.
List<int> porcentajesDelSobre(String tipo) => switch (tipo) {
      'plata' => const [40, 38, 18, 4],
      'oro' => const [20, 40, 30, 10],
      'rey' => const [10, 35, 35, 20],
      _ => const [60, 28, 10, 2],
    };

/// Horas que faltan hasta [proximo], redondeadas hacia arriba y nunca menos de 0.
int horasHasta(DateTime proximo, DateTime ahora) {
  final min = proximo.difference(ahora).inMinutes;
  if (min <= 0) return 0;
  return (min + 59) ~/ 60;
}
