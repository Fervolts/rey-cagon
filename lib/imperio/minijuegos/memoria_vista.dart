// Fusión real (id `memoria`): la poceta vista de frente, cortada. La pinza sostiene el próximo mojón; arrastrar apunta,
// soltar lo deja caer. Dos iguales que se tocan se funden en el siguiente nivel, hasta el Rey; dos Reyes se van en una
// descarga real. La palanca del tanque se carga con las fusiones y se traga a los chiquitos. Turno de 3 minutos; si algo
// se queda por encima de la línea roja más de 2 s, se desborda y se acaba.
// Lógica pura en memoria_logica.dart, dibujo y efectos en memoria_pintor.dart. El Ticker repinta el mundo; el marcador
// solo se reconstruye cuando cambia algo que muestra. Si la app se va al fondo, la partida se pausa.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'estadisticas.dart';
import 'marco.dart';
import 'memoria_logica.dart';
import 'memoria_pintor.dart';
import 'sonido.dart';

class VistaMemoria extends StatefulWidget {
  const VistaMemoria({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});

  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Partida ya armada (para pruebas). Si es null se crea una con semilla al azar.
  final JuegoFusion? juego;

  @override
  State<VistaMemoria> createState() => _EstadoMemoria();
}

const _efectos = [
  'plop', 'chapuzon', 'fusion1', 'fusion2', 'fusion3', 'fusion4', 'combo', 'dorado', 'gana', 'descarga', 'glug', 'alerta', //
  'perdiste', 'viento', 'boton', 'pujo', 'burbuja',
];

/// Color del aviso de peligro y del reloj al final.
const _rojo = Color(0xFFE5484D);

class _EstadoMemoria extends State<VistaMemoria> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final JuegoFusion _j = widget.juego ?? JuegoFusion(semilla: DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
  late final EfectosFusion _ef = EfectosFusion(mov: widget.mov);
  late final RelojJuego _reloj = RelojJuego(this, _paso);
  final _tic = _Aviso();
  final _hud = _Aviso();
  final _sw = Stopwatch();
  final _rng = Random();
  final Map<String, int> _ultimoSonido = {};
  Map<String, ui.Image> _img = const {};
  Size _tam = Size.zero;

  bool _fin = false;
  bool _pausado = false;
  Timer? _cierre;

  /// Hitstop: segundos en que la física se congela (los efectos siguen).
  double _congelado = 0;

  /// Soltar pedido mientras la pinza recarga: se cumple apenas pueda (si llega en menos de 0.3 s).
  double _pendiente = 0;
  int? _puntero;
  bool _yaSolto = false;
  double _alertaEn = 0;
  bool _avisoPalanca = false;
  bool _jaloPalanca = false;

  String? _banner, _bannerSub;
  Color? _bannerColor;
  double _bannerHasta = 0;

  // Lo último que mostró el marcador (para no reconstruirlo en cada cuadro).
  int _hPuntos = -1, _hSeg = -1, _hPresion = 0, _hCuenta = -1, _hReyes = 0;
  bool _hLista = false, _hPista = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(Sonido.precargar(_efectos));
    unawaited(Sonido.musica('musica_fusion', volumen: 0.4));
    for (final clave in archivosFusion.keys) {
      unawaited(imagenFusion(clave).then((img) {
        if (!mounted) return;
        setState(() => _img = {..._img, clave: img});
      }, onError: (_) {}));
    }
    _sw.start();
    _reloj.arrancar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed && !_fin && !_pausado) {
      _pausado = true;
      _puntero = null;
      _reloj.parar();
      _sw.stop();
      unawaited(Sonido.pararMusica());
      _hud.avisar();
    }
  }

  void _seguir() {
    if (!_pausado) return;
    _pausado = false;
    _sw.start();
    _reloj.arrancar();
    unawaited(Sonido.musica('musica_fusion', volumen: 0.4));
    _hud.avisar();
  }

  void _sonar(String nombre, {double volumen = 0.8}) {
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (ahora - (_ultimoSonido[nombre] ?? 0) < 60) return;
    _ultimoSonido[nombre] = ahora;
    Sonido.tocar(nombre, volumen: (volumen * (0.85 + _rng.nextDouble() * 0.15)).clamp(0.05, 1.0));
  }

  void _anunciar(String texto, {String? sub, Color? color, double dur = 1.6}) {
    _banner = texto;
    _bannerSub = sub;
    _bannerColor = color;
    _bannerHasta = _ef.tiempo + dur;
    _hud.avisar();
  }

  void _congelar(double s) {
    if (widget.mov == Movimiento.nada) return;
    _congelado = max(_congelado, s);
  }

  // ----- Toques

  void _baja(PointerDownEvent e) {
    if (_pausado) {
      _seguir();
      return;
    }
    if (_fin || _puntero != null) return;
    final g = GeoFusion.de(_tam);
    if (_j.palancaLista && g.enTanque(e.localPosition)) {
      if (_j.jalarPalanca()) _jaloPalanca = true;
      return;
    }
    _puntero = e.pointer;
    _j.apuntar(g.xMundo(e.localPosition.dx));
  }

  void _mueve(PointerMoveEvent e) {
    if (e.pointer != _puntero || _fin) return;
    _j.apuntar(GeoFusion.de(_tam).xMundo(e.localPosition.dx));
  }

  void _sube(PointerEvent e) {
    if (e.pointer != _puntero) return;
    _puntero = null;
    if (_fin || e is PointerCancelEvent) return;
    if (!_soltar()) _pendiente = 0.3;
  }

  bool _soltar() {
    final nivel = _j.actual;
    if (!_j.soltar()) return false;
    _yaSolto = true;
    _sonar('boton', volumen: 0.18 + nivel * 0.04);
    if (nivel >= 3 && _rng.nextInt(3) == 0) _sonar('pujo', volumen: 0.2);
    return true;
  }

  // ----- Cuadro

  void _paso(double dt) {
    _ef.avanzar(dt, _j.apunte);
    if (_congelado > 0) {
      _congelado -= dt;
    } else {
      _j.avanzar(dt);
    }
    for (final s in _j.tomarSucesos()) {
      _suceso(s);
    }
    if (_pendiente > 0) {
      _pendiente -= dt;
      if (_j.puedeSoltar && _soltar()) _pendiente = 0;
    }
    if (_j.fase == FaseFusion.jugando && _j.cuentaDesborde > 0) {
      _alertaEn -= dt;
      if (_alertaEn <= 0) {
        _alertaEn = 0.5;
        _sonar('alerta', volumen: 0.35 + _j.cuentaDesborde * 0.25);
      }
    } else {
      _alertaEn = 0;
    }
    if (_j.terminado) _terminar();
    _refrescarMarcador();
    _tic.avisar();
  }

  void _refrescarMarcador() {
    final cuenta = _j.fase == FaseFusion.jugando && _j.cuentaDesborde > 0 ? ((segundosDesborde - _j.cuentaDesborde) * 10).ceil() : -1;
    final pista = !_yaSolto && _j.t < 8;
    final seg = _j.restante.ceil();
    final banner = _banner != null && _ef.tiempo >= _bannerHasta;
    if (banner) _banner = null;
    if (_j.palancaLista && !_avisoPalanca) _avisoPalanca = true;
    if (banner ||
        _j.puntosVisibles != _hPuntos ||
        seg != _hSeg ||
        _j.presion != _hPresion ||
        cuenta != _hCuenta ||
        _j.palancaLista != _hLista ||
        _j.reyes != _hReyes ||
        pista != _hPista) {
      _hPuntos = _j.puntosVisibles;
      _hSeg = seg;
      _hPresion = _j.presion;
      _hCuenta = cuenta;
      _hLista = _j.palancaLista;
      _hReyes = _j.reyes;
      _hPista = pista;
      _hud.avisar();
    }
  }

  void _suceso(SucesoFusion s) {
    switch (s.tipo) {
      case TipoSuceso.plop:
        final f = s.fuerza;
        if (s.y > 78) {
          _sonar('chapuzon', volumen: 0.25 + f * 0.55);
          _ef.salpicar(s.x, s.y, 3 + (f * 9).round(), fuerza: 0.5 + f);
        } else {
          _sonar('plop', volumen: 0.2 + f * 0.6 + s.nivel * 0.03);
          if (f > 0.4) _ef.chispas(s.x, s.y, 2, const Color(0xFFFFF4D6), radio: 2);
        }
      case TipoSuceso.fusion:
        final n = s.nivel;
        final r = radioDe(n);
        _sonar(switch (n) { <= 2 => 'fusion1', <= 4 => 'fusion2', <= 6 => 'fusion3', _ => 'fusion4' }, volumen: 0.45 + n * 0.06);
        _ef.estallido(s.x, s.y, n, r);
        if (s.puntos > 0) {
          final oro = n >= 8 || s.cadena >= 2;
          _ef.texto(s.x, s.y - r - 4, '+${s.puntos}', oro ? const Color(0xFFFFD60A) : Colors.white, tam: 12 + n * 1.3);
        }
        if (s.cadena >= 2) {
          _sonar('combo', volumen: 0.5 + min(s.cadena, 4) * 0.1);
          _ef.texto(s.x, s.y - r - 18, 'COMBO x${min(s.cadena, multiplicadorMaximoFusion)}', const Color(0xFFFF9F1C), tam: 14, dur: 1.1);
        }
        if (n >= 4) _ef.sacudir(1.0 + n * 0.7);
        if (n >= 7) {
          _ef.destellar(coloresNivel[n], 0.18 + (n - 7) * 0.1);
          vibracionSuave();
        }
        if (n >= 8) {
          _congelar(0.07);
        } else if (n >= 6) {
          _congelar(0.05);
        }
      case TipoSuceso.dorado:
        _sonar('dorado', volumen: 0.9);
        _ef.chispas(s.x, s.y, 16, const Color(0xFFFFD60A), radio: radioDe(8));
        _anunciar(tr('¡MOJÓN DORADO!', 'GOLDEN POO!'), sub: tr('Uno más y nace un Rey', 'One more and a King is born'),
            color: const Color(0xFFFFD60A));
      case TipoSuceso.rey:
        _sonar('gana', volumen: 0.9);
        _ef.chispas(s.x, s.y, 24, const Color(0xFFFFD60A), radio: radioDe(9));
        _ef.sacudir(9);
        _ef.destellar(const Color(0xFFFFD60A), 0.55);
        _congelar(0.08);
        vibracionSuave();
        _anunciar(tr('¡NACIÓ UN REY!', 'A KING IS BORN!'), sub: tr('Junta dos para la descarga real', 'Merge two for the royal flush'),
            color: const Color(0xFFFFD60A), dur: 2.2);
      case TipoSuceso.descargaReal:
        _sonar('descarga', volumen: 1);
        _sonar('gana', volumen: 0.8);
        _ef.estallido(s.x, s.y, nivelMaximo, radioDe(nivelMaximo));
        _ef.salpicar(s.x, 86, 20, fuerza: 1.6);
        _ef.texto(s.x, s.y - 30, '+${s.puntos}', const Color(0xFFFFD60A), tam: 26, dur: 1.6);
        _ef.sacudir(14);
        _ef.destellar(Colors.white, 0.85);
        _congelar(0.08);
        vibracionSuave();
        _anunciar(tr('¡DESCARGA REAL!', 'ROYAL FLUSH!'), sub: tr('Dos Reyes se fueron por el tubo', 'Two Kings went down the pipe'),
            color: const Color(0xFFFFD60A), dur: 2.4);
      case TipoSuceso.palanca:
        _sonar('descarga', volumen: 0.75);
        _ef.salpicar(0, 86, 12, fuerza: 1.2);
        _ef.sacudir(4);
        _anunciar(tr('¡GLUUUG!', 'GLUUUG!'), sub: tr('La palanca se tragó a los chiquitos', 'The lever swallowed the little ones'), dur: 1.3);
      case TipoSuceso.tragado:
        _ef.tragar(s.x, s.y, s.nivel, retraso: _rng.nextDouble() * 0.25);
        _sonar('glug', volumen: 0.3 + _rng.nextDouble() * 0.3);
      case TipoSuceso.alerta:
        _sonar('alerta', volumen: 0.5);
      case TipoSuceso.desborde:
        _sonar('perdiste', volumen: 0.9);
        _ef.sacudir(10);
        _ef.destellar(_rojo, 0.5);
        _ef.salpicar(0, 6, 24, fuerza: 1.4);
        vibracionSuave();
        _anunciar(tr('¡SE DESBORDÓ!', 'IT OVERFLOWED!'),
            sub: tr('Un mojón pasó la línea roja más de 2 s', 'A poo stayed over the red line for over 2 s'), color: _rojo, dur: 9);
      case TipoSuceso.finTurno:
        _sonar('gana', volumen: 0.85);
        _anunciar(tr('DESCARGA FINAL', 'FINAL FLUSH'), sub: tr('Cada pieza que queda suma puntos', 'Every piece left scores points'),
            color: const Color(0xFFFFD60A), dur: 9);
      case TipoSuceso.finalPieza:
        _ef.hundir(s.x, s.y, s.nivel);
        _ef.texto(s.x, s.y - radioDe(s.nivel), '+${s.puntos}', s.nivel >= 8 ? const Color(0xFFFFD60A) : Colors.white, tam: 11.0 + s.nivel);
        _sonar(s.nivel >= 6 ? 'glug' : 'plop', volumen: 0.3 + s.nivel * 0.06);
      case TipoSuceso.aviso:
        _aviso(s.clave);
    }
  }

  void _aviso(String clave) {
    switch (clave) {
      case 'nivel3':
        _sonar('boton', volumen: 0.4);
        _anunciar(tr('Ya caen mojoncitos', 'Bigger pieces now'), dur: 1.4);
      case 'nivel4':
        _sonar('boton', volumen: 0.4);
        _anunciar(tr('¡Ahora mojones enteros!', 'Now full-size poos!'), dur: 1.4);
      case 'temblor':
        _sonar('descarga', volumen: 0.35);
        _ef.sacudir(5);
        _anunciar(tr('¡EL VECINO JALÓ LA CADENA!', 'THE NEIGHBOR FLUSHED!'), sub: tr('Todo tiembla', 'Everything shakes'));
      case 'frijoles':
        _sonar('burbuja', volumen: 0.5);
        _anunciar(tr('RACHA DE FRIJOLITOS', 'BEAN STREAK'), sub: tr('Los próximos 6 son chiquitos', 'The next 6 are small'));
      case 'presion2':
        _sonar('combo', volumen: 0.7);
        _anunciar(tr('PRESIÓN x2', 'PRESSURE x2'), sub: tr('Todo vale el doble', 'Everything is worth double'), color: const Color(0xFFFFD60A));
      case 'presion4':
        _sonar('combo', volumen: 0.9);
        _anunciar(tr('PRESIÓN x4', 'PRESSURE x4'), sub: tr('Todo vale cuatro veces', 'Everything is worth four times'),
            color: const Color(0xFFFFD60A));
      case 'lluvia':
        _sonar('viento', volumen: 0.6);
        _anunciar(tr('¡CAEN DEL TECHO!', 'INCOMING FROM ABOVE!'), sub: tr('Llueven bolitas', 'Little ones raining down'));
      case 'ultimos10':
        _sonar('alerta', volumen: 0.6);
        _anunciar(tr('¡ÚLTIMOS 10 SEGUNDOS!', 'LAST 10 SECONDS!'), color: _rojo, dur: 1.4);
    }
  }

  void _terminar() {
    if (_fin) return;
    _fin = true;
    _sw.stop();
    _puntero = null;
    unawaited(Sonido.pararMusica());
    vibracionSuave();
    final ms = max(_sw.elapsedMilliseconds, (_j.t * 1000).round()).clamp(minMsFusion, maxMsFusion - 1);
    final puntos = puntosReportables(_j.puntosVisibles, ms);
    final espera = switch (widget.mov) { Movimiento.completo => 1100, Movimiento.simple => 800, Movimiento.nada => 500 };
    _hud.avisar();
    _cierre = Timer(Duration(milliseconds: espera), () {
      _reloj.parar();
      if (mounted) widget.alTerminar(puntos, ms);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cierre?.cancel();
    _reloj.dispose();
    _tic.dispose();
    _hud.dispose();
    unawaited(Sonido.pararMusica());
    super.dispose();
  }

  // ----- Pantalla

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      _tam = Size(c.maxWidth, c.maxHeight);
      return Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            key: const Key('memoria_toque'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _baja,
            onPointerMove: _mueve,
            onPointerUp: _sube,
            onPointerCancel: _sube,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: PintorFusion(j: _j, ef: _ef, oscuro: oscuro, imagenes: _img, mov: widget.mov, repintar: _tic),
              ),
            ),
          ),
          IgnorePointer(child: AnimatedBuilder(animation: _hud, builder: (context, _) => _marcador(context))),
          AnimatedBuilder(animation: _hud, builder: (context, _) => _capa(context)),
        ],
      );
    });
  }

  Widget _caja(Paleta p, Widget hijo, {bool fuerte = false, Color? fondo, Color? borde}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: fondo ?? p.tarjeta,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: borde ?? (fuerte ? p.bordeFuerte : p.borde), width: fuerte ? 2 : 1),
        ),
        child: hijo,
      );

  Widget _marcador(BuildContext context) {
    final p = paleta(context);
    final record = recordMinijuego('memoria');
    final restante = _j.restante.ceil();
    final final10 = _j.fase == FaseFusion.jugando && restante <= 10;
    final reloj = '${restante ~/ 60}:${(restante % 60).toString().padLeft(2, '0')}';
    final g = GeoFusion.de(_tam);
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _caja(
                p,
                fuerte: true,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('PUNTOS', 'POINTS'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.textoSuave)),
                    Text('${_j.puntosVisibles}', key: const Key('memoria_puntos'), style: numeros(context, tamano: 20, weight: FontWeight.w900, color: p.texto)),
                  ],
                ),
              ),
              if (_j.presion > 1) ...[
                const SizedBox(width: 6),
                _caja(p, fondo: p.acento, borde: p.acento,
                    Text('x${_j.presion}', style: numeros(context, tamano: 18, weight: FontWeight.w900, color: p.acentoTexto))),
              ],
              if (_j.reyes > 0) ...[
                const SizedBox(width: 6),
                _caja(
                  p,
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Emoji('👑', tamano: 16),
                    const SizedBox(width: 4),
                    Text('${_j.reyes}', style: numeros(context, tamano: 16, weight: FontWeight.w900, color: p.texto)),
                  ]),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _caja(
                p,
                fuerte: true,
                fondo: final10 && restante.isEven ? _rojo : null,
                borde: final10 ? _rojo : null,
                Text(reloj,
                    key: const Key('memoria_reloj'),
                    style: numeros(context, tamano: 20, weight: FontWeight.w900, color: final10 ? (restante.isEven ? Colors.white : _rojo) : p.texto)),
              ),
              if (record > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(tr('Récord $record', 'Best $record'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.textoSuave)),
                ),
            ],
          ),
        ),
        if (_hCuenta > 0)
          Positioned(
            left: 0,
            right: 0,
            top: g.p(0, lineaDesborde).dy - 54,
            child: Center(
              child: _caja(
                p,
                fuerte: true,
                fondo: _rojo,
                borde: _rojo,
                Text(tr('¡SE DESBORDA! ${(_hCuenta / 10).toStringAsFixed(1)}', 'OVERFLOW! ${(_hCuenta / 10).toStringAsFixed(1)}'),
                    style: numeros(context, tamano: 18, weight: FontWeight.w900, color: Colors.white)),
              ),
            ),
          ),
        if (_banner != null && !_fin)
          Positioned(
            left: 16,
            right: 16,
            top: 62,
            child: Center(
              child: _caja(
                p,
                fuerte: true,
                borde: _bannerColor,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_banner!, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: p.texto)),
                    if (_bannerSub != null)
                      Text(_bannerSub!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textoSuave)),
                  ],
                ),
              ),
            ),
          ),
        if (_hPista)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Center(
              child: _caja(
                p,
                Text(tr('Arrastra para apuntar · suelta para tirar', 'Drag to aim · release to drop'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.texto)),
              ),
            ),
          ),
        if (_j.palancaLista && !_jaloPalanca && _j.fase == FaseFusion.jugando)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Center(
              child: _caja(
                p,
                fondo: p.acento,
                borde: p.acento,
                Text(tr('Toca el tanque: se traga los chiquitos', 'Tap the tank: it swallows the small ones'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.acentoTexto)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _capa(BuildContext context) {
    final p = paleta(context);
    if (_pausado) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _seguir,
        child: Container(
          color: p.fondo.withValues(alpha: 0.82),
          alignment: Alignment.center,
          child: _caja(
            p,
            fuerte: true,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('PAUSA', 'PAUSED'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: p.texto)),
                const SizedBox(height: 4),
                Text(tr('Toca para seguir', 'Tap to continue'), style: TextStyle(fontSize: 14, color: p.textoSuave)),
              ],
            ),
          ),
        ),
      );
    }
    if (!_fin) return const SizedBox.shrink();
    final record = recordMinijuego('memoria');
    final puntos = _j.puntosVisibles;
    final titulo = _j.desbordo ? tr('¡SE DESBORDÓ!', 'IT OVERFLOWED!') : tr('¡POCETA LIMPIA!', 'BOWL CLEAN!');
    final pista = _j.desbordo
        ? tr('Junta los iguales abajo y usa la palanca antes de llegar a la línea', 'Merge matches low and use the lever before the line')
        : tr('${_j.piezasFinal} piezas en la descarga final: +${_j.bonusFinal}', '${_j.piezasFinal} pieces in the final flush: +${_j.bonusFinal}');
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _caja(
            p,
            fuerte: true,
            borde: _j.desbordo ? _rojo : p.acento,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (record > 0 && puntos > record)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    color: p.acento,
                    child: Text(tr('¡NUEVO RÉCORD!', 'NEW RECORD!'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: p.acentoTexto)),
                  ),
                Text(titulo, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.texto)),
                Text('$puntos', style: numeros(context, tamano: 40, weight: FontWeight.w900, color: p.texto)),
                const SizedBox(height: 2),
                Text(pista, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textoSuave)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends ChangeNotifier {
  void avisar() => notifyListeners();
}
