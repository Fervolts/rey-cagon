import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'emoji.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'calendario.dart';
import 'main.dart' show db, escucharCagadas;
import 'push.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'tipos.dart';
import 'widget.dart';

const _avatares = ['💩', '👑', '🧻', '🚽', '🐻', '🦍', '🐷', '🐸', '🦄', '🤡', '🙂', '👻', '🔥', '🌶️', '🍑', '🦖'];

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
      // Sin arrastre de la hoja: arrastrar el avatar mueve lentes y sombrero.
      enableDrag: false,
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
                Padding(
                  padding: const EdgeInsets.only(top: 36, bottom: 8),
                  child: Center(child: Avatar(p, tamano: 96)),
                ),
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
                  Builder(builder: (context) {
                    final total = (p['cagadas'] as num?)?.toInt() ?? (p['total'] as num).toInt();
                    final d = siguienteDesbloqueo(total);
                    return ListTile(
                      leading: d == null ? const Emoji('🏆', tamano: 36) : Opacity(opacity: .4, child: Emoji(d.emoji, tamano: 36)),
                      title: Text(d == null ? 'Lo desbloqueaste todo' : 'Próximo: ${d.nombre}'),
                      subtitle: d == null ? null : Text('Te faltan ${d.minimo - total} cagadas'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _editar,
                    );
                  }),
                if (_esMio) ...[
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Hecho por ahimismito Studios C.A'),
                    subtitle: const Text('ahimismito.com'),
                    onTap: () => launchUrl(Uri.parse('https://ahimismito.com'), mode: LaunchMode.externalApplication),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Créditos y licencias'),
                    onTap: () async {
                      final info = await PackageInfo.fromPlatform();
                      if (!context.mounted) return;
                      showLicensePage(
                        context: context,
                        applicationName: 'Rey Cagón',
                        applicationVersion: info.version,
                        applicationLegalese: '© 2026 ahimismito Studios C.A\nahimismito.com',
                      );
                    },
                  ),
                ],
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
  late final Map<String, dynamic> _puesto = {
    for (final k in ['avatar', 'sombrero', 'lentes', 'mascota', ..._ajustes])
      k: widget.perfil[k],
  };
  // Qué se está moviendo con el dedo en la vista previa: 'lentes', 'sombrero' o null.
  String? _moviendo;
  static const _ajustes = ['lentes_x', 'lentes_y', 'sombrero_x', 'sombrero_y', 'lentes_escala', 'sombrero_escala'];
  static const _vista = 120.0;
  bool _ocupado = false;

  int get _total => (widget.perfil['total'] as num?)?.toInt() ?? 0;

  Future<void> _guardar() async {
    setState(() => _ocupado = true);
    try {
      await db.from('profiles').update({
        'username': _usuario.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        ..._puesto,
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

  void _arrastrar(PointerMoveEvent d) {
    final r = _moviendo!;
    final actual = posicion(_puesto, r);
    setState(() {
      _puesto['${r}_x'] = (actual.x + d.delta.dx / _vista).clamp(-.5, 1.5);
      _puesto['${r}_y'] = (actual.y + d.delta.dy / _vista).clamp(-.5, 1.5);
    });
  }

  /// Fila de opciones de una ranura. Lo bloqueado se ve apagado con las cagadas que pide.
  Widget _ranura(String titulo, String ranura) {
    final opciones = [
      if (ranura == 'avatar')
        for (final a in _avatares) (emoji: a, minimo: 0)
      else
        (emoji: null, minimo: 0),
      for (final d in desbloqueos.where((d) => d.ranura == ranura)) (emoji: d.emoji, minimo: d.minimo),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Rotulo(titulo),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final o in opciones)
                ChoiceChip(
                  label: o.emoji == null
                      ? const SizedBox.square(dimension: 28, child: Icon(Icons.block, size: 22))
                      : o.minimo > _total
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              Opacity(opacity: .3, child: Emoji(o.emoji!, tamano: 28)),
                              const SizedBox(width: 4),
                              Text('${o.minimo}', style: numeros(context, tamano: 12, color: paleta(context).textoSuave)),
                            ])
                          : Emoji(o.emoji!, tamano: 28),
                  selected: _puesto[ranura] == o.emoji,
                  showCheckmark: false,
                  onSelected: o.minimo > _total
                      ? (_) => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Se desbloquea a las ${o.minimo} cagadas. Llevas $_total.')))
                      : (_) => setState(() {
                          _puesto[ranura] = o.emoji;
                          // Avatar nuevo: vuelven a la posición calibrada para él.
                          if (ranura == 'avatar') {
                            for (final k in _ajustes) {
                              _puesto[k] = null;
                            }
                          }
                        }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        physics: _moviendo == null ? null : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('EDITAR PERFIL', style: Theme.of(context).textTheme.titleLarge),
            Padding(
              padding: const EdgeInsets.only(top: 48, bottom: 16),
              child: Center(
                // Listener y no GestureDetector: no compite con el scroll de la hoja, que se
                // congela mientras se mueve algo.
                child: Listener(
                  onPointerMove: _moviendo == null ? null : _arrastrar,
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.all(_vista * .35),
                    child: Avatar({..._puesto, 'cagadas': _total}, tamano: _vista),
                  ),
                ),
              ),
            ),
            if (_puesto['lentes'] != null || _puesto['sombrero'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in ['lentes', 'sombrero'])
                      if (_puesto[r] != null)
                        ChoiceChip(
                          label: Text('MOVER ${r.toUpperCase()}'),
                          selected: _moviendo == r,
                          onSelected: (si) => setState(() => _moviendo = si ? r : null),
                        ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final k in _ajustes) {
                          _puesto[k] = null;
                        }
                      }),
                      child: const Text('RESTABLECER'),
                    ),
                  ],
                ),
              ),
            if (_moviendo != null) ...[
              Text('Arrastra sobre el avatar para mover ${_moviendo == 'lentes' ? 'los lentes' : 'el sombrero'}.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              Row(
                children: [
                  const Rotulo('Tamaño'),
                  Expanded(
                    child: Slider(
                      min: .4,
                      max: 2.5,
                      value: escala(_puesto, _moviendo!).clamp(.4, 2.5),
                      onChanged: (v) => setState(() => _puesto['${_moviendo}_escala'] = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _ranura('Avatar', 'avatar'),
            _ranura('Sombrero', 'sombrero'),
            _ranura('Lentes', 'lentes'),
            _ranura('Mascota', 'mascota'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Tu mascota sale a pasear a las $mascotaSeMueve cagadas. Tu avatar se vuelve '
                '${efectosAvatar.map((e) => '${e.nombre.replaceFirst('Avatar ', '')} a las ${e.minimo}').join(', ')}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
      var consulta = db.from('profiles').select('id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala').neq('id', yo);
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
                    Avatar(g, tamano: 36),
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
