// Tienda de estilo del Imperio: temas de la interfaz, efectos del botón CAGUÉ y movimientos del avatar. Dart puro.
// Son solo cosméticos: no cambian la producción. Se compran una vez y se quedan para siempre (jalar la cadena y los
// reinicios no los borran): la compra vive en la base (tabla `imperio_estilos`, RPC `imperio_estilo_comprar`).
//
// Agregar un estilo = una fila aquí y una en `imperio_estilos_catalogo` de la base (mismo id, tipo y precios).
// test/imperio_estilos_test.dart revisa que las dos listas coincidan.

/// Qué parte de la app cambia.
enum TipoEstilo { tema, efecto, movimiento }

/// Un estilo comprable. Los precios se suman: [mj] se gasta del saldo, [rollos] se gastan (bajan el +% como los
/// objetos de Rollos) y [cagadas] es un mínimo de cagadas reales que no se gasta. Todo en 0 = gratis.
class Estilo {
  final String id;
  final TipoEstilo tipo;
  final String emoji;
  final String nombreEs, nombreEn;
  final double mj;
  final int rollos;
  final int cagadas;

  const Estilo(this.id, this.tipo, this.emoji, this.nombreEs, this.nombreEn, {this.mj = 0, this.rollos = 0, this.cagadas = 0});

  bool get gratis => mj <= 0 && rollos <= 0 && cagadas <= 0;
}

/// El tema y el efecto que vienen de fábrica (gratis, siempre tuyos).
const temaClasico = 'tema_clasico';
const efectoNinguno = 'efecto_ninguno';
const movimientoNinguno = 'mov_ninguno';

const List<Estilo> estilos = [
  // Temas de la interfaz (los colores van en lib/tema.dart).
  Estilo(temaClasico, TipoEstilo.tema, '💛', 'Clásico', 'Classic'),
  Estilo('tema_porcelana', TipoEstilo.tema, '🚽', 'Porcelana', 'Porcelain', mj: 1e5),
  Estilo('tema_cloaca', TipoEstilo.tema, '🧪', 'Cloaca', 'Sewer', mj: 1e6),
  Estilo('tema_papel', TipoEstilo.tema, '🧻', 'Papel higiénico', 'Toilet paper', mj: 1e7),
  Estilo('tema_gameboy', TipoEstilo.tema, '🎮', 'GameBoy', 'GameBoy', mj: 1e8),
  Estilo('tema_neon', TipoEstilo.tema, '🪩', 'Neón de discoteca', 'Disco neon', mj: 1e9),
  Estilo('tema_marmol', TipoEstilo.tema, '🏛️', 'Mármol de palacio', 'Palace marble', rollos: 2, cagadas: 150),
  Estilo('tema_oro', TipoEstilo.tema, '👑', 'Oro macizo', 'Solid gold', rollos: 10),
  // Efectos al apretar CAGUÉ (solo los ves tú).
  Estilo(efectoNinguno, TipoEstilo.efecto, '💩', 'Sin efecto', 'No effect'),
  Estilo('efecto_confeti', TipoEstilo.efecto, '🎊', 'Confeti', 'Confetti', mj: 1e5),
  Estilo('efecto_papel', TipoEstilo.efecto, '🧻', 'Explosión de papel', 'Paper burst', mj: 1e6),
  Estilo('efecto_rayo', TipoEstilo.efecto, '⚡', 'Rayo', 'Lightning', mj: 1e7),
  Estilo('efecto_remolino', TipoEstilo.efecto, '🌀', 'Remolino', 'Whirlpool', mj: 1e8),
  Estilo('efecto_fuegos', TipoEstilo.efecto, '🎆', 'Fuegos artificiales', 'Fireworks', mj: 1e9),
  // Movimientos del avatar (los ven todos: perfil, ranking, chat).
  Estilo(movimientoNinguno, TipoEstilo.movimiento, '🧍', 'Quieto', 'Still'),
  Estilo('mov_respirar', TipoEstilo.movimiento, '😮‍💨', 'Respirar', 'Breathe', mj: 5e4),
  Estilo('mov_rebotar', TipoEstilo.movimiento, '⬆️', 'Rebotar', 'Bounce', mj: 5e5),
  Estilo('mov_saludar', TipoEstilo.movimiento, '👋', 'Saludar', 'Wave', mj: 5e6),
  Estilo('mov_temblar', TipoEstilo.movimiento, '😣', 'Temblor de pujo', 'Push shake', mj: 5e7),
  Estilo('mov_girar', TipoEstilo.movimiento, '🔄', 'Girar', 'Spin', mj: 5e8),
  Estilo('mov_flotar', TipoEstilo.movimiento, '🎈', 'Flotar', 'Float', mj: 5e9),
  Estilo('mov_bailar', TipoEstilo.movimiento, '🕺', 'Bailar', 'Dance', mj: 5e10),
  Estilo('mov_brillo', TipoEstilo.movimiento, '✨', 'Brillo de rey', 'Royal glow', rollos: 3),
];

final Map<String, Estilo> _estiloPorId = {for (final e in estilos) e.id: e};

/// Estilo por id, o null.
Estilo? estiloPorId(String id) => _estiloPorId[id];

/// Los de un tipo, en el orden del catálogo.
List<Estilo> estilosDe(TipoEstilo tipo) => [for (final e in estilos) if (e.tipo == tipo) e];

/// Los gratis se tienen siempre; los de pago, si se compraron. Un id que no está en el catálogo, nunca.
bool tieneEstilo(Set<String> comprados, String id) {
  final e = estiloPorId(id);
  return e != null && (e.gratis || comprados.contains(id));
}
