// Cagadón con apuesta: lógica pura del cobro, el premio y la devolución.
//
// La apuesta se mide en minutos de producción propia (15, 30 o 60). Cada uno
// paga de SU producción al retar o al aceptar: si no le alcanza el saldo, paga
// lo que tenga (hasta 0) y queda anotada la fracción pagada. El servidor guarda
// esa fracción y decide el resultado (supabase/migrations/20261108140000_cagadon_apuesta.sql):
// - gana: cobra 2 × minutos × fracción, en minutos de SU producción al cobrar.
// - pierde: nada.
// - devuelve (empate, rechazo, cancelación, vencido o apuesta anulada):
//   recupera minutos × fracción.
// Los MJ no se compran con dinero: la apuesta no toca Ciruelas ni compras.

import 'estado.dart';

/// Minutos que se pueden apostar. 0 es "sin apuesta".
const List<int> minutosApuesta = [0, 15, 30, 60];

/// Opciones del selector con el tope del flag `apuesta_max_min`.
/// Con tope 0 solo queda "sin apuesta".
List<int> opcionesApuesta(int tope) => [for (final m in minutosApuesta) if (m <= tope) m];

/// MJ que cuestan [min] minutos de una producción de [mps] MJ/s.
double costoApuesta(int min, double mps) => min <= 0 || mps <= 0 ? 0 : min * 60 * mps;

/// Lo que de verdad se paga con [saldo]: todo el [costo] o lo que haya.
/// [fraccion] va de 0 a 1 y es lo que el servidor guarda.
({double mj, double fraccion}) cobroApuesta(double saldo, double costo) {
  if (costo <= 0) return (mj: 0, fraccion: 0);
  final mj = saldo <= 0 ? 0.0 : (saldo < costo ? saldo : costo);
  return (mj: mj, fraccion: (mj / costo).clamp(0.0, 1.0));
}

/// Minutos de producción que cobra el ganador.
double premioApuesta(int min, double fraccion) => 2 * min * fraccion.clamp(0.0, 1.0);

/// Minutos que recupera cada uno si no hubo ganador o la apuesta se anuló.
double devolucionApuesta(int min, double fraccion) => min * fraccion.clamp(0.0, 1.0);

/// Descuenta lo apostado. Solo baja el saldo: los MJ de la vida no se pierden.
void aplicarCobro(Partida p, double mj) {
  if (mj <= 0) return;
  p.saldo = p.saldo - mj < 0 ? 0 : p.saldo - mj;
}

/// Suma el premio del ganador: es producción nueva, sube saldo y MJ de la vida.
void aplicarPremio(Partida p, double mj) {
  if (mj <= 0) return;
  p.saldo += mj;
  p.mjTotal += mj;
}

/// Devuelve lo apostado: solo saldo, y nunca por encima de los MJ de la vida.
void aplicarDevolucion(Partida p, double mj) {
  if (mj <= 0) return;
  final nuevo = p.saldo + mj;
  p.saldo = nuevo > p.mjTotal ? p.mjTotal : nuevo;
}

/// Qué hace un apunte de la cola: descontar lo apostado, sumar el premio o devolver.
enum TipoApunte { cobro, premio, devolucion }

/// Un movimiento de la apuesta que espera a la partida. Se apunta en minutos de producción y se convierte a MJ al
/// aplicarlo, con la producción de ese momento: así funciona igual si se apostó o cobró desde el chat con el Imperio cerrado.
class ApunteApuesta {
  const ApunteApuesta(this.tipo, this.reto, this.minutos, {this.apuesta = 0, this.ganadas = 0});

  final TipoApunte tipo;
  final int reto;
  final double minutos;

  /// Minutos apostados en ese reto (15, 30 o 60) y, en un premio, cuántas apuestas lleva ganadas según el servidor.
  /// Solo sirven para los logros.
  final int apuesta, ganadas;

  Map<String, Object?> toJson() => {'tipo': tipo.name, 'reto': reto, 'minutos': minutos, 'apuesta': apuesta, 'ganadas': ganadas};

  /// null si el apunte está roto (no se aplica).
  static ApunteApuesta? desdeJson(Object? j) {
    if (j is! Map) return null;
    final tipo = TipoApunte.values.where((t) => t.name == j['tipo']).firstOrNull;
    final reto = j['reto'], minutos = j['minutos'];
    if (tipo == null || reto is! num || minutos is! num || !minutos.isFinite || minutos <= 0) return null;
    final apuesta = j['apuesta'], ganadas = j['ganadas'];
    return ApunteApuesta(tipo, reto.toInt(), minutos.toDouble(),
        apuesta: apuesta is num ? apuesta.toInt() : 0, ganadas: ganadas is num ? ganadas.toInt() : 0);
  }
}

/// Aplica [a] a la partida con la producción [mps] y devuelve los MJ que movió (lo descontado, lo ganado o lo devuelto).
double aplicarApunte(Partida p, ApunteApuesta a, double mps) {
  final mj = a.minutos * 60 * (mps > 0 && mps.isFinite ? mps : 0);
  switch (a.tipo) {
    case TipoApunte.cobro:
      final antes = p.saldo;
      aplicarCobro(p, mj);
      return antes - p.saldo;
    case TipoApunte.premio:
      aplicarPremio(p, mj);
      return mj;
    case TipoApunte.devolucion:
      final antes = p.saldo;
      aplicarDevolucion(p, mj);
      return p.saldo - antes;
  }
}

/// Logros que da un premio cobrado (ids de `logros` en catalogo.dart). Las pérdidas y devoluciones no dan nada.
List<String> logrosDeApunte(ApunteApuesta a) => a.tipo != TipoApunte.premio
    ? const []
    : ['apuesta_ganada', if (a.ganadas >= 5) 'apuestas_5', if (a.apuesta >= 60) 'apuesta_60'];

/// Lo que hace falta saber del Imperio para apostar. Solo existe si se puede apostar (Imperio encendido, abierto alguna
/// vez, con producción y con tope mayor que 0).
class ResumenApuesta {
  const ResumenApuesta({required this.saldo, required this.mps, required this.tope});

  final double saldo, mps;
  final int tope;

  List<int> get opciones => opcionesApuesta(tope);
  double costo(int min) => costoApuesta(min, mps);

  /// Lo que se pagaría hoy por [min] minutos (todo o lo que alcance).
  ({double mj, double fraccion}) cuenta(int min) => cobroApuesta(saldo, costo(min));
}
