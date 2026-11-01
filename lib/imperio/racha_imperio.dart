// Racha del Imperio: 30 días seguidos reclamando un premio. Dart puro.
//
// Un día cuenta con la fecha local del teléfono. Si pasa un día sin reclamar, vuelve al día 1; después
// del 30 también vuelve al 1. Lo del servidor (Ciruelas, Fichas) lo acredita `imperio_reclamar_racha`;
// la producción, los objetos y el logro los pone la app con `Imperio.aplicarPremioRacha`.
// Las Ciruelas y Fichas de esta tabla tienen que ser las mismas que en la función SQL.

/// Premio de un día.
class PremioRacha {
  /// Minutos de producción actual (sin efectos), como los precios de objetos.
  final int minutos;
  final int ciruelas;

  /// Una Ficha (si tienes 5, el servidor la cambia por 2 Ciruelas).
  final bool ficha;

  /// Objetos: id del catálogo → cantidad. El Robot se activa con su duración normal.
  final Map<String, int> objetos;

  /// Logro que se gana ese día.
  final String? logro;

  const PremioRacha({this.minutos = 0, this.ciruelas = 0, this.ficha = false, this.objetos = const {}, this.logro});
}

/// Días de la racha (ciclo).
const int diasRacha = 30;

/// Premios del día 1 al 30 (índice 0 = día 1).
const List<PremioRacha> premiosRacha = [
  PremioRacha(minutos: 15),
  PremioRacha(objetos: {'ambientador': 1}),
  PremioRacha(ciruelas: 1),
  PremioRacha(minutos: 30),
  PremioRacha(objetos: {'laxante': 1}),
  PremioRacha(ciruelas: 2),
  PremioRacha(ficha: true, ciruelas: 3),
  PremioRacha(minutos: 45),
  PremioRacha(objetos: {'papel': 1}),
  PremioRacha(ciruelas: 3),
  PremioRacha(minutos: 60),
  PremioRacha(objetos: {'robot': 1}),
  PremioRacha(ciruelas: 4),
  PremioRacha(ficha: true, ciruelas: 5),
  PremioRacha(minutos: 120),
  PremioRacha(objetos: {'ambientador': 2}),
  PremioRacha(ciruelas: 5),
  PremioRacha(objetos: {'laxante': 2}),
  PremioRacha(minutos: 180),
  PremioRacha(ciruelas: 6),
  PremioRacha(ficha: true, ciruelas: 8),
  PremioRacha(minutos: 240),
  PremioRacha(objetos: {'papel': 1, 'robot': 1}),
  PremioRacha(ciruelas: 8),
  PremioRacha(minutos: 360),
  PremioRacha(objetos: {'ambientador': 1, 'laxante': 1}),
  PremioRacha(ciruelas: 10),
  PremioRacha(ficha: true, ciruelas: 12),
  PremioRacha(minutos: 480),
  PremioRacha(ciruelas: 25, logro: 'constancia'),
];

/// Premio del día [dia] (1 a 30; fuera de rango se lleva al ciclo).
PremioRacha premioDia(int dia) => premiosRacha[(dia - 1) % diasRacha];

/// Fecha (sin hora) de [t] en la zona del teléfono, como día UTC para poder restar sin líos de horario de verano.
DateTime fechaLocal(DateTime t) {
  final l = t.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

/// 'AAAA-MM-DD' para mandar al servidor.
String fechaTexto(DateTime f) =>
    '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

/// Lee 'AAAA-MM-DD' (o null).
DateTime? leerFecha(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

/// Estado de la racha para hoy.
class EstadoRacha {
  /// Día que toca reclamar hoy, o el que ya se reclamó hoy.
  final int dia;

  /// Hoy ya se reclamó.
  final bool reclamado;

  /// Días seguidos que se llevan antes de hoy (para la cuadrícula).
  final int previos;

  /// Congeladores 🧊 que se gastan al reclamar hoy (faltaron esos días y alcanzan los congeladores).
  final int congelar;

  const EstadoRacha(this.dia, this.reclamado, this.previos, {this.congelar = 0});
}

/// Días que faltaron que el congelador cubre: k entre 1 y [congeladores]; si no alcanza, 0 (la racha se pierde).
/// Igual que imperio_reclamar_racha en el servidor.
int congeladoresAGastar(int faltaron, int congeladores) => faltaron >= 1 && faltaron <= congeladores ? faltaron : 0;

/// Qué día toca con lo que guarda el servidor (último día y su fecha) y la fecha local de hoy.
/// Ayer reclamado: el siguiente (30 → 1). Hoy reclamado: ese mismo, ya hecho.
/// Faltaron k días y hay k congeladores o más: sigue al siguiente gastando k. Si no: día 1.
EstadoRacha estadoRacha(int rachaDia, DateTime? rachaFecha, DateTime hoy, {int congeladores = 0}) {
  if (rachaDia > 0 && rachaFecha != null) {
    final dif = hoy.difference(rachaFecha).inDays;
    if (dif <= 0) return EstadoRacha(rachaDia, true, rachaDia - 1);
    final k = congeladoresAGastar(dif - 1, congeladores);
    if (dif == 1 || k > 0) {
      final dia = rachaDia % diasRacha + 1;
      return EstadoRacha(dia, false, dia - 1, congelar: k);
    }
  }
  return const EstadoRacha(1, false, 0);
}
