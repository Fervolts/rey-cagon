import 'package:flutter/material.dart';

import 'main.dart' show db, escucharCagadas;
import 'tipos.dart';

const _meses = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// Mes de cagadas de un usuario. Solo el dueño puede borrar (RLS igual lo impide).
class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, List<Map<String, dynamic>>> _porDia = {};
  bool _loading = true;
  late final VoidCallback _soltar;

  bool get _esMio => widget.userId == db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _soltar = escucharCagadas('calendario', () => _load(spinner: false));
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _load({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) setState(() => _loading = true);
    try {
      final rows = await db
          .from('cagadas')
          .select('id, created_at, tipo')
          .eq('user_id', widget.userId)
          .gte('created_at', _mes.toUtc().toIso8601String())
          .lt('created_at', DateTime(_mes.year, _mes.month + 1).toUtc().toIso8601String())
          .order('created_at');
      final porDia = <int, List<Map<String, dynamic>>>{};
      for (final r in rows) {
        final dia = DateTime.parse(r['created_at']).toLocal().day;
        porDia.putIfAbsent(dia, () => []).add(r);
      }
      if (mounted) setState(() => _porDia = porDia);
    } catch (e) {
      _toast('Error cargando calendario: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _moverMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    _load();
  }

  Future<void> _borrar(int id) async {
    try {
      await db.from('cagadas').delete().eq('id', id);
      _toast('Borrada');
      await _load();
    } catch (e) {
      _toast('Error: $e');
    }
  }

  void _verDia(int dia) {
    final entradas = _porDia[dia] ?? [];
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('$dia de ${_meses[_mes.month - 1]}',
              style: Theme.of(context).textTheme.titleLarge),
          if (entradas.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nada este día 🫥'),
          ),
          for (final e in entradas)
            ListTile(
              leading: Text(tipoEmoji(e['tipo']), style: const TextStyle(fontSize: 24)),
              title: Text(TimeOfDay.fromDateTime(DateTime.parse(e['created_at']).toLocal())
                  .format(context)),
              subtitle: Text(tipos[e['tipo']]?.$2 ?? 'Sin tipo'),
              trailing: _esMio
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        Navigator.pop(context);
                        _borrar(e['id']);
                      },
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diasEnMes = DateTime(_mes.year, _mes.month + 1, 0).day;
    final huecos = _mes.weekday - 1; // semana empieza el lunes
    final hoy = DateTime.now();
    final total = _porDia.values.fold(0, (s, l) => s + l.length);
    final esteMes = _mes.year == hoy.year && _mes.month == hoy.month;

    return Scaffold(
      appBar: AppBar(title: Text(_esMio ? 'Mi calendario' : 'Calendario de ${widget.username}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _moverMes(-1)),
              Expanded(
                child: Text('${_meses[_mes.month - 1]} ${_mes.year}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: esteMes ? null : () => _moverMes(1),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                Expanded(child: Text(d, textAlign: TextAlign.center)),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < huecos; i++) const SizedBox(),
                for (var dia = 1; dia <= diasEnMes; dia++)
                  _Dia(
                    dia: dia,
                    cuantas: _porDia[dia]?.length ?? 0,
                    esHoy: esteMes && dia == hoy.day,
                    onTap: () => _verDia(dia),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Text('Total del mes: $total 💩', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Dia extends StatelessWidget {
  const _Dia({required this.dia, required this.cuantas, required this.esHoy, required this.onTap});

  final int dia;
  final int cuantas;
  final bool esHoy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cuantas > 0 ? scheme.primaryContainer : null,
          border: esHoy ? Border.all(color: scheme.primary, width: 2) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$dia', style: const TextStyle(fontSize: 12)),
            if (cuantas > 0) Text(cuantas == 1 ? '💩' : '💩$cuantas', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
