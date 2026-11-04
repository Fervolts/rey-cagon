// Ranking semanal de un minijuego: amigos o global (RPC imperio_minijuego_ranking).

import 'package:flutter/material.dart';

import '../../emoji.dart';
import '../../idioma.dart';
import '../../tema.dart';
import '../control.dart';
import 'datos.dart';

class PantallaRankingMinijuego extends StatefulWidget {
  const PantallaRankingMinijuego({super.key, required this.juego, this.control});
  final String juego;
  final ControlImperio? control;

  @override
  State<PantallaRankingMinijuego> createState() => _PantallaRankingMinijuegoState();
}

class _PantallaRankingMinijuegoState extends State<PantallaRankingMinijuego> {
  String _alcance = 'amigos';
  Future<List<FilaRankingMinijuego>>? _futuro;

  NubeMinijuegos get _nube => (widget.control ?? ControlImperio.vivo)?.nubeMinijuegos ?? const NubeMinijuegos();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() => _futuro = _nube.ranking(widget.juego, _alcance);

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('RANKING DE LA SEMANA', 'WEEKLY RANKING'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            for (final a in const ['amigos', 'global'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _alcance == a
                      ? FilledButton(key: Key('rank_$a'), onPressed: () {}, child: Text(a == 'amigos' ? tr('AMIGOS', 'FRIENDS') : 'GLOBAL'))
                      : OutlinedButton(
                          key: Key('rank_$a'),
                          onPressed: () => setState(() {
                            _alcance = a;
                            _cargar();
                          }),
                          child: Text(a == 'amigos' ? tr('AMIGOS', 'FRIENDS') : 'GLOBAL'),
                        ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<FilaRankingMinijuego>>(
            future: _futuro,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) {
                return Center(child: Text(tr('No se pudo cargar. Revisa tu conexión.', "Couldn't load. Check your connection."), style: TextStyle(color: p.textoSuave)));
              }
              final filas = s.data ?? const [];
              if (filas.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('Nadie ha jugado esta semana. Sé el primero.', 'Nobody has played this week. Be the first.'),
                        textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filas.length,
                itemBuilder: (_, i) {
                  final f = filas[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.tarjeta,
                      border: Border.all(color: f.yo ? p.acento : p.borde),
                      borderRadius: BorderRadius.circular(radio),
                    ),
                    child: Row(children: [
                      SizedBox(width: 34, child: Text('#${f.puesto}', style: TextStyle(fontWeight: FontWeight.w800, color: p.textoSuave))),
                      Emoji(f.avatar, tamano: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: f.yo ? FontWeight.w900 : FontWeight.w600, color: p.texto))),
                      Text('${f.puntos}', style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
