import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accesorios.dart';
import 'cagadon.dart' show TarjetaReto;
import 'emoji.dart';
import 'main.dart' show db;
import 'perfil.dart' show PantallaPerfil;
import 'tema.dart';
import 'tipos.dart';

// Mismos números que public.hitos() en supabase/migrations/…_chat.sql.
const hitos = [10, 30, 50, 100, 200, 300, 500, 1000];

/// Nombre de la sala: cambia cada vez que abres la app, nunca el mismo dos veces seguidas.
/// (nombre completo para títulos, corto para la barra de abajo).
const _nombres = [
  ('La Poceta', 'POCETA'),
  ('El Inodoro', 'INODORO'),
  ('La Taza', 'TAZA'),
  ('El Sanitario', 'SANITARIO'),
  ('El Excusado', 'EXCUSADO'),
  ('El WC', 'WC'),
  ('El Váter', 'VÁTER'),
  ('El Trono', 'TRONO'),
  ('El Cagadero', 'CAGADERO'),
  ('La Letrina', 'LETRINA'),
  ('El Retrete', 'RETRETE'),
  ('El Baño', 'BAÑO'),
  ('The Loo 🇬🇧', 'LOO'),
  ('The John 🇺🇸', 'JOHN'),
  ('Das Klo 🇩🇪', 'KLO'),
  ('Le Petit Coin 🇫🇷', 'PETIT COIN'),
  ('Il Gabinetto 🇮🇹', 'GABINETTO'),
  ('A Privada 🇧🇷', 'PRIVADA'),
  ('Benjo 🇯🇵', 'BENJO'),
];

var nombreSala = 'El Baño';
var nombreCorto = 'BAÑO';

Future<void> elegirNombreSala() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final antes = prefs.getInt('nombre_sala');
    // Sorteo entre todos menos el de la vez pasada.
    var i = Random().nextInt(antes == null ? _nombres.length : _nombres.length - 1);
    if (antes != null && i >= antes) i++;
    await prefs.setInt('nombre_sala', i);
    nombreSala = _nombres[i].$1;
    nombreCorto = _nombres[i].$2;
  } catch (_) {}
}

const _columnasPerfil =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

const _reglas = [
  ('💩', 'Aquí se habla de mojones. Groserías sí, odio no.'),
  ('🚫', 'Nada de insultos racistas, acoso, amenazas ni contenido sexual.'),
  ('📵', 'No compartas teléfonos, correos ni datos de nadie.'),
  ('🔗', 'Los links pasan por un filtro: acortadores, IPs y archivos que se instalan no entran.'),
  ('🚩', 'Mantén apretado un mensaje para reportarlo o bloquear a quien lo escribió. Con 3 reportes se oculta.'),
];

/// La primera vez que alguien va a escribir: reglas de la sala y "Acepto".
Future<bool> aceptoReglas(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('chat_reglas_ok') ?? false) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Reglas de $nombreSala 🚽'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (e, t) in _reglas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Emoji(e, tamano: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t)),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('AHORA NO')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ACEPTO')),
      ],
    ),
  );
  if (ok == true) await prefs.setBool('chat_reglas_ok', true);
  return ok == true;
}

String _error(Object e) => e is PostgrestException ? e.message : '$e';

/// Después de registrar: si llegó a un hito o desbloqueó algo, pregunta si lo presume.
Future<void> ofrecerPresumir(BuildContext context, int total) async {
  final desbloqueo = desbloqueos.where((d) => d.minimo == total).firstOrNull;
  final esHito = hitos.contains(total);
  if (!esHito && desbloqueo == null) return;
  final presumir = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(esHito ? '¡$total cagadas! 👑' : '¡Desbloqueaste ${desbloqueo!.nombre}!'),
      content: Text('¿Lo presumes en $nombreSala?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('PRESUMIR')),
      ],
    ),
  );
  if (presumir != true || !context.mounted || !await aceptoReglas(context)) return;
  try {
    await db.from('mensajes').insert({
      'sala': 'global',
      'tarjeta': esHito ? {'tipo': 'hito', 'n': total} : {'tipo': 'desbloqueo', 'emoji': desbloqueo!.emoji},
    });
    if (context.mounted) _aviso(context, 'Publicado en $nombreSala 🚽');
  } catch (e) {
    if (context.mounted) _aviso(context, _error(e));
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

/// Pestaña del medio (nombre al azar): la sala global y el soporte con los admins.
class PantallaChat extends StatefulWidget {
  const PantallaChat({super.key});

  @override
  State<PantallaChat> createState() => _PantallaChatState();
}

class _PantallaChatState extends State<PantallaChat> {
  bool _soyAdmin = false;

  @override
  void initState() {
    super.initState();
    db.rpc('es_admin').then((v) {
      if (mounted) setState(() => _soyAdmin = v == true);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(nombreSala.toUpperCase()),
            bottom: const TabBar(tabs: [Tab(text: 'TODOS 🚽'), Tab(text: 'SOPORTE 🛠️')]),
          ),
          body: TabBarView(children: [
            const Sala(sala: 'global'),
            _soyAdmin ? const _Bandeja() : Sala(sala: 'soporte', hilo: db.auth.currentUser!.id),
          ]),
        ),
      );
}

/// Abre el hilo de soporte con el formulario de error listo. Para el botón de Perfil.
Future<void> abrirReporteDeError(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('SOPORTE 🛠️')),
          body: Sala(sala: 'soporte', hilo: db.auth.currentUser!.id, abrirBug: true),
        ),
      ),
    );

/// Bandeja de los admins: un hilo por usuario, el más reciente arriba.
class _Bandeja extends StatefulWidget {
  const _Bandeja();

  @override
  State<_Bandeja> createState() => _BandejaState();
}

class _BandejaState extends State<_Bandeja> {
  List<Map<String, dynamic>>? _hilos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = List<Map<String, dynamic>>.from(await db.rpc('hilos_soporte'))
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    if (mounted) setState(() => _hilos = r);
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final hilos = _hilos;
    if (hilos == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _cargar,
      child: hilos.isEmpty
          ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nadie ha escrito a soporte')))])
          : ListView.separated(
              itemCount: hilos.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: p.borde),
              itemBuilder: (context, i) {
                final h = hilos[i];
                return ListTile(
                  leading: Avatar(h, tamano: 36),
                  title: Text(h['username'] ?? '?'),
                  subtitle: Text(
                    '${h['del_usuario'] == true ? '' : 'Tú: '}${h['es_bug'] == true ? '🐞 ' : ''}${h['texto']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_hora(h['created_at']), style: numeros(context, tamano: 12, color: p.textoSuave)),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text('SOPORTE · ${h['username']}')),
                          body: Sala(sala: 'soporte', hilo: h['hilo']),
                        ),
                      ),
                    );
                    _cargar();
                  },
                );
              },
            ),
    );
  }
}

String _hora(String iso) {
  final t = DateTime.parse(iso).toLocal();
  final hoy = DateTime.now();
  final hh = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == hoy.year && t.month == hoy.month && t.day == hoy.day) return hh;
  return '${t.day}/${t.month} $hh';
}

/// Una sala de mensajes en tiempo real: la global, o un hilo de soporte.
class Sala extends StatefulWidget {
  const Sala({super.key, required this.sala, this.hilo, this.abrirBug = false});

  final String sala;
  final String? hilo;
  final bool abrirBug;

  @override
  State<Sala> createState() => _SalaState();
}

class _SalaState extends State<Sala> with AutomaticKeepAliveClientMixin {
  late final Stream<List<Map<String, dynamic>>> _mensajes;
  final _perfiles = <String, Map<String, dynamic>>{};
  final _pidiendo = <String>{};
  Set<String> _admins = {};
  final _texto = TextEditingController();
  // Solo se puede mencionar a gente que sigues.
  List<Map<String, dynamic>> _amigos = [];
  List<Map<String, dynamic>> _sugerencias = [];
  bool _enviando = false;
  bool _soyAdmin = false;

  String get _yo => db.auth.currentUser!.id;
  bool get _esSoporte => widget.sala == 'soporte';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final base = db.from('mensajes').stream(primaryKey: ['id']);
    _mensajes = (_esSoporte ? base.eq('hilo', widget.hilo!) : base.eq('sala', 'global'))
        .order('created_at', ascending: false)
        .limit(200);
    db.rpc('admins_ids').then((r) {
      final ids = {for (final x in r as List) x as String};
      if (!mounted) return;
      setState(() {
        _admins = ids;
        _soyAdmin = ids.contains(_yo);
      });
    }).catchError((_) {});
    if (widget.abrirBug) WidgetsBinding.instance.addPostFrameCallback((_) => _reportarError());
    if (!_esSoporte) {
      _cargarAmigos();
      _texto.addListener(_buscarMencion);
    }
    // El borrador sobrevive a cerrar la app o a que se actualice.
    SharedPreferences.getInstance().then((prefs) {
      final b = prefs.getString(_claveBorrador);
      if (b != null && _texto.text.isEmpty) _texto.text = b;
      _texto.addListener(() => prefs.setString(_claveBorrador, _texto.text));
    });
  }

  String get _claveBorrador => 'borrador_${widget.sala}_${widget.hilo ?? ''}';

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _cargarAmigos() async {
    try {
      final f = await db.from('follows').select('followed').eq('follower', _yo);
      final ids = [for (final x in f) x['followed'] as String];
      if (ids.isEmpty) return;
      final r = await db.from('profiles').select(_columnasPerfil).inFilter('id', ids).order('username');
      if (mounted) setState(() => _amigos = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  // "@algo" justo antes del cursor: sugiere amigos que empiezan así.
  RegExpMatch? _arrobaActual() {
    final sel = _texto.selection;
    final hasta = sel.isValid ? sel.baseOffset : _texto.text.length;
    return RegExp(r'(^|\s)@([^@\n]{0,30})$').firstMatch(_texto.text.substring(0, hasta.clamp(0, _texto.text.length)));
  }

  void _buscarMencion() {
    final m = _arrobaActual();
    final q = m?.group(2)?.toLowerCase();
    final nuevas = q == null
        ? <Map<String, dynamic>>[]
        : _amigos.where((a) => (a['username'] as String).toLowerCase().startsWith(q)).take(8).toList();
    if (nuevas.length != _sugerencias.length || !nuevas.every(_sugerencias.contains)) {
      setState(() => _sugerencias = nuevas);
    }
  }

  void _mencionar(Map<String, dynamic> amigo) {
    final m = _arrobaActual();
    final arroba = '@${amigo['username']} ';
    final fin = m == null ? _texto.text.length : m.end;
    final inicio = m == null ? fin : m.start + m.group(1)!.length;
    final texto = _texto.text.replaceRange(inicio, fin, arroba);
    _texto.value = TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: inicio + arroba.length));
    setState(() => _sugerencias = []);
  }

  bool _mencionaA(String? texto) {
    final yo = _perfiles[_yo]?['username'] as String?;
    return yo != null && texto != null && texto.toLowerCase().contains('@${yo.toLowerCase()}');
  }

  // Los perfiles se piden de a tandas, solo los que faltan.
  void _pedirPerfiles(Iterable<String> ids) {
    final faltan = ids.where((id) => !_perfiles.containsKey(id) && !_pidiendo.contains(id)).toSet();
    if (faltan.isEmpty) return;
    _pidiendo.addAll(faltan);
    db.from('profiles').select(_columnasPerfil).inFilter('id', faltan.toList()).then((r) {
      for (final p in r) {
        _perfiles[p['id'] as String] = p;
      }
      if (mounted) setState(() {});
    }).whenComplete(() => _pidiendo.removeAll(faltan));
  }

  Future<void> _enviar({Map<String, dynamic>? tarjeta, bool bug = false, String? texto}) async {
    final t = (texto ?? _texto.text).trim();
    if (t.isEmpty && tarjeta == null) return;
    if (!_esSoporte && !await aceptoReglas(context)) return;
    setState(() => _enviando = true);
    try {
      await db.from('mensajes').insert({
        'sala': widget.sala,
        if (_esSoporte) 'hilo': widget.hilo,
        'texto': t,
        'tarjeta': ?tarjeta,
        'es_bug': bug,
      });
      if (texto == null && tarjeta == null) _texto.clear();
    } catch (e) {
      if (mounted) _aviso(context, _error(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _compartir() async {
    final yo = await db.from('profiles').select('cagadas').eq('id', _yo).single();
    final ultima = await db
        .from('cagadas')
        .select('id, tipo')
        .eq('user_id', _yo)
        .not('tipo', 'is', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final total = (yo['cagadas'] as num?)?.toInt() ?? 0;
    if (!mounted) return;
    final logrados = hitos.where((h) => h <= total).toList().reversed;
    final mios = desbloqueos.where((d) => d.minimo <= total).toList().reversed;
    final tarjeta = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 0, 16, 16)),
          children: [
            Text('PRESUMIR', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (ultima != null)
              ListTile(
                leading: Emoji(tipoEmoji(ultima['tipo'] as int?), tamano: 30),
                title: Text('Mi última cagada: ${tipos[ultima['tipo']]?.$2}'),
                onTap: () => Navigator.pop(context, {'tipo': 'cagada', 'id': ultima['id']}),
              ),
            for (final h in logrados)
              ListTile(
                leading: const Emoji('👑', tamano: 30),
                title: Text('Llegué a $h cagadas'),
                onTap: () => Navigator.pop(context, {'tipo': 'hito', 'n': h}),
              ),
            for (final d in mios)
              ListTile(
                leading: Emoji(d.emoji, tamano: 30),
                title: Text('Desbloqueé ${d.nombre}'),
                onTap: () => Navigator.pop(context, {'tipo': 'desbloqueo', 'emoji': d.emoji}),
              ),
            if (ultima == null && logrados.isEmpty && mios.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Todavía no tienes nada que presumir. ¡A cagar!'),
              ),
          ],
        ),
      ),
    );
    if (tarjeta != null) await _enviar(tarjeta: tarjeta);
  }

  Future<void> _reportarError() async {
    final que = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reportar un error 🐞'),
        content: TextField(
          controller: que,
          autofocus: true,
          maxLines: 5,
          maxLength: 800,
          decoration: const InputDecoration(hintText: '¿Qué pasó y qué estabas haciendo?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ENVIAR')),
        ],
      ),
    );
    if (enviar != true || que.text.trim().isEmpty) return;
    final info = await PackageInfo.fromPlatform();
    final equipo = 'v${info.version} (${info.buildNumber}) · ${Platform.operatingSystemVersion}';
    await _enviar(bug: true, texto: '${que.text.trim()}\n\n— $equipo');
  }

  Future<void> _opciones(Map<String, dynamic> m) async {
    final suyo = m['user_id'] == _yo;
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!suyo && !_esSoporte && _amigos.any((a) => a['id'] == m['user_id']))
            ListTile(leading: const Icon(Icons.alternate_email), title: const Text('Mencionar'), onTap: () => Navigator.pop(context, 'mencionar')),
          if (!suyo && !_esSoporte)
            ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Reportar mensaje'), onTap: () => Navigator.pop(context, 'reportar')),
          if (!suyo && !_esSoporte && !_admins.contains(m['user_id']))
            ListTile(leading: const Icon(Icons.block), title: const Text('Bloquear a esta persona'), onTap: () => Navigator.pop(context, 'bloquear')),
          if (_soyAdmin && !_esSoporte)
            ListTile(
              leading: Icon(m['oculto'] == true ? Icons.visibility : Icons.visibility_off),
              title: Text(m['oculto'] == true ? 'Volver a mostrar' : 'Ocultar a todos'),
              onTap: () => Navigator.pop(context, 'ocultar'),
            ),
          if (suyo || _soyAdmin)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Borrar'), onTap: () => Navigator.pop(context, 'borrar')),
        ]),
      ),
    );
    if (accion == null || !mounted) return;
    try {
      switch (accion) {
        case 'mencionar':
          _texto.selection = TextSelection.collapsed(offset: _texto.text.length);
          _mencionar(_amigos.firstWhere((a) => a['id'] == m['user_id']));
        case 'reportar':
          final motivo = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final mo in const ['Odio o insultos', 'Acoso', 'Contenido sexual', 'Spam o estafa', 'Datos personales', 'Otro'])
                  ListTile(title: Text(mo), onTap: () => Navigator.pop(context, mo)),
              ]),
            ),
          );
          if (motivo == null) return;
          await db.from('mensaje_reportes').insert({'mensaje_id': m['id'], 'motivo': motivo});
          if (mounted) _aviso(context, 'Reportado. Gracias 🙏');
        case 'bloquear':
          await db.from('bloqueos').insert({'bloqueado': m['user_id']});
          if (mounted) _aviso(context, 'Bloqueado. Ya no verás sus mensajes');
        case 'ocultar':
          await db.from('mensajes').update({'oculto': m['oculto'] != true}).eq('id', m['id']);
        case 'borrar':
          await db.from('mensajes').delete().eq('id', m['id']);
      }
    } on PostgrestException catch (e) {
      if (mounted) _aviso(context, e.code == '23505' ? 'Ya lo habías reportado' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = paleta(context);
    return Column(
      children: [
        if (_esSoporte && widget.hilo == _yo)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(color: p.suave, border: Border(bottom: BorderSide(color: p.borde))),
            child: Row(children: [
              const Expanded(child: Text('Escríbenos dudas, ideas o errores. Te respondemos aquí.')),
              TextButton.icon(onPressed: _reportarError, icon: const Icon(Icons.bug_report_outlined), label: const Text('ERROR')),
            ]),
          ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _mensajes,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('No se pudo cargar el chat'));
              final lista = snap.data;
              if (lista == null) return const Center(child: CircularProgressIndicator());
              _pedirPerfiles([_yo, ...lista.map((m) => m['user_id'] as String)]);
              if (lista.isEmpty) {
                return Center(
                  child: Text(_esSoporte ? 'Todavía no hay mensajes' : 'Nadie ha dicho nada. Estrena $nombreSala 🚽',
                      style: TextStyle(color: p.textoSuave)),
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: lista.length,
                itemBuilder: (context, i) {
                  final m = lista[i];
                  return GestureDetector(
                    onLongPress: () => _opciones(m),
                    child: _Burbuja(
                      mensaje: m,
                      perfil: _perfiles[m['user_id']],
                      mio: m['user_id'] == _yo,
                      admin: _admins.contains(m['user_id']),
                      meMencionan: _mencionaA(m['texto'] as String?),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_sugerencias.isNotEmpty)
          Container(
            height: 52,
            decoration: BoxDecoration(color: p.suave, border: Border(top: BorderSide(color: p.borde))),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final a in _sugerencias)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      avatar: Avatar(a, tamano: 20),
                      label: Text('@${a['username']}'),
                      onPressed: () => _mencionar(a),
                    ),
                  ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borde))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (!_esSoporte)
                IconButton(onPressed: _enviando ? null : _compartir, icon: const Icon(Icons.emoji_events_outlined), tooltip: 'Presumir'),
              if (_esSoporte) const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _texto,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: _esSoporte ? 'Escribe algo…' : 'Escribe algo… (@ para mencionar a un amigo)', counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: _enviando ? null : () => _enviar(), icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje, required this.perfil, required this.mio, required this.admin, this.meMencionan = false});

  final Map<String, dynamic> mensaje;
  final Map<String, dynamic>? perfil;
  final bool mio;
  final bool admin;
  final bool meMencionan;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final texto = Theme.of(context).textTheme;
    final tarjeta = mensaje['tarjeta'] as Map<String, dynamic>?;
    final cuerpo = (mensaje['texto'] as String?) ?? '';
    return Opacity(
      opacity: mensaje['oculto'] == true ? .4 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: mensaje['user_id'])),
              ),
              child: SizedBox(width: 40, child: perfil == null ? const Emoji('💩', tamano: 30) : Avatar(perfil!, tamano: 32)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                decoration: BoxDecoration(
                  color: mio ? p.suave : p.tarjeta,
                  borderRadius: BorderRadius.circular(radio),
                  border: Border.all(
                    color: mensaje['es_bug'] == true ? const Color(0xFFB3261E) : meMencionan ? acento : p.borde,
                    width: meMencionan ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(perfil?['username'] ?? '…',
                            overflow: TextOverflow.ellipsis,
                            style: texto.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (admin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          color: acento,
                          child: const Text('ADMIN', style: TextStyle(color: acentoTexto, fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ],
                      if (mensaje['es_bug'] == true) const Text('  🐞'),
                      const Spacer(),
                      Text(_hora(mensaje['created_at']), style: numeros(context, tamano: 11, color: p.textoSuave)),
                    ]),
                    if (tarjeta != null) ...[const SizedBox(height: 6), _Tarjeta(tarjeta)],
                    if (cuerpo.isNotEmpty) ...[const SizedBox(height: 3), _TextoConLinks(cuerpo)],
                    if (mensaje['oculto'] == true)
                      Text('Oculto por reportes', style: TextStyle(color: p.textoSuave, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta(this.t);

  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) {
    if (t['tipo'] == 'reto' || t['tipo'] == 'reto_fin') return TarjetaReto(id: t['id'] as int, compacta: true);
    final (emoji, titulo, sub) = switch (t['tipo']) {
      'hito' => ('👑', 'LLEGÓ A ${t['n']} CAGADAS', 'Arrodíllense ante el rey'),
      'desbloqueo' => (
          t['emoji'] as String,
          'DESBLOQUEÓ ${(desbloqueos.where((d) => d.emoji == t['emoji']).firstOrNull?.nombre ?? '').toUpperCase()}',
          'A las ${t['minimo']} cagadas',
        ),
      'cagada' => (tipoEmoji(t['mojon'] as int?), 'CAGADA #${t['n']}', 'Le salió: ${tipos[t['mojon']]?.$2 ?? '?'}'),
      _ => ('💩', '', ''),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: acento, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: Row(children: [
        Emoji(emoji, tamano: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            Text(sub, style: TextStyle(color: paleta(context).textoSuave, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

final _link = RegExp(r'((https?://|www\.)[^\s<>"]+)', caseSensitive: false);

/// Texto con los links tocables. Antes de abrir, muestra a qué dominio vas.
class _TextoConLinks extends StatelessWidget {
  const _TextoConLinks(this.texto);

  final String texto;

  Future<void> _abrir(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Abrir link?'),
        content: Text('Vas a salir de Rey Cagón hacia:\n\n${uri.host}\n\nNo pongas contraseñas ni datos de pago en páginas que te manden por chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ABRIR')),
        ],
      ),
    );
    if (ok == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final partes = <InlineSpan>[];
    var desde = 0;
    for (final m in _link.allMatches(texto)) {
      if (m.start > desde) partes.add(TextSpan(text: texto.substring(desde, m.start)));
      final url = m.group(0)!;
      partes.add(TextSpan(
        text: url,
        style: const TextStyle(decoration: TextDecoration.underline, color: Color(0xFF4DA3FF)),
        recognizer: TapGestureRecognizer()..onTap = () => _abrir(context, url),
      ));
      desde = m.end;
    }
    if (desde < texto.length) partes.add(TextSpan(text: texto.substring(desde)));
    return Text.rich(TextSpan(style: base, children: partes));
  }
}
