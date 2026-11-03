import 'dart:async';
import 'dart:math' show max, min, pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'alquilados.dart';
import 'bano.dart';
import 'barra.dart';
import 'bienvenida.dart';
import 'cadena.dart';
import 'cantidades.dart';
import 'cartera.dart';
import 'cofre.dart';
import 'control.dart';
import 'fichas.dart';
import 'fila.dart';
import 'formato.dart';
import 'guia_alquiler.dart';
import 'hallaca.dart';
import 'hoja_racha.dart';
import 'logros.dart' show presumirLogroImperio;
import 'mana.dart';
import 'moneda_app.dart';
import 'motor.dart';
import 'personalizar.dart';
import 'tarjeta_bano.dart' show presumirBano;
import 'poceta.dart';
import 'que_hago.dart';
import 'racha_imperio.dart' show diasRacha;
import 'recorrido.dart';
import 'regalos.dart' show ChipRegalos, hayRegalos;
import 'ranking_amigos.dart';
import 'sala.dart';
import 'tienda_ciruelas.dart';
import 'tienda_estilo.dart';
import 'version_minima.dart';

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
  const PantallaImperio({super.key, required this.activo, this.control});

  final bool activo;

  /// Para pruebas: un control ya armado en vez del que carga de la nube.
  @visibleForTesting
  final ControlImperio? control;

  @override
  State<PantallaImperio> createState() => _PantallaImperioState();
}

class _PantallaImperioState extends State<PantallaImperio> with TickerProviderStateMixin {
  late final ControlImperio _c = widget.control ?? ControlImperio();
  late final AnimationController _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _dialogoAbierto = false;

  // Recorrido guiado (recorrido.dart): mientras corre no salen empujones de la guía ni avisos de atascos.
  List<PasoRecorrido>? _pasosRecorrido;
  bool get _recorrido => _pasosRecorrido != null;

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

  // Cajón de edificios: entra desde la izquierda sobre el baño. 0 = cerrado, 1 = abierto.
  late final AnimationController _cajon = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addStatusListener((_) {
      if (mounted) setState(() {});
    });
  double _anchoCajon = 1; // ancho de la zona, para que el arrastre siga al dedo

  // Desplegables de mejoras abiertos: id del edificio o 'poceta'.
  final _abiertos = <String>{};
  // Con cuántos de ese edificio sale la siguiente mejora (null = no depende de eso). Clave: 'edificio/mejora'.
  final _umbrales = <String, int?>{};

  // (emoji, texto, id del logro para PRESUMIR o null)
  final _cola = <(String, String, String?)>[];
  (String, String, String?)? _aviso;
  (String, String, String?)? _juntos; // el aviso "+N logros" (junta los logros cuando son más de 3)
  int _nJuntos = 0;
  Timer? _timerAviso;
  final Set<Atasco> _atascosAvisados = Set.identity(); // los Atascos que ya se avisaron (por identidad)
  (String, String, String?)? _avisoAtascos; // el aviso "¡N atascos!" lleva un botón que abre los objetos
  int _nAviso = 0; // clave del Dismissible: cada aviso nuevo es otro widget
  // Empujones de la guía de los alquileres (uno a la vez, cada uno una vez) y la ficha resaltada en la tira.
  final _guia = EmpujonesAlquiler();
  Empujon? _empujon;
  Timer? _timerEmpujon;
  String? _resaltado;
  Timer? _timerResaltado;

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
    _timerEmpujon?.cancel();
    _timerResaltado?.cancel();
    _c.removeListener(_alCambiar);
    _c.ciruelaCae.removeListener(_alCaerCiruela);
    _c.dispose();
    _pulso.dispose();
    _cajon.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (!mounted) return;
    if (widget.activo) {
      // Más de 3 logros en cola se juntan en un solo aviso "+N logros" (si no, la cola tarda medio minuto).
      final enCola = _cola.where((a) => a.$3 != null).length + (_cola.contains(_juntos) ? _nJuntos : 0);
      if (_c.logrosNuevos.length + enCola > 3) {
        _nJuntos = _c.logrosNuevos.length + enCola;
        _c.logrosNuevos.clear();
        _cola.removeWhere((a) => a.$3 != null || a == _juntos);
        _juntos = ('🏆', tr('+$_nJuntos logros', '+$_nJuntos achievements'), null);
        _avisar(_juntos!.$1, _juntos!.$2);
      }
      while (_c.logrosNuevos.isNotEmpty) {
        final l = _c.logrosNuevos.removeAt(0);
        _avisar('🏆', tr('Logro: ${nombreLogro(l)}', 'Achievement: ${nombreLogro(l)}'), logro: l.id);
      }
      // Súper Plomero: 1 h de producción al primer tick del día.
      // Atasco nuevo (o el que quedó guardado): aviso arriba y vibración, para que no pase sin verse.
      // Con 2 o más abiertos (y sin Robot, que los destapa en el tick) avisa cuántos hay y lleva a los objetos.
      final atascos = _c.imperio.atascos;
      final nuevos = atascos.where((a) => !_atascosAvisados.contains(a)).toList();
      if (nuevos.isNotEmpty && !_recorrido) {
        if (atascos.length >= 2 && !_c.imperio.robotActivo(_c.ahora)) {
          final n = atascos.length;
          _avisoAtascos = ('🪠', tr('¡$n atascos! El Robot destapa solo', '$n clogs! The Plunger bot unclogs them by itself'), null);
          _avisar(_avisoAtascos!.$1, _avisoAtascos!.$2);
        } else {
          final e = edificioPorId(nuevos.last.edificio);
          final nombre = e == null ? '' : tr(e.nombreEs, e.nombreEn);
          _avisar('🪠', tr('¡Se tapó $nombre! No produce hasta que lo destapes', '$nombre is clogged! It won\'t produce until you unclog it'));
        }
        if (movimiento(context) != Movimiento.nada) HapticFeedback.mediumImpact();
      }
      _atascosAvisados
        ..clear()
        ..addAll(atascos);
      final regalo = _c.imperio.tomarRegaloPlomero();
      if (regalo > 0) {
        final mj = formatoMj(regalo, ingles: enIngles);
        _avisar('🦸', tr('El Súper Plomero te trajo +$mj', 'The Super Plumber brought you +$mj'));
      }
      if (_c.empujonPendiente) {
        _c.empujonPendiente = false;
        _avisar('🎁', tr('Empujón: producción x2 por 30 min', 'Boost: x2 production for 30 min'));
      }
      if (_c.cadenaSincronizadaPendiente) {
        _c.cadenaSincronizadaPendiente = false;
        _avisar('⛓️', tr('Tu cadena se puso al día con la nube', 'Your chain caught up with the cloud'));
      }
      _revisarEmpujon();
      _mostrarDialogos();
      _revisarRecorrido();
    }
    setState(() {});
  }

  /// El recorrido sale una sola vez, cuando no hay nada más en pantalla: ni carga, ni diálogos, ni hojas, ni pendientes.
  void _revisarRecorrido() {
    if (_recorrido || !widget.activo || _c.cargando || _c.apagado || _c.versionVieja || _dialogoAbierto) return;
    if (_c.bienvenidaPendiente || _c.offlinePendiente != null || _c.descargaPendiente != null || _c.rachaPendiente) return;
    if (!(ModalRoute.isCurrentOf(context) ?? true) || _c.imperio.partida.guiaVista.contains(claveRecorrido)) return;
    _empezarRecorrido();
  }

  void _empezarRecorrido() {
    if (_cajon.value > 0) _abrirCajon(false);
    _cerrarEmpujon();
    final jalar = botonJalar(_c.imperio, _c.cadena);
    setState(() => _pasosRecorrido = pasosRecorrido(_c.imperio, _c.ahora,
        moneda: monedaActual().abreviatura, jalarVisible: jalar.visible, cadenaLista: jalar.encendido));
  }

  void _queHago(BuildContext context) => abrirQueHago(context, _c,
      cadenaLista: () => botonJalar(_c.imperio, _c.cadena).encendido,
      alIr: (s) => switch (s.ir) {
            DestinoQueHago.edificios => _abrirCajon(true),
            DestinoQueHago.tienda => _abrirObjetos(context),
            DestinoQueHago.jalar => _jalar(context, botonJalar(_c.imperio, _c.cadena)),
            DestinoQueHago.cerrar => null,
          },
      alRecorrido: _empezarRecorrido);

  /// Un empujón de la guía de los alquileres si toca: nunca encima de un aviso, de otro empujón ni con una hoja abierta.
  void _revisarEmpujon() {
    if (_empujon != null || _aviso != null || _recorrido || _c.cargando || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    final e = _guia.siguiente(_c.imperio, _c.ahora);
    if (e == null) return;
    _timerEmpujon?.cancel();
    _timerEmpujon = Timer(duracionEmpujonGuia, _cerrarEmpujon);
    if (!e.tienda) {
      _timerResaltado?.cancel();
      _timerResaltado = Timer(duracionResaltado, () => mounted ? setState(() => _resaltado = null) : null);
    }
    // Primero el estado (marcarGuia avisa a los oyentes y vuelve a entrar aquí: así no salen dos).
    setState(() {
      _empujon = e;
      if (!e.tienda) _resaltado = e.id;
    });
    _c.marcarGuia(e.clave);
    _c.anotarGuia(e.id, 'empujon');
  }

  void _cerrarEmpujon() {
    _timerEmpujon?.cancel();
    if (mounted && _empujon != null) setState(() => _empujon = null);
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
          if (off.conBonus)
            off.fuerzaBonus < 1
                ? tr('x1,25 por tu cagada tipo 6 (cansado: mitad).', 'x1.25 from your type 6 poop (tired: half).')
                : tr('x1,5 por tu cagada tipo 6.', 'x1.5 from your type 6 poop.'),
          if (off.tanqueLleno) tr('Se llenó el tanque, compra uno más grande.', 'The tank filled up, buy a bigger one.'),
          if (off.regalo > 0) tr('Incluye +${_mj(off.regalo)} de regalo por volver.', 'Includes a +${_mj(off.regalo)} welcome back gift.'),
          if (off.atascoEdificio != null) _lineaAtascoOffline(off),
          if (off.atascos.length > 1)
            tr('Fueron ${off.atascos.length} atascos en total (${off.atascosTapados} siguen tapados).',
                '${off.atascos.length} clogs in total (${off.atascosTapados} still clogged).'),
        ]);
      }
      final d = _c.descargaPendiente;
      if (d != null && mounted) {
        _c.descargaPendiente = null;
        final b = d.tipoBuff == null ? null : buffsTipo[d.tipoBuff];
        await _dialogo('💥', tr('¡DESCARGA!', 'DISCHARGE!'), [
          tr('+${_mj(d.ganado)} y Fiebre de Trono ${duracionFiebre.inSeconds} s', '+${_mj(d.ganado)} and Throne Fever ${duracionFiebre.inSeconds} s'),
          if (d.cantidad > 1) tr('${d.cantidad} cagadas nuevas.', '${d.cantidad} new poops.'),
          if (b != null)
            d.fuerza <= 0
                ? tr('${b.nombreEs}: cansado, sin efecto. Cambia de tipo.', '${b.nombreEn}: tired, no effect. Switch types.')
                : '${tr(b.nombreEs, b.nombreEn)}: ${tr(b.efectoEs, b.efectoEn)}${d.fuerza < 1 ? tr(' (cansado: mitad)', ' (tired: half)') : ''}',
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

  /// Línea del Atasco offline en "Mientras no estabas": qué se atascó, a qué hora y cuánto se dejó de ganar.
  String _lineaAtascoOffline(ResultadoOffline off) {
    final e = edificioPorId(off.atascoEdificio!);
    final nombre = e == null ? '' : tr(e.nombreEs, e.nombreEn);
    final h = DateTime.fromMillisecondsSinceEpoch(off.atascoEn);
    final hora = '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
    if (off.atascoCubierto) return tr('🤖 A las $hora se atascó tu $nombre y se destapó solo.', '🤖 Your $nombre clogged at $hora and unclogged itself.');
    return tr('🪠 Tu $nombre se atascó a las $hora: dejaste de ganar ~${_mj(off.mjPerdidos)}. Un Robot destapador lo destapa solo; el Destapacaños, al instante.',
        '🪠 Your $nombre clogged at $hora: you missed ~${_mj(off.mjPerdidos)}. A Plunger bot unclogs it by itself; Drain cleaner, instantly.');
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
                      child: TextoConEmojis(l, textAlign: TextAlign.center, style: i == 0 ? numeros(context, tamano: 22, weight: FontWeight.w900) : TextStyle(fontSize: 15, height: 1.4, color: p.texto)),
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
    if (!r.contado) return (texto: '', epico: false, contado: false); // pasó del tope de pujos por segundo
    _guia.pujo(_c.ahora);
    final texto = r.epico ? tr('¡ÉPICO! +${_mj(r.ganado)}', 'EPIC! +${_mj(r.ganado)}') : '+${_mj(r.ganado)}';
    return (texto: texto, epico: r.epico, contado: true);
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
    final hallaca = _c.imperio.enTemporada(temporadaNavidad, _c.ahora);
    _avisar('🟡', hallaca ? tr('Hallaca dorada: $texto$doble', 'Golden hallaca: $texto$doble') : '$texto$doble');
  }

  void _tocarAtasco() {
    final r = _c.tocarAtasco();
    if (r == null) return;
    HapticFeedback.selectionClick();
    if (!r.destapado) return;
    HapticFeedback.heavyImpact();
    _avisar('🪠', r.perfecto ? tr('¡Destape perfecto! +${_mj(r.premio)}', 'Perfect unclog! +${_mj(r.premio)}') : tr('¡Destapado!', 'Unclogged!'));
  }

  // ---------- Pantalla ----------

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    if (_c.cargando) return Scaffold(backgroundColor: p.fondo, body: const Center(child: CircularProgressIndicator()));
    if (_c.apagado) return Scaffold(backgroundColor: p.fondo, body: Center(child: _mantenimiento(context)));
    if (_c.versionVieja) return Scaffold(backgroundColor: p.fondo, body: const Center(child: TarjetaVersionMinima()));
    final ahora = _c.ahora;
    final dorado = _c.imperio.dorado(ahora);
    final mov = movimiento(context);
    if (dorado != null && mov != Movimiento.nada) {
      if (!_pulso.isAnimating) _pulso.repeat(reverse: true);
    } else if (_pulso.isAnimating) {
      _pulso.stop();
    }
    final abierto = _cajon.value > 0 || _cajon.isAnimating;
    return PopScope(
      // Atrás cierra el cajón antes de salir (solo si la pestaña se ve).
      canPop: !(abierto && widget.activo),
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) _abrirCajon(false);
      },
      child: Scaffold(
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
                  if (_c.imperio.enTemporada(temporadaDiaRetrete, ahora)) _avisoTemporada(context, ahora),
                  Expanded(child: _zona(context, ahora)),
                  _botonesAbajo(context, ahora),
                ],
              ),
              if (dorado != null)
                Positioned(
                  left: dorado.x * (caja.maxWidth - 72),
                  top: dorado.y * (caja.maxHeight - 72),
                  child: GestureDetector(
                    key: const Key('mojon_dorado'),
                    onTap: _tocarDorado,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.9, end: 1.1).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Center(
                          // En Navidad el mojón dorado sale como hallaca dorada (mismo efecto, otro aspecto).
                          child: _c.imperio.enTemporada(temporadaNavidad, ahora)
                              ? const HallacaDorada(tamano: 60)
                              : const Emoji('🟡', tamano: 60),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final v in _vuelos) _ciruelaVolando(v),
              if (_aviso != null) Positioned(top: 8, left: 16, right: 16, child: _banner(context, _aviso!)),
              if (_aviso == null && _empujon != null)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: TarjetaEmpujon(
                    _empujon!,
                    alCerrar: _cerrarEmpujon,
                    alVer: _empujon!.tienda
                        ? () {
                            _cerrarEmpujon();
                            _abrirObjetos(context);
                          }
                        : null,
                  ),
                ),
              // Con llave: si sale o se va otro hijo de la pila (un atasco, el dorado) el recorrido no vuelve al paso 1.
              if (_pasosRecorrido case final pasos?)
                Positioned.fill(
                  key: const ValueKey('recorrido'),
                  child: RecorridoImperio(
                    control: _c,
                    pasos: pasos,
                    escena: _llaveEscena,
                    alTerminar: () => setState(() => _pasosRecorrido = null),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  // ---------- Cajón de edificios ----------

  void _abrirCajon(bool abrir) {
    if (movimiento(context) == Movimiento.nada) {
      _cajon.value = abrir ? 1 : 0;
    } else if (abrir) {
      _cajon.forward();
    } else {
      _cajon.reverse();
    }
  }

  void _arrastrarCajon(DragUpdateDetails d) => _cajon.value += (d.primaryDelta ?? 0) / _anchoCajon;

  // Se suelta: con impulso va hacia donde iba; si no, abre si pasó la mitad.
  void _soltarCajon(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    _abrirCajon(v.abs() > 300 ? v > 0 : _cajon.value > .5);
  }

  /// Cuántas cosas del cajón se pueden comprar ya (lo mismo que resaltan las filas y las ▼).
  int _comprables(int ahora) {
    final im = _c.imperio;
    var n = _alcanzan(im.mejorasPoceta());
    for (final e in edificios) {
      if (!im.edificioVisible(e.id) || !im.edificioAbierto(e.id) || im.atascado(e.id)) continue;
      if (im.precioEdificioVarios(e.id, _cantidad, ahora) <= im.saldo) n++;
      if (!im.edificioMisterioso(e.id)) n += _alcanzan(im.mejorasDeEdificio(e.id));
    }
    return n;
  }

  // El baño a todo el alto y el cajón encima. El cajón se abre con EDIFICIOS en la barra de abajo o arrastrando desde el borde.
  Widget _zona(BuildContext context, int ahora) {
    return LayoutBuilder(builder: (context, zona) {
      _anchoCajon = max(zona.maxWidth, 1);
      return Stack(
        children: [
          Positioned.fill(child: KeyedSubtree(key: const Key('recorrido_poceta'), child: KeyedSubtree(key: _llavePoceta, child: _poceta(ahora)))),
          // Atasco: la tarjeta para destaparlo también sale en el baño, no solo en el cajón de edificios.
          if (_c.imperio.atasco case final a?) Positioned(
              key: const Key('tarjeta_atasco'), left: 32, right: 12, bottom: 12, child: _tarjetaAtasco(context, a)),
          // Franja del borde: solo los arrastres que empiezan aquí abren el cajón (el resto es pujar).
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _arrastrarCajon,
              onHorizontalDragEnd: _soltarCajon,
            ),
          ),
          AnimatedBuilder(
            animation: _cajon,
            builder: (context, hijo) => Positioned.fill(
              child: Offstage(
                offstage: _cajon.value == 0,
                child: FractionalTranslation(translation: Offset(_cajon.value - 1, 0), child: hijo),
              ),
            ),
            child: _panelCajon(context, ahora),
          ),
        ],
      );
    });
  }

  Widget _panelCajon(BuildContext context, int ahora) {
    final p = paleta(context);
    return GestureDetector(
      // Opaco: con el cajón abierto no se puja por detrás. Arrastrar a la izquierda lo cierra.
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _arrastrarCajon,
      onHorizontalDragEnd: _soltarCajon,
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.fondo, border: Border(right: BorderSide(color: p.primario))),
        child: Column(
          children: [
            _pestanas(context, alCerrar: () => _abrirCajon(false)),
            _barraEfectos(context, ahora),
            Expanded(child: _listaEdificios(context, ahora)),
          ],
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
              Expanded(child: TextoConEmojis(a.$2, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto))),
              if (a.$3 == null && a == _avisoAtascos)
                TextButton(
                  onPressed: () {
                    _siguienteAviso();
                    _abrirObjetos(context);
                  },
                  child: Text(tr('VER', 'SEE')),
                ),
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

  /// Franja mientras dura el Día Mundial del Retrete (temporada del servidor): toda la producción va por su x.
  Widget _avisoTemporada(BuildContext context, int ahora) {
    final p = paleta(context);
    final x = _c.imperio.multiplicadorTemporadaAhora(ahora);
    final n = x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(1);
    return Container(
      key: const Key('aviso_temporada'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: _caja(context, borde: acento, fondo: p.suave),
      child: Row(
        children: [
          const Emoji('🚽', tamano: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr('Día Mundial del Retrete: todo x$n', 'World Toilet Day: everything x$n'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.texto)),
          ),
        ],
      ),
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
      // Fichas: abre la hoja de Fichas (fichas.dart).
      GestureDetector(
        key: const Key('chip_fichas'),
        onTap: () => abrirHojaFichas(context, _c, _avisar),
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
      if (_c.cofre != null) ChipCofre(control: _c, avisar: _avisar),
      // Rollos de regalo por abrir (regalos.dart): solo sale si hay alguno.
      if (hayRegalos(_c)) ChipRegalos(control: _c, avisar: _avisar),
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
                  key: const Key('recorrido_saldo'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _avisar('💩', moneda.nombre),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alto fijo: el saldo se encoge al no caber y, si el alto siguiera a la escala, la pantalla entera
                      // saltaría cada vez que cambian los dígitos.
                      SizedBox(
                        height: 40,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: montoMj(_mj(im.saldo), numeros(context, tamano: 32, weight: FontWeight.w900)),
                        ),
                      ),
                      // MJ/s y MJ por toque en una sola línea: si no caben, se encogen (nunca se parten).
                      SizedBox(
                        height: 18,
                        child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(tr('${_mj(im.mps(ahora))} por seg  ·  ${_mj(im.valorPujo(ahora))} por toque',
                                '${_mj(im.mps(ahora))} per sec  ·  ${_mj(im.valorPujo(ahora))} per tap'),
                            maxLines: 1, softWrap: false, style: numeros(context, tamano: 13, color: p.textoSuave)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Tienda de estilo: temas, efectos de CAGUÉ y movimientos del avatar.
              Tooltip(
                message: tr('Tienda de estilo', 'Style shop'),
                child: InkWell(
                  key: const Key('boton_estilo'),
                  onTap: () => abrirTiendaEstilo(context, _c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: _caja(context),
                    child: Icon(Icons.palette_outlined, size: 18, color: p.texto),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Ranking del Imperio: vive en la pestaña RANKING, este botón lleva ahí.
              Tooltip(
                message: tr('Ranking del Imperio', 'Empire leaderboard'),
                child: InkWell(
                  key: const Key('boton_ranking_imperio'),
                  onTap: verRankingImperio,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: _caja(context),
                    child: Icon(Icons.emoji_events_outlined, size: 18, color: p.texto),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mandar la foto del baño (como lo tengas personalizado) al chat.
              Tooltip(
                message: tr('Compartir mi baño', 'Share my bathroom'),
                child: InkWell(
                  key: const Key('boton_foto_bano'),
                  onTap: () => presumirBano(context, _c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: _caja(context),
                    child: Icon(Icons.photo_camera_outlined, size: 18, color: p.texto),
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
              const SizedBox(width: 6),
              BotonQueHago(alTocar: () => _queHago(context)),
            ],
          ),
          if (im.manaAbierto) ...[
            const SizedBox(height: 6),
            BarraMana(control: _c, avisar: (e, t) => _avisar(e, t), ahora: ahora),
          ],
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
    // Lo alquilado no va en la fila de efectos: lo dibuja la poceta (y su tira "trabajando ahora"). El bono del plomero
    // tampoco mientras el plomero está, que ya lleva su "x3".
    final plomero = im.alquiladoActivo('plomero_horas', ahora);
    final plomeroBono = efectos.any((e) => e.id == 'plomero_bono');
    final otros = <String>[];
    for (final e in efectos) {
      if (conDibujo.contains(e.id) || otros.contains(e.emoji)) continue;
      if (objetoPorId(e.id)?.tipo == TipoObjeto.alquilable || (plomero && e.id == 'plomero_bono')) continue;
      otros.add(e.emoji);
    }
    final jalar = botonJalar(im, _c.cadena);
    return Poceta(
      alTocar: _pujar,
      // Tocar una cosa del baño (bidet, cucaracha, camión...) también puja; además cuenta para los logros escondidos.
      alTocarObjeto: _c.tocarObjeto,
      mps: im.mps(ahora),
      fiebre: im.enFiebre(ahora),
      pujoLoco: efectos.any((e) => e.id == 'pujo_loco'),
      efectos: otros,
      // Lo que se ve en el baño sale de lo comprado: adornos, mejoras de la poceta y de cada edificio.
      // Personalizar (Templo) oculta cosas, elige ambiente y cuántos dedos se ven: solo visual.
      bano: EstadoBano.desde(comprada: im.mejoraComprada, cantidad: im.cantidad, esteticas: im.esteticas, vista: im.partida.vista, alquiler: (
        // Lo alquilado activo también se ve: los primos pujando, la cuadrilla, el plomero, el robot y el guardia.
        primos: im.alquiladoActivo('primo', ahora) ? im.primosActivos() : 0,
        cuadrilla: im.alquiladoActivo('cuadrilla', ahora),
        plomero: plomero,
        robot: im.alquiladoActivo('robot_turbo', ahora) ? 2 : (im.alquiladoActivo('robot', ahora) ? 1 : 0),
        guardia: im.alquiladoActivo('guardia', ahora),
      )),
      // Cada primo puja de verdad pujosPrimo veces por segundo; la poceta lo enseña en menos toques que lo juntan.
      pujoPrimo: im.valorPujo(ahora) * pujosPrimo,
      destapes: im.partida.destapes,
      comprasCuadrilla: im.comprasCuadrilla,
      ultimaCuadrilla: edificioPorId(im.ultimaCuadrilla ?? '')?.emoji,
      plomeroBono: plomeroBono,
      alquileres: fichasAlquiler(im, ahora),
      alTocarAlquiler: (f) => _avisar(f.emoji, avisoAlquiler(f)),
      alquilerResaltado: _resaltado,
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
      // El baño ocupa todo el alto de la zona: más pared y piso, la poceta igual.
      llenar: true,
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

  Widget _pestanas(BuildContext context, {VoidCallback? alCerrar}) {
    final p = paleta(context);
    final visibles = _cantidadesVisibles();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      child: Row(
        children: [
          Rotulo(tr('EDIFICIOS', 'BUILDINGS')),
          const Spacer(),
          for (final n in cantidadesCompra)
            if (visibles.contains(n)) ...[
              if (n != cantidadesCompra.first) const SizedBox(width: 4),
              _opcion(context, 'x$n', _cantidad == n, () => setState(() => _cantidad = n)),
            ],
          if (alCerrar != null) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: tr('Cerrar edificios', 'Close buildings'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: alCerrar,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: _caja(context),
                  child: Icon(Icons.close, size: 18, color: p.texto),
                ),
              ),
            ),
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

  /// El edificio atascado con el desatascador: cada toque salta un poco y llena la barra; a los [toquesAtasco] se destapa.
  Widget _tarjetaAtasco(BuildContext context, Atasco atasco) {
    final p = paleta(context);
    final e = edificioPorId(atasco.edificio);
    final nombre = e == null ? '' : tr(e.nombreEs, e.nombreEn);
    final quieto = movimiento(context) == Movimiento.nada;
    return GestureDetector(
      key: const Key('tarjeta_atasco'),
      behavior: HitTestBehavior.opaque,
      onTap: _tocarAtasco,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _caja(context, borde: p.primario),
        child: Row(
          children: [
            if (e != null) ...[Emoji(e.emoji, tamano: 28), const SizedBox(width: 6)],
            TweenAnimationBuilder<double>(
              key: ValueKey(atasco.toques),
              tween: Tween(begin: quieto ? 0 : 1, end: 0),
              duration: const Duration(milliseconds: 220),
              builder: (context, v, hijo) => Transform.translate(offset: Offset(0, 8 * v), child: hijo),
              child: const Emoji('🪠', tamano: 32),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('¡SE TAPÓ $nombre!', '$nombre CLOGGED!').toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: p.texto)),
                  Text(tr('Toca ${toquesAtasco - atasco.toques} veces para destapar', 'Tap ${toquesAtasco - atasco.toques} times to unclog'),
                      style: TextStyle(fontSize: 12, color: p.texto)),
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

  Widget _filaEdificio(BuildContext context, Edificio e, int ahora) {
    final im = _c.imperio;
    final atasco = im.atasco;
    if (!im.edificioAbierto(e.id)) {
      final faltan = im.faltanCandado(e.candado);
      if (im.candadoPagable(e.candado)) {
        final precio = im.precioCandado(e.candado);
        final alcanza = precio <= im.saldo;
        return GestureDetector(
          onTap: alcanza ? () => _c.pagarCandado(e.candado) : null,
          child: _fila(context,
              emoji: '🔒',
              titulo: _faltanCagadas(faltan),
              detalle: tr('Toca para abrirlo con MJ', 'Tap to unlock it with MJ'),
              derecha: _mj(precio),
              resaltada: alcanza,
              apagada: !alcanza),
        );
      }
      return _fila(context, emoji: '🔒', titulo: faltan > 0 ? _faltanCagadas(faltan) : _cagaVeces(e.candado), apagada: true);
    }
    if (atasco != null && atasco.edificio == e.id) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: _tarjetaAtasco(context, atasco));
    }
    // Los demás atascados salen parados: se destapan cuando les toque ser el primero (o con el Robot).
    if (im.atascado(e.id)) {
      return _fila(context,
          emoji: '🪠',
          titulo: tr(e.nombreEs, e.nombreEn),
          detalle: tr('Atascado: no produce hasta que lo destapes', 'Clogged: no output until you unclog it'),
          contador: im.cantidad(e.id),
          apagada: true);
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

  Widget _botonesAbajo(BuildContext context, int ahora) {
    final jalar = botonJalar(_c.imperio, _c.cadena);
    final moneda = monedaActual().abreviatura;
    final atascos = _c.imperio.atascos.length;
    final atasco = atascos > 0;
    final n = _comprables(ahora);
    return BarraImperio(
      // Abre o cierra el cajón.
      alEdificios: () => _abrirCajon(_cajon.value < 0.5),
      // Con atasco, el desatascador avisa que hay que entrar a destapar.
      atasco: atasco,
      avisoEdificios: atasco ? (atascos >= 2 ? tr('x$atascos', 'x$atascos') : '!') : (n > 0 ? (n > 99 ? '99+' : '$n') : null),
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
      abrirTiendaCiruelas(context, _c, arriba: (_, avisar) => _HojaObjetos(control: _c, avisar: avisar));
}

/// Objetos que se están pagando con Ciruelas (evita el doble toque mientras responde el servidor).
final Set<String> _pagandoCiruelas = {};

/// Cuántos periodos va a alquilar cada alquilable (1, 2, 5 o 10; 0 = Indefinido). Vive mientras la app esté abierta.
final Map<String, int> _vecesElegidas = {};

/// Multiplicador corto para la UI: x1,6 en español, x1.6 en inglés (sin ",0" de sobra).
String _xCorto(double v) {
  var s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return 'x${tr(s.replaceAll('.', ','), s)}';
}

/// Secciones OBJETOS y ALQUILER de la tienda: cada uno se paga con MJ o con Ciruelas.
class _HojaObjetos extends StatelessWidget {
  const _HojaObjetos({required this.control, required this.avisar});
  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final im = control.imperio;
    final ahora = control.ahora;
    final alquiler = [for (final o in objetos) if (o.tipo == TipoObjeto.alquilable) o];
    final a = im.ajustes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Rotulo(tr('Objetos', 'Items')),
        const SizedBox(height: 8),
        for (final o in objetos) if (o.tipo != TipoObjeto.alquilable) _fila(context, p, im, o, ahora),
        if (alquiler.isNotEmpty) ...[
          const SizedBox(height: 8),
          Rotulo(tr('Alquiler', 'Rentals')),
          const SizedBox(height: 4),
          Text(
              tr('Cada periodo que alquilas sube el próximo ${_xCorto(a.calorFactor)} (tope ${_xCorto(a.calorTope)}). '
                      'Se enfría a la mitad cada ${a.calorVidaMediaH.round()} h.',
                  'Each period you rent makes the next one ${_xCorto(a.calorFactor)} (max ${_xCorto(a.calorTope)}). '
                      'It cools down by half every ${a.calorVidaMediaH.round()} h.'),
              style: TextStyle(fontSize: 12, color: p.textoSuave)),
          const SizedBox(height: 8),
          for (final o in alquiler) _fila(context, p, im, o, ahora),
        ],
        if (im.objetosRollosAbiertos) ...[
          const SizedBox(height: 8),
          Rotulo(tr('Rollos de Oro', 'Golden Rolls')),
          const SizedBox(height: 4),
          Text(
              tr('Cada Rollo que gastas deja de darte ${porcentajeRollos(1, im.ajustes.rolloPct)}. Edificios y mejoras siguen abiertos.',
                  'Each Roll you spend stops giving you ${porcentajeRollos(1, im.ajustes.rolloPct)}. Buildings and upgrades stay open.'),
              style: TextStyle(fontSize: 12, color: p.textoSuave)),
          const SizedBox(height: 8),
          for (final r in objetosRollos) _filaRollos(context, p, im, r, ahora),
        ],
      ],
    );
  }

  void _comprarRollos(ObjetoRollos r) {
    if (control.comprarObjetoRollos(r.id)) avisar(r.emoji, tr('${r.nombreEs}: listo', '${r.nombreEn}: done'));
  }

  Widget _filaRollos(BuildContext context, Paleta p, Imperio im, ObjetoRollos r, int ahora) {
    final tiene = im.tieneObjetoRollos(r.id);
    final espera = r.id == 'cadena_reserva' ? im.esperaCadena(ahora) : null;
    final pendiente = r.id == 'cadena_reserva' && tiene > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: _caja(context),
      child: Row(
        children: [
          Emoji(r.emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(r.nombreEs, r.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                Text(tr(r.descEs, r.descEn), style: TextStyle(fontSize: 12, color: p.textoSuave)),
                const SizedBox(height: 2),
                Text(
                    pendiente
                        ? tr('Lista para tu próxima jalada', 'Ready for your next flush')
                        : espera != null
                            ? tr('Otra en ${_cuenta(espera)}', 'Another in ${_cuenta(espera)}')
                            : '$tiene/${r.limite}',
                    style: numeros(context, tamano: 11, color: p.textoSuave)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: Key('pagar_rollos_${r.id}'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 44)),
            onPressed: im.puedeComprarObjetoRollos(r.id, ahora) ? () => _comprarRollos(r) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('${r.costo} ', style: numeros(context, tamano: 13, weight: FontWeight.w900)), const Emoji('🧻', tamano: 18)],
            ),
          ),
        ],
      ),
    );
  }

  /// Hoja para elegir dónde va la Pintura marrón.
  Future<void> _elegirPintura(BuildContext context) {
    final im = control.imperio;
    final o = objetoPorId('pintura')!;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paleta(context).fondo,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
      builder: (hoja) {
        final p = paleta(hoja);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Rotulo(tr('¿Qué edificio pintas?', 'Which building do you paint?')),
                const SizedBox(height: 8),
                for (final id in im.edificiosParaPintura())
                  if (edificioPorId(id) case final e?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton(
                        key: Key('pintar_$id'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), alignment: Alignment.centerLeft),
                        onPressed: () {
                          Navigator.pop(hoja);
                          if (control.usarPintura(id)) {
                            avisar(o.emoji, tr('${e.nombreEs} pintado: +10% hasta jalar', '${e.nombreEn} painted: +10% until you flush'));
                          }
                        },
                        child: Row(
                          children: [
                            Emoji(e.emoji, tamano: 24),
                            const SizedBox(width: 10),
                            Expanded(child: Text(tr(e.nombreEs, e.nombreEn), style: TextStyle(color: p.texto))),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Por qué no se puede comprar o alquilar [o] ahora, con su emoji. null = sí se puede.
  /// Alquilable: [veces] periodos (0 = Indefinido).
  (String, String)? _porQueNo(Imperio im, Objeto o, int ahora, {bool conCiruelas = false, int veces = 1}) {
    if (!im.objetoAbierto(o.id)) {
      return ('🔒', im.faltanCandado(o.candado) > 0 ? _faltanCagadas(im.faltanCandado(o.candado)) : tr('Sale con tu primer Atasco', 'Unlocks with your first Clog'));
    }
    final n = o.maxInventario;
    if (o.tipo == TipoObjeto.consumible && im.enInventario(o.id) >= n) {
      return (o.emoji, tr('Ya tienes $n/$n: usa uno primero', 'You have $n/$n: use one first'));
    }
    final alquilable = o.tipo == TipoObjeto.alquilable;
    if (alquilable) {
      final queda = _cuenta(Duration(milliseconds: max(0, (im.partida.alquilados[o.id] ?? 0) - ahora)));
      if (o.duracion == null) {
        if (im.alquiladoActivo(o.id, ahora)) return (o.emoji, tr('Ya está activo hasta tu próximo offline', 'Already active until your next offline'));
      } else if (veces == 0) {
        if (conCiruelas) return ('🫐', tr('Con Ciruelas se alquila solo x1', 'Plums rent x1 only'));
        if (im.alquilerIndefinido(o.id)) {
          return (o.emoji, tr('Ya se renueva solo. Para cortarlo toca APAGAR', 'It already renews itself. Tap TURN OFF to stop it'));
        }
        if (im.alquiladoActivo(o.id, ahora)) return null;
      } else {
        if (conCiruelas && veces != 1) return ('🫐', tr('Con Ciruelas se alquila solo x1', 'Plums rent x1 only'));
        final caben = im.periodosQueCaben(o.id, ahora);
        if (caben == 0) return (o.emoji, tr('Ya está al máximo: $queda', 'Already maxed: $queda'));
        if (caben < veces) {
          return (o.emoji, tr('Solo caben x$caben más (va por $queda, tope x$vecesAlquilerMax)', 'Only x$caben more fits ($queda left, max x$vecesAlquilerMax)'));
        }
      }
    }
    if (conCiruelas) {
      final faltan = o.ciruelas - im.ciruelas;
      if (faltan > 0) return ('🫐', tr('Te faltan $faltan Ciruelas', 'You need $faltan more Plums'));
    } else {
      final precio = alquilable ? im.precioAlquiler(o.id, ahora, max(veces, 1)) : im.precioObjeto(o.id, ahora);
      final faltan = precio - im.saldo;
      if (faltan > 0) return ('💸', tr('Te faltan ${_mj(faltan)} ${monedaActual().abreviatura}', 'You need ${_mj(faltan)} more ${monedaActual().abreviatura}'));
    }
    return null;
  }

  /// Lo que dice el aviso después de comprar o alquilar [o].
  String _hechoTexto(Objeto o, {bool indefinido = false}) {
    final im = control.imperio;
    final nombre = tr(o.nombreEs, o.nombreEn);
    if (o.tipo == TipoObjeto.consumible) {
      return tr('$nombre: tienes ${im.enInventario(o.id)}/${o.maxInventario}. Toca USAR', '$nombre: you have ${im.enInventario(o.id)}/${o.maxInventario}. Tap USE');
    }
    if (o.duracion == null) return tr('¡$nombre alquilado! Activo hasta tu próximo offline', '$nombre rented! Active until your next offline');
    if (indefinido) {
      return tr('$nombre en Indefinido: se renueva solo mientras puedas pagarlo', '$nombre on Indefinite: it renews itself while you can pay');
    }
    final queda = _cuenta(Duration(milliseconds: (im.partida.alquilados[o.id] ?? 0) - control.ahora));
    return tr('¡$nombre alquilado! Activo: $queda', '$nombre rented! Active: $queda');
  }

  /// Periodos elegidos para [o] (0 = Indefinido). El Guardia y los que no son alquilables van de a uno.
  int _veces(Objeto o) => o.tipo == TipoObjeto.alquilable && o.duracion != null ? (_vecesElegidas[o.id] ?? 1) : 1;

  void _conMj(Objeto o) {
    final veces = _veces(o);
    if (_porQueNo(control.imperio, o, control.ahora, veces: veces) case (final emoji, final texto)) return avisar(emoji, texto);
    if (control.comprarObjeto(o.id, veces: max(veces, 1), indefinido: veces == 0)) {
      HapticFeedback.mediumImpact();
      avisar(o.emoji, _hechoTexto(o, indefinido: veces == 0));
    }
  }

  void _apagar(Objeto o) {
    if (!control.apagarIndefinido(o.id)) return;
    HapticFeedback.selectionClick();
    final queda = _cuenta(Duration(milliseconds: max(0, (control.imperio.partida.alquilados[o.id] ?? 0) - control.ahora)));
    avisar(o.emoji, tr('Indefinido apagado: le queda $queda y no se renueva', 'Indefinite off: $queda left, it will not renew'));
  }

  void _usar(BuildContext context, Objeto o, bool puedeUsar) {
    final im = control.imperio;
    final nombre = tr(o.nombreEs, o.nombreEn);
    if (!im.objetoAbierto(o.id)) return;
    if (im.enInventario(o.id) <= 0) return avisar(o.emoji, tr('No tienes $nombre: cómpralo primero', 'You have no $nombre: buy one first'));
    if (im.esperaRestante(o.id, control.ahora) case final espera?) {
      return avisar('⏳', tr('Lo puedes usar otra vez en ${_cuenta(espera)}', 'You can use it again in ${_cuenta(espera)}'));
    }
    if (!puedeUsar) {
      return avisar(o.emoji, o.id == 'destapacanos'
          ? tr('No hay ningún Atasco ahora', 'There is no Clog right now')
          : tr('No te queda ningún edificio sin pintar', 'No unpainted building left'));
    }
    if (o.id == 'pintura') return unawaited(_elegirPintura(context));
    if (!control.usarObjeto(o.id)) return;
    HapticFeedback.mediumImpact();
    avisar(o.emoji, switch (o.id) {
      'destapacanos' => tr('¡Destapado!', 'Unclogged!'),
      'papel' => tr('Listo: el próximo mojón dorado da el doble', 'Done: your next golden poop gives double'),
      _ => o.duracion == null
          ? tr('$nombre: usado', '$nombre: used')
          : tr('$nombre activo: ${_cuenta(o.duracion!)}', '$nombre active: ${_cuenta(o.duracion!)}'),
    });
  }

  Future<void> _conCiruelas(Objeto o) async {
    if (_porQueNo(control.imperio, o, control.ahora, conCiruelas: true, veces: _veces(o)) case (final emoji, final texto)) return avisar(emoji, texto);
    if (!_pagandoCiruelas.add(o.id)) return;
    try {
      final ok = await control.gastarCiruelas('obj_${o.id}');
      if (ok) HapticFeedback.mediumImpact();
      avisar(ok ? o.emoji : '🫐', ok ? _hechoTexto(o) : tr('No te alcanzan las Ciruelas.', 'Not enough Plums.'));
    } catch (e) {
      avisar('💩', textoError(e));
    } finally {
      _pagandoCiruelas.remove(o.id);
    }
  }

  /// Fila de un objeto. El selector x1/x2/x5/x10/∞ redibuja solo esta fila al tocarlo.
  Widget _fila(BuildContext context, Paleta p, Imperio im, Objeto o, int ahora) =>
      StatefulBuilder(builder: (context, refrescar) => _filaDentro(context, p, im, o, ahora, refrescar));

  Widget _filaDentro(BuildContext context, Paleta p, Imperio im, Objeto o, int ahora, StateSetter refrescar) {
    final abierto = im.objetoAbierto(o.id);
    final espera = im.esperaRestante(o.id, ahora);
    final precio = im.precioObjeto(o.id, ahora);
    // La Cagada fresca no se compra: sale sola 1 h después de cada cagada real.
    final esFicha = o.tipo == TipoObjeto.ficha;
    final fresca = esFicha ? im.efectosActivos(ahora).where((e) => e.id == o.id).firstOrNull?.restante : null;
    final candado = im.faltanCandado(o.candado) > 0 ? _faltanCagadas(im.faltanCandado(o.candado)) : tr('Sale con tu primer Atasco', 'Unlocks with your first Clog');
    final consumible = o.tipo == TipoObjeto.consumible;
    // Pintura: hace falta un edificio sin pintar. Destapacaños: hace falta un Atasco.
    final puedeUsar = switch (o.id) {
      'pintura' => im.edificiosParaPintura().isNotEmpty,
      'destapacanos' => im.partida.atasco != null,
      _ => true,
    };
    final alquilado = o.tipo == TipoObjeto.alquilable && im.alquiladoActivo(o.id, ahora);
    final finAlquiler = im.partida.alquilados[o.id] ?? 0;
    final estiloPrecio = numeros(context, tamano: 13, weight: FontWeight.w900);
    final alquilable = o.tipo == TipoObjeto.alquilable;
    // Alquilable con duración: se eligen los periodos (0 = Indefinido). El Guardia va de a uno.
    final elige = alquilable && o.duracion != null;
    final veces = _veces(o);
    final indef = alquilable && im.alquilerIndefinido(o.id);
    final precioPagar = alquilable ? im.precioAlquiler(o.id, ahora, max(veces, 1)) : precio;
    final puedeMj = abierto && (veces == 0 ? im.puedeIndefinido(o.id, ahora) : im.puedeComprarObjeto(o.id, ahora, veces: veces));
    final calorX = alquilable ? im.multiplicadorCalor(o.id, ahora) : 1.0;
    final estiloInfo = numeros(context, tamano: 11, color: p.textoSuave);
    final infoAlquiler = [
      if (calorX >= 1.05) Text('${_xCorto(calorX)} ${tr('por uso', 'from use')}', key: Key('calor_${o.id}'), style: estiloInfo),
      if (o.id == 'primo')
        Text(im.primosActivos() == 1 ? tr('1 primo', '1 cousin') : tr('${im.primosActivos()} primos', '${im.primosActivos()} cousins'),
            key: const Key('primos_cuenta'), style: estiloInfo),
    ];
    Widget opcion(int n) {
      final sel = veces == n;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: n == 0 ? 0 : 4),
          child: OutlinedButton(
            key: Key('veces_${o.id}_${n == 0 ? 'inf' : n}'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              backgroundColor: sel ? acento : null,
              foregroundColor: sel ? acentoTexto : p.texto,
              side: BorderSide(color: sel ? acento : p.borde),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              refrescar(() => _vecesElegidas[o.id] = n);
            },
            child: Text(n == 0 ? '∞' : 'x$n', style: numeros(context, tamano: 13, weight: FontWeight.w900, color: sel ? acentoTexto : p.texto)),
          ),
        ),
      );
    }
    // Sin poder pagar igual se toca: el aviso dice por qué (falta plata, espera, ya está al máximo).
    Widget pagar({required Widget precio, required bool puede, required VoidCallback alTocar, Key? key}) => Expanded(
          child: OutlinedButton(
            key: key,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 44),
              foregroundColor: puede ? null : p.textoSuave,
              side: puede ? null : BorderSide(color: p.borde),
            ),
            onPressed: alTocar,
            child: Opacity(opacity: puede ? 1 : 0.45, child: precio),
          ),
        );
    // El emoji salta cuando cambia lo que tienes (compraste, alquilaste o usaste).
    final quieto = movimiento(context) == Movimiento.nada;
    final emoji = TweenAnimationBuilder<double>(
      key: ValueKey('${o.id}_${im.enInventario(o.id)}_${finAlquiler}_$alquilado'),
      tween: Tween(begin: quieto ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      builder: (context, v, hijo) => Transform.scale(scale: 1 + 0.45 * v, child: hijo),
      child: Emoji(abierto ? o.emoji : '🔒', tamano: 30),
    );
    return Opacity(
      opacity: abierto ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: _caja(context, borde: alquilado ? acento : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Alquilable: tocar el emoji abre su ficha (lo mismo que el ?).
                if (alquilable && abierto) GestureDetector(onTap: () => alternarGuia(control, o.id), child: emoji) else emoji,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(o.nombreEs, o.nombreEn), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                      Text(abierto ? tr(o.descEs, o.descEn) : candado, style: TextStyle(fontSize: 12, color: p.textoSuave)),
                      if (abierto && infoAlquiler.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Wrap(spacing: 10, children: infoAlquiler),
                      ],
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
                if (alquilable && abierto) ...[
                  const SizedBox(width: 8),
                  BotonGuiaAlquiler(control: control, id: o.id),
                ],
              ],
            ),
            if (alquilable)
              GuiaAlquiler(
                control: control,
                objeto: o,
                ahora: ahora,
                alIr: puedeMj ? () => _conMj(o) : null,
                precioIr: '${_mj(precioPagar)} ${monedaActual().abreviatura}',
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
              if (alquilado) ...[
                Text(
                    o.duracion == null
                        ? tr('Activo hasta tu próximo offline', 'Active until your next offline')
                        : tr('Activo: ${_cuenta(Duration(milliseconds: finAlquiler - ahora))}',
                            'Active: ${_cuenta(Duration(milliseconds: finAlquiler - ahora))}'),
                    style: numeros(context, tamano: 12, color: acento)),
                const SizedBox(height: 6),
              ],
              if (indef) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          tr('∞ Se renueva solo. Próximo: ~${_mj(im.precioAlquiler(o.id, ahora, 1))} ${monedaActual().abreviatura}',
                              '∞ Renews itself. Next: ~${_mj(im.precioAlquiler(o.id, ahora, 1))} ${monedaActual().abreviatura}'),
                          style: numeros(context, tamano: 12, color: p.texto)),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      key: Key('apagar_indef_${o.id}'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 36)),
                      onPressed: () => _apagar(o),
                      child: Text(tr('APAGAR', 'TURN OFF')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              if (elige && abierto) ...[
                Row(children: [for (final n in opcionesAlquiler) opcion(n), opcion(0)]),
                const SizedBox(height: 6),
              ],
              Text(consumible ? tr('COMPRAR CON', 'BUY WITH') : tr('ALQUILAR CON', 'RENT WITH'),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: p.textoSuave)),
              const SizedBox(height: 4),
              Row(
                children: [
                  pagar(
                    key: Key('pagar_mj_${o.id}'),
                    precio: veces == 0 && alquilado
                        ? Text(tr('ACTIVAR ∞', 'TURN ON ∞'), style: estiloPrecio)
                        : montoMj(_mj(precioPagar), estiloPrecio, alineacion: Alignment.center),
                    puede: puedeMj,
                    alTocar: () => _conMj(o),
                  ),
                  if (o.ciruelas > 0) ...[
                    const SizedBox(width: 6),
                    pagar(
                      key: Key('pagar_ciruelas_${o.id}'),
                      precio: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('${o.ciruelas} ', style: estiloPrecio), const Emoji('🫐', tamano: 18)],
                      ),
                      puede: abierto && veces == 1 && !_pagandoCiruelas.contains(o.id) && im.puedeComprarObjeto(o.id, ahora, conCiruelas: true),
                      alTocar: () => _conCiruelas(o),
                    ),
                  ],
                  if (consumible) ...[
                    const SizedBox(width: 6),
                    Opacity(
                      opacity: abierto && im.enInventario(o.id) > 0 && espera == null && puedeUsar ? 1 : 0.4,
                      child: FilledButton(
                        key: Key('usar_${o.id}'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: abierto ? () => _usar(context, o, puedeUsar) : null,
                        child: Text(tr('USAR', 'USE')),
                      ),
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
String _faltanCagadas(int n) => n == 1 ? tr('Te falta 1 cagada', '1 more poop to go') : tr('Te faltan $n cagadas', '$n more poops to go');
