import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'cadena.dart';

/// Barra de abajo del Imperio: OBJETOS, JALAR (solo si [jalar] es visible) y SALA.
/// JALAR no sale hasta comprar La cadena del trono; después de la primera jalada sale para siempre. Sin hueco.
class BarraImperio extends StatelessWidget {
  const BarraImperio({
    super.key,
    required this.jalar,
    required this.moneda,
    required this.alObjetos,
    required this.alJalar,
    required this.alSala,
  });

  final BotonJalar jalar;
  final String moneda;
  final VoidCallback alObjetos;
  final VoidCallback alJalar;
  final VoidCallback alSala;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    Widget boton(String emoji, String texto, VoidCallback? alTocar, {String? nota, bool apagado = false, bool resaltado = false, bool rollo = false, Key? key}) =>
        Expanded(
          key: key,
          child: GestureDetector(
            onTap: alTocar,
            child: Opacity(
              opacity: alTocar == null || apagado ? 0.45 : 1,
              child: Container(
                height: 64,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: p.tarjeta,
                  border: Border.all(color: resaltado ? p.primario : p.borde),
                  borderRadius: BorderRadius.circular(radio),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Emoji(emoji, tamano: nota == null ? 24 : 20),
                    if (nota == null) const SizedBox(height: 2),
                    Text(texto, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6, color: p.texto)),
                    if (nota != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(nota, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: rollo ? 10 : 8, fontWeight: rollo ? FontWeight.w900 : null, color: rollo ? p.texto : p.textoSuave)),
                            ),
                            if (rollo) ...[const SizedBox(width: 2), const Emoji('🧻', tamano: 11)],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 4, 13, 10),
      child: Row(
        children: [
          boton('🧴', tr('OBJETOS', 'ITEMS'), alObjetos),
          if (jalar.visible)
            boton('🚽', tr('JALAR', 'FLUSH'), alJalar,
                key: const Key('boton_jalar'),
                nota: jalar.nota(moneda),
                apagado: !jalar.encendido,
                resaltado: jalar.encendido,
                rollo: jalar.encendido),
          boton('🕹️', tr('SALA', 'ARCADE'), alSala),
        ],
      ),
    );
  }
}
