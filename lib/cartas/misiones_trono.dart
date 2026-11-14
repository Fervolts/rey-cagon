import 'dart:math';

import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'logica.dart';
import 'misiones.dart';
import 'nube.dart';

// Las 3 misiones del día en el TRONO. No dan 🧻: al cumplir las 3 se cobra un sobre de cartas.

/// "MISIONES 1/3 · nuevas en 9 h" y las 3 tarjetas lado a lado.
class MisionesDeHoy extends StatelessWidget {
  const MisionesDeHoy({super.key, required this.misiones, this.ahora});

  final Misiones misiones;

  /// Para las capturas; si no, la hora del teléfono.
  final DateTime? ahora;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final lista = misiones.lista;
    final hechas = lista.where((m) => m.progreso >= m.meta).length;
    final horas = horasHasta(misiones.proximo, ahora ?? DateTime.now());
    final titulo = numeros(context, tamano: 15, weight: FontWeight.w800, color: p.texto).copyWith(letterSpacing: 2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(tr('MISIONES ', 'MISSIONS '), style: titulo),
        Text('$hechas/${lista.length}', style: titulo.copyWith(color: p.acento)),
        const Spacer(),
        Text(tr('nuevas en $horas h', 'new in $horas h'), style: numeros(context, tamano: 12, color: p.textoSuave)),
      ]),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < lista.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _Mision(lista[i])),
          ],
        ]),
      ),
    ]);
  }
}

class _Mision extends StatelessWidget {
  const _Mision(this.m);

  final Mision m;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final hecha = m.progreso >= m.meta;
    final contenido = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Emoji(emojiMision(m.clave), tamano: 30),
        const Spacer(),
        if (m.rara) const Emoji('✨', tamano: 16),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: Text(textoMision(m.clave, m.meta),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2, color: p.texto)),
      ),
      const SizedBox(height: 8),
      // Avance: barra fina y el número.
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radio),
            child: LinearProgressIndicator(
              value: m.meta == 0 ? 1 : min(m.progreso / m.meta, 1),
              minHeight: 4,
              backgroundColor: p.suave,
              color: p.acento,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${min(m.progreso, m.meta)}/${m.meta}', style: numeros(context, tamano: 11, color: p.textoSuave)),
      ]),
    ]);
    return Semantics(
      label: '${textoMision(m.clave, m.meta)}. ${hecha ? tr('Hecha', 'Done') : '${m.progreso}/${m.meta}'}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.tarjeta,
          border: Border.all(color: m.rara && !hecha ? p.acento : p.borde, width: m.rara && !hecha ? 2 : 1),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Stack(children: [
          Opacity(opacity: hecha ? .4 : 1, child: contenido),
          if (hecha) const Positioned.fill(child: Center(child: _Sello())),
        ]),
      ),
    );
  }
}

/// "HECHA" amarillo, torcido como un sello.
class _Sello extends StatelessWidget {
  const _Sello();

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Transform.rotate(
      angle: -.3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: p.acento, width: 2), borderRadius: BorderRadius.circular(radio)),
        child: Text(tr('HECHA', 'DONE'),
            style: numeros(context, tamano: 15, weight: FontWeight.w900, color: p.acento).copyWith(letterSpacing: 2)),
      ),
    );
  }
}

/// Cobrar el sobre de las misiones. Sin las 3 hechas queda apagado; ya cobrado, avisa que vuelva mañana.
class BotonMisiones extends StatelessWidget {
  const BotonMisiones({super.key, required this.misiones, required this.cobrando, required this.alCobrar, this.misterio = false});

  final Misiones misiones;
  final bool cobrando;

  /// Sin el lado secreto encontrado el premio no se nombra: dice "+1 ❓".
  final bool misterio;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    if (misiones.cobrada) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
        alignment: Alignment.center,
        child: Text(misterio ? tr('COBRADO, vuelve mañana', 'CLAIMED, come back tomorrow') : tr('SOBRE COBRADO, vuelve mañana', 'PACK CLAIMED, come back tomorrow'),
            style: numeros(context, tamano: 12, weight: FontWeight.w700, color: p.textoSuave)),
      );
    }
    final listas = misiones.lista.isNotEmpty && misiones.lista.every((m) => m.progreso >= m.meta);
    return FilledButton(
      onPressed: listas && !cobrando ? alCobrar : null,
      style: FilledButton.styleFrom(
        backgroundColor: acento,
        foregroundColor: acentoTexto,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
      ),
      child: cobrando
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : misterio
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('COMPLETA LAS 3: +1 ', 'FINISH ALL 3: +1 '), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const Emoji('❓', tamano: 18),
                ])
              : Text(tr('COMPLETA LAS 3: +1 SOBRE', 'FINISH ALL 3: +1 PACK'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
    );
  }
}
