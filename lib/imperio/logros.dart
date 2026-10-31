import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat.dart' show aceptoReglas, nombreSala;
import '../idioma.dart';
import '../main.dart' show conReintento, db, textoError;
import '../vitrina.dart' show PantallaVitrina;
import 'catalogo.dart';
import 'control.dart';
import 'nube.dart';

/// Mensaje del trigger validar_mensaje (supabase/migrations/…_imperio_logros_chat.sql).
const _sinLogro = 'Todavía no tienes ese logro del Imperio';

/// Ids de los logros del Imperio de quien entró, sin arrancar el juego.
///
/// No usa `imperio_cargar`: esa RPC consume las cagadas nuevas en el servidor y solo el Imperio en marcha
/// las aplica. Lee la fila propia de `imperio` (RLS deja leer solo la tuya) y le suma la copia local,
/// que puede ir por delante si el último guardado no llegó.
Future<Set<String>> cargarLogrosImperio() async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) return {};
  final ids = <String>{};
  final local = await NubeImperio().cargarLocal(uid);
  final estadoLocal = local?['estado'];
  if (estadoLocal is Map) ids.addAll(_ids(estadoLocal['logros']));
  try {
    final fila = await conReintento(() => db.from('imperio').select('estado').eq('user_id', uid).maybeSingle());
    final estado = fila?['estado'];
    if (estado is Map) ids.addAll(_ids(estado['logros']));
  } catch (_) {
    if (estadoLocal is! Map) rethrow;
  }
  return ids;
}

Set<String> _ids(Object? v) => v is List ? {for (final x in v) '$x'} : <String>{};

/// Los logros del Imperio: abre la vitrina en la sección IMPERIO (con PRESUMIR en los ganados).
/// Con [control] (el Imperio en marcha) se actualiza solo; sin él, carga la partida guardada.
class PantallaLogrosImperio extends StatelessWidget {
  const PantallaLogrosImperio({super.key, this.control});
  final ControlImperio? control;

  @override
  Widget build(BuildContext context) {
    final c = control;
    if (c == null) return const PantallaVitrina(trofeos: [], conImperio: true, irAImperio: true);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => PantallaVitrina(
        trofeos: const [],
        conImperio: true,
        irAImperio: true,
        imperio: {for (final l in logros) if (c.imperio.tieneLogro(l.id)) l.id},
      ),
    );
  }
}

/// Pregunta si presume el logro [id] del Imperio y, si sí, lo manda a la sala general como tarjeta
/// `{'tipo': 'logro_imperio', 'id': id}`. El servidor revisa que el logro esté en tu partida guardada.
Future<void> presumirLogroImperio(BuildContext context, String id) async {
  final l = logros.where((x) => x.id == id).firstOrNull;
  final nombre = l == null ? '' : tr(l.nombreEs, l.nombreEn);
  final presumir = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(nombre.isEmpty ? tr('¡Logro del Imperio! 🏆', 'Empire achievement! 🏆') : tr('¡Logro: $nombre! 🏆', 'Achievement: $nombre! 🏆')),
      content: Text(tr('¿Lo presumes en $nombreSala?', 'Show it off in $nombreSala?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('PRESUMIR', 'SHOW OFF'))),
      ],
    ),
  );
  if (presumir != true || !context.mounted || !await aceptoReglas(context)) return;
  try {
    await db.from('mensajes').insert({
      'sala': 'global',
      'tarjeta': {'tipo': 'logro_imperio', 'id': id},
    });
    if (context.mounted) _aviso(context, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
  } catch (e) {
    if (!context.mounted) return;
    final sinLogro = e is PostgrestException && e.message == _sinLogro;
    _aviso(
      context,
      sinLogro
          ? tr('Ese logro todavía no está guardado en la nube. Abre el Imperio un momento y vuelve a intentar.',
              "That achievement isn't saved to the cloud yet. Open the Empire for a moment and try again.")
          : textoError(e),
    );
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));
