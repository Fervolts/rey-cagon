import 'package:flutter/material.dart';

import 'emoji.dart';

/// Algo que se desbloquea al llegar a [minimo] cagadas en total.
typedef Desbloqueo = ({String ranura, String emoji, String nombre, int minimo});

// Mismo catálogo que la tabla desbloqueos (supabase/migrations/…_accesorios.sql).
// El servidor rechaza lo que no esté desbloqueado.
const desbloqueos = <Desbloqueo>[
  (ranura: 'mascota', emoji: '🪰', nombre: 'Mosca', minimo: 1),
  (ranura: 'sombrero', emoji: '🧢', nombre: 'Gorra', minimo: 3),
  (ranura: 'lentes', emoji: '👓', nombre: 'Lentes', minimo: 5),
  (ranura: 'mascota', emoji: '🐛', nombre: 'Gusanito', minimo: 8),
  (ranura: 'sombrero', emoji: '👒', nombre: 'Sombrero de playa', minimo: 12),
  (ranura: 'avatar', emoji: '👽', nombre: 'Alien', minimo: 15),
  (ranura: 'lentes', emoji: '🕶️', nombre: 'Lentes oscuros', minimo: 20),
  (ranura: 'mascota', emoji: '🐀', nombre: 'Rata', minimo: 25),
  (ranura: 'sombrero', emoji: '🎓', nombre: 'Doctor en cagología', minimo: 30),
  (ranura: 'avatar', emoji: '🤖', nombre: 'Robot', minimo: 40),
  (ranura: 'mascota', emoji: '🪳', nombre: 'Cucaracha', minimo: 50),
  (ranura: 'sombrero', emoji: '🎩', nombre: 'Copa', minimo: 60),
  (ranura: 'lentes', emoji: '🥽', nombre: 'Goggles', minimo: 75),
  (ranura: 'avatar', emoji: '🐲', nombre: 'Dragón', minimo: 100),
  (ranura: 'mascota', emoji: '🦨', nombre: 'Mapurite', minimo: 125),
  (ranura: 'sombrero', emoji: '🪖', nombre: 'Casco', minimo: 150),
  (ranura: 'avatar', emoji: '💎', nombre: 'Diamante', minimo: 200),
  (ranura: 'mascota', emoji: '🦆', nombre: 'Pato', minimo: 250),
  (ranura: 'avatar', emoji: '🏆', nombre: 'Un año cagando', minimo: 365),
];

/// Lo próximo que se desbloquea con [total] cagadas, o null si ya tiene todo.
Desbloqueo? siguienteDesbloqueo(int total) {
  for (final d in desbloqueos) {
    if (d.minimo > total) return d;
  }
  return null;
}

/// Avatar con sus accesorios encima. Lee avatar, sombrero, lentes y mascota de [perfil]
/// (una fila de profiles, leaderboard o perfil). Ocupa [tamano]; los accesorios se salen
/// un poco del cuadro, como un sombrero.
class Avatar extends StatelessWidget {
  const Avatar(this.perfil, {super.key, this.tamano = 28});

  final Map<String, dynamic> perfil;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final t = tamano;
    final sombrero = perfil['sombrero'] as String?;
    final lentes = perfil['lentes'] as String?;
    final mascota = perfil['mascota'] as String?;
    return SizedBox(
      width: t,
      height: t,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Emoji(perfil['avatar'] ?? '💩', tamano: t),
          if (lentes != null) Positioned(left: t * .2, top: t * .38, child: Emoji(lentes, tamano: t * .6)),
          if (sombrero != null) Positioned(left: t * .2, top: -t * .22, child: Emoji(sombrero, tamano: t * .6)),
          if (mascota != null) Positioned(right: -t * .22, bottom: -t * .06, child: Emoji(mascota, tamano: t * .42)),
        ],
      ),
    );
  }
}
