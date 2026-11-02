// Ranking del Imperio entre amigos: tú y la gente que sigues, por MJ ganados en la partida (RPC `imperio_ranking_amigos`).
import 'package:flutter/material.dart';

import '../accesorios.dart' show Avatar;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show conReintento, db, textoError;
import '../perfil.dart' show PantallaPerfil;
import '../tema.dart';
import 'formato.dart';

/// Abre la hoja con el ranking.
Future<void> abrirRankingImperio(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => const _HojaRanking(),
  );
}

class _HojaRanking extends StatefulWidget {
  const _HojaRanking();

  @override
  State<_HojaRanking> createState() => _HojaRankingState();
}

class _HojaRankingState extends State<_HojaRanking> {
  late Future<List<Map<String, dynamic>>> _filas = _cargar();

  Future<List<Map<String, dynamic>>> _cargar() async {
    final r = await conReintento(() => db.rpc('imperio_ranking_amigos'));
    return List<Map<String, dynamic>>.from(r as List);
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Emoji('🏆', tamano: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Rotulo(tr('Imperio entre amigos', 'Empire among friends'))),
                ],
              ),
              const SizedBox(height: 4),
              Text(tr('Tú y la gente que sigues, por mojonólares ganados en la partida.', 'You and the people you follow, by Poopbucks earned this game.'),
                  style: TextStyle(color: p.textoSuave, fontSize: 12)),
              const SizedBox(height: 10),
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _filas,
                  builder: (context, s) {
                    if (s.hasError) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(textoError(s.error!), style: TextStyle(color: p.textoSuave)),
                          TextButton(onPressed: () => setState(() => _filas = _cargar()), child: Text(tr('Reintentar', 'Retry'))),
                        ],
                      );
                    }
                    if (!s.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                    final filas = s.data!;
                    if (filas.length <= 1) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(tr('Sigue a alguien para competir con su Imperio.', 'Follow someone to compete with their Empire.'),
                            textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: filas.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) => _fila(context, i + 1, filas[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, int puesto, Map<String, dynamic> f) {
    final p = paleta(context);
    final yo = f['yo'] == true;
    final mj = (f['mj_total'] as num?)?.toDouble() ?? 0;
    final rollos = (f['rollos'] as num?)?.toInt() ?? 0;
    return InkWell(
      key: Key('ranking_imperio_$puesto'),
      onTap: yo ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: f['user_id']))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.tarjeta,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: yo ? acento : p.borde),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: puesto == 1
                  ? const Emoji('👑', tamano: 20)
                  : Text('$puesto', style: numeros(context, tamano: 14, weight: FontWeight.w900, color: p.textoSuave)),
            ),
            Avatar(f, tamano: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(yo ? tr('Tú', 'You') : '${f['username'] ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.texto, fontWeight: FontWeight.w700)),
            ),
            if (rollos > 0) ...[
              const Emoji('🧻', tamano: 16),
              Text(' ${formatoMj(rollos.toDouble(), ingles: enIngles)}  ', style: numeros(context, tamano: 12, color: p.textoSuave)),
            ],
            Text(formatoMj(mj, ingles: enIngles), style: numeros(context, tamano: 14, weight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
