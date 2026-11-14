import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'avisos.dart';
import 'chat.dart';
import 'chat_panel.dart' show abrirPanelChats;
import 'chat_sin_leer.dart' show chatSinLeer;
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart';
import 'muro_dibujo.dart';
import 'muro_editor.dart';
import 'perfil.dart';
import 'privados.dart';
import 'tarjeta_pegada.dart' show TarjetaPegada, presumirEnMuro;
import 'tema.dart';

// Muro del baño: publicaciones con texto y dibujo, 💩 como like y comentarios. Sin Realtime ni push:
// se recarga al bajar. Los topes (10 por hora, 30 comentarios por hora, links y datos) están en el servidor.

const _columnasPerfil =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';
const _porPagina = 20;

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: TextoConEmojis(texto)));

String _cuando(String iso) {
  final t = DateTime.parse(iso).toLocal();
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('ahora', 'now');
  if (d.inMinutes < 60) return tr('hace ${d.inMinutes} min', '${d.inMinutes} min ago');
  if (d.inHours < 24) return tr('hace ${d.inHours} h', '${d.inHours} h ago');
  if (d.inDays < 7) return tr('hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}', '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago');
  return enIngles ? '${t.month}/${t.day}/${t.year}' : '${t.day}/${t.month}/${t.year}';
}

Future<bool> _confirmar(BuildContext context, String pregunta, String boton) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(pregunta),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(boton)),
        ],
      ),
    ) ??
    false;

/// Pestaña BAÑO: el muro. Los chats se abren desde el botón de arriba a la derecha.
class PantallaMuro extends StatefulWidget {
  const PantallaMuro({super.key});

  @override
  State<PantallaMuro> createState() => _PantallaMuroState();
}

class _PantallaMuroState extends State<PantallaMuro> {
  final _scroll = ScrollController();
  final _posts = <Map<String, dynamic>>[];
  bool _amigos = false, _cargando = false, _hayMas = true, _soyAdmin = false;
  String? _error;
  // Cada cambio de TODOS/AMIGOS o recarga invalida las respuestas que vienen en camino.
  int _vuelta = 0;

  @override
  void initState() {
    super.initState();
    revisarPrivados();
    db.rpc('es_admin').then((v) {
      if (mounted) setState(() => _soyAdmin = v == true);
    }).catchError((_) {});
    irA.addListener(_irA);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _cargarMas();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _irA());
    _recargar();
  }

  @override
  void dispose() {
    irA.removeListener(_irA);
    _scroll.dispose();
    super.dispose();
  }

  // Un push o aviso de chat: abrir la lista de chats encima; ella abre la sala (y el hilo).
  void _irA() {
    final destino = irA.value;
    // Con la lista ya abierta encima, ella misma lo atiende: no abrir otra.
    if (destino == null || destino.muro || !mounted || _chatsAbiertos) return;
    destino.muro = true;
    final a = destino.a;
    if (const {'soporte', 'amigos', 'todos', 'global', 'es', 'en'}.contains(a) || esSalaDm(a)) _abrirChats();
  }

  bool _chatsAbiertos = false;

  Future<void> _abrirChats() async {
    if (_chatsAbiertos) return;
    _chatsAbiertos = true;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaChat()));
    _chatsAbiertos = false;
  }

  Future<void> _recargar() async {
    _vuelta++;
    setState(() {
      _posts.clear();
      _hayMas = true;
      _error = null;
      _cargando = false;
    });
    await _cargarMas();
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    final vuelta = _vuelta;
    setState(() => _cargando = true);
    try {
      // shortcut: paginar por created_at salta posts con el mismo instante exacto; pasar a (created_at, id) si molesta.
      final antes = _posts.isEmpty ? null : _posts.last['created_at'];
      final filas = await conReintento(() => db.rpc('muro_feed_tarjetas', params: {'p_antes': antes, 'p_amigos': _amigos, 'p_limite': _porPagina}));
      if (!mounted || vuelta != _vuelta) return;
      final nuevas = [for (final f in filas as List) Map<String, dynamic>.from(f as Map)];
      setState(() {
        _posts.addAll(nuevas);
        _hayMas = nuevas.length == _porPagina;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted || vuelta != _vuelta) return;
      setState(() {
        _error = textoError(e);
        _cargando = false;
      });
    }
  }

  Future<void> _publicar() async {
    if (!await aceptoReglas(context) || !mounted) return;
    final hecho = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PantallaPublicar()));
    if (hecho == true && mounted) {
      _aviso(context, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
      _recargar();
    }
  }

  // 🏆: hitos, desbloqueos y la última cagada se pegan aquí como recorte (antes iban al chat).
  Future<void> _presumir() async {
    if (await presumirEnMuro(context) && mounted) _recargar();
  }

  Future<void> _abrirPost(Map<String, dynamic> post) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _PantallaPost(post: post, soyAdmin: _soyAdmin)));
    if (mounted) setState(() {});
  }

  void _quitar(Map<String, dynamic> post) => setState(() => _posts.remove(post));

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(nombreSala.toUpperCase()),
        actions: [
          IconButton(
            key: const Key('muro_chats'),
            tooltip: tr('Chats', 'Chats'),
            // El panel de chats de la derecha; los push siguen abriendo la lista (_abrirChats).
            onPressed: () => abrirPanelChats(context, soyAdmin: _soyAdmin),
            // El punto es el mismo de la pestaña BAÑO: general, soporte y privados (lib/chat_sin_leer.dart).
            icon: ListenableBuilder(
              listenable: chatSinLeer,
              builder: (context, _) => Stack(clipBehavior: Clip.none, children: [
                const Icon(Icons.chat_bubble_outline),
                if (chatSinLeer.hayNuevo) const Positioned(right: -2, top: -2, child: PuntoSinLeer()),
              ]),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: _posts.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return _cabecera();
            if (i <= _posts.length) {
              final post = _posts[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TarjetaPost(
                  key: ValueKey(post['id']),
                  post: post,
                  soyAdmin: _soyAdmin,
                  alAbrir: () => _abrirPost(post),
                  alBorrar: () => _quitar(post),
                ),
              );
            }
            return _pie(p);
          },
        ),
      ),
    );
  }

  Widget _cabecera() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('muro_publicar'),
                onPressed: _publicar,
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('PUBLICAR', 'POST')),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: tr('Presumir', 'Show off'),
              child: OutlinedButton(key: const Key('Presumir'), onPressed: _presumir, child: const Emoji('🏆', tamano: 20)),
            ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(tr('TODOS', 'ALL'))),
              ButtonSegment(value: true, label: Text(tr('AMIGOS', 'FRIENDS'))),
            ],
            selected: {_amigos},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              _amigos = s.first;
              _recargar();
            },
          ),
        ]),
      );

  Widget _pie(Paleta p) {
    if (_cargando) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              setState(() => _error = null);
              _cargarMas();
            },
            child: Text(tr('Reintentar', 'Retry')),
          ),
        ]),
      );
    }
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          const Emoji('🚽', tamano: 48),
          const SizedBox(height: 12),
          Text(
            _amigos
                ? tr('Tus amigos no han publicado nada todavía.', "Your friends haven't posted anything yet.")
                : tr('Nadie ha publicado todavía. Estrena la pared.', 'Nobody has posted yet. Be the first on the wall.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textoSuave),
          ),
        ]),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Un post: autor, texto, dibujo y la barra de 💩 y comentarios. [alAbrir] lleva al detalle.
class _TarjetaPost extends StatefulWidget {
  const _TarjetaPost({super.key, required this.post, required this.soyAdmin, this.alAbrir, required this.alBorrar});

  final Map<String, dynamic> post;
  final bool soyAdmin;
  final VoidCallback? alAbrir;
  final VoidCallback alBorrar;

  @override
  State<_TarjetaPost> createState() => _TarjetaPostState();
}

class _TarjetaPostState extends State<_TarjetaPost> {
  bool _enVuelo = false;

  Map<String, dynamic> get _post => widget.post;
  bool get _mio => _post['user_id'] == db.auth.currentUser?.id;

  // Optimista: cambia ya y vuelve atrás si el servidor dice que no.
  Future<void> _like() async {
    if (_enVuelo) return;
    final antes = _post['yo_like'] == true;
    final likes = (_post['likes'] as num?)?.toInt() ?? 0;
    setState(() {
      _enVuelo = true;
      _post['yo_like'] = !antes;
      _post['likes'] = likes + (antes ? -1 : 1);
    });
    try {
      final tabla = db.from('muro_likes');
      if (antes) {
        await tabla.delete().eq('post_id', _post['id'] as Object).eq('user_id', db.auth.currentUser!.id);
      } else {
        await tabla.insert({'post_id': _post['id']});
      }
    } catch (e) {
      // Ya estaba (otro teléfono): el estado nuevo es el correcto.
      final yaEstaba = !antes && e is PostgrestException && e.code == '23505';
      if (!yaEstaba) {
        _post['yo_like'] = antes;
        _post['likes'] = likes;
        if (mounted) _aviso(context, textoError(e));
      }
    }
    if (mounted) setState(() => _enVuelo = false);
  }

  Future<void> _reportar() async {
    final motivo = await elegirMotivoReporte(context);
    if (motivo == null || !mounted) return;
    try {
      await db.from('muro_reportes').insert({'post_id': _post['id'], 'motivo': motivo});
      if (mounted) _aviso(context, tr('Reportado. Gracias 🙏', 'Reported. Thanks 🙏'));
    } catch (e) {
      if (mounted) _aviso(context, e is PostgrestException && e.code == '23505' ? tr('Ya lo habías reportado', "You've already reported it") : textoError(e));
    }
  }

  Future<void> _borrar() async {
    if (!await _confirmar(context, tr('¿Borrar esta publicación?', 'Delete this post?'), tr('Borrar', 'Delete')) || !mounted) return;
    try {
      await db.from('muro').delete().eq('id', _post['id'] as Object);
      widget.alBorrar();
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final texto = '${_post['texto'] ?? ''}'.trim();
    final dibujo = Dibujo.deJson(_post['dibujo']);
    final tarjeta = _post['tarjeta'] is Map ? (_post['tarjeta'] as Map).cast<String, dynamic>() : null;
    final reto = tarjeta != null && (tarjeta['tipo'] == 'reto' || tarjeta['tipo'] == 'reto_fin');
    final cuando = _cuando('${_post['created_at']}');
    final likes = (_post['likes'] as num?)?.toInt() ?? 0;
    final comentarios = (_post['comentarios'] as num?)?.toInt() ?? 0;
    final perfil = {..._post, 'id': _post['user_id']};
    return Container(
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: InkWell(
        onTap: widget.alAbrir,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
            child: Row(children: [
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: '${_post['user_id']}'))),
                child: Row(children: [
                  Avatar(perfil, tamano: 30, animarMovimiento: false),
                  const SizedBox(width: 8),
                  Text('${_post['username'] ?? '…'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tarjeta == null ? cuando : '${reto ? tr('lanzó un Cagadón', 'threw down a Poop-Off') : tr('pegó un recorte', 'stuck up a clipping')} · $cuando',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textoSuave, fontSize: 12),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Más', 'More'),
                icon: Icon(Icons.more_vert, color: p.textoSuave),
                onSelected: (v) => v == 'borrar' ? _borrar() : _reportar(),
                itemBuilder: (_) => [
                  if (!_mio) PopupMenuItem(value: 'reportar', child: Text(tr('Reportar', 'Report'))),
                  if (_mio || widget.soyAdmin) PopupMenuItem(value: 'borrar', child: Text(tr('Borrar', 'Delete'))),
                ],
              ),
            ]),
          ),
          if (texto.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextoConEmojis(texto, style: TextStyle(color: p.texto, fontSize: 15)),
            ),
          if (dibujo != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: VistaDibujo(dibujo)),
          if (tarjeta != null) _Recorte(tarjeta, giro: ((_post['id'] as num?)?.toInt() ?? 0).isEven ? pi / 180 : -pi / 180),
          Row(children: [
            TextButton.icon(
              key: Key('muro_like_${_post['id']}'),
              onPressed: _like,
              icon: Opacity(opacity: _post['yo_like'] == true ? 1 : 0.35, child: const Emoji('💩', tamano: 20)),
              label: Text('$likes', style: numeros(context, color: _post['yo_like'] == true ? p.texto : p.textoSuave)),
            ),
            TextButton.icon(
              onPressed: widget.alAbrir,
              icon: Icon(Icons.chat_bubble_outline, size: 18, color: p.textoSuave),
              label: Text('$comentarios', style: numeros(context, color: p.textoSuave)),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Tarjeta del servidor (hito, racha, reto, Imperio…) pegada con cinta: torcida 1° (derecha sin movimiento) y dos tiras amarillas.
class _Recorte extends StatelessWidget {
  const _Recorte(this.tarjeta, {required this.giro});

  final Map<String, dynamic> tarjeta;
  final double giro;

  @override
  Widget build(BuildContext context) {
    final cinta = Container(width: 44, height: 14, color: acento.withValues(alpha: .55));
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      // Centrado: las tarjetas que se miden solas quedan como recorte en medio; las anchas llenan.
      child: Center(
        child: Transform.rotate(
          angle: movimiento(context) == Movimiento.nada ? 0 : giro,
          child: Stack(clipBehavior: Clip.none, children: [
            TarjetaPegada(tarjeta, muro: true),
            Positioned(top: -7, left: 10, child: IgnorePointer(child: Transform.rotate(angle: -.25, child: cinta))),
            Positioned(top: -7, right: 10, child: IgnorePointer(child: Transform.rotate(angle: .25, child: cinta))),
          ]),
        ),
      ),
    );
  }
}

/// Un post con sus comentarios (los 200 primeros) y la caja para comentar.
class _PantallaPost extends StatefulWidget {
  const _PantallaPost({required this.post, required this.soyAdmin});

  final Map<String, dynamic> post;
  final bool soyAdmin;

  @override
  State<_PantallaPost> createState() => _PantallaPostState();
}

class _PantallaPostState extends State<_PantallaPost> {
  final _texto = TextEditingController();
  List<Map<String, dynamic>>? _comentarios;
  String? _error;
  bool _enviando = false;

  String? get _yo => db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final filas = await conReintento(() => db
          .from('muro_comentarios')
          .select('id, user_id, texto, created_at, profiles($_columnasPerfil)')
          .eq('post_id', widget.post['id'] as Object)
          .order('created_at')
          .limit(200));
      if (!mounted) return;
      setState(() {
        _comentarios = filas;
        _error = null;
        widget.post['comentarios'] = filas.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
    }
  }

  Future<void> _comentar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty || _enviando) return;
    if (!await aceptoReglas(context) || !mounted) return;
    setState(() => _enviando = true);
    try {
      await db.from('muro_comentarios').insert({'post_id': widget.post['id'], 'texto': texto});
      _texto.clear();
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _borrar(Map<String, dynamic> c) async {
    if (!await _confirmar(context, tr('¿Borrar este comentario?', 'Delete this comment?'), tr('Borrar', 'Delete')) || !mounted) return;
    try {
      await db.from('muro_comentarios').delete().eq('id', c['id'] as Object);
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final dueno = widget.post['user_id'] == _yo;
    return Scaffold(
      appBar: AppBar(title: Text(nombreSala.toUpperCase())),
      body: Column(children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargar,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
              _TarjetaPost(post: widget.post, soyAdmin: widget.soyAdmin, alBorrar: () => Navigator.pop(context)),
              const SizedBox(height: 16),
              Rotulo(tr('Comentarios', 'Comments')),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: TextStyle(color: p.textoSuave))
              else if (_comentarios == null)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (_comentarios!.isEmpty)
                Text(tr('Nadie ha comentado. Sé el primero.', 'No comments yet. Be the first.'), style: TextStyle(color: p.textoSuave))
              else
                for (final c in _comentarios!) _comentario(c, p, puedeBorrar: dueno || widget.soyAdmin || c['user_id'] == _yo),
            ]),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borde))),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('muro_comentario'),
                  controller: _texto,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: tr('Comenta…', 'Comment…'), counterText: ''),
                ),
              ),
              IconButton(tooltip: tr('Enviar', 'Send'), onPressed: _enviando ? null : _comentar, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _comentario(Map<String, dynamic> c, Paleta p, {required bool puedeBorrar}) {
    final perfil = (c['profiles'] as Map?)?.cast<String, dynamic>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: '${c['user_id']}'))),
          child: perfil == null ? const Emoji('💩', tamano: 26) : Avatar(perfil, tamano: 26, animarMovimiento: false),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${perfil?['username'] ?? '…'}', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '  ${_cuando('${c['created_at']}')}', style: TextStyle(color: p.textoSuave, fontSize: 12)),
            ])),
            TextoConEmojis('${c['texto']}', style: TextStyle(color: p.texto)),
          ]),
        ),
        if (puedeBorrar)
          IconButton(
            tooltip: tr('Borrar', 'Delete'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _borrar(c),
            icon: Icon(Icons.delete_outline, size: 18, color: p.textoSuave),
          ),
      ]),
    );
  }
}
