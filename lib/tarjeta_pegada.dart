import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'cagadon.dart' show TarjetaReto;
import 'chat.dart' show aceptoReglas, hitos, nombreSala;
import 'cloaca.dart' show TarjetaCloaca;
import 'emoji.dart';
import 'idioma.dart';
import 'imperio/regalos.dart' show TarjetaImperio, TarjetaRegalo;
import 'imperio/tarjeta_bano.dart';
import 'imperio/tarjeta_cartera.dart';
import 'main.dart' show conReintento, db, textoError;
import 'presumir.dart';
import 'tema.dart';

// Las tarjetas (hitos, rachas, retos, Imperio…) ya no van al chat: se pegan en el muro.

/// Dibuja una tarjeta según su tipo. En el muro, el reto es el post vivo: invitación para los dos,
/// marcador mientras dura y resultado al final. En el chat (mensajes viejos) va compacto.
class TarjetaPegada extends StatelessWidget {
  const TarjetaPegada(this.t, {super.key, this.muro = false});

  final Map<String, dynamic> t;
  final bool muro;

  @override
  Widget build(BuildContext context) {
    if (t['tipo'] == 'reto' || t['tipo'] == 'reto_fin') {
      return muro ? TarjetaReto(id: t['id'] as int, muro: true) : TarjetaReto(id: t['id'] as int, compacta: true);
    }
    if (t['tipo'] == 'cartera') return TarjetaCartera(t);
    if (t['tipo'] == 'bano') return TarjetaBano(t);
    if (t['tipo'] == 'regalo') return TarjetaRegalo(t);
    if (t['tipo'] == 'imperio') return TarjetaImperio(t);
    if (t['tipo'] == 'cloaca') return TarjetaCloaca(t);
    final propia = tarjetaPresumir(t);
    if (propia != null) return propia;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: acento, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: const Emoji('💩', tamano: 40),
    );
  }
}

void _aviso(BuildContext context, String texto) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: TextoConEmojis(texto)));

/// Pega [tarjeta] en el muro. El servidor la revisa y le pone los números. Devuelve si quedó pegada.
Future<bool> pegarEnMuro(BuildContext context, Map<String, dynamic> tarjeta) async {
  if (!context.mounted || !await aceptoReglas(context)) return false;
  try {
    await db.from('muro').insert({'tarjeta': tarjeta});
    if (context.mounted) _aviso(context, tr('Pegado en $nombreSala 🚽', 'Stuck up in $nombreSala 🚽'));
    return true;
  } catch (e) {
    if (context.mounted) _aviso(context, textoError(e));
    return false;
  }
}

/// El botón 🏆 del muro: escoge qué presumir (última cagada, hitos, desbloqueos) y lo pega. Devuelve si pegó algo.
Future<bool> presumirEnMuro(BuildContext context) async {
  final yo = db.auth.currentUser?.id;
  if (yo == null) return false;
  final Map<String, dynamic> perfil;
  final Map<String, dynamic>? ultima;
  try {
    (perfil, ultima) = await (
      conReintento(() => db.from('profiles').select('cagadas').eq('id', yo).single()),
      conReintento(() => db
          .from('cagadas')
          .select('id, tipo')
          .eq('user_id', yo)
          .not('tipo', 'is', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()),
    ).wait;
  } catch (e) {
    if (context.mounted) _aviso(context, textoError(e));
    return false;
  }
  final total = (perfil['cagadas'] as num?)?.toInt() ?? 0;
  if (!context.mounted) return false;
  final logrados = hitos.where((h) => h <= total).toList().reversed;
  final mios = desbloqueos.where((d) => d.minimo <= total).toList().reversed;
  final tarjeta = await elegirPresumir(context, ultima: ultima, total: total, hitos: logrados, mios: mios);
  if (tarjeta == null || !context.mounted) return false;
  return pegarEnMuro(context, tarjeta);
}
