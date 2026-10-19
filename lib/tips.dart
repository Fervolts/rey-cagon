import 'package:flutter/material.dart';

import 'emoji.dart';
import 'tema.dart';

const _tips = [
  ('💧', 'Toma agua', 'La fibra sin agua es cemento. Si tu pipí sale oscuro, te falta agua y a tu cagada también.'),
  ('🌽', 'Come fibra', 'Fruta, vegetales, granos, avena, caraotas. Sube de a poco o vas a vivir el Volcán en carne propia.'),
  ('🍑', 'Lechosa, ciruela y kiwi', 'Los clásicos de las abuelas funcionan. Dos kiwis al día tienen hasta estudios.'),
  ('🏃', 'Muévete', 'Caminar mueve el intestino. Media hora al día y el tráfico fluye.'),
  ('⏰', 'Hazte una hora', 'El cuerpo ama la rutina. Después del desayuno es la hora pico: el estómago lleno le avisa al intestino.'),
  ('☕', 'El cafecito ayuda', 'El café estimula el colon en mucha gente. No es casualidad que la cola del baño sea a las 8 a. m.'),
  ('🚽', 'Ponte en cuclillas', 'Sube los pies en un banquito, rodillas más arriba que las caderas. La tubería se endereza y sale sin pujar.'),
  ('🙅', 'No la aguantes', 'Si te dieron ganas, ve. Aguantarla la seca y la próxima es Piedritas de conejo.'),
  ('📱', 'Suelta el teléfono', 'Más de 10 minutos sentado no es cagar, es acampar. Pujar de más da hemorroides.'),
  ('🧻', 'Límpiate de adelante hacia atrás', 'Y sin frotar como lija. Si te irrita el papel, agua o toallitas sin perfume.'),
];

const _alarmas = [
  'Sangre en la cagada o cagada negra',
  'Cambios en tu ritmo que duran más de dos semanas',
  'Dolor fuerte de barriga, fiebre o vómito',
  'Diarrea por más de dos días o estreñimiento de más de una semana',
  'Bajar de peso sin estar intentándolo',
];

class PantallaTips extends StatelessWidget {
  const PantallaTips({super.key});

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('TIPS PARA CAGAR MEJOR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.suave,
              border: Border(left: BorderSide(color: acento, width: 4)),
            ),
            child: const Text(
              'Esto es entretenimiento, no consejo médico. Son tips generales: si algo te preocupa, habla con un médico.',
            ),
          ),
          const SizedBox(height: 16),
          for (final (i, (emoji, titulo, cuerpo)) in _tips.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borde))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text((i + 1).toString().padLeft(2, '0'),
                        style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.textoSuave)),
                  ),
                  Emoji(emoji, tamano: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: texto.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(cuerpo, style: texto.bodyMedium?.copyWith(color: p.textoSuave)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radio),
              side: const BorderSide(color: Color(0xFFB3261E)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Rotulo('Ve al médico si tienes'),
                  const SizedBox(height: 8),
                  for (final a in _alarmas)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('• $a'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
