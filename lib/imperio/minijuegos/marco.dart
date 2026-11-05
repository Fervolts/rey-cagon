// Marco común de los minijuegos: instrucción de una línea, el juego, y la pantalla de fin (puntos, récord, MJ y lo que queda hoy).
// El premio lo decide el servidor (control.terminarMinijuego); aquí solo se muestra.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import '../control.dart';
import '../formato.dart';
import '../telemetria.dart';
import 'datos.dart';
import 'destapa_vista.dart';
import 'memoria_vista.dart';
import 'ranking_vista.dart';
import 'sonido.dart';
import 'tuberia_vista.dart';

/// Lo que llama cada juego al acabar: puntos y milisegundos reales jugados.
typedef AlTerminarJuego = void Function(int puntos, int ms);

/// Reloj de un juego: un Ticker que da el tiempo entre cuadros (con tope, para que un tirón no atraviese un codo).
class RelojJuego {
  RelojJuego(TickerProvider vsync, this.alTic) {
    _ticker = vsync.createTicker(_tic);
  }
  final void Function(double dt) alTic;
  late final Ticker _ticker;
  Duration _antes = Duration.zero;
  bool _corre = false;

  void arrancar() {
    if (_corre) return;
    _corre = true;
    _antes = Duration.zero;
    _ticker.start();
  }

  void parar() {
    _corre = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _tic(Duration t) {
    final dt = _antes == Duration.zero ? 0.0 : (t - _antes).inMicroseconds / 1e6;
    _antes = t;
    alTic(dt.clamp(0.0, 0.05));
  }

  void dispose() {
    _corre = false;
    _ticker.dispose();
  }
}

/// Vibración suave. Nunca lanza (en tests o en aparatos sin motor no hace nada).
void vibracionSuave() {
  try {
    unawaited(HapticFeedback.selectionClick());
  } catch (_) {}
}

class DatosJuego {
  const DatosJuego(this.id, this.emoji, this.es, this.en, this.instruccionEs, this.instruccionEn);
  final String id, emoji, es, en, instruccionEs, instruccionEn;
}

const juegosAbiertosDatos = <String, DatosJuego>{
  'tuberia': DatosJuego('tuberia', '🚰', 'Tubería Express', 'Pipe Express',
      'Mantén en las bajadas para agarrar velocidad, suelta en las subidas para volar. Cae en una BAJADA o arriba de la loma, no abajo de una subida. Las rampas te lanzan. Que no te alcance el Atasco.',
      "Hold on downhills to build speed, release on uphills to fly. Land on a DOWNHILL or on top of a hill, not at the bottom of an uphill. Ramps launch you. Don't let the Clog catch you."),
  'destapa': DatosJuego('destapa', '🪠', 'Destapa', 'Unclog', 'Toca los inodoros tapados hasta destaparlos. Patito: desliza arriba. Celular: mantén. Que no se desborden.', "Tap clogged toilets until they unclog. Duck: swipe up. Phone: hold. Don't let them overflow."),
  'memoria': DatosJuego('memoria', '👑', 'Fusión real', 'Royal Merge', 'Arrastra para apuntar y suelta. Junta dos iguales para crecer hasta el Rey; no pases la línea roja.', "Drag to aim and release. Merge two of a kind up to the King; don't cross the red line."),
};

/// Una partida completa: instrucción, juego y fin.
class PantallaMinijuego extends StatefulWidget {
  const PantallaMinijuego({super.key, required this.juego, this.control});
  final String juego;
  final ControlImperio? control;

  @override
  State<PantallaMinijuego> createState() => _PantallaMinijuegoState();
}

enum _Fase { intro, jugando, fin }

class _PantallaMinijuegoState extends State<PantallaMinijuego> {
  _Fase _fase = _Fase.intro;
  int _vuelta = 0;
  ResultadoMinijuego? _res;
  double _mj = 0;
  int _puntos = 0;
  bool _guardando = false;

  ControlImperio? get _c => widget.control ?? ControlImperio.vivo;
  DatosJuego get _d => juegosAbiertosDatos[widget.juego]!;

  @override
  void initState() {
    super.initState();
    unawaited(Sonido.leerPreferencia());
  }

  @override
  void dispose() {
    unawaited(Sonido.pararMusica());
    super.dispose();
  }

  void _jugar() {
    Telemetria.instancia.registrar('minijuego_inicia', {'juego': widget.juego});
    setState(() {
      _fase = _Fase.jugando;
      _res = null;
      _mj = 0;
      _vuelta++;
    });
  }

  Future<void> _fin(int puntos, int ms) async {
    if (_fase == _Fase.fin) return;
    unawaited(Sonido.pararMusica());
    setState(() {
      _fase = _Fase.fin;
      _puntos = puntos;
      _guardando = puntos > 0;
      _res = null;
    });
    if (puntos <= 0) return;
    final c = _c;
    if (c == null) {
      setState(() {
        _res = ResultadoMinijuego.sinRed(puntos);
        _guardando = false;
      });
      return;
    }
    final (r, mj) = await c.terminarMinijuego(widget.juego, puntos, ms);
    if (!mounted) return;
    setState(() {
      _res = r;
      _mj = mj;
      _guardando = false;
    });
  }

  Widget _juego() {
    final mov = movimientoDe(context);
    return switch (widget.juego) {
      'tuberia' => VistaTuberia(key: ValueKey('t$_vuelta'), alTerminar: _fin, mov: mov),
      'destapa' => VistaDestapa(key: ValueKey('d$_vuelta'), alTerminar: _fin, mov: mov),
      _ => VistaMemoria(key: ValueKey('m$_vuelta'), alTerminar: _fin, mov: mov),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(_d.es, _d.en)),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: Sonido.silencio,
            builder: (context, mudo, _) => IconButton(
              key: const Key('minijuego_sonido'),
              tooltip: mudo ? tr('Activar sonido', 'Sound on') : tr('Silenciar', 'Mute'),
              icon: Icon(mudo ? Icons.volume_off_outlined : Icons.volume_up_outlined),
              onPressed: Sonido.alternarSilencio,
            ),
          ),
          IconButton(
            key: const Key('minijuego_ranking'),
            tooltip: tr('Ranking de la semana', 'Weekly ranking'),
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaRankingMinijuego(juego: widget.juego, control: _c))),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (_fase) {
          _Fase.intro => _intro(p),
          _Fase.jugando => _juego(),
          _Fase.fin => _finVista(p),
        },
      ),
    );
  }

  Widget _intro(Paleta p) {
    final r = _c?.minijuegos;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Emoji(_d.emoji, tamano: 56),
          const SizedBox(height: 16),
          Text(tr(_d.instruccionEs, _d.instruccionEn), textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.texto)),
          const SizedBox(height: 10),
          Text(lineaHoy(r), key: const Key('minijuego_hoy'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textoSuave)),
          const SizedBox(height: 20),
          FilledButton(key: const Key('minijuego_jugar'), onPressed: _jugar, child: Text(tr('JUGAR', 'PLAY'))),
        ]),
      ),
    );
  }

  Widget _finVista(Paleta p) {
    final r = _res;
    final c = _c;
    final res = c?.minijuegos;
    final motivo = textoMotivoMinijuego(r?.motivo);
    final record = r != null && r.record > 0 ? r.record : (res?.juegos[widget.juego]?.record ?? 0);
    Widget fila(String k, String v, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: p.textoSuave))),
            Text(v, key: key, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
          ]),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('FIN DE LA PARTIDA', 'GAME OVER'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.textoSuave)),
            const SizedBox(height: 8),
            Text('$_puntos', key: const Key('minijuego_puntos'), style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: p.texto)),
            Text(tr('puntos', 'points'), style: TextStyle(color: p.textoSuave)),
            if (r?.nuevoRecord == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('NUEVO RÉCORD', 'NEW RECORD'), key: const Key('minijuego_nuevo_record'), style: TextStyle(fontWeight: FontWeight.w900, color: p.acento)),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
              child: Column(children: [
                fila(tr('Tu récord', 'Your record'), '$record', key: const Key('minijuego_record')),
                if (_guardando)
                  fila(tr('MJ ganados', 'MJ earned'), '...')
                else
                  fila(tr('MJ ganados', 'MJ earned'), _mj > 0 ? '+${formatoMj(_mj, ingles: enIngles)}' : '0', key: const Key('minijuego_mj')),
                fila(tr('Premio de hoy', "Today's prize"), lineaQuedaHoy(res), key: const Key('minijuego_queda')),
              ]),
            ),
            if (motivo != null && !_guardando)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(motivo, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textoSuave))),
            if (_puntos <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(tr('Sin puntos no hay premio.', 'No points, no prize.'), style: TextStyle(fontSize: 12, color: p.textoSuave)),
              ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(key: const Key('minijuego_salir'), onPressed: () => Navigator.of(context).pop(), child: Text(tr('SALIR', 'EXIT')))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(key: const Key('minijuego_otra'), onPressed: _guardando ? null : _jugar, child: Text(tr('OTRA VEZ', 'AGAIN')))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Línea de la tarjeta y de la instrucción: cuánto puede dar hoy.
String lineaHoy(ResumenMinijuegos? r) {
  final max = r?.minutosMax ?? minutosMaxDefecto;
  if (r == null) return tr('Cada partida puede dar hasta $max min de producción.', 'Each game can give up to $max min of production.');
  if (!r.activo) return tr('Los premios están en pausa por ahora.', 'Prizes are paused for now.');
  if (r.partidasHoy >= r.topePartidas) return tr('Hoy ya no hay más premios. Puedes jugar por puntos.', 'No more prizes today. You can still play for points.');
  final p = r.puedeDarHoy;
  if (p <= 0) return tr('Hoy ya ganaste el tope (${r.topeDia} min). Puedes jugar por puntos.', "You hit today's cap (${r.topeDia} min). You can still play for points.");
  return tr('Hoy puede dar hasta $p min (te quedan ${r.restanHoy} de ${r.topeDia}).', 'Today it can give up to $p min (${r.restanHoy} of ${r.topeDia} left).');
}

/// "12 de 30 min" o similar para la pantalla de fin.
String lineaQuedaHoy(ResumenMinijuegos? r) {
  if (r == null) return '-';
  return tr('quedan ${r.restanHoy} min', '${r.restanHoy} min left');
}

/// El nivel de movimiento (tests: se puede forzar sin tocar preferencias).
Movimiento movimientoDe(BuildContext context) => movimiento(context);
