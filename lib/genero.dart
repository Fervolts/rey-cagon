import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emoji.dart';
import 'idioma.dart';
import 'tema.dart';

/// Géneros que guarda profiles.genero. El primero que eliges es libre; después se cambia una vez al año
/// (trigger validar_genero).
Map<String, (String, String, String)> get generos => {
  'hombre': ('🤴', tr('Rey', 'King'), tr('Hombre', 'Man')),
  'mujer': ('👸', tr('Reina', 'Queen'), tr('Mujer', 'Woman')),
  'otro': ('🫅', tr('Monarca', 'Monarch'), tr('Prefiero no decir', 'Rather not say')),
};

/// Género de quien usa este teléfono. También vive en prefs porque el widget corre sin la app abierta.
String? miGenero;

/// Texto de rey o de reina según [miGenero]. 'otro' va como rey, como estaba la app antes.
String segun(String rey, String reina) => miGenero == 'mujer' ? reina : rey;

Future<void> cargarGenero() async => miGenero = (await SharedPreferences.getInstance()).getString('genero');

Future<void> guardarGenero(String? g) async {
  miGenero = g;
  final prefs = await SharedPreferences.getInstance();
  g == null ? await prefs.remove('genero') : await prefs.setString('genero', g);
}

/// Las tres opciones en fila. [onTap] null las deja apagadas.
class ElegirGenero extends StatelessWidget {
  const ElegirGenero({super.key, required this.valor, required this.onTap});

  final String? valor;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Row(
      children: [
        for (final g in generos.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: g.key == valor ? acento : p.tarjeta,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radio),
                  side: BorderSide(color: g.key == valor ? acento : p.borde, width: 2),
                ),
                child: InkWell(
                  onTap: onTap == null ? null : () => onTap!(g.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Column(children: [
                      Emoji(g.value.$1, tamano: 48),
                      const SizedBox(height: 6),
                      Text(g.value.$2.toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: g.key == valor ? acentoTexto : null)),
                      Text(g.value.$3,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: g.key == valor ? acentoTexto : p.textoSuave)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
