import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat.dart' show aceptoReglas, nombreSala;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show conReintento, db, textoError;
import '../tema.dart';
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

/// Los logros del Imperio: conseguidos arriba con PRESUMIR, por conseguir abajo con candado.
/// Con [control] (el Imperio en marcha) se actualiza solo; sin él, carga la partida guardada.
class PantallaLogrosImperio extends StatefulWidget {
  const PantallaLogrosImperio({super.key, this.control});
  final ControlImperio? control;

  @override
  State<PantallaLogrosImperio> createState() => _PantallaLogrosImperioState();
}

class _PantallaLogrosImperioState extends State<PantallaLogrosImperio> {
  Set<String>? _ids;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.control == null) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final ids = await cargarLogrosImperio();
      if (mounted) setState(() => _ids = ids);
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = widget.control;
    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(title: Text(tr('LOGROS DEL IMPERIO', 'EMPIRE ACHIEVEMENTS'))),
      body: c != null
          ? ListenableBuilder(listenable: c, builder: (context, _) => _lista(context, (id) => c.imperio.tieneLogro(id)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _cargar, child: Text(tr('REINTENTAR', 'RETRY'))),
                    ]),
                  ),
                )
              : _ids == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(onRefresh: _cargar, child: _lista(context, _ids!.contains)),
    );
  }

  Widget _lista(BuildContext context, bool Function(String id) tiene) {
    final hechos = logros.where((l) => tiene(l.id)).toList();
    final faltan = logros.where((l) => !tiene(l.id)).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [Rotulo(tr('Desbloqueados', 'Unlocked')), const Spacer(), Text('${hechos.length}/${logros.length}', style: numeros(context))]),
        const SizedBox(height: 8),
        if (hechos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Todavía ninguno. ¡A pujar!', 'None yet. Start pushing!'), style: TextStyle(color: paleta(context).textoSuave)),
          ),
        for (final l in hechos) _Fila(logro: l, tiene: true),
        if (faltan.isNotEmpty) ...[
          const SizedBox(height: 16),
          Rotulo(tr('Por conseguir', 'To unlock')),
          const SizedBox(height: 8),
          for (final l in faltan) _Fila(logro: l, tiene: false),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.logro, required this.tiene});
  final Logro logro;
  final bool tiene;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Opacity(
      opacity: tiene ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.tarjeta,
          border: Border.all(color: tiene ? p.primario : p.borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Row(children: [
          Emoji(tiene ? '🏆' : '🔒', tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(logro.nombreEs, logro.nombreEn), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: p.texto)),
              const SizedBox(height: 2),
              Text(tr(logro.descEs, logro.descEn), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textoSuave)),
            ]),
          ),
          if (tiene) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => presumirLogroImperio(context, logro.id),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
              ),
              child: Text(tr('PRESUMIR', 'SHOW OFF'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ],
        ]),
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
