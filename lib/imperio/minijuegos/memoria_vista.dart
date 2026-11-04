// Memoria del rollo: parejas con los emojis de la app, tres niveles seguidos (4x3, 4x4, 5x4). Lógica en memoria_logica.dart.

import 'package:flutter/material.dart';

import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import 'marco.dart';
import 'memoria_logica.dart';

class VistaMemoria extends StatefulWidget {
  const VistaMemoria({super.key, required this.alTerminar, this.partida});
  final AlTerminarJuego alTerminar;

  /// Solo para pruebas.
  final PartidaMemoria? partida;

  @override
  State<VistaMemoria> createState() => _VistaMemoriaState();
}

class _VistaMemoriaState extends State<VistaMemoria> with SingleTickerProviderStateMixin {
  late final PartidaMemoria _pa = widget.partida ?? PartidaMemoria();
  late final RelojJuego _reloj;
  final _sw = Stopwatch();
  bool _entreNiveles = false;
  bool _acabo = false;

  @override
  void initState() {
    super.initState();
    _reloj = RelojJuego(this, _paso);
    _sw.start();
    _reloj.arrancar();
  }

  void _paso(double dt) {
    if (_acabo || _entreNiveles) return;
    _pa.juego.avanzar(dt);
    if (_pa.nivelTerminado) {
      _reloj.parar();
      _sw.stop();
      if (_pa.terminada) {
        _acabo = true;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) widget.alTerminar(_pa.puntos, _sw.elapsedMilliseconds);
        });
      } else {
        _entreNiveles = true;
      }
    }
    setState(() {});
  }

  void _siguiente() {
    _pa.siguiente();
    _entreNiveles = false;
    _sw.start();
    _reloj.arrancar();
    setState(() {});
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final j = _pa.juego;
    final n = j.nivel;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          Text(tr('Nivel ${_pa.nivel + 1} de ${nivelesMemoria.length}', 'Level ${_pa.nivel + 1} of ${nivelesMemoria.length}'), style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
          const Spacer(),
          Text(tr('Errores ${_pa.erroresTotal}', 'Mistakes ${_pa.erroresTotal}'), key: const Key('memoria_errores'), style: TextStyle(color: p.textoSuave)),
          const SizedBox(width: 12),
          Text('${j.segundos.toStringAsFixed(1)} s', style: TextStyle(color: p.textoSuave)),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _entreNiveles
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('Nivel superado', 'Level cleared'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.texto)),
                    const SizedBox(height: 6),
                    Text(tr('${_pa.puntos} puntos hasta ahora', '${_pa.puntos} points so far'), style: TextStyle(color: p.textoSuave)),
                    const SizedBox(height: 16),
                    FilledButton(key: const Key('memoria_siguiente'), onPressed: _siguiente, child: Text(tr('SIGUIENTE NIVEL', 'NEXT LEVEL'))),
                  ]),
                )
              : LayoutBuilder(builder: (context, c) {
                  const sep = 8.0;
                  final w = (c.maxWidth - sep * (n.columnas - 1)) / n.columnas;
                  final h = (c.maxHeight - sep * (n.filas - 1)) / n.filas;
                  final lado = w < h ? w : h;
                  return Center(
                    child: SizedBox(
                      width: lado * n.columnas + sep * (n.columnas - 1),
                      height: lado * n.filas + sep * (n.filas - 1),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: n.columnas, crossAxisSpacing: sep, mainAxisSpacing: sep),
                        itemCount: j.cartas.length,
                        itemBuilder: (_, i) => _CartaVista(
                          key: Key('carta_$i'),
                          carta: j.cartas[i],
                          lado: lado,
                          alTocar: () {
                            j.toca(i);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                  );
                }),
        ),
      ),
    ]);
  }
}

class _CartaVista extends StatelessWidget {
  const _CartaVista({super.key, required this.carta, required this.lado, required this.alTocar});
  final Carta carta;
  final double lado;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final abierta = carta.estado != EstadoCarta.oculta;
    final hecha = carta.estado == EstadoCarta.hecha;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: alTocar,
      child: Container(
        decoration: BoxDecoration(
          color: abierta ? p.tarjeta : p.suave,
          border: Border.all(color: hecha ? p.acento : (abierta ? p.bordeFuerte : p.borde)),
          borderRadius: BorderRadius.circular(radio),
        ),
        alignment: Alignment.center,
        child: abierta
            ? Opacity(opacity: hecha ? 0.55 : 1, child: Emoji(carta.emoji, tamano: lado * 0.55))
            : Text('?', style: TextStyle(fontSize: lado * 0.4, fontWeight: FontWeight.w900, color: p.textoSuave)),
      ),
    );
  }
}
