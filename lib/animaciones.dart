import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'idioma.dart';

/// Cuánto se mueve la app. Completo: el mojón vuela al inodoro y el ranking entra animado.
/// Simple: un brinco corto dentro del botón. Nada: solo el botón que se hunde al apretarlo.
enum Movimiento { completo, simple, nada }

/// Lo que eligió en Perfil: 'auto', 'completo', 'simple' o 'nada'.
final movimientoElegido = ValueNotifier<String>('auto');

/// Lo que le toca a este teléfono en automático. Se decide una vez al abrir la app.
var _delTelefono = Movimiento.completo;

Movimiento get movimientoDelTelefono => _delTelefono;

Future<void> iniciarMovimiento() async {
  try {
    movimientoElegido.value = (await SharedPreferences.getInstance()).getString('movimiento') ?? 'auto';
  } catch (_) {}
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final a = await DeviceInfoPlugin().androidInfo;
    // Android Go, menos de 3 GB de RAM o un Android viejo (antes del 9): animaciones simples.
    if (a.isLowRamDevice || a.physicalRamSize < 3000 || a.version.sdkInt < 28) _delTelefono = Movimiento.simple;
  } catch (_) {}
}

Future<void> elegirMovimiento(String valor) async {
  movimientoElegido.value = valor;
  try {
    await (await SharedPreferences.getInstance()).setString('movimiento', valor);
  } catch (_) {}
}

/// El nivel que se usa ahora. Si el teléfono tiene "quitar animaciones" activado, manda eso.
Movimiento movimiento(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return Movimiento.nada;
  return switch (movimientoElegido.value) {
    'completo' => Movimiento.completo,
    'simple' => Movimiento.simple,
    'nada' => Movimiento.nada,
    _ => _delTelefono,
  };
}

String nombreMovimiento(Movimiento m) => switch (m) {
      Movimiento.completo => tr('Completas', 'Full'),
      Movimiento.simple => tr('Simples', 'Simple'),
      Movimiento.nada => tr('Apagadas', 'Off'),
    };
