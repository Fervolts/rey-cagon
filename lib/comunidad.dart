import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emoji.dart';
import 'main.dart' show db;

// Comunidad oficial fuera de la app: el canal de WhatsApp (y Discord si algún día hace falta).
// Los links viven en public.comunidad; sin fila activa no sale nada.

typedef _Link = ({String id, String url});

Future<List<_Link>> _links() async {
  try {
    final r = await db.from('comunidad').select('id, url').order('id', ascending: false);
    return [for (final x in r) (id: x['id'] as String, url: x['url'] as String)];
  } catch (_) {
    return [];
  }
}

String _nombre(String id) => id == 'discord' ? 'el Discord' : 'el canal de WhatsApp';

Future<void> _abrir(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Una sola vez, cuando la cuenta ya tiene un par de días: invitación a la comunidad.
Future<void> ofrecerComunidad(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('comunidad_ofrecida') ?? false) return;
  final creada = DateTime.tryParse(db.auth.currentUser?.createdAt ?? '');
  if (creada == null || DateTime.now().difference(creada) < const Duration(days: 2)) return;
  final links = await _links();
  if (links.isEmpty) return;
  await prefs.setBool('comunidad_ofrecida', true);
  final link = links.first;
  if (!context.mounted) return;
  final unirme = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('🚽 La comunidad del trono'),
      content: Text('Únete a ${_nombre(link.id)} de Rey Cagón: memes, chisme del baño y adelantos de lo que viene.\n\n'
          'Es un canal: nadie ve tu número.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('AHORA NO')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('UNIRME')),
      ],
    ),
  );
  if (unirme == true) await _abrir(link.url);
}

/// Fila fija en el perfil propio. No pinta nada si no hay link activo.
class FilaComunidad extends StatefulWidget {
  const FilaComunidad({super.key});

  @override
  State<FilaComunidad> createState() => _FilaComunidadState();
}

class _FilaComunidadState extends State<FilaComunidad> {
  List<_Link> _lista = [];

  @override
  void initState() {
    super.initState();
    _links().then((l) {
      if (mounted) setState(() => _lista = l);
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final l in _lista)
          ListTile(
            leading: Emoji(l.id == 'discord' ? '🎮' : '📢', tamano: 24),
            title: Text(l.id == 'discord' ? 'Discord de Rey Cagón' : 'Canal de WhatsApp de Rey Cagón'),
            subtitle: const Text('Memes, chisme y adelantos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _abrir(l.url),
          ),
      ]);
}
