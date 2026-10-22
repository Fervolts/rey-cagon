import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accesorios.dart';
import 'cagadon.dart' show retar;
import 'emoji.dart';
import 'main.dart' show conReintento, db, escucharCagadas, textoError;
import 'perfil.dart' show PantallaPerfil;
import 'tema.dart';

// Pestaña AMIGOS del baño: buscar gente, a quién sigues, quién te sigue y tus favoritos arriba.

const _columnas =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

enum _Lista { sigues, teSiguen }

enum _Orden { nombre, cagadas }

class PantallaAmigos extends StatefulWidget {
  const PantallaAmigos({super.key});

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
      if (!mounted) return;
      setState(() {
        _sigo = s;
        _meSiguen = m;
        _bloqueados = {for (final b in bloqueos) b['bloqueado'] as String};
        _perfiles = {for (final p in perfiles) p['id'] as String: p};
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
        title: Text('¿Bloquear a ${g['username']}?'),
        content: const Text('Deja de verte y tú dejas de verlo: rankings, chat y follows en los dos sentidos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('BLOQUEAR')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('bloqueos').insert({'bloqueado': g['id']});
      _aviso('Bloqueado');
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
    final gente = buscando ? resultados : _visibles;
    final sinSeguirDeVuelta = _meSiguen.difference(_sigo).difference(_bloqueados).length;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 12, 16, 16)),
        children: [
          TextField(
            controller: _buscador,
            onChanged: _escribiendo,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar gente por username',
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
          if (!buscando) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text('SIGUES · ${_sigo.difference(_bloqueados).length}'),
                selected: _lista == _Lista.sigues,
                onSelected: (_) => setState(() => _lista = _Lista.sigues),
              ),
              ChoiceChip(
                label: Text('TE SIGUEN · ${_meSiguen.difference(_bloqueados).length}'),
                selected: _lista == _Lista.teSiguen,
                onSelected: (_) => setState(() => _lista = _Lista.teSiguen),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  _lista == _Lista.teSiguen && sinSeguirDeVuelta > 0
                      ? '$sinSeguirDeVuelta sin seguir de vuelta'
                      : '★ = favorito, sale arriba',
                  style: TextStyle(color: p.textoSuave, fontSize: 12),
                ),
              ),
              PopupMenuButton<_Orden>(
                initialValue: _orden,
                onSelected: (o) => setState(() => _orden = o),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Orden.nombre, child: Text('Por nombre')),
                  PopupMenuItem(value: _Orden.cagadas, child: Text('Por cagadas')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sort, size: 18, color: p.textoSuave),
                    const SizedBox(width: 4),
                    Text(_orden == _Orden.nombre ? 'A-Z' : 'MÁS CAGADAS', style: numeros(context, tamano: 12, color: p.textoSuave)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 4),
          ],
          if (_cargando && !buscando)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (gente.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(children: [
                Emoji(buscando ? '🫥' : '🚽', tamano: 48),
                const SizedBox(height: 8),
                Text(
                  buscando
                      ? 'Nadie con ese nombre'
                      : _lista == _Lista.sigues
                          ? 'No sigues a nadie. Búscalos arriba para competir.'
                          : 'Nadie te sigue todavía. Pásales tu username.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textoSuave),
                ),
              ]),
            )
          else
            for (final g in gente)
              _FilaAmigo(
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
                    tooltip: favorito ? 'Quitar de favoritos' : 'Favorito',
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
                '$n ${n == 1 ? 'cagada' : 'cagadas'}${loSigo && meSigue ? ' · se siguen' : meSigue ? ' · te sigue' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: numeros(context, tamano: 12, color: p.textoSuave),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          if (loSigo)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (a) => switch (a) {
                'retar' => onRetar(),
                'dejar' => onSeguir(),
                _ => onBloquear(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'retar', child: Text('⚔️  Retar a un Cagadón')),
                PopupMenuItem(value: 'dejar', child: Text('Dejar de seguir')),
                PopupMenuItem(value: 'bloquear', child: Text('Bloquear')),
              ],
            )
          else
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: onSeguir,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: Size.zero),
                child: Text(meSigue ? 'SEGUIR DE VUELTA' : 'SEGUIR'),
              ),
            ),
        ]),
      ),
    );
  }
}
