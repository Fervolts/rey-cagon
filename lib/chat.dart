import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accesorios.dart';
import 'amigos.dart';
import 'animaciones.dart';
import 'avisos.dart';
import 'cagadon.dart' show TarjetaReto;
import 'popups.dart' show PantallaPopups;
import 'emoji.dart';
import 'idioma.dart';
import 'peso.dart';
import 'racha.dart';
import 'main.dart' show db, esDeRed;
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

const _nombresEn = [
  ('The Throne', 'THRONE'),
  ('The Porcelain Throne', 'PORCELAIN'),
  ('The Loo', 'LOO'),
  ('The John', 'JOHN'),
  ('The Can', 'CAN'),
  ('The Crapper', 'CRAPPER'),
  ('The Head', 'HEAD'),
  ('The Bog', 'BOG'),
  ('The Potty', 'POTTY'),
  ('The Latrine', 'LATRINE'),
  ('The Commode', 'COMMODE'),
  ('The Restroom', 'RESTROOM'),
  ('El Baño 🇪🇸', 'BAÑO'),
  ('Das Klo 🇩🇪', 'KLO'),
  ('Le Petit Coin 🇫🇷', 'PETIT COIN'),
  ('Il Gabinetto 🇮🇹', 'GABINETTO'),
  ('Benjo 🇯🇵', 'BENJO'),
];

var nombreSala = 'El Baño';
var nombreCorto = 'BAÑO';

Future<void> elegirNombreSala() async {
  final nombres = enIngles ? _nombresEn : _nombres;
  final clave = enIngles ? 'nombre_sala_en' : 'nombre_sala';
  try {
    final prefs = await SharedPreferences.getInstance();
    var antes = prefs.getInt(clave);
    if (antes != null && antes >= nombres.length) antes = null;
    // Sorteo entre todos menos el de la vez pasada.
    var i = Random().nextInt(antes == null ? nombres.length : nombres.length - 1);
    if (antes != null && i >= antes) i++;
    await prefs.setInt(clave, i);
    nombreSala = nombres[i].$1;
    nombreCorto = nombres[i].$2;
  } catch (_) {}
}

const _columnasPerfil =
    'id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala';

List<(String, String)> get _reglas => [
  ('💩', tr('Aquí se habla de mojones. Groserías sí, odio no.', 'We talk turds here. Swearing is fine, hate is not.')),
  ('🚫', tr('Nada de insultos racistas, acoso, amenazas ni contenido sexual.', 'No racist insults, harassment, threats or sexual content.')),
  ('📵', tr('No compartas teléfonos, correos ni datos de nadie.', "Don't share phone numbers, emails or anyone's personal info.")),
  ('🔗', tr('Los links pasan por un filtro: acortadores, IPs y archivos que se instalan no entran.', "Links go through a filter: shorteners, IPs and files that install stuff don't get in.")),
  ('🚩', tr('Mantén apretado un mensaje para reportarlo o bloquear a quien lo escribió. Con 3 reportes se oculta.', 'Press and hold a message to report it or block whoever wrote it. With 3 reports it gets hidden.')),
];

/// La primera vez que alguien va a escribir: reglas de la sala y "Acepto".
Future<bool> aceptoReglas(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('chat_reglas_ok') ?? false) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Reglas de $nombreSala 🚽', '$nombreSala rules 🚽')),
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
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('AHORA NO', 'NOT NOW'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ACEPTO', 'I AGREE'))),
      ],
    ),
  );
  if (ok == true) await prefs.setBool('chat_reglas_ok', true);
  return ok == true;
}

// Los del trigger de hilos (supabase/migrations/…_hilos_reacciones.sql).
const _erroresHilo = {
  'Ese mensaje ya no existe': 'That message no longer exists',
  'No se puede responder a una respuesta': "You can't reply to a reply",
  'La respuesta tiene que ir en la misma sala': 'The reply has to go in the same room',
};

String _error(Object e) =>
    e is PostgrestException ? (enIngles ? _erroresHilo[e.message] : null) ?? trServidor(e.message) : '$e';

/// Las reacciones que se pueden poner. Mismos que el check de mensaje_reacciones en la base.
const _reaccionesRapidas = ['💩', '😂', '🔥', '👑', '🤢', '💀'];

/// Después de registrar: si llegó a un hito o desbloqueó algo, pregunta si lo presume.
Future<void> ofrecerPresumir(BuildContext context, int total) async {
  final desbloqueo = desbloqueos.where((d) => d.minimo == total).firstOrNull;
  final esHito = hitos.contains(total);
  if (!esHito && desbloqueo == null) return;
  final presumir = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(esHito ? tr('¡$total cagadas! 👑', '$total poops! 👑') : tr('¡Desbloqueaste ${desbloqueo!.nombre}!', 'You unlocked ${desbloqueo.nombre}!')),
      content: Text(tr('¿Lo presumes en $nombreSala?', 'Show it off in $nombreSala?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('NO', 'NO'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('PRESUMIR', 'SHOW OFF'))),
      ],
    ),
  );
  if (presumir != true || !context.mounted || !await aceptoReglas(context)) return;
  try {
    await db.from('mensajes').insert({
      'sala': 'global',
      'tarjeta': esHito ? {'tipo': 'hito', 'n': total} : {'tipo': 'desbloqueo', 'emoji': desbloqueo!.emoji},
    });
    if (context.mounted) _aviso(context, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
  } catch (e) {
    if (context.mounted) _aviso(context, _error(e));
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(texto)));

/// Pestaña del medio (nombre al azar): la sala general, la de cada idioma (primero la tuya), los
/// amigos y, desde el botón de arriba, el soporte con los admins.
class PantallaChat extends StatefulWidget {
  const PantallaChat({super.key});

  @override
  State<PantallaChat> createState() => _PantallaChatState();
}

class _PantallaChatState extends State<PantallaChat> with SingleTickerProviderStateMixin {
  // Salas en public.mensajes: 'global' es la general, 'es' y 'en' las de cada idioma.
  final _pestanas = ['global', idioma.value, if (enIngles) 'es' else 'en', 'amigos'];
  late final _tabs = TabController(length: _pestanas.length, vsync: this);
  bool _soyAdmin = false;

  @override
  void initState() {
    super.initState();
    db.rpc('es_admin').then((v) {
      if (mounted) setState(() => _soyAdmin = v == true);
    }).catchError((_) {});
    irA.addListener(_irA);
    WidgetsBinding.instance.addPostFrameCallback((_) => _irA());
  }

  @override
  void dispose() {
    irA.removeListener(_irA);
    _tabs.dispose();
    super.dispose();
  }

  // Un toque en un push o en un aviso: elegir la pestaña del baño.
  void _irA() {
    final destino = irA.value;
    if (destino == null || destino.bano || !mounted) return;
    destino.bano = true;
    if (destino.a == 'soporte') {
      _abrirSoporte();
      return;
    }
    final i = _pestanas.indexOf(destino.a == 'todos' ? 'global' : destino.a);
    if (i >= 0) _tabs.animateTo(i);
  }

  void _abrirSoporte() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(tr('SOPORTE 🛠️', 'SUPPORT 🛠️'))),
            body: _soyAdmin ? const _Bandeja() : Sala(sala: 'soporte', hilo: db.auth.currentUser!.id),
          ),
        ),
      );

  String _nombrePestana(String sala) => switch (sala) {
        'global' => 'GENERAL 🌎',
        'es' => 'ESPAÑOL',
        'en' => 'ENGLISH',
        _ => tr('AMIGOS 👥', 'FRIENDS 👥'),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(nombreSala.toUpperCase()),
          actions: [
            if (_soyAdmin)
              IconButton(
                tooltip: 'Pop-ups',
                icon: const Icon(Icons.campaign_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaPopups())),
              ),
            IconButton(
              tooltip: tr('Soporte', 'Support'),
              icon: const Icon(Icons.support_agent),
              onPressed: _abrirSoporte,
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final p in _pestanas) Tab(text: _nombrePestana(p))],
          ),
        ),
        body: TabBarView(controller: _tabs, children: [
          for (final p in _pestanas) p == 'amigos' ? const PantallaAmigos() : Sala(key: ValueKey(p), sala: p),
        ]),
      );
}

/// Abre el hilo de soporte con el formulario de error listo. Para el botón de Perfil.
Future<void> abrirReporteDeError(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('SOPORTE 🛠️', 'SUPPORT 🛠️'))),
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
          ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('Nadie ha escrito a soporte', 'Nobody has written to support'))))])
          : ListView.separated(
              itemCount: hilos.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: p.borde),
              itemBuilder: (context, i) {
                final h = hilos[i];
                return ListTile(
                  leading: Avatar(h, tamano: 36),
                  title: Text(h['username'] ?? '?'),
                  subtitle: Text(
                    '${h['del_usuario'] == true ? '' : tr('Tú: ', 'You: ')}${h['es_bug'] == true ? '🐞 ' : ''}${h['texto']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_hora(h['created_at']), style: numeros(context, tamano: 12, color: p.textoSuave)),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(tr('SOPORTE · ${h['username']}', 'SUPPORT · ${h['username']}'))),
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
  return enIngles ? '${t.month}/${t.day} $hh' : '${t.day}/${t.month} $hh';
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

var _canales = 0;

class _SalaState extends State<Sala> with AutomaticKeepAliveClientMixin {
  // Mensajes por id. Se llena con una consulta normal y se mantiene al día con realtime; si
  // realtime se cae (pantalla apagada, cambio de red, token vencido) se reconecta y se vuelve a
  // consultar. Antes era db.from().stream(), que al fallar una vez se quedaba muerto o vacío.
  static const _limite = 200;
  final _porId = <int, Map<String, dynamic>>{};
  bool _cargado = false;
  Object? _errorCarga;
  bool _reconectando = false;
  RealtimeChannel? _canal;
  Timer? _reintentoCarga, _reintentoCanal;
  // Anuncios fijados arriba de la sala global (los fija un admin por un tiempo).
  List<Map<String, dynamic>> _fijados = [];
  int _verFijado = 0;
  late final AppLifecycleListener _ciclo;
  final _perfiles = <String, Map<String, dynamic>>{};
  final _pidiendo = <String>{};
  Set<String> _admins = {};
  final _texto = TextEditingController();
  // Solo se puede mencionar a gente que sigues.
  List<Map<String, dynamic>> _amigos = [];
  List<Map<String, dynamic>> _sugerencias = [];
  bool _enviando = false;
  bool _soyAdmin = false;
  // Hilos: las respuestas van aparte, por id del mensaje padre, y no salen en el flujo de la sala.
  // Si la base todavía no tiene la columna responde_a (migración sin aplicar), _hayHilos queda en
  // false y la sala funciona como antes.
  final _respuestas = <int, Map<int, Map<String, dynamic>>>{};
  bool _hayHilos = true;
  // Ids borrados, para que un hilo abierto sepa que su padre ya no está.
  final _borrados = <int>{};
  // Reacciones: id del mensaje → emoji → quiénes la pusieron. Tienen su propio canal de realtime.
  final _reacciones = <int, Map<String, Set<String>>>{};
  bool _hayReacciones = true;
  RealtimeChannel? _canalReacciones;
  Timer? _reintentoReacciones;
  // Cuándo llegó cada mensaje nuevo (para animarlo una sola vez) y cuándo puse cada reacción
  // ("id emoji", para el brinco del chip).
  final _llegada = <int, DateTime>{};
  final _rebote = <String, DateTime>{};
  // La pantalla del hilo es otra ruta: escucha esto para repintarse cuando la sala cambia.
  final _version = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _version.value++;
  }

  String get _yo => db.auth.currentUser!.id;
  bool get _esSoporte => widget.sala == 'soporte';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _conectar();
    _ciclo = AppLifecycleListener(onResume: () {
      _conectar();
      _cargar();
    });
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
    _ciclo.dispose();
    _reintentoCarga?.cancel();
    _reintentoCanal?.cancel();
    _reintentoReacciones?.cancel();
    final canal = _canal;
    _canal = null;
    if (canal != null) db.removeChannel(canal);
    final reacciones = _canalReacciones;
    _canalReacciones = null;
    if (reacciones != null) db.removeChannel(reacciones);
    // _version no se cierra: un hilo abierto todavía puede quitarse de oyente después.
    _texto.dispose();
    super.dispose();
  }

  // Lista para pintar: lo más nuevo primero (el ListView va al revés).
  List<Map<String, dynamic>> get _lista {
    final ids = _porId.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final id in ids.take(_limite)) _porId[id]!];
  }

  bool _esDeAqui(Map<String, dynamic> m) => _esSoporte ? m['hilo'] == widget.hilo : m['sala'] == widget.sala;

  Future<void> _cargar({int intento = 0}) async {
    try {
      final base = db.from('mensajes').select();
      final deAqui = _esSoporte ? base.eq('hilo', widget.hilo!) : base.eq('sala', widget.sala);
      // Las respuestas de hilos no van en el flujo: se piden aparte con _cargarRespuestas.
      final r = await (_hayHilos ? deAqui.isFilter('responde_a', null) : deAqui).order('id', ascending: false).limit(_limite);
      if (!mounted) return;
      final ultimo = r.isEmpty ? 0 : r.first['id'] as int;
      setState(() {
        // Lo que llegó por realtime mientras se consultaba (más nuevo que lo consultado) se queda.
        final recientes = _porId.entries.where((e) => e.key > ultimo).toList();
        _porId
          ..clear()
          ..addEntries([for (final m in r) MapEntry(m['id'] as int, m)])
          ..addEntries(recientes);
        _cargado = true;
        _errorCarga = null;
      });
      _cargarFijados();
      final ids = [for (final m in r) m['id'] as int];
      _cargarReacciones(ids);
      _cargarRespuestas(ids);
    } catch (e) {
      if (!mounted) return;
      // Sin la migración de hilos la columna no existe: se pide como antes.
      if (_hayHilos && e is PostgrestException && (e.code == '42703' || e.message.contains('responde_a'))) {
        _hayHilos = false;
        return _cargar(intento: intento);
      }
      // Sin red: se reintenta solo. Mientras, se sigue mostrando lo que ya había.
      if (intento < 4) {
        _reintentoCarga?.cancel();
        _reintentoCarga = Timer(Duration(seconds: 2 * (intento + 1)), () => _cargar(intento: intento + 1));
      }
      if (!_cargado || !esDeRed(e)) setState(() => _errorCarga = e);
    }
  }

  // Aparte de los 200 últimos: un anuncio fijado puede ser más viejo que eso.
  Future<void> _cargarFijados() async {
    if (_esSoporte) return;
    try {
      final r = await db
          .from('mensajes')
          .select()
          .eq('sala', widget.sala)
          .gt('fijado_hasta', DateTime.now().toUtc().toIso8601String())
          .order('id', ascending: false)
          .limit(5);
      if (!mounted) return;
      _pedirPerfiles(r.map((m) => m['user_id'] as String));
      setState(() => _fijados = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  // Respuestas de estos mensajes (todas, hasta 1000), y sus reacciones. Lo que llegó por realtime
  // mientras se consultaba se queda.
  Future<void> _cargarRespuestas(List<int> padres) async {
    if (!_hayHilos || padres.isEmpty) return;
    try {
      final todas = <Map<String, dynamic>>[];
      for (var i = 0; i < padres.length; i += 150) {
        final tanda = padres.sublist(i, min(i + 150, padres.length));
        todas.addAll(await db.from('mensajes').select().inFilter('responde_a', tanda).order('id', ascending: false).limit(1000));
      }
      if (!mounted) return;
      final ultimo = todas.fold<int>(0, (a, m) => max(a, m['id'] as int));
      final nuevas = <int, Map<int, Map<String, dynamic>>>{};
      for (final m in todas) {
        (nuevas[m['responde_a'] as int] ??= {})[m['id'] as int] = m;
      }
      _pedirPerfiles(todas.map((m) => m['user_id'] as String));
      setState(() {
        for (final padre in padres) {
          final recientes = _respuestas[padre]?.entries.where((e) => e.key > ultimo).toList() ?? const [];
          _respuestas[padre] = {...?nuevas[padre]}..addEntries(recientes);
        }
      });
      _cargarReacciones([for (final m in todas) m['id'] as int]);
    } catch (_) {}
  }

  Future<void> _cargarReacciones(List<int> ids) async {
    if (!_hayReacciones || ids.isEmpty) return;
    try {
      final todas = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 150) {
        final tanda = ids.sublist(i, min(i + 150, ids.length));
        todas.addAll(await db.from('mensaje_reacciones').select('mensaje_id, user_id, emoji').inFilter('mensaje_id', tanda).limit(1000));
      }
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _reacciones.remove(id);
        }
        for (final x in todas) {
          ((_reacciones[x['mensaje_id'] as int] ??= {})[x['emoji'] as String] ??= {}).add(x['user_id'] as String);
        }
      });
    } on PostgrestException catch (e) {
      // Sin la migración la tabla no existe: no se muestran reacciones.
      if (e.code == '42P01' || e.code == 'PGRST205' || e.code == 'PGRST200') _hayReacciones = false;
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _fijadosVigentes =>
      _fijados.where((m) => DateTime.parse(m['fijado_hasta'] as String).isAfter(DateTime.now())).toList();

  bool _estaFijado(Map<String, dynamic> m) =>
      m['fijado_hasta'] != null && DateTime.parse(m['fijado_hasta'] as String).isAfter(DateTime.now());

  void _conectar() {
    final viejo = _canal;
    if (viejo != null) db.removeChannel(viejo);
    final filtro = _esSoporte
        ? PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'hilo', value: widget.hilo)
        : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'sala', value: widget.sala);
    late final RealtimeChannel canal;
    var unido = false;
    canal = db
        .channel('sala-${widget.sala}-${_canales++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes',
          filter: filtro,
          callback: (c) => _poner(c.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'mensajes',
          filter: filtro,
          callback: (c) {
            final m = c.newRecord;
            final cambiaFijado = m['fijado_hasta'] != null || _fijados.any((f) => f['id'] == m['id']);
            _poner(m);
            if (cambiaFijado) _cargarFijados();
          },
        )
        // Los borrados no se pueden filtrar en realtime: llega solo el id y se quita si está.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'mensajes',
          callback: (c) {
            final id = c.oldRecord['id'];
            if (id is! int) return;
            _borrados.add(id);
            if (mounted && (_porId.containsKey(id) || _respuestas.containsKey(id) || _respuestas.values.any((r) => r.containsKey(id)))) {
              setState(() => _quitar(id));
            }
            if (_fijados.any((f) => f['id'] == id)) _cargarFijados();
          },
        )
        .subscribe((estado, [_]) {
          if (!mounted || _canal != canal) return;
          switch (estado) {
            case RealtimeSubscribeStatus.subscribed:
              // Al unirse (o volver a unirse) se consulta de nuevo: pudo perderse algo en el hueco.
              if (unido || _reconectando) _cargar();
              unido = true;
              if (_reconectando) setState(() => _reconectando = false);
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.closed:
              setState(() => _reconectando = true);
              _reintentoCanal?.cancel();
              _reintentoCanal = Timer(const Duration(seconds: 3), () {
                if (mounted && _canal == canal) _conectar();
              });
          }
        });
    _canal = canal;
    _conectarReacciones();
  }

  // Reacciones de todos los mensajes (la tabla no tiene sala): las de mensajes que no están en
  // pantalla se ignoran. Los borrados llegan con la llave completa (mensaje, usuario, emoji).
  void _conectarReacciones() {
    final viejo = _canalReacciones;
    _canalReacciones = null;
    if (viejo != null) db.removeChannel(viejo);
    if (!_hayReacciones) return;
    late final RealtimeChannel canal;
    canal = db
        .channel('reacciones-${widget.sala}-${_canales++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensaje_reacciones',
          callback: (c) => _cambiarReaccion(c.newRecord, poner: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'mensaje_reacciones',
          callback: (c) => _cambiarReaccion(c.oldRecord, poner: false),
        )
        .subscribe((estado, [_]) {
          if (!mounted || _canalReacciones != canal) return;
          if (estado == RealtimeSubscribeStatus.channelError || estado == RealtimeSubscribeStatus.timedOut || estado == RealtimeSubscribeStatus.closed) {
            _reintentoReacciones?.cancel();
            _reintentoReacciones = Timer(const Duration(seconds: 10), () {
              if (mounted && _canalReacciones == canal) _conectarReacciones();
            });
          }
        });
    _canalReacciones = canal;
  }

  bool _esConocido(int id) => _porId.containsKey(id) || _respuestas.values.any((r) => r.containsKey(id));

  void _cambiarReaccion(Map<String, dynamic> r, {required bool poner}) {
    final id = r['mensaje_id'], quien = r['user_id'], emoji = r['emoji'];
    if (!mounted || id is! int || quien is! String || emoji is! String) return;
    final ya = _reacciones[id]?[emoji]?.contains(quien) ?? false;
    if (ya == poner || (poner && !_esConocido(id))) return;
    setState(() => _marcarReaccion(id, emoji, quien, poner));
  }

  void _marcarReaccion(int id, String emoji, String quien, bool poner) {
    final del = _reacciones[id] ??= {};
    if (poner) {
      (del[emoji] ??= {}).add(quien);
    } else {
      del[emoji]?.remove(quien);
      if (del[emoji]?.isEmpty ?? false) del.remove(emoji);
    }
  }

  // Tocar una reacción: si es mía la quita, si no la pone. Se pinta antes de que conteste la base.
  Future<void> _reaccionar(Map<String, dynamic> m, String emoji) async {
    final id = m['id'] as int;
    final quitar = _reacciones[id]?[emoji]?.contains(_yo) ?? false;
    setState(() {
      _marcarReaccion(id, emoji, _yo, !quitar);
      if (!quitar) _rebote['$id $emoji'] = DateTime.now();
    });
    try {
      if (quitar) {
        await db.from('mensaje_reacciones').delete().eq('mensaje_id', id).eq('user_id', _yo).eq('emoji', emoji);
      } else {
        await db.from('mensaje_reacciones').insert({'mensaje_id': id, 'emoji': emoji});
      }
    } catch (e) {
      // Ya estaba puesta (otro teléfono, doble toque): da igual.
      if (e is PostgrestException && e.code == '23505') return;
      if (!mounted) return;
      setState(() => _marcarReaccion(id, emoji, _yo, quitar));
      _aviso(context, _error(e));
    }
  }

  void _quitar(int id) {
    _porId.remove(id);
    _respuestas.remove(id);
    for (final r in _respuestas.values) {
      r.remove(id);
    }
    _reacciones.remove(id);
  }

  void _poner(Map<String, dynamic> m) {
    if (!mounted || m['id'] == null || !_esDeAqui(m)) return;
    final id = m['id'] as int;
    final padre = m['responde_a'] as int?;
    setState(() {
      if (_cargado && !_esConocido(id)) _llegada[id] = DateTime.now();
      if (padre == null) {
        _porId[id] = m;
      } else {
        (_respuestas[padre] ??= {})[id] = m;
      }
    });
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

  // [respondeA]: id del mensaje padre si es una respuesta en hilo. [desde]: el context de la
  // pantalla del hilo, para que las reglas y los avisos salgan ahí. Devuelve si se mandó.
  Future<bool> _enviar({Map<String, dynamic>? tarjeta, bool bug = false, String? texto, int? respondeA, BuildContext? desde}) async {
    final t = (texto ?? _texto.text).trim();
    final donde = desde ?? context;
    if (t.isEmpty && tarjeta == null) return false;
    if (!_esSoporte && !await aceptoReglas(donde)) return false;
    if (!mounted) return false;
    setState(() => _enviando = true);
    try {
      final nuevo = await db
          .from('mensajes')
          .insert({
            'sala': widget.sala,
            if (_esSoporte) 'hilo': widget.hilo,
            'texto': t,
            'tarjeta': ?tarjeta,
            'es_bug': bug,
            'responde_a': ?respondeA,
          })
          .select()
          .single();
      // Se pinta ya, sin esperar a realtime.
      _poner(nuevo);
      if (texto == null && tarjeta == null) _texto.clear();
      return true;
    } catch (e) {
      if (donde.mounted) _aviso(donde, _error(e));
      return false;
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
            Text(tr('PRESUMIR', 'SHOW OFF'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (ultima != null)
              ListTile(
                leading: Emoji(tipoEmoji(ultima['tipo'] as int?), tamano: 30),
                title: Text(tr('Mi última cagada: ${tipos[ultima['tipo']]?.$2}', 'My latest poop: ${tipos[ultima['tipo']]?.$2}')),
                onTap: () => Navigator.pop(context, {'tipo': 'cagada', 'id': ultima['id']}),
              ),
            for (final h in logrados)
              ListTile(
                leading: const Emoji('👑', tamano: 30),
                title: Text(tr('Llegué a $h cagadas', 'I hit $h poops')),
                onTap: () => Navigator.pop(context, {'tipo': 'hito', 'n': h}),
              ),
            for (final d in mios)
              ListTile(
                leading: Emoji(d.emoji, tamano: 30),
                title: Text(tr('Desbloqueé ${d.nombre}', 'I unlocked ${d.nombre}')),
                onTap: () => Navigator.pop(context, {'tipo': 'desbloqueo', 'emoji': d.emoji}),
              ),
            if (ultima == null && logrados.isEmpty && mios.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('Todavía no tienes nada que presumir. ¡A cagar!', 'Nothing to show off yet. Go drop a deuce!')),
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
        title: Text(tr('Reportar un error 🐞', 'Report a bug 🐞')),
        content: TextField(
          controller: que,
          autofocus: true,
          maxLines: 5,
          maxLength: 800,
          decoration: InputDecoration(hintText: tr('¿Qué pasó y qué estabas haciendo?', 'What happened and what were you doing?')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCELAR', 'CANCEL'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ENVIAR', 'SEND'))),
        ],
      ),
    );
    if (enviar != true || que.text.trim().isEmpty) return;
    final info = await PackageInfo.fromPlatform();
    final equipo = 'v${info.version} (${info.buildNumber}) · ${Platform.operatingSystemVersion}';
    await _enviar(bug: true, texto: '${que.text.trim()}\n\n— $equipo');
  }

  // [enHilo]: el menú se abre desde la pantalla de un hilo (ahí no se menciona ni se abre otro hilo).
  Future<void> _opciones(Map<String, dynamic> m, {bool enHilo = false}) async {
    final suyo = m['user_id'] == _yo;
    final esRespuesta = m['responde_a'] != null;
    final mias = {for (final e in _reaccionesRapidas) if (_reacciones[m['id']]?[e]?.contains(_yo) ?? false) e};
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_hayReacciones && m['id'] is int)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final e in _reaccionesRapidas)
                  InkWell(
                    borderRadius: BorderRadius.circular(radio),
                    onTap: () => Navigator.pop(context, 'reaccion:$e'),
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: mias.contains(e) ? acento.withValues(alpha: .18) : null,
                        border: Border.all(color: mias.contains(e) ? acento : paleta(context).borde),
                        borderRadius: BorderRadius.circular(radio),
                      ),
                      child: Emoji(e, tamano: 26),
                    ),
                  ),
              ]),
            ),
          if (_hayHilos && !enHilo && !esRespuesta && m['id'] is int)
            ListTile(leading: const Icon(Icons.forum_outlined), title: Text(tr('Responder en hilo', 'Reply in thread')), onTap: () => Navigator.pop(context, 'hilo')),
          if (!enHilo && !suyo && !_esSoporte && _amigos.any((a) => a['id'] == m['user_id']))
            ListTile(leading: const Icon(Icons.alternate_email), title: Text(tr('Mencionar', 'Mention')), onTap: () => Navigator.pop(context, 'mencionar')),
          if (!suyo && !_esSoporte)
            ListTile(leading: const Icon(Icons.flag_outlined), title: Text(tr('Reportar mensaje', 'Report message')), onTap: () => Navigator.pop(context, 'reportar')),
          if (!suyo && !_esSoporte && !_admins.contains(m['user_id']))
            ListTile(leading: const Icon(Icons.block), title: Text(tr('Bloquear a esta persona', 'Block this person')), onTap: () => Navigator.pop(context, 'bloquear')),
          if (_soyAdmin && !_esSoporte && !esRespuesta)
            _estaFijado(m)
                ? ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(tr('Desfijar', 'Unpin')), onTap: () => Navigator.pop(context, 'desfijar'))
                : ListTile(leading: const Icon(Icons.push_pin), title: Text(tr('Fijar arriba como anuncio', 'Pin on top as announcement')), onTap: () => Navigator.pop(context, 'fijar')),
          if (_soyAdmin && !_esSoporte)
            ListTile(
              leading: Icon(m['oculto'] == true ? Icons.visibility : Icons.visibility_off),
              title: Text(m['oculto'] == true ? tr('Volver a mostrar', 'Show again') : tr('Ocultar a todos', 'Hide from everyone')),
              onTap: () => Navigator.pop(context, 'ocultar'),
            ),
          if (suyo || _soyAdmin)
            ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr('Borrar', 'Delete')), onTap: () => Navigator.pop(context, 'borrar')),
        ]),
      ),
    );
    if (accion == null || !mounted) return;
    if (accion.startsWith('reaccion:')) return _reaccionar(m, accion.substring('reaccion:'.length));
    try {
      switch (accion) {
        case 'hilo':
          _abrirHilo(m);
        case 'mencionar':
          _texto.selection = TextSelection.collapsed(offset: _texto.text.length);
          _mencionar(_amigos.firstWhere((a) => a['id'] == m['user_id']));
        case 'reportar':
          final motivo = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // El primero es lo que se guarda en la base de datos; el segundo, lo que se ve en inglés.
                for (final (mo, moEn) in const [
                  ('Odio o insultos', 'Hate or insults'),
                  ('Acoso', 'Harassment'),
                  ('Contenido sexual', 'Sexual content'),
                  ('Spam o estafa', 'Spam or scam'),
                  ('Datos personales', 'Personal info'),
                  ('Otro', 'Other'),
                ])
                  ListTile(title: Text(tr(mo, moEn)), onTap: () => Navigator.pop(context, mo)),
              ]),
            ),
          );
          if (motivo == null) return;
          await db.from('mensaje_reportes').insert({'mensaje_id': m['id'], 'motivo': motivo});
          if (mounted) _aviso(context, tr('Reportado. Gracias 🙏', 'Reported. Thanks 🙏'));
        case 'bloquear':
          await db.from('bloqueos').insert({'bloqueado': m['user_id']});
          if (mounted) _aviso(context, tr('Bloqueado. Ya no verás sus mensajes', "Blocked. You won't see their messages anymore"));
        case 'ocultar':
          final r = await db.from('mensajes').update({'oculto': m['oculto'] != true}).eq('id', m['id']).select().single();
          _poner(r);
        case 'fijar':
          final dias = await showModalBottomSheet<int>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(title: Text(tr('📌 ¿Cuánto tiempo se queda arriba?', '📌 How long does it stay on top?'))),
                for (final (d, nombre) in [(1, tr('1 día', '1 day')), (3, tr('3 días', '3 days')), (7, tr('1 semana', '1 week')), (30, tr('1 mes', '1 month'))])
                  ListTile(title: Text(nombre), onTap: () => Navigator.pop(context, d)),
              ]),
            ),
          );
          if (dias == null) return;
          await _fijar(m, DateTime.now().toUtc().add(Duration(days: dias)));
          if (mounted) _aviso(context, tr('Fijado arriba 📌', 'Pinned on top 📌'));
        case 'desfijar':
          await _fijar(m, null);
        case 'borrar':
          await db.from('mensajes').delete().eq('id', m['id']);
          _borrados.add(m['id'] as int);
          if (mounted) setState(() => _quitar(m['id'] as int));
      }
    } on PostgrestException catch (e) {
      if (mounted) _aviso(context, e.code == '23505' ? tr('Ya lo habías reportado', "You've already reported it") : _error(e));
    }
  }

  void _abrirHilo(Map<String, dynamic> m) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PantallaHilo(sala: this, padre: m)));
  }

  // Un mensaje de la lista (de la sala o de un hilo) con su menú, su animación de llegada, sus
  // reacciones y, si es padre, el resumen del hilo. [anterior]: el mensaje de arriba, para pegar
  // burbujas seguidas de la misma persona.
  Widget _mensaje(Map<String, dynamic> m, {Map<String, dynamic>? anterior, bool enHilo = false}) {
    final id = m['id'] as int;
    final mio = m['user_id'] == _yo;
    final llego = _llegada[id];
    final hora = DateTime.tryParse('${m['created_at']}'), horaAnterior = DateTime.tryParse('${anterior?['created_at']}');
    final seguido = anterior != null &&
        anterior['user_id'] == m['user_id'] &&
        m['tarjeta'] == null &&
        anterior['tarjeta'] == null &&
        hora != null &&
        horaAnterior != null &&
        hora.difference(horaAnterior).abs() < const Duration(minutes: 5);
    return GestureDetector(
      key: ValueKey<int>(id),
      onLongPress: () => _opciones(m, enHilo: enHilo),
      child: _Aparecer(
        animar: llego != null && DateTime.now().difference(llego) < const Duration(seconds: 1),
        desdeDerecha: mio,
        child: _Burbuja(
          mensaje: m,
          perfil: _perfiles[m['user_id']],
          mio: mio,
          admin: _admins.contains(m['user_id']),
          meMencionan: _mencionaA(m['texto'] as String?),
          seguido: seguido,
          pie: _pie(m, mio: mio, conHilo: !enHilo),
        ),
      ),
    );
  }

  // Lo de abajo de la burbuja: chips de reacciones y, si tiene respuestas, el resumen del hilo.
  Widget? _pie(Map<String, dynamic> m, {required bool mio, required bool conHilo}) {
    final id = m['id'] as int;
    final del = _reacciones[id] ?? const {};
    final chips = [
      for (final e in _reaccionesRapidas)
        if ((del[e]?.length ?? 0) > 0)
          _ChipReaccion(
            key: ValueKey(e),
            emoji: e,
            cuantos: del[e]!.length,
            mia: del[e]!.contains(_yo),
            rebote: _rebote['$id $e'],
            onTap: () => _reaccionar(m, e),
          ),
    ];
    final respuestas = conHilo ? (_respuestas[id]?.values.toList() ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
    if (chips.isEmpty && respuestas.isEmpty) return null;
    final quienes = <String>[];
    for (final r in respuestas.toList()..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int))) {
      final u = r['user_id'] as String;
      if (!quienes.contains(u)) quienes.add(u);
      if (quienes.length == 3) break;
    }
    _pedirPerfiles(quienes);
    final tarjeta = m['tarjeta'] != null;
    final alinear = tarjeta ? WrapAlignment.center : (mio ? WrapAlignment.end : WrapAlignment.start);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: tarjeta ? CrossAxisAlignment.center : (mio ? CrossAxisAlignment.end : CrossAxisAlignment.start),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chips.isNotEmpty) Wrap(alignment: alinear, spacing: 4, runSpacing: 4, children: chips),
          if (respuestas.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: chips.isEmpty ? 0 : 4),
              child: _ResumenHilo(
                cuantas: respuestas.length,
                perfiles: [for (final u in quienes) _perfiles[u]],
                onTap: () => _abrirHilo(m),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _fijar(Map<String, dynamic> m, DateTime? hasta) async {
    final r = await db.from('mensajes').update({'fijado_hasta': hasta?.toIso8601String()}).eq('id', m['id']).select().single();
    _poner(r);
    await _cargarFijados();
  }

  Future<void> _abrirFijado(Map<String, dynamic> m) async {
    final hasta = DateTime.parse(m['fijado_hasta'] as String).toLocal();
    final tarjeta = m['tarjeta'] as Map<String, dynamic>?;
    final texto = (m['texto'] as String?) ?? '';
    final desfijar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('📌 ${tr('ANUNCIO', 'ANNOUNCEMENT')} · ${_perfiles[m['user_id']]?['username'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (tarjeta != null) ...[_Tarjeta(tarjeta), const SizedBox(height: 8)],
            if (texto.isNotEmpty) _TextoConLinks(texto),
            const SizedBox(height: 12),
            Text(tr('Fijado hasta el ${hasta.day}/${hasta.month}', 'Pinned until ${hasta.month}/${hasta.day}'), style: numeros(context, tamano: 12, color: paleta(context).textoSuave)),
          ]),
        ),
        actions: [
          if (_soyAdmin) TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('DESFIJAR', 'UNPIN'))),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('VALE', 'OK'))),
        ],
      ),
    );
    if (desfijar == true) {
      try {
        await _fijar(m, null);
      } on PostgrestException catch (e) {
        if (mounted) _aviso(context, trServidor(e.message));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = paleta(context);
    final fijados = _fijadosVigentes;
    return Column(
      children: [
        if (fijados.isNotEmpty)
          _BarraFijada(
            mensaje: fijados[_verFijado % fijados.length],
            indice: _verFijado % fijados.length,
            total: fijados.length,
            onTap: () => _abrirFijado(fijados[_verFijado % fijados.length]),
            onSiguiente: () => setState(() => _verFijado++),
          ),
        if (_esSoporte && widget.hilo == _yo)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(color: p.suave, border: Border(bottom: BorderSide(color: p.borde))),
            child: Row(children: [
              Expanded(child: Text(tr('Escríbenos dudas, ideas o errores. Te respondemos aquí.', 'Write us questions, ideas or bugs. We reply here.'))),
              TextButton.icon(onPressed: _reportarError, icon: const Icon(Icons.bug_report_outlined), label: Text(tr('ERROR', 'BUG'))),
            ]),
          ),
        if (_reconectando && _cargado)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: p.suave,
            child: Text(tr('Reconectando…', 'Reconnecting…'), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave, fontSize: 12)),
          ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (!_cargado) {
                if (_errorCarga == null) return const Center(child: CircularProgressIndicator());
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('No se pudo cargar el chat', "Couldn't load the chat"), style: TextStyle(color: p.textoSuave)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _errorCarga = null);
                        _conectar();
                        _cargar();
                      },
                      child: Text(tr('REINTENTAR', 'RETRY')),
                    ),
                  ]),
                );
              }
              final lista = _lista;
              _pedirPerfiles([_yo, ...lista.map((m) => m['user_id'] as String)]);
              if (lista.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Text(_esSoporte ? tr('Todavía no hay mensajes', 'No messages yet') : tr('Nadie ha dicho nada. Estrena $nombreSala 🚽', 'Nobody has said anything. Break the ice in $nombreSala 🚽'),
                          style: TextStyle(color: p.textoSuave)),
                    ),
                  ]),
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: lista.length,
                // Con llaves por id, un mensaje nuevo abajo no rehace (ni re-anima) los de arriba.
                findChildIndexCallback: (llave) {
                  if (llave is! ValueKey<int>) return null;
                  final i = lista.indexWhere((m) => m['id'] == llave.value);
                  return i < 0 ? null : i;
                },
                itemBuilder: (context, i) => _mensaje(lista[i], anterior: i + 1 < lista.length ? lista[i + 1] : null),
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
                IconButton(onPressed: _enviando ? null : _compartir, icon: const Icon(Icons.emoji_events_outlined), tooltip: tr('Presumir', 'Show off')),
              if (_esSoporte) const SizedBox(width: 8),
              IconButton(onPressed: () => ponerEmoji(context, _texto), icon: const Icon(Icons.emoji_emotions_outlined), tooltip: tr('Emojis', 'Emojis')),
              Expanded(
                child: TextField(
                  controller: _texto,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: _esSoporte ? tr('Escribe algo…', 'Write something…') : tr('Escribe algo… (@ para mencionar a un amigo)', 'Write something… (@ to mention a friend)'), counterText: '', isDense: true),
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

/// La franja de arriba del chat con el anuncio fijado. Con varios, se pasa al siguiente.
class _BarraFijada extends StatelessWidget {
  const _BarraFijada({required this.mensaje, required this.indice, required this.total, required this.onTap, required this.onSiguiente});

  final Map<String, dynamic> mensaje;
  final int indice, total;
  final VoidCallback onTap, onSiguiente;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final texto = (mensaje['texto'] as String?)?.replaceAll('\n', ' ') ?? '';
    return Material(
      color: acento.withValues(alpha: .14),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: const BorderSide(color: acento, width: 4), bottom: BorderSide(color: p.borde)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            const Emoji('📌', tamano: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('ANUNCIO', 'ANNOUNCEMENT'), style: numeros(context, tamano: 10, weight: FontWeight.w900).copyWith(letterSpacing: 1.2)),
                Text(texto.isEmpty ? tr('Toca para verlo', 'Tap to view') : texto, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (total > 1)
              TextButton(
                onPressed: onSiguiente,
                style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                child: Text('${indice + 1}/$total ›', style: numeros(context, tamano: 12, weight: FontWeight.w800)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.mensaje,
    required this.perfil,
    required this.mio,
    required this.admin,
    this.meMencionan = false,
    this.seguido = false,
    this.pie,
  });

  final Map<String, dynamic> mensaje;
  final Map<String, dynamic>? perfil;
  final bool mio;
  final bool admin;
  final bool meMencionan;
  // Mismo autor que el de arriba hace poco: sin avatar ni nombre, pegado al anterior.
  final bool seguido;
  // Reacciones y resumen del hilo, debajo de la burbuja.
  final Widget? pie;

  void _verPerfil(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: mensaje['user_id'])));

  Widget _avatar(BuildContext context, double tamano) => GestureDetector(
        onTap: () => _verPerfil(context),
        child: perfil == null ? Emoji('💩', tamano: tamano) : Avatar(perfil!, tamano: tamano),
      );

  Widget _nombre(BuildContext context, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: GestureDetector(
            onTap: () => _verPerfil(context),
            child: Text(perfil?['username'] ?? '…',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ),
        ),
        if (admin) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: acento,
            child: const Text('ADMIN', style: TextStyle(color: acentoTexto, fontSize: 9, fontWeight: FontWeight.w900)),
          ),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final tarjeta = mensaje['tarjeta'] as Map<String, dynamic>?;
    final cuerpo = (mensaje['texto'] as String?) ?? '';
    final bug = mensaje['es_bug'] == true;
    final fijado = mensaje['fijado_hasta'] != null && (DateTime.tryParse('${mensaje['fijado_hasta']}')?.isAfter(DateTime.now()) ?? false);
    final oculto = mensaje['oculto'] == true;
    final etiquetaOculto = Text(tr('Oculto por reportes', 'Hidden due to reports'), style: TextStyle(color: mio ? acentoTexto.withValues(alpha: .7) : p.textoSuave, fontSize: 11));

    // Las tarjetas (hitos, rachas, retos…) van al centro y a lo ancho, de quien sea.
    if (tarjeta != null) {
      return Opacity(
        opacity: oculto ? .4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _avatar(context, 18),
              const SizedBox(width: 6),
              Flexible(child: _nombre(context)),
              const SizedBox(width: 8),
              Text(_hora(mensaje['created_at']), style: numeros(context, tamano: 10, color: p.textoSuave)),
            ]),
            const SizedBox(height: 6),
            _Tarjeta(tarjeta),
            if (cuerpo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: _TextoConLinks(cuerpo)),
            if (oculto) etiquetaOculto,
            ?pie,
          ]),
        ),
      );
    }

    final tinta = mio ? acentoTexto : p.texto;
    final borde = bug
        ? Border.all(color: const Color(0xFFB3261E), width: 2)
        : meMencionan
            ? Border.all(color: acento, width: 2)
            : Border.all(color: mio ? acento : p.borde);
    final conCabecera = (!mio && !seguido) || bug || fijado;
    final burbuja = Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 5),
      decoration: BoxDecoration(color: mio ? acento : p.tarjeta, borderRadius: BorderRadius.circular(radio), border: borde),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: tinta),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (conCabecera)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!mio) Flexible(child: _nombre(context, color: tinta)),
                if (bug) const Padding(padding: EdgeInsets.only(left: 6), child: Emoji('🐞', tamano: 14)),
                if (fijado) const Padding(padding: EdgeInsets.only(left: 6), child: Emoji('📌', tamano: 14)),
              ]),
            ),
          // La hora va pegada al final del texto, y baja de renglón si no cabe (como en WhatsApp).
          Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
            if (cuerpo.isNotEmpty) _TextoConLinks(cuerpo, colorLink: mio ? acentoTexto : null),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(_hora(mensaje['created_at']), style: numeros(context, tamano: 10, color: mio ? acentoTexto.withValues(alpha: .65) : p.textoSuave)),
            ),
          ]),
          if (oculto) etiquetaOculto,
        ]),
      ),
    );

    final arriba = seguido ? 1.0 : 6.0;
    return Opacity(
      opacity: oculto ? .4 : 1,
      child: mio
          ? Padding(
              padding: EdgeInsets.fromLTRB(56, arriba, 10, 1),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [burbuja, ?pie]),
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(8, arriba, 48, 1),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 36, child: seguido ? null : Align(alignment: Alignment.topLeft, child: _avatar(context, 30))),
                const SizedBox(width: 6),
                Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [burbuja, ?pie])),
              ]),
            ),
    );
  }
}

/// Un mensaje recién llegado entra deslizándose desde su lado (o solo aparece, según el movimiento).
class _Aparecer extends StatefulWidget {
  const _Aparecer({required this.animar, required this.desdeDerecha, required this.child});

  final bool animar;
  final bool desdeDerecha;
  final Widget child;

  @override
  State<_Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<_Aparecer> with SingleTickerProviderStateMixin {
  AnimationController? _control;
  Animation<double>? _curva;

  @override
  void initState() {
    super.initState();
    if (!widget.animar) return;
    final c = _control = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _curva = CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
    c.forward();
  }

  @override
  void dispose() {
    _control?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curva = _curva;
    if (curva == null) return widget.child;
    return switch (movimiento(context)) {
      Movimiento.nada => widget.child,
      Movimiento.simple => FadeTransition(opacity: curva, child: widget.child),
      Movimiento.completo => SlideTransition(
          position: Tween(begin: Offset(widget.desdeDerecha ? .08 : -.08, .15), end: Offset.zero).animate(curva),
          child: FadeTransition(opacity: curva, child: widget.child),
        ),
    };
  }
}

/// Chip de una reacción: emoji y cuántos. Si es mía va con el acento y tocarla la quita.
/// Brinca cuando la acabo de poner (solo con movimiento completo).
class _ChipReaccion extends StatefulWidget {
  const _ChipReaccion({super.key, required this.emoji, required this.cuantos, required this.mia, required this.onTap, this.rebote});

  final String emoji;
  final int cuantos;
  final bool mia;
  final VoidCallback onTap;
  // Cuándo la puse yo; si fue hace un momento, brinca.
  final DateTime? rebote;

  @override
  State<_ChipReaccion> createState() => _ChipReaccionState();
}

class _ChipReaccionState extends State<_ChipReaccion> with SingleTickerProviderStateMixin {
  late final _control = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  var _completo = false;

  bool get _reciente => widget.rebote != null && DateTime.now().difference(widget.rebote!) < const Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _completo && _reciente) _control.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(_ChipReaccion viejo) {
    super.didUpdateWidget(viejo);
    if (_completo && _reciente && (widget.rebote != viejo.rebote || widget.cuantos != viejo.cuantos)) _control.forward(from: 0);
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _completo = movimiento(context) == Movimiento.completo;
    final p = paleta(context);
    final chip = InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(radio),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: widget.mia ? acento.withValues(alpha: .18) : p.tarjeta,
          border: Border.all(color: widget.mia ? acento : p.borde),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Emoji(widget.emoji, tamano: 16),
          const SizedBox(width: 4),
          Text('${widget.cuantos}', style: numeros(context, tamano: 12, weight: FontWeight.w800, color: p.texto)),
        ]),
      ),
    );
    return AnimatedBuilder(
      animation: _control,
      builder: (context, child) => Transform.scale(scale: 1 + .3 * sin(pi * _control.value), child: child),
      child: chip,
    );
  }
}

/// "N respuestas" con las caras de los últimos que respondieron. Abre el hilo.
class _ResumenHilo extends StatelessWidget {
  const _ResumenHilo({required this.cuantas, required this.perfiles, required this.onTap});

  final int cuantas;
  final List<Map<String, dynamic>?> perfiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radio),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 4, 3),
        decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final perfil in perfiles)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: perfil == null ? const Emoji('💩', tamano: 18) : Avatar(perfil, tamano: 18),
            ),
          const SizedBox(width: 3),
          Text(
            cuantas == 1 ? tr('1 respuesta', '1 reply') : tr('$cuantas respuestas', '$cuantas replies'),
            style: TextStyle(color: p.texto, fontSize: 12, fontWeight: FontWeight.w800),
          ),
          Icon(Icons.chevron_right, size: 16, color: p.textoSuave),
        ]),
      ),
    );
  }
}

/// Un hilo: el mensaje de arriba, sus respuestas en orden y su propia caja de texto. Los datos
/// son de la sala (realtime, reacciones, perfiles); esta pantalla solo los pinta.
class _PantallaHilo extends StatefulWidget {
  const _PantallaHilo({required this.sala, required this.padre});

  final _SalaState sala;
  final Map<String, dynamic> padre;

  @override
  State<_PantallaHilo> createState() => _PantallaHiloState();
}

class _PantallaHiloState extends State<_PantallaHilo> {
  final _texto = TextEditingController();
  final _scroll = ScrollController();
  var _cargando = true;
  var _cerrado = false;
  var _cuantas = 0;

  _SalaState get _sala => widget.sala;
  int get _id => widget.padre['id'] as int;

  @override
  void initState() {
    super.initState();
    _sala._version.addListener(_cambio);
    _cuantas = _sala._respuestas[_id]?.length ?? 0;
    _sala._cargarRespuestas([_id]).whenComplete(() {
      if (!mounted) return;
      setState(() => _cargando = false);
      _alFinal();
    });
  }

  @override
  void dispose() {
    _sala._version.removeListener(_cambio);
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _cambio() {
    if (!mounted || _cerrado) return;
    // Borraron el mensaje de arriba (o se cerró la sala): el hilo ya no existe.
    if (_sala._borrados.contains(_id) || !_sala.mounted) {
      _cerrado = true;
      Navigator.of(context).maybePop();
      return;
    }
    final n = _sala._respuestas[_id]?.length ?? 0;
    final abajo = !_scroll.hasClients || _scroll.position.extentAfter < 80;
    final bajar = n > _cuantas && abajo;
    _cuantas = n;
    setState(() {});
    if (bajar) _alFinal();
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _mandar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty) return;
    final ok = await _sala._enviar(texto: texto, respondeA: _id, desde: context);
    if (!mounted) return;
    if (ok) {
      _texto.clear();
      _alFinal();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final padre = _sala._porId[_id] ?? widget.padre;
    final respuestas = (_sala._respuestas[_id]?.values.toList() ?? <Map<String, dynamic>>[])..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    _sala._pedirPerfiles([padre['user_id'] as String, ...respuestas.map((m) => m['user_id'] as String)]);
    return Scaffold(
      appBar: AppBar(title: Text(tr('HILO', 'THREAD'))),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _sala._mensaje(padre, enHilo: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(children: [
                  Text(
                    respuestas.length == 1 ? tr('1 RESPUESTA', '1 REPLY') : tr('${respuestas.length} RESPUESTAS', '${respuestas.length} REPLIES'),
                    style: numeros(context, tamano: 11, weight: FontWeight.w800, color: p.textoSuave),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: p.borde, height: 1)),
                ]),
              ),
              if (respuestas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Center(
                    child: _cargando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('Nadie ha respondido todavía. Sé el primero.', 'No replies yet. Be the first.'), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
                  ),
                ),
              for (var i = 0; i < respuestas.length; i++) _sala._mensaje(respuestas[i], anterior: i > 0 ? respuestas[i - 1] : null, enHilo: true),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.borde))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(onPressed: () => ponerEmoji(context, _texto), icon: const Icon(Icons.emoji_emotions_outlined), tooltip: tr('Emojis', 'Emojis')),
              Expanded(
                child: TextField(
                  controller: _texto,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: tr('Responder en el hilo…', 'Reply in thread…'), counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: _sala._enviando ? null : _mandar, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
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
      'hito' => ('👑', tr('LLEGÓ A ${t['n']} CAGADAS', 'HIT ${t['n']} POOPS'), t['reina'] == true ? tr('Arrodíllense ante la reina', 'Bow down to the queen') : tr('Arrodíllense ante el rey', 'Bow down to the king')),
      'desbloqueo' => (
          t['emoji'] as String,
          tr('DESBLOQUEÓ ${(desbloqueos.where((d) => d.emoji == t['emoji']).firstOrNull?.nombre ?? '').toUpperCase()}', 'UNLOCKED ${(desbloqueos.where((d) => d.emoji == t['emoji']).firstOrNull?.nombre ?? '').toUpperCase()}'),
          tr('A las ${t['minimo']} cagadas', 'At ${t['minimo']} poops'),
        ),
      'cagada' => (
          tipoEmoji(t['mojon'] as int?),
          tr('CAGADA #${t['n']}', 'POOP #${t['n']}'),
          tr('Le salió: ${tipos[t['mojon']]?.$2 ?? '?'}', 'Came out as: ${tipos[t['mojon']]?.$2 ?? '?'}') +
              (pesos[t['peso']] == null ? '' : ' · ${tr('Peso', 'Weight')}: ${pesos[t['peso']]!.$1} ${pesos[t['peso']]!.$2}'),
        ),
      'racha' => (
          estiloRacha(t['n'] as int).$2,
          nombreRacha(t['n'] as int) ?? '',
          tr('Cagó ${t['n']} veces hoy', 'Pooped ${t['n']} times today'),
        ),
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
            Text(titulo,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  fontStyle: t['tipo'] == 'racha' ? FontStyle.italic : null,
                  color: t['tipo'] == 'racha' ? estiloRacha(t['n'] as int).$1.last : null,
                )),
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
  const _TextoConLinks(this.texto, {this.colorLink});

  final String texto;
  // Sobre la burbuja amarilla el azul no se lee: ahí los links van del color del texto.
  final Color? colorLink;

  Future<void> _abrir(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Abrir link?', 'Open link?')),
        content: Text(tr('Vas a salir de Rey Cagón hacia:\n\n${uri.host}\n\nNo pongas contraseñas ni datos de pago en páginas que te manden por chat.', "You're leaving King of the Throne for:\n\n${uri.host}\n\nDon't enter passwords or payment info on pages sent to you in chat.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCELAR', 'CANCEL'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ABRIR', 'OPEN'))),
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
        style: TextStyle(decoration: TextDecoration.underline, color: colorLink ?? const Color(0xFF4DA3FF)),
        recognizer: TapGestureRecognizer()..onTap = () => _abrir(context, url),
      ));
      desde = m.end;
    }
    if (desde < texto.length) partes.add(TextSpan(text: texto.substring(desde)));
    return Text.rich(TextSpan(style: base, children: partes));
  }
}

// Los del teclado de siempre más los del baño. Se pintan con la fuente del sistema y, si es
// vieja, con la de respaldo del tema (los nuevos también se ven).
const _emojisChat = [
  '💩', '🚽', '🧻', '👑', '🤴', '👸', '🔥', '💥', '☢️', '🏆', '🥇', '💪',
  '😂', '🤣', '😭', '😅', '😎', '🤩', '😳', '🥵', '🤢', '🤮', '😤', '😈',
  '🙄', '🤔', '🫡', '🫣', '🫠', '🥲', '😏', '🤫', '🤐', '💀', '👀', '🙈',
  '👍', '👎', '👏', '🙌', '🙏', '🤝', '✌️', '🤞', '🫶', '❤️', '💯', '✨',
  '🍌', '🌶️', '🌽', '☕', '🍺', '🍔', '🌮', '🍕', '🚿', '🪠', '🧼', '🐋',
];

/// Hoja con emojis que se insertan donde está el cursor de [texto]. Se queda abierta para poner varios.
Future<void> ponerEmoji(BuildContext context, TextEditingController texto) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: GridView.count(
        crossAxisCount: 8,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: [
          for (final e in _emojisChat)
            InkWell(
              onTap: () {
                final sel = texto.selection;
                final inicio = sel.isValid ? sel.start : texto.text.length;
                final fin = sel.isValid ? sel.end : texto.text.length;
                texto.value = TextEditingValue(
                  text: texto.text.replaceRange(inicio, fin, e),
                  selection: TextSelection.collapsed(offset: inicio + e.length),
                );
              },
              child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
            ),
        ],
      ),
    ),
  );
}
