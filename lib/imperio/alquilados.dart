// Lo alquilado que está trabajando, a la vista: la tira "trabajando ahora" junto a la poceta y las cuentas puras que
// usa la poceta para dibujar a los primos tocando (poceta.dart dibuja a cada alquilado).
//
// Los primos pujan de verdad 10 veces por segundo cada uno ([pujosPrimo], en el motor). En pantalla solo se ven
// [toquesPorSegundoPrimo] toques por primo, y un "+MJ" cada [cadaFlotantePrimo] toques que junta lo de esos pujos:
// sumados, los "+MJ" de un primo dan lo que gana de verdad.

import 'dart:math';

import 'package:flutter/material.dart';

import '../emoji.dart';
import '../idioma.dart';
import '../tema.dart';
import 'motor.dart';

/// Toques que se ven por segundo de cada primo (la economía va aparte: [pujosPrimo]).
const toquesPorSegundoPrimo = 3.5;

/// Desfase de cada primo, para que no toquen todos a la vez (en segundos).
double fasePrimo(int i) => i / 4 / toquesPorSegundoPrimo;

/// Qué toque va dando el primo [i] en el segundo [t] (cuenta desde 0; negativo antes del primero).
int toquePrimo(int i, double t) => ((t - fasePrimo(i)) * toquesPorSegundoPrimo).floor();

/// En qué segundo empieza el toque [k] del primo [i].
double inicioToquePrimo(int i, int k) => fasePrimo(i) + k / toquesPorSegundoPrimo;

/// Cada cuántos toques de un primo sale su "+MJ": con más primos, menos seguido (no se amontonan).
int cadaFlotantePrimo(int primos) => max(2, primos);

/// Lo que dice cada "+MJ" de un primo: lo que gana en los toques que junta. [pujoPrimoPorSegundo] es lo de un primo
/// en un segundo (valor del pujo x [pujosPrimo]).
double montoFlotantePrimo(double pujoPrimoPorSegundo, int primos) => pujoPrimoPorSegundo * cadaFlotantePrimo(primos) / toquesPorSegundoPrimo;

/// Una ficha de la tira: el alquilable, su emoji y lo que dice (lo que le queda, ∞ o cuántos primos).
typedef FichaAlquiler = ({String id, String emoji, String texto});

/// Lo que dice una ficha: "∞" si es indefinido, el tiempo que queda ("14:59", "1:59:59") o, sin tiempo (el Guardia),
/// que está vigilando. Con primos, "x2 " delante.
String textoFichaAlquiler({Duration? restante, bool indefinido = false, int primos = 0}) {
  final String tiempo;
  if (indefinido) {
    tiempo = '∞';
  } else if (restante == null) {
    tiempo = tr('activo', 'on');
  } else {
    final s = max(0, (restante.inMilliseconds / 1000).ceil());
    String dos(int n) => n.toString().padLeft(2, '0');
    tiempo = s >= 3600 ? '${s ~/ 3600}:${dos(s % 3600 ~/ 60)}:${dos(s % 60)}' : '${s ~/ 60}:${dos(s % 60)}';
  }
  return primos > 0 ? 'x$primos $tiempo' : tiempo;
}

/// Las fichas de lo alquilado activo, en el orden del catálogo.
List<FichaAlquiler> fichasAlquiler(Imperio im, int ahora) => [
      for (final o in objetos)
        if (o.tipo == TipoObjeto.alquilable && im.alquiladoActivo(o.id, ahora))
          (
            id: o.id,
            emoji: o.emoji,
            texto: textoFichaAlquiler(
              restante: o.duracion == null ? null : Duration(milliseconds: (im.partida.alquilados[o.id] ?? ahora) - ahora),
              indefinido: im.alquilerIndefinido(o.id),
              primos: o.id == 'primo' ? im.primosActivos() : 0,
            ),
          ),
    ];

/// El aviso corto al tocar una ficha: qué es, qué hace y cuánto le queda.
String avisoAlquiler(FichaAlquiler f) {
  final o = objetoPorId(f.id);
  if (o == null) return f.texto;
  return '${tr(o.nombreEs, o.nombreEn)} (${f.texto}): ${tr(o.descEs, o.descEn)}';
}

/// La tira "trabajando ahora": una ficha cuadrada por alquilado activo. Quieta (no se anima nunca): se lee igual con
/// movimiento "nada". Tocar una ficha llama a [alTocar] y no puja.
class TiraAlquiler extends StatelessWidget {
  const TiraAlquiler(this.fichas, {super.key, this.alTocar});

  final List<FichaAlquiler> fichas;
  final void Function(FichaAlquiler ficha)? alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final estilo = numeros(context, tamano: 11, weight: FontWeight.w800, color: p.texto);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final f in fichas)
          Semantics(
            key: ValueKey('ficha_${f.id}'),
            container: true,
            button: true,
            label: avisoAlquiler(f),
            onTap: alTocar == null ? null : () => alTocar!(f),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: alTocar == null ? null : () => alTocar!(f),
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: acento), borderRadius: BorderRadius.circular(radio)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Emoji(f.emoji, tamano: 14),
                  const SizedBox(width: 3),
                  Text(f.texto, style: estilo),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
