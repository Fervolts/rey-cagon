import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'imperio/apuesta_local.dart';
import 'imperio/formato.dart';
import 'main.dart' show conReintento, db, escucharCagadas, textoError;
import 'tema.dart';

// El Cagadón: reto 1 vs 1 entre amigos. Gana el que cague más hoy (hora de Venezuela);
// en empate, el que llegó primero a ese número. El servidor lo cierra a las 00:05.

const _columnasPerfil =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

String _hoyCaracas() => DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String().substring(0, 10);

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

String _mj(double v) => formatoMj(v, ingles: enIngles);

/// Minutos sin decimales si son enteros (30), con uno si no (7.5).
String _minutos(double m) => m == m.roundToDouble() ? m.toInt().toString() : m.toStringAsFixed(1);

String _avisoApuesta(int min, double mj) => tr('Apostaste $min min de producción (${_mj(mj)} MJ)', 'You bet $min min of production (${_mj(mj)} MJ)');

/// Botón del perfil de un amigo. Si el Imperio está encendido y ya lo abrió, deja elegir una apuesta.
Future<void> retar(BuildContext context, String uid, String nombre) async {
  final res = await resumenApuesta();
  if (!context.mounted) return;
  final opciones = res?.opciones ?? const [0];
  var min = 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, poner) => AlertDialog(
        title: TextoConEmojis(tr('⚔️ Cagadón', '⚔️ Poop-Off')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(
              '¿Retas a $nombre? Gana el que cague más hoy, hasta las 11:59 p. m. '
                  'Si empatan, gana el que llegó primero.',
              'Challenge $nombre? Whoever poops more today wins, until 11:59 p.m. '
                  'If you tie, whoever got there first wins.')),
          if (res != null && opciones.length > 1) ...[
            const SizedBox(height: 14),
            TextoConEmojis(tr('💰 Apuesta en minutos de tu producción', '💰 Bet in minutes of your production'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in opciones)
                _ChipApuesta(
                  titulo: m == 0 ? tr('Sin apuesta', 'No bet') : '$m min',
                  detalle: m == 0 ? null : '${_mj(res.cuenta(m).mj)} MJ',
                  elegido: m == min,
                  alTocar: () => poner(() => min = m),
                ),
            ]),
            if (min > 0) ...[
              const SizedBox(height: 8),
              Text(
                res.cuenta(min).fraccion < 1
                    ? tr('No te alcanza el saldo: pagas lo que tienes y el premio baja en proporción.',
                        'Not enough balance: you pay what you have and the prize shrinks to match.')
                    : tr('Pagas ahora. Si ganas cobras el doble; si empatan o no acepta, lo recuperas.',
                        'You pay now. Win and you collect double; tie or no accept and you get it back.'),
                style: TextStyle(color: paleta(context).textoSuave, fontSize: 12),
              ),
            ],
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(min > 0 ? tr('RETAR Y APOSTAR', 'CHALLENGE AND BET') : tr('RETAR', 'CHALLENGE'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final cuenta = min > 0 && res != null ? res.cuenta(min) : null;
  try {
    final fila = await db
        .from('retos')
        .insert({'retado': uid, if (cuenta != null) ...{'apuesta_min': min, 'pago_retador': cuenta.fraccion}})
        .select('id')
        .single();
    if (cuenta != null) {
      await pagarApuesta(reto: (fila['id'] as num).toInt(), min: min, fraccion: cuenta.fraccion, rol: 'reta');
      if (context.mounted) _aviso(context, '${tr('Reto enviado a $nombre.', 'Challenge sent to $nombre.')} ${_avisoApuesta(min, cuenta.mj)}');
    } else if (context.mounted) {
      _aviso(context, tr('Reto enviado a $nombre ⚔️', 'Challenge sent to $nombre ⚔️'));
    }
  } on PostgrestException catch (e) {
    if (context.mounted) _aviso(context, trServidor(e.message));
  }
}

/// Opción cuadrada del selector de apuesta.
class _ChipApuesta extends StatelessWidget {
  const _ChipApuesta({required this.titulo, required this.detalle, required this.elegido, required this.alTocar});

  final String titulo;
  final String? detalle;
  final bool elegido;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final color = elegido ? acentoTexto : p.texto;
    return InkWell(
      onTap: alTocar,
      borderRadius: BorderRadius.circular(radio),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: elegido ? acento : null,
          border: Border.all(color: elegido ? acento : p.bordeFuerte),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          if (detalle != null) Text(detalle!, style: numeros(context, tamano: 11, color: color)),
        ]),
      ),
    );
  }
}

Future<int> victorias(String uid) async => ((await db.rpc('victorias', params: {'uid': uid})) as num?)?.toInt() ?? 0;

/// Los retos de hoy en la pantalla de inicio: invitaciones, esperas y marcadores en vivo.
class RetosDeHoy extends StatefulWidget {
  const RetosDeHoy({super.key});

  @override
  State<RetosDeHoy> createState() => _RetosDeHoyState();
}

var _canalesRetos = 0;

class _RetosDeHoyState extends State<RetosDeHoy> {
  /// Los retos de hoy. Antes salían de .stream(), que tras un corte de red se quedaba congelado:
  /// ahora se consultan y se vuelven a consultar cuando realtime avisa, cuando el canal se reconecta
  /// y al volver a la app. El día se recalcula en cada consulta (la app puede quedar abierta de un día a otro).
  List<Map<String, dynamic>>? _hoy;
  late final RealtimeChannel _canal;
  late final AppLifecycleListener _ciclo;
  Timer? _espera;
  var _cortado = false;

  /// Apuestas con algo por cobrar o recuperar (de hoy o de días pasados) y el nombre del otro.
  List<Map<String, dynamic>> _porCobrar = [];
  Map<String, String> _nombres = {};
  String _estados = '';

  @override
  void initState() {
    super.initState();
    _canal = db
        .channel('retos-hoy-${_canalesRetos++}')
        // Sin filtro por día: el día cambia y los borrados no se pueden filtrar; la base solo manda los míos.
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'retos', callback: (_) => _avisar())
        .subscribe((estado, [_]) {
          if (estado != RealtimeSubscribeStatus.subscribed) {
            _cortado = true;
          } else if (_cortado) {
            _cortado = false;
            _avisar();
          }
        });
    _ciclo = AppLifecycleListener(onResume: _avisar);
    _pedirRetos();
    _cargarPorCobrar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _ciclo.dispose();
    db.removeChannel(_canal);
    super.dispose();
  }

  void _avisar() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 300), _pedirRetos);
  }

  Future<void> _pedirRetos() async {
    try {
      final hoy = await conReintento(() => db.from('retos').select().eq('dia', _hoyCaracas()).order('id'));
      if (!mounted) return;
      // Un reto de hoy cambió de estado (rechazado, cancelado, aceptado): puede haber algo nuevo que recuperar.
      final estados = [for (final r in hoy) '${r['id']}:${r['estado']}'].join(',');
      final antes = _estados;
      _estados = estados;
      setState(() => _hoy = hoy);
      if (antes.isNotEmpty && estados != antes) _cargarPorCobrar();
    } catch (_) {
      // Sin red: queda lo que ya se veía; el próximo aviso o la vuelta a la app lo pone al día.
    }
  }

  Future<void> _cargarPorCobrar() async {
    try {
      final pendientes = await conReintento(() => db.rpc('reto_apuesta_pendientes'));
      final filas = [for (final f in pendientes as List) Map<String, dynamic>.from(f as Map)];
      final faltan = {for (final f in filas) f['otro'] as String}.difference(_nombres.keys.toSet());
      if (faltan.isNotEmpty) {
        final ps = await conReintento(() => db.from('profiles').select('id, username').inFilter('id', faltan.toList()));
        _nombres = {..._nombres, for (final p in ps) p['id'] as String: (p['username'] ?? '') as String};
      }
      if (mounted) setState(() => _porCobrar = filas);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) {
          final hoy = _hoy ?? [];
          final vivos = hoy.where((r) => r['estado'] == 'pendiente' || r['estado'] == 'aceptado').toList();
          final ids = {for (final r in vivos) r['id']};
          final cobros = _porCobrar.where((f) => !ids.contains(f['id'])).toList();
          if (vivos.isEmpty && cobros.isEmpty) return const SizedBox.shrink();
          return Column(children: [
            for (final f in cobros)
              Padding(
                key: ValueKey('cobro-${f['id']}'),
                padding: const EdgeInsets.only(bottom: 10),
                child: _CobroPendiente(f, nombre: _nombres[f['otro']] ?? '…', alCobrar: _cargarPorCobrar),
              ),
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

/// Una apuesta ya resuelta que falta cobrar (ganada) o recuperar (empate, rechazo, cancelación o anulada).
class _CobroPendiente extends StatelessWidget {
  const _CobroPendiente(this.fila, {required this.nombre, required this.alCobrar});

  final Map<String, dynamic> fila;
  final String nombre;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final gana = fila['resultado'] == 'gana';
    final apuesta = (fila['apuesta'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
      child: Row(children: [
        Expanded(
          child: TextoConEmojis(
            gana
                ? tr('💰 Le ganaste a $nombre la apuesta de $apuesta min', '💰 You beat $nombre on the $apuesta min bet')
                : tr('💰 Recupera tu apuesta de $apuesta min del reto con $nombre', '💰 Get back your $apuesta min bet from the challenge with $nombre'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        _BotonCobrar(reto: (fila['id'] as num).toInt(), gana: gana, minutos: (fila['minutos'] as num?)?.toDouble() ?? 0, alCobrar: alCobrar),
      ]),
    );
  }
}

/// COBRAR o RECUPERAR. Late suave para que se note; con "Simples" da un solo brinco y con "Apagadas" se queda quieto.
class _BotonCobrar extends StatefulWidget {
  const _BotonCobrar({required this.reto, required this.gana, required this.minutos, required this.alCobrar});

  final int reto;
  final bool gana;
  final double minutos;
  final VoidCallback alCobrar;

  @override
  State<_BotonCobrar> createState() => _BotonCobrarState();
}

class _BotonCobrarState extends State<_BotonCobrar> with SingleTickerProviderStateMixin {
  late final _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final _escala = Tween(begin: 1.0, end: 1.07).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut));
  Movimiento? _nivel;
  bool _ocupado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = movimiento(context);
    if (m == _nivel) return;
    _nivel = m;
    switch (m) {
      case Movimiento.completo:
        _pulso.repeat(reverse: true);
      case Movimiento.simple:
        _pulso.forward(from: 0).then((_) {
          if (mounted) _pulso.reverse();
        });
      case Movimiento.nada:
        _pulso.value = 0;
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  Future<void> _cobrar() async {
    setState(() => _ocupado = true);
    _pulso.stop();
    try {
      final r = await cobrarApuesta(widget.reto);
      if (!mounted) return;
      final min = _minutos(r.minutos);
      final mj = r.mj == null ? '' : ' (${_mj(r.mj!)} MJ)';
      _aviso(
        context,
        r.minutos <= 0
            ? tr('No había nada que cobrar en esa apuesta.', 'There was nothing to collect on that bet.')
            : r.resultado == 'gana'
                ? tr('Cobraste $min min de producción$mj. Se suman en tu Imperio.', 'You collected $min min of production$mj. It goes to your Empire.')
                : tr('Recuperaste $min min de producción$mj.', 'You got back $min min of production$mj.'),
      );
    } on PostgrestException catch (e) {
      if (mounted) _aviso(context, trServidor(e.message));
    } catch (_) {
      if (mounted) _aviso(context, tr('No se pudo cobrar. Intenta otra vez.', 'Could not collect. Try again.'));
    } finally {
      if (mounted) setState(() => _ocupado = false);
      widget.alCobrar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final min = _minutos(widget.minutos);
    return ScaleTransition(
      scale: _escala,
      child: FilledButton(
        onPressed: _ocupado ? null : _cobrar,
        child: Text(widget.gana ? tr('COBRAR $min MIN', 'COLLECT $min MIN') : tr('RECUPERAR $min MIN', 'GET BACK $min MIN')),
      ),
    );
  }
}

class _Invitacion extends StatefulWidget {
  const _Invitacion(this.reto, {this.alResponder});

  final Map<String, dynamic> reto;

  /// La tarjeta del muro se recarga al responder (en inicio lo hace realtime).
  final VoidCallback? alResponder;

  @override
  State<_Invitacion> createState() => _InvitacionState();
}

class _InvitacionState extends State<_Invitacion> {
  Map<String, dynamic>? _otro;
  bool _ocupado = false;

  bool get _meRetaron => widget.reto['retado'] == db.auth.currentUser!.id;

  /// Minutos apostados por el que retó (0 sin apuesta o en una app vieja).
  int get _apuesta => (widget.reto['apuesta_min'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _cargarOtro();
  }

  Future<void> _cargarOtro() async {
    final otro = _meRetaron ? widget.reto['retador'] : widget.reto['retado'];
    try {
      final p = await conReintento(() => db.from('profiles').select(_columnasPerfil).eq('id', otro).maybeSingle());
      if (mounted) setState(() => _otro = p);
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    }
  }

  Future<void> _responder(String accion) async {
    setState(() => _ocupado = true);
    try {
      await db.rpc('responder_reto', params: {'rid': widget.reto['id'], 'accion': accion});
      if (mounted && accion == 'aceptar') _aviso(context, tr('¡Que empiece el Cagadón! 💩', 'Let the Poop-Off begin! 💩'));
      widget.alResponder?.call();
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Aceptar un reto con apuesta: paga lo suyo. Sin Imperio (apagado, nunca abierto o tope menor) acepta sin apuesta
  /// y el servidor la anula para los dos.
  Future<void> _aceptar() async {
    final apuesta = _apuesta;
    if (apuesta <= 0) return _responder('aceptar');
    setState(() => _ocupado = true);
    try {
      final res = await resumenApuesta();
      final cuenta = res != null && apuesta <= res.tope ? res.cuenta(apuesta) : null;
      await db.rpc('aceptar_reto_apuesta', params: {'rid': widget.reto['id'], 'p_apuesta': cuenta == null ? 0 : apuesta, 'p_fraccion': cuenta?.fraccion ?? 0});
      if (cuenta != null) await pagarApuesta(reto: (widget.reto['id'] as num).toInt(), min: apuesta, fraccion: cuenta.fraccion, rol: 'acepta');
      widget.alResponder?.call();
      if (mounted) {
        _aviso(
            context,
            cuenta != null
                ? _avisoApuesta(apuesta, cuenta.mj)
                : tr('Cagadón aceptado sin apuesta: abre el Imperio para apostar.', 'Poop-Off accepted with no bet: open the Empire to bet.'));
      }
    } catch (e) {
      if (mounted) _aviso(context, textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final nombre = _otro?['username'] ?? '…';
    final apuesta = _apuesta;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (_otro != null) Avatar(_otro!, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: TextoConEmojis(
              _meRetaron
                  ? tr('⚔️ $nombre te retó a un Cagadón', '⚔️ $nombre challenged you to a Poop-Off')
                  : tr('⏳ Esperando a que $nombre acepte tu Cagadón', '⏳ Waiting for $nombre to accept your Poop-Off'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('Gana el que cague más hoy.', 'Whoever poops more today wins.'), style: TextStyle(color: p.textoSuave, fontSize: 13)),
        if (apuesta > 0) ...[
          const SizedBox(height: 4),
          TextoConEmojis(
            _meRetaron
                ? tr('💰 Apuesta: $apuesta min de producción. Si aceptas, pagas lo tuyo ahora.',
                    '💰 Bet: $apuesta min of production. If you accept, you pay your share now.')
                : tr('💰 Apostaste $apuesta min de producción. Si no acepta, lo recuperas.',
                    '💰 You bet $apuesta min of production. If they don\'t accept, you get it back.'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_meRetaron) ...[
            TextButton(onPressed: _ocupado ? null : () => _responder('rechazar'), child: Text(tr('RAJARSE 🐔', 'CHICKEN OUT 🐔'))),
            const SizedBox(width: 6),
            FilledButton(
                onPressed: _ocupado ? null : _aceptar,
                child: Text(apuesta > 0 ? tr('ACEPTAR Y APOSTAR', 'ACCEPT AND BET') : tr('ACEPTAR', 'ACCEPT'))),
          ] else
            TextButton(onPressed: _ocupado ? null : () => _responder('cancelar'), child: Text(tr('CANCELAR', 'CANCEL'))),
        ]),
      ]),
    );
  }
}

/// Marcador de un Cagadón aceptado o terminado. Sirve en inicio y en el chat; se refresca solo.
/// Con [muro] es la tarjeta del muro: muestra el reto en cualquier estado (pendiente con sus botones solo para el
/// retado o el que retó, rajado, vencido) y la misma tarjeta pasa a marcador en vivo y a resultado.
class TarjetaReto extends StatefulWidget {
  const TarjetaReto({super.key, required this.id, this.compacta = false, this.muro = false});

  final int id;
  final bool compacta;
  final bool muro;

  @override
  State<TarjetaReto> createState() => _TarjetaRetoState();
}

class _TarjetaRetoState extends State<TarjetaReto> {
  Map<String, dynamic>? _r;
  Map<String, Map<String, dynamic>> _perfiles = {};
  late final VoidCallback _soltar;

  /// Lo de la apuesta (reto_apuesta): minutos, si se anuló y, si es mío, resultado, minutos por cobrar y si ya cobré.
  Map<String, dynamic>? _apuesta;
  String? _estadoApuesta;

  /// La primera carga falló (sin red o sin el reto): se ofrece reintentar.
  bool _falla = false;

  /// Reto pendiente de hoy en el que estoy (solo en el muro): se muestra la invitación con sus botones.
  Map<String, dynamic>? _invitacion;

  /// Marca de "la apuesta no se pudo pedir": se deja la que había y se vuelve a pedir la próxima vez.
  static const Object _sinApuesta = Object();

  @override
  void initState() {
    super.initState();
    _cargar();
    _soltar = escucharCagadas('reto-${widget.id}', _cargar, contexto: context);
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final filas = await conReintento(() => db.rpc(widget.muro ? 'reto_muro' : 'reto_publico', params: {'rid': widget.id})) as List;
      if (filas.isEmpty) {
        if (mounted) setState(() => _falla = true);
        return;
      }
      final r = filas.first as Map<String, dynamic>;
      // Pendiente y de hoy con uno de los dos mirando: la fila completa (trae la apuesta) para la invitación.
      final yo = db.auth.currentUser?.id;
      Map<String, dynamic>? invitacion;
      if (r['estado'] == 'pendiente' && r['dia'] == _hoyCaracas() && (yo == r['retador'] || yo == r['retado'])) {
        invitacion = await conReintento(() => db.from('retos').select().eq('id', widget.id).maybeSingle());
      }
      // Perfiles y apuesta no dependen uno del otro: van a la vez.
      // La apuesta solo cambia con el estado del reto (o al cobrar): no se pide en cada cagada.
      final pedirApuesta = _estadoApuesta != r['estado'];
      final (ps, a) = await (
        _perfiles.isEmpty
            ? conReintento(() => db.from('profiles').select(_columnasPerfil).inFilter('id', [r['retador'], r['retado']]))
            : Future<List<Map<String, dynamic>>?>.value(),
        pedirApuesta ? conReintento(() => db.rpc('reto_apuesta', params: {'rid': widget.id})).catchError((_) => _sinApuesta) : Future.value(_sinApuesta),
      ).wait;
      if (ps != null) _perfiles = {for (final p in ps) p['id'] as String: p};
      if (pedirApuesta && !identical(a, _sinApuesta)) {
        _apuesta = a is Map ? Map<String, dynamic>.from(a) : null;
        _estadoApuesta = r['estado'] as String?;
      }
      if (mounted) {
        setState(() {
          _r = r;
          _invitacion = invitacion;
          _falla = false;
        });
      }
    } catch (_) {
      // Sin datos todavía: en vez de la ruedita eterna, un botón para reintentar.
      if (mounted && _r == null) setState(() => _falla = true);
    }
  }

  Future<void> _recargarApuesta() async {
    _estadoApuesta = null;
    await _cargar();
  }

  /// Reto sin marcador (muro): pendiente visto por otros, rajado, vencido o cancelado. Solo lectura.
  Widget _sinMarcador(BuildContext context, Map<String, dynamic> r) {
    final p = paleta(context);
    final retador = _perfiles[r['retador']], retado = _perfiles[r['retado']];
    final de = retador?['username'] ?? '…', a = retado?['username'] ?? '…';
    final estado = r['estado'];
    final texto = switch (estado) {
      'pendiente' when r['dia'] == _hoyCaracas() => tr('⏳ Esperando a que $a acepte', '⏳ Waiting for $a to accept'),
      'rechazado' => tr('🐔 $a se rajó', '🐔 $a chickened out'),
      'cancelado' => tr('🚫 $de canceló el Cagadón', '🚫 $de called off the Poop-Off'),
      _ => tr('⌛ $a no respondió a tiempo', "⌛ $a didn't answer in time"),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: Column(children: [
        TextoConEmojis(tr('⚔️ $de retó a $a a un Cagadón', '⚔️ $de challenged $a to a Poop-Off'),
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (retador != null) Avatar(retador, tamano: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: p.textoSuave)),
          ),
          if (retado != null) Avatar(retado, tamano: 30),
        ]),
        const SizedBox(height: 8),
        TextoConEmojis(texto, textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave, fontSize: 13)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final r = _r;
    if (r == null) {
      if (!_falla) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
      return SizedBox(
        height: 60,
        child: Center(
          child: TextButton(
            onPressed: () {
              setState(() => _falla = false);
              _cargar();
            },
            child: Text(tr('No se pudo cargar el Cagadón. Reintentar', 'Could not load the Poop-Off. Retry')),
          ),
        ),
      );
    }
    final invitacion = _invitacion;
    if (invitacion != null) return _Invitacion(invitacion, alResponder: _cargar);
    if (r['a'] == null || r['b'] == null) return _sinMarcador(context, r);
    final fin = r['estado'] == 'terminado';
    final a = r['a'] as int, b = r['b'] as int;
    final ganador = r['ganador'];
    final apuesta = (_apuesta?['apuesta'] as num?)?.toInt() ?? 0;
    final anulada = _apuesta?['anulada'] == true;
    final resultado = _apuesta?['resultado'];
    final porCobrar = (_apuesta?['minutos'] as num?)?.toDouble() ?? 0;
    final cobrable = (resultado == 'gana' || resultado == 'devuelve') && _apuesta?['cobrado'] != true && porCobrar > 0;
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
        TextoConEmojis(fin ? (ganador == null ? tr('🤝 CAGADÓN EMPATADO', '🤝 POOP-OFF TIED') : tr('🏆 CAGADÓN TERMINADO', '🏆 POOP-OFF OVER')) : tr('⚔️ CAGADÓN EN VIVO · HOY', '⚔️ POOP-OFF LIVE · TODAY'),
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
        if (apuesta > 0) ...[
          const SizedBox(height: 6),
          TextoConEmojis(
            anulada
                ? tr('💰 Apuesta de $apuesta min anulada: cada uno recupera lo suyo', '💰 $apuesta min bet called off: each gets theirs back')
                : tr('💰 Apuesta: $apuesta min de producción', '💰 Bet: $apuesta min of production'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: widget.compacta ? 12 : 13),
          ),
          if (cobrable) ...[
            const SizedBox(height: 6),
            _BotonCobrar(reto: widget.id, gana: resultado == 'gana', minutos: porCobrar, alCobrar: _recargarApuesta),
          ],
        ],
      ]),
    );
  }
}
