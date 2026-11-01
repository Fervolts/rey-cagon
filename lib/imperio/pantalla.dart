import 'dart:async';
import 'dart:math' show max, min, pi, sin;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'bano.dart';
import 'barra.dart';
import 'bienvenida.dart';
import 'cadena.dart';
import 'cantidades.dart';
import 'cartera.dart';
import 'control.dart';
import 'fila.dart';
import 'formato.dart';
import 'hoja_racha.dart';
import 'logros.dart' show presumirLogroImperio;
import 'moneda_app.dart';
import 'motor.dart';
import 'personalizar.dart';
import 'poceta.dart';
import 'racha_imperio.dart' show diasRacha;
import 'sala.dart';
import 'tienda_ciruelas.dart';

String _mj(double v) => formatoMj(v, ingles: enIngles);

/// "1:05" o "1:02:05".
String _cuenta(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 31);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// "2 h 15 min" o "45 min".
String _duracionLarga(double segundos) {
  final min = (segundos / 60).floor();
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Aviso cuando el flag `imperio_activo` está apagado.
Widget _mantenimiento(BuildContext context) {
  final p = paleta(context);
  return Container(
    margin: const EdgeInsets.all(24),
    padding: const EdgeInsets.all(20),
    decoration: _caja(context, borde: p.bordeFuerte),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Emoji('🚧', tamano: 48),
        const SizedBox(height: 12),
        Text(tr('El Imperio está en mantenimiento', 'The Empire is under maintenance'),
            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: p.texto)),
      ],
    ),
  );
}

BoxDecoration _caja(BuildContext context, {Color? borde, Color? fondo}) {
  final p = paleta(context);
  return BoxDecoration(color: fondo ?? p.tarjeta, border: Border.all(color: borde ?? p.borde), borderRadius: BorderRadius.circular(radio));
}

/// Pestaña IMPERIO: el clicker. [activo] = la pestaña se ve (el bucle solo corre así).
class PantallaImperio extends StatefulWidget {
  const PantallaImperio({super.key, required this.activo});

  final bool activo;

  @override
  State<PantallaImperio> createState() => _PantallaImperioState();
}

class _PantallaImperioState extends State<PantallaImperio> with TickerProviderStateMixin {
  final _c = ControlImperio();
  late final AnimationController _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _dialogoAbierto = false;

  // Cuántos edificios compra cada toque (x1, x10, x100, x1000) y qué botones ya salieron alguna vez.
  int _cantidad = 1;
  var _cantidadesVistas = <int>{};
  bool _vistasCargadas = false;
  static const _claveVistas = 'imperio_cantidades_vistas';

  // Ciruelas que vuelan de la poceta al chip: (id, desde, hasta) en coordenadas de la escena.
  final _llaveEscena = GlobalKey();
  final _llavePoceta = GlobalKey();
  final _llaveCiruelas = GlobalKey();
  final _vuelos = <(int, Offset, Offset)>[];
  int _nVuelo = 0;

  // Desplegables de mejoras abiertos: id del edificio o 'poceta'.
  final _abiertos = <String>{};
  // Con cuántos de ese edificio sale la siguiente mejora (null = no depende de eso). Clave: 'edificio/mejora'.
  final _umbrales = <String, int?>{};

  // (emoji, texto, id del logro para PRESUMIR o null)
  final _cola = <(String, String, String?)>[];
  (String, String, String?)? _aviso;
  Timer? _timerAviso;
  int _nAviso = 0; // clave del Dismissible: cada aviso nuevo es otro widget

  @override
  void initState() {
    super.initState();
    _c.addListener(_alCambiar);
    _c.ciruelaCae.addListener(_alCaerCiruela);
    _c.visible = widget.activo;
    _c.iniciar();
    _cargarVistas();
  }

  @override
  void didUpdateWidget(PantallaImperio vieja) {
    super.didUpdateWidget(vieja);
    if (vieja.activo != widget.activo) {
      _c.visible = widget.activo;
      if (widget.activo) WidgetsBinding.instance.addPostFrameCallback((_) => _alCambiar());
    }
  }

  @override
  void dispose() {
    _timerAviso?.cancel();
    _c.removeListener(_alCambiar);
    _c.ciruelaCae.removeListener(_alCaerCiruela);
    _c.dispose();
    _pulso.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (!mounted) return;
    if (widget.activo) {
      while (_c.logrosNuevos.isNotEmpty) {
        final l = _c.logrosNuevos.removeAt(0);
        _avisar('🏆', tr('Logro: ${nombreLogro(l)}', 'Achievement: ${nombreLogro(l)}'), logro: l.id);
      }
      _mostrarDialogos();
    }
    setState(() {});
  }

  // ---------- Ciruelas 🫐 ----------

  void _alCaerCiruela() {
    if (!mounted) return;
    _avisar('🫐', tr('¡Cayó una Ciruela! Gástala en la tienda 🫐', 'A Plum dropped! Spend it in the shop 🫐'));
    if (movimiento(context) == Movimiento.nada) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final escena = _llaveEscena.currentContext?.findRenderObject() as RenderBox?;
      final poceta = _llavePoceta.currentContext?.findRenderObject() as RenderBox?;
      final chip = _llaveCiruelas.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || escena == null || poceta == null || chip == null || !escena.hasSize) return;
      Offset centro(RenderBox b) => escena.globalToLocal(b.localToGlobal(b.size.center(Offset.zero)));
      setState(() => _vuelos.add((_nVuelo++, centro(poceta), centro(chip))));
    });
  }

  Widget _ciruelaVolando((int, Offset, Offset) v) => Positioned.fill(
        key: ValueKey('vuelo_${v.$1}'),
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOutCubic,
            onEnd: () => setState(() => _vuelos.remove(v)),
            builder: (context, t, _) {
              // Sube en arco y se achica al llegar al chip.
              final pos = Offset.lerp(v.$2, v.$3, t)! + Offset(0, -70 * sin(pi * t));
              return Stack(children: [
                Positioned(
                  left: pos.dx - 18,
                  top: pos.dy - 18,
                  child: Transform.scale(scale: 1.5 - 0.9 * t, child: const Emoji('🫐', tamano: 36)),
                ),
              ]);
            },
          ),
        ),
      );

  // ---------- Cantidad de compra ----------

  Future<void> _cargarVistas() async {
    try {
      final guardadas = (await SharedPreferences.getInstance()).getStringList(_claveVistas) ?? const [];
      if (!mounted) return;
      setState(() => _cantidadesVistas = {..._cantidadesVistas, ...guardadas.map(int.tryParse).whereType<int>()});
    } catch (_) {
      // Sin preferencias: los botones salen igual cuando toque.
    }
    _vistasCargadas = true;
  }

  Set<int> _cantidadesVisibles() {
    final v = cantidadesDe(_c.imperio, _c.ahora, vistas: _cantidadesVistas);
    if (!_cantidadesVistas.containsAll(v)) {
      _cantidadesVistas = {..._cantidadesVistas, ...v};
      if (_vistasCargadas) {
        final lista = [for (final n in _cantidadesVistas) '$n'];
        SharedPreferences.getInstance().then((p) => p.setStringList(_claveVistas, lista)).ignore();
      }
    }
    return v;
  }

  // ---------- Avisos de arriba ----------

  void _avisar(String emoji, String texto, {String? logro}) {
    _cola.add((emoji, texto, logro));
    if (_aviso == null) _siguienteAviso();
  }

  void _siguienteAviso() {
    _timerAviso?.cancel();
    if (!mounted) return;
    setState(() {
      _aviso = _cola.isEmpty ? null : _cola.removeAt(0);
      _nAviso++;
    });
    if (_aviso != null) _timerAviso = Timer(Duration(milliseconds: _aviso!.$3 == null ? 2400 : 4500), _siguienteAviso);
  }

  // ---------- Diálogos al cargar (en orden, una vez cada uno) ----------

  Future<void> _mostrarDialogos() async {
    if (_dialogoAbierto || _c.cargando || !widget.activo) return;
    _dialogoAbierto = true;
    try {
      if (_c.bienvenidaPendiente) {
        _c.bienvenidaPendiente = false;
        final b = _c.imperio.bienvenida();
        await mostrarBienvenidaVeterano(context, cagadas: b.cagadas, multiplicador: b.multiplicador, fichas: b.fichas, fundador: _c.fundador);
      }
      final off = _c.offlinePendiente;
      if (off != null && mounted) {
        _c.offlinePendiente = null;
        await _dialogo('🌙', tr('MIENTRAS NO ESTABAS', 'WHILE YOU WERE AWAY'), [
          '+${_mj(off.ganado)} ${monedaActual().abreviatura}',
          tr('Fuera ${_duracionLarga(off.segundosAusente)}. Contó ${_duracionLarga(off.segundosContados)}.',
              'Away ${_duracionLarga(off.segundosAusente)}. Counted ${_duracionLarga(off.segundosContados)}.'),
          if (off.conBonus) tr('x1,5 por tu cagada tipo 6.', 'x1.5 from your type 6 poop.'),
          if (off.tanqueLleno) tr('Se llenó el tanque, compra uno más grande.', 'The tank filled up, buy a bigger one.'),
        ]);
      }
      final d = _c.descargaPendiente;
      if (d != null && mounted) {
        _c.descargaPendiente = null;
        final b = d.tipoBuff == null ? null : buffsTipo[d.tipoBuff];
        await _dialogo('💥', tr('¡DESCARGA!', 'DISCHARGE!'), [
          tr('+${_mj(d.ganado)} y Fiebre de Trono ${duracionFiebre.inSeconds} s', '+${_mj(d.ganado)} and Throne Fever ${duracionFiebre.inSeconds} s'),
          if (d.cantidad > 1) tr('${d.cantidad} cagadas nuevas.', '${d.cantidad} new poops.'),
          if (b != null) '${tr(b.nombreEs, b.nombreEn)}: ${tr(b.efectoEs, b.efectoEn)}',
        ]);
      }
      if (_c.rachaPendiente && mounted) {
        _c.rachaPendiente = false;
        await mostrarHojaRacha(context, _c, _avisar);
      }
    } finally {
      _dialogoAbierto = false;
    }
    if (mounted && (_c.offlinePendiente != null || _c.descargaPendiente != null || _c.bienvenidaPendiente || _c.rachaPendiente)) _mostrarDialogos();
  }

  Future<void> _dialogo(String emoji, String titulo, List<String> lineas) => showDialog<void>(
        context: context,
        builder: (context) {
          final p = paleta(context);
          return Dialog(
            insetPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: p.bordeFuerte)),
            backgroundColor: p.tarjeta,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Emoji(emoji, tamano: 64),
                  const SizedBox(height: 12),
                  Text(titulo, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.6, color: p.texto)),
                  const SizedBox(height: 12),
                  for (final (i, l) in lineas.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(l, textAlign: TextAlign.center, style: i == 0 ? numeros(context, tamano: 22, weight: FontWeight.w900) : TextStyle(fontSize: 15, height: 1.4, color: p.texto)),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('¡A PUJAR!', 'LET\'S PUSH!'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  // ---------- Acciones ----------

  ToquePoceta _pujar() {
    final r = _c.pujar();
    final texto = r.epico ? tr('¡ÉPICO! +${_mj(r.ganado)}', 'EPIC! +${_mj(r.ganado)}') : '+${_mj(r.ganado)}';
    return (texto: texto, epico: r.epico);
  }

  void _tocarDorado() {
    final r = _c.tocarDorado();
    if (r == null) return;
    final doble = r.doble ? tr(' (doble)', ' (double)') : '';
    final texto = switch (r.efecto) {
      EfectoDorado.fiebre => tr('Fiebre dorada x${multiplicadorFiebre.toInt()} por ${r.duracion.inSeconds} s', 'Golden fever x${multiplicadorFiebre.toInt()} for ${r.duracion.inSeconds} s'),
      EfectoDorado.lluvia => tr('Lluvia de mojones +${_mj(r.cantidad)}', 'Poop rain +${_mj(r.cantidad)}'),
      EfectoDorado.pujoLoco => tr('Pujo loco por ${r.duracion.inSeconds} s', 'Crazy push for ${r.duracion.inSeconds} s'),
      EfectoDorado.constructor => tr('Constructor: edificios -50% por ${r.duracion.inSeconds} s', 'Builder: buildings -50% for ${r.duracion.inSeconds} s'),
    };
    _avisar('🟡', '$texto$doble');
  }

  void _tocarAtasco() {
    final r = _c.tocarAtasco();
    if (r == null || !r.destapado) return;
    _avisar('🪠', r.perfecto ? tr('¡Destape perfecto! +${_mj(r.premio)}', 'Perfect unclog! +${_mj(r.premio)}') : tr('¡Destapado!', 'Unclogged!'));
  }

  // ---------- Pantalla ----------

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    if (_c.cargando) return Scaffold(backgroundColor: p.fondo, body: const Center(child: CircularProgressIndicator()));
    if (_c.apagado) return Scaffold(backgroundColor: p.fondo, body: Center(child: _mantenimiento(context)));
    final ahora = _c.ahora;
    final dorado = _c.imperio.dorado(ahora);
    final mov = movimiento(context);
    if (dorado != null && mov != Movimiento.nada) {
      if (!_pulso.isAnimating) _pulso.repeat(reverse: true);
    } else if (_pulso.isAnimating) {
      _pulso.stop();
    }
    return Scaffold(
      backgroundColor: p.fondo,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, caja) => Stack(
            key: _llaveEscena,
            children: [
              Column(
                children: [
                  _cabecera(context, ahora),
                  if (_c.sinConexion) _sinConexion(context),
                  KeyedSubtree(key: _llavePoceta, child: _poceta(ahora)),
                  _barraEfectos(context, ahora),
                  _pestanas(context),
                  Expanded(child: _listaEdificios(context, ahora)),
                  _botonesAbajo(context),
                ],
              ),
              if (dorado != null)
                Positioned(
                  left: dorado.x * (caja.maxWidth - 72),
                  top: dorado.y * (caja.maxHeight - 72),
                  child: GestureDetector(
                    onTap: _tocarDorado,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.9, end: 1.1).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
                      child: const SizedBox(width: 72, height: 72, child: Center(child: Emoji('🟡', tamano: 60))),
                    ),
                  ),
                ),
              for (final v in _vuelos) _ciruelaVolando(v),
              if (_aviso != null) Positioned(top: 8, left: 16, right: 16, child: _banner(context, _aviso!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(BuildContext context, (String, String, String?) a) {
    final p = paleta(context);
    // Se quita tocándolo o deslizándolo hacia cualquier lado.
    return Dismissible(
      key: ValueKey(_nAviso),
      onDismissed: (_) => _siguienteAviso(),
      child: GestureDetector(
        onTap: _siguienteAviso,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _caja(context, borde: p.primario),
          child: Row(
            children: [
              Emoji(a.$1, tamano: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(a.$2, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto))),
              if (a.$3 != null)
                TextButton(
                  onPressed: () {
                    _siguienteAviso();
                    presumirLogroImperio(context, a.$3!, guardar: _c.guardarTodo);
                  },
                  child: Text(tr('PRESUMIR', 'SHOW OFF')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sinConexion(BuildContext context) {
    final p = paleta(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: _caja(context, fondo: p.suave),
      child: Text(tr('Sin conexión: se guarda en el teléfono', 'Offline: saving on this phone'),
          style: TextStyle(fontSize: 12, color: p.textoSuave)),
    );
  }

  Widget _cabecera(BuildContext context, int ahora) {
    final p = paleta(context);
    final im = _c.imperio;
    final moneda = monedaActual();
    final racha = _c.racha;
    final rollos = im.partida.rollos;
    // Chips en una sola fila, todos del mismo ancho y alto.
    final chips = <Widget>[
      GestureDetector(
        onTap: () => _avisar('🎟️', tr('${im.fichas} Fichas para los minijuegos del ARCADE', '${im.fichas} Tokens for the ARCADE minigames')),
        child: _chip(context, '🎟️', '${im.fichas}'),
      ),
      // Ciruelas: abre la tienda. La llave es el destino de la ciruela que vuela.
      GestureDetector(
        key: const Key('chip_ciruelas'),
        onTap: () => _abrirObjetos(context),
        child: KeyedSubtree(key: _llaveCiruelas, child: _chip(context, '🫐', '${im.ciruelas}', borde: acento)),
      ),
      GestureDetector(
        onTap: () => _avisar('💩', tr('x${_mj(im.multiplicadorCagadas)} por tus ${im.cagadas} cagadas reales',
            'x${_mj(im.multiplicadorCagadas)} from your ${im.cagadas} real poops')),
        child: _chip(context, '💩', 'x${_mj(im.multiplicadorCagadas)}'),
      ),
      if (racha != null)
        GestureDetector(
          key: const Key('chip_racha'),
          onTap: () => mostrarHojaRacha(context, _c, _avisar),
          child: _chip(context, '🔥', '${racha.dia}/$diasRacha', borde: racha.reclamado ? null : acento),
        ),
      if (rollos > 0)
        GestureDetector(
          key: const Key('chip_rollos'),
          onTap: () => _avisar('🧻', tr('${_mj(rollos.toDouble())} Rollos de Oro: todo produce ${_pctRollos(im)} para siempre',
              '${_mj(rollos.toDouble())} Golden Rolls: everything makes ${_pctRollos(im)} forever')),
          child: _chip(context, '🧻', '${_mj(rollos.toDouble())} · ${_pctRollos(im)}'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _avisar('💩', moneda.nombre),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: montoMj(_mj(im.saldo), numeros(context, tamano: 32, weight: FontWeight.w900)),
                      ),
                      // MJ/s y MJ por toque en una sola línea: si no caben, se encogen (nunca se parten).
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(tr('${_mj(im.mps(ahora))} por seg  ·  ${_mj(im.valorPujo(ahora))} por toque',
                                '${_mj(im.mps(ahora))} per sec  ·  ${_mj(im.valorPujo(ahora))} per tap'),
                            maxLines: 1, softWrap: false, style: numeros(context, tamano: 13, color: p.textoSuave)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Presumir la cartera: en el chat o como imagen para historias.
              Tooltip(
                message: tr('Presumir cartera', 'Show off your wallet'),
                child: InkWell(
                  key: const Key('boton_cartera'),
                  onTap: () => compartirCartera(context, _c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: _caja(context),
                    child: Icon(Icons.ios_share, size: 18, color: p.texto),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(flex: i == chips.length - 1 && rollos > 0 ? 2 : 1, child: chips[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _pctRollos(Imperio im) => porcentajeRollos(im.partida.rollos, im.ajustes.rolloPct);

  Widget _chip(BuildContext context, String emoji, String texto, {Color? borde}) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: _caja(context, borde: borde),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Emoji(emoji, tamano: 16), const SizedBox(width: 5), Text(texto, style: numeros(context, tamano: 13, weight: FontWeight.w800))],
          ),
        ),
      );

  Widget _poceta(int ahora) {
    final im = _c.imperio;
    final efectos = im.efectosActivos(ahora);
    const conDibujo = {'fiebre_dorada', 'fiebre_trono', 'pujo_loco'};
    final otros = <String>[];
    for (final e in efectos) {
      if (!conDibujo.contains(e.id) && !otros.contains(e.emoji)) otros.add(e.emoji);
    }
    final jalar = botonJalar(im, _c.cadena);
    return Poceta(
      alTocar: _pujar,
      mps: im.mps(ahora),
      fiebre: im.enFiebre(ahora),
      pujoLoco: efectos.any((e) => e.id == 'pujo_loco'),
      efectos: otros,
      // Lo que se ve en el baño sale de lo comprado: adornos, mejoras de la poceta y de cada edificio.
      // Personalizar (Templo) oculta cosas, elige ambiente y cuántos dedos se ven: solo visual.
      bano: EstadoBano.desde(comprada: im.mejoraComprada, cantidad: im.cantidad, esteticas: im.esteticas, vista: im.partida.vista),
      dedos: min(im.cantidad('dedo'), (im.partida.vista['dedos'] as int?) ?? im.cantidad('dedo')),
      activo: widget.activo,
      // Cuánto más rápido va que lo normal (fiebre, pujo loco...): acelera la escena.
      apuro: im.mps(ahora) / max(im.mpsSinEfectos(), 1e-9),
      alPersonalizar: im.cantidad('templo') >= 1
          ? () => abrirPersonalizar(context, _c).then((_) => mounted ? setState(() {}) : null)
          : null,
      jalar: im.cadenaDesbloqueada ? jalar.encendido : null,
      alJalar: () => _jalar(context, jalar),
      // El cartelito solo la primera vez que la cadena queda lista.
      cartelJalar: jalar.encendido && im.partida.jaladas == 0,
    );
  }

  // Botón JALAR y palanca de la poceta hacen lo mismo.
  void _jalar(BuildContext context, BotonJalar jalar) {
    if (jalar.encendido) {
      unawaited(jalarLaCadena(context, _c, avisar: (e, t) => _avisar(e, t)));
    } else {
      _c.abrirCadena(false);
      _avisar('🚽', jalar.aviso(monedaActual().abreviatura));
    }
  }

  Widget _barraEfectos(BuildContext context, int ahora) {
    final efectos = _c.imperio.efectosActivos(ahora);
    if (efectos.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final e in efectos)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => _avisar(e.emoji, '${tr(e.nombreEs, e.nombreEn)}: ${tr(e.efectoEs, e.efectoEn)}'),
                child: _chip(context, e.emoji, e.restante == null ? tr(e.nombreEs, e.nombreEn) : _cuenta(e.restante!),
                    borde: paleta(context).primario),
              ),
            ),
        ],
      ),
    );
  }

  Widget _opcion(BuildContext context, String texto, bool elegida, VoidCallback alTocar) {
    final p = paleta(context);
    return GestureDetector(
      onTap: alTocar,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _caja(context, borde: elegida ? p.primario : p.borde, fondo: elegida ? p.primario : p.tarjeta),
        child: Text(texto, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8, color: elegida ? p.sobrePrimario : p.texto)),
      ),
    );
  }

  Widget _pestanas(BuildContext context) {
    final visibles = _cantidadesVisibles();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Rotulo(tr('EDIFICIOS', 'BUILDINGS')),
          const Spacer(),
          for (final n in cantidadesCompra)
            if (visibles.contains(n)) ...[
              if (n != cantidadesCompra.first) const SizedBox(width: 4),
              _opcion(context, 'x$n', _cantidad == n, () => setState(() => _cantidad = n)),
            ],
        ],
      ),
    );
  }

  Widget _listaEdificios(BuildContext context, int ahora) {
    final im = _c.imperio;
    final lista = [for (final e in edificios) if (im.edificioVisible(e.id)) e];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: lista.length + 1,
      itemBuilder: (context, i) => i == 0 ? _filaPoceta(context) : _filaEdificio(context, lista[i - 1], ahora),
    );
  }

  Widget _filaEdificio(BuildContext context, Edificio e, int ahora) {
    final p = paleta(context);
    final im = _c.imperio;
    final atasco = im.atasco;
    if (!im.edificioAbierto(e.id)) {
      return _fila(context, emoji: '🔒', titulo: _cagaVeces(e.candado), apagada: true);
    }
    if (atasco != null && atasco.edificio == e.id) {
      return GestureDetector(
        onTap: _tocarAtasco,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: _caja(context, borde: p.primario),
          child: Row(
            children: [
              const Emoji('🪠', tamano: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('¡ATASCADO! toca $toquesAtasco veces', 'CLOGGED! tap $toquesAtasco times'), style: TextStyle(fontWeight: FontWeight.w900, color: p.texto)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: atasco.toques / toquesAtasco, minHeight: 6, color: p.primario, backgroundColor: p.suave),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final n = _cantidad;
    final precio = im.precioEdificioVarios(e.id, n, ahora);
    final alcanza = precio <= im.saldo;
    final misterio = im.edificioMisterioso(e.id);
    // El Dedo no produce por segundo: suma a cada pujo. Los millonarios con mejoras de pujo muestran las dos cosas.
    final pujo = im.pujoEdificio(e.id, ahora);
    final porSegundo = '${_mj(im.mpsEdificio(e.id, ahora))} /s';
    final porToque = tr('+${_mj(pujo)} por toque', '+${_mj(pujo)} per tap');
    final detalle = e.pujoBase > 0 ? porToque : (pujo > 0 ? '$porSegundo · $porToque' : porSegundo);
    final abierto = _abiertos.contains(e.id);
    final ofertas = misterio ? const <Mejora>[] : im.mejorasDeEdificio(e.id);
    final siguiente = misterio ? null : im.siguienteMejora(e.id);
    final fila = GestureDetector(
      onTap: alcanza ? () => _c.comprarEdificio(e.id, n) : null,
      child: _fila(
        context,
        emoji: misterio ? '❓' : e.emoji,
        titulo: misterio ? '???' : tr(e.nombreEs, e.nombreEn),
        detalle: detalle,
        derecha: _mj(precio),
        contador: im.cantidad(e.id),
        resaltada: alcanza,
        extra: misterio || (ofertas.isEmpty && siguiente == null) ? null : _flecha(context, e.id, ofertas),
      ),
    );
    if (!abierto || misterio) return fila;
    return Column(children: [fila, _desplegable(context, ofertas, siguiente: siguiente, edificio: e)]);
  }

  // ---------- Desplegables de mejoras ----------

  /// Cuántas de estas mejoras alcanzan con el saldo de ahora.
  int _alcanzan(List<Mejora> ms) => ms.where((m) => _c.imperio.precioMejora(m) <= _c.imperio.saldo).length;

  void _alternar(String clave) {
    setState(() {
      if (!_abiertos.remove(clave)) {
        _abiertos.add(clave);
        _c.anotar('mejoras_abre', {'edificio': clave});
      }
    });
  }

  /// La ▼ de la derecha de una fila. Con borde de acento y número si hay mejoras que alcanzan.
  Widget _flecha(BuildContext context, String clave, List<Mejora> ofertas) {
    final p = paleta(context);
    final listas = _alcanzan(ofertas);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _alternar(clave),
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(left: 8),
        decoration: _caja(context, borde: listas > 0 ? p.primario : p.borde, fondo: listas > 0 ? p.primario : null),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedRotation(
              turns: _abiertos.contains(clave) ? .5 : 0,
              duration: movimiento(context) == Movimiento.nada ? Duration.zero : const Duration(milliseconds: 150),
              child: Icon(Icons.keyboard_arrow_down, size: 20, color: listas > 0 ? p.sobrePrimario : p.texto),
            ),
            if (listas > 0) Text('$listas', style: numeros(context, tamano: 10, weight: FontWeight.w900, color: p.sobrePrimario)),
          ],
        ),
      ),
    );
  }

  /// Primera fila de la lista: las mejoras del baño (adornos, tanque, válvula, imán, brillo, incienso...).
  Widget _filaPoceta(BuildContext context) {
    final im = _c.imperio;
    final ofertas = im.mejorasPoceta();
    final listas = _alcanzan(ofertas);
    final fila = GestureDetector(
      onTap: () => _alternar('poceta'),
      child: _fila(
        context,
        emoji: '🚽',
        titulo: tr('TU BAÑO', 'YOUR BATHROOM'),
        detalle: ofertas.isEmpty
            ? tr('Sin mejoras por ahora', 'No upgrades for now')
            : tr('${ofertas.length} ${ofertas.length == 1 ? 'mejora' : 'mejoras'}', '${ofertas.length} ${ofertas.length == 1 ? 'upgrade' : 'upgrades'}'),
        resaltada: listas > 0,
        extra: _flecha(context, 'poceta', ofertas),
      ),
    );
    if (!_abiertos.contains('poceta')) return fila;
    return Column(children: [fila, _desplegable(context, ofertas)]);
  }

  Widget _desplegable(BuildContext context, List<Mejora> ofertas, {Mejora? siguiente, Edificio? edificio}) {
    final p = paleta(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 0, 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: _caja(context, fondo: p.suave),
      child: Column(
        children: [
          if (ofertas.isEmpty && siguiente == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(tr('Nada por ahora. Sigue pujando.', 'Nothing yet. Keep pushing.'), style: TextStyle(fontSize: 12, color: p.textoSuave)),
            ),
          for (final m in ofertas) _filaMejora(context, m),
          if (siguiente != null && edificio != null) _filaSiguiente(context, siguiente, edificio),
        ],
      ),
    );
  }

  Widget _filaMejora(BuildContext context, Mejora m) {
    final p = paleta(context);
    final im = _c.imperio;
    final precio = im.precioMejora(m);
    final alcanza = precio <= im.saldo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Emoji(m.emoji, tamano: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(m.nombreEs, m.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.texto)),
                Text(tr(m.efectoEs, m.efectoEn), style: TextStyle(fontSize: 11, color: p.textoSuave)),
                montoMj(_mj(precio), numeros(context, tamano: 12, weight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: alcanza
                ? () async {
                    // La cadena borra la corrida al jalar: antes de comprarla se explica.
                    if (m.id == 'cadena_trono' && (!await confirmarComprarCadena(context, _c) || !mounted)) return;
                    _c.comprarMejora(m.id);
                  }
                : null,
            child: Text(tr('COMPRAR', 'BUY')),
          ),
        ],
      ),
    );
  }

  /// La que viene después, con candado y cuándo sale.
  Widget _filaSiguiente(BuildContext context, Mejora m, Edificio e) {
    final p = paleta(context);
    final im = _c.imperio;
    final hoy = im.cantidad(e.id);
    final n = _umbrales.putIfAbsent('${e.id}/${m.id}/$hoy', () => _umbral(m, e.id));
    final cuando = n == null
        ? tr('Sigue jugando para que salga', 'Keep playing to unlock it')
        : tr('Sale con $n ${e.nombreEs} (tienes $hoy)', 'Unlocks at $n ${e.nombreEn} (you have $hoy)');
    return Opacity(
      opacity: .6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Emoji('🔒', tamano: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(m.nombreEs, m.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.texto)),
                  Text(cuando, style: TextStyle(fontSize: 11, color: p.textoSuave)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Con cuántos de ese edificio se cumple la condición de la mejora, probando sobre una copia de la partida.
  /// null si no depende de la cantidad (o ya se cumple y falta otra cosa).
  int? _umbral(Mejora m, String id) {
    final copia = Partida.desdeJson(_c.imperio.partida.toJson());
    bool sale(int n) {
      copia.edificios[id] = n;
      return m.condicion(copia);
    }

    var bajo = copia.edificios[id] ?? 0, alto = 1000;
    if (sale(bajo) || !sale(alto)) return null;
    while (alto - bajo > 1) {
      final medio = (bajo + alto) ~/ 2;
      if (sale(medio)) {
        alto = medio;
      } else {
        bajo = medio;
      }
    }
    return alto;
  }

  Widget _fila(BuildContext context,
      {required String emoji,
      required String titulo,
      String? detalle,
      String? derecha,
      int? contador,
      Widget? extra,
      bool resaltada = false,
      bool apagada = false}) =>
      FilaImperio(
        emoji: emoji,
        titulo: titulo,
        detalle: detalle,
        derecha: derecha,
        contador: contador,
        extra: extra,
        resaltada: resaltada,
        apagada: apagada,
      );

  Widget _botonesAbajo(BuildContext context) {
    final jalar = botonJalar(_c.imperio, _c.cadena);
    final moneda = monedaActual().abreviatura;
    return BarraImperio(
      jalar: jalar,
      moneda: moneda,
      alObjetos: () => _abrirObjetos(context),
      alJalar: () => _jalar(context, jalar),
      alSala: () {
        _c.anotar('sala_abre');
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaSala()));
      },
    );
  }

  void _abrirObjetos(BuildContext context) =>
      abrirTiendaCiruelas(context, _c, _avisar, arriba: (_) => _HojaObjetos(control: _c, avisar: _avisar));
}

/// Objetos que se están pagando con Ciruelas (evita el doble toque mientras responde el servidor).
final Set<String> _pagandoCiruelas = {};

/// Sección OBJETOS de la tienda: cada uno se paga con MJ o con Ciruelas.
class _HojaObjetos extends StatelessWidget {
  const _HojaObjetos({required this.control, required this.avisar});
  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final ahora = control.ahora;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Rotulo(tr('Objetos', 'Items')),
        const SizedBox(height: 8),
        for (final o in objetos) _fila(context, p, im, o, ahora),
      ],
    );
  }

  Future<void> _conCiruelas(Objeto o) async {
    if (!_pagandoCiruelas.add(o.id)) return;
    try {
      final ok = await control.gastarCiruelas('obj_${o.id}');
      avisar(ok ? o.emoji : '🫐',
          ok ? tr('${o.nombreEs}: listo', '${o.nombreEn}: done') : tr('No te alcanzan las Ciruelas.', 'Not enough Plums.'));
    } catch (e) {
      avisar('💩', textoError(e));
    } finally {
      _pagandoCiruelas.remove(o.id);
    }
  }

  Widget _fila(BuildContext context, Paleta p, Imperio im, Objeto o, int ahora) {
    final abierto = im.objetoAbierto(o.id);
    final espera = im.esperaRestante(o.id, ahora);
    final precio = im.precioObjeto(o.id, ahora);
    // La Cagada fresca no se compra: sale sola 1 h después de cada cagada real.
    final esFicha = o.tipo == TipoObjeto.ficha;
    final fresca = esFicha ? im.efectosActivos(ahora).where((e) => e.id == o.id).firstOrNull?.restante : null;
    final candado = im.cagadas < o.candado ? _cagaVeces(o.candado) : tr('Sale con tu primer Atasco', 'Unlocks with your first Clog');
    final consumible = o.tipo == TipoObjeto.consumible;
    final estiloPrecio = numeros(context, tamano: 13, weight: FontWeight.w900);
    Widget pagar({required Widget precio, required bool puede, required VoidCallback alTocar, Key? key}) => Expanded(
          child: OutlinedButton(
            key: key,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 44)),
            onPressed: puede ? alTocar : null,
            child: precio,
          ),
        );
    return Opacity(
      opacity: abierto ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: _caja(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Emoji(abierto ? o.emoji : '🔒', tamano: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(o.nombreEs, o.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                      Text(abierto ? tr(o.descEs, o.descEn) : candado, style: TextStyle(fontSize: 12, color: p.textoSuave)),
                    ],
                  ),
                ),
                if (consumible) Text('${im.enInventario(o.id)}/${o.maxInventario}', style: numeros(context, tamano: 13, color: p.textoSuave)),
                if (espera != null) ...[
                  const SizedBox(width: 8),
                  const Emoji('⏳', tamano: 14),
                  const SizedBox(width: 3),
                  Text(_cuenta(espera), style: numeros(context, tamano: 12, color: p.textoSuave)),
                ],
              ],
            ),
            if (esFicha)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    fresca != null
                        ? tr('Activa: ${_cuenta(fresca)}', 'Active: ${_cuenta(fresca)}')
                        : tr('Gratis 1 h después de cada cagada real', 'Free for 1 h after each real poop'),
                    style: numeros(context, tamano: 12, color: p.textoSuave)),
              )
            else ...[
              const SizedBox(height: 8),
              Text(consumible ? tr('COMPRAR CON', 'BUY WITH') : tr('ALQUILAR CON', 'RENT WITH'),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: p.textoSuave)),
              const SizedBox(height: 4),
              Row(
                children: [
                  pagar(
                    key: Key('pagar_mj_${o.id}'),
                    precio: montoMj(_mj(precio), estiloPrecio, alineacion: Alignment.center),
                    puede: abierto && im.puedeComprarObjeto(o.id, ahora),
                    alTocar: () => control.comprarObjeto(o.id),
                  ),
                  if (o.ciruelas > 0) ...[
                    const SizedBox(width: 6),
                    pagar(
                      key: Key('pagar_ciruelas_${o.id}'),
                      precio: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('${o.ciruelas} ', style: estiloPrecio), const Emoji('🫐', tamano: 18)],
                      ),
                      puede: abierto && !_pagandoCiruelas.contains(o.id) && im.puedeComprarObjeto(o.id, ahora, conCiruelas: true),
                      alTocar: () => _conCiruelas(o),
                    ),
                  ],
                  if (consumible) ...[
                    const SizedBox(width: 6),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: abierto && im.enInventario(o.id) > 0 && espera == null ? () => control.usarObjeto(o.id) : null,
                      child: Text(tr('USAR', 'USE')),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _cagaVeces(int n) => n == 1 ? tr('Caga 1 vez', 'Poop once') : tr('Caga $n veces', 'Poop $n times');
