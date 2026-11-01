// Hoja de Fichas 🎟️ (se abre con el chip de Fichas): Cagada fresca, Sin espera, Tanque extra y Congelador.
// Las Fichas viven en el servidor (tope 5); el efecto lo pone control.dart.

import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'catalogo.dart';
import 'ciruelas.dart' show maxCongeladores;
import 'control.dart';
import 'saldo_fijo.dart';

/// Tope de Fichas que guarda el servidor.
const int maxFichas = 5;

/// Lo que se compra con Fichas: id para `imperio_usar_fichas` (o 'cagada_fresca', la de siempre), emoji y precio.
const Map<String, (String, int)> usosFichas = {
  'cagada_fresca': ('💩', 1),
  'sin_espera': ('⏩', 1),
  'tanque_extra': ('🛢️', 2),
  'congelador': ('🧊', 3),
};

/// Nombre de lo que tiene la espera [id] (objeto, alquilable o `hab_<habilidad>`). Si no se conoce, el id.
(String emoji, String nombre) nombreEspera(String id) {
  if (objetoPorId(id) case final o?) return (o.emoji, tr(o.nombreEs, o.nombreEn));
  if (id.startsWith('hab_')) {
    if (habilidadPorId(id.substring(4)) case final h?) return (h.emoji, tr(h.nombreEs, h.nombreEn));
  }
  return ('⏳', id);
}

/// "2 h 5 min", "12 min" o "<1 min".
String faltaCorto(int ms) {
  final min = ms ~/ 60000;
  if (min < 1) return '<1 min';
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Abre la hoja. [avisar] pone el aviso de arriba de la pantalla del Imperio.
Future<void> abrirHojaFichas(BuildContext context, ControlImperio control, void Function(String emoji, String texto) avisar) {
  control.anotar('fichas_abre', {'fichas': control.imperio.fichas});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: paleta(context).fondo,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    builder: (_) => ListenableBuilder(
      listenable: control,
      builder: (context, _) => HojaFichas(control: control, avisar: avisar),
    ),
  );
}

class HojaFichas extends StatefulWidget {
  const HojaFichas({super.key, required this.control, required this.avisar});

  final ControlImperio control;
  final void Function(String emoji, String texto) avisar;

  @override
  State<HojaFichas> createState() => _HojaFichasState();
}

class _HojaFichasState extends State<HojaFichas> {
  String? _ocupado; // lo que se está pagando
  bool _verEsperas = false;

  Future<void> _usar(String id, Future<bool> Function() uso, String emoji, String hecho) async {
    setState(() => _ocupado = id);
    try {
      final ok = await uso();
      widget.avisar(ok ? emoji : '🎟️', ok ? hecho : tr('No te alcanzan las Fichas.', 'Not enough Tokens.'));
      if (ok && mounted) setState(() => _verEsperas = false);
    } catch (e) {
      widget.avisar('💩', textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = widget.control;
    final fichas = c.imperio.fichas;
    final esperas = c.imperio.esperasActivas(c.ahora);
    bool alcanza(String id) => _ocupado == null && fichas >= usosFichas[id]!.$2;
    final congLleno = c.congeladores >= maxCongeladores;
    return SafeArea(
      // El saldo queda fijo arriba; solo baja la lista.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaldoFijo(control: c),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Emoji('🎟️', tamano: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('$fichas/$maxFichas Fichas', '$fichas/$maxFichas Tokens'),
                                key: const Key('saldo_fichas'), style: numeros(context, tamano: 22, weight: FontWeight.w900)),
                            Text(
                                tr('Salen en la racha y en el Cofre del Trono. Guardas hasta $maxFichas.',
                                    'They come from the streak and the Throne Chest. You keep up to $maxFichas.'),
                                style: TextStyle(fontSize: 12, color: p.textoSuave)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _fila(
                    context,
                    id: 'cagada_fresca',
                    titulo: tr('Cagada fresca', 'Fresh poop'),
                    detalle: tr('Producción x2 por 1 h', 'Production x2 for 1 h'),
                    boton: _boton(
                        tr('USAR', 'USE'),
                        alcanza('cagada_fresca')
                            ? () => _usar('cagada_fresca', c.usarFichaFresca, '💩', tr('Cagada fresca: x2 por 1 h', 'Fresh poop: x2 for 1 h'))
                            : null),
                  ),
                  _fila(
                    context,
                    id: 'sin_espera',
                    titulo: tr('Sin espera', 'No wait'),
                    detalle: esperas.isEmpty
                        ? tr('Nada está esperando ahora', 'Nothing is waiting right now')
                        : tr('Borra la espera de algo: ${esperas.length} esperando', 'Clears a wait: ${esperas.length} waiting'),
                    boton: _boton(
                        _verEsperas ? tr('CERRAR', 'CLOSE') : tr('ELEGIR', 'PICK'),
                        _ocupado == null && esperas.isNotEmpty && (fichas >= 1 || _verEsperas)
                            ? () => setState(() => _verEsperas = !_verEsperas)
                            : null),
                  ),
                  if (_verEsperas && esperas.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final MapEntry(key: id, value: ms) in esperas.entries)
                            () {
                              final (emoji, nombre) = nombreEspera(id);
                              return Container(
                                key: Key('espera_$id'),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: p.suave, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
                                child: Row(
                                  children: [
                                    Emoji(emoji, tamano: 22),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(nombre, style: TextStyle(fontWeight: FontWeight.w700, color: p.texto)),
                                          Text(tr('Faltan ${faltaCorto(ms)}', '${faltaCorto(ms)} left'),
                                              style: numeros(context, tamano: 12, color: p.textoSuave)),
                                        ],
                                      ),
                                    ),
                                    _boton(
                                        tr('YA', 'NOW'),
                                        alcanza('sin_espera')
                                            ? () => _usar('sin_espera', () => c.usarFichas('sin_espera', espera: id), '⏩',
                                                tr('$nombre: listo, sin espera', '$nombre: ready, no wait'))
                                            : null),
                                  ],
                                ),
                              );
                            }(),
                        ],
                      ),
                    ),
                  _fila(
                    context,
                    id: 'tanque_extra',
                    titulo: tr('Tanque extra', 'Extra tank'),
                    detalle: c.tanqueExtra
                        ? tr('Ya lo tienes: +1 h a lo que juntas sin abrir', 'You have it: +1 h to what you save while away')
                        : tr('+1 h a lo que juntas sin abrir, para siempre', '+1 h to what you save while away, forever'),
                    boton: c.tanqueExtra
                        ? Text(tr('LISTO', 'DONE'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8, color: p.textoSuave))
                        : _boton(
                            tr('USAR', 'USE'),
                            alcanza('tanque_extra')
                                ? () => _usar('tanque_extra', () => c.usarFichas('tanque_extra'), '🛢️', tr('Tanque extra: +1 h', 'Extra tank: +1 h'))
                                : null),
                  ),
                  _fila(
                    context,
                    id: 'congelador',
                    titulo: tr('Congelador de racha', 'Streak freezer'),
                    detalle: tr('Si se te pasa un día, la racha sigue · ${c.congeladores}/$maxCongeladores',
                        'Miss a day and the streak goes on · ${c.congeladores}/$maxCongeladores'),
                    boton: _boton(
                        congLleno ? tr('LLENO', 'FULL') : tr('USAR', 'USE'),
                        !congLleno && alcanza('congelador')
                            ? () => _usar('congelador', () => c.usarFichas('congelador'), '🧊',
                                tr('Congelador: ${c.congeladores + 1}/$maxCongeladores', 'Freezer: ${c.congeladores + 1}/$maxCongeladores'))
                            : null),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boton(String texto, VoidCallback? alTocar) =>
      FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: alTocar, child: Text(texto));

  Widget _fila(BuildContext context, {required String id, required String titulo, required String detalle, required Widget boton}) {
    final p = paleta(context);
    final (emoji, precio) = usosFichas[id]!;
    return Container(
      key: Key('ficha_$id'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: Row(
        children: [
          Emoji(emoji, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: p.texto)),
                Text(detalle, style: TextStyle(fontSize: 12, color: p.textoSuave)),
                Row(
                  children: [
                    Text('$precio ', style: numeros(context, tamano: 13, weight: FontWeight.w800)),
                    const Emoji('🎟️', tamano: 14),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          boton,
        ],
      ),
    );
  }
}
