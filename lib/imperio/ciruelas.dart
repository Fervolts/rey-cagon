// Tienda de Ciruelas 🫐: lo que se compra con la moneda premium. Dart puro.
//
// El servidor (`imperio_gastar_ciruelas`) valida el saldo y descuenta; el efecto lo pone la app con
// `Imperio.aplicarOfertaCiruela`. Agregar una oferta = una fila aquí, su precio en la función SQL y su
// efecto en el motor.

/// Algo que se compra con Ciruelas.
class OfertaCiruela {
  final String id;
  final String emoji;
  final String nombreEs, nombreEn;
  final String descEs, descEn;

  /// Precio en Ciruelas (el mismo que en `imperio_gastar_ciruelas`).
  final int precio;

  const OfertaCiruela(this.id, this.emoji, this.nombreEs, this.nombreEn, this.descEs, this.descEn, this.precio);
}

const List<OfertaCiruela> ofertasCiruela = [
  OfertaCiruela('cagada_fresca', '💩', 'Cagada fresca', 'Fresh dump', 'Producción x2 por 1 h más', 'Production x2 for 1 more hour', 3),
  OfertaCiruela('produccion_2h', '⏰', '2 h de producción', '2 h of production', 'Te las da al instante', 'Get them right now', 5),
  OfertaCiruela('robot_24h', '🤖', 'Robot destapador 24 h', 'Plunger bot 24 h', 'Destapa solo cada Atasco por un día',
      'Unclogs every Clog by itself for a day', 10),
  OfertaCiruela('congelador', '🧊', 'Congelador de racha', 'Streak freezer', 'Si se te pasa un día, la racha sigue (guardas hasta 2)',
      'Miss a day and the streak goes on (keep up to 2)', 5),
];

/// Congeladores 🧊 que se pueden guardar a la vez (el mismo tope que en la base).
const maxCongeladores = 2;

final Map<String, OfertaCiruela> _ofertaPorId = {for (final o in ofertasCiruela) o.id: o};

/// Oferta por id, o null.
OfertaCiruela? ofertaPorId(String id) => _ofertaPorId[id];
