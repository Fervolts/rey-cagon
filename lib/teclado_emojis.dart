import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'idioma.dart';
import 'tema.dart';

// Teclado de emojis del chat, como el de iOS: ocupa el lugar del teclado del sistema, con
// secciones, barra de categorías abajo y borrar. Los emojis se pintan como texto (igual que en
// los mensajes); los nuevos salen con la fuente de respaldo del tema.

const _caras = [
  '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍', '🤩',
  '😘', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🫢', '🫣', '🤫', '🤔', '🫡', '🤐', '🤨',
  '😐', '😑', '😶', '🫥', '😏', '😒', '🙄', '😬', '😮‍💨', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷',
  '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '🥸', '😎', '🤓', '🧐',
  '😕', '🫤', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '🥹', '😦', '😧', '😨', '😰', '😥', '😢',
  '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀',
  '☠️', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖',
];

const _bano = [
  '💩', '🚽', '🧻', '🪠', '🧼', '🚿', '🛁', '🪥', '🧴', '💨', '💦', '🩸', '🔥', '💥', '☢️', '🌋',
  '🐋', '🍑', '🌶️', '🌽', '🫘', '🥦', '☕', '🍺', '🌮', '🌯', '🍔', '🍕', '👑', '🤴', '👸', '🏆',
  '🥇', '🥈', '🥉', '🎖️',
];

const _gestos = [
  '👍', '👎', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '🙏', '✌️', '🤞', '🫰', '🤟', '🤘', '👌', '🤌',
  '🤏', '👈', '👉', '👆', '👇', '☝️', '✋', '🤚', '🖐️', '🖖', '👋', '🤙', '💪', '🦵', '🦶', '👂',
  '👃', '🧠', '👀', '👁️', '👅', '👄', '🙈', '🙉', '🙊',
];

const _corazones = [
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤️‍🔥', '💕', '💞', '💓', '💗', '💖',
  '💘', '💝', '💯', '💢', '💫', '🕳️', '💬', '🗯️', '💭', '💤', '✨', '⭐', '🌟', '⚡', '🎉', '🎊',
  '🎈', '🎁', '🏁', '🚩', '✅', '❌', '⚠️', '🆘', '🔞',
];

const _animales = [
  '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔',
  '🐧', '🐦', '🐤', '🦆', '🦅', '🦉', '🐴', '🦄', '🐝', '🪰', '🪳', '🐛', '🦋', '🐌', '🐍', '🦖',
  '🐢', '🐙', '🦀', '🐟', '🐬', '🐳', '🦈', '🐊', '🦨', '🐀',
];

const _comida = [
  '🍎', '🍌', '🍉', '🍇', '🍓', '🥑', '🍆', '🥕', '🍄', '🥜', '🍞', '🧀', '🥚', '🍳', '🥓', '🍗',
  '🍖', '🌭', '🍟', '🥗', '🍝', '🍜', '🍣', '🍦', '🍩', '🍪', '🎂', '🍫', '🍬', '🍵', '🥤', '🍻',
  '🥂', '🍷', '🥃',
];

const _cosas = [
  '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🎮', '🎲', '🎯', '🎸', '🎧', '📱', '💻', '📸', '📺', '⏰',
  '⌛', '💡', '💸', '💰', '💳', '📦', '✏️', '📌', '✂️', '🔒', '🔑', '🔨', '💣', '🧨', '💊', '💉',
  '🧪', '🚗', '🚕', '🚑', '🚓', '🚒', '✈️', '🚀', '🛸', '🏠', '🏥', '🗿', '🌍', '🌙', '☀️', '⛅',
  '🌧️', '⛈️', '🌈', '❄️', '☃️', '🌊',
];

const _maxRecientes = 24;
const _claveRecientes = 'emojis_recientes';

// Alto del teclado del sistema la última vez que se vio, para que el panel ocupe lo mismo.
double _altoTeclado = 0;

/// Recuerda el alto del teclado del sistema. Llamarlo en el build de la pantalla del chat.
void recordarAltoTeclado(BuildContext context) {
  final alto = MediaQuery.viewInsetsOf(context).bottom;
  if (alto > 150) _altoTeclado = alto;
}

/// Mete [e] donde está el cursor de [texto] (o reemplaza lo seleccionado).
void insertarEnTexto(TextEditingController texto, String e) {
  final sel = texto.selection;
  final inicio = sel.isValid ? sel.start : texto.text.length;
  final fin = sel.isValid ? sel.end : texto.text.length;
  texto.value = TextEditingValue(
    text: texto.text.replaceRange(inicio, fin, e),
    selection: TextSelection.collapsed(offset: inicio + e.length),
  );
}

/// Borra lo seleccionado o el último carácter visible antes del cursor (un emoji entero, no medio).
void borrarEnTexto(TextEditingController texto) {
  final sel = texto.selection;
  final fin = sel.isValid ? sel.end : texto.text.length;
  var inicio = sel.isValid ? sel.start : fin;
  if (inicio == fin) {
    if (fin == 0) return;
    inicio = texto.text.substring(0, fin).characters.skipLast(1).toString().length;
  }
  texto.value = TextEditingValue(
    text: texto.text.replaceRange(inicio, fin, ''),
    selection: TextSelection.collapsed(offset: inicio),
  );
}

/// El panel de emojis. Va debajo de la caja de texto cuando el teclado del sistema está escondido.
class TecladoEmojis extends StatefulWidget {
  const TecladoEmojis({super.key, required this.texto});

  final TextEditingController texto;

  @override
  State<TecladoEmojis> createState() => _TecladoEmojisState();
}

class _TecladoEmojisState extends State<TecladoEmojis> {
  final _scroll = ScrollController();
  List<String> _recientes = [];
  int _actual = 0;
  // Dónde empieza cada sección; se recalcula en cada build con el ancho real.
  List<double> _inicios = [];
  // Mientras salta por un toque en la barra, el scroll no cambia la categoría marcada.
  bool _saltando = false;

  static const _altoTitulo = 30.0;

  List<(IconData, String, List<String>)> get _secciones => [
        if (_recientes.isNotEmpty) (Icons.schedule, tr('RECIENTES', 'RECENT'), _recientes),
        (Icons.emoji_emotions_outlined, tr('CARAS', 'FACES'), _caras),
        (Icons.wc, tr('DEL BAÑO', 'BATHROOM'), _bano),
        (Icons.waving_hand_outlined, tr('GESTOS', 'GESTURES'), _gestos),
        (Icons.favorite_border, tr('CORAZONES Y SÍMBOLOS', 'HEARTS & SYMBOLS'), _corazones),
        (Icons.pets, tr('ANIMALES', 'ANIMALS'), _animales),
        (Icons.fastfood_outlined, tr('COMIDA', 'FOOD'), _comida),
        (Icons.sports_soccer_outlined, tr('COSAS', 'THINGS'), _cosas),
      ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alMover);
    SharedPreferences.getInstance().then((prefs) {
      final guardados = prefs.getStringList(_claveRecientes) ?? const [];
      if (mounted && guardados.isNotEmpty) setState(() => _recientes = guardados);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _alMover() {
    if (_saltando || _inicios.isEmpty) return;
    final y = _scroll.offset + 1;
    var i = 0;
    while (i + 1 < _inicios.length && _inicios[i + 1] <= y) {
      i++;
    }
    if (i != _actual) setState(() => _actual = i);
  }

  Future<void> _ir(int i) async {
    setState(() => _actual = i);
    _saltando = true;
    final destino = _inicios[i].clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(destino, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    _saltando = false;
  }

  void _poner(String e) {
    HapticFeedback.selectionClick();
    insertarEnTexto(widget.texto, e);
    // Los recientes se guardan pero no se reordenan en pantalla mientras está abierto: si no, el
    // emoji se movería debajo del dedo.
    final nuevos = [e, ..._recientes.where((r) => r != e)].take(_maxRecientes).toList();
    SharedPreferences.getInstance().then((prefs) => prefs.setStringList(_claveRecientes, nuevos));
    if (_recientes.isEmpty) setState(() => _recientes = nuevos);
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final pantalla = MediaQuery.sizeOf(context).height;
    final alto = (_altoTeclado > 0 ? _altoTeclado : pantalla * .36).clamp(240.0, pantalla * .45);
    final secciones = _secciones;
    final estilo = DefaultTextStyle.of(context).style.copyWith(fontSize: 28, height: 1.15);
    return Container(
      height: alto,
      decoration: BoxDecoration(color: p.suave, border: Border(top: BorderSide(color: p.borde))),
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, caja) {
            const lado = 8.0;
            final columnas = ((caja.maxWidth - lado * 2) / 46).floor().clamp(6, 14);
            final celda = (caja.maxWidth - lado * 2) / columnas;
            final inicios = <double>[];
            var y = 0.0;
            for (final s in secciones) {
              inicios.add(y);
              y += _altoTitulo + (s.$3.length / columnas).ceil() * celda;
            }
            _inicios = inicios;
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                for (final (_, titulo, emojis) in secciones) ...[
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _altoTitulo,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: Text(titulo, style: numeros(context, tamano: 10, weight: FontWeight.w800, color: p.textoSuave)),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: lado),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columnas),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => InkWell(
                          onTap: () => _poner(emojis[i]),
                          borderRadius: BorderRadius.circular(radio),
                          child: Center(child: Text(emojis[i], style: estilo)),
                        ),
                        childCount: emojis.length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            );
          }),
        ),
        Container(
          height: 44,
          decoration: BoxDecoration(color: p.tarjeta, border: Border(top: BorderSide(color: p.borde))),
          child: Row(children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final (i, (icono, titulo, _)) in secciones.indexed)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == _actual,
                        label: titulo,
                        child: InkWell(
                          onTap: () => _ir(i),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: i == _actual ? acento : Colors.transparent, width: 2)),
                            ),
                            child: Icon(icono, size: 20, color: i == _actual ? p.texto : p.textoSuave),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(width: 1, color: p.borde),
            SizedBox(
              width: 52,
              child: InkWell(
                onTap: () => borrarEnTexto(widget.texto),
                child: Icon(Icons.backspace_outlined, size: 20, color: p.texto, semanticLabel: tr('Borrar', 'Delete')),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Para la pantalla que tiene la caja de texto: el botón alterna entre el teclado del sistema y
/// el de emojis, y tocar la caja vuelve al del sistema.
mixin ConTecladoEmojis<T extends StatefulWidget> on State<T> {
  final focoTexto = FocusNode();
  bool emojisAbiertos = false;

  void alternarEmojis() {
    if (emojisAbiertos) {
      setState(() => emojisAbiertos = false);
      focoTexto.requestFocus();
      return;
    }
    focoTexto.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() => emojisAbiertos = true);
  }

  void cerrarEmojis() {
    if (emojisAbiertos) setState(() => emojisAbiertos = false);
  }

  /// Botón de la caja de texto: carita para abrir los emojis, teclado para volver.
  Widget botonEmojis() => IconButton(
        onPressed: alternarEmojis,
        icon: Icon(emojisAbiertos ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined),
        tooltip: emojisAbiertos ? tr('Teclado', 'Keyboard') : tr('Emojis', 'Emojis'),
      );

  /// La caja de texto con el panel debajo. Atrás cierra el panel antes de salir.
  Widget conPanelEmojis(BuildContext context, TextEditingController texto, Widget caja) {
    recordarAltoTeclado(context);
    return PopScope(
      canPop: !emojisAbiertos,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) cerrarEmojis();
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        caja,
        if (emojisAbiertos) TecladoEmojis(texto: texto),
      ]),
    );
  }

  @override
  void dispose() {
    focoTexto.dispose();
    super.dispose();
  }
}
