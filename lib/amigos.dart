import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accesorios.dart';
import 'cagadon.dart' show retar;
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show conReintento, db, escucharCagadas, textoError;
import 'perfil.dart' show PantallaPerfil;
import 'tema.dart';
import 'vivo.dart';

// Pestaña AMIGOS del baño: buscar gente, a quién sigues, quién te sigue y tus favoritos arriba.

const _columnas =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

enum _Lista { sigues, teSiguen }

enum _Orden { nombre, cagadas }

/// Lo que abre el botón de agregar amigos: el buscador listo para escribir y, sin texto,
/// gente nueva para seguir en vez de los que ya sigues.
class PantallaBuscarAmigos extends StatelessWidget {
  const PantallaBuscarAmigos({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('BUSCAR AMIGOS', 'FIND FRIENDS'))),
        body: const PantallaAmigos(buscar: true),
      );
}

class PantallaAmigos extends StatefulWidget {
  const PantallaAmigos({super.key, this.buscar = false});

  /// Abre con el teclado puesto en el buscador y muestra sugeridos en vez de tus listas.
  final bool buscar;

  @override
  State<PantallaAmigos> createState() => _PantallaAmigosState();
}

class _PantallaAmigosState extends State<PantallaAmigos> with AutomaticKeepAliveClientMixin {
  final _buscador = TextEditingController();
  Timer? _espera;
  String _q = '';
  _Lista _lista = _Lista.sigues;
  _Orden _orden = _Orden.nombre;

  Map<String, Map<String, dynamic>> _perfiles = {};
  Set<String> _sigo = {}, _meSiguen = {}, _bloqueados = {};
  // Favoritos: solo en este teléfono, para tener arriba a los de siempre.
  Set<String> _favoritos = {};
  List<Map<String, dynamic>>? _resultados;
  // Sin texto en BUSCAR AMIGOS: los que te siguen sin seguirlos de vuelta y luego los más activos.
  List<Map<String, dynamic>> _sugeridos = [];
  bool _cargando = true;
  late final VoidCallback _soltar;

  String get _yo => db.auth.currentUser!.id;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _favoritos = (prefs.getStringList('amigos_favoritos') ?? []).toSet());
    });
    _cargar();
    _soltar = escucharCagadas('amigos', _cargar);
  }

  @override
  void dispose() {
    _soltar();
    _espera?.cancel();
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final (sigo, meSiguen, bloqueos) = await conReintento(() => (
            db.from('follows').select('followed').eq('follower', _yo),
            db.from('follows').select('follower').eq('followed', _yo),
            db.from('bloqueos').select('bloqueado'),
          ).wait);
      final s = {for (final f in sigo) f['followed'] as String};
      final m = {for (final f in meSiguen) f['follower'] as String};
      final ids = {...s, ...m}.toList();
      final perfiles = ids.isEmpty ? <Map<String, dynamic>>[] : await db.from('profiles').select(_columnas).inFilter('id', ids);
      final activos = widget.buscar
          ? await db.from('profiles').select(_columnas).neq('id', _yo).gt('cagadas', 0).order('cagadas', ascending: false).limit(60)
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final bloqueados = {for (final b in bloqueos) b['bloqueado'] as String};
      final porId = {for (final p in perfiles) p['id'] as String: p};
      setState(() {
        _sugeridos = [
          for (final id in m.difference(s).difference(bloqueados))
            if (porId[id] != null) porId[id]!,
          for (final g in activos)
            if (!s.contains(g['id']) && !m.contains(g['id']) && !bloqueados.contains(g['id'])) g,
        ];
        _sigo = s;
        _meSiguen = m;
        _bloqueados = bloqueados;
        _perfiles = porId;
        _cargando = false;
      });
      if (_q.isNotEmpty) await _buscar(_q);
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        _aviso(textoError(e));
      }
    }
  }

  void _escribiendo(String q) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), () => _buscar(q.trim()));
  }

  Future<void> _buscar(String q) async {
    _q = q;
    if (q.isEmpty) {
      setState(() => _resultados = null);
      return;
    }
    try {
      // % y _ son comodines en ilike: se escapan para buscar el texto tal cual.
      final limpio = q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      final r = await db.from('profiles').select(_columnas).neq('id', _yo).ilike('username', '%$limpio%').order('username').limit(50);
      if (!mounted || q != _q) return;
      setState(() => _resultados = List<Map<String, dynamic>>.from(r).where((g) => !_bloqueados.contains(g['id'])).toList());
    } catch (e) {
      if (mounted) _aviso(textoError(e));
    }
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _seguir(String id) async {
    try {
      if (_sigo.contains(id)) {
        await db.from('follows').delete().eq('follower', _yo).eq('followed', id);
      } else {
        await db.from('follows').insert({'followed': id});
      }
      await _cargar();
    } catch (e) {
      _aviso(textoError(e));
    }
  }

  Future<void> _favorito(String id) async {
    setState(() => _favoritos.contains(id) ? _favoritos.remove(id) : _favoritos.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('amigos_favoritos', _favoritos.toList());
  }

  Future<void> _bloquear(Map<String, dynamic> g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Bloquear a ${g['username']}?', 'Block ${g['username']}?')),
        content: Text(tr('Deja de verte y tú dejas de verlo: rankings, chat y follows en los dos sentidos.', "They stop seeing you and you stop seeing them: leaderboards, chat and follows, both ways.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('BLOQUEAR', 'BLOCK'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('bloqueos').insert({'bloqueado': g['id']});
      _aviso(tr('Bloqueado', 'Blocked'));
      await _cargar();
    } catch (e) {
      _aviso(textoError(e));
    }
  }

  List<Map<String, dynamic>> get _visibles {
    final ids = _lista == _Lista.sigues ? _sigo : _meSiguen;
    final gente = [
      for (final id in ids)
        if (_perfiles[id] != null && !_bloqueados.contains(id)) _perfiles[id]!,
    ];
    int porOrden(Map<String, dynamic> a, Map<String, dynamic> b) => _orden == _Orden.cagadas
        ? ((b['cagadas'] as num?) ?? 0).compareTo((a['cagadas'] as num?) ?? 0)
        : (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase());
    return gente
      ..sort((a, b) {
        final fa = _favoritos.contains(a['id']), fb = _favoritos.contains(b['id']);
        if (fa != fb) return fa ? -1 : 1;
        return porOrden(a, b);
      });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = paleta(context);
    final resultados = _resultados;
    final buscando = resultados != null;
    final sugerir = widget.buscar && !buscando;
    final gente = buscando ? resultados : sugerir ? _sugeridos : _visibles;
    final sinSeguirDeVuelta = _meSiguen.difference(_sigo).difference(_bloqueados).length;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 12, 16, 16)),
        children: [
          TextField(
            controller: _buscador,
            autofocus: widget.buscar,
            onChanged: _escribiendo,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Buscar gente por username', 'Search people by username'),
              isDense: true,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _buscador.clear();
                        _buscar('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (sugerir) ...[
            Rotulo(tr('Gente para seguir', 'People to follow')),
            const SizedBox(height: 4),
          ] else if (!buscando) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text('${tr('SIGUES', 'FOLLOWING')} · ${_sigo.difference(_bloqueados).length}'),
                selected: _lista == _Lista.sigues,
                onSelected: (_) => setState(() => _lista = _Lista.sigues),
              ),
              ChoiceChip(
                label: Text('${tr('TE SIGUEN', 'FOLLOWERS')} · ${_meSiguen.difference(_bloqueados).length}'),
                selected: _lista == _Lista.teSiguen,
                onSelected: (_) => setState(() => _lista = _Lista.teSiguen),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  _lista == _Lista.teSiguen && sinSeguirDeVuelta > 0
                      ? tr('$sinSeguirDeVuelta sin seguir de vuelta', '$sinSeguirDeVuelta not followed back')
                      : tr('★ = favorito, sale arriba', '★ = favorite, shows up on top'),
                  style: TextStyle(color: p.textoSuave, fontSize: 12),
                ),
              ),
              PopupMenuButton<_Orden>(
                initialValue: _orden,
                onSelected: (o) => setState(() => _orden = o),
                itemBuilder: (_) => [
                  PopupMenuItem(value: _Orden.nombre, child: Text(tr('Por nombre', 'By name'))),
                  PopupMenuItem(value: _Orden.cagadas, child: Text(tr('Por cagadas', 'By poops'))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sort, size: 18, color: p.textoSuave),
                    const SizedBox(width: 4),
                    Text(_orden == _Orden.nombre ? 'A-Z' : tr('MÁS CAGADAS', 'MOST POOPS'), style: numeros(context, tamano: 12, color: p.textoSuave)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 4),
          ],
          if (_cargando && !buscando)
            const Padding(padding: EdgeInsets.all(32), child: Cargando())
          else if (gente.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(children: [
                Respira(child: Emoji(buscando ? '🫥' : '🚽', tamano: 48)),
                const SizedBox(height: 8),
                Text(
                  buscando
                      ? tr('Nadie con ese nombre', 'Nobody with that name')
                      : sugerir
                          ? tr('Ya sigues a todos. Busca por username arriba.', 'You already follow everyone. Search by username above.')
                          : _lista == _Lista.sigues
                          ? tr('No sigues a nadie. Búscalos arriba para competir.', "You're not following anyone. Search for them above to compete.")
                          : tr('Nadie te sigue todavía. Pásales tu username.', 'Nobody follows you yet. Send them your username.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textoSuave),
                ),
              ]),
            )
          else
            for (final (i, g) in gente.indexed)
              Aparece(
                key: ValueKey(g['id']),
                orden: i,
                child: _FilaAmigo(
                key: ValueKey(g['id']),
                perfil: g,
                loSigo: _sigo.contains(g['id']),
                meSigue: _meSiguen.contains(g['id']),
                favorito: _favoritos.contains(g['id']),
                onFavorito: _sigo.contains(g['id']) ? () => _favorito(g['id']) : null,
                onSeguir: () => _seguir(g['id']),
                onRetar: () => retar(context, g['id'], g['username']),
                onBloquear: () => _bloquear(g),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: g['id'])),
                ).then((_) => _cargar()),
              ),
              ),
        ],
      ),
    );
  }
}

class _FilaAmigo extends StatelessWidget {
  const _FilaAmigo({
    super.key,
    required this.perfil,
    required this.loSigo,
    required this.meSigue,
    required this.favorito,
    required this.onSeguir,
    required this.onRetar,
    required this.onBloquear,
    required this.onTap,
    this.onFavorito,
  });

  final Map<String, dynamic> perfil;
  final bool loSigo, meSigue, favorito;
  final VoidCallback onSeguir, onRetar, onBloquear, onTap;
  final VoidCallback? onFavorito;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final n = (perfil['cagadas'] as num?)?.toInt() ?? 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 36,
            child: onFavorito == null
                ? null
                : IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: favorito ? tr('Quitar de favoritos', 'Remove from favorites') : tr('Favorito', 'Favorite'),
                    onPressed: onFavorito,
                    icon: Icon(favorito ? Icons.star : Icons.star_border, color: favorito ? acento : p.textoSuave),
                  ),
          ),
          Avatar(perfil, tamano: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                perfil['username'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                '$n ${n == 1 ? tr('cagada', 'poop') : tr('cagadas', 'poops')}${loSigo && meSigue ? tr(' · se siguen', ' · mutuals') : meSigue ? tr(' · te sigue', ' · follows you') : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: numeros(context, tamano: 12, color: p.textoSuave),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          if (loSigo)
            PopupMenuButton<String>(
              tooltip: tr('Opciones', 'Options'),
              onSelected: (a) => switch (a) {
                'retar' => onRetar(),
                'dejar' => onSeguir(),
                _ => onBloquear(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'retar', child: Text(tr('⚔️  Retar a un Cagadón', '⚔️  Challenge to a Poop-Off'))),
                PopupMenuItem(value: 'dejar', child: Text(tr('Dejar de seguir', 'Unfollow'))),
                PopupMenuItem(value: 'bloquear', child: Text(tr('Bloquear', 'Block'))),
              ],
            )
          else
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: onSeguir,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: Size.zero),
                child: Text(meSigue ? tr('SEGUIR DE VUELTA', 'FOLLOW BACK') : tr('SEGUIR', 'FOLLOW')),
              ),
            ),
        ]),
      ),
    );
  }
}
