import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show conReintento, db, textoError;
import 'perfil.dart' show PantallaPerfil;
import 'popups.dart';
import 'tema.dart';

// Centro de avisos: lo que llega por push queda guardado en public.notificaciones (lo escribe la
// Edge Function), más los anuncios de los admins (public.anuncios, iguales para todos).

/// A dónde mandar a la persona: un toque en un push o en un aviso. Cada pantalla que sabe
/// llegar ahí marca su parte como hecha (la de abajo cambia de pestaña, el baño elige su pestaña).
class Ir {
  Ir(this.a);

  /// 'inicio', 'todos' (o una sala: 'global', 'es', 'en'), 'amigos', 'soporte' o 'avisos'.
  final String a;
  bool inicio = false, bano = false;
}

final irA = ValueNotifier<Ir?>(null);
void ir(String a) => irA.value = Ir(a);

/// Avisos sin leer más anuncios sin ver. Lo pinta la campana y el puntito de la pestaña.
final avisosSinLeer = ValueNotifier<int>(0);

const _anuncioVisto = 'anuncio_visto';

Future<void> contarAvisos() async {
  final yo = db.auth.currentUser?.id;
  if (yo == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final visto = prefs.getInt(_anuncioVisto) ?? 0;
    final (n, a) = await (
      db.from('notificaciones').count(CountOption.exact).eq('user_id', yo).eq('leida', false),
      db.from('anuncios').count(CountOption.exact).gt('id', visto).or('idioma.is.null,idioma.eq.${idioma.value}'),
    ).wait;
    avisosSinLeer.value = n + a;
  } catch (_) {}
}

// El servidor guarda cada aviso en los dos idiomas (titulo_en/cuerpo_en desde la versión con inglés).
Map<String, dynamic> _enSuIdioma(Map<String, dynamic> n) => enIngles && n['titulo_en'] != null
    ? {'titulo': n['titulo_en'], 'cuerpo': n['cuerpo_en'] ?? n['cuerpo']}
    : const {};

var _canales = 0;

/// Escucha avisos y anuncios nuevos en vivo. [onAnuncio] se llama cuando un admin publica uno.
/// Devuelve con qué soltarlo en dispose().
VoidCallback escucharAvisos({VoidCallback? onAnuncio}) {
  final yo = db.auth.currentUser!.id;
  final canal = db
      .channel('avisos-${_canales++}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notificaciones',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: yo),
        callback: (_) => contarAvisos(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'anuncios',
        callback: (_) {
          contarAvisos();
          onAnuncio?.call();
        },
      )
      .subscribe();
  final ciclo = AppLifecycleListener(onResume: contarAvisos);
  contarAvisos();
  return () {
    ciclo.dispose();
    db.removeChannel(canal);
  };
}

/// Al abrir la app (o si llega uno en vivo): el pop-up vigente más nuevo que no hayas visto.
Future<void> mostrarAnuncioNuevo(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final visto = prefs.getInt(_anuncioVisto) ?? 0;
    final a = await db
        .from('anuncios')
        .select()
        .gt('id', visto)
        .or('idioma.is.null,idioma.eq.${idioma.value}')
        .gt('hasta', DateTime.now().toUtc().toIso8601String())
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    if (a == null || !context.mounted) return;
    await prefs.setInt(_anuncioVisto, a['id'] as int);
    contarAvisos();
    if (context.mounted) await verPopup(context, a);
  } catch (_) {}
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

/// El rollo de papel de la pantalla principal: abre la Lectura del Baño (el centro de avisos)
/// con el número de papelitos sin leer.
class BotonAvisos extends StatelessWidget {
  const BotonAvisos({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: avisosSinLeer,
        builder: (context, n, _) => Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: const Color(0xFFE5484D),
          offset: const Offset(-2, 2),
          child: IconButton.outlined(
            tooltip: tr('Lectura del baño', 'Bathroom Reading'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaAvisos())),
            icon: const Emoji('🧻', tamano: 22),
          ),
        ),
      );
}

class PantallaAvisos extends StatefulWidget {
  const PantallaAvisos({super.key});

  @override
  State<PantallaAvisos> createState() => _PantallaAvisosState();
}

class _PantallaAvisosState extends State<PantallaAvisos> {
  List<Map<String, dynamic>>? _avisos;
  bool _soyAdmin = false;

  String get _yo => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _cargar();
    db.rpc('es_admin').then((v) {
      if (mounted) setState(() => _soyAdmin = v == true);
    }).catchError((_) {});
  }

  Future<void> _cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final visto = prefs.getInt(_anuncioVisto) ?? 0;
      final (notis, anuncios) = await conReintento(() => (
            db.from('notificaciones').select().eq('user_id', _yo).order('created_at', ascending: false).limit(100),
            db.from('anuncios').select().or('idioma.is.null,idioma.eq.${idioma.value}').order('created_at', ascending: false).limit(30),
          ).wait);
      final todos = [
        for (final n in notis) {...n, ..._enSuIdioma(n), 'nuevo': n['leida'] != true},
        for (final a in anuncios) {...a, 'tipo': 'anuncio', 'cuerpo': a['texto'], 'anuncio': true, 'nuevo': (a['id'] as int) > visto},
      ]..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
      if (!mounted) return;
      setState(() => _avisos = todos);
      // Abrir el centro = verlos todos. El puntito "nuevo" se queda hasta la próxima vez.
      final maxAnuncio = anuncios.fold<int>(visto, (m, a) => (a['id'] as int) > m ? a['id'] as int : m);
      await prefs.setInt(_anuncioVisto, maxAnuncio);
      if (notis.any((n) => n['leida'] != true)) {
        await db.from('notificaciones').update({'leida': true}).eq('user_id', _yo).eq('leida', false);
      }
      await contarAvisos();
    } catch (e) {
      if (mounted) {
        setState(() => _avisos ??= []);
        _aviso(context, textoError(e));
      }
    }
  }

  Future<void> _borrarTodo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Jalar la cadena? 🚽', 'Flush it? 🚽')),
        content: Text(tr('Tus avisos se van por el tubo y no vuelven. Los anuncios del admin se quedan.', 'Your notices go down the pipes and never come back. Admin announcements stay.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('JALAR', 'FLUSH'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('notificaciones').delete().eq('user_id', _yo);
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
  }

  Future<void> _borrarAnuncio(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Borrar el anuncio?', 'Delete the announcement?')),
        content: Text(tr('Desaparece para todos. Los push que ya llegaron no se pueden quitar.', "It disappears for everyone. Pushes that already went out can't be taken back.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('BORRAR', 'DELETE'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('anuncios').delete().eq('id', a['id']);
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
  }

  void _abrir(Map<String, dynamic> a) {
    final datos = (a['datos'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (a['tipo']) {
      case 'anuncio':
        verPopup(context, a);
      case 'follow' || 'placer' when datos['user_id'] != null:
        Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: datos['user_id'])));
      case 'mencion' || 'reporte_chat':
        Navigator.pop(context);
        ir(datos['sala'] as String? ?? 'todos');
      case 'soporte':
        Navigator.pop(context);
        ir('soporte');
      case 'reto':
        Navigator.pop(context);
        ir('inicio');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final avisos = _avisos;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('📰 LECTURA DEL BAÑO', '📰 BATHROOM READING')),
        actions: [
          if (_soyAdmin)
            IconButton(
              tooltip: tr('Pop-ups', 'Pop-ups'),
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaPopups())).then((_) => _cargar()),
            ),
          if (avisos?.any((a) => a['anuncio'] != true) ?? false)
            TextButton(onPressed: _borrarTodo, child: Text(tr('🚽 JALAR', '🚽 FLUSH'))),
        ],
      ),
      body: avisos == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: avisos.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      const Center(child: Emoji('🧻', tamano: 56)),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(tr('Nada que leer mientras cagas.\nCuando te sigan, te mencionen o te reten, sale aquí.', 'Nothing to read while you poop.\nWhen someone follows you, mentions you or challenges you, it shows up here.'),
                            textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
                      ),
                    ])
                  : ListView.separated(
                      padding: conBordeAbajo(context, EdgeInsets.zero),
                      itemCount: avisos.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: p.borde),
                      itemBuilder: (context, i) => _FilaAviso(
                        aviso: avisos[i],
                        onTap: () => _abrir(avisos[i]),
                        onBorrar: _soyAdmin && avisos[i]['anuncio'] == true ? () => _borrarAnuncio(avisos[i]) : null,
                      ),
                    ),
            ),
    );
  }
}

class _FilaAviso extends StatelessWidget {
  const _FilaAviso({required this.aviso, required this.onTap, this.onBorrar});

  final Map<String, dynamic> aviso;
  final VoidCallback onTap;
  final VoidCallback? onBorrar;

  static const _emojis = {
    'anuncio': '📢',
    'follow': '👀',
    'mencion': '📣',
    'reto': '⚔️',
    'soporte': '🛠️',
    'placer': '🤫',
    'reporte_chat': '🚩',
  };

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final nuevo = aviso['nuevo'] == true;
    final anuncio = aviso['anuncio'] == true;
    final cuerpo = (aviso['cuerpo'] as String?) ?? '';
    return InkWell(
      onTap: onTap,
      onLongPress: onBorrar,
      child: Container(
        color: anuncio ? acento.withValues(alpha: .10) : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Emoji(anuncio ? (aviso['emoji'] as String?) ?? '📢' : _emojis[aviso['tipo']] ?? '💩', tamano: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                // Los títulos del push ya traen su emoji; aquí va en la columna de la izquierda.
                anuncio ? '${aviso['titulo']}' : '${aviso['titulo']}'.replaceFirst(_emojiInicial, ''),
                style: TextStyle(fontWeight: nuevo ? FontWeight.w800 : FontWeight.w600),
              ),
              if (cuerpo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(cuerpo, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textoSuave, fontSize: 13)),
                ),
              const SizedBox(height: 4),
              Text(
                '${anuncio ? tr('DEL ADMIN · ', 'FROM THE ADMIN · ') : ''}${_cuando(aviso['created_at'] as String)}',
                style: numeros(context, tamano: 11, color: p.textoSuave),
              ),
            ]),
          ),
          if (nuevo)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 6),
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}

final _emojiInicial = RegExp(r'^[^\p{L}\p{N}@"¿¡]+\s+', unicode: true);

String _cuando(String iso) {
  final t = DateTime.parse(iso).toLocal();
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('ahora', 'now');
  if (d.inMinutes < 60) return tr('hace ${d.inMinutes} min', '${d.inMinutes} min ago');
  if (d.inHours < 24) return tr('hace ${d.inHours} h', '${d.inHours} h ago');
  if (d.inDays < 7) return tr('hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}', '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago');
  return enIngles ? '${t.month}/${t.day}/${t.year}' : '${t.day}/${t.month}/${t.year}';
}
