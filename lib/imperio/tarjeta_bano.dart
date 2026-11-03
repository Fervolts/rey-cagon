// Presumir el baño en el chat: una "foto" del baño. No se sube ninguna imagen: la tarjeta trae lo que dibuja el baño
// (lo arma el servidor desde tu fila, rama 'bano' de validar_mensaje) y aquí se pinta con el código del juego, quieto.

import 'dart:math';

import 'package:flutter/material.dart';

import '../animaciones.dart';
import '../chat.dart' show aceptoReglas, nombreSala;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show db, textoError;
import '../presumir.dart' show preguntarPresumir;
import '../tema.dart';
import 'bano.dart';
import 'casas.dart';
import 'control.dart';
import 'personalizar.dart' show nombreAmbiente;
import 'poceta.dart';

/// Edificios que viajan en la tarjeta (los que mira `EstadoBano.desde`). Igual que el array de la migración.
const edificiosTarjetaBano = [
  'dedo', 'ciruela', 'cafe', 'arepa', 'inodoro', 'bano', 'camion', 'planta', 'cloaca', 'granja', //
  'mina', 'templo', 'volcan', 'laxante_tiempo', 'agujero',
];

/// Mejoras que viajan en la tarjeta (las que dibujan algo). La misma expresión que la migración.
const mejorasTarjetaBano = r'^((adorno|tanque|valvula|dedo|ciruela|cafe|arepa|inodoro|bano|camion|planta)_[a-z0-9]{1,20}|iman|brillo|lavanda|guantes|faja)$';

final _mejora = RegExp(mejorasTarjetaBano);
final _estetica = RegExp(r'^est_[a-z0-9_]{1,40}$');
final _oculto = RegExp(r'^[a-z0-9_]{1,40}$');
final _ambiente = RegExp(r'^[a-z]{1,20}$');

// Como jsonb_array_elements_text: textos tal cual, números y sí/no como texto; lo demás no cuenta.
String? _texto(Object? x) => x is String ? x : (x is num || x is bool ? '$x' : null);

List<String> _limpios(Object? lista, RegExp patron, int tope) {
  final r = {for (final x in lista is List ? lista : const []) ?_texto(x)}.where(patron.hasMatch).toList()..sort();
  return r.take(tope).toList();
}

/// La tarjeta que arma el servidor desde la partida guardada ([estado], `Partida.toJson`) y las estéticas compradas.
/// Copia la rama 'bano' de `validar_mensaje`: solo lo que dibuja el baño, lo que venga mal se vuelve vacío.
Map<String, dynamic> tarjetaBano(Object? estado, Iterable<Object?> esteticas) {
  final e = estado is Map ? estado : const {};
  final ed = e['edificios'] is Map ? e['edificios'] as Map : const {};
  final v = e['vista'] is Map ? e['vista'] as Map : const {};
  final ocultos = _limpios(v['ocultos'] is List ? v['ocultos'] : null, _oculto, 100);
  final dedos = v['dedos'];
  final ambiente = v['ambiente'];
  final m = e['mudanzas'];
  final ab = e['abdicaciones'];
  return {
    'tipo': 'bano',
    // En qué casa va (0 = Rancho). El servidor lo saca de la fila, igual que lo demás.
    'mudanzas': m is num && m.isFinite && m > 0 ? m.floor() : 0,
    // Cuántas veces abdicó (la dinastía del pie). También de la fila.
    'abdicaciones': ab is num && ab.isFinite && ab > 0 ? ab.floor() : 0,
    'edificios': {
      for (final id in edificiosTarjetaBano)
        if (ed[id] is num && (ed[id] as num) >= 1) id: (ed[id] as num) >= 1000000 ? 1000000 : (ed[id] as num).floor(),
    },
    'mejoras': _limpios(e['mejoras'], _mejora, 200),
    'esteticas': _limpios(esteticas.toList(), _estetica, 100),
    'vista': {
      if (ocultos.isNotEmpty) 'ocultos': ocultos,
      if (dedos is num && dedos.isFinite) 'dedos': dedos.clamp(0, 24).floor(),
      if (ambiente is String && _ambiente.hasMatch(ambiente)) 'ambiente': ambiente,
    },
  };
}

/// Lo que dibuja una tarjeta del chat: el baño y cuántos dedos se ven. Aguanta datos rotos o vacíos (baño básico).
({EstadoBano bano, int dedos, int mudanzas, int abdicaciones}) banoDeTarjeta(Map<String, dynamic> t) {
  final limpia = tarjetaBano(t, t['esteticas'] is List ? t['esteticas'] as List : const []);
  final ed = limpia['edificios'] as Map<String, int>;
  final mejoras = (limpia['mejoras'] as List<String>).toSet();
  final vista = limpia['vista'] as Map<String, Object>;
  int cantidad(String id) => ed[id] ?? 0;
  final bano = EstadoBano.desde(
      comprada: mejoras.contains, cantidad: cantidad, esteticas: (limpia['esteticas'] as List<String>).toSet(), vista: vista);
  // Igual que en la pestaña: lo elegido en Personalizar, nunca más de los que tienes.
  final tope = min(cantidad('dedo'), Poceta.topeDedos);
  final dedos = min(tope, (vista['dedos'] as int?) ?? tope);
  return (bano: bano, dedos: dedos, mudanzas: limpia['mudanzas'] as int, abdicaciones: limpia['abdicaciones'] as int);
}

/// La escena quieta: el baño a su tamaño de verdad, en 4:3 (el baño es apaisado), encogido a lo que le den.
class _Escena extends StatelessWidget {
  const _Escena(this.bano, this.dedos);

  final EstadoBano bano;
  final int dedos;

  @override
  Widget build(BuildContext context) {
    final alto = Bano.altura(bano);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: alto * 4 / 3,
            height: alto,
            child: IgnorePointer(
              child: Poceta(alTocar: () => (texto: '', epico: false, contado: true), mps: 0, bano: bano, dedos: dedos, activo: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// La tarjeta "foto del baño" del chat: marco tipo polaroid con el baño y el pie "🚽 Mi baño · ambiente".
/// Al tocarla se abre en grande.
class TarjetaBano extends StatelessWidget {
  const TarjetaBano(this.t, {super.key});

  final Map<String, dynamic> t;

  static const anchoMaximo = 280.0;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final (:bano, :dedos, :mudanzas, :abdicaciones) = banoDeTarjeta(t);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: anchoMaximo),
        child: Semantics(
          button: true,
          label: tr('Foto del baño. Toca para verla en grande', 'Bathroom photo. Tap to see it big'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _verGrande(context, bano, dedos, mudanzas, abdicaciones),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(border: Border.all(color: p.borde)),
                  child: _Escena(bano, dedos),
                ),
                _Pie(bano.ambiente, mudanzas, abdicaciones, color: p.texto, suave: p.textoSuave),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "🚽 Mi baño" a la izquierda y el ambiente a la derecha.
class _Pie extends StatelessWidget {
  const _Pie(this.ambiente, this.mudanzas, this.abdicaciones, {required this.color, required this.suave, this.tamano = 13});

  final AmbienteBano ambiente;
  final int mudanzas, abdicaciones;
  final Color color, suave;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final (emoji, nombre) = nombreAmbiente(ambiente, mudanzas);
    // Desde la primera mudanza el pie dice en qué casa está el baño: "🏡 Quinta"; tras abdicar, con la dinastía:
    // "🛖 Rancho · Dinastía II".
    final casa = mudanzas > 0 || abdicaciones > 0
        ? conDinastia(casaConEmoji(mudanzas), abdicaciones)
        : '🚽 ${tr('Mi baño', 'My bathroom')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      // Cada lado se queda con lo suyo (el ambiente, que es más largo, con más sitio) y va pegado a la derecha aunque
      // sea corto.
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
          flex: 2,
          child: TextoConEmojis(casa,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: tamano, fontWeight: FontWeight.w900, color: color)),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 3,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Emoji(emoji, tamano: tamano),
            const SizedBox(width: 4),
            Flexible(
              child: Text(nombre.toUpperCase(),
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  textWidthBasis: TextWidthBasis.longestLine, // partido en dos, que el emoji siga pegado al texto
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'monospace', fontSize: tamano - 3, color: suave, letterSpacing: 1)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Fondo de la vista en grande.
const _fondoGrande = Color(0xFF0D0D0D);

Future<void> _verGrande(BuildContext context, EstadoBano bano, int dedos, int mudanzas, int abdicaciones) {
  final quieto = movimiento(context) == Movimiento.nada;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Cerrar', 'Close'),
    barrierColor: _fondoGrande,
    transitionDuration: quieto ? Duration.zero : const Duration(milliseconds: 160),
    transitionBuilder: (context, a, _, hijo) => quieto ? hijo : FadeTransition(opacity: a, child: hijo),
    pageBuilder: (context, _, _) => _Grande(bano, dedos, mudanzas, abdicaciones),
  );
}

class _Grande extends StatelessWidget {
  const _Grande(this.bano, this.dedos, this.mudanzas, this.abdicaciones);

  final EstadoBano bano;
  final int dedos, mudanzas, abdicaciones;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _fondoGrande,
      child: SafeArea(
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 56, 12, 24),
            // Lo más grande que quepa a lo ancho y a lo alto (acostado o en tablet también), dejando sitio al pie.
            child: LayoutBuilder(builder: (context, c) {
              final ancho = min(min(c.maxWidth, 720.0), max(0.0, c.maxHeight - 56) * 4 / 3);
              return Center(
                child: SizedBox(
                  width: ancho,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
                      child: _Escena(bano, dedos),
                    ),
                    _Pie(bano.ambiente, mudanzas, abdicaciones, color: Colors.white, suave: Colors.white60, tamano: 15),
                  ]),
                ),
              );
            }),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              key: const Key('tarjeta_bano_cerrar'),
              tooltip: tr('Cerrar', 'Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Presume el baño en la sala general: muestra cómo sale, pide las reglas y manda la tarjeta. El servidor arma la
/// tarjeta desde la fila guardada, por eso se guarda primero.
Future<void> presumirBano(BuildContext context, ControlImperio control) async {
  final mensajero = ScaffoldMessenger.maybeOf(context);
  void aviso(String texto) => mensajero
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
  final guardado = control.guardarTodo();
  final im = control.imperio;
  // La vista previa sale de lo mismo que lee el servidor: sale igual que en el chat.
  final previa = tarjetaBano(im.partida.toJson(), im.esteticas);
  final si = await preguntarPresumir(context,
      titulo: tr('📸 Foto del baño', '📸 Bathroom photo'), tarjeta: TarjetaBano(previa), boton: tr('PRESUMIR', 'SHOW IT OFF'));
  if (!si || !context.mounted) return;
  if (!await aceptoReglas(context)) return;
  try {
    await guardado;
    await db.from('mensajes').insert({
      'sala': 'global',
      'tarjeta': {'tipo': 'bano'},
    });
    control.anotar('bano_compartir');
    aviso(tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
  } catch (e) {
    // textoError traduce los del servidor ("Espera un rato…", "Todavía no tienes Imperio").
    aviso(textoError(e));
  }
}
