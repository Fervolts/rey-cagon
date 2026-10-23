import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'actualizar.dart' show esDePlay;
import 'idioma.dart';
import 'tema.dart';

List<(String, String)> get _pasos => [
      (tr('Únete al grupo de testers', 'Join the testers group'), 'https://groups.google.com/g/rey-cagon-testers'),
      (tr('Acepta la prueba', 'Accept the test'), 'https://play.google.com/apps/testing/com.ahimismito.rey_cagon'),
      (tr('Instala desde Play', 'Install from Play'), 'https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon'),
    ];

/// Solo en la APK directa: invita a pasarse a la prueba cerrada de Play Store.
/// "Después" la calla hasta el próximo arranque; "Ya estoy" no la vuelve a mostrar.
Future<void> invitarAPlay(BuildContext context) async {
  if (esDePlay) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('play_invitado') ?? false) return;
  if (!context.mounted) return;
  final listo = await showDialog<bool>(
    context: context,
    builder: (context) {
      final p = paleta(context);
      return AlertDialog(
        title: Text(tr('¡Llegamos a Play Store! 👑', "We're on the Play Store! 👑")),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Necesitamos testers para salir publicados. Hazlo en este orden, '
                  'con la misma cuenta de Google del teléfono:',
                  'We need testers to get published. Do it in this order, '
                  'with the same Google account as your phone:')),
              const SizedBox(height: 12),
              for (final (i, (texto, url)) in _pasos.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    child: Text('${i + 1}. ${texto.toUpperCase()}'),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                tr(
                    'Antes de instalar la de Play, desinstala esta: no se instala encima. '
                    'Tu cuenta y tus cagadas no se pierden. Déjala instalada al menos 14 días.',
                    "Before installing the Play version, uninstall this one: it won't install on top. "
                    "Your account and your poops are safe. Keep it installed for at least 14 days."),
                style: TextStyle(color: p.textoSuave, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Después', 'Later'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Ya estoy', "I'm in"))),
        ],
      );
    },
  );
  if (listo == true) await prefs.setBool('play_invitado', true);
}
