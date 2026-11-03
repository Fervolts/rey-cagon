// Regalos 🎁 (pantalla): el chip del Imperio con los Rollos por abrir, la hoja para abrirlos, el botón REGALAR del perfil
// y las tarjetas del chat ('regalo' y la genérica 'imperio'). Lo que responde el servidor está en regalos_datos.dart.

import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../animaciones.dart';
import '../avisos.dart' show ir;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show db, textoError;
import '../tema.dart';
import 'control.dart';
import 'formato.dart';
import 'regalos_datos.dart';
import 'telemetria.dart';

/// Lo piden la tarjeta del chat (ABRIR) y el push 'regalo': al llegar al Imperio, el chip abre la hoja de regalos.
/// Guarda cuándo se pidió: si el chip tarda más de un minuto en salir (sin red, sin Rollos), ya no se abre.
final pedirHojaRegalos = ValueNotifier<DateTime?>(null);

/// Pide abrir la hoja de regalos al llegar al Imperio y va para allá.
void irARegalos() {
  pedirHojaRegalos.value = DateTime.now();
  ir('imperio');
}

/// Si el chip 🎁 de regalos sale en la cabecera del Imperio: solo con Rollos por abrir.
bool hayRegalos(ControlImperio c) {
  final r = c.regalos;
  return r != null && r.activo && r.regalos.isNotEmpty;
}

/// Chip 🎁 ×N con los Rollos por abrir (el del Cofre dice x/3, ABRIR o ✓). Amarillo si hoy todavía se puede abrir alguno.
/// Al tocarlo abre [abrirHojaRegalos].
class ChipRegalos extends StatefulWidget {
  const ChipRegalos({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  State<ChipRegalos> createState() => _ChipRegalosState();
}

class _ChipRegalosState extends State<ChipRegalos> {
  @override
  void initState() {
    super.initState();
    pedirHojaRegalos.addListener(_pedida);
    _pedida();
  }

  @override
  void dispose() {
    pedirHojaRegalos.removeListener(_pedida);
    super.dispose();
  }

  void _pedida() {
    final pedida = pedirHojaRegalos.value;
    if (pedida == null) return;
    pedirHojaRegalos.value = null;
    if (DateTime.now().difference(pedida) > const Duration(minutes: 1)) return;
    // Después del cambio de pestaña (ir('imperio') cierra lo que haya encima en este mismo frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) abrirHojaRegalos(context, widget.control, widget.avisar);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final r = widget.control.regalos;
    if (r == null || r.regalos.isEmpty) return const SizedBox.shrink();
    final listo = r.puedeAbrir;
    return GestureDetector(
      key: const Key('chip_regalos'),
      onTap: () => abrirHojaRegalos(context, widget.control, widget.avisar),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: listo ? acento : p.tarjeta,
          border: Border.all(color: listo ? acento : p.borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Emoji('🎁', tamano: 16),
            const SizedBox(width: 5),
            Text('×${r.regalos.length}',
                style: numeros(context, tamano: 13, weight: FontWeight.w800, color: listo ? Colors.black : p.textoSuave)),
          ]),
        ),
      ),
    );
  }
}

/// Hoja con los Rollos de regalo por abrir: uno por fila, de quién viene y ABRIR.
Future<void> abrirHojaRegalos(BuildContext context, ControlImperio control, void Function(String emoji, String texto) avisar) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => HojaRegalos(control: control, avisar: avisar),
  );
}

class HojaRegalos extends StatefulWidget {
  const HojaRegalos({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  State<HojaRegalos> createState() => _HojaRegalosState();
}

class _HojaRegalosState extends State<HojaRegalos> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  /// El Rollo que se está abriendo.
  String? _abriendo;

  /// Lo último que salió: de quién y cuántos MJ.
  (String, double)? _premio;
  String? _error;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _abrir(Regalo g) async {
    if (_abriendo != null) return;
    setState(() {
      _abriendo = g.id;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    final m = movimiento(context);
    _anim.duration = Duration(milliseconds: m == Movimiento.completo ? 700 : 250);
    final animacion = m == Movimiento.nada ? Future<void>.value() : _anim.forward(from: 0).orCancel.catchError((_) {});
    try {
      final (r, mj) = await widget.control.abrirRegalo(g);
      await animacion;
      if (!mounted) return;
      if (r.ok) {
        HapticFeedback.heavyImpact();
        setState(() => _premio = (g.deNombre, mj));
      } else {
        setState(() => _error = textoMotivoRegalo(r.motivo));
      }
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
    } finally {
      if (mounted) {
        _anim.reset();
        setState(() => _abriendo = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.control, builder: (context, _) => _cuerpo(context));
  }

  Widget _cuerpo(BuildContext context) {
    final p = paleta(context);
    final r = widget.control.regalos ?? const EstadoRegalos();
    final premio = _premio;

    Widget rollo(String id) => AnimatedBuilder(
          animation: _anim,
          child: const Emoji('🧻', tamano: 28),
          builder: (context, child) {
            final t = _anim.value;
            if (t == 0 || _abriendo != id) return child!;
            return Transform.scale(scale: 1 + 0.3 * sin(pi * t), child: child);
          },
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Emoji('🎁', tamano: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Rotulo(tr('Rollos de regalo', 'Gift Rolls')),
                const SizedBox(height: 4),
                Text(
                  tr('Cada Rollo trae ${r.minutos} min de tu producción. Hoy puedes abrir ${r.abrirQuedan} más.',
                      'Each Roll holds ${r.minutos} min of your production. You can open ${r.abrirQuedan} more today.'),
                  style: TextStyle(color: p.textoSuave, fontSize: 13),
                ),
              ]),
            ),
          ]),
          if (premio != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('premio_regalo'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
              child: Row(children: [
                const Emoji('✨', tamano: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('+${formatoMj(premio.$2, ingles: enIngles)} MJ del Rollo de ${premio.$1}',
                        '+${formatoMj(premio.$2, ingles: enIngles)} MJ from ${premio.$1}\'s Roll'),
                    style: numeros(context, tamano: 14, weight: FontWeight.w800),
                  ),
                ),
              ]),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
          ],
          const SizedBox(height: 12),
          if (r.regalos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('No tienes Rollos por abrir.', 'No Rolls to open.'), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
            ),
          for (final g in r.regalos)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
              child: Row(children: [
                rollo(g.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('De ${g.deNombre}', 'From ${g.deNombre}'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                FilledButton(
                  key: Key('abrir_regalo_${g.id}'),
                  onPressed: r.puedeAbrir && _abriendo == null ? () => _abrir(g) : null,
                  child: Text(_abriendo == g.id ? tr('Abriendo...', 'Opening...') : tr('ABRIR', 'OPEN')),
                ),
              ]),
            ),
          if (r.regalos.isNotEmpty && r.abrirQuedan == 0)
            Text(textoMotivoRegalo('tope_abrir'), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            tr('Tú también puedes regalar: un Rollo al día a cada amigo (se siguen los dos), desde su perfil.',
                'You can gift too: one Roll a day to each friend (you follow each other), from their profile.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textoSuave, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}

/// Regala un Rollo a [para] (botón 🎁 REGALAR del perfil). Avisa con un SnackBar lo que dijo el servidor.
/// Devuelve lo que respondió (null si falló la red). [control], si hay Imperio abierto, pone los topes al día.
Future<ResultadoRegalo?> regalarRollo(BuildContext context, String para, String nombre, {ControlImperio? control}) async {
  final avisos = ScaffoldMessenger.of(context);
  void avisar(String texto) => avisos.showSnackBar(SnackBar(content: TextoConEmojis(texto)));
  try {
    final r = await const NubeRegalos().regalar(para);
    if (r.ok) {
      Telemetria.instancia.registrar('imperio_regalo_envia', {'dados': r.dados, 'en_chat': r.enChat});
      control?.regaloHecho(para, r);
      avisar(tr('🎁 Le regalaste un Rollo 🧻 a $nombre.', '🎁 You gifted $nombre a Roll 🧻.'));
    } else {
      avisar(textoMotivoRegalo(r.motivo));
    }
    return r;
  } catch (e) {
    avisar(textoError(e));
    return null;
  }
}

/// Tarjeta 'regalo' del chat {id, de, para, de_nombre, para_nombre}: la pone el servidor con el primer regalo del día.
/// Si el Rollo es para mí y sigue sin abrir, sale ABRIR: lleva al Imperio y abre la hoja de regalos.
class TarjetaRegalo extends StatefulWidget {
  const TarjetaRegalo(this.t, {super.key, this.yo, this.sinAbrir});

  final Map<String, dynamic> t;

  /// Para pruebas: mi id (si no, el de la sesión).
  final String? yo;

  /// Para pruebas: si el Rollo sigue sin abrir (si no, se le pregunta a la nube).
  final Future<bool?> Function(String id)? sinAbrir;

  @override
  State<TarjetaRegalo> createState() => _TarjetaRegaloState();
}

class _TarjetaRegaloState extends State<TarjetaRegalo> {
  Future<bool?>? _pendiente;

  String? get _yo {
    if (widget.yo != null) return widget.yo;
    try {
      return db.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final id = '${widget.t['id'] ?? ''}';
    if (id.isNotEmpty && _yo != null && widget.t['para'] == _yo) {
      _pendiente = (widget.sinAbrir ?? const NubeRegalos().sinAbrir)(id).catchError((_) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final de = '${widget.t['de_nombre'] ?? ''}'.trim();
    final para = '${widget.t['para_nombre'] ?? ''}'.trim();
    final linea = de.isEmpty || para.isEmpty
        ? tr('Regaló un Rollo de papel 🧻', 'Gifted a Roll of paper 🧻')
        : tr('$de le regaló un Rollo 🧻 a $para', '$de gifted $para a Roll 🧻');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Emoji('🎁', tamano: 32),
        const SizedBox(width: 10),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ROLLO DE REGALO', 'GIFT ROLL'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.textoSuave)),
            const SizedBox(height: 2),
            TextoConEmojis(linea, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (_pendiente != null)
              FutureBuilder<bool?>(
                future: _pendiente,
                builder: (context, s) => s.data != true
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FilledButton(
                          key: const Key('abrir_regalo_chat'),
                          onPressed: irARegalos,
                          child: Text(tr('ABRIR', 'OPEN')),
                        ),
                      ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Tarjeta genérica del Imperio {emoji, titulo, linea}, para avisos del Imperio en el chat (la Mudanza, por ejemplo).
/// Solo la pone el servidor: desde SQL, `select public.imperio_tarjeta_chat(user_id,
/// jsonb_build_object('tipo', 'imperio', 'emoji', '🏛️', 'titulo', 'Mudanza', 'linea', 'Se mudó a ...'))`.
/// validar_mensaje la recorta (emoji 8, titulo 60, linea 140). El emoji tiene que estar en el mapa de emoji.dart.
class TarjetaImperio extends StatelessWidget {
  const TarjetaImperio(this.t, {super.key});

  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final emoji = '${t['emoji'] ?? ''}'.trim();
    final titulo = '${t['titulo'] ?? ''}'.trim();
    final linea = '${t['linea'] ?? ''}'.trim();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Emoji(emoji.isEmpty ? '💩' : emoji, tamano: 32),
        const SizedBox(width: 10),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextoConEmojis(titulo.isEmpty ? tr('IMPERIO', 'EMPIRE') : titulo.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.textoSuave)),
            if (linea.isNotEmpty) ...[
              const SizedBox(height: 2),
              TextoConEmojis(linea, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ]),
    );
  }
}
