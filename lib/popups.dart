import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show conReintento, db, textoError;
import 'tema.dart';

// Pop-ups de los admins (tabla public.anuncios). Salen una vez al abrir la app mientras estén
// vigentes, quedan en la Lectura del Baño y, si se pide, mandan push a todos.

/// El pop-up tal cual lo ve la gente. También sirve de vista previa en el editor.
Future<void> verPopup(BuildContext context, Map<String, dynamic> a) => showDialog<void>(
      context: context,
      builder: (context) {
        final boton = a['boton_texto'] as String?;
        final url = a['boton_url'] as String?;
        return AlertDialog(
          title: Column(children: [
            Emoji((a['emoji'] as String?) ?? '📢', tamano: 56),
            const SizedBox(height: 12),
            Text('${a['titulo']}', textAlign: TextAlign.center),
          ]),
          content: SingleChildScrollView(child: Text('${a['texto']}', textAlign: TextAlign.center)),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (boton != null && url != null) ...[
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('CERRAR', 'CLOSE'))),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                child: Text(boton.toUpperCase()),
              ),
            ] else
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('VALE', 'OK'))),
          ],
        );
      },
    );

bool vigente(Map<String, dynamic> a) => DateTime.parse(a['hasta'] as String).isAfter(DateTime.now());

/// Solo admins: los pop-ups publicados y el botón para armar uno nuevo.
class PantallaPopups extends StatefulWidget {
  const PantallaPopups({super.key});

  @override
  State<PantallaPopups> createState() => _PantallaPopupsState();
}

class _PantallaPopupsState extends State<PantallaPopups> {
  List<Map<String, dynamic>>? _lista;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await conReintento(() => db.from('anuncios').select().order('created_at', ascending: false).limit(50));
      if (mounted) setState(() => _lista = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (mounted) {
        setState(() => _lista ??= []);
        _aviso(context, textoError(e));
      }
    }
  }

  Future<void> _opciones(Map<String, dynamic> a) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.visibility_outlined), title: Text(tr('Ver cómo se ve', 'See how it looks')), onTap: () => Navigator.pop(context, 'ver')),
          if (vigente(a))
            ListTile(leading: const Icon(Icons.stop_circle_outlined), title: Text(tr('Apagar ya', 'Turn off now')), onTap: () => Navigator.pop(context, 'apagar')),
          ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr('Borrar', 'Delete')), onTap: () => Navigator.pop(context, 'borrar')),
        ]),
      ),
    );
    if (accion == null || !mounted) return;
    try {
      switch (accion) {
        case 'ver':
          await verPopup(context, a);
        case 'apagar':
          await db.from('anuncios').update({'hasta': DateTime.now().toUtc().toIso8601String()}).eq('id', a['id']);
          await _cargar();
        case 'borrar':
          await db.from('anuncios').delete().eq('id', a['id']);
          await _cargar();
      }
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final lista = _lista;
    return Scaffold(
      appBar: AppBar(title: Text(tr('📢 POP-UPS', '📢 POP-UPS'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _EditorPopup()));
          if (ok == true) await _cargar();
        },
        icon: const Icon(Icons.add),
        label: Text(tr('NUEVO', 'NEW')),
      ),
      body: lista == null
          ? const Center(child: CircularProgressIndicator())
          : lista.isEmpty
              ? Center(child: Text(tr('Todavía no has hecho ningún pop-up', "You haven't made any pop-ups yet"), style: TextStyle(color: p.textoSuave)))
              : ListView.separated(
                  padding: conBordeAbajo(context, const EdgeInsets.only(bottom: 88)),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: p.borde),
                  itemBuilder: (context, i) {
                    final a = lista[i];
                    final activo = vigente(a);
                    final hasta = DateTime.parse(a['hasta'] as String).toLocal();
                    return ListTile(
                      leading: Emoji((a['emoji'] as String?) ?? '📢', tamano: 30),
                      title: Text('${a['titulo']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${activo ? tr('Sale hasta el ${hasta.day}/${hasta.month} ${hasta.hour.toString().padLeft(2, '0')}:${hasta.minute.toString().padLeft(2, '0')}', 'Shows until ${hasta.month}/${hasta.day} ${hasta.hour.toString().padLeft(2, '0')}:${hasta.minute.toString().padLeft(2, '0')}') : tr('Ya no sale', 'No longer showing')}'
                        '${a['push'] == true ? tr(' · con push', ' · with push') : ''}${a['boton_url'] != null ? tr(' · con botón', ' · with button') : ''}',
                        style: numeros(context, tamano: 12, color: p.textoSuave),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        color: activo ? acento : p.suave,
                        child: Text(activo ? tr('ACTIVO', 'ACTIVE') : tr('APAGADO', 'OFF'),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: activo ? acentoTexto : p.textoSuave)),
                      ),
                      onTap: () => _opciones(a),
                    );
                  },
                ),
    );
  }
}

const _emojis = ['📢', '💩', '🚽', '🧻', '👑', '🎉', '🔥', '⚔️', '🆕', '🛠️', '📲', '🏆'];
Map<int, String> get _duraciones => {1: tr('1 día', '1 day'), 3: tr('3 días', '3 days'), 7: tr('1 semana', '1 week'), 30: tr('1 mes', '1 month')};

class _EditorPopup extends StatefulWidget {
  const _EditorPopup();

  @override
  State<_EditorPopup> createState() => _EditorPopupState();
}

class _EditorPopupState extends State<_EditorPopup> {
  final _titulo = TextEditingController();
  final _texto = TextEditingController();
  final _boton = TextEditingController();
  final _url = TextEditingController();
  String _emoji = '📢';
  int _dias = 3;
  bool _push = true;
  // null = para todos; 'es' o 'en' = solo los teléfonos en ese idioma.
  String? _idioma;
  bool _conBoton = false;
  bool _ocupado = false;

  Map<String, dynamic> get _popup => {
        'emoji': _emoji,
        'titulo': _titulo.text.trim(),
        'texto': _texto.text.trim(),
        if (_conBoton) 'boton_texto': _boton.text.trim(),
        if (_conBoton) 'boton_url': _url.text.trim(),
      };

  String? get _problema {
    if (_titulo.text.trim().isEmpty) return tr('Ponle un título', 'Give it a title');
    if (_texto.text.trim().isEmpty) return tr('Escribe el mensaje', 'Write the message');
    if (_conBoton) {
      if (_boton.text.trim().isEmpty) return tr('Ponle texto al botón', 'Add text to the button');
      final u = Uri.tryParse(_url.text.trim());
      if (u == null || u.scheme != 'https' || u.host.isEmpty) return tr('El link tiene que empezar con https://', 'The link has to start with https://');
    }
    return null;
  }

  Future<void> _publicar() async {
    final problema = _problema;
    if (problema != null) return _aviso(context, problema);
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Publicarlo?', 'Publish it?')),
        content: Text(_push
            ? tr('Le llega una notificación a TODOS los teléfonos ahora mismo, y sale como pop-up al abrir la app por ${_duraciones[_dias]}. El push no se puede deshacer.',
                'A notification goes out to EVERY phone right now, and it shows as a pop-up when opening the app for ${_duraciones[_dias]}. The push can\'t be undone.')
            : tr('Sale como pop-up al abrir la app por ${_duraciones[_dias]}. Sin notificación.', 'Shows as a pop-up when opening the app for ${_duraciones[_dias]}. No notification.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('PUBLICAR', 'PUBLISH'))),
        ],
      ),
    );
    if (seguro != true) return;
    setState(() => _ocupado = true);
    try {
      await db.from('anuncios').insert({
        ..._popup,
        'push': _push,
        'idioma': _idioma,
        'hasta': DateTime.now().toUtc().add(Duration(days: _dias)).toIso8601String(),
      });
      if (!mounted) return;
      _aviso(context, _push ? tr('Publicado y enviado a todos 📢', 'Published and sent to everyone 📢') : tr('Publicado 📢', 'Published 📢'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('NUEVO POP-UP', 'NEW POP-UP'))),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Rotulo('Emoji'),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _emojis)
                  InkWell(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: _emoji == e ? acento : p.borde, width: _emoji == e ? 2 : 1),
                        borderRadius: BorderRadius.circular(radio),
                      ),
                      child: Emoji(e, tamano: 26),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _titulo,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Título', 'Title')),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _texto,
                minLines: 3,
                maxLines: 8,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Mensaje', 'Message')),
                onChanged: (_) => setState(() {}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Con botón y link', 'With button and link')),
                subtitle: Text(tr('Ej: "Unirme" → canal de WhatsApp', 'E.g. "Join" → WhatsApp channel')),
                value: _conBoton,
                onChanged: (v) => setState(() => _conBoton = v),
              ),
              if (_conBoton) ...[
                TextField(
                  controller: _boton,
                  maxLength: 30,
                  decoration: InputDecoration(labelText: tr('Texto del botón', 'Button text'), hintText: tr('Unirme', 'Join')),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Link', hintText: 'https://…'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              Rotulo(tr('Para', 'For')),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (valor, nombre) in const [(null, 'TODOS'), ('es', 'ESPAÑOL'), ('en', 'ENGLISH')])
                  ChoiceChip(label: Text(nombre), selected: _idioma == valor, onSelected: (_) => setState(() => _idioma = valor)),
              ]),
              const SizedBox(height: 16),
              Rotulo(tr('Sale por', 'Shows for')),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final MapEntry(key: d, value: nombre) in _duraciones.entries)
                  ChoiceChip(label: Text(nombre.toUpperCase()), selected: _dias == d, onSelected: (_) => setState(() => _dias = d)),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Mandar notificación a todos', 'Send a notification to everyone')),
                subtitle: Text(tr('Si lo apagas, solo sale al abrir la app', 'If you turn it off, it only shows when opening the app')),
                value: _push,
                onChanged: (v) => setState(() => _push = v),
              ),
            ],
          ),
        ),
        Container(
          padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 10, 16, 10)),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borde))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _problema == null ? () => verPopup(context, _popup) : null,
                child: Text(tr('VISTA PREVIA', 'PREVIEW')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: _ocupado ? null : _publicar, child: Text(tr('PUBLICAR', 'PUBLISH')))),
          ]),
        ),
      ]),
    );
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));
