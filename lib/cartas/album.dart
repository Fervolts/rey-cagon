import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../animaciones.dart';
import '../emoji.dart';
import '../idioma.dart';
import '../logros.dart';
import '../main.dart' show textoError;
import '../tema.dart';
import 'catalogo.dart';
import 'logica.dart';
import 'nube.dart';

// El álbum de las 128 cartas y cómo se ve cada una según su nivel. Ver docs/CARTAS.md.

const _plata = Color(0xFFB8BEC6);
const _oro = Color(0xFFD4A017);
const _arcoiris = [Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFFFFCC00), Color(0xFF34C759), Color(0xFF007AFF), Color(0xFFAF52DE), Color(0xFFFF3B30)];

/// Nombre del nivel, como en docs/CARTAS.md.
String nombreNivel(int nivel) => switch (nivel) {
      0 => tr('descolorida', 'faded'),
      1 => tr('normal', 'normal'),
      2 => tr('holográfica', 'holo'),
      3 => tr('plateada', 'silver'),
      4 => tr('dorada', 'gold'),
      _ => tr('rainbow', 'rainbow'),
    };

String nombreRareza(Rareza r) => switch (r) {
      Rareza.comun => tr('común', 'common'),
      Rareza.rara => tr('rara', 'rare'),
      Rareza.epica => tr('épica', 'epic'),
      Rareza.legendaria => tr('legendaria', 'legendary'),
    };

/// Épica y legendaria van en amarillo; común y rara en gris.
Color colorRareza(BuildContext context, Rareza r) => r.index >= Rareza.epica.index ? paleta(context).acento : paleta(context).textoSuave;

/// De 1 a 4 cuadritos según la rareza.
class Cuadritos extends StatelessWidget {
  const Cuadritos(this.rareza, {super.key, this.tamano = 6});

  final Rareza rareza;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final c = colorRareza(context, rareza);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i <= rareza.index; i++) ...[
        if (i > 0) SizedBox(width: tamano / 3),
        Container(width: tamano, height: tamano, color: c),
      ],
    ]);
  }
}

/// Una carta. Sin [mia] es una silueta con ❓. El marco va por rareza y, desde el nivel 3, por nivel.
/// Los niveles 2 (holo) y 5 (rainbow) se mueven, salvo con el movimiento apagado.
class CartaVisual extends StatefulWidget {
  const CartaVisual({super.key, required this.n, required this.mia, this.ancho = 80});

  final int n;
  final MiCarta? mia;
  final double ancho;

  @override
  State<CartaVisual> createState() => _CartaVisualState();
}

class _CartaVisualState extends State<CartaVisual> with SingleTickerProviderStateMixin {
  AnimationController? _brillo;

  int get _nivel => widget.mia?.nivel ?? 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustar();
  }

  @override
  void didUpdateWidget(CartaVisual old) {
    super.didUpdateWidget(old);
    _ajustar();
  }

  // El controlador solo existe para holo y rainbow con movimiento.
  void _ajustar() {
    final anima = widget.mia != null && (_nivel == 2 || _nivel == 5) && movimiento(context) != Movimiento.nada;
    if (anima && _brillo == null) {
      _brillo = AnimationController(vsync: this, duration: Duration(milliseconds: _nivel == 5 ? 3000 : 2400))..repeat();
    } else if (!anima && _brillo != null) {
      _brillo!.dispose();
      _brillo = null;
    }
  }

  @override
  void dispose() {
    _brillo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = carta(widget.n);
    final mia = widget.mia;
    final w = widget.ancho;
    final h = w * 4 / 3;
    final grueso = w < 60 ? 1.5 : 2.0;
    final (Color marco, double ancho) = mia == null
        ? (p.borde, 1)
        : switch (_nivel) {
            3 => (_plata, grueso + 1),
            4 => (_oro, grueso + 1),
            _ => switch (c.rareza) {
                Rareza.legendaria => (p.acento, grueso),
                Rareza.epica => (p.bordeFuerte, grueso),
                Rareza.rara => (p.bordeFuerte, 1.0),
                Rareza.comun => (p.borde, 1.0),
              },
          };
    Widget cara = mia == null
        ? Center(child: Text('?', style: numeros(context, tamano: w * .42, weight: FontWeight.w900, color: p.borde)))
        : Column(children: [
            Expanded(child: Center(child: Emoji(c.emoji, tamano: w * .5))),
            Padding(padding: EdgeInsets.only(bottom: w * .08), child: Cuadritos(c.rareza, tamano: math.max(4, w / 14))),
          ]);
    // Nivel 0: descolorida.
    if (mia != null && _nivel == 0) {
      cara = ColorFiltered(
        colorFilter: const ColorFilter.matrix([.33, .33, .33, 0, 0, .33, .33, .33, 0, 0, .33, .33, .33, 0, 0, 0, 0, 0, .6, 0]),
        child: cara,
      );
    }
    final fondo = switch (_nivel) {
      3 when mia != null => Color.lerp(p.tarjeta, _plata, .12)!,
      4 when mia != null => Color.lerp(p.tarjeta, _oro, .12)!,
      _ => mia == null ? p.suave : p.tarjeta,
    };
    final brillo = _brillo;
    Widget caja(double t) {
      final rainbow = mia != null && _nivel == 5;
      final holo = mia != null && _nivel == 2;
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(radio),
          border: rainbow ? null : Border.all(color: marco, width: ancho),
          gradient: rainbow
              ? SweepGradient(colors: _arcoiris, transform: GradientRotation(t * 2 * math.pi))
              : null,
        ),
        padding: rainbow ? EdgeInsets.all(grueso + 1) : null,
        child: Container(
          decoration: rainbow ? BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(radio)) : null,
          child: Stack(fit: StackFit.expand, children: [
            cara,
            if (holo || rainbow)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.5 + 3 * t, -1),
                      end: Alignment(-0.5 + 3 * t, 1),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        (rainbow ? const Color(0xFFFFCCFF) : const Color(0xFFBFF6FF)).withValues(alpha: .45),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
    }

    return Semantics(
      label: mia == null ? tr('Carta ${widget.n}, sin conseguir', 'Card ${widget.n}, not found') : '${nombreCarta(c)}, ${nombreNivel(_nivel)}',
      excludeSemantics: true,
      child: brillo == null ? caja(.5) : AnimatedBuilder(animation: brillo, builder: (context, _) => caja(brillo.value)),
    );
  }
}

/// Las 128 cartas en una grilla. Tocar una conseguida abre su detalle con MEJORAR.
class PantallaAlbum extends StatefulWidget {
  const PantallaAlbum({super.key, this.inicial});

  /// Lo que ya tenía el lado secreto, para no arrancar en blanco.
  final EstadoCartas? inicial;

  @override
  State<PantallaAlbum> createState() => _PantallaAlbumState();
}

class _PantallaAlbumState extends State<PantallaAlbum> {
  late Map<int, MiCarta>? _cartas = widget.inicial?.cartas;
  Object? _error;

  @override
  void initState() {
    super.initState();
    cartasCambiaron.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    cartasCambiaron.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final e = await estadoCartas();
      if (!mounted) return;
      setState(() {
        _cartas = e.cartas;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartas = _cartas;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Álbum', 'Album'))),
      body: cartas == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(textoError(_error!)))
          : VistaAlbum(cartas: cartas, alTocar: (n) => verCarta(context, n, cartas[n])),
    );
  }
}

/// La grilla del álbum, pura (para las capturas).
class VistaAlbum extends StatelessWidget {
  const VistaAlbum({super.key, required this.cartas, required this.alTocar});

  final Map<int, MiCarta> cartas;
  final ValueChanged<int> alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        sliver: SliverToBoxAdapter(
          child: Row(children: [
            Rotulo(tr('Colección', 'Collection')),
            const Spacer(),
            Text('${cartas.length} / $_total', style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.texto)),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        sliver: SliverLayoutBuilder(builder: (context, c) {
          final ancho = (c.crossAxisExtent - 3 * 8) / 4;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3 / 4,
            ),
            delegate: SliverChildBuilderDelegate(
              childCount: _total,
              (context, i) {
                final n = i + 1;
                final mia = cartas[n];
                return GestureDetector(
                  onTap: mia == null ? null : () => alTocar(n),
                  child: Stack(children: [
                    CartaVisual(n: n, mia: mia, ancho: ancho),
                    // Avisa si alcanza para subir.
                    if (mia != null && puedeMejorar(nivel: mia.nivel, copias: mia.copias, gastadas: mia.gastadas))
                      Positioned(top: 3, right: 3, child: Container(width: 8, height: 8, color: p.acento)),
                  ]),
                );
              },
            ),
          );
        }),
      ),
    ]);
  }
}

/// El campo `cartas` de VistaAlbum tapa la lista del catálogo.
final _total = cartas.length;

/// El detalle de una carta en una hoja de abajo, con MEJORAR.
Future<void> verCarta(BuildContext context, int n, MiCarta? mia) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
      builder: (_) => _HojaCarta(n: n, mia: mia),
    );

class _HojaCarta extends StatefulWidget {
  const _HojaCarta({required this.n, required this.mia});

  final int n;
  final MiCarta? mia;

  @override
  State<_HojaCarta> createState() => _HojaCartaState();
}

class _HojaCartaState extends State<_HojaCarta> {
  late MiCarta? _mia = widget.mia;
  bool _mejorando = false;
  String? _error;

  Future<void> _mejorar() async {
    setState(() {
      _mejorando = true;
      _error = null;
    });
    try {
      final m = await mejorarCarta(widget.n);
      if (!mounted) return;
      setState(() => _mia = m);
      for (final clave in logrosDeColeccion(distintas: 0, nivelMasAlto: m.nivel)) {
        if (!mounted) break;
        await ganarLogro(context, clave);
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = trServidor(e.message));
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
    } finally {
      if (mounted) setState(() => _mejorando = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: DetalleCarta(n: widget.n, mia: _mia, mejorando: _mejorando, error: _error, alMejorar: _mejorar),
        ),
      );
}

/// Detalle puro: carta grande, nombre, frase, rareza, nivel, repetidas y el botón MEJORAR.
class DetalleCarta extends StatelessWidget {
  const DetalleCarta({super.key, required this.n, required this.mia, this.mejorando = false, this.error, this.alMejorar});

  final int n;
  final MiCarta? mia;
  final bool mejorando;
  final String? error;
  final VoidCallback? alMejorar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final c = carta(n);
    final mia = this.mia;
    final nivel = mia?.nivel ?? 0;
    final repetidas = mia == null ? 0 : repetidasDisponibles(mia.copias, mia.gastadas);
    final puede = mia != null && puedeMejorar(nivel: nivel, copias: mia.copias, gastadas: mia.gastadas);
    final dato = numeros(context, tamano: 12, weight: FontWeight.w700, color: p.textoSuave);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: CartaVisual(n: n, mia: mia, ancho: 150)),
      const SizedBox(height: 16),
      Row(children: [
        Text('#$n', style: dato),
        const SizedBox(width: 8),
        Cuadritos(c.rareza, tamano: 8),
        const SizedBox(width: 6),
        Text(nombreRareza(c.rareza).toUpperCase(), style: dato.copyWith(color: colorRareza(context, c.rareza))),
        const Spacer(),
        if (mia != null) Text('${tr('NIVEL', 'LEVEL')} $nivel · ${nombreNivel(nivel).toUpperCase()}', style: dato),
      ]),
      const SizedBox(height: 8),
      Text(mia == null ? '???' : nombreCarta(c), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      if (mia != null) ...[
        const SizedBox(height: 4),
        Text(fraseCarta(c), style: TextStyle(color: p.textoSuave, height: 1.3)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text(tr('Repetidas: $repetidas', 'Duplicates: $repetidas'), style: dato)),
          if (nivel < nivelMax) Text(tr('Subir cuesta ${costoMejora(nivel)}', 'Upgrade costs ${costoMejora(nivel)}'), style: dato),
        ]),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: puede && !mejorando ? alMejorar : null,
          style: FilledButton.styleFrom(
            backgroundColor: acento,
            foregroundColor: acentoTexto,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
          ),
          child: mejorando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(nivel >= nivelMax ? tr('NIVEL MÁXIMO', 'MAX LEVEL') : tr('MEJORAR', 'UPGRADE'),
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
      ],
    ]);
  }
}
