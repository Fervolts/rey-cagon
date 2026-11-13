// Chat rápido: los últimos mensajes de una sala y una caja para contestar ahí mismo, sin abrir el chat entero.
// Lo usa la zona de la Cloaca encima del código para invitar.

import 'dart:async';

import 'package:flutter/material.dart';

import 'accesorios.dart' show Avatar, columnasAvatar;
import 'chat.dart' show aceptoReglas;
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show db, textoError, ultimosDeSala;
import 'tema.dart';

class ChatRapido extends StatefulWidget {
  const ChatRapido({super.key, required this.sala, this.alVerTodo, this.cuantos = 4});

  final String sala;
  final VoidCallback? alVerTodo;
  final int cuantos;

  @override
  State<ChatRapido> createState() => _ChatRapidoState();
}

class _ChatRapidoState extends State<ChatRapido> {
  final _texto = TextEditingController();
  final _perfiles = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _ultimos = const [];
  VoidCallback? _soltar;
  bool _cargado = false, _enviando = false;

  String get _yo => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _escuchar();
  }

  @override
  void didUpdateWidget(ChatRapido viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.sala != widget.sala) _escuchar();
  }

  @override
  void dispose() {
    _soltar?.call();
    _texto.dispose();
    super.dispose();
  }

  void _escuchar() {
    _soltar?.call();
    _soltar = ultimosDeSala(widget.sala, widget.cuantos * 3, _alLlegar);
    // Si la primera consulta falla, que no quede la rueda para siempre.
    Timer(const Duration(seconds: 20), () {
      if (mounted && !_cargado) setState(() => _cargado = true);
    });
  }

  // Sin respuestas de hilos ni ocultos de otros: lo mismo que se ve abajo del todo en el chat.
  void _alLlegar(List<Map<String, dynamic>> filas) {
    if (!mounted) return;
    final ultimos = filas
        .where((m) => m['responde_a'] == null && (m['oculto'] != true || m['user_id'] == _yo))
        .take(widget.cuantos)
        .toList()
        .reversed
        .toList();
    setState(() {
      _ultimos = ultimos;
      _cargado = true;
    });
    final faltan = {for (final m in ultimos) '${m['user_id']}'}.where((id) => !_perfiles.containsKey(id)).toList();
    if (faltan.isEmpty) return;
    db.from('profiles').select(columnasAvatar).inFilter('id', faltan).then((r) {
      for (final p in r) {
        _perfiles[p['id'] as String] = p;
      }
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  Future<void> _enviar() async {
    final t = _texto.text.trim();
    if (t.isEmpty || _enviando) return;
    if (!await aceptoReglas(context) || !mounted) return;
    setState(() => _enviando = true);
    try {
      await db.from('mensajes').insert({'sala': widget.sala, 'texto': t});
      _texto.clear();
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: TextoConEmojis(textoError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _fila(Paleta p, Map<String, dynamic> m) {
    final perfil = _perfiles['${m['user_id']}'];
    final texto = '${m['texto'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 28, height: 28, child: perfil == null ? const Emoji('💩', tamano: 22) : Avatar(perfil, tamano: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextoConEmojis(m['user_id'] == _yo ? tr('Tú', 'You') : '${perfil?['username'] ?? '…'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: p.textoSuave)),
            TextoConEmojis(texto.isEmpty ? tr('mandó una tarjeta', 'sent a card') : texto,
                maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.3, color: p.texto)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Rotulo(tr('Chat rápido', 'Quick chat'))),
          if (widget.alVerTodo != null)
            TextButton(
              key: const Key('chat_rapido_ver_todo'),
              onPressed: widget.alVerTodo,
              child: Text(tr('VER TODO', 'SEE ALL'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6)),
            ),
        ]),
        if (!_cargado)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (_ultimos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Nadie ha dicho nada todavía. Rompe el hielo.', 'Nobody has said anything yet. Break the ice.'),
                style: TextStyle(color: p.textoSuave, fontSize: 13)),
          )
        else
          for (final m in _ultimos) _fila(p, m),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('chat_rapido_texto'),
              controller: _texto,
              minLines: 1,
              maxLines: 3,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviar(),
              decoration: InputDecoration(
                hintText: tr('Escribe a tu Cloaca…', 'Write to your Sewer…'),
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(radio)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filled(
              key: const Key('chat_rapido_enviar'),
              tooltip: tr('Enviar', 'Send'),
              style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio))),
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 20),
            ),
          ),
        ]),
      ]),
    );
  }
}
