import 'package:flutter/material.dart';

import 'emoji.dart';
import 'idioma.dart';
import 'peso.dart';
import 'main.dart' show conReintento, db, escucharCagadas, esDeRed, textoError;
import 'tema.dart';
import 'tipos.dart';

List<String> get meses => enIngles
    ? [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ]
    : [
        'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
        'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
      ];

/// Mes de cagadas de un usuario. Solo el dueño puede borrar (RLS igual lo impide).
class PantallaCalendario extends StatefulWidget {
  const PantallaCalendario({super.key, required this.usuarioId, required this.nombre});

  final String usuarioId;
  final String nombre;

  @override
  State<PantallaCalendario> createState() => _PantallaCalendarioState();
}

class _PantallaCalendarioState extends State<PantallaCalendario> {
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, List<Map<String, dynamic>>> _porDia = {};
  bool _cargando = true;
  late final VoidCallback _soltar;

  bool get _esMio => widget.usuarioId == db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _cargar();
    _soltar = escucharCagadas('calendario', () => _cargar(spinner: false));
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _cargar({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) setState(() => _cargando = true);
    try {
      final rows = await conReintento(() => db
          .from('cagadas')
          .select('id, created_at, tipo, peso')
          .eq('user_id', widget.usuarioId)
          .gte('created_at', _mes.toUtc().toIso8601String())
          .lt('created_at', DateTime(_mes.year, _mes.month + 1).toUtc().toIso8601String())
          .order('created_at'));
      final porDia = <int, List<Map<String, dynamic>>>{};
      for (final r in rows) {
        final dia = DateTime.parse(r['created_at']).toLocal().day;
        porDia.putIfAbsent(dia, () => []).add(r);
      }
      if (mounted) setState(() => _porDia = porDia);
    } catch (e) {
      if (spinner || !esDeRed(e)) _mensaje(textoError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mensaje(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  void _moverMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    _cargar();
  }

  Future<void> _borrar(int id) async {
    try {
      await db.from('cagadas').delete().eq('id', id);
      _mensaje(tr('Borrada', 'Deleted'));
      await _cargar();
    } catch (e) {
      _mensaje(textoError(e));
    }
  }

  void _verDia(int dia) {
    final entradas = _porDia[dia] ?? [];
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: conBordeAbajo(context, const EdgeInsets.all(16)),
        children: [
          Text(enIngles ? '${meses[_mes.month - 1]} $dia' : '$dia de ${meses[_mes.month - 1]}',
              style: Theme.of(context).textTheme.titleLarge),
          if (entradas.isEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(tr('Nada este día 🫥', 'Nothing this day 🫥')),
          ),
          for (final e in entradas)
            ListTile(
              leading: Emoji(tipoEmoji(e['tipo']), tamano: 32),
              title: Text(TimeOfDay.fromDateTime(DateTime.parse(e['created_at']).toLocal())
                  .format(context)),
              subtitle: Text((tipos[e['tipo']]?.$2 ?? tr('Sin tipo', 'No type')) +
                  (pesos[e['peso']] == null ? '' : ' · ${pesos[e['peso']]!.$1} ${pesos[e['peso']]!.$2}')),
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
      appBar: AppBar(title: Text(_esMio ? tr('MI CALENDARIO', 'MY CALENDAR') : tr('CALENDARIO DE ${widget.nombre.toUpperCase()}', "${widget.nombre.toUpperCase()}'S CALENDAR"))),
      body: ListView(
        padding: conBordeAbajo(context, const EdgeInsets.all(16)),
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _moverMes(-1)),
              Expanded(
                child: Text('${meses[_mes.month - 1]} ${_mes.year}'.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: numeros(context, tamano: 15, weight: FontWeight.w800).copyWith(letterSpacing: 1.2)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: esteMes ? null : () => _moverMes(1),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in (enIngles ? ['M', 'T', 'W', 'T', 'F', 'S', 'S'] : ['L', 'M', 'M', 'J', 'V', 'S', 'D']))
                Expanded(child: Center(child: Rotulo(d))),
            ],
          ),
          const SizedBox(height: 4),
          if (_cargando)
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
          Text(tr('TOTAL DEL MES: ${total.toString().padLeft(2, '0')}', 'MONTH TOTAL: ${total.toString().padLeft(2, '0')}'),
              textAlign: TextAlign.center, style: numeros(context, tamano: 13, weight: FontWeight.w700)),
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
          border: esHoy
              ? Border.all(color: scheme.primary, width: 2)
              : Border.all(color: paleta(context).borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$dia', style: numeros(context, tamano: 12, color: cuantas > 0 ? acentoTexto : null)),
            if (cuantas > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Emoji('💩', tamano: 14),
                  if (cuantas > 1) Text('$cuantas', style: numeros(context, tamano: 11, color: acentoTexto)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
