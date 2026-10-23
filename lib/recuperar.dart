import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'idioma.dart';
import 'main.dart' show db;
import 'tema.dart';

/// Recuperar la contraseña con un código que llega por correo, sin links ni dominios.
/// Al verificar el código ya hay sesión (la pantalla de inicio se monta debajo), así que
/// esta pantalla se queda encima hasta que se guarde la contraseña nueva.
class PantallaRecuperar extends StatefulWidget {
  const PantallaRecuperar({super.key, this.correo = ''});

  final String correo;

  @override
  State<PantallaRecuperar> createState() => _PantallaRecuperarState();
}

class _PantallaRecuperarState extends State<PantallaRecuperar> {
  late final _correo = TextEditingController(text: widget.correo);
  final _codigo = TextEditingController();
  final _clave = TextEditingController();
  int _paso = 0; // 0 pedir código, 1 poner código, 2 contraseña nueva
  bool _ocupado = false;

  Future<void> _hacer(Future<void> Function() accion) async {
    setState(() => _ocupado = true);
    try {
      await accion();
    } on AuthException catch (e) {
      _mensaje(trServidor(e.message));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _mensaje(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _pedirCodigo() => _hacer(() async {
        await db.auth.resetPasswordForEmail(_correo.text.trim());
        setState(() => _paso = 1);
        _mensaje(tr('Si el correo existe, te llegó un código. Revisa también spam.',
            "If that email exists, a code is on its way. Check spam too."));
      });

  Future<void> _verificar() => _hacer(() async {
        await db.auth.verifyOTP(
          email: _correo.text.trim(),
          token: _codigo.text.trim(),
          type: OtpType.recovery,
        );
        setState(() => _paso = 2);
      });

  Future<void> _guardar() => _hacer(() async {
        if (_clave.text.length < 6) {
          _mensaje(tr('Mínimo 6 caracteres.', 'At least 6 characters.'));
          return;
        }
        await db.auth.updateUser(UserAttributes(password: _clave.text));
        if (!mounted) return;
        _mensaje(tr('Listo, contraseña cambiada.', 'Done, password changed.'));
        Navigator.pop(context);
      });

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final p = paleta(context);
    final (rotulo, control, boton, accion) = switch (_paso) {
      0 => ('Email', _correo, tr('ENVIAR CÓDIGO', 'SEND CODE'), _pedirCodigo),
      1 => (tr('Código del correo', 'Code from the email'), _codigo, tr('VERIFICAR', 'VERIFY'), _verificar),
      _ => (tr('Contraseña nueva', 'New password'), _clave, tr('GUARDAR', 'SAVE'), _guardar),
    };
    return PopScope(
      // Con el código ya verificado hay sesión: no dejar salir sin poner la contraseña.
      canPop: _paso < 2,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('RECUPERAR CONTRASEÑA', 'RESET PASSWORD')), automaticallyImplyLeading: _paso < 2),
        body: ListView(
          padding: conBordeAbajo(context, const EdgeInsets.all(24)),
          children: [
            Text(
              switch (_paso) {
                0 => tr('Te mandamos un código a tu correo.', "We'll email you a code."),
                1 => tr('Pon el código que te llegó a ${_correo.text.trim()}.', 'Enter the code we sent to ${_correo.text.trim()}.'),
                _ => tr('Elige tu contraseña nueva.', 'Pick your new password.'),
              },
              style: texto.bodyLarge?.copyWith(color: p.textoSuave),
            ),
            const SizedBox(height: 24),
            Rotulo(rotulo),
            const SizedBox(height: 6),
            TextField(
              key: ValueKey(_paso),
              controller: control,
              autofocus: true,
              obscureText: _paso == 2,
              keyboardType: switch (_paso) {
                0 => TextInputType.emailAddress,
                1 => TextInputType.number,
                _ => TextInputType.visiblePassword,
              },
              onSubmitted: (_) => _ocupado ? null : accion(),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _ocupado ? null : accion, child: Text(boton)),
            if (_paso == 1)
              TextButton(
                onPressed: _ocupado ? null : _pedirCodigo,
                child: Text(tr('MANDAR OTRO CÓDIGO', 'SEND ANOTHER CODE')),
              ),
          ],
        ),
      ),
    );
  }
}
