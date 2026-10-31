import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'bienvenida.dart';
import 'control.dart';
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';
import 'sala.dart';

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
  late final AnimationController _rebote = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  late final AnimationController _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _azar = Random();

  bool _mejorasTab = false, _porDiez = false, _dialogoAbierto = false;
  final _flotantes = <_DatosFlotante>[];
  int _idFlotante = 0;
  String? _ultimoPujo; // con movimiento "nada": se ve fijo debajo del mojón

  final _cola = <(String, String)>[];
  (String, String)? _aviso;
  Timer? _timerAviso;

  @override
  void initState() {
    super.initState();
    _c.addListener(_alCambiar);
    _c.visible = widget.activo;
    _c.iniciar();
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
    _c.dispose();
    _rebote.dispose();
    _pulso.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (!mounted) return;
    if (widget.activo) {
      while (_c.logrosNuevos.isNotEmpty) {
        final l = _c.logrosNuevos.removeAt(0);
        _avisar('🏆', tr('Logro: ${l.nombreEs}', 'Achievement: ${l.nombreEn}'));
      }
      _mostrarDialogos();
    }
    setState(() {});
  }

  // ---------- Avisos de arriba ----------

  void _avisar(String emoji, String texto) {
    _cola.add((emoji, texto));
    if (_aviso == null) _siguienteAviso();
  }

  void _siguienteAviso() {
    _timerAviso?.cancel();
    if (!mounted) return;
    setState(() => _aviso = _cola.isEmpty ? null : _cola.removeAt(0));
    if (_aviso != null) _timerAviso = Timer(const Duration(milliseconds: 2400), _siguienteAviso);
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
    } finally {
      _dialogoAbierto = false;
    }
    if (mounted && (_c.offlinePendiente != null || _c.descargaPendiente != null || _c.bienvenidaPendiente)) _mostrarDialogos();
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

  void _pujar() {
    final r = _c.pujar();
    final mov = movimiento(context);
    final texto = r.epico ? tr('¡ÉPICO! +${_mj(r.ganado)}', 'EPIC! +${_mj(r.ganado)}') : '+${_mj(r.ganado)}';
    if (mov == Movimiento.completo) _rebote.forward(from: 0);
    if (mov == Movimiento.nada) {
      _ultimoPujo = texto;
      return;
    }
    if (_flotantes.length > 14) _flotantes.removeAt(0);
    _flotantes.add(_DatosFlotante(_idFlotante++, texto, r.epico, _azar.nextDouble() * 120 - 60));
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
            children: [
              Column(
                children: [
                  _cabecera(context, ahora),
                  if (_c.sinConexion) _sinConexion(context),
                  _mojon(context, mov),
                  _barraEfectos(context, ahora),
                  _pestanas(context),
                  Expanded(child: _mejorasTab ? _listaMejoras(context) : _listaEdificios(context, ahora)),
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
              if (_aviso != null) Positioned(top: 8, left: 16, right: 16, child: _banner(context, _aviso!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(BuildContext context, (String, String) a) {
    final p = paleta(context);
    return GestureDetector(
      onTap: _siguienteAviso,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _caja(context, borde: p.primario),
        child: Row(
          children: [
            Emoji(a.$1, tamano: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(a.$2, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto))),
          ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Text('${_mj(im.saldo)} ${moneda.abreviatura}', style: numeros(context, tamano: 32, weight: FontWeight.w900)),
                  ),
                  Text('${_mj(im.mps(ahora))} /s', style: numeros(context, tamano: 14, color: p.textoSuave)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _chip(context, '🎟️', '${im.fichas}'),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _avisar('💩', tr('x${_mj(im.multiplicadorCagadas)} por tus ${im.cagadas} cagadas reales',
                'x${_mj(im.multiplicadorCagadas)} from your ${im.cagadas} real poops')),
            child: _chip(context, '💩', 'x${_mj(im.multiplicadorCagadas)}'),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String emoji, String texto, {Color? borde}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: _caja(context, borde: borde),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Emoji(emoji, tamano: 16), const SizedBox(width: 5), Text(texto, style: numeros(context, tamano: 13, weight: FontWeight.w800))],
        ),
      );

  Widget _mojon(BuildContext context, Movimiento mov) {
    final p = paleta(context);
    const lado = 168.0;
    final escala = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.92), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0), weight: 1),
    ]).animate(_rebote);
    return SizedBox(
      height: lado + 36,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _pujar(),
            child: ScaleTransition(
              scale: escala,
              child: Container(
                width: lado,
                height: lado,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.tarjeta, border: Border.all(color: p.primario, width: 3)),
                child: const Center(child: Emoji('💩', tamano: 104)),
              ),
            ),
          ),
          if (mov == Movimiento.nada && _ultimoPujo != null)
            Positioned(bottom: 0, child: Text(_ultimoPujo!, style: numeros(context, tamano: 16, weight: FontWeight.w900))),
          for (final f in _flotantes)
            _Flotante(
              key: ValueKey(f.id),
              datos: f,
              alTerminar: () {
                if (mounted) setState(() => _flotantes.remove(f));
              },
            ),
        ],
      ),
    );
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

  Widget _pestanas(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(
          children: [
            _opcion(context, tr('EDIFICIOS', 'BUILDINGS'), !_mejorasTab, () => setState(() => _mejorasTab = false)),
            const SizedBox(width: 6),
            _opcion(context, tr('MEJORAS', 'UPGRADES'), _mejorasTab, () => setState(() => _mejorasTab = true)),
            const Spacer(),
            if (!_mejorasTab) ...[
              _opcion(context, 'x1', !_porDiez, () => setState(() => _porDiez = false)),
              const SizedBox(width: 4),
              _opcion(context, 'x10', _porDiez, () => setState(() => _porDiez = true)),
            ],
          ],
        ),
      );

  Widget _listaEdificios(BuildContext context, int ahora) {
    final im = _c.imperio;
    final lista = [for (final e in edificiosFase1) if (im.edificioVisible(e.id)) e];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: lista.length,
      itemBuilder: (context, i) => _filaEdificio(context, lista[i], ahora),
    );
  }

  Widget _filaEdificio(BuildContext context, Edificio e, int ahora) {
    final p = paleta(context);
    final im = _c.imperio;
    final moneda = monedaActual().abreviatura;
    final atasco = im.atasco;
    if (!im.edificioAbierto(e.id)) {
      return _fila(context, emoji: '🔒', titulo: tr('Caga ${e.candado} veces', 'Poop ${e.candado} times'), apagada: true);
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
    final n = _porDiez ? 10 : 1;
    final precio = im.precioEdificioVarios(e.id, n, ahora);
    final alcanza = precio <= im.saldo;
    final misterio = im.edificioMisterioso(e.id);
    return GestureDetector(
      onTap: alcanza ? () => _c.comprarEdificio(e.id, n) : null,
      child: _fila(
        context,
        emoji: misterio ? '❓' : e.emoji,
        titulo: misterio ? '???' : tr(e.nombreEs, e.nombreEn),
        detalle: '${_mj(im.mpsEdificio(e.id, ahora))} /s',
        derecha: '${_mj(precio)} $moneda',
        contador: im.cantidad(e.id),
        resaltada: alcanza,
      ),
    );
  }

  Widget _fila(BuildContext context,
      {required String emoji, required String titulo, String? detalle, String? derecha, int? contador, bool resaltada = false, bool apagada = false}) {
    final p = paleta(context);
    return Opacity(
      opacity: apagada ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: _caja(context, borde: resaltada ? p.primario : p.borde),
        child: Row(
          children: [
            Emoji(emoji, tamano: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto), overflow: TextOverflow.ellipsis),
                  if (detalle != null) Text(detalle, style: numeros(context, tamano: 12, color: p.textoSuave)),
                ],
              ),
            ),
            if (derecha != null) Text(derecha, style: numeros(context, tamano: 13, weight: FontWeight.w800, color: resaltada ? p.texto : p.textoSuave)),
            if (contador != null) ...[
              const SizedBox(width: 10),
              SizedBox(width: 34, child: Text('$contador', textAlign: TextAlign.right, style: numeros(context, tamano: 20, weight: FontWeight.w900))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _listaMejoras(BuildContext context) {
    final p = paleta(context);
    final im = _c.imperio;
    final lista = im.mejorasDisponibles();
    final moneda = monedaActual().abreviatura;
    if (lista.isEmpty) {
      return Center(child: Text(tr('Nada por ahora. Sigue pujando.', 'Nothing yet. Keep pushing.'), style: TextStyle(color: p.textoSuave)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: lista.length,
      itemBuilder: (context, i) {
        final m = lista[i];
        final alcanza = m.precio <= im.saldo;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: _caja(context, borde: alcanza ? p.primario : p.borde),
          child: Row(
            children: [
              Emoji(m.emoji, tamano: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(m.nombreEs, m.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                    Text(tr(m.efectoEs, m.efectoEn), style: TextStyle(fontSize: 12, color: p.textoSuave)),
                    Text('${_mj(m.precio)} $moneda', style: numeros(context, tamano: 12, weight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: alcanza ? () => _c.comprarMejora(m.id) : null, child: Text(tr('COMPRAR', 'BUY'))),
            ],
          ),
        );
      },
    );
  }

  Widget _botonesAbajo(BuildContext context) {
    final p = paleta(context);
    Widget boton(String emoji, String texto, VoidCallback? alTocar, {String? nota}) => Expanded(
          child: GestureDetector(
            onTap: alTocar,
            child: Opacity(
              opacity: alTocar == null ? 0.45 : 1,
              child: Container(
                height: 64,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: _caja(context),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Emoji(emoji, tamano: 24),
                    const SizedBox(height: 2),
                    Text(texto, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6, color: p.texto)),
                    if (nota != null) Text(nota, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: p.textoSuave)),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 4, 13, 10),
      child: Row(
        children: [
          boton('🧴', tr('OBJETOS', 'ITEMS'), () => _abrirObjetos(context)),
          boton('🏆', tr('LOGROS', 'ACHIEVEMENTS'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PantallaLogros(control: _c)))),
          boton('🚽', tr('JALAR', 'FLUSH'), null, nota: tr('PRÓXIMAMENTE · 15 cagadas', 'SOON · 15 poops')),
          boton('🕹️', tr('SALA', 'ARCADE'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaSala()))),
        ],
      ),
    );
  }

  void _abrirObjetos(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: paleta(context).fondo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
        builder: (_) => ListenableBuilder(
          listenable: _c,
          builder: (context, _) => _HojaObjetos(control: _c, avisar: _avisar),
        ),
      );
}

// ---------- "+N" que sube y se apaga ----------

class _DatosFlotante {
  _DatosFlotante(this.id, this.texto, this.epico, this.dx);
  final int id;
  final String texto;
  final bool epico;
  final double dx;
}

class _Flotante extends StatefulWidget {
  const _Flotante({super.key, required this.datos, required this.alTerminar});
  final _DatosFlotante datos;
  final VoidCallback alTerminar;

  @override
  State<_Flotante> createState() => _FlotanteState();
}

class _FlotanteState extends State<_Flotante> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: Duration(milliseconds: widget.datos.epico ? 1200 : 800))
    ..forward().whenComplete(widget.alTerminar);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    final p = paleta(context);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, hijo) => Positioned(
        top: 60 - 70 * _a.value,
        child: Transform.translate(offset: Offset(d.dx, 0), child: Opacity(opacity: 1 - _a.value, child: hijo)),
      ),
      child: IgnorePointer(
        child: Text(d.texto,
            style: numeros(context, tamano: d.epico ? 28 : 18, weight: FontWeight.w900, color: d.epico ? p.primario : p.texto)),
      ),
    );
  }
}

// ---------- Objetos ----------

class _HojaObjetos extends StatelessWidget {
  const _HojaObjetos({required this.control, required this.avisar});
  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  Future<void> _cagadaFresca(BuildContext context) async {
    try {
      final ok = await control.usarCagadaFresca();
      if (!ok) avisar('🎟️', tr('No te quedan Fichas. Caga de verdad para ganar más.', 'No Tokens left. Poop for real to earn more.'));
    } catch (e) {
      avisar('💩', textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final ahora = control.ahora;
    final moneda = monedaActual().abreviatura;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Rotulo(tr('Objetos', 'Items')),
            const SizedBox(height: 10),
            for (final o in objetos) _fila(context, p, im, o, ahora, moneda),
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Paleta p, Imperio im, Objeto o, int ahora, String moneda) {
    final abierto = im.objetoAbierto(o.id);
    final espera = im.esperaRestante(o.id, ahora);
    final precio = im.precioObjeto(o.id, ahora);
    final esFicha = o.tipo == TipoObjeto.ficha;
    final candado = im.cagadas < o.candado
        ? tr('Caga ${o.candado} veces', 'Poop ${o.candado} times')
        : tr('Sale con tu primer Atasco', 'Unlocks with your first Clog');
    final botones = <Widget>[
      if (esFicha) FilledButton(onPressed: abierto && im.fichas > 0 ? () => _cagadaFresca(context) : null, child: Text(tr('USAR', 'USE'))),
      if (o.tipo == TipoObjeto.consumible) ...[
        OutlinedButton(
          onPressed: abierto && precio <= im.saldo && im.enInventario(o.id) < o.maxInventario ? () => control.comprarObjeto(o.id) : null,
          child: Text(tr('COMPRAR', 'BUY')),
        ),
        const SizedBox(width: 6),
        FilledButton(onPressed: abierto && im.enInventario(o.id) > 0 && espera == null ? () => control.usarObjeto(o.id) : null, child: Text(tr('USAR', 'USE'))),
      ],
      if (o.tipo == TipoObjeto.alquilable)
        FilledButton(onPressed: abierto && precio <= im.saldo ? () => control.comprarObjeto(o.id) : null, child: Text(tr('ALQUILAR', 'RENT'))),
    ];
    return Opacity(
      opacity: abierto ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: _caja(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                if (esFicha) ...[
                  Text('1 ', style: numeros(context, tamano: 13, weight: FontWeight.w800)),
                  const Emoji('🎟️', tamano: 16),
                ] else
                  Text('${_mj(precio)} $moneda', style: numeros(context, tamano: 13, weight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (o.tipo == TipoObjeto.consumible) Text('${im.enInventario(o.id)}/${o.maxInventario}', style: numeros(context, tamano: 12, color: p.textoSuave)),
                if (esFicha) Text(tr('Tienes ${im.fichas}', 'You have ${im.fichas}'), style: numeros(context, tamano: 12, color: p.textoSuave)),
                if (espera != null) ...[
                  const SizedBox(width: 10),
                  const Emoji('⏳', tamano: 14),
                  const SizedBox(width: 4),
                  Text(_cuenta(espera), style: numeros(context, tamano: 12, color: p.textoSuave)),
                ],
                const Spacer(),
                ...botones,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Logros ----------

class _PantallaLogros extends StatelessWidget {
  const _PantallaLogros({required this.control});
  final ControlImperio control;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(title: Text(tr('LOGROS', 'ACHIEVEMENTS'))),
      body: ListenableBuilder(
        listenable: control,
        builder: (context, _) {
          final im = control.imperio;
          final hechos = logros.where((l) => im.tieneLogro(l.id)).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [Rotulo(tr('Desbloqueados', 'Unlocked')), const Spacer(), Text('$hechos/${logros.length}', style: numeros(context))]),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.25),
                  itemCount: logros.length,
                  itemBuilder: (context, i) {
                    final l = logros[i];
                    final tiene = im.tieneLogro(l.id);
                    return Opacity(
                      opacity: tiene ? 1 : 0.4,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: _caja(context, borde: tiene ? p.primario : p.borde),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Emoji(tiene ? '🏆' : '🔒', tamano: 30),
                            const SizedBox(height: 6),
                            Text(tr(l.nombreEs, l.nombreEn), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.texto)),
                            const SizedBox(height: 2),
                            Text(tr(l.descEs, l.descEn), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: p.textoSuave)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
