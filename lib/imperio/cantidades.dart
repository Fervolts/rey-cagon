// Botones de cantidad de compra (x1, x10, x100, x1000). Dart puro.
//
// x100 sale cuando tienes 50 de algún edificio o te alcanzan 100 del más barato; x1000 con 500 o si
// te alcanzan 1000. Una vez visto, el botón se queda (la pantalla guarda los vistos en el teléfono).

import 'motor.dart';

const cantidadesCompra = [1, 10, 100, 1000];

/// Cuántos edificios hay que tener (de uno solo) para que salga cada cantidad.
const _minimoTenidos = {100: 50, 1000: 500};

/// Cantidades que se muestran. [masBarato] = precio de n unidades del edificio más barato (solo se llama
/// para las que todavía no se han visto).
Set<int> cantidadesVisibles({
  required Iterable<int> tenidos,
  required double saldo,
  required double Function(int n) masBarato,
  Set<int> vistas = const {},
}) {
  final maximo = tenidos.fold(0, (a, b) => a > b ? a : b);
  final r = <int>{1, 10};
  for (final MapEntry(key: n, value: minimo) in _minimoTenidos.entries) {
    if (vistas.contains(n) || maximo >= minimo || masBarato(n) <= saldo) r.add(n);
  }
  return r;
}

/// Lo mismo, leyendo la partida: los edificios abiertos y el más barato de ellos. Todos crecen igual
/// (x1,15 por unidad), así que el más barato de 1 también lo es de n.
Set<int> cantidadesDe(Imperio im, int ahora, {Set<int> vistas = const {}}) {
  String? barato;
  var minimo = double.infinity;
  for (final e in edificios) {
    if (!im.edificioAbierto(e.id)) continue;
    final p = im.precioEdificio(e.id, ahora);
    if (p < minimo) (minimo, barato) = (p, e.id);
  }
  final b = barato;
  return cantidadesVisibles(
    tenidos: [for (final e in edificios) im.cantidad(e.id)],
    saldo: im.saldo,
    masBarato: (n) => b == null ? double.infinity : im.precioEdificioVarios(b, n, ahora),
    vistas: vistas,
  );
}
