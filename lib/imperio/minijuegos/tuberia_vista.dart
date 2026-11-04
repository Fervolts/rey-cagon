// Tubería Express: el mojón baja por el desagüe; un toque cambia de carril. Lógica en tuberia_logica.dart, dibujo en
// tuberia_pintor.dart y efectos en tuberia_efectos.dart. Nada se reconstruye por cuadro salvo el mojón (un Emoji con
// Transform): el tubo lo repinta el Ticker y el marcador solo cambia cuando cambian los puntos, la racha o un letrero.
// Si la app se va al fondo, la partida se pausa (y el cronómetro también).

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'estadisticas.dart';
import 'marco.dart';
import 'tuberia_efectos.dart';
import 'tuberia_logica.dart';
import 'tuberia_pintor.dart';

class VistaTuberia extends StatefulWidget {
  const VistaTuberia({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});
  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Solo para pruebas: una partida ya armada.
  final JuegoTuberia? juego;

  @override
  State<VistaTuberia> createState() => _VistaTuberiaState();
}

List<String> _nombresZona() => [
      tr('Desagüe', 'Drain'),
      tr('Cloaca', 'Sewer'),
      tr('Colector', 'Main line'),
      tr('Túnel profundo', 'Deep tunnel'),
      tr('Recta final', 'Final stretch'),
    ];

class _VistaTuberiaState extends State<VistaTuberia> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final JuegoTuberia _j = widget.juego ?? JuegoTuberia(record: recordMinijuego('tuberia'));
  late final RelojJuego _reloj;
  late final EfectosTuberia _ef = EfectosTuberia(widget.mov);
  final _tic = _Aviso();
  final _hud = _Aviso();
  final _sw = Stopwatch();
  Timer? _cierre;
  bool _fin = false;
  bool _pausado = false;

  // Lo que muestra el marcador (para avisar solo cuando cambia).
  int _puntos = -1, _mult = 1, _racha = 0;
  PistaTuberia? _pista = PistaTuberia.toca;
  String? _banner, _bannerSub;
  bool _bannerFuerte = false;
  double _bannerHasta = 0;
  int _bannerVez = 0;
  double _gota = 0;

  // Geometría del último layout (para poner chispas donde está el mojón).
  double _x0 = 0, _tubo = 200, _yJ = 100, _pxPorM = 20;
  Paleta? _p;

  Offset get _mojon => Offset(_x0 + _tubo * (0.25 + 0.5 * _j.posicion), _yJ);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reloj = RelojJuego(this, _paso);
    _sw.start();
    _reloj.arrancar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_fin && !_pausado) {
      _pausado = true;
      _reloj.parar();
      _sw.stop();
      _hud.avisar();
    }
  }

  void _seguir() {
    _pausado = false;
    _sw.start();
    _reloj.arrancar();
    _hud.avisar();
  }

  void _paso(double dt) {
    final p = _p;
    if (!_fin) {
      _j.avanzar(dt);
      if (p != null) {
        for (final s in _j.tomarSucesos()) {
          _suceso(s, p);
        }
        // Estela: gotas que se quedan atrás, más seguidas cuanto más rápido.
        _gota += dt * _j.velocidad;
        if (_gota > 0.9) {
          _gota = 0;
          _ef.gota(_mojon + const Offset(0, -12), colorAguas.withValues(alpha: 0.7), _j.velocidad * _pxPorM * 0.35);
        }
      }
      if (_j.puntos != _puntos || _j.multiplicador != _mult || _j.racha != _racha || _j.pista != _pista) {
        _puntos = _j.puntos;
        _mult = _j.multiplicador;
        _racha = _j.racha;
        _pista = _j.pista;
        _hud.avisar();
      }
      if (_j.terminado) _terminar();
    }
    _ef.avanzar(dt);
    if (_banner != null && _ef.fase >= _bannerHasta) {
      _banner = _bannerSub = null;
      _hud.avisar();
    }
    _tic.avisar();
  }

  void _letrero(String titulo, String? sub, double segundos, {bool fuerte = false}) {
    _banner = titulo;
    _bannerSub = sub;
    _bannerFuerte = fuerte;
    _bannerHasta = _ef.fase + segundos;
    _bannerVez++;
    _hud.avisar();
  }

  void _suceso(SucesoTuberia s, Paleta p) {
    final aqui = _mojon;
    switch (s.tipo) {
      case TipoSuceso.rollo:
        // sonido: plop del rollo, más agudo con la racha
        final dorado = s.valor == 1;
        _ef.agarro();
        _ef.chispas(aqui, dorado ? p.acento : const Color(0xFFF7F3EA), dorado ? 12 : 7, fuerza: 120);
        _ef.letrero('+${s.puntos}', aqui + const Offset(26, -18), dorado ? p.acento : p.texto, tam: dorado ? 18 : 14);
      case TipoSuceso.casi:
        // sonido: roce metálico
        vibracionSuave();
        final lado = Offset(_x0 + _tubo * (0.25 + 0.5 * s.carril), _yJ);
        _ef.chispas(Offset((lado.dx + aqui.dx) / 2, _yJ), p.acento, 10, fuerza: 170);
        _ef.letrero(tr('¡CASI! +${s.puntos}', 'CLOSE! +${s.puntos}'), aqui + const Offset(0, -34), p.acento, tam: 17);
        _ef.destello(p.acento, 0.22);
        _ef.sacudir(3);
      case TipoSuceso.multiplicador:
        // sonido: subida de multiplicador (arpegio corto)
        vibracionSuave();
        _ef.chispas(aqui, p.acento, 22, fuerza: 220);
        _ef.letrero('x${s.valor}', aqui + const Offset(0, 54), p.acento, tam: 34);
        _ef.destello(p.acento, 0.4);
        _ef.sacudir(4);
      case TipoSuceso.perdido:
        if (s.valor >= 3) _ef.letrero(tr('racha rota', 'streak lost'), aqui + const Offset(0, -30), p.textoSuave, tam: 13);
      case TipoSuceso.avisoDescarga:
        // sonido: alguien jala la cadena a lo lejos
        _letrero(tr('¡VIENE UNA DESCARGA!', 'FLUSH INCOMING!'), tr('Alguien jaló la cadena', 'Someone pulled the chain'), 2.2);
      case TipoSuceso.descarga:
        // sonido: descarga del inodoro (ruido blanco que sube)
        vibracionSuave();
        _ef.sacudir(8);
        _ef.destello(colorAguas, 0.6);
        _ef.chispas(aqui, colorAguas, 18, fuerza: 200);
        _letrero(tr('¡DESCARGA!', 'FLUSH!'), tr('Más rápido · rollos dorados x2', 'Faster · golden rolls x2'), 2.4, fuerte: true);
      case TipoSuceso.finDescarga:
        break;
      case TipoSuceso.zona:
        // sonido: campanita de zona
        final nombres = _nombresZona();
        _letrero(nombres[s.valor.clamp(0, nombres.length - 1)].toUpperCase(),
            tr('Zona ${s.valor + 1} de ${nombres.length} · más rápido', 'Zone ${s.valor + 1} of ${nombres.length} · faster'), 2.0);
      case TipoSuceso.record:
        // sonido: fanfarria de récord
        vibracionSuave();
        _ef.destello(p.acento, 0.5);
        _ef.chispas(aqui, p.acento, 24, fuerza: 240);
        _letrero(tr('¡NUEVO RÉCORD!', 'NEW RECORD!'), tr('Todo lo que sigue es gloria', 'Everything from here is glory'), 2.0, fuerte: true);
      case TipoSuceso.choque:
        // sonido: splash grave contra el codo
        vibracionSuave();
        _ef.sacudir(14);
        _ef.destello(colorAguas, 0.75);
        _ef.chispas(aqui, colorAguas, 30, fuerza: 260, tam: 5);
      case TipoSuceso.meta:
        // sonido: llegada a la planta
        vibracionSuave();
        _ef.destello(p.acento, 0.8);
        _ef.chispas(aqui, p.acento, 40, fuerza: 300, tam: 4);
    }
  }

  void _terminar() {
    _fin = true;
    _sw.stop();
    _hud.avisar();
    // Un instante para ver el choque y el letrero (los efectos siguen corriendo); después se para todo y se entrega.
    final ms = switch (widget.mov) {
      Movimiento.completo => 1000,
      Movimiento.simple => 700,
      Movimiento.nada => 450,
    };
    _cierre = Timer(Duration(milliseconds: ms), () {
      _reloj.parar();
      if (mounted) widget.alTerminar(_j.puntos, _sw.elapsedMilliseconds);
    });
  }

  void _toque() {
    if (_pausado) return _seguir();
    if (_fin) return;
    _j.toque();
    // sonido: cambio de carril (swish corto)
    _ef.chispas(_mojon, (_p?.textoSuave ?? Colors.grey).withValues(alpha: 0.6), 3, fuerza: 60);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cierre?.cancel();
    _reloj.dispose();
    _tic.dispose();
    _hud.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p = paleta(context);
    return GestureDetector(
      key: const Key('tuberia_toque'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _toque(),
      child: LayoutBuilder(builder: (context, c) {
        final ancho = c.maxWidth, alto = c.maxHeight;
        final tubo = _tubo = (ancho * 0.8).clamp(160.0, 420.0);
        final x0 = _x0 = (ancho - tubo) / 2;
        final yJugador = _yJ = alto * 0.28;
        final pxPorM = _pxPorM = (alto * 0.72) / 18;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: PintorTuberia(
                    j: _j, ef: _ef, p: p, x0: x0, tubo: tubo, yJugador: yJugador, pxPorM: pxPorM, mov: widget.mov, repintar: _tic),
              ),
            ),
          ),
          AnimatedBuilder(animation: _tic, builder: (context, _) => _mojonWidget()),
          Positioned(top: 8, left: 8, right: 8, child: AnimatedBuilder(animation: _hud, builder: (context, _) => _marcador(p))),
          Positioned(
            top: 66,
            left: 16,
            right: 16,
            child: AnimatedBuilder(animation: _hud, builder: (context, _) => _bannerWidget(p)),
          ),
          Positioned(left: 16, right: 16, bottom: 22, child: AnimatedBuilder(animation: _hud, builder: (context, _) => _pistaWidget(p))),
          Positioned.fill(child: AnimatedBuilder(animation: _hud, builder: (context, _) => _capa(p))),
        ]);
      }),
    );
  }

  // El mojón: se inclina y se estira al cambiar de carril, crece al agarrar y se aplasta al chocar.
  Widget _mojonWidget() {
    const tam = 34.0;
    final pos = _mojon + _ef.sacudida;
    final completo = widget.mov == Movimiento.completo;
    final falta = _j.carril - _j.posicion; // con signo: hacia dónde va
    var sx = 1.0, sy = 1.0, ang = 0.0, op = 1.0;
    if (completo) {
      sx += 0.22 * falta.abs();
      sy -= 0.14 * falta.abs();
      ang = falta * 0.5 + sin(_ef.fase * 7) * 0.05;
    }
    final b = _ef.brinco;
    sx += 0.28 * b;
    sy += 0.28 * b;
    if (_fin && !_j.llego) {
      op = widget.mov == Movimiento.nada ? 0.4 : 0.75;
      if (widget.mov != Movimiento.nada) {
        sx = 1.55;
        sy = 0.5;
        ang = 0;
      }
    }
    return Positioned(
      left: pos.dx - tam / 2,
      top: pos.dy - tam / 2,
      child: Opacity(
        opacity: op,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(sx, sy, 1)..rotateZ(ang),
          child: const Emoji('💩', tamano: tam),
        ),
      ),
    );
  }

  Widget _caja(Paleta p, {required Widget child, bool fuerte = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: fuerte ? p.acento : p.tarjeta,
          border: Border.all(color: fuerte ? p.acento : p.borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: child,
      );

  Widget _marcador(Paleta p) {
    final record = _j.record;
    final mult = _j.multiplicador;
    final fuerte = mult > 1;
    final hecho = mult >= JuegoTuberia.multiplicadorMaximo ? JuegoTuberia.rachaPorNivel : _j.racha % JuegoTuberia.rachaPorNivel;
    final colorMult = fuerte ? p.acentoTexto : p.texto;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 92,
        child: record <= 0
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: _caja(
                  p,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('RÉCORD', 'BEST'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.textoSuave)),
                    Text('$record', style: numeros(context, tamano: 13, weight: FontWeight.w800, color: _puntos > record ? p.acento : p.texto)),
                  ]),
                ),
              ),
      ),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${max(0, _puntos)}', key: const Key('tuberia_metros'), style: numeros(context, tamano: 28, weight: FontWeight.w900, color: p.texto)),
          Text('${_j.distancia.floor()} m', style: numeros(context, tamano: 11, weight: FontWeight.w700, color: p.textoSuave)),
        ]),
      ),
      SizedBox(
        width: 92,
        child: Align(
          alignment: Alignment.centerRight,
          child: _caja(
            p,
            fuerte: fuerte,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Emoji('🧻', tamano: 14),
                const SizedBox(width: 4),
                Text('x$mult', style: numeros(context, tamano: 16, weight: FontWeight.w900, color: colorMult)),
              ]),
              const SizedBox(height: 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < JuegoTuberia.rachaPorNivel; i++)
                  Container(
                    width: 8,
                    height: 4,
                    margin: const EdgeInsets.only(left: 2),
                    decoration: BoxDecoration(
                      color: i < hecho ? colorMult : Colors.transparent,
                      border: Border.all(color: colorMult.withValues(alpha: 0.6)),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _bannerWidget(Paleta p) {
    final t = _banner;
    Widget hijo = const SizedBox.shrink(key: ValueKey('nada'));
    if (t != null) {
      hijo = Center(
        key: ValueKey(_bannerVez),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _bannerFuerte ? p.acento : p.fondo,
            border: Border.all(color: _bannerFuerte ? p.acento : p.bordeFuerte),
            borderRadius: BorderRadius.circular(radio),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1, color: _bannerFuerte ? p.acentoTexto : p.texto)),
            if (_bannerSub != null)
              Text(_bannerSub!,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: _bannerFuerte ? p.acentoTexto : p.textoSuave)),
          ]),
        ),
      );
    }
    if (widget.mov == Movimiento.nada) return hijo;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: widget.mov == Movimiento.completo ? 180 : 120),
      transitionBuilder: (child, a) => widget.mov == Movimiento.completo
          ? FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child))
          : FadeTransition(opacity: a, child: child),
      child: hijo,
    );
  }

  Widget _pistaWidget(Paleta p) {
    final texto = switch (_fin ? null : _pista) {
      PistaTuberia.toca => tr('Toca para cambiar de carril · agarra los rollos', 'Tap to switch lanes · grab the rolls'),
      PistaTuberia.esquiva => tr('¡Un codo en tu carril! Toca para esquivarlo', 'A bend in your lane! Tap to dodge it'),
      PistaTuberia.racha => tr('Rollos seguidos suben el multiplicador', 'Rolls in a row raise the multiplier'),
      null => null,
    };
    if (texto == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: p.fondo, border: Border.all(color: p.acento), borderRadius: BorderRadius.circular(radio)),
        child: Text(texto, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.texto)),
      ),
    );
  }

  // Pausa o final: un cartel encima de todo.
  Widget _capa(Paleta p) {
    if (_pausado) {
      return ColoredBox(
        color: p.fondo.withValues(alpha: 0.8),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('PAUSA', 'PAUSED'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2, color: p.texto)),
            const SizedBox(height: 6),
            Text(tr('Toca para seguir', 'Tap to continue'), style: TextStyle(fontSize: 14, color: p.textoSuave)),
          ]),
        ),
      );
    }
    if (!_fin) return const IgnorePointer(child: SizedBox.expand());
    final record = _j.record, puntos = _j.puntos;
    final String titulo;
    String? sub;
    var fuerte = true;
    if (_j.llego) {
      titulo = tr('¡LLEGASTE A LA PLANTA!', 'YOU REACHED THE PLANT!');
      sub = tr('${JuegoTuberia.meta.round()} m sin atascarte', '${JuegoTuberia.meta.round()} m without a clog');
    } else if (record > 0 && puntos > record) {
      titulo = tr('¡NUEVO RÉCORD!', 'NEW RECORD!');
    } else if (record > 0 && puntos == record) {
      titulo = tr('¡EMPATASTE EL RÉCORD!', 'RECORD TIED!');
    } else if (record > 0 && puntos >= record * 0.8) {
      titulo = tr('¡A ${record - puntos} DEL RÉCORD!', '${record - puntos} SHORT OF THE RECORD!');
      sub = tr('Casi, casi', 'So close');
    } else {
      titulo = tr('¡ATASCADO!', 'CLOGGED!');
      sub = tr('${_j.distancia.floor()} m · ${_nombresZona()[_j.zona]}', '${_j.distancia.floor()} m · ${_nombresZona()[_j.zona]}');
      fuerte = false;
    }
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: fuerte ? p.acento : p.fondo,
            border: Border.all(color: fuerte ? p.acento : p.bordeFuerte),
            borderRadius: BorderRadius.circular(radio),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(titulo,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1, color: fuerte ? p.acentoTexto : p.texto)),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: fuerte ? p.acentoTexto : p.textoSuave)),
          ]),
        ),
      ),
    );
  }
}

class _Aviso extends ChangeNotifier {
  void avisar() => notifyListeners();
}
