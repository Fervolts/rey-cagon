import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'main.dart' show supabaseUrl;

// Lo escribe scripts/publicar.sh junto con la APK.
const _manifiesto = '$supabaseUrl/storage/v1/object/public/releases/version.json';

var _abierto = false;
int? _pospuesta;

/// La versión de Play se compila con --dart-define=CANAL=play: ahí las actualizaciones llegan por la tienda.
const esDePlay = String.fromEnvironment('CANAL') == 'play';

/// Al abrir la app y al volver a ella: si hay una versión con build mayor que la instalada,
/// ofrece bajarla e instalarla. "Después" la calla hasta el próximo arranque.
Future<void> revisarActualizacion(BuildContext context) async {
  if (esDePlay) return _revisarPlay(context);
  if (_abierto) return;
  _abierto = true;
  try {
    await _revisar(context);
  } finally {
    _abierto = false;
  }
}

Future<void> _revisar(BuildContext context) async {
  final Map<String, dynamic> remota;
  try {
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await cliente.getUrl(Uri.parse('$_manifiesto?t=${DateTime.now().millisecondsSinceEpoch}'));
    final res = await req.close();
    if (res.statusCode != 200) return;
    remota = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    cliente.close();
  } catch (_) {
    return; // Sin internet o sin manifiesto: se revisa la próxima vez.
  }
  final local = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
  final build = remota['build'] as int? ?? 0;
  if (build <= local || build == _pospuesta || !context.mounted) return;

  final actualizar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Actualízame, mojón 💩'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versión ${remota['version']} disponible',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((remota['notas'] as String?)?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(remota['notas']),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('DESPUÉS')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ACTUALIZAR')),
      ],
    ),
  );
  if (actualizar != true) _pospuesta = build;
  if (actualizar != true || !context.mounted) return;

  final eventos = OtaUpdate().execute(
    remota['url'],
    destinationFilename: 'rey-cagon.apk',
    // La APK se verifica contra el hash del manifiesto antes de abrir el instalador.
    sha256checksum: remota['sha256'],
  );
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StreamBuilder<OtaEvent>(
      stream: eventos,
      builder: (context, snap) {
        final e = snap.data;
        final bajando = e == null || e.status == OtaStatus.DOWNLOADING;
        final pct = double.tryParse(e?.value ?? '');
        final error = e != null && !bajando && e.status != OtaStatus.INSTALLING && e.status != OtaStatus.INSTALLATION_DONE;
        if (e?.status == OtaStatus.INSTALLING) {
          // El instalador de Android toma el control; cerramos el diálogo.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
        }
        return AlertDialog(
          title: Text(error ? 'No se pudo actualizar' : 'Bajando actualización'),
          content: error
              ? Text('${e.status.name}: ${e.value ?? ''}')
              : LinearProgressIndicator(value: pct == null ? null : pct / 100),
          actions: [
            if (error) TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
          ],
        );
      },
    ),
  );
}

/// En Play: actualización inmediata de Google (In-App Updates). Pantalla completa de Google,
/// se instala y la app se reinicia sola. Solo funciona instalada desde Play.
///
/// Para no deshacerle nada a nadie:
/// - Solo se revisa al abrir la app, antes de que toque nada; al volver de otra app no, para no
///   cortar a nadie a mitad de registrar una cagada o de escribir.
/// - Los datos viven en el servidor y las preferencias del teléfono sobreviven a la actualización;
///   el borrador del chat se guarda aparte (ver chat.dart).
/// - Si la inmediata falla o la cancelan, cae a la flexible (se baja de fondo y ofrece REINICIAR).
/// - Una sola vez por sesión.
var _playRevisada = false;

Future<void> _revisarPlay(BuildContext context) async {
  if (_playRevisada || _abierto) return;
  _playRevisada = true;
  _abierto = true;
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (!context.mounted) return;
    if (info.installStatus == InstallStatus.downloaded) return _ofrecerReinicio(context);
    if (info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress) {
      // Una inmediata que quedó a medias: se retoma.
      await InAppUpdate.performImmediateUpdate();
      return;
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
    if (info.immediateUpdateAllowed) {
      final r = await InAppUpdate.performImmediateUpdate();
      if (r == AppUpdateResult.success) return;
    }
    if (!info.flexibleUpdateAllowed) return;
    if (await InAppUpdate.startFlexibleUpdate() != AppUpdateResult.success) return;
    if (context.mounted) _ofrecerReinicio(context);
  } catch (_) {
    // Sin Play Store, sin internet o instalada por fuera: se revisa la próxima vez que abra.
  } finally {
    _abierto = false;
  }
}

void _ofrecerReinicio(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Actualización lista 💩'),
      duration: const Duration(days: 1),
      action: SnackBarAction(label: 'REINICIAR', onPressed: InAppUpdate.completeFlexibleUpdate),
    ),
  );
}
