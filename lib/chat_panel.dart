import 'package:flutter/material.dart';

import 'amigos.dart' show PantallaAmigos;
import 'animaciones.dart';
import 'chat.dart' show PantallaGeneral, abrirChatAmigos, abrirChatGeneral, abrirChatSoporte, cuerpoSoporte;
import 'chat_sin_leer.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'panel.dart' show PantallaPanel;
import 'popups.dart' show PantallaPopups;
import 'privados.dart' show PantallaPrivados, privadosDisponibles, privadosSinLeer, revisarPrivados;
import 'teclado_emojis.dart' show panelEmojisAbierto;
import 'tema.dart';

enum _Pestana { general, privados, amigos, soporte }

/// El panel de chats que sale de la derecha al tocar el botón de chats del muro: el muro queda atenuado detrás,
/// se cierra tocando afuera, con ✕ o deslizando a la derecha. ⤢ abre ese chat a pantalla completa.
Future<void> abrirPanelChats(BuildContext context, {required bool soyAdmin}) {
  final quieto = movimiento(context) == Movimiento.nada;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Cerrar', 'Close'),
    barrierColor: Colors.black54,
    transitionDuration: quieto ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => PanelChats(soyAdmin: soyAdmin),
    transitionBuilder: (_, anim, _, hijo) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: hijo,
    ),
  );
}

/// El cuerpo del panel: cabecera, pestañas con lo sin leer y el chat elegido en vivo.
class PanelChats extends StatefulWidget {
  const PanelChats({super.key, required this.soyAdmin});

  final bool soyAdmin;

  @override
  State<PanelChats> createState() => _PanelChatsState();
}

class _PanelChatsState extends State<PanelChats> {
  late final _pestanas = [_Pestana.general, if (privadosDisponibles.value) _Pestana.privados, _Pestana.amigos, _Pestana.soporte];
  // Abre en la primera con algo sin leer; si no hay nada, en General.
  late _Pestana _tab = _pestanas[pestanaInicial([for (final t in _pestanas) _sinLeer(t)])];
  double _arrastre = 0;

  bool _sinLeer(_Pestana t) => switch (t) {
        _Pestana.general => chatSinLeer.hay(ChatCual.general),
        _Pestana.soporte => chatSinLeer.hay(ChatCual.soporte),
        _Pestana.privados => privadosSinLeer.value,
        _Pestana.amigos => false,
      };

  int _cuenta(_Pestana t) => switch (t) {
        _Pestana.general => chatSinLeer.cuenta(ChatCual.general),
        _Pestana.soporte => chatSinLeer.cuenta(ChatCual.soporte),
        _ => 0,
      };

  (String, String) _nombre(_Pestana t) => switch (t) {
        _Pestana.general => ('🌎', tr('GENERAL', 'GENERAL')),
        _Pestana.privados => ('💌', tr('PRIVADOS', 'PRIVATE')),
        _Pestana.amigos => ('👥', tr('AMIGOS', 'FRIENDS')),
        _Pestana.soporte => ('🛠️', tr('SOPORTE', 'SUPPORT')),
      };

  void _elegir(_Pestana t) {
    if (t == _tab) return;
    panelEmojisAbierto.value = false;
    // Al salir de Privados se vuelve a mirar si queda alguno sin leer.
    if (_tab == _Pestana.privados) revisarPrivados();
    setState(() => _tab = t);
  }

  @override
  void dispose() {
    panelEmojisAbierto.value = false;
    if (_tab == _Pestana.privados) revisarPrivados();
    super.dispose();
  }

  // Cierra el panel y abre ese chat a pantalla completa (General abre en TODOS).
  void _pantallaCompleta() {
    final nav = Navigator.of(context);
    nav.pop();
    final ctx = nav.context;
    switch (_tab) {
      case _Pestana.general:
        abrirChatGeneral(ctx);
      case _Pestana.amigos:
        abrirChatAmigos(ctx);
      case _Pestana.soporte:
        abrirChatSoporte(ctx, soyAdmin: widget.soyAdmin);
      case _Pestana.privados:
        nav.push(MaterialPageRoute(builder: (_) => const PantallaPrivados())).then((_) => revisarPrivados());
    }
  }

  Widget _cuerpo() => switch (_tab) {
        _Pestana.general => const VistoMientras(cual: ChatCual.general, child: PantallaGeneral(conBarra: false)),
        _Pestana.privados => const PantallaPrivados(conBarra: false),
        _Pestana.amigos => const PantallaAmigos(),
        _Pestana.soporte => cuerpoSoporte(soyAdmin: widget.soyAdmin),
      };

  Widget _pestana(_Pestana t, Paleta p) {
    final elegida = t == _tab;
    final (emoji, nombre) = _nombre(t);
    return Expanded(
      child: InkWell(
        key: Key('panel_tab_${t.name}'),
        onTap: () => _elegir(t),
        child: Container(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: elegida ? p.acento : Colors.transparent, width: 3))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Emoji(emoji, tamano: 18),
              if (_sinLeer(t)) ...[const SizedBox(width: 3), PlacaSinLeer(cuenta: _cuenta(t))],
            ]),
            const SizedBox(height: 3),
            Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: elegida ? p.texto : p.textoSuave),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final (emoji, nombre) = _nombre(_tab);
    const compacto = VisualDensity.compact;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        // Deslizar a la derecha lo cierra.
        onHorizontalDragStart: (_) => _arrastre = 0,
        onHorizontalDragUpdate: (d) => _arrastre += d.delta.dx,
        onHorizontalDragEnd: (d) {
          if (_arrastre > 60 || (d.primaryVelocity ?? 0) > 400) Navigator.pop(context);
        },
        child: Container(
          key: const Key('panel_chats'),
          width: MediaQuery.sizeOf(context).width * 0.85,
          decoration: BoxDecoration(color: p.fondo, border: Border(left: BorderSide(color: p.acento, width: 2))),
          child: Scaffold(
            backgroundColor: p.fondo,
            body: SafeArea(
              left: false,
              bottom: false,
              child: Column(children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borde))),
                  child: Row(children: [
                    Emoji(emoji, tamano: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.texto)),
                    ),
                    // Los admins siguen llegando a Pop-ups y al Panel desde aquí, como en la lista de chats.
                    if (widget.soyAdmin) ...[
                      IconButton(
                        visualDensity: compacto,
                        tooltip: tr('Pop-ups', 'Pop-ups'),
                        icon: const Icon(Icons.campaign_outlined, size: 20),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaPopups())),
                      ),
                      IconButton(
                        visualDensity: compacto,
                        tooltip: tr('Panel', 'Dashboard'),
                        icon: const Icon(Icons.insights_outlined, size: 20),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaPanel())),
                      ),
                    ],
                    IconButton(
                      key: const Key('panel_chats_completo'),
                      visualDensity: compacto,
                      tooltip: tr('Pantalla completa', 'Full screen'),
                      icon: const Icon(Icons.open_in_full, size: 20),
                      onPressed: _pantallaCompleta,
                    ),
                    IconButton(
                      key: const Key('panel_chats_cerrar'),
                      visualDensity: compacto,
                      tooltip: tr('Cerrar', 'Close'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borde))),
                  child: ListenableBuilder(
                    listenable: chatSinLeer,
                    builder: (context, _) => Row(children: [for (final t in _pestanas) _pestana(t, p)]),
                  ),
                ),
                Expanded(child: KeyedSubtree(key: ValueKey(_tab), child: _cuerpo())),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// La placa de una pestaña: cuadro amarillo con el número ("99+" desde 100), o un punto amarillo si aún no hay número.
class PlacaSinLeer extends StatelessWidget {
  const PlacaSinLeer({super.key, required this.cuenta});

  final int cuenta;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final etiqueta = etiquetaCuenta(cuenta);
    if (etiqueta == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: p.acento, borderRadius: BorderRadius.circular(radio)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: p.acento, borderRadius: BorderRadius.circular(radio)),
      child: Text(etiqueta, style: numeros(context, tamano: 10, weight: FontWeight.w800, color: p.acentoTexto)),
    );
  }
}
