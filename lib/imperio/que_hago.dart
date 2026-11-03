// "¿Qué hago ahora?": la próxima jugada que más conviene, calculada solo con el Imperio (sin widgets ni red).
// La hoja y el botón ? viven en recorrido.dart; aquí solo está la cuenta, para poder probarla sola.

import 'dart:math';

import '../idioma.dart';
import 'casas.dart';
import 'formato.dart';
import 'motor.dart';

/// Toques por segundo que se le suponen al jugador para comparar el pujo con lo que entra solo (conservador: uno).
const double toquesSupuestos = 1;

/// Jalar conviene cuando los Rollos nuevos suben la producción al menos esto (x1,5) o abren un edificio de la fase 2.
const double saltoRollosConviene = 1.5;

/// Un nivel de la Plomería conviene cuando sube lo que entra al menos esto (x1,2), aun gastando sus Rollos de Oro.
const double saltoPlomeriaConviene = 1.2;

/// Nodos de la Plomería que suben lo que entra (los demás no se pueden medir con el ritmo).
const List<String> plomeriaQueProduce = ['tuberia_ancha', 'llave_paso'];

/// A dónde lleva el botón IR de la hoja.
enum DestinoQueHago { cerrar, edificios, tienda, jalar, mudanza }

/// Una jugada sugerida. [id] va a la telemetría (`imperio_que_hago`): destapar, robot, dorado, mudanza, jalar, plomeria,
/// edificio, mejora, esperar o pujar. [objetivo] es el edificio o la mejora (si aplica) y [segundos], lo que falta esperando (si aplica).
class Sugerencia {
  const Sugerencia(this.id, this.emoji, this.titulo, this.texto, this.ir, {this.objetivo, this.segundos});

  final String id;
  final String emoji;
  final String titulo;
  final String texto;
  final DestinoQueHago ir;
  final String? objetivo;
  final int? segundos;
}

/// Algo que se puede comprar con MJ: un edificio o una mejora, con lo que cuesta y lo que suma por segundo.
class Compra {
  const Compra(this.id, this.emoji, this.nombre, this.precio, this.suma, {required this.esEdificio});

  final String id;
  final String emoji;
  final String nombre;
  final double precio;

  /// MJ por segundo que suma (lo que entra solo más un toque por segundo).
  final double suma;
  final bool esEdificio;

  /// Segundos de lo que suma para recuperar el precio. Menos es mejor.
  double get retorno => precio / suma;
}

String _mj(double v) => formatoMj(v, ingles: enIngles);

/// Lo que entra por segundo contando un toque por segundo (sin efectos de momento ni atascos).
double _ritmo(Imperio im, int ahora) => im.mpsSinEfectos(contarAtasco: false) + im.valorPujo(ahora) * toquesSupuestos;

/// Todos los edificios y mejoras abiertos que suman algo, con su retorno. Prueba cada compra en el Imperio y la deshace.
List<Compra> comprasPosibles(Imperio im, int ahora, {bool soloEdificios = false}) {
  final p = im.partida;
  final base = _ritmo(im, ahora);
  final r = <Compra>[];
  for (final e in edificios) {
    if (!im.edificioVisible(e.id) || !im.edificioAbierto(e.id)) continue;
    final precio = im.precioEdificio(e.id, ahora);
    final antes = p.edificios[e.id];
    p.edificios[e.id] = (antes ?? 0) + 1;
    final double suma;
    try {
      suma = _ritmo(im, ahora) - base;
    } finally {
      if (antes == null) {
        p.edificios.remove(e.id);
      } else {
        p.edificios[e.id] = antes;
      }
    }
    if (suma > 0 && precio.isFinite) r.add(Compra(e.id, e.emoji, nombreEdificio(e.id, p.mudanzas), precio, suma, esEdificio: true));
  }
  if (soloEdificios) return r;
  for (final m in im.mejorasDisponibles()) {
    final precio = im.precioMejora(m);
    p.mejoras.add(m.id);
    final double suma;
    try {
      suma = _ritmo(im, ahora) - base;
    } finally {
      p.mejoras.remove(m.id);
    }
    if (suma > 0 && precio.isFinite) r.add(Compra(m.id, m.emoji, tr(m.nombreEs, m.nombreEn), precio, suma, esEdificio: false));
  }
  return r;
}

/// La compra de menor retorno: entre las que alcanzan con [soloAlcanzan], o entre todas.
Compra? mejorCompra(Imperio im, int ahora, {bool soloAlcanzan = false, bool soloEdificios = false}) {
  Compra? mejor;
  for (final c in comprasPosibles(im, ahora, soloEdificios: soloEdificios)) {
    if (soloAlcanzan && c.precio > im.saldo) continue;
    if (mejor == null || c.retorno < mejor.retorno) mejor = c;
  }
  return mejor;
}

/// Lo que da jalar ahora: rollos nuevos, cuánto multiplica la producción y el primer edificio de la fase 2 que abre (o null).
({int nuevos, double salto, Edificio? abre}) cuentaJalar(Imperio im) {
  final n = im.rollosPorGanar;
  final pct = im.ajustes.rolloPct;
  final r = im.partida.rollos;
  final salto = (1 + (r + n) * pct) / (1 + r * pct);
  final ganados = im.partida.rollosGanados;
  Edificio? abre;
  for (final e in edificios) {
    if (!e.fase1 && e.rollos > ganados && e.rollos <= ganados + n) {
      abre = e;
      break;
    }
  }
  return (nuevos: n, salto: salto, abre: abre);
}

/// Jalar conviene: la cadena está lista, da al menos un rollo y sube la producción x1,5 o abre un edificio nuevo.
bool jalarConviene(Imperio im, {required bool cadenaLista}) {
  if (!cadenaLista || !im.cadenaDesbloqueada) return false;
  final j = cuentaJalar(im);
  return j.nuevos >= 1 && (j.salto >= saltoRollosConviene || j.abre != null);
}

/// El nivel de la Plomería que más sube lo que entra, contando los Rollos de Oro que gasta (bajan el +% por rollo).
/// Null si ninguno alcanza o ninguno sube al menos [saltoPlomeriaConviene]. Prueba cada compra y la deshace.
({ObjetoRollos objeto, double salto})? plomeriaConviene(Imperio im, int ahora) {
  final p = im.partida;
  final base = _ritmo(im, ahora);
  if (base <= 0) return null;
  ({ObjetoRollos objeto, double salto})? mejor;
  for (final id in plomeriaQueProduce) {
    final o = objetoRollosPorId(id);
    if (o == null || !im.puedeComprarObjetoRollos(id, ahora)) continue;
    final precio = im.precioObjetoRollos(id).toInt();
    final antes = p.objetosRollos[id];
    p.rollos -= precio;
    p.objetosRollos[id] = (antes ?? 0) + 1;
    final double salto;
    try {
      salto = _ritmo(im, ahora) / base;
    } finally {
      p.rollos += precio;
      if (antes == null) {
        p.objetosRollos.remove(id);
      } else {
        p.objetosRollos[id] = antes;
      }
    }
    if (salto >= saltoPlomeriaConviene && (mejor == null || salto > mejor.salto)) mejor = (objeto: o, salto: salto);
  }
  return mejor;
}

/// Duración corta para el texto: "40 s", "12 min", "3 h", "2 d".
String duracionCorta(int s) {
  if (s < 60) return '$s s';
  if (s < 3600) return '${(s / 60).round()} min';
  if (s < 86400) return '${(s / 3600).round()} h';
  return '${(s / 86400).round()} d';
}

/// Porcentaje de producción de [rollos] Rollos de Oro: "+40%".
String pctRollos(int rollos, double pct) {
  final v = rollos * pct * 100;
  return '+${v == v.roundToDouble() ? '${v.round()}' : _mj(v)}%';
}

/// La próxima jugada, en este orden: 1) un Atasco abierto (con dos o más y el Robot abierto, alquilarlo); 2) el mojón
/// dorado en pantalla; 3) mudarse si se puede; 4) jalar si conviene (si no, siempre habría algo barato que comprar y
/// nunca saldría); 5) un nivel de la Plomería que rinde; 6) la compra que alcanza con menor retorno; 7) pujar o esperar
/// lo que falta para la mejor compra. [cadenaLista]: el botón JALAR está encendido (lo decide cadena.dart, que pide red;
/// por eso llega de afuera). [mudanzaLista]: el servidor conoce la mudanza y se cumplen los requisitos (las cagadas las
/// cuenta el servidor). [moneda]: la abreviatura de los MJ.
Sugerencia queHagoAhora(Imperio im, int ahora, {bool cadenaLista = false, bool mudanzaLista = false, String moneda = 'MJ'}) {
  final atascos = im.atascos;
  if (atascos.isNotEmpty && !im.robotActivo(ahora)) {
    if (atascos.length >= 2 && im.objetoAbierto('robot')) {
      return Sugerencia('robot', '🤖', tr('Alquila el Robot destapador', 'Rent the Plunger bot'),
          tr('Tienes ${atascos.length} cagadores tapados y no producen nada. El Robot los destapa solo mientras juegas.',
              '${atascos.length} poopers are clogged and make nothing. The Plunger bot unclogs them by itself while you play.'),
          DestinoQueHago.tienda);
    }
    final e = edificioPorId(atascos.first.edificio);
    final nombre = e == null ? '' : nombreEdificio(e.id, im.partida.mudanzas);
    return Sugerencia('destapar', '🪠', tr('Destapa $nombre', 'Unclog $nombre'),
        tr('Está tapado y no produce ni un $moneda. Dale a la tarjeta de abajo hasta que suelte.',
            "It's clogged and makes zero $moneda. Tap the card below until it lets go."),
        DestinoQueHago.cerrar,
        objetivo: atascos.first.edificio);
  }
  if (im.dorado(ahora) != null) {
    return Sugerencia('dorado', '🟡', tr('Toca el mojón dorado', 'Tap the golden poop'),
        tr('Anda flotando por la pantalla y se va rápido. Trae premio.', "It's floating around the screen and leaves fast. It brings a prize."),
        DestinoQueHago.cerrar);
  }
  if (mudanzaLista) {
    final m = im.partida.mudanzas + 1;
    final llaves = im.llavesPorGanar;
    final pct = (im.ajustes.llavePct * 100).round();
    return Sugerencia('mudanza', casaDe(m).emoji, tr('Múdate a ${nombreCasa(m)}', 'Move to the ${nombreCasa(m)}'),
        tr('Produce x${_mj(multiplicadorCasa(m) / multiplicadorCasa(m - 1))} y te llevas ${_mj(llaves.toDouble())} Llaves (+$pct% cada una). '
                'Empiezas de cero en una casa más grande.',
            'It makes x${_mj(multiplicadorCasa(m) / multiplicadorCasa(m - 1))} and you take ${_mj(llaves.toDouble())} Keys (+$pct% each). '
                'You start over in a bigger house.'),
        DestinoQueHago.mudanza);
  }
  if (jalarConviene(im, cadenaLista: cadenaLista)) {
    final j = cuentaJalar(im);
    final pct = im.ajustes.rolloPct;
    final total = im.partida.rollos + j.nuevos;
    final abre = j.abre == null ? '' : tr(' y se abre ', ' and unlocks ') + nombreEdificio(j.abre!.id, im.partida.mudanzas);
    return Sugerencia('jalar', '🧻', tr('Jala la cadena', 'Flush the chain'),
        tr('Te da ${_mj(j.nuevos.toDouble())} Rollos de Oro: todo pasa a producir ${pctRollos(total, pct)} hasta la mudanza$abre. '
                'Empiezas de cero, pero más rápido.',
            'You get ${_mj(j.nuevos.toDouble())} Golden Rolls: everything makes ${pctRollos(total, pct)} until you move$abre. '
                'You start over, but faster.'),
        DestinoQueHago.jalar);
  }
  final plomeria = plomeriaConviene(im, ahora);
  if (plomeria != null) {
    final o = plomeria.objeto;
    final precio = _mj(im.precioObjetoRollos(o.id));
    final salto = _mj((plomeria.salto * 100).roundToDouble() / 100);
    return Sugerencia('plomeria', o.emoji, tr('Compra ${o.nombreEs}', 'Buy ${o.nombreEn}'),
        tr('En la Plomería: cuesta $precio Rollos de Oro y aun así todo produce x$salto hasta la mudanza.',
            'In Plumbing: it costs $precio Golden Rolls and everything still makes x$salto until you move.'),
        DestinoQueHago.tienda,
        objetivo: o.id);
  }
  final ya = mejorCompra(im, ahora, soloAlcanzan: true);
  if (ya != null) {
    return Sugerencia(ya.esEdificio ? 'edificio' : 'mejora', ya.emoji, tr('Compra ${ya.nombre}', 'Buy ${ya.nombre}'),
        tr('Cuesta ${_mj(ya.precio)} $moneda y suma +${_mj(ya.suma)} $moneda/s. Se paga solo en ${duracionCorta(ya.retorno.ceil())}.',
            'Costs ${_mj(ya.precio)} $moneda and adds +${_mj(ya.suma)} $moneda/s. Pays for itself in ${duracionCorta(ya.retorno.ceil())}.'),
        DestinoQueHago.edificios,
        objetivo: ya.id);
  }
  final meta = mejorCompra(im, ahora);
  if (meta == null) {
    return Sugerencia('pujar', '💩', tr('Puja en la poceta', 'Push on the toilet'),
        tr('Cada toque da ${_mj(im.valorPujo(ahora))} $moneda. Junta y vuelve a preguntarme.',
            'Each tap gives ${_mj(im.valorPujo(ahora))} $moneda. Save up and ask me again.'),
        DestinoQueHago.cerrar);
  }
  final falta = max(0.0, meta.precio - im.saldo);
  final mps = im.mps(ahora);
  if (mps <= 0) {
    final toques = (falta / max(im.valorPujo(ahora), 1e-9)).ceil();
    return Sugerencia('pujar', '💩', tr('Puja en la poceta', 'Push on the toilet'),
        tr('Te faltan ${_mj(falta)} $moneda para ${meta.nombre}: unos ${_mj(toques.toDouble())} toques a la poceta.',
            "You're ${_mj(falta)} $moneda short of ${meta.nombre}: about ${_mj(toques.toDouble())} taps on the toilet."),
        DestinoQueHago.cerrar,
        objetivo: meta.id);
  }
  final s = (falta / mps).ceil();
  return Sugerencia('esperar', '⏳', tr('Junta para ${meta.nombre}', 'Save up for ${meta.nombre}'),
      tr('Te faltan ${_mj(falta)} $moneda. Puja o espera ${duracionCorta(s)} y cómpralo: es lo que más rinde.',
          "You're ${_mj(falta)} $moneda short. Push or wait ${duracionCorta(s)} and buy it: it's your best deal."),
      DestinoQueHago.cerrar,
      objetivo: meta.id,
      segundos: s);
}
