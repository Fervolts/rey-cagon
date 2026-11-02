import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'cadena.dart';

/// Barra de abajo del Imperio: EDIFICIOS, TIENDA, JALAR (solo si [jalar] es visible) y SALA. Baja, para no tapar el baño.
/// JALAR no sale hasta comprar La cadena del trono; después de la primera jalada sale para siempre. Sin hueco.
/// EDIFICIOS abre el cajón; [avisoEdificios] va en la esquina (cuántos se pueden comprar, '!' con un atasco o 'xN' con N atascos).
class BarraImperio extends StatelessWidget {
  const BarraImperio({
    super.key,
    required this.jalar,
    required this.moneda,
    required this.alObjetos,
    required this.alJalar,
    required this.alSala,
    required this.alEdificios,
    this.avisoEdificios,
    this.atasco = false,
  });

  final BotonJalar jalar;
  final String moneda;
  final VoidCallback alObjetos;
  final VoidCallback alJalar;
  final VoidCallback alSala;
  final VoidCallback alEdificios;
  final String? avisoEdificios;

  /// Con atasco el botón de edificios muestra el desatascador.
  final bool atasco;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    Widget boton(String emoji, String texto, VoidCallback? alTocar,
            {String? nota, String? aviso, bool apagado = false, bool resaltado = false, bool rollo = false, Key? key}) =>
        Expanded(
          key: key,
          child: GestureDetector(
            onTap: alTocar,
            child: Opacity(
              opacity: alTocar == null || apagado ? 0.45 : 1,
              child: Container(
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: p.tarjeta,
                  border: Border.all(color: resaltado ? p.primario : p.borde),
                  borderRadius: BorderRadius.circular(radio),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Emoji(emoji, tamano: nota == null ? 18 : 15),
                    if (nota == null) const SizedBox(height: 2),
                    Text(texto, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5, color: p.texto)),
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
                    if (aviso != null)
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          height: 15,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: p.primario, borderRadius: BorderRadius.circular(radio)),
                          alignment: Alignment.center,
                          child: Text(aviso, style: numeros(context, tamano: 9, weight: FontWeight.w900, color: p.sobrePrimario)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Row(
        children: [
          boton(atasco ? '🪠' : '🏗️', tr('EDIFICIOS', 'BUILDINGS'), alEdificios,
              key: const Key('boton_edificios'), aviso: avisoEdificios, resaltado: atasco),
          boton('🛒', tr('TIENDA', 'SHOP'), alObjetos, key: const Key('boton_tienda')),
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
