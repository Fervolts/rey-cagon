import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendario.dart';
import 'main.dart' show db, escucharCagadas;
import 'push.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'tipos.dart';

const _avatares = ['💩', '👑', '🧻', '🚽', '🐻', '🦍', '🐷', '🐸', '🦄', '🤡', '😎', '👻', '🔥', '🌶️', '🍑', '🦖'];

String _fecha(DateTime d) => '${d.day}/${d.month}/${d.year}';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key, required this.userId});

  final String userId;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  Map<String, dynamic>? _p;
  bool _ocupado = false;
  late final VoidCallback _soltar;

  bool get _esMio => widget.userId == db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _soltar = escucharCagadas('perfil', _load);
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await db.rpc('perfil', params: {'uid': widget.userId});
      if (mounted) setState(() => _p = (rows as List).firstOrNull);
    } catch (e) {
      _toast('Error cargando perfil: $e');
    }
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _seguir() async {
    setState(() => _ocupado = true);
    try {
      if (_p!['lo_sigo'] == true) {
        await db.from('follows').delete().eq('follower', db.auth.currentUser!.id).eq('followed', widget.userId);
      } else {
        await db.from('follows').insert({'followed': widget.userId});
      }
      await _load();
    } catch (e) {
      _toast('Error: $e');
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
    if (cambio == true) await _load();
  }

  Future<void> _salir() async {
    cancelarRecordatorio().catchError((_) {});
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
                Center(child: Text(p['avatar'], style: const TextStyle(fontSize: 72))),
                Center(child: Text(p['username'], style: texto.headlineSmall)),
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
                  leading: Text(tipoEmoji(p['tipo_favorito']), style: const TextStyle(fontSize: 28)),
                  title: const Text('Especialidad de la casa'),
                  subtitle: Text(tipos[p['tipo_favorito']]?.$2 ?? 'Todavía no se sabe'),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text('Ver calendario'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CalendarioScreen(userId: widget.userId, username: p['username']),
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
  late final _username = TextEditingController(text: widget.perfil['username']);
  late final _bio = TextEditingController(text: widget.perfil['bio'] ?? '');
  late String _avatar = widget.perfil['avatar'];
  bool _ocupado = false;

  Future<void> _guardar() async {
    setState(() => _ocupado = true);
    try {
      await db.from('profiles').update({
        'username': _username.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'avatar': _avatar,
      }).eq('id', db.auth.currentUser!.id);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      final msg = e.code == '23505'
          ? 'Ese username ya existe'
          : e.code == '23514'
              ? 'Username de 2 a 24 letras, bio de máximo 140'
              : e.message;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                  label: Text(a, style: const TextStyle(fontSize: 20)),
                  selected: a == _avatar,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _avatar = a),
                ),
            ],
          ),
          TextField(
            controller: _username,
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
class BuscarScreen extends StatefulWidget {
  const BuscarScreen({super.key});

  @override
  State<BuscarScreen> createState() => _BuscarScreenState();
}

class _BuscarScreenState extends State<BuscarScreen> {
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
    final me = db.auth.currentUser!.id;
    try {
      var consulta = db.from('profiles').select('id, username, avatar').neq('id', me);
      if (q.trim().isNotEmpty) {
        // % y _ son comodines en ilike: se escapan para buscar el texto tal cual.
        final limpio = q.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
        consulta = consulta.ilike('username', '%$limpio%');
      }
      final (gente, sigo) = await (
        consulta.order('username').limit(50),
        db.from('follows').select('followed').eq('follower', me),
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
    final me = db.auth.currentUser!.id;
    try {
      if (_sigo.contains(id)) {
        await db.from('follows').delete().eq('follower', me).eq('followed', id);
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
            ListTile(
              leading: Text(g['avatar'], style: const TextStyle(fontSize: 28)),
              title: Text(g['username']),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PerfilScreen(userId: g['id'])),
              ).then((_) => _buscar(_q)),
              trailing: _sigo.contains(g['id'])
                  ? OutlinedButton(onPressed: () => _toggle(g['id']), child: const Text('SIGUIENDO'))
                  : FilledButton(onPressed: () => _toggle(g['id']), child: const Text('SEGUIR')),
            ),
        ],
      ),
    );
  }
}
