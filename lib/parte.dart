import 'package:flutter/material.dart';

import 'emoji.dart';
import 'idioma.dart';
import 'peso.dart';
import 'placer.dart';
import 'tema.dart';
import 'tipos.dart';

/// Lo que se anotó en el parte. Todo puede quedar en null.
typedef Parte = ({int? tipo, int? peso, int? placer, Set<String> etiquetas});

/// Una sola hoja después de cada cagada: qué salió, cuánto pesó y, si tiene el secreto,
/// si lo disfrutó. [numero] es el total histórico con esta. null si la salta.
Future<Parte?> pedirParte(BuildContext context, {required int numero, required bool secreto}) =>
    showModalBottomSheet<Parte>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _Parte(numero: numero, secreto: secreto),
    );

class _Parte extends StatefulWidget {
  const _Parte({required this.numero, required this.secreto});

  final int numero;
  final bool secreto;

  @override
  State<_Parte> createState() => _ParteState();
}

class _ParteState extends State<_Parte> {
  // 0 es "No sé": se marca pero no se guarda.
  int? _tipo;
  int? _peso;
  int? _placer;
  final _etiquetas = <String>{};
  final _hora = TimeOfDay.now();

  void _listo() => Navigator.pop(context, (
        tipo: _tipo == 0 ? null : _tipo,
        peso: _peso,
        placer: _placer,
        etiquetas: _etiquetas,
      ));

  Widget _casilla({required bool elegida, required VoidCallback onTap, required Widget child}) {
    final p = paleta(context);
    return Material(
      color: elegida ? acento : p.tarjeta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radio),
        side: elegida ? const BorderSide(color: acentoTexto, width: 2) : BorderSide(color: p.borde),
      ),
      child: InkWell(onTap: onTap, child: child),
    );
  }

  Widget _tipoCasilla(int valor, String emoji, String texto) => _casilla(
        elegida: _tipo == valor,
        onTap: () => setState(() => _tipo = _tipo == valor ? null : valor),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Emoji(emoji, tamano: 34),
              const SizedBox(height: 2),
              Text(texto,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _tipo == valor ? acentoTexto : null)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final texto = Theme.of(context).textTheme;
    final peso = pesos[_peso];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(tr('PARTE DE CAGADA #${widget.numero}', 'POOP REPORT #${widget.numero}'),
                      style: texto.titleLarge),
                ),
                Text(_hora.format(context), style: numeros(context, tamano: 13, color: p.textoSuave)),
              ],
            ),
            const SizedBox(height: 2),
            Text(tr('Todo es opcional. Un toque en LISTO y se guarda.', 'Everything is optional. Tap DONE and it is saved.'),
                style: TextStyle(color: p.textoSuave)),
            const SizedBox(height: 14),
            Rotulo(tr('¿Qué salió?', 'What came out?')),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: .95,
              children: [
                for (final t in tipos.entries) _tipoCasilla(t.key, t.value.$1, t.value.$2),
                _tipoCasilla(0, '🤷', tr('No sé', 'No idea')),
              ],
            ),
            const SizedBox(height: 16),
            Rotulo(tr('Peso del mojón', 'Poop weight')),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // El riel que une las cinco paradas.
                  Positioned(left: 28, right: 28, child: Container(height: 2, color: p.bordeFuerte)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final e in pesos.entries)
                        AnimatedScale(
                          scale: _peso == e.key ? 1.15 : 1,
                          duration: const Duration(milliseconds: 150),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: _casilla(
                              elegida: _peso == e.key,
                              onTap: () => setState(() => _peso = _peso == e.key ? null : e.key),
                              child: Center(child: Emoji(e.value.$1, tamano: 34)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              peso == null ? tr('Toca uno, o déjalo así', 'Tap one, or leave it') : '${peso.$2.toUpperCase()} · ${peso.$3}',
              textAlign: TextAlign.center,
              style: TextStyle(color: peso == null ? p.textoSuave : p.texto, fontWeight: peso == null ? null : FontWeight.w700),
            ),
            if (widget.secreto) ...[
              const SizedBox(height: 16),
              _Secreto(
                placer: _placer,
                etiquetas: _etiquetas,
                alElegir: (v) => setState(() => _placer = _placer == v ? null : v),
                alMarcar: (e, si) => setState(() => si ? _etiquetas.add(e) : _etiquetas.remove(e)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('SALTAR', 'SKIP'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: _listo, child: Text(tr('LISTO', 'DONE')))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La caja negra y dorada de la pregunta secreta, dentro del parte.
class _Secreto extends StatelessWidget {
  const _Secreto({required this.placer, required this.etiquetas, required this.alElegir, required this.alMarcar});

  final int? placer;
  final Set<String> etiquetas;
  final ValueChanged<int> alElegir;
  final void Function(String etiqueta, bool si) alMarcar;

  static const _fondo = Color(0xFF1B1407);

  Widget _chips(List<String> cuales) => Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final e in cuales)
            FilterChip(
              label: Text(nombreEtiqueta(e).toUpperCase()),
              selected: etiquetas.contains(e),
              visualDensity: VisualDensity.compact,
              onSelected: (si) => alMarcar(e, si),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => Theme(
        data: tema(Brightness.dark),
        child: Builder(builder: (context) {
          final p = paleta(context);
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _fondo, border: Border.all(color: acento, width: 2)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Emoji('✨', tamano: 18),
                    const SizedBox(width: 6),
                    Rotulo(tr('Secreto', 'Secret')),
                    const Spacer(),
                    Text(tr('¿Lo disfrutaste?', 'Did you enjoy it?'),
                        style: const TextStyle(color: acento, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var v = 1; v <= 7; v++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            color: v == placer ? acento : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(radio),
                              side: BorderSide(color: v == placer ? acento : p.bordeFuerte),
                            ),
                            child: InkWell(
                              onTap: () => alElegir(v),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  children: [
                                    if (v == 1 || v == 7) iconoPlacer(v, tamano: 26) else const SizedBox(height: 26),
                                    Text('$v',
                                        style: numeros(context,
                                            tamano: 16, weight: FontWeight.w800, color: v == placer ? acentoTexto : p.texto)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(tr('DESTRUCTIVA', 'DESTRUCTIVE'), style: numeros(context, tamano: 10, color: p.textoSuave)),
                    const Spacer(),
                    Text(tr('CELESTIAL', 'CELESTIAL'), style: numeros(context, tamano: 10, color: p.textoSuave)),
                  ],
                ),
                const SizedBox(height: 10),
                _chips(destructivas),
                const SizedBox(height: 6),
                _chips(placenteras),
              ],
            ),
          );
        }),
      );
}
