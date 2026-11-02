// El chat en vivo: quién está escribiendo y las @menciones tocables. Aquí va solo la lógica
// pura y los widgets; el canal de realtime y las consultas viven en chat.dart.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'tema.dart';
import 'vitrina.dart' show tituloPorTotal;

/// Sin señal en este tiempo, se deja de mostrar que alguien escribe.
const vidaEscribiendo = Duration(seconds: 5);

/// Mientras escribes, a lo sumo un aviso cada tanto.
const pausaEscribiendo = Duration(milliseconds: 2500);

/// "Fulano está escribiendo", "Fulano y Mengano están escribiendo" o "Varios están escribiendo".
String textoEscribiendo(List<String> nombres) => switch (nombres.length) {
      0 => '',
      1 => tr('${nombres[0]} está escribiendo', '${nombres[0]} is typing'),
      2 => tr('${nombres[0]} y ${nombres[1]} están escribiendo', '${nombres[0]} and ${nombres[1]} are typing'),
      _ => tr('Varios están escribiendo', 'Several people are typing'),
    };

/// Quién escribe ahora mismo. [hilo] es null en la sala y el id del mensaje padre en un hilo.
class Escribiendo {
  final _hasta = <String, DateTime>{};
  final _perfil = <String, Map<String, dynamic>>{};
  final _hilo = <String, String?>{};

  bool get vacio => _hasta.isEmpty;

  void senal(String id, Map<String, dynamic> perfil, {String? hilo, DateTime? ahora}) {
    // Se quita y se vuelve a poner para que quede de último en el orden de llegada.
    final nuevo = !_hasta.containsKey(id) || _hilo[id] != hilo;
    if (nuevo) _hasta.remove(id);
    _hasta[id] = (ahora ?? DateTime.now()).add(vidaEscribiendo);
    _perfil[id] = perfil;
    _hilo[id] = hilo;
  }

  /// Devuelve si estaba.
  bool quitar(String id) {
    _perfil.remove(id);
    _hilo.remove(id);
    return _hasta.remove(id) != null;
  }

  /// Los que siguen escribiendo en ese lugar, en orden de llegada.
  List<String> vigentes({String? hilo, DateTime? ahora}) {
    final t = ahora ?? DateTime.now();
    return [
      for (final e in _hasta.entries)
        if (e.value.isAfter(t) && _hilo[e.key] == hilo) e.key,
    ];
  }

  Map<String, dynamic>? perfil(String id) => _perfil[id];

  /// Quita los vencidos. Devuelve si cambió algo.
  bool limpiar([DateTime? ahora]) {
    final t = ahora ?? DateTime.now();
    final vencidos = [for (final e in _hasta.entries) if (!e.value.isAfter(t)) e.key];
    vencidos.forEach(quitar);
    return vencidos.isNotEmpty;
  }

  /// Cuándo vence el próximo, para programar la limpieza.
  DateTime? get proximoVencimiento => _hasta.values.fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
}

/// Deja pasar un aviso cada [pausaEscribiendo] como mucho.
class Latido {
  DateTime? _ultimo;

  bool toca([DateTime? ahora]) {
    final t = ahora ?? DateTime.now();
    if (_ultimo != null && t.difference(_ultimo!) < pausaEscribiendo) return false;
    _ultimo = t;
    return true;
  }

  void reiniciar() => _ultimo = null;
}

/// Una @mención dentro de un texto: [inicio] es la @ y [fin] el final del nombre (exclusivo).
class Mencion {
  const Mencion(this.inicio, this.fin, this.username);

  final int inicio, fin;
  // En minúsculas, como llave para buscar el perfil.
  final String username;

  @override
  bool operator ==(Object other) => other is Mencion && other.inicio == inicio && other.fin == fin && other.username == username;

  @override
  int get hashCode => Object.hash(inicio, fin, username);

  @override
  String toString() => 'Mencion($inicio, $fin, $username)';
}

final _letra = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// Busca "@usuario" de los [usernames] conocidos. La @ no puede ir pegada a una letra; gana el
/// nombre más largo (los nombres pueden tener espacios) y después no puede seguir una letra.
List<Mencion> partirMenciones(String texto, Iterable<String> usernames) {
  final nombres = {for (final u in usernames) if (u.isNotEmpty) u.toLowerCase()}.toList()..sort((a, b) => b.length.compareTo(a.length));
  final salida = <Mencion>[];
  if (nombres.isEmpty) return salida;
  var i = 0;
  while (i < texto.length) {
    if (texto[i] != '@' || (i > 0 && _letra.hasMatch(texto[i - 1]))) {
      i++;
      continue;
    }
    Mencion? hallada;
    for (final n in nombres) {
      final fin = i + 1 + n.length;
      if (fin > texto.length || texto.substring(i + 1, fin).toLowerCase() != n) continue;
      if (fin < texto.length && _letra.hasMatch(texto[fin])) continue;
      hallada = Mencion(i, fin, n);
      break;
    }
    if (hallada == null) {
      i++;
    } else {
      salida.add(hallada);
      i = hallada.fin;
    }
  }
  return salida;
}

final _candidato = RegExp(r'(?<![\p{L}\p{N}_])@([^\s@]{2,24})', unicode: true);
final _puntuacionFinal = RegExp(r'''[.,;:!?)\]}"'»…]+$''');

/// Las palabras tras una @, tal cual se escribieron, para pedir sus perfiles de una vez.
Set<String> candidatosMencion(String texto) => {
      for (final m in _candidato.allMatches(texto))
        if (m.group(1)!.replaceAll(_puntuacionFinal, '') case final c when c.length >= 2) c,
    };

/// Da a los textos del chat los perfiles que se pueden mencionar y qué hacer al tocar uno.
class MencionesChat extends InheritedWidget {
  const MencionesChat({super.key, required this.perfiles, required this.alTocar, required super.child});

  // Llave: username en minúsculas.
  final Map<String, Map<String, dynamic>> perfiles;
  final void Function(BuildContext context, Offset donde, Map<String, dynamic> perfil) alTocar;

  static MencionesChat? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MencionesChat>();

  @override
  bool updateShouldNotify(MencionesChat oldWidget) => perfiles.length != oldWidget.perfiles.length || !perfiles.keys.every(oldWidget.perfiles.containsKey);
}

/// El chip de una mención dentro de la burbuja. [sobreAcento]: la burbuja propia, que ya es del acento.
WidgetSpan chipMencion(BuildContext context, String texto, Map<String, dynamic> perfil, {required TextStyle base, bool sobreAcento = false}) {
  final menciones = MencionesChat.maybeOf(context);
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Builder(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => menciones?.alTocar(context, d.globalPosition, perfil),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: sobreAcento ? acentoTexto.withValues(alpha: .12) : acento.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(radio),
          ),
          child: Text(texto, style: base.copyWith(fontWeight: FontWeight.w800)),
        ),
      ),
    ),
  );
}

/// El resumen que sale al tocar una mención; tocarlo abre el perfil.
Future<void> mostrarMencion(BuildContext context, Offset donde, Map<String, dynamic> perfil, {required VoidCallback abrirPerfil}) async {
  final p = paleta(context);
  final capa = Overlay.of(context).context.findRenderObject() as RenderBox;
  final punto = capa.globalToLocal(donde);
  final abrir = await showMenu<bool>(
    context: context,
    position: RelativeRect.fromRect(punto & const Size(1, 1), Offset.zero & capa.size),
    elevation: 0,
    color: p.tarjeta,
    menuPadding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio), side: BorderSide(color: p.borde)),
    items: [PopupMenuItem<bool>(value: true, padding: EdgeInsets.zero, child: TarjetaMencion(perfil))],
  );
  if (abrir == true) abrirPerfil();
}

class TarjetaMencion extends StatelessWidget {
  const TarjetaMencion(this.perfil, {super.key});

  final Map<String, dynamic> perfil;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final n = (perfil['cagadas'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Avatar(perfil, tamano: 44),
        const SizedBox(width: 12),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('@${perfil['username'] ?? ''}', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.texto, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(tituloPorTotal(n), style: TextStyle(color: p.textoSuave, fontSize: 12)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Emoji('💩', tamano: 14),
              const SizedBox(width: 4),
              Text(n == 1 ? tr('1 cagada', '1 poop') : tr('$n cagadas', '$n poops'), style: numeros(context, tamano: 12, color: p.texto)),
            ]),
            const SizedBox(height: 6),
            Text(tr('VER PERFIL ›', 'VIEW PROFILE ›'), style: numeros(context, tamano: 10, weight: FontWeight.w800, color: p.textoSuave)),
          ]),
        ),
      ]),
    );
  }
}

/// La franja de "Fulano está escribiendo…" sobre la caja de texto. Vacía si nadie escribe.
class IndicadorEscribiendo extends StatefulWidget {
  const IndicadorEscribiendo({super.key, required this.perfiles});

  final List<Map<String, dynamic>> perfiles;

  @override
  State<IndicadorEscribiendo> createState() => _IndicadorEscribiendoState();
}

class _IndicadorEscribiendoState extends State<IndicadorEscribiendo> with SingleTickerProviderStateMixin {
  late final _ciclo = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  var _mov = Movimiento.completo;

  @override
  void initState() {
    super.initState();
    movimientoElegido.addListener(_ajustar);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustar();
  }

  @override
  void didUpdateWidget(IndicadorEscribiendo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ajustar();
  }

  // Solo se anima si hay alguien y el movimiento no está apagado.
  void _ajustar() {
    if (!mounted) return;
    final mov = movimiento(context);
    if (mov != _mov) setState(() => _mov = mov);
    final animar = mov != Movimiento.nada && widget.perfiles.isNotEmpty;
    if (animar && !_ciclo.isAnimating) {
      _ciclo.repeat();
    } else if (!animar && _ciclo.isAnimating) {
      _ciclo.stop();
    }
  }

  @override
  void dispose() {
    movimientoElegido.removeListener(_ajustar);
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final quienes = widget.perfiles;
    final nada = _mov == Movimiento.nada;
    return AnimatedSize(
      duration: nada ? Duration.zero : const Duration(milliseconds: 150),
      alignment: Alignment.bottomCenter,
      child: quienes.isEmpty
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borde))),
              child: AnimatedBuilder(
                animation: _ciclo,
                builder: (context, _) => Row(children: [
                  for (var i = 0; i < math.min(quienes.length, 3); i++)
                    Padding(padding: const EdgeInsets.only(right: 2), child: _avatar(quienes[i], i)),
                  const SizedBox(width: 4),
                  for (var i = 0; i < 3; i++) _punto(p, i),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      textoEscribiendo([for (final q in quienes) '${q['username'] ?? '…'}']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textoSuave, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  // Con movimiento completo el avatar brinca y se mece; si no, quieto.
  Widget _avatar(Map<String, dynamic> perfil, int i) {
    final a = Avatar(perfil, tamano: 18, animarMovimiento: false);
    if (_mov != Movimiento.completo) return a;
    final t = (_ciclo.value + i * .33) * 2 * math.pi;
    return Transform.translate(
      offset: Offset(0, -2.5 * math.sin(t).abs()),
      child: Transform.rotate(angle: .08 * math.sin(t / 2), child: a),
    );
  }

  // Tres cuadritos que se encienden uno tras otro. Quietos si el movimiento está apagado.
  Widget _punto(Paleta p, int i) {
    var alfa = 1.0;
    if (_mov != Movimiento.nada) {
      final fase = (_ciclo.value - i * .2) % 1.0;
      alfa = .3 + .7 * math.max(0.0, math.sin(fase * math.pi));
    }
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.only(right: 2),
      color: p.textoSuave.withValues(alpha: alfa),
    );
  }
}
