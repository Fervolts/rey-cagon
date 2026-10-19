import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://TU-PROYECTO.supabase.co';
const supabaseKey = 'sb_publishable_...';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const ReyCagonApp());
}

final db = Supabase.instance.client;

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await db.rpc('leaderboard', params: {'period': _period});
      setState(() => _rows = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      _toast('Error cargando ranking: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cague() async {
    try {
      await db.from('cagadas').insert({});
      _toast('Registrado 💩');
      await _load();
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _deshacer() async {
    try {
      final last = await db
          .from('cagadas')
          .select('id')
          .eq('user_id', db.auth.currentUser!.id)
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

  @override
  Widget build(BuildContext context) {
    final me = db.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rey Cagón 👑💩'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => db.auth.signOut(),
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
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                for (final p in periods.entries)
                  ButtonSegment(value: p.key, label: Text(p.value)),
              ],
              selected: {_period},
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
                ),
          ],
        ),
      ),
    );
  }
}
