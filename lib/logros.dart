import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'animaciones.dart';
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'main.dart' show db;
import 'racha.dart';
import 'tema.dart';

/// Un logro secreto. Solo se ve cuando ya es tuyo. [ladoSecreto]: solo lo ven quienes también
/// tienen el lado secreto (o el dueño).
typedef LogroSecreto = ({String clave, String emoji, String nombre, String detalle, bool ladoSecreto});

/// Todos los logros secretos. Los de eventos de pantalla (psst, corona) se guardan en la tabla
/// `logros`; los demás salen de las cagadas y de `placer_desbloqueado`.
List<LogroSecreto> get logrosSecretos => <LogroSecreto>[
      (
        clave: 'placer_lado',
        emoji: '🍑',
        nombre: tr('Del otro lado', 'The other side'),
        detalle: tr('Encontraste el lado secreto', 'You found the secret side'),
        ladoSecreto: true,
      ),
      (
        clave: 'psst_meon',
        emoji: '🍺',
        nombre: tr('Sabes demasiado', 'You know too much'),
        detalle: tr(segun('Viste a REY MEÓN', 'Viste a REINA MEONA'), segun('You saw KING OF THE PEE', 'You saw QUEEN OF THE PEE')),
        ladoSecreto: false,
      ),
      (
        clave: 'psst_pulcro',
        emoji: '🚿',
        nombre: tr(segun('Chismoso', 'Chismosa'), 'Snoop'),
        detalle: tr(segun('Viste a REY PULCRO', 'Viste a REINA PULCRA'), segun('You saw KING OF CLEAN', 'You saw QUEEN OF CLEAN')),
        ladoSecreto: false,
      ),
      (
        clave: 'psst_todas',
        emoji: '👽',
        nombre: tr(segun('Viene del futuro', 'Viene del futuro'), 'From the future'),
        detalle: tr('Viste todas las que vienen', 'You saw every app coming'),
        ladoSecreto: false,
      ),
      (
        clave: 'hexa',
        emoji: estiloRacha(6).$2,
        nombre: (nombreRacha(6) ?? 'HEXA POOP!').replaceAll('!', ''),
        detalle: tr('6 en un día', '6 in one day'),
        ladoSecreto: false,
      ),
      (
        clave: 'corona',
        emoji: '🫅',
        nombre: tr('Suelta la corona', 'Hands off the crown'),
        detalle: tr('La tocaste 10 veces seguidas', 'You poked it 10 times in a row'),
        ladoSecreto: false,
      ),
      (
        clave: 'hora_1111',
        emoji: '✨',
        nombre: tr('Pide un deseo', 'Make a wish'),
        detalle: tr('Cagaste a las 11:11', 'You pooped at 11:11'),
        ladoSecreto: false,
      ),
      (
        clave: 'hora_333',
        emoji: '👻',
        nombre: tr('Hora del espanto', 'Witching hour'),
        detalle: tr('Cagaste a las 3:33 am', 'You pooped at 3:33 am'),
        ladoSecreto: false,
      ),
      (
        clave: 'ano_nuevo',
        emoji: '🎆',
        nombre: tr('Año nuevo, mojón nuevo', 'New year, new poop'),
        detalle: tr('Cagaste un 1 de enero', 'You pooped on January 1st'),
        ladoSecreto: false,
      ),
      (
        clave: 'viernes_13',
        emoji: '🐈‍⬛',
        nombre: tr('Mala suerte', 'Bad luck'),
        detalle: tr('Cagaste un viernes 13', 'You pooped on Friday the 13th'),
        ladoSecreto: false,
      ),
    ];

// SharedPreferences: los ganados en este teléfono (por si la tabla no existe o no hay red),
// los que faltan por subir, los que ya avisaron con el toast y los que ya se revelaron en la vitrina.
const _locales = 'logros_locales', _pendientes = 'logros_pendientes', _avisados = 'logros_avisados', _revelados = 'logros_revelados';

Future<SharedPreferences?> _prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}

Set<String> _leer(SharedPreferences? p, String clave) => {...?p?.getStringList(clave)};

Future<void> _sumar(SharedPreferences? p, String clave, Iterable<String> valores) async {
  if (p == null) return;
  try {
    await p.setStringList(clave, {..._leer(p, clave), ...valores}.toList());
  } catch (_) {}
}

/// Sube los logros que quedaron pendientes. Si la tabla aún no existe o no hay red, se quedan
/// guardados en el teléfono y se reintenta la próxima vez.
Future<void> sincronizarLogros() async {
  final yo = db.auth.currentUser?.id;
  final p = await _prefs();
  final pendientes = _leer(p, _pendientes);
  if (yo == null || p == null || pendientes.isEmpty) return;
  try {
    await db.from('logros').upsert(
          [for (final c in pendientes) {'user_id': yo, 'clave': c}],
          onConflict: 'user_id,clave',
          ignoreDuplicates: true,
        );
    await p.setStringList(_pendientes, []);
  } catch (_) {}
}

/// Las claves guardadas de [uid]: las del servidor y, si es el propio, también las del teléfono.
Future<Set<String>> logrosDe(String uid) async {
  final esMio = uid == db.auth.currentUser?.id;
  final claves = <String>{};
  if (esMio) {
    claves.addAll(_leer(await _prefs(), _locales));
    await sincronizarLogros();
  }
  try {
    final filas = await db.from('logros').select('clave').eq('user_id', uid);
    claves.addAll([for (final f in filas) f['clave'] as String]);
  } catch (_) {}
  return claves;
}

/// Un logro de evento de pantalla (psst, corona). Se guarda en el teléfono, se sube cuando se
/// pueda y, si es nuevo, sale el toast.
Future<void> ganarLogro(BuildContext context, String clave) async {
  final p = await _prefs();
  final tenia = _leer(p, _locales);
  if (tenia.contains(clave)) return;
  final nuevos = [clave];
  // Las dos apps que vienen: se gana también "todas las que vienen".
  if ({...tenia, clave}.containsAll(const ['psst_meon', 'psst_pulcro']) && !tenia.contains('psst_todas')) nuevos.add('psst_todas');
  await _sumar(p, _locales, nuevos);
  await _sumar(p, _pendientes, nuevos);
  await _sumar(p, _avisados, nuevos);
  if (context.mounted) avisarLogrosSecretos(context, nuevos);
  await sincronizarLogros();
}

/// Lo que todavía no avisó con el toast, de entre [ganados]. Los deja marcados como avisados.
Future<List<String>> porAvisar(Iterable<String> ganados) async {
  final p = await _prefs();
  final nuevos = ganados.where((c) => !_leer(p, _avisados).contains(c)).toList();
  await _sumar(p, _avisados, nuevos);
  return nuevos;
}

/// Lo que todavía no se reveló con la animación en la vitrina, de entre [ganados].
Future<Set<String>> porRevelar(Iterable<String> ganados) async {
  final ya = _leer(await _prefs(), _revelados);
  return {for (final c in ganados) if (!ya.contains(c)) c};
}

Future<void> marcarRevelado(String clave) async => _sumar(await _prefs(), _revelados, [clave]);

/// El toast "🤫 Logro secreto: …". Si son varios, uno detrás de otro (los encola el ScaffoldMessenger).
void avisarLogrosSecretos(BuildContext context, Iterable<String> claves) {
  final catalogo = {for (final l in logrosSecretos) l.clave: l};
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  for (final c in claves) {
    final l = catalogo[c];
    if (l == null) continue;
    HapticFeedback.mediumImpact();
    m.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: acento,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radio)), side: BorderSide(color: acentoTexto, width: 2)),
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          const Emoji('🤫', tamano: 28),
          const SizedBox(width: 10),
          Emoji(l.emoji, tamano: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Logro secreto: ${l.nombre}', 'Secret achievement: ${l.nombre}'),
              style: const TextStyle(color: acentoTexto, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    ));
  }
}

/// Easter egg de YO: tocar el avatar (la corona) 10 veces seguidas. Se sacude, da una vuelta
/// y protesta. La primera vez gana el logro secreto "Suelta la corona".
class CoronaTocable extends StatefulWidget {
  const CoronaTocable({super.key, required this.child, this.alGanar});

  final Widget child;

  /// Después de ganar el logro (para que la vitrina lo muestre).
  final VoidCallback? alGanar;

  @override
  State<CoronaTocable> createState() => _CoronaTocableState();
}

class _CoronaTocableState extends State<CoronaTocable> with SingleTickerProviderStateMixin {
  late final _giro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  var _toques = 0;
  DateTime _ultimo = DateTime(2000);

  static List<String> get _quejas => [
        tr('¡Suelta la corona! Eso no se toca.', 'Hands off the crown! Not yours to touch.'),
        tr(segun('El rey está ocupado. En el trono.', 'La reina está ocupada. En el trono.'), segun('The king is busy. On the throne.', 'The queen is busy. On the throne.')),
        tr('¿Te lavaste las manos antes de tocar eso?', 'Did you wash your hands before touching that?'),
      ];

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  void _tocar() {
    final ahora = DateTime.now();
    // "Seguidas": menos de un segundo entre toque y toque.
    _toques = ahora.difference(_ultimo) < const Duration(seconds: 1) ? _toques + 1 : 1;
    _ultimo = ahora;
    if (_toques < 10) {
      if (_toques >= 6) HapticFeedback.selectionClick();
      return;
    }
    _toques = 0;
    HapticFeedback.heavyImpact();
    if (movimiento(context) != Movimiento.nada) _giro.forward(from: 0);
    final quejas = _quejas;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Row(children: [
        const Emoji('👑', tamano: 24),
        const SizedBox(width: 10),
        Expanded(child: Text(quejas[math.Random().nextInt(quejas.length)])),
      ])));
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      ganarLogro(context, 'corona').then((_) => widget.alGanar?.call());
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _tocar,
        child: AnimatedBuilder(
          animation: _giro,
          child: widget.child,
          builder: (context, child) {
            final t = _giro.value;
            if (t == 0 || t == 1) return child!;
            // Simple: solo se sacude. Completo: se sacude y da una vuelta entera.
            final sacudida = math.sin(t * math.pi * 8) * (1 - t) * .25;
            final vuelta = movimiento(context) == Movimiento.completo ? Curves.easeInOutBack.transform(t) * 2 * math.pi : 0.0;
            return Transform.rotate(angle: sacudida + vuelta, child: child);
          },
        ),
      );
}
