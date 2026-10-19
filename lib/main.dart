import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendario.dart';
import 'push.dart';
import 'recordatorio.dart';
import 'tipos.dart';

const supabaseUrl = 'https://TU-PROYECTO.supabase.co';
const supabaseKey = 'sb_publishable_...';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  try {
    await initRecordatorio();
    await initPush();
  } catch (_) {
    // Sin notificaciones la app igual sirve.
  }
  runApp(const ReyCagonApp());
}

final db = Supabase.instance.client;

/// Llama [onCambio] (agrupado en 400ms) cuando alguien registra o borra una cagada,
/// y cuando la app vuelve a primer plano. Devuelve con qué soltarlo en dispose().
VoidCallback escucharCagadas(String nombre, VoidCallback onCambio) {
  Timer? espera;
  void avisar() {
    espera?.cancel();
    espera = Timer(const Duration(milliseconds: 400), onCambio);
  }

  final canal = db
      .channel(nombre)
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'cagadas',
        callback: (_) => avisar(),
      )
      .subscribe();
  final ciclo = AppLifecycleListener(onResume: avisar);
  return () {
    espera?.cancel();
    ciclo.dispose();
    db.removeChannel(canal);
  };
}

class ReyCagonApp extends StatelessWidget {
  const ReyCagonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rey Cagón',
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, _) =>
            db.auth.currentSession == null ? const AuthScreen() : const HomeScreen(),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _signUp = false;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_signUp) {
        await db.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'username': _username.text.trim()},
        );
      } else {
        await db.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rey Cagón 👑💩')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_signUp)
            TextField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_signUp ? 'Crear cuenta' : 'Entrar'),
          ),
          TextButton(
            onPressed: () => setState(() => _signUp = !_signUp),
            child: Text(_signUp ? 'Ya tengo cuenta' : 'Crear cuenta nueva'),
          ),
          const SizedBox(height: 32),
          const Text(disclaimer, textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

const periods = {
  'week': 'Semana',
  'month': 'Mes',
  'quarter': 'Trimestre',
  'year': 'Año',
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _period = 'week';
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _hoy = [];
  bool _loading = true;
  late final VoidCallback _soltar;

  String get _me => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _soltar = escucharCagadas('home', () => _load(spinner: false));
    _avisoPrimeraVez();
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _avisoPrimeraVez() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('disclaimer_ok') ?? false) {
      await pedirPermisoNotificaciones().catchError((_) {});
      await registrarTelefono().catchError((_) {});
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Antes de empezar 👑'),
        content: const Text(disclaimer),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido, a cagar'),
          ),
        ],
      ),
    );
    await prefs.setBool('disclaimer_ok', true);
    await pedirPermisoNotificaciones().catchError((_) {});
    await registrarTelefono().catchError((_) {});
  }

  Future<void> _load({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) setState(() => _loading = true);
    try {
      final (data, hoy) = await (
        db.rpc('leaderboard', params: {'period': _period}),
        db.rpc('leaderboard', params: {'period': 'day'}),
      ).wait;
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data);
        _hoy = List<Map<String, dynamic>>.from(hoy);
      });
      final mio = _hoy.where((r) => r['user_id'] == _me).firstOrNull;
      reprogramarRecordatorio(yaCagoHoy: (mio?['total'] ?? 0) > 0).catchError((_) {});
    } catch (e) {
      _toast('Error cargando ranking: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cague() async {
    try {
      final nueva = await db.from('cagadas').insert({}).select('id').single();
      _toast('Registrado 💩');
      await _load();
      if (!mounted) return;
      final tipo = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('¿Qué salió?', style: Theme.of(context).textTheme.titleLarge),
            for (final t in tipos.entries)
              ListTile(
                leading: Text(t.value.$1, style: const TextStyle(fontSize: 24)),
                title: Text(t.value.$2),
                onTap: () => Navigator.pop(context, t.key),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prefiero no decir')),
          ],
        ),
      );
      if (tipo != null) await db.from('cagadas').update({'tipo': tipo}).eq('id', nueva['id']);
    } on PostgrestException catch (e) {
      // El trigger limitar_cagadas manda el texto listo para mostrar ("solo una por hora...").
      _toast(e.hint == 'limite_hora' ? e.message : 'Error: ${e.message}');
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _deshacer() async {
    try {
      final last = await db
          .from('cagadas')
          .select('id')
          .eq('user_id', _me)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (last == null) return _toast('No hay nada que deshacer');
      await db.from('cagadas').delete().eq('id', last['id']);
      _toast('Deshecho');
      await _load();
    } catch (e) {
      _toast('Error: $e');
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// "Fulanito cagó 3 veces hoy... vas perdiendo"
  String? get _avisoDelDia {
    if (_hoy.isEmpty) return null;
    final lider = _hoy.first;
    final mio = _hoy.firstWhere((r) => r['user_id'] == _me, orElse: () => {'total': 0})['total'];
    final n = lider['total'] as int;
    if (n == 0) return 'Nadie ha cagado hoy. Sé el primero 💩';
    if (lider['user_id'] == _me || mio == n) return 'Vas ganando hoy 👑 ($mio)';
    return '${lider['username']} cagó $n ${n == 1 ? 'vez' : 'veces'} hoy... vas perdiendo';
  }

  void _verCalendario(String userId, String username) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CalendarioScreen(userId: userId, username: username),
        ),
      ).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final aviso = _avisoDelDia;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rey Cagón 👑💩'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Mi calendario',
            onPressed: () => _verCalendario(me, 'mí'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              cancelarRecordatorio().catchError((_) {});
              await olvidarTelefono().catchError((_) {});
              await db.auth.signOut();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              onPressed: _cague,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              child: const Text('CAGUÉ 💩', style: TextStyle(fontSize: 24)),
            ),
            TextButton(onPressed: _deshacer, child: const Text('Deshacer la última')),
            if (aviso != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(aviso, textAlign: TextAlign.center),
                ),
              ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                for (final p in periods.entries)
                  ButtonSegment(value: p.key, label: Text(p.value)),
              ],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _load();
              },
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final (i, r) in _rows.indexed)
                ListTile(
                  leading: Text(i == 0 ? '👑' : '${i + 1}', style: const TextStyle(fontSize: 20)),
                  title: Text(
                    r['username'],
                    style: TextStyle(
                      fontWeight: r['user_id'] == me ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: Text('${r['total']}', style: const TextStyle(fontSize: 20)),
                  onTap: () => _verCalendario(r['user_id'], r['username']),
                ),
            const SizedBox(height: 24),
            const Text(disclaimer, textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
