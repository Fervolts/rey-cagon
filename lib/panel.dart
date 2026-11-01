import 'dart:async';

import 'package:flutter/material.dart';

import 'idioma.dart';
import 'main.dart' show db, textoError;
import 'tema.dart';

/// Panel de admin: actividad del Imperio y rendimiento de los push (RPC `panel_admin`).
/// Se refresca cada 10 s mientras está abierta. Solo admins: a los demás la RPC les responde error.
class PantallaPanel extends StatefulWidget {
  const PantallaPanel({super.key});

  @override
  State<PantallaPanel> createState() => _PantallaPanelState();
}

class _PantallaPanelState extends State<PantallaPanel> {
  Map<String, dynamic>? _datos;
  Object? _error;
  bool _cargando = false;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _cargar();
    _reloj = Timer.periodic(const Duration(seconds: 10), (_) => _cargar());
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (_cargando) return;
    _cargando = true;
    try {
      final r = await db.rpc('panel_admin', params: {'p_n': 50});
      // Sospechas de exploits (supabase/consultas/exploits.sql). Si falla, el panel sale igual.
      final sospechas = await db.rpc('panel_sospechas', params: {'p_n': 30}).catchError((_) => const []);
      if (mounted) {
        setState(() {
          _datos = {...Map<String, dynamic>.from(r as Map), 'sospechas': sospechas};
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _cargando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Panel', 'Dashboard'))),
      body: d == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(textoError(_error!), textAlign: TextAlign.center)),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(textoError(_error!), style: TextStyle(color: paleta(context).textoSuave)),
                    ),
                  Text(
                    (d['poceta_activo'] == true)
                        ? tr('Avisos de la poceta: ENCENDIDOS', 'Toilet alerts: ON')
                        : tr('Avisos de la poceta: apagados', 'Toilet alerts: off'),
                    style: numeros(context, tamano: 12, color: paleta(context).textoSuave),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Cifra(tr('Activos 24 h', 'Active 24 h'), d['dau_24h']),
                      _Cifra(tr('Eventos 24 h', 'Events 24 h'), d['eventos_24h']),
                      _Cifra(tr('Aperturas 24 h', 'Opens 24 h'), d['aperturas_24h']),
                      _Cifra(tr('Cagadas 24 h', 'Poops 24 h'), d['cagadas_24h']),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Rotulo(tr('Por hora (24 h)', 'Per hour (24 h)')),
                  const SizedBox(height: 6),
                  _PorHora(_lista(d['por_hora'])),
                  const SizedBox(height: 20),
                  Rotulo(tr('Top eventos (24 h)', 'Top events (24 h)')),
                  const SizedBox(height: 6),
                  _Tabla(
                    encabezado: [tr('Evento', 'Event'), 'N', tr('Usuarios', 'Users')],
                    filas: [for (final e in _lista(d['top_eventos'])) ['${e['evento']}', '${e['n']}', '${e['usuarios']}']],
                  ),
                  const SizedBox(height: 20),
                  Rotulo(tr('Push (7 días)', 'Push (7 days)')),
                  const SizedBox(height: 6),
                  _Tabla(
                    encabezado: [tr('Tipo', 'Type'), tr('Env', 'Sent'), tr('Toc', 'Tap'), tr('Abr', 'Open'), '%'],
                    filas: [
                      for (final p in _lista(d['push']))
                        [
                          [p['tipo'], p['subtipo'], p['variante']].where((x) => x != null).join(' · '),
                          '${p['enviados']}',
                          '${p['tocados']}',
                          '${p['abrio']}',
                          _porcentaje(p['tocados'], p['enviados']),
                        ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Rotulo(tr('Sospechas de trampa', 'Cheat suspicions')),
                  const SizedBox(height: 6),
                  _Tabla(
                    encabezado: [tr('Usuario', 'User'), tr('Tipo', 'Type'), tr('Cuándo', 'When')],
                    filas: [
                      for (final s in _lista(d['sospechas']))
                        ['${s['usuario'] ?? '?'}', '${s['tipo']}', _fecha(s['creado'])],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Rotulo(tr('En vivo', 'Live')),
                  const SizedBox(height: 6),
                  _Tabla(
                    encabezado: [tr('Hora', 'Time'), tr('Usuario', 'User'), tr('Evento', 'Event')],
                    filas: [
                      for (final v in _lista(d['vivo'])) [_hora(v['creado'], segundos: true), '${v['usuario'] ?? '?'}', '${v['evento']}'],
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

List<Map<String, dynamic>> _lista(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

String _hora(Object? iso, {bool segundos = false}) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  String dos(int n) => n.toString().padLeft(2, '0');
  return segundos ? '${dos(t.hour)}:${dos(t.minute)}:${dos(t.second)}' : '${dos(t.hour)}:00';
}

String _fecha(Object? iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(t.day)}/${dos(t.month)} ${dos(t.hour)}:${dos(t.minute)}';
}

String _porcentaje(Object? parte, Object? total) {
  final p = (parte as num?) ?? 0;
  final t = (total as num?) ?? 0;
  return t == 0 ? '-' : (p * 100 / t).toStringAsFixed(1);
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.titulo, this.valor);

  final String titulo;
  final Object? valor;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.tarjeta,
        border: Border.all(color: p.borde),
        borderRadius: BorderRadius.circular(radio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Rotulo(titulo),
          const SizedBox(height: 4),
          Text('${valor ?? 0}', style: numeros(context, tamano: 24, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Una fila por hora con barra proporcional a los eventos.
class _PorHora extends StatelessWidget {
  const _PorHora(this.horas);

  final List<Map<String, dynamic>> horas;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    if (horas.isEmpty) return Text(tr('Sin eventos', 'No events'), style: TextStyle(color: p.textoSuave));
    final maximo = horas.map((h) => (h['eventos'] as num?) ?? 0).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final h in horas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(width: 48, child: Text(_hora(h['hora']), style: numeros(context, tamano: 12, color: p.textoSuave))),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: maximo == 0 ? 0 : (((h['eventos'] as num?) ?? 0) / maximo).clamp(0.02, 1.0).toDouble(),
                      child: Container(height: 12, color: p.primario),
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text('${h['eventos']} · ${h['usuarios']}u', textAlign: TextAlign.right, style: numeros(context, tamano: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tabla simple con bordes de 1px. La primera columna se estira; las demás son números.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.encabezado, required this.filas});

  final List<String> encabezado;
  final List<List<String>> filas;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    if (filas.isEmpty) return Text(tr('Nada todavía', 'Nothing yet'), style: TextStyle(color: p.textoSuave));
    Widget celda(String t, int i, {bool titulo = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Text(
            t,
            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: titulo
                ? numeros(context, tamano: 11, weight: FontWeight.w700, color: p.textoSuave)
                : numeros(context, tamano: 12, weight: i == 0 ? FontWeight.w500 : FontWeight.w600),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Table(
        columnWidths: {0: const FlexColumnWidth(), for (var i = 1; i < encabezado.length; i++) i: const IntrinsicColumnWidth()},
        border: TableBorder(horizontalInside: BorderSide(color: p.borde)),
        children: [
          TableRow(
            decoration: BoxDecoration(color: p.suave),
            children: [for (var i = 0; i < encabezado.length; i++) celda(encabezado[i], i, titulo: true)],
          ),
          for (final f in filas) TableRow(children: [for (var i = 0; i < encabezado.length; i++) celda(i < f.length ? f[i] : '', i)]),
        ],
      ),
    );
  }
}
