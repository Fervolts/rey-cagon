import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'animaciones.dart';
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'logros.dart';
import 'tema.dart';

// Lo que hace vivo al TRONO: el título que se sacude, la frase del día, la mosca y el pujo largo.
// Cada pieza esconde un logro secreto. Ninguna registra una cagada: eso solo lo hace el botón CAGUÉ.

/// Cómo se gana un logro. En la app es [ganarLogro]; en las pruebas, uno falso que no toca la base.
typedef GanarLogro = Future<void> Function(BuildContext context, String clave);

/// Cuánto hay que mantener apretado CAGUÉ para el pujo eterno. Soltar antes es un toque normal.
const duracionPujo = Duration(seconds: 3);

/// Si el TRONO está a la vista: la pestaña activa del IndexedStack y sin otra pantalla encima.
bool tronoALaVista(BuildContext context) => Visibility.of(context) && TickerMode.valuesOf(context).enabled;

void _chiste(BuildContext context, String emoji, String texto) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Row(children: [
      Emoji(emoji, tamano: 24),
      const SizedBox(width: 10),
      Expanded(child: Text(texto)),
    ])));
}

/// El título "Rey Cagón". Cada toque lo sacude; 7 seguidos son un golpe de estado: sale una
/// corona al lado y se gana "Golpe de estado".
class TituloTrono extends StatefulWidget {
  const TituloTrono({super.key, required this.texto, this.estilo, this.ganar = ganarLogro});

  final String texto;
  final TextStyle? estilo;
  final GanarLogro ganar;

  @override
  State<TituloTrono> createState() => _TituloTronoState();
}

class _TituloTronoState extends State<TituloTrono> with SingleTickerProviderStateMixin {
  late final _sacudida = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  var _toques = 0;
  DateTime _ultimo = DateTime(2000);
  var _corona = false;

  static List<String> get _chistes => [
        tr('¡Golpe de estado! El trono es tuyo... hasta que alguien cague más.', 'Coup! The throne is yours... until someone poops more.'),
        tr(segun('Larga vida al rey. O hasta la próxima descarga.', 'Larga vida a la reina. O hasta la próxima descarga.'),
            segun('Long live the king. Or until the next flush.', 'Long live the queen. Or until the next flush.')),
      ];

  @override
  void dispose() {
    _sacudida.dispose();
    super.dispose();
  }

  void _tocar() {
    final ahora = DateTime.now();
    // "Seguidos": menos de un segundo entre toque y toque.
    _toques = ahora.difference(_ultimo) < const Duration(seconds: 1) ? _toques + 1 : 1;
    _ultimo = ahora;
    if (movimiento(context) != Movimiento.nada) _sacudida.forward(from: 0);
    if (_toques < 7) {
      if (_toques >= 4) HapticFeedback.selectionClick();
      return;
    }
    _toques = 0;
    HapticFeedback.heavyImpact();
    setState(() => _corona = true);
    final chistes = _chistes;
    _chiste(context, segun('🤴', '👸'), chistes[math.Random().nextInt(chistes.length)]);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) widget.ganar(context, 'trono_golpe');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tocar,
        child: AnimatedBuilder(
          animation: _sacudida,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.texto, style: widget.estilo)),
              if (_corona) ...[const SizedBox(width: 6), const Emoji('👑', tamano: 22)],
            ],
          ),
          builder: (context, child) {
            final t = _sacudida.value;
            if (t == 0 || t == 1) return child!;
            return Transform.rotate(angle: math.sin(t * math.pi * 6) * (1 - t) * .06, alignment: Alignment.centerLeft, child: child);
          },
        ),
      ),
    );
  }
}

/// Las frases de la tarjeta de hoy, en orden. La primera depende de cuántas llevas (o de la hora
/// si todavía nada); las demás se barajan distinto cada día.
List<String> frasesDelTrono(DateTime ahora, int hoy) {
  final h = ahora.hour;
  final primera = hoy > 0
      ? switch (hoy) {
          1 => tr('Una ya cuenta. El reino respira.', 'One counts. The kingdom breathes.'),
          < 5 => tr('Vas bien. El inodoro ya te llama por tu nombre.', 'Going well. The toilet knows you by name.'),
          5 => tr('RAMPAGE. Que alguien llame a un plomero.', 'RAMPAGE. Someone call a plumber.'),
          _ => tr('Esto ya es un problema de salud pública.', 'This is now a public health issue.'),
        }
      : switch (h) {
          3 => tr('Las 3 de la mañana. Ni el inodoro está despierto.', '3 a.m. Not even the toilet is awake.'),
          < 5 => tr('Madrugada. El trono te espera en silencio.', 'Late night. The throne waits in silence.'),
          < 9 => tr('Café primero. Lo demás llega solo.', 'Coffee first. The rest comes on its own.'),
          < 12 => tr('Media mañana: hora pico en el trono.', 'Mid-morning: rush hour on the throne.'),
          < 15 => tr('Después del almuerzo es que se pone bueno.', 'After lunch is when it gets good.'),
          < 19 => tr('La tarde es larga. El trono también.', 'The afternoon is long. So is the throne.'),
          _ => tr('Todavía estás a tiempo de salvar el día.', 'There is still time to save the day.'),
        };
  final resto = [
    tr('El papel se acaba justo cuando más lo necesitas.', 'The paper runs out right when you need it most.'),
    tr(segun('Un rey nunca le pasa seguro a la puerta. Confía.', 'Una reina nunca le pasa seguro a la puerta. Confía.'),
        segun('A king never locks the door. He trusts.', 'A queen never locks the door. She trusts.')),
    tr('Lo que pasa en el trono se queda en el trono.', 'What happens on the throne stays on the throne.'),
    tr('Nadie ha leído el champú tantas veces como tú.', 'Nobody has read the shampoo bottle as often as you.'),
    tr('El celular en el baño: tu verdadera oficina.', 'Your phone in the bathroom: your real office.'),
    tr('Cinco minutos más y te cobran alquiler.', 'Five more minutes and they charge you rent.'),
    tr('Si se te duermen las piernas, valió la pena.', 'If your legs fall asleep, it was worth it.'),
    tr('Un pujo a la vez.', 'One push at a time.'),
    tr('El trono no juzga. Tus amigos sí.', 'The throne does not judge. Your friends do.'),
    tr('Hay días de río y días de piedra.', 'Some days are rivers, some days are rocks.'),
    tr('Descarga y sigue adelante. Literal.', 'Flush and move on. Literally.'),
    tr('Abre la ventana. Hazlo por los demás.', 'Open a window. Do it for the others.'),
    tr('Dicen que por aquí anda una mosca.', 'They say there is a fly around here.'),
    tr('El título de arriba se pone nervioso si lo tocas mucho.', 'The title up there gets nervous if you poke it.'),
  ]..shuffle(math.Random(ahora.day + ahora.month * 31));
  return [primera, ...resto.where((f) => f != primera)];
}

/// La frase de la tarjeta de hoy. Al tocarla pasa a la siguiente; leer 10 distintas gana
/// "Filósofo del trono". Abrir el trono a las 3 de la mañana gana "Insomnio real".
class FraseDelTrono extends StatefulWidget {
  const FraseDelTrono({super.key, required this.hoy, this.ahora = DateTime.now, this.ganar = ganarLogro});

  final int hoy;
  final DateTime Function() ahora;
  final GanarLogro ganar;

  @override
  State<FraseDelTrono> createState() => _FraseDelTronoState();
}

class _FraseDelTronoState extends State<FraseDelTrono> with WidgetsBindingObserver {
  late List<String> _frases;
  var _i = 0;
  final _leidas = <String>{};
  var _filosofo = false;
  var _desvelo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barajar();
  }

  void _barajar() {
    _frases = frasesDelTrono(widget.ahora(), widget.hoy);
    _i = 0;
    _leidas.add(_frases.first);
  }

  @override
  void didUpdateWidget(FraseDelTrono viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.hoy != widget.hoy) _barajar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depende de la visibilidad: al volver a la pestaña se revisa la hora otra vez.
    if (tronoALaVista(context)) WidgetsBinding.instance.addPostFrameCallback((_) => _revisarHora());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _revisarHora();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _revisarHora() {
    if (_desvelo || !mounted || !tronoALaVista(context) || widget.ahora().hour != 3) return;
    _desvelo = true;
    widget.ganar(context, 'trono_desvelo');
  }

  void _siguiente() {
    HapticFeedback.selectionClick();
    setState(() => _i = (_i + 1) % _frases.length);
    _leidas.add(_frases[_i]);
    if (!_filosofo && _leidas.length >= 10) {
      _filosofo = true;
      widget.ganar(context, 'trono_filosofo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textoSuave, fontWeight: FontWeight.w600);
    return Semantics(
      button: true,
      hint: tr('Otra frase', 'Another line'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _siguiente,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: movimiento(context) == Movimiento.nada ? Duration.zero : const Duration(milliseconds: 220),
                  layoutBuilder: (actual, previos) => Stack(alignment: Alignment.centerLeft, children: [...previos, ?actual]),
                  child: Text(_frases[_i], key: ValueKey(_i), style: estilo),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.refresh, size: 14, color: p.textoSuave),
            ],
          ),
        ),
      ),
    );
  }
}

/// El área del botón CAGUÉ con una mosca que aparece al rato de estar en el trono. Vuela alrededor
/// del botón sin taparlo; aplastarla la primera vez gana "Matamoscas". Vuelve al rato.
/// Completo: da vueltas. Simple: salta de un sitio a otro. Nada: se queda quieta.
class ZonaMosca extends StatefulWidget {
  const ZonaMosca({
    super.key,
    required this.child,
    this.ganar = ganarLogro,
    this.aparece = const Duration(seconds: 7),
    this.vuelve = const Duration(seconds: 25),
  });

  /// El botón (200x200), centrado.
  final Widget child;
  final GanarLogro ganar;
  final Duration aparece;
  final Duration vuelve;

  static const alto = 248.0;

  @override
  State<ZonaMosca> createState() => _ZonaMoscaState();
}

enum _Mosca { fuera, volando, aplastada }

class _ZonaMoscaState extends State<ZonaMosca> with SingleTickerProviderStateMixin {
  // Mitad de la caja que se puede tocar (36x36) y radio del botón más 2 de aire.
  static const _media = 18.0, _boton = 102.0;

  late final _vuelo = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  final _azar = math.Random();
  var _mosca = _Mosca.fuera;
  Timer? _espera, _salto;
  Offset? _punto;
  var _gano = false;
  var _vista = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vista = tronoALaVista(context);
    _ajustar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _salto?.cancel();
    _vuelo.dispose();
    super.dispose();
  }

  void _parar() {
    _espera?.cancel();
    _espera = null;
    _salto?.cancel();
    _salto = null;
    _vuelo.stop();
  }

  /// Arranca o para todo según si se ve y el nivel de movimiento. Fuera de la vista no corre nada.
  void _ajustar() {
    if (!_vista) return _parar();
    if (_mosca == _Mosca.fuera) {
      _espera ??= Timer(widget.aparece, _aparecer);
    } else if (_mosca == _Mosca.volando) {
      _mover();
    }
  }

  void _mover() {
    final nivel = movimiento(context);
    if (nivel == Movimiento.completo) {
      _salto?.cancel();
      _salto = null;
      if (!_vuelo.isAnimating) _vuelo.repeat();
    } else {
      _vuelo.stop();
      if (nivel == Movimiento.simple) {
        _salto ??= Timer.periodic(const Duration(milliseconds: 2500), (_) {
          if (mounted) setState(() => _punto = null);
        });
      } else {
        _salto?.cancel();
        _salto = null;
      }
    }
  }

  void _aparecer() {
    _espera = null;
    if (!mounted || !_vista) return;
    setState(() {
      _mosca = _Mosca.volando;
      _punto = null;
    });
    _mover();
  }

  void _aplastar() {
    HapticFeedback.heavyImpact();
    _parar();
    setState(() => _mosca = _Mosca.aplastada);
    if (!_gano) {
      _gano = true;
      widget.ganar(context, 'trono_mosca');
    }
    _espera = Timer(const Duration(milliseconds: 600), () {
      _espera = null;
      if (!mounted) return;
      setState(() => _mosca = _Mosca.fuera);
      if (_vista) _espera = Timer(widget.vuelve, _aparecer);
    });
  }

  /// Corre el punto hacia afuera si la caja de la mosca tocaría el círculo del botón.
  static Offset _seguro(Offset p, double ancho, double alto) {
    final x = p.dx.clamp(-ancho, ancho), y = p.dy.clamp(-alto, alto);
    final a = math.max(x.abs() - _media, 0.0), b = math.max(y.abs() - _media, 0.0);
    if (a * a + b * b >= _boton * _boton) return Offset(x, y);
    final lado = x < 0 ? -1.0 : 1.0;
    final falta = math.sqrt(_boton * _boton - math.min(b, _boton) * math.min(b, _boton));
    return Offset(lado * math.min(falta + _media, ancho), y);
  }

  Offset _enVuelta(double t, double ancho, double alto) {
    final v = t * 2 * math.pi;
    final p = Offset(ancho * math.sin(v) + 6 * math.sin(v * 13), alto * math.sin(2 * v + math.pi / 3) + 5 * math.cos(v * 11));
    return _seguro(p, ancho, alto);
  }

  Offset _alAzar(double ancho, double alto) =>
      _seguro(Offset((_azar.nextDouble() * 2 - 1) * ancho, (_azar.nextDouble() * 2 - 1) * alto), ancho, alto);

  Widget _bicho(bool aplastada, {bool volteada = false, double giro = 0}) {
    Widget e = Emoji(aplastada ? '💥' : '🪰', tamano: 22);
    if (volteada) e = Transform.flip(flipX: true, child: e);
    if (giro != 0) e = Transform.rotate(angle: giro, child: e);
    return Semantics(
      button: !aplastada,
      label: tr('Mosca', 'Fly'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: aplastada ? null : _aplastar,
        child: SizedBox(width: _media * 2, height: _media * 2, child: Center(child: e)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final w = math.min(caja.maxWidth, 320.0);
      const h = ZonaMosca.alto;
      final ancho = w / 2 - _media, alto = h / 2 - _media;
      final aplastada = _mosca == _Mosca.aplastada;
      Widget? mosca;
      if (_mosca != _Mosca.fuera) {
        if (_vuelo.isAnimating && !aplastada) {
          mosca = AnimatedBuilder(
            animation: _vuelo,
            builder: (context, _) {
              final t = _vuelo.value;
              final p = _enVuelta(t, ancho, alto);
              final antes = _enVuelta((t - .005) % 1, ancho, alto);
              return Positioned(
                left: w / 2 + p.dx - _media,
                top: h / 2 + p.dy - _media,
                child: _bicho(false, volteada: p.dx < antes.dx, giro: math.sin(t * math.pi * 2 * 40) * .12),
              );
            },
          );
        } else {
          final p = _punto ??= movimiento(context) == Movimiento.nada ? _seguro(Offset(ancho, -alto), ancho, alto) : _alAzar(ancho, alto);
          mosca = Positioned(left: w / 2 + p.dx - _media, top: h / 2 + p.dy - _media, child: _bicho(aplastada));
        }
      }
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(children: [Center(child: widget.child), ?mosca]),
        ),
      );
    });
  }
}

/// Mantener apretado CAGUÉ: tiembla cada vez más y a los [duracionPujo] es un pujo eterno.
/// Llama a [alPujar] para que el botón NO registre ese toque, y gana "Pujo eterno".
/// Usa Listener (no entra a la arena de gestos), así el toque normal del botón no cambia.
class Pujo extends StatefulWidget {
  const Pujo({super.key, required this.child, required this.alPujar, this.ganar = ganarLogro});

  final Widget child;
  final VoidCallback alPujar;
  final GanarLogro ganar;

  @override
  State<Pujo> createState() => _PujoState();
}

class _PujoState extends State<Pujo> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: duracionPujo);
  Timer? _fin, _tic;
  int? _dedo;
  Offset _inicio = Offset.zero;

  static List<String> get _chistes => [
        tr('Pujo eterno. Las venas de la frente lo confirman.', 'The long push. The veins on your forehead confirm it.'),
        tr('Eso no fue una cagada, fue un parto.', 'That was not a poop, that was childbirth.'),
        tr('Tres segundos de fe. El trono te respeta.', 'Three seconds of faith. The throne respects you.'),
      ];

  @override
  void dispose() {
    _fin?.cancel();
    _tic?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _apretar(PointerDownEvent e) {
    if (_dedo != null) return;
    _dedo = e.pointer;
    _inicio = e.position;
    _fin = Timer(duracionPujo, _pujar);
    _tic = Timer.periodic(const Duration(milliseconds: 500), (_) => HapticFeedback.selectionClick());
    if (movimiento(context) != Movimiento.nada) _c.forward(from: 0);
  }

  void _soltar(PointerEvent e) {
    if (e.pointer != _dedo) return;
    _dedo = null;
    _cortar();
  }

  void _cortar() {
    _fin?.cancel();
    _fin = null;
    _tic?.cancel();
    _tic = null;
    _c.stop();
    _c.value = 0;
  }

  void _pujar() {
    _cortar();
    HapticFeedback.heavyImpact();
    widget.alPujar();
    final chistes = _chistes;
    _chiste(context, '💨', chistes[math.Random().nextInt(chistes.length)]);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) widget.ganar(context, 'trono_pujo');
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _apretar,
        onPointerMove: (e) {
          if (e.pointer == _dedo && (e.position - _inicio).distance > 18) _soltar(e);
        },
        onPointerUp: _soltar,
        onPointerCancel: _soltar,
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) {
            final t = _c.value;
            if (t < .25) return child!;
            // Del 25 % en adelante tiembla, cada vez más fuerte.
            final fuerza = (t - .25) / .75 * 4;
            final s = t * duracionPujo.inMilliseconds / 1000;
            return Transform.translate(offset: Offset(math.sin(s * math.pi * 2 * 19) * fuerza, math.cos(s * math.pi * 2 * 23) * fuerza * .5), child: child);
          },
        ),
      );
}
