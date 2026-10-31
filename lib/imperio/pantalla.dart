import 'dart:async';

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'bienvenida.dart';
import 'control.dart';
import 'formato.dart';
import 'logros.dart' show presumirLogroImperio;
import 'moneda_app.dart';
import 'motor.dart';
import 'poceta.dart';
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
  bool _porDiez = false, _dialogoAbierto = false;

  // Desplegables de mejoras abiertos: id del edificio o 'poceta'.
  final _abiertos = <String>{};
  // Con cuántos de ese edificio sale la siguiente mejora (null = no depende de eso). Clave: 'edificio/mejora'.
  final _umbrales = <String, int?>{};

  // (emoji, texto, id del logro para PRESUMIR o null)
  final _cola = <(String, String, String?)>[];
  (String, String, String?)? _aviso;
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
    _pulso.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (!mounted) return;
    if (widget.activo) {
      while (_c.logrosNuevos.isNotEmpty) {
        final l = _c.logrosNuevos.removeAt(0);
        _avisar('🏆', tr('Logro: ${l.nombreEs}', 'Achievement: ${l.nombreEn}'), logro: l.id);
      }
      _mostrarDialogos();
    }
    setState(() {});
  }

  // ---------- Avisos de arriba ----------

  void _avisar(String emoji, String texto, {String? logro}) {
    _cola.add((emoji, texto, logro));
    if (_aviso == null) _siguienteAviso();
  }

  void _siguienteAviso() {
    _timerAviso?.cancel();
    if (!mounted) return;
    setState(() => _aviso = _cola.isEmpty ? null : _cola.removeAt(0));
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
            children: [
              Column(
                children: [
                  _cabecera(context, ahora),
                  if (_c.sinConexion) _sinConexion(context),
                  _poceta(ahora),
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
              if (_aviso != null) Positioned(top: 8, left: 16, right: 16, child: _banner(context, _aviso!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(BuildContext context, (String, String, String?) a) {
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
            if (a.$3 != null)
              TextButton(
                onPressed: () {
                  _siguienteAviso();
                  presumirLogroImperio(context, a.$3!);
                },
                child: Text(tr('PRESUMIR', 'SHOW OFF')),
              ),
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
                  Wrap(
                    spacing: 12,
                    children: [
                      Text('${_mj(im.mps(ahora))} /s', style: numeros(context, tamano: 14, color: p.textoSuave)),
                      Text('${_mj(im.valorPujo(ahora))} /pujo', style: numeros(context, tamano: 14, color: p.textoSuave)),
                    ],
                  ),
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

  Widget _poceta(int ahora) {
    final im = _c.imperio;
    final efectos = im.efectosActivos(ahora);
    // Mejoras compradas que no son de un edificio (tanque, válvula, imán, brillo, incienso) y las de pujo (guantes...).
    final accesorios = <String>[];
    for (final m in mejoras) {
      if ((m.edificio == null || m.familia == FamiliaMejora.clic) && im.mejoraComprada(m.id) && !accesorios.contains(m.emoji)) accesorios.add(m.emoji);
    }
    const conDibujo = {'fiebre_dorada', 'fiebre_trono', 'pujo_loco'};
    final otros = <String>[];
    for (final e in efectos) {
      if (!conDibujo.contains(e.id) && !otros.contains(e.emoji)) otros.add(e.emoji);
    }
    return Poceta(
      alTocar: _pujar,
      mps: im.mps(ahora),
      fiebre: im.enFiebre(ahora),
      pujoLoco: efectos.any((e) => e.id == 'pujo_loco'),
      efectos: otros,
      accesorios: accesorios,
      dedos: im.cantidad('dedo'),
      activo: widget.activo,
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
            Rotulo(tr('EDIFICIOS', 'BUILDINGS')),
            const Spacer(),
            _opcion(context, 'x1', !_porDiez, () => setState(() => _porDiez = false)),
            const SizedBox(width: 4),
            _opcion(context, 'x10', _porDiez, () => setState(() => _porDiez = true)),
          ],
        ),
      );

  Widget _listaEdificios(BuildContext context, int ahora) {
    final im = _c.imperio;
    final lista = [for (final e in edificiosFase1) if (im.edificioVisible(e.id)) e];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: lista.length + 1,
      itemBuilder: (context, i) => i == 0 ? _filaPoceta(context) : _filaEdificio(context, lista[i - 1], ahora),
    );
  }

  Widget _filaEdificio(BuildContext context, Edificio e, int ahora) {
    final p = paleta(context);
    final im = _c.imperio;
    final moneda = monedaActual().abreviatura;
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
    final n = _porDiez ? 10 : 1;
    final precio = im.precioEdificioVarios(e.id, n, ahora);
    final alcanza = precio <= im.saldo;
    final misterio = im.edificioMisterioso(e.id);
    // El Dedo no produce por segundo: suma a cada pujo. Los millonarios con mejoras de pujo muestran las dos cosas.
    final pujo = im.pujoEdificio(e.id, ahora);
    final porSegundo = '${_mj(im.mpsEdificio(e.id, ahora))} /s';
    final detalle = e.pujoBase > 0 ? '+${_mj(pujo)} /pujo' : (pujo > 0 ? '$porSegundo · +${_mj(pujo)} /pujo' : porSegundo);
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
        derecha: '${_mj(precio)} $moneda',
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

  /// Primera fila de la lista: las mejoras de la poceta (tanque, válvula, imán, brillo, incienso...).
  Widget _filaPoceta(BuildContext context) {
    final im = _c.imperio;
    final ofertas = im.mejorasPoceta();
    final listas = _alcanzan(ofertas);
    final fila = GestureDetector(
      onTap: () => _alternar('poceta'),
      child: _fila(
        context,
        emoji: '🚽',
        titulo: tr('TU POCETA', 'YOUR TOILET'),
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
                Text('${_mj(precio)} ${monedaActual().abreviatura}', style: numeros(context, tamano: 12, weight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: alcanza ? () => _c.comprarMejora(m.id) : null,
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
      bool apagada = false}) {
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
            ?extra,
          ],
        ),
      ),
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
                    Emoji(emoji, tamano: nota == null ? 24 : 20),
                    if (nota == null) const SizedBox(height: 2),
                    Text(texto, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6, color: p.texto)),
                    if (nota != null) Text(nota, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: p.textoSuave)),
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
          boton('🚽', tr('JALAR', 'FLUSH'), null, nota: tr('CON 15 CAGADAS', 'AT 15 POOPS')),
          boton('🕹️', tr('SALA', 'ARCADE'), () {
            _c.anotar('sala_abre');
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaSala()));
          }),
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
        ? _cagaVeces(o.candado)
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

String _cagaVeces(int n) => n == 1 ? tr('Caga 1 vez', 'Poop once') : tr('Caga $n veces', 'Poop $n times');
