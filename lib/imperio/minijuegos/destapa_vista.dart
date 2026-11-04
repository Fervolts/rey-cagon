// Destapa: ritmo sin audio. Cuadrados que se cierran sobre el inodoro; tocas cuando llegan, aguantas los de mantener.
// Lógica en destapa_logica.dart, dibujo en destapa_pintor.dart. Aquí: dedos, jugo (golpe del destapador, salpicadura,
// textos que saltan, sacudida, agua que sube) y háptica según el golpe. Todo respeta movimiento(context).

import 'dart:async';
import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../animaciones.dart';
import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'destapa_logica.dart';
import 'destapa_pintor.dart';
import 'marco.dart';

class VistaDestapa extends StatefulWidget {
  const VistaDestapa({super.key, required this.alTerminar, this.mov = Movimiento.completo, this.juego});
  final AlTerminarJuego alTerminar;
  final Movimiento mov;

  /// Solo para pruebas.
  final JuegoDestapa? juego;

  @override
  State<VistaDestapa> createState() => _VistaDestapaState();
}

// Háptica por calidad: 0 tic, 1 suave, 2 medio, 3 fuerte.
void _vibra(int nivel) {
  try {
    unawaited(switch (nivel) {
      0 => HapticFeedback.selectionClick(),
      1 => HapticFeedback.lightImpact(),
      2 => HapticFeedback.mediumImpact(),
      _ => HapticFeedback.heavyImpact(),
    });
  } catch (_) {}
}

class _VistaDestapaState extends State<VistaDestapa> with SingleTickerProviderStateMixin {
  late final JuegoDestapa _j = widget.juego ?? JuegoDestapa();
  late final RelojJuego _reloj;
  final _sw = Stopwatch();
  final _cuadro = Stopwatch(); // desde el último tic: el toque se juzga a su hora real, no a la del cuadro
  final _gotas = Salpicadura();
  bool _fin = false;
  int _dedos = 0;
  double _sacudida = 0; // 1 recién fallado, baja a 0
  double _empuje = 0; // 1 recién golpeado: el destapador baja
  double _bump = 0; // 1 recién perfecto
  double _agua = 0; // nivel que se ve, persigue fallos / máximo
  String _pop = '';
  Color? _popColor;
  double _popEdad = 9;
  String _aviso = '';
  double _avisoEdad = 9;

  bool get _completo => widget.mov == Movimiento.completo;
  bool get _quieto => widget.mov == Movimiento.nada;

  @override
  void initState() {
    super.initState();
    _reloj = RelojJuego(this, _paso);
    _sw.start();
    _cuadro.start();
    _reloj.arrancar();
  }

  double get _desfase => m.min(0.05, _cuadro.elapsedMicroseconds / 1e6);

  void _paso(double dt) {
    if (_fin) return;
    _cuadro.reset();
    _j.avanzar(dt);
    _efectos();
    _sacudida = m.max(0, _sacudida - dt * 3.5);
    _empuje = m.max(0, _empuje - dt * 6);
    _bump = m.max(0, _bump - dt * 5);
    _popEdad += dt;
    _avisoEdad += dt;
    final meta = _j.fallos / JuegoDestapa.fallosMaximos;
    _agua = _quieto ? meta : _agua + (meta - _agua) * m.min(1, dt * 5);
    if (_completo) _gotas.avanzar(dt);
    _quizaTerminar();
    if (mounted) setState(() {});
  }

  void _baja(PointerDownEvent _) {
    _dedos++;
    if (_fin) return;
    _j.toque(desfase: _desfase);
    _efectos();
    _quizaTerminar();
    setState(() {});
  }

  void _sube(PointerEvent _) {
    _dedos = m.max(0, _dedos - 1);
    if (_fin || _dedos > 0) return;
    _j.suelta(desfase: _desfase);
    _efectos();
    _quizaTerminar();
    setState(() {});
  }

  void _popea(String t, Color c) {
    _pop = t;
    _popColor = c;
    _popEdad = 0;
  }

  // Gotas solo con todo el movimiento: con simple o nada no se mueven.
  void _salpica(int n, {bool dorada = false, double fuerza = 1}) {
    if (_completo) _gotas.soltar(n, dorada: dorada, fuerza: fuerza);
  }

  void _avisa(String t) {
    _aviso = t;
    _avisoEdad = 0;
  }

  // Lo que pasó en la lógica, convertido en jugo.
  void _efectos() {
    final p = paleta(context);
    for (final e in _j.tomarEventos()) {
      switch (e.suceso) {
        case Suceso.golpe:
          if (e.golpe == Golpe.perfecto) {
            // sonido: golpe del destapador, perfecto (más agudo, con brillo).
            _vibra(1);
            _popea(tr('¡PERFECTO! +${e.valor}', 'PERFECT! +${e.valor}'), p.acento);
            _bump = 1;
            _salpica(7, dorada: true);
          } else {
            // sonido: golpe del destapador, bueno.
            _vibra(0);
            _popea(tr('BIEN +${e.valor}', 'GOOD +${e.valor}'), p.texto);
            _salpica(3, fuerza: 0.7);
          }
          _empuje = 1;
        case Suceso.mantenido:
          // sonido: chupón que suelta (mantener completo).
          _vibra(1);
          _popea(tr('¡AGUANTÓ! +${e.valor}', 'HELD! +${e.valor}'), p.acento);
          _empuje = 1;
          _salpica(5, dorada: true);
        case Suceso.fallo:
          // sonido: chapuzón / gorgoteo del agua que sube.
          _vibra(2);
          _popea(tr('FALLO', 'MISS'), colorAgua);
          _sacudida = 1;
        case Suceso.destapado:
          // sonido: descarga del inodoro.
          _vibra(1);
          _avisa(tr('¡DESTAPADO!', 'UNCLOGGED!'));
          _salpica(16, fuerza: 1.3);
        case Suceso.jefe:
          // sonido: tambor grave, entra el atasco gordo.
          _vibra(2);
          _avisa(tr('¡ATASCO GORDO!', 'MEGA CLOG!'));
        case Suceso.jefeVencido:
          // sonido: descarga larga + fanfarria.
          _vibra(3);
          _avisa(e.valor > 0 ? tr('¡VENCIDO! El agua baja', 'BEATEN! Water drains') : tr('¡ATASCO VENCIDO!', 'CLOG BEATEN!'));
          _salpica(24, dorada: true, fuerza: 1.5);
        case Suceso.masRapido:
          if (_avisoEdad > 1.2) _avisa(tr('MÁS RÁPIDO', 'FASTER'));
        case Suceso.multiplicador:
          // sonido: subida de racha.
          _vibra(1);
          _avisa(tr('RACHA x${e.valor}', 'STREAK x${e.valor}'));
        case Suceso.finTurno:
          _vibra(3);
          _avisa(tr('¡TURNO COMPLETO!', 'SHIFT COMPLETE!'));
      }
    }
  }

  void _quizaTerminar() {
    if (!_j.terminado || _fin) return;
    _fin = true;
    _reloj.parar();
    _sw.stop();
    if (!_j.turnoCompleto) _avisa(tr('¡SE DESBORDÓ!', 'IT OVERFLOWED!'));
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.alTerminar(_j.puntos, _sw.elapsedMilliseconds);
    });
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final x = _j.multiplicador;
    return Listener(
      key: const Key('destapa_toque'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _baja,
      onPointerUp: _sube,
      onPointerCancel: _sube,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Text('${_j.puntos}', key: const Key('destapa_puntos'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.texto)),
            const SizedBox(width: 10),
            Container(
              key: const Key('destapa_multi'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: x > 1 ? p.acento : null,
                border: Border.all(color: x > 1 ? p.acento : p.borde),
                borderRadius: BorderRadius.circular(radio),
              ),
              child: Text('x$x', style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'monospace', color: x > 1 ? p.acentoTexto : p.textoSuave)),
            ),
            const Spacer(),
            for (var i = 0; i < JuegoDestapa.fallosMaximos; i++)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Opacity(opacity: i < JuegoDestapa.fallosMaximos - _j.fallos ? 1 : 0.2, child: const Emoji('🧻', tamano: 22)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            Text(
              _j.esJefe ? tr('ATASCO GORDO', 'MEGA CLOG') : tr('INODORO ${_j.inodoros + 1}', 'TOILET ${_j.inodoros + 1}'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: _j.esJefe ? p.acento : p.textoSuave),
            ),
            const Spacer(),
            if (_j.racha >= 3)
              Text(
                tr('racha ${_j.racha}', 'streak ${_j.racha}'),
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: x > 1 ? p.acento : p.textoSuave),
              ),
          ]),
        ),
        Expanded(child: LayoutBuilder(builder: (context, caja) => _juego(p, Size(caja.maxWidth, caja.maxHeight)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Column(children: [
            Container(
              height: 8,
              decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (_j.avance / _j.requiere).clamp(0.0, 1.0),
                child: ColoredBox(color: p.acento),
              ),
            ),
            const SizedBox(height: 6),
            Text(tr('Inodoros destapados: ${_j.inodoros}', 'Toilets unclogged: ${_j.inodoros}'), style: TextStyle(fontSize: 12, color: p.textoSuave)),
          ]),
        ),
      ]),
    );
  }

  Widget _juego(Paleta p, Size s) {
    final g = GeoDestapa(s);
    final c = g.centro;
    final dx = _completo ? m.sin(_sacudida * 34) * 8 * _sacudida : 0.0;
    final inodoro = g.lado * 0.62;
    // Tapón: se encoge con el avance; el del atasco gordo es más grande.
    final resta = 1 - (_j.avance / _j.requiere).clamp(0.0, 1.0);
    final tapon = (inodoro * 0.22 + inodoro * 0.3 * resta) * (_j.esJefe ? 1.35 : 1);
    final baja = _quieto ? 0.0 : _empuje * g.lado * 0.12;
    final h = _j.mantenida;
    final popVivo = _quieto || _popEdad < 0.7;
    final popEsc = _completo ? 1 + 0.5 * m.max(0, 1 - _popEdad / 0.14) : 1.0;
    final popSube = _completo ? -_popEdad * 30 : 0.0;
    final popAlfa = _quieto ? 1.0 : (1 - m.max(0, _popEdad - 0.4) / 0.3).clamp(0.0, 1.0);
    final avisoVivo = _avisoEdad < 1.3;
    final avisoEsc = _completo ? 1 + 0.25 * m.max(0, 1 - _avisoEdad / 0.18) : 1.0;
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(
          child: CustomPaint(
            painter: PintorDestapa(j: _j, p: p, mov: widget.mov, agua: _agua, bump: _bump, gotas: _gotas),
          ),
        ),
        Positioned(
          left: c.dx - inodoro / 2,
          top: c.dy - inodoro / 2 + inodoro * 0.08,
          child: Emoji('🚽', tamano: inodoro),
        ),
        Positioned(
          left: c.dx - tapon / 2,
          top: c.dy - tapon / 2 - inodoro * 0.12,
          child: Emoji('💩', tamano: tapon),
        ),
        Positioned(
          left: c.dx - inodoro * 0.25,
          top: c.dy - g.lado * 0.5 - inodoro * 0.42 + baja,
          child: Emoji('🪠', tamano: inodoro * 0.5),
        ),
        if (h != null)
          Positioned(
            left: 0,
            right: 0,
            top: c.dy + g.lado / 2 + 8,
            child: Center(
              child: Text(tr('¡MANTÉN!', 'HOLD!'), style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: p.acento)),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: c.dy - g.lado / 2 - 34 - inodoro * 0.42 + popSube,
          child: Center(
            child: Opacity(
              opacity: popVivo ? popAlfa : 0,
              child: Transform.scale(
                scale: popEsc,
                child: Text(
                  _pop,
                  key: const Key('destapa_golpe'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _popColor ?? p.acento),
                ),
              ),
            ),
          ),
        ),
        if (avisoVivo && _aviso.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            top: 8,
            child: Center(
              child: Transform.scale(
                scale: avisoEsc,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: p.fondo, border: Border.all(color: p.acento), borderRadius: BorderRadius.circular(radio)),
                  child: Text(_aviso, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1, color: p.acento)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
