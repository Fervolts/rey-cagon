import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accesorios.dart';
import 'emoji.dart';
import 'genero.dart';
import 'idioma.dart';
import 'main.dart' show db;
import 'perfil.dart' show PantallaBuscar, avataresGratis;
import 'tema.dart';
import 'tipos.dart';

/// Bienvenida para la gente nueva: seis pantallas que se pasan deslizando. La última trae el
/// aviso de entretenimiento; al cerrarla se pide el permiso de notificaciones.
class PantallaBienvenida extends StatefulWidget {
  const PantallaBienvenida({super.key});

  @override
  State<PantallaBienvenida> createState() => _PantallaBienvenidaState();
}

class _PantallaBienvenidaState extends State<PantallaBienvenida> {
  static const _total = 6;
  final _paginas = PageController();
  int _pagina = 0;
  String _avatar = '💩';
  String? _genero;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (_pagina < _total - 1) {
      _paginas.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      // El género se guarda al salir: elegir varias veces aquí no gasta el cambio del año.
      if (_genero != null) {
        guardarGenero(_genero);
        db.from('profiles').update({'genero': _genero}).eq('id', db.auth.currentUser!.id).catchError((_) => null);
      }
      Navigator.pop(context);
    }
  }

  Future<void> _elegirAvatar(String a) async {
    setState(() => _avatar = a);
    await db.from('profiles').update({'avatar': a}).eq('id', db.auth.currentUser!.id).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final ultima = _pagina == _total - 1;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ultima
                      ? null
                      : TextButton(
                          onPressed: () => _paginas.animateToPage(_total - 1,
                              duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic),
                          child: Text(tr('SALTAR', 'SKIP')),
                        ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _paginas,
                  onPageChanged: (i) => setState(() => _pagina = i),
                  children: [
                    _Pagina(
                      visual: const _Rebote(child: Emoji('👑', tamano: 150)),
                      titulo: tr(segun('Bienvenido, rey', 'Bienvenida, reina'), 'Welcome, your majesty'),
                      texto: tr('Aquí compites con tus amigos por quién caga más. Semana, mes, trimestre y año.',
                          'Here you compete with your friends over who poops the most. Week, month, quarter and year.'),
                    ),
                    _Pagina(
                      visual: _Rebote(child: Emoji(generos[_genero]?.$1 ?? '🫅', tamano: 150)),
                      titulo: tr('¿Rey o reina?', 'King or queen?'),
                      texto: tr('Para saber cómo tratarte en la corte. Lo puedes cambiar en tu perfil una vez al año.',
                          'So the court knows how to address you. You can change it in your profile once a year.'),
                      extra: ElegirGenero(valor: _genero, onTap: (g) => setState(() => _genero = miGenero = g)),
                    ),
                    _Pagina(
                      visual: const _BotonDeMuestra(),
                      titulo: tr('Cagaste, lo tocas', 'You pooped, you tap it'),
                      texto: tr(
                          'Cada vez que vayas al baño, dale a CAGUÉ y dinos qué salió. '
                              'Una por hora como máximo: sin trampas.',
                          'Every time you hit the bathroom, tap I POOPED and tell us what came out. '
                              'One per hour max: no cheating.'),
                    ),
                    _Pagina(
                      visual: const _Rebote(child: Emoji('👀', tamano: 150)),
                      titulo: tr('Busca a tus amigos', 'Find your friends'),
                      texto: tr('Síguelos para competir. Solo te llegan avisos de la gente que sigues.',
                          'Follow them to compete. You only get alerts from people you follow.'),
                      extra: OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaBuscar())),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(tr('BUSCAR AMIGOS', 'FIND FRIENDS')),
                      ),
                    ),
                    _Pagina(
                      visual: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Avatar({'avatar': _avatar}, tamano: 120),
                      ),
                      titulo: tr('Elige tu avatar', 'Pick your avatar'),
                      texto: tr('Mientras más cagas, más sombreros, lentes y mascotas desbloqueas.',
                          'The more you poop, the more hats, glasses and pets you unlock.'),
                      extra: Column(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final a in avataresGratis)
                                ChoiceChip(
                                  label: Emoji(a, tamano: 26),
                                  selected: a == _avatar,
                                  showCheckmark: false,
                                  onSelected: (_) => _elegirAvatar(a),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final d in desbloqueos.take(4))
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Column(
                                    children: [
                                      Opacity(opacity: .35, child: Emoji(d.emoji, tamano: 30)),
                                      Text('${d.minimo}', style: numeros(context, tamano: 11, color: p.textoSuave)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _Pagina(
                      visual: const _Rebote(child: Emoji('🧻', tamano: 150)),
                      titulo: tr('Último detalle', 'One last thing'),
                      texto: disclaimer,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _total; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _pagina ? 22 : 8,
                            height: 8,
                            color: i == _pagina ? acento : p.borde,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _siguiente,
                        child: Text(ultima ? tr('ENTENDIDO, A CAGAR', "GOT IT, LET'S POOP") : tr('SIGUIENTE', 'NEXT')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pagina extends StatelessWidget {
  const _Pagina({required this.visual, required this.titulo, required this.texto, this.extra});

  final Widget visual;
  final String titulo;
  final String texto;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 24),
        SizedBox(height: 210, child: Center(child: visual)),
        const SizedBox(height: 24),
        Text(titulo.toUpperCase(), style: texto.headlineLarge),
        Container(width: 48, height: 4, color: acento, margin: const EdgeInsets.symmetric(vertical: 12)),
        Text(this.texto, style: texto.bodyLarge?.copyWith(color: paleta(context).textoSuave, height: 1.4)),
        if (extra != null) ...[const SizedBox(height: 20), extra!],
      ],
    );
  }
}

/// Rebote suave, para que la pantalla no se sienta quieta.
class _Rebote extends StatefulWidget {
  const _Rebote({required this.child});

  final Widget child;

  @override
  State<_Rebote> createState() => _ReboteState();
}

class _ReboteState extends State<_Rebote> with SingleTickerProviderStateMixin {
  late final _reloj = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _reloj,
        builder: (context, hijo) => Transform.translate(
          offset: Offset(0, -10 * math.sin(_reloj.value * math.pi).abs()),
          child: hijo,
        ),
        child: widget.child,
      );
}

/// El botón CAGUÉ de mentira, latiendo como si pidiera que lo toquen.
class _BotonDeMuestra extends StatefulWidget {
  const _BotonDeMuestra();

  @override
  State<_BotonDeMuestra> createState() => _BotonDeMuestraState();
}

class _BotonDeMuestraState extends State<_BotonDeMuestra> with SingleTickerProviderStateMixin {
  late final _reloj = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return AnimatedBuilder(
      animation: _reloj,
      builder: (context, _) {
        final v = _reloj.value;
        // Dos latidos y una pausa; en el segundo se "aprieta" y se pone amarillo.
        final latido = v < .5 ? math.sin(v * 4 * math.pi).abs() : 0.0;
        final apretado = v > .2 && v < .3;
        return Transform.scale(
          scale: 1 - .06 * latido,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(shape: BoxShape.circle, color: apretado ? acento : p.primario),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Emoji('💩', tamano: 80),
                Text(tr('CAGUÉ', 'I POOPED'),
                    style: TextStyle(
                      color: apretado ? acentoTexto : p.sobrePrimario,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}
