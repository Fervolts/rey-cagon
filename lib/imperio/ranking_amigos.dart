// Ranking del Imperio: amigos (tú y la gente que sigues) o global, por MJ ganados en la partida o por Rollos de Oro
// (RPC `imperio_ranking`). Si el servidor todavía no la tiene, cae a `imperio_ranking_amigos` (solo amigos).
// Vive en la pestaña RANKING (selector CAGADAS / IMPERIO); el botón 🏆 del Imperio lleva ahí con [verRankingImperio].
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../accesorios.dart' show Avatar;
import '../avisos.dart' show ir;
import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show conReintento, db, textoError;
import '../perfil.dart' show PantallaPerfil;
import '../tema.dart';
import 'formato.dart';

/// Una fila del ranking ya leída. [mapa] es la fila tal cual llegó (Avatar saca de ahí accesorios y movimiento).
class FilaRankingImperio {
  const FilaRankingImperio({
    required this.mapa,
    required this.userId,
    required this.nombre,
    required this.yo,
    required this.mj,
    required this.rollos,
    required this.jaladas,
    required this.puesto,
    this.movimiento,
  });

  final Map<String, dynamic> mapa;
  final String? userId;
  final String nombre;
  final bool yo;
  final double mj;
  final int rollos;
  final int jaladas;
  final int puesto;
  final String? movimiento;

  /// Lee la fila [f]. Si no trae `puesto` (la RPC vieja), usa [puestoSiFalta].
  factory FilaRankingImperio.desde(Map<String, dynamic> f, {required int puestoSiFalta}) {
    return FilaRankingImperio(
      mapa: f,
      userId: f['user_id'] as String?,
      nombre: '${f['username'] ?? ''}',
      yo: f['yo'] == true,
      mj: (f['mj_total'] as num?)?.toDouble() ?? 0,
      rollos: (f['rollos'] as num?)?.toInt() ?? 0,
      jaladas: (f['jaladas'] as num?)?.toInt() ?? 0,
      puesto: (f['puesto'] as num?)?.toInt() ?? puestoSiFalta,
      movimiento: f['movimiento'] as String?,
    );
  }
}

/// Convierte la respuesta de la RPC en filas. Con [ordenLocal] = 'rollos' reordena aquí (la RPC vieja solo ordena
/// por MJ) y renumera los puestos.
List<FilaRankingImperio> filasRanking(Object? respuesta, {String? ordenLocal}) {
  final crudas = respuesta is List ? respuesta.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : <Map<String, dynamic>>[];
  if (ordenLocal == 'rollos') {
    double mj(Map<String, dynamic> f) => (f['mj_total'] as num?)?.toDouble() ?? 0;
    int rl(Map<String, dynamic> f) => (f['rollos'] as num?)?.toInt() ?? 0;
    crudas.sort((a, b) {
      final r = rl(b).compareTo(rl(a));
      return r != 0 ? r : mj(b).compareTo(mj(a));
    });
    return [for (var i = 0; i < crudas.length; i++) FilaRankingImperio.desde({...crudas[i]}..remove('puesto'), puestoSiFalta: i + 1)];
  }
  return [for (var i = 0; i < crudas.length; i++) FilaRankingImperio.desde(crudas[i], puestoSiFalta: i + 1)];
}

/// True si el error dice que la función no existe en el servidor (migración sin aplicar).
bool faltaFuncion(Object e) => e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883');

/// true = la pestaña RANKING muestra el Imperio en vez de las cagadas.
final rankingImperio = ValueNotifier<bool>(false);

/// Lleva a la pestaña RANKING con el Imperio a la vista.
void verRankingImperio() {
  rankingImperio.value = true;
  ir('ranking');
}

/// El ranking del Imperio dentro de la lista de la pestaña RANKING. [soloAmigos] sale del selector de la pantalla
/// (SOLO MIS AMIGOS / TODOS); el orden MJ / ROLLOS es suyo. Cambiar [vuelta] lo vuelve a pedir (deslizar para refrescar).
class RankingImperio extends StatefulWidget {
  const RankingImperio({super.key, required this.soloAmigos, this.vuelta = 0, this.alTocar});

  final bool soloAmigos;
  final int vuelta;

  /// Tocar a otro: abre su perfil. Si es null, lo abre aquí.
  final void Function(String userId)? alTocar;

  @override
  State<RankingImperio> createState() => _RankingImperioState();
}

class _RankingImperioState extends State<RankingImperio> {
  String _orden = 'mj';

  /// El servidor no tiene imperio_ranking: solo amigos, y el orden por rollos se hace aquí.
  bool _viejo = false;
  late Future<List<FilaRankingImperio>> _filas = _cargar();

  String get _alcance => widget.soloAmigos || _viejo ? 'amigos' : 'global';

  Future<List<FilaRankingImperio>> _cargar() async {
    if (!_viejo) {
      try {
        final r = await conReintento(() => db.rpc('imperio_ranking', params: {'p_alcance': _alcance, 'p_orden': _orden}));
        return filasRanking(r);
      } catch (e) {
        if (!faltaFuncion(e)) rethrow;
        _viejo = true;
        if (mounted) setState(() {});
      }
    }
    final r = await conReintento(() => db.rpc('imperio_ranking_amigos'));
    return filasRanking(r, ordenLocal: _orden);
  }

  void _recargar() => setState(() => _filas = _cargar());

  @override
  void didUpdateWidget(RankingImperio viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.soloAmigos != widget.soloAmigos || viejo.vuelta != widget.vuelta) _filas = _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final global = _alcance == 'global';
    final porRollos = _orden == 'rollos';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _chip('ranking_imperio_por_mj', tr('POR MJ', 'BY PB'), !porRollos, () => _orden = 'mj'),
            const SizedBox(width: 8),
            _chip('ranking_imperio_por_rollos', tr('POR ROLLOS', 'BY ROLLS'), porRollos, () => _orden = 'rollos'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          switch ((global, porRollos)) {
            (false, false) => tr('Tú y la gente que sigues, por mojonólares ganados en la partida.', 'You and the people you follow, by Poopbucks earned this game.'),
            (false, true) => tr('Tú y la gente que sigues, por Rollos de Oro ganados.', 'You and the people you follow, by Golden Rolls earned.'),
            (true, false) => tr('Los 100 mejores Imperios, por mojonólares ganados en la partida.', 'The top 100 Empires, by Poopbucks earned this game.'),
            (true, true) => tr('Los 100 mejores Imperios, por Rollos de Oro ganados.', 'The top 100 Empires, by Golden Rolls earned.'),
          },
          style: TextStyle(color: p.textoSuave, fontSize: 12),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<FilaRankingImperio>>(
          future: _filas,
          builder: (context, s) {
            if (s.hasError) {
              return Column(
                children: [
                  Text(textoError(s.error!), style: TextStyle(color: p.textoSuave)),
                  TextButton(onPressed: _recargar, child: Text(tr('Reintentar', 'Retry'))),
                ],
              );
            }
            if (!s.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            final filas = s.data!;
            if (filas.where((f) => !f.yo).isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    global
                        ? tr('Todavía nadie ha ganado mojonólares en esta partida.', 'Nobody has earned Poopbucks this game yet.')
                        : tr('Sigue a alguien para competir con su Imperio.', 'Follow someone to compete with their Empire.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textoSuave)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < filas.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _fila(context, filas[i], porRollos),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _chip(String clave, String texto, bool sel, VoidCallback poner) {
    return ChoiceChip(
      key: Key(clave),
      label: Text(texto),
      labelStyle: TextStyle(color: sel ? acentoTexto : null, fontWeight: FontWeight.w800, letterSpacing: 1),
      selected: sel,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        if (sel) return;
        poner();
        _recargar();
      },
    );
  }

  Widget _fila(BuildContext context, FilaRankingImperio f, bool porRollos) {
    final p = paleta(context);
    // El número por el que se ordena va grande; el otro, chico y suave.
    TextStyle estilo(bool principal) => numeros(context, tamano: principal ? 14 : 12, weight: principal ? FontWeight.w900 : FontWeight.w600,
        color: principal ? null : p.textoSuave);
    final mj = Text(formatoMj(f.mj, ingles: enIngles), style: estilo(!porRollos));
    final rollos = Row(mainAxisSize: MainAxisSize.min, children: [
      const Emoji('🧻', tamano: 16),
      Text(' ${formatoCantidad(f.rollos, ingles: enIngles)}', style: estilo(porRollos)),
    ]);
    return InkWell(
      key: Key('ranking_imperio_${f.puesto}'),
      onTap: f.yo || f.userId == null
          ? null
          : () => widget.alTocar != null
              ? widget.alTocar!(f.userId!)
              : Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: f.userId!))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.tarjeta,
          borderRadius: BorderRadius.circular(radio),
          border: Border.all(color: f.yo ? acento : p.borde),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: f.puesto == 1
                  ? const Emoji('👑', tamano: 20)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${f.puesto}', style: numeros(context, tamano: 14, weight: FontWeight.w900, color: p.textoSuave)),
                    ),
            ),
            Avatar(f.mapa, tamano: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(f.yo ? tr('Tú', 'You') : f.nombre,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.texto, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            // Lo que ordena arriba y grande, lo otro debajo: en una sola línea se montaban con nombres largos.
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: porRollos ? [rollos, mj] : [mj, if (f.rollos > 0) rollos],
            ),
          ],
        ),
      ),
    );
  }
}
