// Guía de los alquileres: la ficha "qué hace" de cada alquilable (la primera vez que se ve en la tienda, o con el botón ?)
// con un ejemplo en vivo con los números del jugador, y los empujones de la pantalla (uno a la vez, cada uno una sola vez).
// Lo ya visto queda en `Partida.guiaVista` (jalar la cadena no lo borra). Telemetría: `alquiler_guia` {id, accion}.

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'casas.dart';
import 'control.dart';
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';

/// Un Atasco abierto más que esto (ms) sin Robot nunca alquilado: empujón del Robot.
const msAtascoEmpujon = 20000;

/// Pujos a mano en [msVentanaPujos] para el empujón del Primo (6 por segundo durante 5 s).
const pujosRapidos = 30;
const msVentanaPujos = 5000;

/// Lo que dura un empujón en pantalla y lo que dura resaltada la ficha del recién alquilado en la tira.
const duracionEmpujonGuia = Duration(seconds: 9);
const duracionResaltado = Duration(seconds: 5);

String _mj(double v) => formatoMj(v, ingles: enIngles);

String _horas(Duration d) {
  final h = d.inMinutes / 60;
  final txt = h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(1).replaceAll('.', enIngles ? '.' : ',');
  return '$txt h';
}

/// El edificio que compraría ahora la Cuadrilla: el abierto (que produce) más barato.
Edificio? edificioMasBarato(Imperio im, int ahora) {
  Edificio? barato;
  for (final e in edificios) {
    if (e.mpsBase <= 0 || !im.edificioAbierto(e.id)) continue;
    if (barato == null || im.precioEdificio(e.id, ahora) < im.precioEdificio(barato.id, ahora)) barato = e;
  }
  return barato;
}

/// Lo que dice la ficha de [id]: qué hace en lenguaje llano y un ejemplo con los números de ahora.
({String que, String ejemplo}) textosGuia(Imperio im, String id, int ahora) {
  final mon = monedaActual().abreviatura;
  final p = im.partida;
  String destapes() => p.destapes == 1
      ? tr('Llevas 1 destape a mano.', 'You have unclogged 1 by hand.')
      : tr('Llevas ${p.destapes} destapes a mano.', 'You have unclogged ${p.destapes} by hand.');
  switch (id) {
    case 'robot':
      return (que: tr('Destapa solo cada Atasco mientras dure. No tienes que tocar nada.', 'Unclogs every Clog by itself while it lasts. No tapping.'), ejemplo: destapes());
    case 'robot_turbo':
      return (
        que: tr('Destapa solo cada Atasco y el Atasco no frena la producción.', 'Unclogs every Clog by itself and the Clog does not slow production.'),
        ejemplo: destapes(),
      );
    case 'plomero_horas':
      final extra = im.mpsSinEfectos() * 2 * duracionBonoPlomero.inSeconds;
      return (
        que: tr('Cada Atasco que destapes: producción x3 por 1 min.', 'Every Clog you unclog: production x3 for 1 min.'),
        ejemplo: tr('Ahora eso es +${_mj(extra)} $mon por destape.', 'Right now that is +${_mj(extra)} $mon per unclog.'),
      );
    case 'primo':
      final mjs = im.valorPujo(ahora) * pujosPrimo;
      return (
        que: tr('Puja ${pujosPrimo.round()} veces por segundo por ti mientras la app está abierta.',
            'Pushes ${pujosPrimo.round()} times per second for you while the app is open.'),
        ejemplo: tr('Ahora serían +${_mj(mjs)} $mon/s.', 'Right now that is +${_mj(mjs)} $mon/s.'),
      );
    case 'cuadrilla':
      final e = edificioMasBarato(im, ahora);
      final String ejemplo;
      if (e == null) {
        ejemplo = tr('Ahora no hay edificio que comprar.', 'There is no building to buy right now.');
      } else {
        final nombre = '${e.emoji} ${nombreEdificio(e.id, im.partida.mudanzas)}';
        final precio = im.precioEdificio(e.id, ahora);
        ejemplo = precio <= im.saldo
            ? tr('Ahora compraría: $nombre.', 'Right now it would buy: $nombre.')
            : tr('Ahora compraría: $nombre, cuando tengas ${_mj(precio)} $mon.', 'Right now it would buy: $nombre, once you have ${_mj(precio)} $mon.');
      }
      return (que: tr('Cada minuto compra el edificio más barato si te alcanza.', 'Every minute it buys the cheapest building if you can afford it.'), ejemplo: ejemplo);
    case 'guardia':
      final tope = im.topeOffline > topeGuardia ? im.topeOffline : topeGuardia;
      final pct = (im.porcentajeOffline * 100).round();
      return (
        que: tr('Tu próximo offline cuenta al 100% y hasta ${_horas(tope)}. Se gasta al volver.',
            'Your next offline counts at 100% and up to ${_horas(tope)}. It is used up when you come back.'),
        ejemplo: tr('Hoy cuenta al $pct% hasta ${_horas(im.topeOffline)}.', 'Today it counts at $pct% up to ${_horas(im.topeOffline)}.'),
      );
  }
  final o = objetoPorId(id);
  return (que: o == null ? '' : tr(o.descEs, o.descEn), ejemplo: '');
}

// ---------- La ficha en la tienda ----------

/// Fichas reabiertas con el botón ? (solo en esta sesión de la app).
final ValueNotifier<Set<String>> guiaReabierta = ValueNotifier(<String>{});

/// Fichas ya anotadas (`ficha`) en esta sesión: la primera vez que salen solas se anota una vez.
final Set<String> _fichaAnotada = {};

@visibleForTesting
void reiniciarGuia() {
  guiaReabierta.value = {};
  _fichaAnotada.clear();
}

/// El alquilable abierto que todavía no entendió, primero en el catálogo: su ficha sale sola (una a la vez).
String? guiaPendiente(Imperio im) {
  for (final o in objetos) {
    if (o.tipo == TipoObjeto.alquilable && im.objetoAbierto(o.id) && !im.partida.guiaVista.contains(o.id)) return o.id;
  }
  return null;
}

/// Si la ficha de [id] va abierta: la pendiente ([guiaPendiente]) o reabierta con el ?.
bool guiaAbierta(Imperio im, String id) =>
    objetoPorId(id)?.tipo == TipoObjeto.alquilable && im.objetoAbierto(id) && (guiaReabierta.value.contains(id) || guiaPendiente(im) == id);

void _cerrarFicha(String id) {
  if (guiaReabierta.value.contains(id)) guiaReabierta.value = {...guiaReabierta.value}..remove(id);
}

/// Abre la ficha de [id] (el ? o tocar el emoji de la fila), o la cierra si ya va abierta (cuenta como vista).
void alternarGuia(ControlImperio control, String id) {
  final im = control.imperio;
  if (!im.objetoAbierto(id)) return;
  if (guiaAbierta(im, id)) {
    _cerrarFicha(id);
    control.marcarGuia(id);
    return;
  }
  _fichaAnotada.add(id);
  control.anotarGuia(id, 'ficha');
  guiaReabierta.value = {...guiaReabierta.value, id};
}

/// El botón ? de la fila del alquilable: abre (o cierra) su ficha.
class BotonGuiaAlquiler extends StatelessWidget {
  const BotonGuiaAlquiler({super.key, required this.control, required this.id});

  final ControlImperio control;
  final String id;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: guiaReabierta,
      builder: (context, abiertas, _) {
        final abierta = guiaAbierta(control.imperio, id);
        return Semantics(
          button: true,
          label: tr('Qué hace', 'What it does'),
          child: SizedBox(
            width: 30,
            height: 30,
            child: OutlinedButton(
              key: Key('guia_$id'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 30),
                backgroundColor: abierta ? acento : null,
                foregroundColor: abierta ? acentoTexto : p.texto,
                side: BorderSide(color: abierta ? acento : p.borde),
              ),
              onPressed: () => alternarGuia(control, id),
              child: Text('?', style: numeros(context, tamano: 14, weight: FontWeight.w900, color: abierta ? acentoTexto : p.texto)),
            ),
          ),
        );
      },
    );
  }
}

/// La ficha de qué hace el alquilable [objeto], dentro de su fila de la tienda. Sale sola mientras no la entendió
/// (y la anota una vez), o con el ?. [alIr]: alquilar desde la ficha (null si no alcanza: no hay botón); [precioIr] va
/// en ese botón.
class GuiaAlquiler extends StatelessWidget {
  const GuiaAlquiler({super.key, required this.control, required this.objeto, required this.ahora, this.alIr, this.precioIr});

  final ControlImperio control;
  final Objeto objeto;
  final int ahora;
  final VoidCallback? alIr;
  final String? precioIr;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: guiaReabierta,
      builder: (context, _, _) {
        final im = control.imperio;
        final id = objeto.id;
        if (!guiaAbierta(im, id)) return const SizedBox.shrink();
        if (!im.partida.guiaVista.contains(id) && _fichaAnotada.add(id)) control.anotarGuia(id, 'ficha');
        return TarjetaGuiaAlquiler(
          objeto: objeto,
          textos: textosGuia(im, id, ahora),
          precioIr: precioIr,
          alEntendido: () {
            control.anotarGuia(id, 'entendido');
            _cerrarFicha(id);
            control.marcarGuia(id);
          },
          alIr: alIr == null
              ? null
              : () {
                  control.anotarGuia(id, 'ir');
                  _cerrarFicha(id);
                  control.marcarGuia(id);
                  alIr!();
                },
        );
      },
    );
  }
}

/// La tarjeta de la ficha (sin estado): emoji, nombre, qué hace, el ejemplo y los botones ENTENDIDO y ALQUILAR.
class TarjetaGuiaAlquiler extends StatelessWidget {
  const TarjetaGuiaAlquiler({super.key, required this.objeto, required this.textos, required this.alEntendido, this.alIr, this.precioIr});

  final Objeto objeto;
  final ({String que, String ejemplo}) textos;
  final VoidCallback alEntendido;
  final VoidCallback? alIr;
  final String? precioIr;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final quieto = movimiento(context) == Movimiento.nada;
    // El amarillo como letra solo se lee sobre fondo oscuro; en claro el rótulo va en gris y el ejemplo sobre amarillo.
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final tarjeta = Container(
      key: Key('guia_ficha_${objeto.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.fondo, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Emoji(objeto.emoji, tamano: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Qué hace ${objeto.nombreEs}', 'What ${objeto.nombreEn} does').toUpperCase(),
                    style: numeros(context, tamano: 11, weight: FontWeight.w900, color: oscuro ? acento : p.textoSuave)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(textos.que, style: TextStyle(fontWeight: FontWeight.w700, color: p.texto)),
          if (textos.ejemplo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: acento, borderRadius: BorderRadius.circular(radio)),
              child: TextoConEmojis(textos.ejemplo, style: numeros(context, tamano: 13, weight: FontWeight.w800, color: acentoTexto)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: Key('guia_entendido_${objeto.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: p.texto, side: BorderSide(color: p.borde)),
                  onPressed: alEntendido,
                  child: Text(tr('ENTENDIDO', 'GOT IT'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              if (alIr != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    key: Key('guia_ir_${objeto.id}'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: acento, foregroundColor: acentoTexto),
                    onPressed: alIr,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(precioIr == null ? tr('ALQUILAR', 'RENT') : '${tr('ALQUILAR', 'RENT')} · $precioIr',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    if (quieto) return tarjeta;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, v, hijo) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: hijo)),
      child: tarjeta,
    );
  }
}

// ---------- Empujones en la pantalla ----------

/// Un empujón: [clave] va a `Partida.guiaVista` al mostrarse; [id] es el alquilable; [tienda]: lleva botón VER (abre
/// la tienda). Sin tienda es el del recién alquilado: va con su ficha resaltada en la tira.
typedef Empujon = ({String clave, String id, String emoji, String texto, bool tienda});

/// Decide qué empujón toca (estado de esta sesión: los pujos a mano y lo que ya se había alquilado al empezar).
class EmpujonesAlquiler {
  final List<int> _pujos = [];
  Partida? _partida;
  Set<String> _usadosAlEmpezar = {};

  /// Un pujo a mano en [ahora] (ms).
  void pujo(int ahora) {
    _pujos.add(ahora);
    _pujos.removeWhere((t) => ahora - t > msVentanaPujos);
  }

  /// Puja rápido a mano: [pujosRapidos] o más en los últimos [msVentanaPujos].
  bool pujaRapido(int ahora) => _pujos.where((t) => ahora - t <= msVentanaPujos).length >= pujosRapidos;

  /// El empujón que toca ahora, o null. No marca nada: el que lo muestra lo pone en `guiaVista` con su [Empujon.clave].
  Empujon? siguiente(Imperio im, int ahora) {
    final p = im.partida;
    if (!identical(p, _partida)) {
      _partida = p;
      _usadosAlEmpezar = {...p.alquiladosUsados};
    }
    final vista = p.guiaVista;
    // Primer alquiler de algo (en esta sesión): ya está trabajando.
    for (final o in objetos) {
      if (o.tipo != TipoObjeto.alquilable || _usadosAlEmpezar.contains(o.id) || vista.contains('trabaja_${o.id}')) continue;
      if (!im.alquiladoActivo(o.id, ahora)) continue;
      return (
        clave: 'trabaja_${o.id}',
        id: o.id,
        emoji: o.emoji,
        texto: tr('Ya está trabajando: míralo en la poceta', 'It is already working: look at the toilet'),
        tienda: false,
      );
    }
    final a = p.atasco;
    if (a != null &&
        ahora - a.desde > msAtascoEmpujon &&
        !vista.contains('empujon_robot') &&
        im.objetoAbierto('robot') &&
        !p.alquiladosUsados.contains('robot') &&
        !im.robotActivo(ahora) &&
        !im.alquiladoActivo('robot_turbo', ahora)) {
      return (
        clave: 'empujon_robot',
        id: 'robot',
        emoji: '🤖',
        texto: tr('¿Atascado? El Robot destapa solo cada Atasco. Lo alquilas en Objetos.', 'Clogged? The Robot unclogs every Clog by itself. Rent it in Items.'),
        tienda: true,
      );
    }
    if (!vista.contains('empujon_primo') &&
        im.objetoAbierto('primo') &&
        !p.alquiladosUsados.contains('primo') &&
        !im.alquiladoActivo('primo', ahora) &&
        pujaRapido(ahora)) {
      return (
        clave: 'empujon_primo',
        id: 'primo',
        emoji: '👦',
        texto: tr('Un Primo puja ${pujosPrimo.round()} veces por segundo por ti. Lo alquilas en Objetos.',
            'A Cousin pushes ${pujosPrimo.round()} times per second for you. Rent one in Items.'),
        tienda: true,
      );
    }
    return null;
  }
}

/// El empujón en pantalla: se quita tocándolo o deslizándolo. [alVer] (si va) abre la tienda.
class TarjetaEmpujon extends StatelessWidget {
  const TarjetaEmpujon(this.empujon, {super.key, required this.alCerrar, this.alVer});

  final Empujon empujon;
  final VoidCallback alCerrar;
  final VoidCallback? alVer;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Dismissible(
      key: Key('empujon_${empujon.clave}'),
      onDismissed: (_) => alCerrar(),
      child: GestureDetector(
        onTap: alCerrar,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
          child: Row(
            children: [
              Emoji(empujon.emoji, tamano: 22),
              const SizedBox(width: 10),
              Expanded(child: TextoConEmojis(empujon.texto, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto))),
              if (alVer != null)
                TextButton(
                  key: Key('empujon_ver_${empujon.id}'),
                  onPressed: alVer,
                  child: Text(tr('VER', 'SEE'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
