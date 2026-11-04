import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart' show Avatar;
import 'chat.dart' show Sala;
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show conReintento, db, textoError;
import 'perfil.dart' show PantallaPerfil;
import 'teclado_emojis.dart' show panelEmojisAbierto;
import 'tema.dart';
import 'vivo.dart' show Cargando;

// Chats privados entre dos personas (supabase/migrations/…_privados.sql). Van en public.mensajes con
// sala 'dm:<uuidA>:<uuidB>' (minúsculas, A < B). Quién te puede escribir lo decide profiles.mensajes_de:
// 'todos', 'amigos' (la gente que tú sigues) o 'nadie'; a quien ya te escribió siempre le puedes contestar.

/// La sala de la pareja: la misma sin importar quién la abre. Igual que public.dm_sala() en la base.
String salaDm(String yo, String otro) {
  final a = yo.toLowerCase(), b = otro.toLowerCase();
  return a.compareTo(b) < 0 ? 'dm:$a:$b' : 'dm:$b:$a';
}

bool esSalaDm(String sala) => sala.startsWith('dm:');

/// El otro lado de la pareja, o null si la sala no es dm o no estoy en ella.
String? otroDeSala(String sala, String yo) {
  final partes = sala.split(':');
  if (partes.length != 3 || partes[0] != 'dm' || partes[1].isEmpty || partes[2].isEmpty) return null;
  final y = yo.toLowerCase();
  if (partes[1] == y && partes[2] != y) return partes[2];
  if (partes[2] == y && partes[1] != y) return partes[1];
  return null;
}

/// Sin leer: el último mensaje es del otro y es más nuevo que el último que vi en esa sala.
bool privadoSinLeer({required int ultimo, required String? autor, required String yo, required int visto}) =>
    autor != null && autor != yo && ultimo > visto;

/// Llave en SharedPreferences del último id visto en una sala privada (como soporte_visto).
String clavePrivadoVisto(String sala) => 'privado_visto_$sala';

/// Falta la migración: la RPC o la columna no existen todavía en la base.
bool faltaPrivados(Object e) =>
    e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883' || e.code == '42703' || e.code == 'PGRST204');

/// El texto de un error al mandar un privado: si la base no deja (ya no te acepta mensajes), dilo claro.
String errorPrivado(Object e) => e is PostgrestException && e.code == '42501'
    ? tr('Esta persona no recibe tus mensajes ahora.', "This person isn't taking your messages right now.")
    : textoError(e);

/// Puntito en la pestaña del baño y en la fila de Privados.
final privadosSinLeer = ValueNotifier<bool>(false);

/// Si la base ya tiene los privados. Se apaga si falta la migración: se esconden la fila y el botón.
final privadosDisponibles = ValueNotifier<bool>(true);

/// La sala privada que está abierta en pantalla: un push de ella no se muestra ni prende el puntito.
String? privadoAbierto;

Future<List<Map<String, dynamic>>> _bandeja() async {
  final r = await conReintento(() => db.rpc('dm_bandeja'));
  return [for (final f in r as List) Map<String, dynamic>.from(f as Map)];
}

bool _sinLeer(Map<String, dynamic> f, SharedPreferences prefs, String yo) =>
    f['sala'] != privadoAbierto &&
    privadoSinLeer(
      ultimo: (f['mensaje_id'] as num?)?.toInt() ?? 0,
      autor: f['autor'] as String?,
      yo: yo,
      visto: prefs.getInt(clavePrivadoVisto('${f['sala']}')) ?? 0,
    );

/// Revisa la bandeja y prende o apaga el puntito. Al abrir, al volver a la app y al llegar un push.
Future<void> revisarPrivados() async {
  final yo = db.auth.currentUser?.id;
  if (yo == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final filas = await _bandeja();
    privadosDisponibles.value = true;
    privadosSinLeer.value = filas.any((f) => _sinLeer(f, prefs, yo));
  } catch (e) {
    if (faltaPrivados(e)) {
      privadosDisponibles.value = false;
      privadosSinLeer.value = false;
    }
  }
}

/// Guarda como visto el último mensaje de la sala.
Future<void> marcarPrivadoVisto(String sala) async {
  try {
    final r = await conReintento(() => db.from('mensajes').select('id').eq('sala', sala).order('id', ascending: false).limit(1));
    if (r.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final id = r.first['id'] as int;
    if (id > (prefs.getInt(clavePrivadoVisto(sala)) ?? 0)) await prefs.setInt(clavePrivadoVisto(sala), id);
  } catch (_) {}
  await revisarPrivados();
}

/// Abre la conversación con esa persona. Se marca vista al entrar y al salir.
Future<void> abrirPrivado(BuildContext context, String otroId, String username) async {
  final sala = salaDm(db.auth.currentUser!.id, otroId);
  privadoAbierto = sala;
  marcarPrivadoVisto(sala);
  await Navigator.push(context, MaterialPageRoute(builder: (_) => _PantallaPrivado(sala: sala, otroId: otroId, username: username)));
  if (privadoAbierto == sala) privadoAbierto = null;
  await marcarPrivadoVisto(sala);
}

/// Desde un push o un aviso: solo se sabe la sala. Se busca el nombre y se abre.
Future<void> abrirPrivadoDeSala(BuildContext context, String sala) async {
  final otro = otroDeSala(sala, db.auth.currentUser!.id);
  if (otro == null) return;
  var nombre = tr('Privado', 'Private');
  try {
    final p = await conReintento(() => db.from('profiles').select('username').eq('id', otro).maybeSingle());
    nombre = p?['username'] as String? ?? nombre;
  } catch (_) {}
  if (context.mounted) await abrirPrivado(context, otro, nombre);
}

class _PantallaPrivado extends StatefulWidget {
  const _PantallaPrivado({required this.sala, required this.otroId, required this.username});

  final String sala, otroId, username;

  @override
  State<_PantallaPrivado> createState() => _PantallaPrivadoState();
}

class _PantallaPrivadoState extends State<_PantallaPrivado> {
  @override
  void dispose() {
    panelEmojisAbierto.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: widget.otroId))),
            child: Text(widget.username, overflow: TextOverflow.ellipsis),
          ),
        ),
        body: Sala(key: ValueKey(widget.sala), sala: widget.sala),
      );
}

/// La bandeja: una fila por conversación, la más reciente arriba.
class PantallaPrivados extends StatefulWidget {
  const PantallaPrivados({super.key});

  @override
  State<PantallaPrivados> createState() => _PantallaPrivadosState();
}

class _PantallaPrivadosState extends State<PantallaPrivados> {
  List<Map<String, dynamic>>? _filas;
  SharedPreferences? _prefs;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filas = await _bandeja();
      if (!mounted) return;
      setState(() {
        _filas = filas;
        _prefs = prefs;
        _error = null;
      });
      privadosSinLeer.value = filas.any((f) => _sinLeer(f, prefs, db.auth.currentUser!.id));
    } catch (e) {
      if (faltaPrivados(e)) privadosDisponibles.value = false;
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _abrir(Map<String, dynamic> f) async {
    await abrirPrivado(context, '${f['otro']}', (f['perfil'] as Map?)?['username'] as String? ?? '?');
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final filas = _filas;
    final yo = db.auth.currentUser!.id;
    Widget cuerpo;
    if (filas == null && _error != null) {
      final e = _error!;
      cuerpo = ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(textoError(e), textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _cargar, child: Text(tr('REINTENTAR', 'RETRY'))),
          ]),
        ),
      ]);
    } else if (filas == null) {
      cuerpo = const Center(child: Cargando());
    } else if (filas.isEmpty) {
      cuerpo = ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
          child: Column(children: [
            const Emoji('💌', tamano: 56),
            const SizedBox(height: 16),
            Text(tr('Todavía no tienes privados', "You don't have private messages yet"),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              tr('Entra al perfil de alguien y toca MENSAJE para escribirle.', "Open someone's profile and tap MESSAGE to write to them."),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textoSuave),
            ),
          ]),
        ),
      ]);
    } else {
      cuerpo = ListView.separated(
        padding: conBordeAbajo(context, EdgeInsets.zero),
        itemCount: filas.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: p.borde),
        itemBuilder: (context, i) {
          final f = filas[i];
          final perfil = Map<String, dynamic>.from((f['perfil'] as Map?) ?? {'id': f['otro']});
          final prefs = _prefs;
          final nuevo = prefs != null && _sinLeer(f, prefs, yo);
          final texto = '${f['texto'] ?? ''}'.replaceAll('\n', ' ');
          return ListTile(
            key: ValueKey('privado_${f['sala']}'),
            leading: Avatar(perfil, tamano: 36),
            title: Text(perfil['username'] as String? ?? '?', style: TextStyle(fontWeight: nuevo ? FontWeight.w800 : FontWeight.w600)),
            subtitle: TextoConEmojis(
              '${f['autor'] == yo ? tr('Tú: ', 'You: ') : ''}$texto',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: nuevo ? p.texto : p.textoSuave),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (f['created_at'] != null) Text(horaPrivado('${f['created_at']}'), style: numeros(context, tamano: 12, color: p.textoSuave)),
              if (nuevo) ...[const SizedBox(width: 8), const PuntoSinLeer()],
            ]),
            onTap: () => _abrir(f),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('PRIVADOS', 'PRIVATE'))),
      body: RefreshIndicator(onRefresh: _cargar, child: cuerpo),
    );
  }
}

/// Hora si es de hoy, día y hora si no.
String horaPrivado(String iso, {DateTime? ahora}) {
  final t = DateTime.parse(iso).toLocal();
  final hoy = ahora ?? DateTime.now();
  final hh = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == hoy.year && t.month == hoy.month && t.day == hoy.day) return hh;
  return enIngles ? '${t.month}/${t.day}' : '${t.day}/${t.month}';
}

/// El puntito rojo de sin leer, cuadrado como todo lo demás.
class PuntoSinLeer extends StatelessWidget {
  const PuntoSinLeer({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(radio)),
      );
}
