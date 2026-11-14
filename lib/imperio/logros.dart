import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat.dart' show aceptoReglas, nombreSala;
import '../idioma.dart';
import '../main.dart' show conReintento, db, textoError;
import '../presumir.dart' show preguntarLogroImperio;
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

/// Pregunta si presume el logro [id] del Imperio y, si sí, lo pega en el muro como tarjeta
/// `{'tipo': 'logro_imperio', 'id': id}`. El servidor revisa que el logro esté en tu partida guardada.
/// [guardar] sube la partida antes de publicar: un logro recién ganado todavía no está en la nube.
/// Si el servidor aún no lo ve (había otro guardado en curso), guarda de nuevo y reintenta.
Future<void> presumirLogroImperio(BuildContext context, String id, {Future<void> Function()? guardar}) async {
  final presumir = await preguntarLogroImperio(context, id);
  if (presumir != true || !context.mounted || !await aceptoReglas(context)) return;
  bool sinLogro(Object e) => e is PostgrestException && e.message == _sinLogro;
  Future<void> publicar() => db.from('muro').insert({
        'tarjeta': {'tipo': 'logro_imperio', 'id': id},
      });
  try {
    for (var intento = 0;; intento++) {
      try {
        if (guardar != null) await guardar();
        await publicar();
        break;
      } catch (e) {
        if (guardar == null || intento >= 2 || !sinLogro(e)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    if (context.mounted) _aviso(context, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
  } catch (e) {
    if (!context.mounted) return;
    _aviso(
      context,
      sinLogro(e)
          ? tr('Ese logro todavía no está guardado en la nube. Abre el Imperio un momento y vuelve a intentar.',
              "That achievement isn't saved to the cloud yet. Open the Empire for a moment and try again.")
          : textoError(e),
    );
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));
