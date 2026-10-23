import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show db, escucharCagadas;
import 'tema.dart';

// El Cagadón: reto 1 vs 1 entre amigos. Gana el que cague más hoy (hora de Venezuela);
// en empate, el que llegó primero a ese número. El servidor lo cierra a las 00:05.

const _columnasPerfil =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

String _hoyCaracas() => DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String().substring(0, 10);

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

/// Botón del perfil de un amigo.
Future<void> retar(BuildContext context, String uid, String nombre) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('⚔️ Cagadón', '⚔️ Poop-Off')),
      content: Text(tr(
          '¿Retas a $nombre? Gana el que cague más hoy, hasta las 11:59 p. m. '
              'Si empatan, gana el que llegó primero.',
          'Challenge $nombre? Whoever poops more today wins, until 11:59 p.m. '
              'If you tie, whoever got there first wins.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('RETAR', 'CHALLENGE'))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await db.from('retos').insert({'retado': uid});
    if (context.mounted) _aviso(context, tr('Reto enviado a $nombre ⚔️', 'Challenge sent to $nombre ⚔️'));
  } on PostgrestException catch (e) {
    if (context.mounted) _aviso(context, trServidor(e.message));
  }
}

Future<int> victorias(String uid) async => ((await db.rpc('victorias', params: {'uid': uid})) as num?)?.toInt() ?? 0;

/// Los retos de hoy en la pantalla de inicio: invitaciones, esperas y marcadores en vivo.
class RetosDeHoy extends StatefulWidget {
  const RetosDeHoy({super.key});

  @override
  State<RetosDeHoy> createState() => _RetosDeHoyState();
}

class _RetosDeHoyState extends State<RetosDeHoy> {
  late final Stream<List<Map<String, dynamic>>> _retos =
      db.from('retos').stream(primaryKey: ['id']).eq('dia', _hoyCaracas());

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _retos,
        builder: (context, snap) {
          final vivos = (snap.data ?? []).where((r) => r['estado'] == 'pendiente' || r['estado'] == 'aceptado').toList();
          if (vivos.isEmpty) return const SizedBox.shrink();
          return Column(children: [
            for (final r in vivos)
              Padding(
                key: ValueKey(r['id']),
                padding: const EdgeInsets.only(bottom: 10),
                child: r['estado'] == 'aceptado' ? TarjetaReto(id: r['id'] as int) : _Invitacion(r),
              ),
          ]);
        },
      );
}

class _Invitacion extends StatefulWidget {
  const _Invitacion(this.reto);

  final Map<String, dynamic> reto;

  @override
  State<_Invitacion> createState() => _InvitacionState();
}

class _InvitacionState extends State<_Invitacion> {
  Map<String, dynamic>? _otro;
  bool _ocupado = false;

  bool get _meRetaron => widget.reto['retado'] == db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    final otro = _meRetaron ? widget.reto['retador'] : widget.reto['retado'];
    db.from('profiles').select(_columnasPerfil).eq('id', otro).maybeSingle().then((p) {
      if (mounted) setState(() => _otro = p);
    });
  }

  Future<void> _responder(String accion) async {
    setState(() => _ocupado = true);
    try {
      await db.rpc('responder_reto', params: {'rid': widget.reto['id'], 'accion': accion});
      if (mounted && accion == 'aceptar') _aviso(context, tr('¡Que empiece el Cagadón! 💩', 'Let the Poop-Off begin! 💩'));
    } on PostgrestException catch (e) {
      if (mounted) _aviso(context, trServidor(e.message));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final nombre = _otro?['username'] ?? '…';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (_otro != null) Avatar(_otro!, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _meRetaron
                  ? tr('⚔️ $nombre te retó a un Cagadón', '⚔️ $nombre challenged you to a Poop-Off')
                  : tr('⏳ Esperando a que $nombre acepte tu Cagadón', '⏳ Waiting for $nombre to accept your Poop-Off'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('Gana el que cague más hoy.', 'Whoever poops more today wins.'), style: TextStyle(color: p.textoSuave, fontSize: 13)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_meRetaron) ...[
            TextButton(onPressed: _ocupado ? null : () => _responder('rechazar'), child: Text(tr('RAJARSE 🐔', 'CHICKEN OUT 🐔'))),
            const SizedBox(width: 6),
            FilledButton(onPressed: _ocupado ? null : () => _responder('aceptar'), child: Text(tr('ACEPTAR', 'ACCEPT'))),
          ] else
            TextButton(onPressed: _ocupado ? null : () => _responder('cancelar'), child: Text(tr('CANCELAR', 'CANCEL'))),
        ]),
      ]),
    );
  }
}

/// Marcador de un Cagadón aceptado o terminado. Sirve en inicio y en el chat; se refresca solo.
class TarjetaReto extends StatefulWidget {
  const TarjetaReto({super.key, required this.id, this.compacta = false});

  final int id;
  final bool compacta;

  @override
  State<TarjetaReto> createState() => _TarjetaRetoState();
}

class _TarjetaRetoState extends State<TarjetaReto> {
  Map<String, dynamic>? _r;
  Map<String, Map<String, dynamic>> _perfiles = {};
  late final VoidCallback _soltar;

  @override
  void initState() {
    super.initState();
    _cargar();
    _soltar = escucharCagadas('reto-${widget.id}', _cargar);
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final filas = await db.rpc('reto_publico', params: {'rid': widget.id}) as List;
      if (filas.isEmpty) return;
      final r = filas.first as Map<String, dynamic>;
      if (_perfiles.isEmpty) {
        final ps = await db.from('profiles').select(_columnasPerfil).inFilter('id', [r['retador'], r['retado']]);
        _perfiles = {for (final p in ps) p['id'] as String: p};
      }
      if (mounted) setState(() => _r = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final r = _r;
    if (r == null) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
    final fin = r['estado'] == 'terminado';
    final a = r['a'] as int, b = r['b'] as int;
    final ganador = r['ganador'];
    Widget lado(String uid, int n, bool lider) {
      final perfil = _perfiles[uid];
      return Expanded(
        child: Column(children: [
          if (perfil != null) Avatar(perfil, tamano: widget.compacta ? 30 : 40),
          const SizedBox(height: 4),
          Text(perfil?['username'] ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('$n', style: numeros(context, tamano: widget.compacta ? 26 : 34, weight: FontWeight.w900, color: lider ? null : p.textoSuave)),
          if (fin && ganador == uid) const Emoji('👑', tamano: 22),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: Column(children: [
        Text(fin ? (ganador == null ? tr('🤝 CAGADÓN EMPATADO', '🤝 POOP-OFF TIED') : tr('🏆 CAGADÓN TERMINADO', '🏆 POOP-OFF OVER')) : tr('⚔️ CAGADÓN EN VIVO · HOY', '⚔️ POOP-OFF LIVE · TODAY'),
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          lado(r['retador'], a, a >= b),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: p.textoSuave)),
          ),
          lado(r['retado'], b, b >= a),
        ]),
        if (!fin)
          Text(a == b ? tr('Empatados. En empate gana el que llegó primero.', 'Tied. In a tie, whoever got there first wins.') : tr('Hasta las 11:59 p. m.', 'Until 11:59 p.m.'),
              style: TextStyle(color: p.textoSuave, fontSize: 12)),
      ]),
    );
  }
}
