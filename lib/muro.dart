import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'avisos.dart';
import 'chat.dart';
import 'chat_panel.dart' show abrirPanelChats;
import 'chat_sin_leer.dart' show chatSinLeer;
import 'cloaca.dart' show NubeCloacas, abrirCloaca;
import 'compartir.dart' show compartirImagen;
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart';
import 'muro_dibujo.dart';
import 'muro_editor.dart';
import 'perfil.dart';
import 'privados.dart';
import 'tarjeta_pegada.dart' show TarjetaPegada, presumirEnMuro;
import 'tema.dart';
import 'vitrina.dart' show tituloPorTotal;

// Muro del baño: publicaciones con texto y dibujo, 💩 como like y comentarios. Sin Realtime ni push:
// se recarga al bajar y cada 60 s (y al volver a la app) se pregunta cuántos hay nuevos (muro_nuevos).
// Los topes (10 por hora, 30 comentarios por hora, links y datos) están en el servidor.

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

class _PantallaMuroState extends State<PantallaMuro> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _posts = <Map<String, dynamic>>[];
  bool _cargando = false, _hayMas = true, _soyAdmin = false, _sinCloaca = false;
  // 0 TODOS, 1 AMIGOS, 2 MI CLOACA.
  int _pestana = 0;
  String? _error;
  // Cada cambio de pestaña o recarga invalida las respuestas que vienen en camino.
  int _vuelta = 0;
  // El dibujo con más 💩 de hoy (solo en TODOS); sale fijo arriba y no se repite en la lista.
  Map<String, dynamic>? _trono;
  Map<String, dynamic>? _yo;
  // El post más nuevo cargado: de ahí se cuentan los nuevos. [_nuevos] es lo que dice la píldora.
  String? _desde;
  int _nuevos = 0;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    revisarPrivados();
    db.rpc('es_admin').then((v) {
      if (mounted) setState(() => _soyAdmin = v == true);
    }).catchError((_) {});
    final yo = db.auth.currentUser?.id;
    if (yo != null) {
      db.from('profiles').select(_columnasPerfil).eq('id', yo).maybeSingle().then((v) {
        if (mounted) setState(() => _yo = v);
      }).catchError((_) {});
    }
    irA.addListener(_irA);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _cargarMas();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _irA());
    _reloj = Timer.periodic(const Duration(seconds: 60), (_) => _contarNuevos());
    _recargar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    irA.removeListener(_irA);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _contarNuevos();
  }

  // Solo con la pestaña BAÑO a la vista (las otras pestañas tienen TickerMode apagado).
  Future<void> _contarNuevos() async {
    final desde = _desde, vuelta = _vuelta;
    if (!mounted || desde == null || !TickerMode.getValuesNotifier(context).value.enabled) return;
    try {
      final n = await db.rpc('muro_nuevos', params: {'p_desde': desde, 'p_amigos': _pestana == 1, 'p_cloaca': _pestana == 2});
      if (mounted && vuelta == _vuelta && n is num && n.toInt() != _nuevos) setState(() => _nuevos = n.toInt());
    } catch (_) {
      // Sin red: se vuelve a probar en el próximo minuto.
    }
  }

  void _verNuevos() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _recargar();
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
    final vuelta = ++_vuelta;
    setState(() {
      _posts.clear();
      _hayMas = true;
      _error = null;
      _cargando = false;
      _trono = null;
      _desde = null;
      _nuevos = 0;
      _sinCloaca = false;
    });
    if (_pestana == 0) {
      db.rpc('muro_trono').then((filas) {
        if (!mounted || vuelta != _vuelta || filas is! List || filas.isEmpty) return;
        final trono = Map<String, dynamic>.from(filas.first as Map);
        setState(() {
          _trono = trono;
          _posts.removeWhere((p) => p['id'] == trono['id']);
        });
      }).catchError((_) {});
    }
    await _cargarMas();
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    final vuelta = _vuelta;
    setState(() => _cargando = true);
    try {
      // shortcut: paginar por created_at salta posts con el mismo instante exacto; pasar a (created_at, id) si molesta.
      final antes = _posts.isEmpty ? null : _posts.last['created_at'];
      final filas = await conReintento(() => db.rpc('muro_feed_tarjetas',
          params: {'p_antes': antes, 'p_amigos': _pestana == 1, 'p_limite': _porPagina, 'p_cloaca': _pestana == 2}));
      if (!mounted || vuelta != _vuelta) return;
      final nuevas = [for (final f in filas as List) Map<String, dynamic>.from(f as Map)];
      // MI CLOACA vacía: ¿no hay posts o no hay Cloaca? Solo se pregunta en ese caso.
      final sinCloaca = _pestana == 2 && antes == null && nuevas.isEmpty
          ? await const NubeCloacas().mia().then((e) => e.cloaca == null, onError: (_) => false)
          : false;
      if (!mounted || vuelta != _vuelta) return;
      setState(() {
        _desde ??= nuevas.isEmpty ? DateTime.now().toUtc().toIso8601String() : '${nuevas.first['created_at']}';
        _posts.addAll(nuevas.where((p) => p['id'] != _trono?['id']));
        _hayMas = nuevas.length == _porPagina;
        _cargando = false;
        _sinCloaca = sinCloaca;
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
        title: Row(children: [
          Text(nombreSala.toUpperCase()),
          const SizedBox(width: 8),
          TextoConEmojis('🧻 ${tr('pared', 'wall')}', style: TextStyle(color: p.textoSuave, fontSize: 12)),
        ]),
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
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _Azulejos(Color.lerp(p.fondo, p.texto, .07)!))),
        RefreshIndicator(
          onRefresh: _recargar,
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 72),
            itemCount: _posts.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) return _cabecera(p);
              if (i <= _posts.length) {
                final post = _posts[i - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
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
        if (_nuevos > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            child: Center(
              child: GestureDetector(
                key: const Key('muro_nuevos'),
                onTap: _verNuevos,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: p.acento, borderRadius: BorderRadius.circular(radio)),
                  child: Text(
                    '↑ $_nuevos ${_nuevos == 1 ? tr('GRAFITI NUEVO', 'NEW GRAFFITI') : tr('GRAFITIS NUEVOS', 'NEW GRAFFITI')}',
                    style: TextStyle(color: p.acentoTexto, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .5),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  void _cambiarPestana(int i) {
    if (i == _pestana) return;
    _pestana = i;
    _recargar();
  }

  Widget _cabecera(Paleta p) {
    final pestanas = [tr('TODOS', 'ALL'), tr('AMIGOS', 'FRIENDS'), tr('MI CLOACA', 'MY SEWER')];
    final trono = _trono;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Pestañas: raya abajo y la elegida con subrayado amarillo.
      Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borde))),
        child: Row(children: [
          for (var i = 0; i < pestanas.length; i++)
            Expanded(
              child: InkWell(
                key: Key('muro_pestana_$i'),
                onTap: () => _cambiarPestana(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: i == _pestana ? BoxDecoration(border: Border(bottom: BorderSide(color: p.acento, width: 3))) : null,
                  child: Text(
                    pestanas[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: i == _pestana ? p.texto : p.textoSuave),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      // Escribir: mi avatar y la caja rayada; 🏆 al lado.
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
        child: Row(children: [
          if (_yo != null) Avatar(_yo!, tamano: 30, animarMovimiento: false) else const Emoji('💩', tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              key: const Key('muro_publicar'),
              onTap: _publicar,
              child: CustomPaint(
                painter: _BordeRayado(p.bordeFuerte),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(tr('Grafitea algo en la pared…', 'Graffiti something on the wall…'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textoSuave, fontSize: 14)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: tr('Presumir', 'Show off'),
            child: OutlinedButton(key: const Key('Presumir'), onPressed: _presumir, child: const Emoji('🏆', tamano: 20)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      if (trono != null && _pestana == 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TarjetaPost(
            key: ValueKey('trono_${trono['id']}'),
            post: trono,
            soyAdmin: _soyAdmin,
            trono: true,
            alAbrir: () => _abrirPost(trono),
            alBorrar: () => setState(() => _trono = null),
          ),
        ),
    ]);
  }

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
    if (_posts.isEmpty && _trono == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          const Emoji('🚽', tamano: 48),
          const SizedBox(height: 12),
          Text(
            switch (_pestana) {
              1 => tr('Tus amigos no han publicado nada todavía.', "Your friends haven't posted anything yet."),
              2 when _sinCloaca => tr('No estás en ninguna Cloaca. Únete a una y aquí verás lo que pegan.',
                  "You're not in any Sewer. Join one and you'll see what they post here."),
              2 => tr('Nadie de tu Cloaca ha publicado todavía.', "Nobody in your Sewer has posted yet."),
              _ => tr('Nadie ha publicado todavía. Estrena la pared.', 'Nobody has posted yet. Be the first on the wall.'),
            },
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textoSuave),
          ),
          if (_pestana == 2 && _sinCloaca) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('muro_ir_cloaca'),
              onPressed: () async {
                await abrirCloaca(context);
                if (mounted) _recargar();
              },
              child: Text(tr('IR A LAS CLOACAS', 'GO TO SEWERS')),
            ),
          ],
        ]),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Solo para pruebas: la tarjeta de un post tal como sale en el muro.
@visibleForTesting
Widget tarjetaPostDePrueba(Map<String, dynamic> post, {bool trono = false}) =>
    _TarjetaPost(post: post, soyAdmin: false, trono: trono, alAbrir: () {}, alBorrar: () {});

/// Un post: autor, texto, dibujo y la barra de 💩 y comentarios. [alAbrir] lleva al detalle.
/// [trono]: el del trono de hoy, con borde amarillo y su encabezado.
class _TarjetaPost extends StatefulWidget {
  const _TarjetaPost(
      {super.key, required this.post, required this.soyAdmin, this.alAbrir, required this.alBorrar, this.trono = false});

  final Map<String, dynamic> post;
  final bool soyAdmin;
  final VoidCallback? alAbrir;
  final VoidCallback alBorrar;
  final bool trono;

  @override
  State<_TarjetaPost> createState() => _TarjetaPostState();
}

class _TarjetaPostState extends State<_TarjetaPost> {
  bool _enVuelo = false, _compartiendo = false;
  final _foto = GlobalKey();

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

  // ↗: la tarjeta tal como se ve, como imagen.
  Future<void> _compartir() async {
    if (_compartiendo) return;
    setState(() => _compartiendo = true);
    final ok = await compartirImagen(context, _foto,
        nombre: 'muro_${_post['id']}.png',
        texto: tr('Mira lo que pegaron en la pared de Rey Cagón 🚽 https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon',
            'Look what got posted on the Poop King wall 🚽 https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon'));
    if (!mounted) return;
    if (!ok) _aviso(context, tr('No se pudo compartir', 'Could not share'));
    setState(() => _compartiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final texto = '${_post['texto'] ?? ''}'.trim();
    final dibujo = Dibujo.deJson(_post['dibujo']);
    final tarjeta = _post['tarjeta'] is Map ? (_post['tarjeta'] as Map).cast<String, dynamic>() : null;
    final reto = tarjeta != null && (tarjeta['tipo'] == 'reto' || tarjeta['tipo'] == 'reto_fin');
    final likes = (_post['likes'] as num?)?.toInt() ?? 0;
    final comentarios = (_post['comentarios'] as num?)?.toInt() ?? 0;
    final racha = (_post['racha'] as num?)?.toInt() ?? 0;
    final cloaca = '${_post['cloaca_nombre'] ?? ''}'.trim();
    final topTexto = '${_post['top_texto'] ?? ''}'.trim();
    final yoLike = _post['yo_like'] == true;
    final perfil = {..._post, 'id': _post['user_id']};
    final suave = TextStyle(color: p.textoSuave, fontSize: 11.5);
    return RepaintBoundary(
      key: _foto,
      child: Container(
        decoration: BoxDecoration(
          color: p.tarjeta,
          border: Border.all(color: widget.trono ? p.acento : p.borde, width: widget.trono ? 2 : 1),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: InkWell(
          onTap: widget.alAbrir,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.trono)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(children: [
                  Expanded(
                    child: TextoConEmojis('👑 ${tr('TRONO DE HOY', "TODAY'S THRONE")}',
                        style: TextStyle(
                            color: oscuro ? p.acento : p.texto, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ),
                  TextoConEmojis('$likes 💩', style: numeros(context, tamano: 11, weight: FontWeight.w800, color: p.textoSuave)),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: '${_post['user_id']}'))),
                  child: Avatar(perfil, tamano: 30, animarMovimiento: false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_post['username'] ?? '…'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    // Título, racha, Cloaca y, si es recorte, qué hizo.
                    Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(tituloPorTotal((_post['cagadas'] as num?)?.toInt() ?? 0, genero: _post['genero'] as String?), style: suave),
                      if (racha > 0)
                        TextoConEmojis('🔥 $racha',
                            style: TextStyle(
                                color: oscuro ? const Color(0xFFFFB27A) : const Color(0xFFC2410C),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                      if (cloaca.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(border: Border.all(color: p.bordeFuerte)),
                          child: Text(cloaca.toUpperCase(),
                              style: TextStyle(color: p.textoSuave, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .5)),
                        ),
                      if (tarjeta != null)
                        Text(reto ? tr('lanzó un Cagadón', 'threw down a Poop-Off') : tr('pegó un recorte', 'stuck up a clipping'),
                            style: suave),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(_cuando('${_post['created_at']}'), style: numeros(context, tamano: 11, color: p.textoSuave)),
              ]),
            ),
            if (texto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextoConEmojis(texto, style: TextStyle(color: p.texto, fontSize: 15)),
              ),
            if (dibujo != null) Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: VistaDibujo(dibujo)),
            if (tarjeta != null)
              _Recorte(tarjeta,
                  giro: ((_post['id'] as num?)?.toInt() ?? 0).isEven ? pi / 180 : -pi / 180,
                  muroId: (_post['id'] as num?)?.toInt(),
                  autor: _post['user_id'] as String?),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                InkWell(
                  key: Key('muro_like_${_post['id']}'),
                  onTap: _like,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: yoLike ? BoxDecoration(color: p.acento, borderRadius: BorderRadius.circular(radio)) : null,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Opacity(opacity: yoLike ? 1 : 0.35, child: const Emoji('💩', tamano: 18)),
                      const SizedBox(width: 6),
                      Text('$likes',
                          style: numeros(context, weight: FontWeight.w800, color: yoLike ? p.acentoTexto : p.textoSuave)),
                    ]),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.alAbrir,
                  icon: Icon(Icons.chat_bubble_outline, size: 18, color: p.textoSuave),
                  label: Text('$comentarios', style: numeros(context, color: p.textoSuave)),
                ),
                IconButton(
                  key: Key('muro_compartir_${_post['id']}'),
                  tooltip: tr('Compartir', 'Share'),
                  onPressed: _compartiendo ? null : _compartir,
                  icon: Icon(Icons.north_east, size: 18, color: p.textoSuave),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('Más', 'More'),
                  icon: Icon(Icons.more_horiz, color: p.textoSuave),
                  onSelected: (v) => v == 'borrar' ? _borrar() : _reportar(),
                  itemBuilder: (_) => [
                    if (!_mio) PopupMenuItem(value: 'reportar', child: Text(tr('Reportar', 'Report'))),
                    if (_mio || widget.soyAdmin) PopupMenuItem(value: 'borrar', child: Text(tr('Borrar', 'Delete'))),
                  ],
                ),
              ]),
            ),
            // El último comentario, solo en el muro (en el detalle ya están todos).
            if (widget.alAbrir != null && topTexto.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borde))),
                child: Text.rich(
                  TextSpan(style: TextStyle(color: p.texto, fontSize: 12.5), children: [
                    TextSpan(text: '${_post['top_nombre'] ?? '…'} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ...spansConEmojis(topTexto, tamano: 15),
                    if (comentarios > 1)
                      TextSpan(text: tr(' · ver los $comentarios', ' · see all $comentarios'), style: TextStyle(color: p.textoSuave)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Fondo del baño: azulejos, una raya cada 36 px.
class _Azulejos extends CustomPainter {
  const _Azulejos(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 36.0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pincel);
    }
    for (var y = 36.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pincel);
    }
  }

  @override
  bool shouldRepaint(_Azulejos viejo) => viejo.color != color;
}

/// Borde de 1 px a rayas de la caja para escribir.
class _BordeRayado extends CustomPainter {
  const _BordeRayado(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1;
    const raya = 5.0, hueco = 4.0;
    void linea(Offset a, Offset b) {
      final largo = (b - a).distance;
      final paso = (b - a) / largo;
      for (var d = 0.0; d < largo; d += raya + hueco) {
        canvas.drawLine(a + paso * d, a + paso * (d + raya).clamp(0, largo), pincel);
      }
    }

    final w = size.width - .5, h = size.height - .5;
    linea(const Offset(.5, .5), Offset(w, .5));
    linea(Offset(w, .5), Offset(w, h));
    linea(Offset(w, h), Offset(.5, h));
    linea(Offset(.5, h), const Offset(.5, .5));
  }

  @override
  bool shouldRepaint(_BordeRayado viejo) => viejo.color != color;
}

/// Tarjeta del servidor (hito, racha, reto, Imperio…) pegada con cinta: torcida 1° (derecha sin movimiento) y dos tiras amarillas.
class _Recorte extends StatelessWidget {
  const _Recorte(this.tarjeta, {required this.giro, this.muroId, this.autor});

  final Map<String, dynamic> tarjeta;
  final double giro;
  final int? muroId;
  final String? autor;

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
            TarjetaPegada(tarjeta, muro: true, muroId: muroId, autor: autor),
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
