// Tubería Express: surf de una mano por la cloaca. Mantener el dedo = pesado (baja rápido), soltar = liviano (vuela en
// la cresta). Lógica en tuberia_logica.dart, dibujo en tuberia_pintor.dart (un solo CustomPainter) y efectos, animación
// del mojón y cámara en tuberia_efectos.dart. El mundo lo repinta el Ticker; el marcador solo se reconstruye cuando
// cambia algo que muestra. Si la app se va al fondo, la partida se pausa (y el cronómetro también). Los PNG se cargan
// una sola vez para toda la app; mientras tanto el pintor dibuja formas de respaldo.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../animaciones.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'estadisticas.dart';
import 'marco.dart';
import 'sonido.dart';
import 'tuberia_efectos.dart';
import 'tuberia_logica.dart';
import 'tuberia_pintor.dart';

/// Nombre de cada zona, en el orden en que aparecen (cada [JuegoTuberia.metrosZona] metros, la última se repite).
String nombreZonaTuberia(int z) => switch (z % JuegoTuberia.zonas) {
      0 => tr('Baño', 'Bathroom'),
      1 => tr('Desagüe', 'Drain'),
      2 => tr('Cloaca', 'Sewer'),
      3 => tr('Río de la ciudad', 'City river'),
      _ => tr('Planta de tratamiento', 'Treatment plant'),
    };

const _sonidos = [
  'viento', 'chapuzon', 'pujo', 'pujo_largo', 'rollo', 'dorado', 'combo', 'cucaracha', 'fallo', 'perdiste', 'plop', //
  'descarga', 'alerta', 'glug', 'gana', 'burbuja',
];

// PNG que usa el pintor: se cargan una vez para toda la app; si uno falla se puede volver a pedir.
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

class VistaTuberia extends StatefulWidget {
  const VistaTuberia({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});
  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Solo para pruebas: una partida ya armada.
  final JuegoTuberia? juego;

  @override
  State<VistaTuberia> createState() => _VistaTuberiaState();
}

class _VistaTuberiaState extends State<VistaTuberia> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final JuegoTuberia _j = widget.juego ?? JuegoTuberia(record: recordMinijuego('tuberia'));
  late final EfectosTuberia _ef = EfectosTuberia(mov: widget.mov);
  late final AnimMojon _anim = AnimMojon(mov: widget.mov);
  final _cam = CamaraTuberia();
  var _img = ImagenesTuberia();
  final _tic = _Aviso();
  final _hud = _Aviso();
  late final RelojJuego _reloj = RelojJuego(this, _paso);
  final _sw = Stopwatch();
  final _azar = Random(5);

  int _dedos = 0;
  bool _fin = false;
  bool _porTiempo = false;
  bool _pausado = false;
  Timer? _cierre;

  // Lo que muestra el marcador (se compara para no reconstruir de más).
  int _metros = 0, _puntos = 0, _combo = 0, _fiebre = 0;
  int _zonaLetrero = 0;
  double _tLetrero = 2.4; // arranca mostrando la zona donde va
  String? _banner;
  int _bannerVez = 0;
  double _tBanner = 0;

  // Tutorial: dura hasta [_limpiosTutorial] aterrizajes limpios en total (se guardan en el teléfono).
  static const _claveTutorial = 'tuberia_tutorial_limpios', _limpiosTutorial = 6;
  bool _tutorial = false;
  int _limpiosGuardados = 0, _plafsTutorial = 0;

  // Sonido: último toque de cada tipo (reloj real) para no saturar.
  final _ultimo = <String, double>{};
  double _tPresion = 0, _ultimoPujo = -9, _ultimoPujoLargo = -9, _ultimoViento = -9, _proxBurbuja = 3;

  static const _imagenes = ['pile_of_poo', 'roll_of_paper', 'cockroach', 'rat', 'toilet', 'bathtub', 'sparkles'];

  @override
  void initState() {
    super.initState();
    _zonaLetrero = _j.zona;
    WidgetsBinding.instance.addObserver(this);
    unawaited(Sonido.precargar(_sonidos));
    unawaited(Sonido.musica('musica_tuberia', volumen: 0.45));
    for (final n in _imagenes) {
      _imagen(n).then((i) {
        if (mounted) setState(() => _img = _con(n, i));
      }, onError: (_) {});
    }
    _sw.start();
    _reloj.arrancar();
    unawaited(_leerTutorial());
  }

  Future<void> _leerTutorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _limpiosGuardados = prefs.getInt(_claveTutorial) ?? 0;
    } catch (_) {
      return;
    }
    if (!mounted || _limpiosGuardados >= _limpiosTutorial) return;
    setState(() => _tutorial = true);
    _tLetrero = 0;
    _mostrarBanner(tr('Mantén en las bajadas.\nSuelta en las subidas para volar.', 'Hold on downhills.\nRelease on uphills to fly.'), 4);
  }

  void _guardarTutorial() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_claveTutorial, _limpiosGuardados);
      } catch (_) {}
    }());
  }

  // Consejos del tutorial según lo que acaba de pasar.
  void _tutorialSuceso(SucesoTuberia s) {
    if (!_tutorial) return;
    switch (s.tipo) {
      case TipoSuceso.limpio:
        _limpiosGuardados++;
        _guardarTutorial();
        if (_limpiosGuardados >= _limpiosTutorial) {
          _mostrarBanner(tr('¡Ya le agarraste el truco!', "You've got the hang of it!"), 2.5);
        } else if (_limpiosGuardados <= 2) {
          _mostrarBanner(tr('¡LIMPIO! Caer en bajada da velocidad', 'CLEAN! Landing downhill gives speed'), 2.5);
        }
      case TipoSuceso.plaf:
        _plafsTutorial++;
        if (_plafsTutorial <= 3) {
          _mostrarBanner(
              tr('Caíste en una SUBIDA.\nEn el aire, mira la marca: verde = bajada.\nMantén para caer antes, suelta para volar más.',
                  'You landed UPHILL.\nIn the air, watch the mark: green = downhill.\nHold to drop sooner, release to fly further.'),
              4);
        }
      default:
    }
  }

  ImagenesTuberia _con(String n, ui.Image i) {
    final a = _img;
    return ImagenesTuberia()
      ..mojon = n == 'pile_of_poo' ? i : a.mojon
      ..rollo = n == 'roll_of_paper' ? i : a.rollo
      ..cucaracha = n == 'cockroach' ? i : a.cucaracha
      ..rata = n == 'rat' ? i : a.rata
      ..inodoro = n == 'toilet' ? i : a.inodoro
      ..banera = n == 'bathtub' ? i : a.banera
      ..chispas = n == 'sparkles' ? i : a.chispas;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed && !_fin && !_pausado) {
      _pausado = true;
      _reloj.parar();
      _sw.stop();
      _j.presionado = false;
      _dedos = 0;
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

  // ---------------------------------------------------------------- entrada

  void _baja(PointerDownEvent _) {
    if (_pausado) {
      _seguir();
      return;
    }
    _dedos++;
    if (_dedos == 1 && !_fin) {
      _j.presionado = true;
      _tPresion = 0;
      if (_ef.fase - _ultimoPujo > 0.9) {
        _ultimoPujo = _ef.fase;
        _suena('pujo', 0.35);
      }
    }
  }

  void _sube(PointerEvent _) {
    _dedos = max(0, _dedos - 1);
    if (_dedos == 0) _j.presionado = false;
  }

  // ---------------------------------------------------------------- cuadro

  void _paso(double dt) {
    final dtJ = _ef.avanzar(dt);
    if (!_ef.congelado && !_j.terminado) _j.avanzar(dtJ);
    final cercania = _j.terminado ? 0.0 : cercaniaAtasco(_j.separacion);
    _anim.avanzar(dt, _j, cercania);
    _cam.avanzar(dt, _j, cercania, suave: widget.mov != Movimiento.nada);
    for (final s in _j.tomarSucesos()) {
      _suceso(s);
    }
    if (!_j.terminado) {
      if (cercania > 0.6) _ef.sacudir((cercania - 0.6) * 6);
      _ambiente(dt);
      if (_sw.elapsedMilliseconds >= JuegoTuberia.tiempoMaximo * 1000) {
        _j.cortar();
        for (final s in _j.tomarSucesos()) {
          _suceso(s);
        }
      }
    }
    if (_tLetrero > 0) _tLetrero = max(0, _tLetrero - dt);
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

  void _ambiente(double dt) {
    if (_j.pesado) {
      _tPresion += dt;
      if (_tPresion > 1.2 && _ef.fase - _ultimoPujoLargo > 3) {
        _ultimoPujoLargo = _ef.fase;
        _suena('pujo_largo', 0.3);
      }
    }
    if (!_j.enSuelo && _j.alturaSobreSuelo > 3 && _ef.fase - _ultimoViento > 1.5) {
      _ultimoViento = _ef.fase;
      _suena('viento', (0.15 + _j.alturaSobreSuelo / 30).clamp(0.15, 0.5));
    }
    if (_j.zona % JuegoTuberia.zonas == 4) {
      _proxBurbuja -= dt;
      if (_proxBurbuja <= 0) {
        _proxBurbuja = 2.5 + _azar.nextDouble() * 2;
        _suena('burbuja', 0.15 + _azar.nextDouble() * 0.15);
      }
    }
  }

  void _refrescarHud() {
    final metros = _j.distancia.floor();
    final puntos = _j.puntos;
    final combo = _j.combo;
    final fiebre = (_j.fiebre / JuegoTuberia.duracionFiebre * 40).ceil();
    final letrero = _tLetrero > 0;
    if (metros != _metros || puntos != _puntos || combo != _combo || fiebre != _fiebre || letrero != (_zonaLetrero >= 0)) {
      _metros = metros;
      _puntos = puntos;
      _combo = combo;
      _fiebre = fiebre;
      if (!letrero) _zonaLetrero = -1;
      _hud.avisar();
    }
  }

  void _suena(String n, double volumen) {
    final antes = _ultimo[n];
    if (antes != null && _ef.fase - antes < 0.06) return;
    _ultimo[n] = _ef.fase;
    Sonido.tocar(n, volumen: (volumen * (0.88 + 0.24 * _azar.nextDouble())).clamp(0.0, 1.0));
  }

  void _mostrarBanner(String s, double segundos) {
    _banner = s;
    _bannerVez++;
    _tBanner = segundos;
    _hud.avisar();
  }

  static const _barro = Color(0xFF6B4A2E);
  static const _amarillo = Color(0xFFFFD60A);
  static const _rojo = Color(0xFFE5484D);

  void _suceso(SucesoTuberia s) {
    _tutorialSuceso(s);
    switch (s.tipo) {
      case TipoSuceso.despegue:
        _ultimoViento = _ef.fase;
        _suena('viento', 0.18 + 0.25 * s.fuerza);
        _anim.golpe(-1.2);
      case TipoSuceso.aterrizaje:
        _suena('chapuzon', 0.25 + 0.5 * s.fuerza);
        _anim.golpe(1.2 + 2 * s.fuerza);
        _ef.salpicar(s.x, s.y, 6 + (8 * s.fuerza).round(), color: _barro, fuerza: 2.5 + 3 * s.fuerza, forma: FormaParticula.gota);
      case TipoSuceso.limpio:
        _suena('chapuzon', 0.35 + 0.5 * s.fuerza);
        _anim.golpe(1.5 + 2 * s.fuerza);
        _anim.alegria = 0.8;
        _ef.salpicar(s.x, s.y, 8, color: _barro, fuerza: 3 + 3 * s.fuerza, forma: FormaParticula.gota, haciaX: 2);
        _ef.salpicar(s.x, s.y + 0.3, 10, color: _amarillo, fuerza: 6, forma: FormaParticula.chispa, tam: 0.1, gravedad: -4, vida: 0.5);
        _ef.texto(s.x, s.y + 1.4, s.valor >= 2 ? '+${s.puntos}  x${s.valor}' : '+${s.puntos}', tam: s.valor >= 3 ? 24 : 20);
        _ef.destellar(_amarillo, 0.12 + 0.03 * min(s.valor, 6));
        if (s.valor >= 3) {
          _ef.hitstop(0.045);
          _ef.sacudir(3);
        }
      case TipoSuceso.combo:
        _suena('combo', 0.5 + 0.05 * s.valor);
        if (s.valor >= 3) vibracionSuave();
      case TipoSuceso.plaf:
        _suena('fallo', 0.55);
        _suena('chapuzon', 0.7);
        _anim
          ..mareo = 1.2
          ..giroExtra = 1
          ..golpe(4);
        _ef.salpicar(s.x, s.y, 18, color: _barro, fuerza: 6, forma: FormaParticula.gota);
        _ef.texto(s.x, s.y + 1.4, tr('¡PLAF!', 'SPLAT!'), color: const Color(0xFFF4E3CF), tam: 26);
        if (s.valor >= 2) _ef.texto(s.x + 1.5, s.y + 2.4, tr('combo perdido', 'combo lost'), color: _rojo, tam: 14, vida: 1.1);
        _ef.hitstop(0.06);
        _ef.sacudir(7);
        _ef.destellar(_barro, 0.3);
        vibracionSuave();
      case TipoSuceso.rollo:
        _suena('rollo', 0.45 + 0.04 * min(s.valor, 8));
        _ef.salpicar(s.x, s.y, 12, color: Colors.white, fuerza: 4, forma: FormaParticula.papel, tam: 0.16, gravedad: -3, vida: 1.1);
        _ef.texto(s.x, s.y + 1, '+${s.puntos}', color: Colors.white, tam: 18);
      case TipoSuceso.dorado:
        _suena('dorado', 0.8);
        _ef.salpicar(s.x, s.y, 24, color: _amarillo, fuerza: 7, forma: FormaParticula.chispa, tam: 0.12, gravedad: -3, vida: 0.9);
        _ef.salpicar(s.x, s.y, 12, color: const Color(0xFFFFB800), fuerza: 4, forma: FormaParticula.papel, tam: 0.18, gravedad: -3, vida: 1.2);
        _ef.texto(s.x, s.y + 1.2, '+${s.puntos}', tam: 22);
        _ef.hitstop(0.07);
        _ef.sacudir(4);
        _ef.destellar(_amarillo, 0.5);
        _anim.alegria = 1.5;
        vibracionSuave();
      case TipoSuceso.fiebre:
        _suena('descarga', 0.5);
        _mostrarBanner(tr('¡FIEBRE DORADA!', 'GOLDEN FEVER!'), 1.6);
      case TipoSuceso.finFiebre:
        break;
      case TipoSuceso.aplasta:
        _suena('cucaracha', 0.7);
        _suena('chapuzon', 0.4);
        _anim
          ..alegria = 0.8
          ..golpe(2.5);
        _ef.salpicar(s.x, s.y + 0.1, 14, color: const Color(0xFF3B2414), fuerza: 4, tam: 0.1);
        _ef.texto(s.x, s.y + 1.2, '${tr('¡CRAC!', 'CRUNCH!')} +${s.puntos}', color: const Color(0xFF9BE15D), tam: 20);
        _ef.hitstop(0.05);
        _ef.sacudir(4);
        vibracionSuave();
      case TipoSuceso.choqueCucaracha:
        _suena('plop', 0.6);
        _suena('cucaracha', 0.45);
        _anim
          ..mareo = 0.8
          ..golpe(2.5);
        _ef.salpicar(s.x, s.y + 0.3, 8, color: const Color(0xFF7A3E1D), fuerza: 3, tam: 0.08);
        _ef.texto(s.x, s.y + 1.4, tr('¡AY! más lento', 'OUCH! slower'), color: _rojo, tam: 16);
        _ef.sacudir(3);
      case TipoSuceso.zona:
        _suena('descarga', 0.6);
        _zonaLetrero = s.valor;
        _tLetrero = 2.4;
        _ef.destellar(Colors.white, 0.35);
        _hud.avisar();
      case TipoSuceso.atascoCerca:
        _suena('alerta', 0.5);
        _ef.destellar(_rojo, 0.25);
      case TipoSuceso.atascoAcelera:
        _suena('glug', 0.6);
        _mostrarBanner(tr('¡El Atasco acelera!', 'The Clog speeds up!'), 1.8);
      case TipoSuceso.record:
        _suena('gana', 0.6);
        _ef.salpicar(s.x, s.y + 1, 16, color: _amarillo, fuerza: 6, forma: FormaParticula.papel, tam: 0.15, gravedad: -3, vida: 1.2);
        _mostrarBanner(tr('¡NUEVO RÉCORD!', 'NEW RECORD!'), 1.8);
      case TipoSuceso.atrapado:
        _terminar(porTiempo: s.valor == 1);
    }
  }

  void _terminar({required bool porTiempo}) {
    if (_fin) return;
    _fin = true;
    _porTiempo = porTiempo;
    _sw.stop();
    _j.presionado = false;
    if (!porTiempo) {
      _suena('chapuzon', 0.9);
      _ef.salpicar(_j.x, _j.y, 26, color: _barro, fuerza: 7, forma: FormaParticula.gota);
      _ef.hitstop(0.08);
      _ef.sacudir(10);
      _ef.destellar(_rojo, 0.5);
      _anim
        ..mareo = 3
        ..golpe(4);
    }
    Sonido.tocar('perdiste', volumen: 0.7);
    unawaited(Sonido.pararMusica());
    vibracionSuave();
    _hud.avisar();
    final espera = switch (widget.mov) { Movimiento.completo => 1000, Movimiento.simple => 700, Movimiento.nada => 450 };
    // Los ms nunca bajan del tiempo de juego (el contrato de puntos se cumple sobre ese tiempo) ni pasan del máximo.
    final ms = max(_sw.elapsedMilliseconds, (_j.tiempo * 1000).ceil()).clamp(0, 1190000);
    final puntos = _j.puntos;
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
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          key: const Key('tuberia_toque'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _baja,
          onPointerUp: _sube,
          onPointerCancel: _sube,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: PintorTuberia(
                juego: _j,
                efectos: _ef,
                anim: _anim,
                camara: _cam,
                imagenes: _img,
                oscuro: oscuro,
                mov: widget.mov,
                tutorial: _tutorial,
                repaint: _tic,
              ),
            ),
          ),
        ),
        IgnorePointer(child: AnimatedBuilder(animation: _hud, builder: (context, _) => _marcador(context))),
        AnimatedBuilder(animation: _hud, builder: (context, _) => _capa(context)),
      ],
    );
  }

  Widget _caja(Paleta p, Widget hijo, {bool fuerte = false, Color? fondo}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: fondo ?? p.tarjeta,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: fuerte ? p.bordeFuerte : p.borde, width: fuerte ? 2 : 1),
        ),
        child: hijo,
      );

  Widget _marcador(BuildContext context) {
    final p = paleta(context);
    final record = _j.record;
    final fiebre = _j.fiebre / JuegoTuberia.duracionFiebre;
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _caja(
                p,
                fuerte: true,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$_metros', key: const Key('tuberia_metros'), style: numeros(context, tamano: 28, weight: FontWeight.w900, color: p.texto)),
                        const SizedBox(width: 3),
                        Text('m', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.textoSuave)),
                      ],
                    ),
                    Text('${tr('PUNTOS', 'POINTS')} $_puntos',
                        style: numeros(context, tamano: 12, weight: FontWeight.w800, color: p.textoSuave)),
                  ],
                ),
              ),
              if (_combo >= 2) ...[
                const SizedBox(height: 6),
                _caja(
                  p,
                  fondo: p.acento,
                  fuerte: true,
                  Text('COMBO x$_combo', style: numeros(context, tamano: 15, weight: FontWeight.w900, color: p.acentoTexto)),
                ),
              ],
              if (fiebre > 0) ...[
                const SizedBox(height: 6),
                // Fiebre con nombre: el banner puede quedar tapado por el letrero de zona.
                _caja(
                  p,
                  fondo: const Color(0xFF201008),
                  fuerte: true,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('FIEBRE x2', 'FEVER x2'),
                          style: numeros(context, tamano: 13, weight: FontWeight.w900, color: const Color(0xFFFFD60A))),
                      const SizedBox(height: 4),
                      Container(
                        width: 96,
                        height: 6,
                        color: const Color(0x40FFD60A),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(widthFactor: fiebre.clamp(0.0, 1.0), child: Container(color: const Color(0xFFFFD60A))),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (record > 0)
          Positioned(
            top: 8,
            right: 12,
            child: _caja(
              p,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('RÉCORD', 'RECORD'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: p.textoSuave, letterSpacing: 1)),
                  Text('$record', style: numeros(context, tamano: 16, weight: FontWeight.w900, color: p.texto)),
                ],
              ),
            ),
          ),
        // Debajo de la columna de marcador (puntos, combo, fiebre) para no taparla.
        Positioned(top: 196, left: 0, right: 0, child: Center(child: _letrero(context))),
      ],
    );
  }

  // Letrero grande de zona y banners cortos (Atasco, fiebre, récord). Un solo hueco: la zona manda.
  Widget _letrero(BuildContext context) {
    final p = paleta(context);
    Widget hijo = const SizedBox.shrink(key: ValueKey('nada'));
    if (_fin) {
      hijo = const SizedBox.shrink(key: ValueKey('fin'));
    } else if (_tLetrero > 0 && _zonaLetrero >= 0) {
      hijo = Container(
        key: ValueKey('zona$_zonaLetrero'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: p.acento,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: const Color(0xFF201008), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${tr('ZONA', 'ZONE')} ${_zonaLetrero + 1}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2, color: p.acentoTexto)),
            Text(nombreZonaTuberia(_zonaLetrero).toUpperCase(),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.1, color: p.acentoTexto)),
          ],
        ),
      );
    } else if (_banner != null) {
      hijo = KeyedSubtree(
        key: ValueKey(_bannerVez),
        child: _caja(p, fuerte: true,
            Text(_banner!, textAlign: TextAlign.center, style: TextStyle(fontSize: _banner!.contains('\n') ? 15 : 18, fontWeight: FontWeight.w900, color: p.texto))),
      );
    }
    return switch (widget.mov) {
      Movimiento.nada => hijo,
      Movimiento.simple => AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: hijo),
      Movimiento.completo => AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: c),
          ),
          child: hijo,
        ),
    };
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
    final puntos = _j.puntos;
    final record = _j.record;
    String? sobre;
    String? debajo;
    if (record > 0 && puntos > record) {
      sobre = tr('¡NUEVO RÉCORD!', 'NEW RECORD!');
    } else if (record > 0 && puntos == record) {
      sobre = tr('¡EMPATASTE EL RÉCORD!', 'RECORD TIED!');
    } else if (record > 0 && record - puntos <= max(20, record ~/ 10)) {
      sobre = tr('¡A ${record - puntos} DEL RÉCORD!', '${record - puntos} SHORT OF THE RECORD!');
      debajo = tr('Casi, casi', 'So close');
    }
    final titulo = _porTiempo ? tr('¡Se acabó el tiempo!', "Time's up!") : tr('¡TE ALCANZÓ EL ATASCO!', 'THE CLOG CAUGHT YOU!');
    final pista = _porTiempo ? null : tr('Baja pesado y suelta en el valle para volar', 'Go down heavy and release in the valley to fly');
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _caja(
            p,
            fuerte: true,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sobre != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    color: p.acento,
                    child: Text(sobre, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: p.acentoTexto)),
                  ),
                Text(titulo, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: p.texto)),
                const SizedBox(height: 4),
                Text('$_metros m · $puntos ${tr('puntos', 'points')}',
                    style: numeros(context, tamano: 16, weight: FontWeight.w800, color: p.texto)),
                if (debajo != null) Text(debajo, style: TextStyle(fontSize: 13, color: p.textoSuave)),
                if (pista != null) ...[
                  const SizedBox(height: 6),
                  Text(pista, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.textoSuave)),
                ],
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
