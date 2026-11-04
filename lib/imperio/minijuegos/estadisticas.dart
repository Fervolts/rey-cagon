// Lo que el servidor cuenta de los minijuegos (récord y partidas por juego), en un global sin dependencias.
// Los logros de la Sala (lib/imperio/catalogo.dart) lo leen en su condición; lo llena ControlImperio.cargarMinijuegos
// y cada partida guardada. Está aparte de datos.dart para que el catálogo siga siendo puro (sin Supabase).

/// Los tres minijuegos abiertos, en el orden de la Sala.
const List<String> juegosAbiertos = ['tuberia', 'destapa', 'memoria'];

/// Récord y partidas de un juego.
class EstadisticaJuego {
  final int record;
  final int partidas;

  /// Mejor puntaje de esta semana de Caracas (lo que cuenta el ranking).
  final int semana;
  const EstadisticaJuego({this.record = 0, this.partidas = 0, this.semana = 0});

  EstadisticaJuego trasPartida(int puntos) =>
      EstadisticaJuego(record: puntos > record ? puntos : record, partidas: partidas + 1, semana: puntos > semana ? puntos : semana);
}

/// Estadísticas por id de juego. Vacío hasta que el servidor responde (sin red no se gana ningún logro de la Sala).
final Map<String, EstadisticaJuego> estadisticasMinijuegos = {};

int recordMinijuego(String juego) => estadisticasMinijuegos[juego]?.record ?? 0;
int partidasMinijuego(String juego) => estadisticasMinijuegos[juego]?.partidas ?? 0;
