import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:in_app_update/in_app_update.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'idioma.dart';
import 'main.dart' show supabaseUrl;

// Lo escribe scripts/publicar.sh junto con la APK.
const _manifiesto = '$supabaseUrl/storage/v1/object/public/releases/version.json';

var _abierto = false;
int? _pospuesta;

/// Llegó el push de versión nueva con la app abierta: el trono lo escucha y revisa en el momento,
/// sin esperar a que la cierren y la vuelvan a abrir.
final versionAnunciada = ValueNotifier<int>(0);

/// La versión de Play (flavor `play`): ahí las actualizaciones llegan por la tienda. Sale del flavor
/// para no depender de acordarse del --dart-define=CANAL=play, que ya se olvidó una vez.
const esDePlay = appFlavor == 'play' || String.fromEnvironment('CANAL') == 'play';

/// Al abrir la app, al volver a ella, cada 30 min con la app abierta y al llegar el push de versión:
/// si hay una versión con build mayor que la instalada, ofrece bajarla e instalarla.
/// "Después" calla ese build hasta el próximo arranque.
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
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    // Con tope: una conexión colgada dejaba la revisión trabada hasta cerrar la app.
    remota = await () async {
      final req = await cliente.getUrl(Uri.parse('$_manifiesto?t=${DateTime.now().millisecondsSinceEpoch}'));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    }()
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    return; // Sin internet o sin manifiesto: se revisa la próxima vez.
  } finally {
    cliente.close(force: true);
  }
  final local = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
  final build = remota['build'] as int? ?? 0;
  if (build <= local || build == _pospuesta || !context.mounted) return;

  final actualizar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Actualízame, mojón 💩', 'Update me, you turd 💩')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Versión ${remota['version']} disponible', 'Version ${remota['version']} available'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((remota['notas'] as String?)?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(remota['notas']),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('DESPUÉS', 'LATER'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('ACTUALIZAR', 'UPDATE'))),
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
          title: Text(error ? tr('No se pudo actualizar', "Couldn't update") : tr('Bajando actualización', 'Downloading update')),
          content: error
              ? Text('${e.status.name}: ${e.value ?? ''}')
              : LinearProgressIndicator(value: pct == null ? null : pct / 100),
          actions: [
            if (error) TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('CERRAR', 'CLOSE'))),
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
/// - La inmediata solo en la primera revisión de la sesión, al abrir, antes de que toque nada.
/// - Las siguientes (volver de otra app, cada 30 min, push de versión) usan la flexible: se baja de
///   fondo y ofrece REINICIAR, sin cortar a nadie a mitad de registrar una cagada o de escribir.
/// - Los datos viven en el servidor y las preferencias del teléfono sobreviven a la actualización;
///   el borrador del chat se guarda aparte (ver chat.dart).
/// - Si la inmediata falla o la cancelan, cae a la flexible.
/// - Como mucho una revisión cada 10 min.
DateTime? _playRevisadaEn;

Future<void> _revisarPlay(BuildContext context) async {
  final ahora = DateTime.now();
  final primera = _playRevisadaEn == null;
  if (_abierto || (!primera && ahora.difference(_playRevisadaEn!) < const Duration(minutes: 10))) return;
  _playRevisadaEn = ahora;
  _abierto = true;
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (!context.mounted) return;
    if (info.installStatus == InstallStatus.downloaded) return _ofrecerReinicio(context);
    if (info.installStatus == InstallStatus.downloading || info.installStatus == InstallStatus.pending) return;
    if (info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress) {
      // Una inmediata que quedó a medias: se retoma.
      await InAppUpdate.performImmediateUpdate();
      return;
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
    if (primera && info.immediateUpdateAllowed) {
      final r = await InAppUpdate.performImmediateUpdate();
      if (r == AppUpdateResult.success) return;
    }
    if (!info.flexibleUpdateAllowed) return;
    if (await InAppUpdate.startFlexibleUpdate() != AppUpdateResult.success) return;
    if (context.mounted) _ofrecerReinicio(context);
  } catch (_) {
    // Sin Play Store, sin internet o instalada por fuera: se revisa la próxima vez.
  } finally {
    _abierto = false;
  }
}

void _ofrecerReinicio(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(tr('Actualización lista 💩', 'Update ready 💩')),
      duration: const Duration(days: 1),
      action: SnackBarAction(label: tr('REINICIAR', 'RESTART'), onPressed: InAppUpdate.completeFlexibleUpdate),
    ),
  );
}

/// El build instalado (versionCode), o null si no se puede leer.
Future<int?> buildInstalado() async {
  try {
    return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
  } catch (_) {
    return null;
  }
}

/// Botón ACTUALIZAR de una pantalla que bloquea por versión vieja: en Play intenta la actualización
/// inmediata y si no se puede abre la ficha de la tienda; fuera de Play revisa el manifiesto otra vez,
/// aunque antes le hayan dado DESPUÉS.
Future<void> abrirActualizacion(BuildContext context) async {
  if (!esDePlay) {
    _pospuesta = null;
    return revisarActualizacion(context);
  }
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability == UpdateAvailability.updateAvailable && info.immediateUpdateAllowed) {
      if (await InAppUpdate.performImmediateUpdate() == AppUpdateResult.success) return;
    }
  } catch (_) {
    // Sin Play Store o instalada por fuera: se abre la ficha.
  }
  try {
    final id = (await PackageInfo.fromPlatform()).packageName;
    await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=$id'), mode: LaunchMode.externalApplication);
  } catch (_) {}
}
