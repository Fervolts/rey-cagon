import 'package:flutter/material.dart';
import 'emoji.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendario.dart';
import 'main.dart' show db, escucharCagadas;
import 'push.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'tipos.dart';
import 'widget.dart';

const _avatares = ['💩', '👑', '🧻', '🚽', '🐻', '🦍', '🐷', '🐸', '🦄', '🤡', '😎', '👻', '🔥', '🌶️', '🍑', '🦖'];

String _fecha(DateTime d) => '${d.day}/${d.month}/${d.year}';

class PantallaPerfil extends StatefulWidget {
  const PantallaPerfil({super.key, required this.usuarioId});

  final String usuarioId;

  @override
  State<PantallaPerfil> createState() => _PantallaPerfilState();
}

class _PantallaPerfilState extends State<PantallaPerfil> {
  Map<String, dynamic>? _p;
  bool _ocupado = false;
  late final VoidCallback _soltar;

  bool get _esMio => widget.usuarioId == db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _cargar();
    _soltar = escucharCagadas('perfil', _cargar);
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final rows = await db.rpc('perfil', params: {'uid': widget.usuarioId});
      if (mounted) setState(() => _p = (rows as List).firstOrNull);
    } catch (e) {
      _mensaje('Error cargando perfil: $e');
    }
  }

  void _mensaje(String texto) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _seguir() async {
    setState(() => _ocupado = true);
    try {
      if (_p!['lo_sigo'] == true) {
        await db.from('follows').delete().eq('follower', db.auth.currentUser!.id).eq('followed', widget.usuarioId);
      } else {
        await db.from('follows').insert({'followed': widget.usuarioId});
      }
      await _cargar();
    } catch (e) {
      _mensaje('Error: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _editar() async {
    final cambio = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditarPerfil(perfil: _p!),
    );
    if (cambio == true) await _cargar();
  }

  Future<void> _salir() async {
    cancelarRecordatorio().catchError((_) {});
    limpiarWidget().catchError((_) {});
    await olvidarTelefono().catchError((_) {});
    await db.auth.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_esMio ? 'MI PERFIL' : 'PERFIL'),
        actions: [
          if (_esMio && p != null) IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: _editar),
          if (_esMio) IconButton(icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión', onPressed: _salir),
        ],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(child: Emoji(p['avatar'], tamano: 96)),
                Text(p['username'],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: texto.headlineSmall),
                if ((p['bio'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(p['bio'], textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 4),
                Text('Cagando desde el ${_fecha(DateTime.parse(p['desde']).toLocal())}',
                    textAlign: TextAlign.center, style: texto.bodySmall),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Numero(valor: p['seguidores'], texto: 'seguidores'),
                    const SizedBox(width: 32),
                    _Numero(valor: p['siguiendo'], texto: 'siguiendo'),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_esMio)
                  Center(
                    child: p['lo_sigo'] == true
                        ? OutlinedButton(onPressed: _ocupado ? null : _seguir, child: const Text('DEJAR DE SEGUIR'))
                        : FilledButton(onPressed: _ocupado ? null : _seguir, child: const Text('SEGUIR')),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      runSpacing: 12,
                      children: [
                        _Numero(valor: p['hoy'], texto: 'hoy'),
                        _Numero(valor: p['semana'], texto: 'semana'),
                        _Numero(valor: p['mes'], texto: 'mes'),
                        _Numero(valor: p['anio'], texto: 'año'),
                        _Numero(valor: p['total'], texto: 'total'),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: Emoji(tipoEmoji(p['tipo_favorito']), tamano: 36),
                  title: const Text('Especialidad de la casa'),
                  subtitle: Text(tipos[p['tipo_favorito']]?.$2 ?? 'Todavía no se sabe'),
                ),
                if (_esMio)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Créditos y licencias'),
                    onTap: () => showLicensePage(context: context, applicationName: 'Rey Cagón'),
                  ),
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text('Ver calendario'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PantallaCalendario(usuarioId: widget.usuarioId, nombre: p['username']),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.valor, required this.texto});

  final Object? valor;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Text('$valor', style: Theme.of(context).textTheme.titleLarge),
            Rotulo(texto),
          ],
        ),
      );
}

class _EditarPerfil extends StatefulWidget {
  const _EditarPerfil({required this.perfil});

  final Map<String, dynamic> perfil;

  @override
  State<_EditarPerfil> createState() => _EditarPerfilState();
}

class _EditarPerfilState extends State<_EditarPerfil> {
  late final _usuario = TextEditingController(text: widget.perfil['username']);
  late final _bio = TextEditingController(text: widget.perfil['bio'] ?? '');
  late String _avatar = widget.perfil['avatar'];
  bool _ocupado = false;

  Future<void> _guardar() async {
    setState(() => _ocupado = true);
    try {
      await db.from('profiles').update({
        'username': _usuario.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'avatar': _avatar,
      }).eq('id', db.auth.currentUser!.id);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      final texto = e.code == '23505'
          ? 'Ese username ya existe'
          : e.code == '23514'
              ? 'Username de 2 a 24 letras, bio de máximo 140'
              : e.message;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('EDITAR PERFIL', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final a in _avatares)
                ChoiceChip(
                  label: Emoji(a, tamano: 28),
                  selected: a == _avatar,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _avatar = a),
                ),
            ],
          ),
          TextField(
            controller: _usuario,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          TextField(
            controller: _bio,
            maxLength: 140,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('GUARDAR')),
        ],
      ),
    );
  }
}

/// Buscar gente por username para seguirla.
class PantallaBuscar extends StatefulWidget {
  const PantallaBuscar({super.key});

  @override
  State<PantallaBuscar> createState() => _PantallaBuscarState();
}

class _PantallaBuscarState extends State<PantallaBuscar> {
  List<Map<String, dynamic>> _gente = [];
  Set<String> _sigo = {};
  String _q = '';

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    _q = q;
    final yo = db.auth.currentUser!.id;
    try {
      var consulta = db.from('profiles').select('id, username, avatar').neq('id', yo);
      if (q.trim().isNotEmpty) {
        // % y _ son comodines en ilike: se escapan para buscar el texto tal cual.
        final limpio = q.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
        consulta = consulta.ilike('username', '%$limpio%');
      }
      final (gente, sigo) = await (
        consulta.order('username').limit(50),
        db.from('follows').select('followed').eq('follower', yo),
      ).wait;
      if (!mounted || q != _q) return;
      setState(() {
        _gente = List<Map<String, dynamic>>.from(gente);
        _sigo = {for (final f in sigo) f['followed'] as String};
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggle(String id) async {
    final yo = db.auth.currentUser!.id;
    try {
      if (_sigo.contains(id)) {
        await db.from('follows').delete().eq('follower', yo).eq('followed', id);
      } else {
        await db.from('follows').insert({'followed': id});
      }
      await _buscar(_q);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BUSCAR AMIGOS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Username'),
            onChanged: _buscar,
          ),
          const SizedBox(height: 8),
          if (_gente.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nadie por aquí 🫥', textAlign: TextAlign.center)),
          for (final g in _gente)
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: g['id'])),
              ).then((_) => _buscar(_q)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Emoji(g['avatar'], tamano: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        g['username'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Ancho fijo: el botón no se encoge ni empuja el nombre.
                    SizedBox(
                      width: 116,
                      height: 40,
                      child: _sigo.contains(g['id'])
                          ? OutlinedButton(
                              onPressed: () => _toggle(g['id']),
                              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                              child: const Text('SIGUIENDO'),
                            )
                          : FilledButton(
                              onPressed: () => _toggle(g['id']),
                              style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                              child: const Text('SEGUIR'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
