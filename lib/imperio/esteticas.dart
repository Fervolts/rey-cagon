// Estéticas premium del baño: se compran solo con Ciruelas y lo único que hacen es subir la suerte de
// las Ciruelas (al pujar y al cagar de verdad). Dart puro.
//
// Agregar una estética = una fila aquí y una en la tabla `imperio_esteticas` de la base (mismo id,
// precio y bono). test/imperio_ciruelas_test.dart revisa que las dos listas coincidan.

/// Una estética comprable.
class Estetica {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;

  /// Precio en Ciruelas.
  final int precio;

  /// Bono de suerte: 0.04 = +4%.
  final double bono;

  const Estetica(this.id, this.emoji, this.nombreEs, this.nombreEn, this.precio, this.bono);
}

const List<Estetica> esteticas = [
  Estetica('est_tobo', '🪣', 'Tobo dorado', 'Golden bucket', 50, 0.04),
  Estetica('est_papel', '🧻', 'Porta-rollo de oro', 'Gold roll holder', 75, 0.04),
  Estetica('est_lavamanos', '🚰', 'Lavamanos de mármol', 'Marble sink', 75, 0.05),
  Estetica('est_espejo', '🪞', 'Espejo con luces', 'Hollywood mirror', 100, 0.05),
  Estetica('est_repisa', '🫙', 'Repisa de cristal', 'Glass shelf', 100, 0.05),
  Estetica('est_cortina', '✨', 'Cortina de terciopelo', 'Velvet curtain', 150, 0.05),
  Estetica('est_ventana', '🎨', 'Vitral de colores', 'Stained glass window', 200, 0.06),
  Estetica('est_alfombra', '🟫', 'Alfombra roja', 'Red carpet', 250, 0.06),
  Estetica('est_lampara', '💡', 'Lámpara de araña', 'Chandelier', 300, 0.07),
  Estetica('est_piso', '💎', 'Piso de mármol', 'Marble floor', 400, 0.08),
];

final Map<String, Estetica> _esteticaPorId = {for (final e in esteticas) e.id: e};

/// Estética por id, o null.
Estetica? esteticaPorId(String id) => _esteticaPorId[id];

/// Probabilidad base de una Ciruela por pujo (la tira la app; el servidor pone el tope diario).
const double probCiruelaPujoBase = 1 / 1500;

/// Probabilidad base de una Ciruela por cagada real (la tira el servidor en `imperio_cargar`).
const double probCiruelaCagadaBase = 0.05;

/// Suma de los bonos de las estéticas compradas (ids desconocidos no cuentan).
double bonoSuerteDe(Iterable<String> compradas) {
  var s = 0.0;
  for (final id in compradas.toSet()) {
    s += esteticaPorId(id)?.bono ?? 0;
  }
  return s;
}

/// prob = base x (1 + suma de bonos).
double probConBono(double base, Iterable<String> compradas) => base * (1 + bonoSuerteDe(compradas));

/// Ciruelas por suerte de pujo que acepta el servidor al día: 3 + la mitad de las estéticas (hacia abajo).
int topeSuertePujo(int nEsteticas) => 3 + nEsteticas ~/ 2;
