// Ranking del Imperio: amigos (tú y la gente que sigues) o global, por MJ ganados en la partida o por Rollos de Oro
// (RPC `imperio_ranking`). Si el servidor todavía no la tiene, cae a `imperio_ranking_amigos` (solo amigos).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../accesorios.dart' show Avatar;
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
  String _alcance = 'amigos';
  String _orden = 'mj';

  /// El servidor no tiene imperio_ranking: solo amigos, y el orden por rollos se hace aquí.
  bool _viejo = false;
  late Future<List<FilaRankingImperio>> _filas = _cargar();

  Future<List<FilaRankingImperio>> _cargar() async {
    if (!_viejo) {
      try {
        final r = await conReintento(() => db.rpc('imperio_ranking', params: {'p_alcance': _alcance, 'p_orden': _orden}));
        return filasRanking(r);
      } catch (e) {
        if (!faltaFuncion(e)) rethrow;
        _viejo = true;
        _alcance = 'amigos';
        if (mounted) setState(() {});
      }
    }
    final r = await conReintento(() => db.rpc('imperio_ranking_amigos'));
    return filasRanking(r, ordenLocal: _orden);
  }

  void _recargar() => setState(() => _filas = _cargar());

  Future<void> _refrescar() async {
    final f = _cargar();
    setState(() => _filas = f);
    await f.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final global = _alcance == 'global' && !_viejo;
    final porRollos = _orden == 'rollos';
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
                  Expanded(child: Rotulo(global ? tr('Imperio global', 'Global Empire') : tr('Imperio entre amigos', 'Empire among friends'))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                switch ((global, porRollos)) {
                  (false, false) => tr('Tú y la gente que sigues, por mojonólares ganados en la partida.',
                      'You and the people you follow, by Poopbucks earned this game.'),
                  (false, true) => tr('Tú y la gente que sigues, por Rollos de Oro ganados.', 'You and the people you follow, by Golden Rolls earned.'),
                  (true, false) => tr('Los 100 mejores Imperios, por mojonólares ganados en la partida.',
                      'The top 100 Empires, by Poopbucks earned this game.'),
                  (true, true) => tr('Los 100 mejores Imperios, por Rollos de Oro ganados.', 'The top 100 Empires, by Golden Rolls earned.'),
                },
                style: TextStyle(color: p.textoSuave, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (!_viejo) ...[
                    _chip('ranking_imperio_amigos', tr('AMIGOS', 'FRIENDS'), _alcance == 'amigos', () => _alcance = 'amigos'),
                    _chip('ranking_imperio_global', tr('GLOBAL', 'GLOBAL'), _alcance == 'global', () => _alcance = 'global'),
                    const SizedBox(width: 10),
                  ],
                  _chip('ranking_imperio_por_mj', 'MJ', !porRollos, () => _orden = 'mj'),
                  _chip('ranking_imperio_por_rollos', tr('ROLLOS', 'ROLLS'), porRollos, () => _orden = 'rollos'),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: FutureBuilder<List<FilaRankingImperio>>(
                  future: _filas,
                  builder: (context, s) {
                    if (s.hasError) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(textoError(s.error!), style: TextStyle(color: p.textoSuave)),
                          TextButton(onPressed: _recargar, child: Text(tr('Reintentar', 'Retry'))),
                        ],
                      );
                    }
                    if (!s.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                    final filas = s.data!;
                    final vacio = filas.where((f) => !f.yo).isEmpty;
                    return RefreshIndicator(
                      onRefresh: _refrescar,
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: vacio ? 1 : filas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          if (!vacio) return _fila(context, filas[i], porRollos);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                                global
                                    ? tr('Todavía nadie ha ganado mojonólares en esta partida.', 'Nobody has earned Poopbucks this game yet.')
                                    : tr('Sigue a alguien para competir con su Imperio.', 'Follow someone to compete with their Empire.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: p.textoSuave)),
                          );
                        },
                      ),
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
      onTap: f.yo || f.userId == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: f.userId!))),
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
            if (porRollos) ...[mj, const SizedBox(width: 10), rollos] else ...[if (f.rollos > 0) ...[rollos, const SizedBox(width: 10)], mj],
          ],
        ),
      ),
    );
  }
}
