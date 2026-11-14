// Destapa: medio tiempo en el baño del estadio. Una fila de inodoros (2, luego 3 y 4) se tapa sola y el agua sube;
// se destapan a golpes de destapador (toques), el patito se saca deslizando hacia arriba, el celular se mantiene
// apretado y la cucaracha se aplasta antes de que se escape. Tres desbordes y se inunda el baño.
// Esta vista junta la lógica (destapa_logica.dart), el dibujo (destapa_pintor.dart) y los efectos: lee los dedos,
// hace sonar cada suceso, congela un instante en los golpes grandes y pinta el marcador cuadrado de la app encima.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'destapa_efectos.dart';
import 'destapa_logica.dart';
import 'destapa_pintor.dart';
import 'estadisticas.dart';
import 'marco.dart';
import 'sonido.dart';

// Cada PNG se carga una vez por proceso. Si falla se olvida para reintentar la próxima vez.
final _cargas = <String, Future<ui.Image>>{};

Future<ui.Image> _imagen(String nombre) => _cargas[nombre] ??= () async {
      try {
        final datos = await rootBundle.load('assets/emoji/$nombre.png');
        return await decodeImageFromList(datos.buffer.asUint8List());
      } catch (_) {
        _cargas.remove(nombre);
        rethrow;
      }
    }();

/// La llama el marco durante la instrucción: así el juego no decodifica PNG ni crea sonidos en sus primeros cuadros.
void precargarDestapa() {
  for (final n in _VistaDestapaState._archivos) {
    _imagen(n).ignore();
  }
  unawaited(Sonido.precargar(_VistaDestapaState._sonidos));
}

class VistaDestapa extends StatefulWidget {
  const VistaDestapa({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});

  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Solo para pruebas: una partida ya armada.
  final JuegoDestapa? juego;

  @override
  State<VistaDestapa> createState() => _VistaDestapaState();
}

class _Dedo {
  _Dedo(this.inodoro, this.inicio);
  final int inodoro;
  final Offset inicio;
  bool deslizo = false;
}

class _VistaDestapaState extends State<VistaDestapa> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final JuegoDestapa _j = widget.juego ?? JuegoDestapa();
  late final EfectosDestapa _ef = EfectosDestapa(widget.mov);
  final _tic = _Aviso();
  final _hud = _Aviso();
  late final PintorDestapa _pintor = PintorDestapa(juego: _j, ef: _ef, imgs: ImagenesDestapa(), tic: _tic);
  late final RelojJuego _reloj = RelojJuego(this, _paso);
  final _sw = Stopwatch();
  final _azar = Random(11);
  final _dedos = <int, _Dedo>{};
  final _record = recordMinijuego('destapa');

  bool _fin = false;
  bool _pausado = false;
  Timer? _cierre;
  double _congelado = 0;

  // Lo que muestra el marcador (se compara para no reconstruir de más).
  int _puntos = 0, _segundos = -1, _multi = 1, _barraCombo = 0, _vidas = JuegoDestapa.vidas;
  bool _prorroga = false;
  String? _banner;
  double _tBanner = 0;

  // Sonido: último toque de cada tipo (reloj de los efectos) para no saturar.
  final _ultimo = <String, double>{};

  static const _sonidos = [
    'glug', 'destapador', 'descarga', 'burbuja', 'cucaracha', 'alerta', 'fallo', 'combo', 'dorado', 'perdiste', 'gana', //
    'plop', 'chapuzon', 'pujo', 'boton',
  ];

  static const _archivos = ['pile_of_poo', 'plunger', 'duck', 'mobile_phone', 'cockroach', 'crown', 'sweat_droplets', 'fly'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(Sonido.precargar(_sonidos));
    unawaited(Sonido.musica('musica_destapa', volumen: 0.4));
    for (final n in _archivos) {
      _imagen(n).then((i) {
        if (mounted) _pintor.imgs = _con(n, i);
      }, onError: (_) {});
    }
    _sw.start();
    _reloj.arrancar();
  }

  ImagenesDestapa _con(String n, ui.Image i) {
    final a = _pintor.imgs;
    return ImagenesDestapa()
      ..mojon = n == 'pile_of_poo' ? i : a.mojon
      ..destapador = n == 'plunger' ? i : a.destapador
      ..patito = n == 'duck' ? i : a.patito
      ..celular = n == 'mobile_phone' ? i : a.celular
      ..cucaracha = n == 'cockroach' ? i : a.cucaracha
      ..corona = n == 'crown' ? i : a.corona
      ..sudor = n == 'sweat_droplets' ? i : a.sudor
      ..mosca = n == 'fly' ? i : a.mosca;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed && !_fin && !_pausado) {
      _pausado = true;
      _reloj.parar();
      _sw.stop();
      _soltarTodo();
      _hud.avisar();
    }
  }

  void _seguir() {
    if (!_pausado) return;
    _pausado = false;
    _sw.start();
    _reloj.arrancar();
    _hud.avisar();
  }

  void _soltarTodo() {
    for (final d in _dedos.values) {
      _j.soltar(d.inodoro);
    }
    _dedos.clear();
  }

  // ---------------------------------------------------------------- entrada

  void _baja(PointerDownEvent e) {
    if (_pausado) {
      _seguir();
      return;
    }
    if (_fin) return;
    final i = _pintor.inodoroEn(e.localPosition);
    if (i < 0) return;
    _dedos[e.pointer] = _Dedo(i, e.localPosition);
    _j.bajar(i);
  }

  void _mueve(PointerMoveEvent e) {
    final d = _dedos[e.pointer];
    if (d == null || d.deslizo || _fin) return;
    if (e.localPosition.dy - d.inicio.dy < -30) {
      d.deslizo = true;
      _j.deslizar(d.inodoro);
    }
  }

  void _sube(PointerEvent e) {
    final d = _dedos.remove(e.pointer);
    if (d != null) _j.soltar(d.inodoro);
  }

  // ---------------------------------------------------------------- cuadro

  void _paso(double dt) {
    _ef.avanzar(dt);
    if (_congelado > 0) {
      _congelado = max(0, _congelado - dt);
    } else {
      if (!_j.terminado) _j.avanzar(dt);
      _pintor.avanzar(dt);
    }
    for (final e in _j.tomarEventos()) {
      _pintor.reaccionar(e);
      _suceso(e);
    }
    if (_tBanner > 0) {
      _tBanner = max(0, _tBanner - dt);
      if (_tBanner == 0) {
        _banner = null;
        _hud.avisar();
      }
    }
    _refrescarHud();
    _tic.avisar();
  }

  void _refrescarHud() {
    final seg = _j.prorroga ? (_j.tiempo - JuegoDestapa.medioTiempo).floor() : _j.quedaMedio.ceil();
    final barra = (_j.progresoCombo * 20).floor();
    if (_j.puntos != _puntos || seg != _segundos || _j.multiplicador != _multi || barra != _barraCombo ||
        _j.vidasQuedan != _vidas || _j.prorroga != _prorroga) {
      _puntos = _j.puntos;
      _segundos = seg;
      _multi = _j.multiplicador;
      _barraCombo = barra;
      _vidas = _j.vidasQuedan;
      _prorroga = _j.prorroga;
      _hud.avisar();
    }
  }

  void _suena(String n, double volumen, {double cada = 0.06}) {
    final antes = _ultimo[n];
    if (antes != null && _ef.fase - antes < cada) return;
    _ultimo[n] = _ef.fase;
    Sonido.tocar(n, volumen: (volumen * (0.85 + 0.3 * _azar.nextDouble())).clamp(0.0, 1.0));
  }

  void _congelar(double s) {
    if (widget.mov != Movimiento.nada) _congelado = max(_congelado, s);
  }

  void _mostrarBanner(String s, double segundos) {
    _banner = s;
    _tBanner = segundos;
    _hud.avisar();
  }

  void _suceso(Evento e) {
    switch (e.suceso) {
      case Suceso.atasco:
        _suena(e.tipo == TipoAtasco.cucaracha ? 'cucaracha' : 'plop', 0.4);
        if (e.dorado) _suena('dorado', 0.6);
      case Suceso.golpe:
        _suena('destapador', e.tipo == TipoAtasco.gordo ? 0.75 : 0.55, cada: 0.04);
        vibracionSuave();
      case Suceso.golpeVacio:
        _suena(e.tipo == TipoAtasco.patito ? 'boton' : 'plop', 0.25);
      case Suceso.recupera:
        _suena('burbuja', 0.3, cada: 0.3);
      case Suceso.glug:
        _suena('glug', (0.15 + 0.5 * e.valor / 100).clamp(0.15, 0.65), cada: 0.4);
      case Suceso.alerta:
        _suena('alerta', 0.5, cada: 0.3);
      case Suceso.destapado:
        _suena('descarga', 0.55 + 0.1 * _azar.nextDouble());
        if (e.dorado) _suena('dorado', 0.85);
        switch (e.tipo) {
          case TipoAtasco.patito:
            _suena('chapuzon', 0.4);
          case TipoAtasco.cucaracha:
            _suena('cucaracha', 0.6);
          case TipoAtasco.gordo:
            _suena('pujo', 0.4);
          default:
            break;
        }
        if (e.dorado || e.tipo == TipoAtasco.gordo) _congelar(0.05);
      case Suceso.desborde:
        _suena('fallo', 0.8);
        _suena('chapuzon', 0.7);
        _congelar(0.075);
        vibracionSuave();
      case Suceso.hundido:
        _suena('burbuja', 0.5);
        _suena('glug', 0.35);
      case Suceso.escapa:
        _suena('cucaracha', 0.6);
        _suena('fallo', 0.3);
      case Suceso.combo:
        _suena('combo', 0.6 + 0.1 * e.valor);
        _congelar(0.045);
        vibracionSuave();
      case Suceso.comboRoto:
        _suena('fallo', 0.3);
      case Suceso.nuevoInodoro:
        _suena('descarga', 0.45);
        _suena('boton', 0.4);
      case Suceso.prorroga:
        _suena('gana', 0.6);
        _mostrarBanner(tr('¡PRÓRROGA!', 'EXTRA TIME!'), 1.8);
      case Suceso.fin:
        _terminar();
    }
  }

  void _terminar() {
    if (_fin) return;
    _fin = true;
    _sw.stop();
    _dedos.clear();
    Sonido.tocar(_j.pitazoFinal ? 'gana' : 'perdiste', volumen: 0.7);
    unawaited(Sonido.pararMusica());
    vibracionSuave();
    _banner = null;
    _hud.avisar();
    final espera = switch (widget.mov) { Movimiento.completo => 1000, Movimiento.simple => 700, Movimiento.nada => 450 };
    // Los ms nunca bajan del tiempo de juego (el contrato de puntos se cumple sobre ese tiempo) y quedan en el rango
    // que acepta el servidor; los puntos se recortan al tope por si acaso.
    final ms = max(_sw.elapsedMilliseconds, (_j.tiempo * 1000).ceil()).clamp(1500, 1200000);
    final tope = min(JuegoDestapa.topePuntos, (ms ~/ 1000 + 1) * JuegoDestapa.puntosPorSegundo);
    final puntos = min(_j.puntos, tope);
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

  // ---------------------------------------------------------------- pantalla

  @override
  Widget build(BuildContext context) {
    _pintor.oscuro = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          key: const Key('destapa_toque'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _baja,
          onPointerMove: _mueve,
          onPointerUp: _sube,
          onPointerCancel: _sube,
          child: RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: _pintor)),
        ),
        IgnorePointer(child: AnimatedBuilder(animation: _hud, builder: (context, _) => _marcador(context))),
      ],
    );
  }

  Widget _caja(Paleta p, Widget hijo, {bool fuerte = false, Color? fondo, EdgeInsets? relleno}) => Container(
        padding: relleno ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: fondo ?? p.tarjeta,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: fuerte ? p.bordeFuerte : p.borde, width: fuerte ? 2 : 1),
        ),
        child: hijo,
      );

  TextStyle _rotulo(Paleta p) => TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: p.textoSuave, letterSpacing: 1);

  String _reloj2(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _marcador(BuildContext context) {
    final p = paleta(context);
    final ultimos = !_prorroga && _segundos <= 10;
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 12,
          child: _caja(
            p,
            fuerte: true,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_puntos', key: const Key('destapa_puntos'), style: numeros(context, tamano: 28, weight: FontWeight.w900, color: p.texto)),
                Text(_record > 0 ? '${tr('RÉCORD', 'RECORD')} $_record' : tr('PUNTOS', 'POINTS'), style: _rotulo(p)),
              ],
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: _caja(
              p,
              fuerte: true,
              fondo: _prorroga ? p.acento : null,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _prorroga ? tr('PRÓRROGA', 'EXTRA TIME') : _reloj2(max(0, _segundos)),
                    key: const Key('destapa_reloj'),
                    style: numeros(context,
                        tamano: _prorroga ? 15 : 22,
                        weight: FontWeight.w900,
                        color: _prorroga ? p.acentoTexto : (ultimos ? const Color(0xFFE5383B) : p.texto)),
                  ),
                  Text(_prorroga ? '+${_reloj2(max(0, _segundos))}' : tr('MEDIO TIEMPO', 'HALF TIME'),
                      style: _rotulo(p).copyWith(color: _prorroga ? p.acentoTexto : p.textoSuave)),
                ],
              ),
            ),
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
                relleno: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                Row(
                  key: const Key('destapa_vidas'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var k = 0; k < JuegoDestapa.vidas; k++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Opacity(opacity: k < _vidas ? 1 : 0.2, child: const Emoji('🚽', tamano: 22)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _combo(context, p),
            ],
          ),
        ),
        if (_banner != null)
          Positioned(top: 150, left: 0, right: 0, child: Center(child: _letrero(context, p, _banner!, null))),
        if (_fin) Center(child: _letrero(context, p, _razon(), _pista())),
        if (_pausado && !_fin) Center(child: _letrero(context, p, tr('PAUSA', 'PAUSED'), tr('Toca para seguir', 'Tap to resume'))),
      ],
    );
  }

  Widget _combo(BuildContext context, Paleta p) {
    final lleno = _multi >= 3;
    return _caja(
      p,
      fuerte: _multi > 1,
      fondo: _multi > 1 ? p.acento : null,
      relleno: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      Column(
        key: const Key('destapa_multi'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('COMBO x$_multi', style: numeros(context, tamano: 13, weight: FontWeight.w900, color: _multi > 1 ? p.acentoTexto : p.texto)),
          const SizedBox(height: 3),
          Container(
            width: 84,
            height: 6,
            decoration: BoxDecoration(
              color: _multi > 1 ? p.acentoTexto.withValues(alpha: 0.2) : p.suave,
              borderRadius: BorderRadius.circular(radio),
              border: Border.all(color: _multi > 1 ? p.acentoTexto : p.bordeFuerte),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: lleno ? 1 : (_barraCombo / 20).clamp(0.0, 1.0),
              child: Container(color: _multi > 1 ? p.acentoTexto : p.acento),
            ),
          ),
        ],
      ),
    );
  }

  String _razon() => _j.pitazoFinal ? tr('¡PITAZO FINAL!', 'FINAL WHISTLE!') : tr('¡SE INUNDÓ EL BAÑO!', 'THE RESTROOM FLOODED!');

  String? _pista() {
    if (_j.pitazoFinal) return null;
    return switch (_j.tipoUltimoDesborde) {
      TipoAtasco.gordo => tr('El gordo se recupera si lo sueltas', 'The big one heals if you stop'),
      TipoAtasco.patito => tr('Al patito se le desliza hacia arriba', 'Swipe the duck up'),
      TipoAtasco.celular => tr('Al celular se le mantiene apretado', 'Hold the phone down'),
      _ => tr('Atiende primero el agua en rojo', 'Go for the red water first'),
    };
  }

  Widget _letrero(BuildContext context, Paleta p, String titulo, String? pista) => _caja(
        p,
        fuerte: true,
        relleno: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titulo, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: p.texto, letterSpacing: 0.5)),
            if (pista != null) ...[
              const SizedBox(height: 4),
              Text(pista, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.textoSuave)),
            ],
          ],
        ),
      );
}

class _Aviso extends ChangeNotifier {
  void avisar() => notifyListeners();
}
