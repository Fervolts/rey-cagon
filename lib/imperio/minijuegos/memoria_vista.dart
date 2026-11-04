// Memoria del rollo: tres niveles seguidos (4x3, 4x4, 5x4) con vista previa, racha con multiplicador, papel que se
// gasta y cartas especiales. Lógica en memoria_logica.dart, carta y chispas en memoria_carta.dart.
// Un solo reloj (RelojJuego) mueve el juego y todos los efectos; con Movimiento.nada no se anima nada.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'marco.dart';
import 'memoria_carta.dart';
import 'memoria_logica.dart';

class VistaMemoria extends StatefulWidget {
  const VistaMemoria({super.key, required this.alTerminar, this.partida, this.mov});
  final AlTerminarJuego alTerminar;

  /// Solo para pruebas.
  final PartidaMemoria? partida;

  /// Cuánto se anima. Si no llega, se lee del teléfono.
  final Movimiento? mov;

  @override
  State<VistaMemoria> createState() => _VistaMemoriaState();
}

class _Flotante {
  _Flotante(this.x, this.y, this.texto, this.grande);
  final double x, y;
  final String texto;
  final bool grande;
  double t = 0;
}

class _VistaMemoriaState extends State<VistaMemoria> with SingleTickerProviderStateMixin {
  late final PartidaMemoria _pa = widget.partida ?? PartidaMemoria();
  late final RelojJuego _reloj;
  final _sw = Stopwatch();
  final _azar = Random();
  Movimiento _mov = Movimiento.completo;

  // Estado visual por carta (se rehace en cada nivel).
  List<double> _giro = [], _pop = [], _sacude = [], _marca = [], _entrada = [], _retraso = [];
  final List<Chispa> _chispas = [];
  final List<_Flotante> _flotantes = [];

  // Tablero en pantalla, para saber dónde nace cada chispa.
  double _lado = 0, _sep = 8, _ox = 0, _oy = 0;

  bool _previaAntes = false, _destapaAntes = false;
  double _pulsoMult = 1, _tiempo = 0;
  String? _aviso;
  double _avisoResta = 0;

  /// Fiesta al cerrar un nivel, antes del resumen.
  double _fiesta = 0;
  bool _entreNiveles = false, _acabo = false;
  double _tResumen = 0;

  // Lo del nivel que acaba de cerrar, para el resumen.
  JuegoMemoria? _cerrado;

  @override
  void initState() {
    super.initState();
    _reloj = RelojJuego(this, _paso);
    _armarNivel();
    _sw.start();
    _reloj.arrancar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mov = widget.mov ?? movimiento(context);
  }

  bool get _anima => _mov != Movimiento.nada;
  double get _durGiro => _mov == Movimiento.completo ? 0.24 : 0.16;

  void _armarNivel() {
    final j = _pa.juego;
    final n = j.cartas.length;
    _giro = [for (var i = 0; i < n; i++) j.seVe(i) ? 1.0 : 0.0];
    _pop = List.filled(n, 1.0);
    _sacude = List.filled(n, 1.0);
    _marca = List.filled(n, 1.0);
    _retraso = List.filled(n, 0.0);
    final cols = j.nivel.columnas;
    _entrada = [for (var i = 0; i < n; i++) _mov == Movimiento.completo ? -((i % cols) + (i ~/ cols)) * 0.035 : 1.0];
    _chispas.clear();
    _flotantes.clear();
    _previaAntes = j.enPrevia;
    _destapaAntes = false;
    _pulsoMult = 1;
    _avisar(j.enPrevia ? null : tr('Toca dos cartas', 'Tap two cards'), 1.6);
  }

  void _avisar(String? texto, double segundos) {
    _aviso = texto;
    _avisoResta = texto == null ? 0 : segundos;
  }

  /// Retraso en ola (de la esquina de arriba a la izquierda) para voltear todo el tablero.
  void _ola() {
    final cols = _pa.juego.nivel.columnas;
    for (var i = 0; i < _retraso.length; i++) {
      _retraso[i] = _mov == Movimiento.completo ? ((i % cols) + (i ~/ cols)) * 0.03 : 0;
    }
  }

  void _paso(double dt) {
    _tiempo += dt;
    if (_entreNiveles) {
      _tResumen += dt;
      if (!_anima || _tResumen > 3) _reloj.parar();
      setState(() {});
      return;
    }
    final j = _pa.juego;
    if (!_acabo && _fiesta <= 0) j.avanzar(dt);

    // Se acabó la vista previa o el destapador: las cartas se tapan en ola.
    if (_previaAntes && !j.enPrevia) {
      _ola();
      _avisar(tr('¡A buscar!', 'Go!'), 1.0);
      // sonido: fin de la vista previa (barajeo corto)
    }
    if (_destapaAntes && !j.destapando) _ola();
    _previaAntes = j.enPrevia;
    _destapaAntes = j.destapando;

    _animarCartas(dt);
    _animarEfectos(dt);

    if (_avisoResta > 0) {
      _avisoResta -= dt;
      if (_avisoResta <= 0) _aviso = null;
    }

    if (_fiesta > 0) {
      _fiesta -= dt;
      if (_fiesta <= 0) _cerrarNivel();
    } else if (j.terminado && !_acabo && !_entreNiveles) {
      _empezarFiesta();
    }
    setState(() {});
  }

  void _animarCartas(double dt) {
    final j = _pa.juego;
    final paso = _anima ? dt / _durGiro : 1.0;
    for (var i = 0; i < j.cartas.length; i++) {
      final meta = j.seVe(i) ? 1.0 : 0.0;
      if (_retraso[i] > 0 && meta == 0) {
        _retraso[i] -= dt;
      } else {
        _retraso[i] = 0;
        if (_giro[i] < meta) {
          _giro[i] = min(meta, _giro[i] + paso);
        } else if (_giro[i] > meta) {
          _giro[i] = max(meta, _giro[i] - paso);
        }
      }
      if (_pop[i] < 1) _pop[i] = min(1, _pop[i] + dt / 0.32);
      if (_sacude[i] < 1) _sacude[i] = min(1, _sacude[i] + dt / 0.4);
      if (_marca[i] < 1) _marca[i] = min(1, _marca[i] + dt / 1.4);
      if (_entrada[i] < 1) _entrada[i] = min(1, _entrada[i] + dt / 0.28);
    }
  }

  void _animarEfectos(double dt) {
    _chispas.removeWhere((c) => !c.avanzar(dt));
    for (final f in _flotantes) {
      f.t += dt / 0.8;
    }
    _flotantes.removeWhere((f) => f.t >= 1);
    if (_pulsoMult < 1) _pulsoMult = min(1, _pulsoMult + dt / 0.3);
  }

  Offset _centro(int i) {
    final cols = _pa.juego.nivel.columnas;
    return Offset(_ox + (i % cols) * (_lado + _sep) + _lado / 2, _oy + (i ~/ cols) * (_lado + _sep) + _lado / 2);
  }

  void _chispear(int i, int cuantas, double fuerza) {
    if (_mov != Movimiento.completo || _lado <= 0) return;
    final p = paleta(context);
    final c = _centro(i);
    for (var k = 0; k < cuantas; k++) {
      final a = _azar.nextDouble() * 2 * pi;
      final v = fuerza * (0.4 + 0.6 * _azar.nextDouble());
      final color = k % 3 == 0 ? p.texto : p.acento;
      _chispas.add(Chispa(c.dx, c.dy, cos(a) * v, sin(a) * v - fuerza * 0.5, 3 + _azar.nextDouble() * 4, color, 0.45 + _azar.nextDouble() * 0.35));
    }
  }

  void _tocar(int i) {
    final j = _pa.juego;
    if (_fiesta > 0 || _acabo || !j.toca(i)) return;
    final jg = j.jugada!;
    switch (jg.tipo) {
      case TipoJugada.primera:
        // sonido: voltear carta (papel)
        break;
      case TipoJugada.acierto:
        // sonido: acierto, más agudo cuanto más larga la racha (jg.multiplicador)
        vibracionSuave();
        _pop[jg.a] = -0.08;
        _pop[jg.b] = 0;
        _chispear(jg.b, 6 + 3 * jg.multiplicador, 160 + 40.0 * jg.multiplicador);
        if (_anima && _lado > 0) {
          final c = _centro(jg.b);
          final texto = jg.multiplicador > 1 ? '+${jg.puntos} x${jg.multiplicador}' : '+${jg.puntos}';
          _flotantes.add(_Flotante(c.dx, c.dy - _lado * 0.2, texto, jg.multiplicador >= multiplicadorMaximo));
        }
        if (jg.multiplicador > 1) _pulsoMult = 0;
        if (jg.destapa) {
          // sonido: destapador (chupón)
          _avisar(tr('¡Destapado! Mira bien', 'Unclogged! Look closely'), JuegoMemoria.tiempoDestapa);
        } else if (jg.multiplicador == multiplicadorMaximo && j.racha == multiplicadorMaximo) {
          _avisar(tr('¡Racha al máximo!', 'Max streak!'), 1.2);
        }
        break;
      case TipoJugada.exploracion:
        break;
      case TipoJugada.fallo:
        // sonido: fallo (pedo corto)
        _sacude[jg.a] = 0;
        _sacude[jg.b] = 0;
        _avisar(tr('Esa ya la habías visto', 'You had seen that one'), 1.0);
        break;
    }
    final cambio = jg.cambio;
    if (cambio != null) {
      // sonido: cucaracha corriendo
      _marca[cambio.$1] = 0;
      _marca[cambio.$2] = 0;
      _avisar(tr('¡La cucaracha movió dos cartas!', 'The cockroach moved two cards!'), 1.6);
    }
    setState(() {});
  }

  void _empezarFiesta() {
    final j = _pa.juego;
    // sonido: nivel superado
    vibracionSuave();
    _fiesta = switch (_mov) { Movimiento.completo => 0.9, Movimiento.simple => 0.5, Movimiento.nada => 0.3 };
    if (_anima) {
      final cols = j.nivel.columnas;
      for (var i = 0; i < j.cartas.length; i++) {
        _pop[i] = -((i % cols) + (i ~/ cols)) * 0.05;
      }
    }
    for (var i = 0; i < j.cartas.length; i += 2) {
      _chispear(i, 5, 220);
    }
  }

  void _cerrarNivel() {
    _fiesta = 0;
    _sw.stop(); // la fiesta cuenta como partida; el resumen entre niveles no
    if (_pa.terminada) {
      _acabo = true;
      _reloj.parar();
      widget.alTerminar(_pa.puntos, _sw.elapsedMilliseconds);
      return;
    }
    _cerrado = _pa.juego;
    _entreNiveles = true;
    _tResumen = 0;
    if (!_anima) _reloj.parar();
  }

  void _siguiente() {
    if (!_pa.siguiente()) return;
    _entreNiveles = false;
    _cerrado = null;
    _armarNivel();
    _sw.start();
    _reloj.arrancar();
    setState(() {});
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Column(children: [
      _hud(p),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: _entreNiveles && _cerrado != null ? SingleChildScrollView(child: _resumen(p, _cerrado!)) : _tablero(p),
        ),
      ),
    ]);
  }

  Widget _hud(Paleta p) {
    final j = _pa.juego;
    final mult = j.multiplicadorSiguiente;
    final frac = j.papelFraccion.clamp(0.0, 1.0);
    final poco = frac < 0.25 && !j.enPrevia;
    final parpadeo = poco && _mov == Movimiento.completo ? 0.55 + 0.45 * cos(_tiempo * 10) : 1.0;
    final escalaMult = _anima && _pulsoMult < 1 ? 1 + 0.25 * sin(pi * _pulsoMult) : 1.0;
    String? aviso = _aviso;
    if (j.enPrevia) aviso = tr('Memoriza… ${j.previaRestante.toStringAsFixed(1)}', 'Memorize… ${j.previaRestante.toStringAsFixed(1)}');
    if (j.destapando) aviso = tr('¡Destapado! Mira bien', 'Unclogged! Look closely');
    if (_entreNiveles) aviso = null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Rotulo(tr('Nivel ${_pa.nivel + 1}/${nivelesMemoria.length}', 'Level ${_pa.nivel + 1}/${nivelesMemoria.length}')),
          const Spacer(),
          Text('${_pa.puntosEnVivo}', key: const Key('memoria_puntos'), style: numeros(context, tamano: 22, weight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Emoji(emojiReverso, tamano: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
              padding: const EdgeInsets.all(1),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: frac,
                heightFactor: 1,
                child: Opacity(opacity: parpadeo, child: ColoredBox(color: poco ? p.texto : p.acento)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Transform.scale(
            scale: escalaMult,
            child: Container(
              key: const Key('memoria_multiplicador'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: mult > 1 ? p.acento : null,
                border: Border.all(color: mult > 1 ? p.acento : p.borde),
                borderRadius: BorderRadius.circular(radio),
              ),
              child: Text('x$mult', style: numeros(context, tamano: 13, weight: FontWeight.w900, color: mult > 1 ? p.acentoTexto : p.textoSuave)),
            ),
          ),
          const SizedBox(width: 10),
          Text(tr('Fallos ${_pa.erroresTotal}', 'Misses ${_pa.erroresTotal}'),
              key: const Key('memoria_errores'), style: numeros(context, tamano: 12, color: p.textoSuave)),
        ]),
        SizedBox(
          height: 22,
          child: Center(
            child: aviso == null
                ? null
                : Text(aviso, key: const Key('memoria_aviso'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.texto)),
          ),
        ),
      ]),
    );
  }

  Widget _tablero(Paleta p) {
    final j = _pa.juego;
    final n = j.nivel;
    return LayoutBuilder(builder: (context, c) {
      const sep = 8.0;
      final w = (c.maxWidth - sep * (n.columnas - 1)) / n.columnas;
      final h = (c.maxHeight - sep * (n.filas - 1)) / n.filas;
      final lado = max(1.0, min(w, h));
      _lado = lado;
      _sep = sep;
      _ox = (c.maxWidth - (lado * n.columnas + sep * (n.columnas - 1))) / 2;
      _oy = (c.maxHeight - (lado * n.filas + sep * (n.filas - 1))) / 2;
      return Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < j.cartas.length; i++)
          Positioned(
            left: _ox + (i % n.columnas) * (lado + sep),
            top: _oy + (i ~/ n.columnas) * (lado + sep),
            width: lado,
            height: lado,
            child: Listener(
              key: Key('carta_$i'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _tocar(i),
              child: CartaMemoriaVista(
                emoji: j.cartas[i].emoji,
                lado: lado,
                mov: _mov,
                giro: _giro[i],
                hecha: j.cartas[i].estado == EstadoCarta.hecha,
                pop: _pop[i].clamp(0.0, 1.0),
                sacude: _sacude[i],
                marca: _marca[i],
                entrada: _entrada[i].clamp(0.0, 1.0),
              ),
            ),
          ),
        if (_chispas.isNotEmpty)
          Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: ChispasPintor(_chispas))))),
        for (final f in _flotantes)
          Positioned(
            left: f.x - 60,
            top: f.y - 14 - 36 * Curves.easeOut.transform(f.t),
            width: 120,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - f.t).clamp(0.0, 1.0),
                child: Text(
                  f.texto,
                  textAlign: TextAlign.center,
                  style: numeros(context, tamano: f.grande ? 20 : 16, weight: FontWeight.w900, color: f.grande ? p.acento : p.texto),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  /// Resumen entre niveles: cada línea entra un poco después de la anterior.
  Widget _resumen(Paleta p, JuegoMemoria j) {
    final t = _anima ? _tResumen : 99.0;
    double aparece(int k) => ((t - k * 0.12) / 0.2).clamp(0.0, 1.0);
    Widget linea(int k, String texto, String valor, {bool fuerte = false}) {
      final a = aparece(k);
      return Opacity(
        opacity: a,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - a)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(texto, style: TextStyle(color: fuerte ? p.texto : p.textoSuave, fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500))),
              Text(valor, style: numeros(context, tamano: fuerte ? 18 : 14, weight: fuerte ? FontWeight.w900 : FontWeight.w600)),
            ]),
          ),
        ),
      );
    }

    final prox = _pa.proximo;
    final cuenta = (j.puntos * aparece(6)).round();
    final novedad = prox == null
        ? null
        : prox.cucaracha
            ? (emojiCucaracha, tr('Llega la cucaracha: si sale en una pareja equivocada, cambia de sitio dos cartas.',
                'Here comes the cockroach: in a wrong pair it swaps two hidden cards.'))
            : prox.destapador
                ? (emojiDestapador, tr('Llega el destapador: al emparejarlo ves todas las cartas un segundo.',
                    'Here comes the plunger: match it to see every card for a second.'))
                : null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Rotulo(tr('Nivel ${_pa.nivel + 1} superado', 'Level ${_pa.nivel + 1} cleared')),
            const SizedBox(height: 8),
            linea(0, tr('Parejas', 'Pairs'), '${j.puntosParejas}'),
            linea(1, tr('Fallos (${j.errores})', 'Misses (${j.errores})'), j.descuentoFallos > 0 ? '−${j.descuentoFallos}' : '0'),
            linea(2, tr('Papel que sobró', 'Paper left'), '+${j.bonusPapel}'),
            linea(3, tr('Sin fallos', 'No misses'), '+${j.bonusLimpio}'),
            linea(4, tr('Mejor racha', 'Best streak'), '${j.mejorRacha}'),
            Opacity(opacity: aparece(5), child: Divider(height: 14, color: p.borde)),
            linea(6, tr('Este nivel', 'This level'), '$cuenta', fuerte: true),
            linea(7, tr('Total', 'Total'), '${_pa.puntos}'),
            if (novedad != null) ...[
              const SizedBox(height: 10),
              Opacity(
                opacity: aparece(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(border: Border.all(color: p.acento), borderRadius: BorderRadius.circular(radio)),
                  child: Row(children: [
                    Emoji(novedad.$1, tamano: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text(novedad.$2, style: TextStyle(fontSize: 13, color: p.texto))),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('memoria_siguiente'),
              onPressed: _siguiente,
              child: Text(tr('SIGUIENTE NIVEL', 'NEXT LEVEL')),
            ),
          ]),
        ),
      ),
    );
  }
}
