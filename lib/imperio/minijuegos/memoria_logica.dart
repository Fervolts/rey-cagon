// Memoria del rollo, lógica pura: parejas de cartas con emojis de la app. Una partida son tres niveles seguidos
// (4x3, 4x4 y 5x4) que aprietan cada vez más: vista previa más corta, menos papel por pareja y cartas especiales.
//
// Puntos de un nivel. Todo tiene tope, así la partida perfecta da justo maximoPartidaMemoria (3600, el tope del servidor):
// - cada pareja da puntosPorPareja más puntosPorRacha por cada punto de multiplicador de la racha sobre x1 (x4 como mucho);
// - un fallo de memoria quita penalPorFallo y corta la racha. Explorar (dos cartas que nunca habías volteado y sin
//   saber dónde estaba la pareja de la primera) no es fallo: no quita puntos ni corta la racha, solo gasta papel;
// - el papel es el reloj: se gasta un segundo por segundo y cada pareja devuelve un poco (más con racha). Lo que quede
//   al cerrar da hasta bonusPapelPorPareja por pareja, y un nivel sin fallos da bonusLimpioPorPareja por pareja.
// Cartas especiales: el destapador (nivel 2 y 3) enseña todas las cartas un momento al emparejarlo; la cucaracha
// (nivel 3) cambia de sitio dos cartas tapadas cada vez que sale en una pareja equivocada.

import 'dart:math';

/// Emojis de las cartas. Todos tienen su PNG en assets/emoji (lo comprueba un test), así se ven igual en todos los teléfonos.
/// El 🧻 no está: es el reverso de las cartas.
const List<String> emojisMemoria = ['💩', '🚽', '🪠', '🪳', '🚿', '🫧', '🔥', '🍑', '👑', '🐸', '🦆', '🏆', '💎', '🪣', '🧴', '🦨'];

/// Al emparejarlo se ven todas las cartas [JuegoMemoria.tiempoDestapa] segundos.
const String emojiDestapador = '🪠';

/// Si sale en una pareja equivocada cambia de sitio dos cartas tapadas.
const String emojiCucaracha = '🪳';

/// Los que salen como parejas normales. Los especiales solo entran en los niveles que los traen.
final List<String> emojisNormales = [for (final e in emojisMemoria) if (e != emojiDestapador && e != emojiCucaracha) e];

class NivelMemoria {
  final int columnas, filas;

  /// Segundos con todas las cartas a la vista al empezar.
  final double previa;

  /// Segundos de papel por pareja al empezar.
  final double papelPorPareja;
  final bool destapador, cucaracha;
  const NivelMemoria(this.columnas, this.filas, {this.previa = 0, this.papelPorPareja = 3, this.destapador = false, this.cucaracha = false});
  int get cartas => columnas * filas;
  int get pares => cartas ~/ 2;
  double get papelInicial => pares * papelPorPareja;
}

const List<NivelMemoria> nivelesMemoria = [
  NivelMemoria(4, 3, previa: 2.2, papelPorPareja: 2.6),
  NivelMemoria(4, 4, previa: 1.8, papelPorPareja: 2.3, destapador: true),
  NivelMemoria(5, 4, previa: 1.5, papelPorPareja: 2.0, destapador: true, cucaracha: true),
];

const int puntosPorPareja = 50;
const int puntosPorRacha = 20;
const int multiplicadorMaximo = 4;
const int penalPorFallo = 15;
const int bonusPapelPorPareja = 40;
const int bonusLimpioPorPareja = 15;

/// Segundos de papel que devuelve una pareja, por cada punto de multiplicador.
const double papelPorAcierto = 0.3;

/// Multiplicador con [racha] parejas seguidas sin fallar (la actual incluida).
int multiplicadorDe(int racha) => racha.clamp(1, multiplicadorMaximo);

/// Lo que da una pareja con multiplicador [mult].
int puntosDePareja(int mult) => puntosPorPareja + puntosPorRacha * (mult - 1);

/// Lo más que puede dar un nivel: todas las parejas seguidas, papel lleno y sin fallos.
int maximoNivelMemoria(NivelMemoria n) {
  var parejas = 0;
  for (var k = 1; k <= n.pares; k++) {
    parejas += puntosDePareja(multiplicadorDe(k));
  }
  return parejas + (bonusPapelPorPareja + bonusLimpioPorPareja) * n.pares;
}

/// Lo más que puede dar una partida (los tres niveles perfectos). No pasa de 3600, el tope del servidor.
int get maximoPartidaMemoria => nivelesMemoria.fold(0, (s, n) => s + maximoNivelMemoria(n));

enum EstadoCarta { oculta, visible, hecha }

class Carta {
  final String emoji;
  EstadoCarta estado = EstadoCarta.oculta;
  Carta(this.emoji);
}

enum TipoJugada { primera, acierto, exploracion, fallo }

/// Lo que pasó con el último toque, para que la vista lo celebre o lo sacuda.
class Jugada {
  const Jugada(this.tipo, this.a, {this.b = -1, this.puntos = 0, this.multiplicador = 1, this.destapa = false, this.cambio});
  final TipoJugada tipo;

  /// Cartas: [a] la primera, [b] la segunda (-1 si es la primera del turno).
  final int a, b;
  final int puntos, multiplicador;

  /// Se emparejó el destapador: se ven todas un momento.
  final bool destapa;

  /// La cucaracha cambió de sitio estas dos cartas tapadas.
  final (int, int)? cambio;
}

/// Un nivel suelto.
class JuegoMemoria {
  JuegoMemoria(this.nivel, {Random? azar, bool conPrevia = true}) : _azar = azar ?? Random() {
    final especiales = [if (nivel.destapador) emojiDestapador, if (nivel.cucaracha) emojiCucaracha];
    final normales = [...emojisNormales]..shuffle(_azar);
    final elegidos = [...especiales, ...normales.take(nivel.pares - especiales.length)];
    final mazo = [for (final e in elegidos) ...[e, e]]..shuffle(_azar);
    cartas = [for (final e in mazo) Carta(e)];
    _previa = conPrevia ? nivel.previa : 0;
    _papel = nivel.papelInicial;
  }

  final NivelMemoria nivel;
  final Random _azar;
  late final List<Carta> cartas;

  /// Tiempo que se ve una pareja equivocada antes de taparse sola. Tocar otra carta la tapa antes.
  static const double esperaFallo = 0.7;

  /// Tiempo que se ve todo al emparejar el destapador.
  static const double tiempoDestapa = 1.0;

  final List<int> _abiertas = [];
  final Set<int> _vistas = {};
  double _espera = 0, _previa = 0, _destapa = 0, _segundos = 0, _papel = 0;
  bool _corre = false;
  int _errores = 0, _exploraciones = 0, _parejas = 0, _racha = 0, _mejorRacha = 0, _puntosParejas = 0;
  Jugada? _jugada;

  /// Fallos de memoria (no cuenta explorar).
  int get errores => _errores;
  int get exploraciones => _exploraciones;
  int get parejas => _parejas;
  int get racha => _racha;
  int get mejorRacha => _mejorRacha;
  double get segundos => _segundos;
  double get papel => _papel;
  double get papelFraccion => nivel.papelInicial <= 0 ? 0 : _papel / nivel.papelInicial;

  /// Multiplicador que tendrá la próxima pareja.
  int get multiplicadorSiguiente => multiplicadorDe(_racha + 1);
  bool get terminado => _parejas == nivel.pares;
  Jugada? get jugada => _jugada;

  /// Todas las cartas a la vista al empezar; no se puede tocar y el papel no corre.
  bool get enPrevia => _previa > 0;
  double get previaRestante => _previa;

  /// Se emparejó el destapador: todas a la vista, no se puede tocar.
  bool get destapando => _destapa > 0;

  /// La carta [i] se ve (volteada, hecha, vista previa o destapador).
  bool seVe(int i) => enPrevia || destapando || cartas[i].estado != EstadoCarta.oculta;

  int get puntosParejas => _puntosParejas;
  int get descuentoFallos => _errores * penalPorFallo;
  int get bonusPapel => terminado ? (bonusPapelPorPareja * nivel.pares * papelFraccion.clamp(0.0, 1.0)).round() : 0;
  int get bonusLimpio => terminado && _errores == 0 ? bonusLimpioPorPareja * nivel.pares : 0;

  /// Puntos del nivel. Los bonus solo cuentan al cerrarlo. Nunca baja de 0.
  int get puntos => max(0, _puntosParejas - descuentoFallos + bonusPapel + bonusLimpio);

  /// No se puede tocar ahora mismo (vista previa o destapador).
  bool get bloqueado => enPrevia || destapando;

  /// Hay una pareja equivocada a la vista esperando taparse.
  bool get esperando => _espera > 0;

  int _pareja(int i) {
    for (var k = 0; k < cartas.length; k++) {
      if (k != i && cartas[k].emoji == cartas[i].emoji) return k;
    }
    return -1;
  }

  void _tapar() {
    for (final i in _abiertas) {
      if (cartas[i].estado == EstadoCarta.visible) cartas[i].estado = EstadoCarta.oculta;
    }
    _abiertas.clear();
    _espera = 0;
  }

  /// Voltea la carta [i]. Devuelve false si no se pudo (ya a la vista, hecha, bloqueado o fuera de rango).
  /// Con una pareja equivocada a la vista, tocar otra carta tapada la tapa de una y voltea la nueva.
  bool toca(int i) {
    if (i < 0 || i >= cartas.length || bloqueado || terminado) return false;
    final c = cartas[i];
    if (c.estado != EstadoCarta.oculta) return false;
    if (_espera > 0) _tapar();
    _corre = true;
    c.estado = EstadoCarta.visible;
    _abiertas.add(i);
    if (_abiertas.length == 1) {
      _jugada = Jugada(TipoJugada.primera, i);
      return true;
    }
    final a = _abiertas[0];
    final ca = cartas[a];
    if (ca.emoji == c.emoji) {
      ca.estado = c.estado = EstadoCarta.hecha;
      _parejas++;
      _racha++;
      _mejorRacha = max(_mejorRacha, _racha);
      final mult = multiplicadorDe(_racha);
      final pts = puntosDePareja(mult);
      _puntosParejas += pts;
      _papel = min(nivel.papelInicial, _papel + papelPorAcierto * mult);
      final destapa = c.emoji == emojiDestapador && !terminado;
      if (destapa) _destapa = tiempoDestapa;
      _abiertas.clear();
      _vistas.addAll([a, i]);
      _jugada = Jugada(TipoJugada.acierto, a, b: i, puntos: pts, multiplicador: mult, destapa: destapa);
      return true;
    }
    // Fallo de memoria: ya sabías dónde estaba la pareja de la primera, o la segunda ya la habías volteado.
    final fallo = _vistas.contains(_pareja(a)) || _vistas.contains(i);
    _vistas.addAll([a, i]);
    if (fallo) {
      _errores++;
      _racha = 0;
    } else {
      _exploraciones++;
    }
    _espera = esperaFallo;
    final cambio = (ca.emoji == emojiCucaracha || c.emoji == emojiCucaracha) ? _cucaracha(a, i) : null;
    _jugada = Jugada(fallo ? TipoJugada.fallo : TipoJugada.exploracion, a, b: i, cambio: cambio);
    return true;
  }

  /// La cucaracha cambia de sitio dos cartas tapadas (no las que están a la vista). Las dos quedan como no vistas.
  (int, int)? _cucaracha(int a, int b) {
    final tapadas = [for (var k = 0; k < cartas.length; k++) if (k != a && k != b && cartas[k].estado == EstadoCarta.oculta) k];
    if (tapadas.length < 2) return null;
    tapadas.shuffle(_azar);
    final x = tapadas[0], y = tapadas[1];
    final t = cartas[x];
    cartas[x] = cartas[y];
    cartas[y] = t;
    _vistas.removeAll([x, y]);
    return (x, y);
  }

  void avanzar(double dt) {
    if (dt <= 0 || terminado) return;
    if (_previa > 0) {
      _previa -= dt;
      if (_previa <= 0) {
        _previa = 0;
        _corre = true; // el papel empieza a gastarse al taparse las cartas
      }
      return;
    }
    if (_destapa > 0) {
      _destapa = max(0, _destapa - dt); // premio: el papel no se gasta mientras se ve todo
      return;
    }
    if (_corre) {
      _segundos += dt;
      _papel = max(0, _papel - dt);
    }
    if (_espera > 0) {
      _espera -= dt;
      if (_espera <= 0) _tapar();
    }
  }
}

/// Los tres niveles seguidos.
class PartidaMemoria {
  // ignore: prefer_initializing_formals
  PartidaMemoria({Random? azar, this.conPrevia = true}) : _azar = azar {
    juego = JuegoMemoria(nivelesMemoria[0], azar: _azar, conPrevia: conPrevia);
  }

  final Random? _azar;
  final bool conPrevia;
  late JuegoMemoria juego;
  int _nivel = 0;
  int _acumulado = 0;
  int _erroresTotal = 0;

  int get nivel => _nivel;
  int get erroresTotal => _erroresTotal + juego.errores;

  /// Puntos de los niveles ya cerrados más el actual si ya acabó.
  int get puntos => _acumulado + (juego.terminado ? juego.puntos : 0);

  /// Puntos de los niveles cerrados más lo que va del actual sin bonus (para el marcador en vivo).
  int get puntosEnVivo => _acumulado + (juego.terminado ? juego.puntos : max(0, juego.puntosParejas - juego.descuentoFallos));
  bool get nivelTerminado => juego.terminado;
  bool get terminada => _nivel == nivelesMemoria.length - 1 && juego.terminado;

  /// El nivel que viene después del actual, o null si es el último.
  NivelMemoria? get proximo => _nivel + 1 < nivelesMemoria.length ? nivelesMemoria[_nivel + 1] : null;

  /// Cierra el nivel que acabó y arma el siguiente. No hace nada si no ha acabado o ya era el último.
  bool siguiente() {
    if (!juego.terminado || terminada) return false;
    _acumulado += juego.puntos;
    _erroresTotal += juego.errores;
    _nivel++;
    juego = JuegoMemoria(nivelesMemoria[_nivel], azar: _azar, conPrevia: conPrevia);
    return true;
  }
}
