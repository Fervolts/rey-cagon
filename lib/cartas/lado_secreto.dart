import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../animaciones.dart';
import '../emoji.dart';
import '../genero.dart';
import '../idioma.dart';
import '../logros.dart';
import '../main.dart' show conReintento, textoError;
import '../nuclear.dart' show verdeNuclear;
import '../tema.dart';
import 'album.dart';
import 'catalogo.dart';
import 'logica.dart';
import 'nube.dart';

// El lado secreto del TRONO: el sobre del día, lo último que salió y los logros de colección.
// Solo se ve deslizando el TRONO a la izquierda, después de encontrar el secreto. Ver docs/CARTAS.md.

class LadoSecreto extends StatefulWidget {
  const LadoSecreto({super.key});

  @override
  State<LadoSecreto> createState() => _LadoSecretoState();
}

class _LadoSecretoState extends State<LadoSecreto> with AutomaticKeepAliveClientMixin {
  EstadoCartas? _estado;
  Object? _error;
  bool _abriendo = false;

  @override
  bool get wantKeepAlive => true;

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
      final e = await conReintento(estadoCartas);
      if (!mounted) return;
      setState(() {
        _estado = e;
        _error = null;
      });
      final alto = e.cartas.values.fold(0, (m, c) => math.max(m, c.nivel));
      for (final clave in logrosDeColeccion(distintas: e.cartas.length, nivelMasAlto: alto)) {
        if (!mounted) return;
        await ganarLogro(context, clave);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _abrir(Sobre s) async {
    final antes = _estado?.cartas ?? const {};
    setState(() => _abriendo = true);
    try {
      final abierto = await conReintento(() => abrirSobre(s.id));
      if (!mounted) return;
      if (abierto.tipo == 'rey') await ganarLogro(context, 'sobre_rey');
      if (!mounted) return;
      await showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .88),
        barrierDismissible: false,
        pageBuilder: (context, _, _) => Material(
          type: MaterialType.transparency,
          child: SafeArea(child: AbrirSobre(sobre: abierto, antes: antes, alCerrar: () => Navigator.pop(context))),
        ),
      );
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trServidor(e.message))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(textoError(e))));
    } finally {
      if (mounted) setState(() => _abriendo = false);
      // abrirSobre no avisa: así se recargan el lado secreto y el álbum.
      cartasCambiaron.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final estado = _estado;
    if (estado == null) {
      final error = _error;
      if (error == null) return const Center(child: CircularProgressIndicator());
      final sinSecreto = error is PostgrestException && error.message == 'sin_secreto';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(sinSecreto ? tr('Todavía no encontraste el lado secreto.', 'You have not found the secret side yet.') : textoError(error),
                textAlign: TextAlign.center),
            if (!sinSecreto) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: Text(tr('REINTENTAR', 'RETRY'))),
            ],
          ]),
        ),
      );
    }
    return VistaLadoSecreto(
      estado: estado,
      ahora: DateTime.now(),
      abriendo: _abriendo,
      alAbrir: _abrir,
      alAlbum: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaAlbum(inicial: estado))),
      alVerCarta: (n) => verCarta(context, n, estado.cartas[n]),
    );
  }
}

/// Todo el lado secreto sin red (para las capturas).
class VistaLadoSecreto extends StatelessWidget {
  const VistaLadoSecreto({
    super.key,
    required this.estado,
    required this.ahora,
    required this.alAbrir,
    required this.alAlbum,
    required this.alVerCarta,
    this.abriendo = false,
  });

  final EstadoCartas estado;
  final DateTime ahora;
  final bool abriendo;
  final ValueChanged<Sobre> alAbrir;
  final VoidCallback alAlbum;
  final ValueChanged<int> alVerCarta;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final sobre = estado.sobres.firstOrNull;
    final distintas = estado.cartas.length;
    final horas = horasHasta(estado.proximo, ahora);
    final chico = numeros(context, tamano: 12, color: p.textoSuave);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: p.acento, width: 2), borderRadius: BorderRadius.circular(radio)),
          child: Text(tr('SOLO PARA LOS QUE SABEN', 'ONLY FOR THOSE WHO KNOW'),
              style: numeros(context, tamano: 11, weight: FontWeight.w800, color: p.texto).copyWith(letterSpacing: 1.5)),
        ),
        const Spacer(),
        const Emoji('🔑', tamano: 22),
      ]),
      const SizedBox(height: 12),
      Text(tr('El lado secreto', 'The secret side'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 20),
      Rotulo(tr('Tu sobre de hoy', 'Your pack today')),
      const SizedBox(height: 8),
      if (sobre == null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
          child: Text(tr('Ya abriste el de hoy. Próximo sobre en $horas h.', 'You opened today\'s. Next pack in $horas h.'),
              textAlign: TextAlign.center, style: numeros(context, tamano: 13, weight: FontWeight.w700, color: p.textoSuave)),
        )
      else ...[
        Semantics(
          button: true,
          label: tr('Abrir el sobre', 'Open the pack'),
          child: GestureDetector(
            onTap: abriendo ? null : () => alAbrir(sobre),
            child: Opacity(opacity: abriendo ? .6 : 1, child: DibujoSobre(sobre: sobre)),
          ),
        ),
        const SizedBox(height: 10),
        _Porcentajes(sobre.tipo),
        const SizedBox(height: 8),
        Row(children: [
          if (estado.sobres.length > 1)
            Text(tr('+${estado.sobres.length - 1} sin abrir', '+${estado.sobres.length - 1} unopened'),
                style: chico.copyWith(color: p.acento, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(tr('Próximo sobre en $horas h', 'Next pack in $horas h'), style: chico),
        ]),
      ],
      const SizedBox(height: 24),
      Row(children: [
        Rotulo(tr('Últimas', 'Latest')),
        const Spacer(),
        Text('$distintas / ${cartas.length}', style: numeros(context, tamano: 13, weight: FontWeight.w800, color: p.texto)),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final ancho = (c.maxWidth - 5 * 6) / 6;
        return Row(children: [
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            if (i < estado.ultimas.length)
              GestureDetector(
                onTap: () => alVerCarta(estado.ultimas[i]),
                child: CartaVisual(n: estado.ultimas[i], mia: estado.cartas[estado.ultimas[i]], ancho: ancho),
              )
            else
              Container(
                width: ancho,
                height: ancho * 4 / 3,
                decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
              ),
          ],
        ]);
      }),
      const SizedBox(height: 24),
      Rotulo(tr('Logros de colección', 'Collection achievements')),
      const SizedBox(height: 8),
      _LogrosColeccion(distintas),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: alAlbum,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: p.bordeFuerte, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
        ),
        child: Text(tr('VER EL ÁLBUM', 'SEE THE ALBUM'), style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: p.texto)),
      ),
    ]);
  }
}

String _nombreSobre(Sobre s) => s.origen == 'misiones'
    ? tr('SOBRE DE MISIONES', 'MISSIONS PACK')
    : tr('SOBRE DEL DÍA', 'DAILY PACK');

String _nombreTipo(String tipo) => switch (tipo) {
      'plata' => tr('PLATA', 'SILVER'),
      'oro' => tr('ORO', 'GOLD'),
      'rey' => segun(tr('DEL REY', 'KING'), tr('DE LA REINA', 'QUEEN')),
      _ => tr('NORMAL', 'NORMAL'),
    };

/// El sobre amarillo rayado con la línea de corte punteada arriba.
class DibujoSobre extends StatelessWidget {
  const DibujoSobre({super.key, required this.sobre});

  final Sobre sobre;

  static const alto = 176.0;
  static const corte = 30.0;

  @override
  Widget build(BuildContext context) {
    final tinta = acentoTexto;
    final n = cartasDelSobre(sobre.tipo);
    return Container(
      height: alto,
      decoration: BoxDecoration(color: acento, border: Border.all(color: tinta, width: 2), borderRadius: BorderRadius.circular(radio)),
      child: CustomPaint(
        painter: _Rayas(tinta),
        child: Stack(children: [
          Positioned(
            top: 6,
            right: 8,
            child: Text(_nombreTipo(sobre.tipo), style: numeros(context, tamano: 10, weight: FontWeight.w900, color: tinta).copyWith(letterSpacing: 1.5)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: corte + 8),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(radio)),
                  child: const Emoji('🃏', tamano: 34),
                ),
                const SizedBox(height: 10),
                Text(_nombreSobre(sobre), style: numeros(context, tamano: 16, weight: FontWeight.w900, color: tinta).copyWith(letterSpacing: 2)),
                const SizedBox(height: 2),
                Text(tr('$n cartas · tócalo para abrir', '$n cards · tap to open'), style: numeros(context, tamano: 12, weight: FontWeight.w600, color: tinta)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Rayas extends CustomPainter {
  const _Rayas(this.tinta);

  final Color tinta;

  @override
  void paint(Canvas canvas, Size size) {
    final raya = Paint()
      ..color = tinta.withValues(alpha: .07)
      ..strokeWidth = 6;
    for (var x = -size.height; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), raya);
    }
    final punto = Paint()
      ..color = tinta.withValues(alpha: .6)
      ..strokeWidth = 1.5;
    for (var x = 6.0; x < size.width - 6; x += 12) {
      canvas.drawLine(Offset(x, DibujoSobre.corte), Offset(math.min(x + 7, size.width - 6), DibujoSobre.corte), punto);
    }
  }

  @override
  bool shouldRepaint(_Rayas old) => old.tinta != tinta;
}

/// Tira de 4 columnas: qué tan probable es cada rareza en este sobre.
class _Porcentajes extends StatelessWidget {
  const _Porcentajes(this.tipo);

  final String tipo;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final pct = porcentajesDelSobre(tipo);
    return Container(
      decoration: BoxDecoration(border: Border.all(color: p.borde), borderRadius: BorderRadius.circular(radio)),
      child: IntrinsicHeight(
        child: Row(children: [
          for (final r in Rareza.values) ...[
            if (r.index > 0) VerticalDivider(width: 1, color: p.borde),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Text('${pct[r.index]}%', style: numeros(context, tamano: 15, weight: FontWeight.w800, color: colorRareza(context, r))),
                  const SizedBox(height: 2),
                  Text(nombreRareza(r).toUpperCase(), style: numeros(context, tamano: 9, weight: FontWeight.w700, color: colorRareza(context, r))),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Las metas de la colección en casillas 🏆 y cuánto falta para la próxima.
class _LogrosColeccion extends StatelessWidget {
  const _LogrosColeccion(this.distintas);

  final int distintas;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final proxima = metasColeccion.where((m) => distintas < m).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < metasColeccion.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _Meta(metasColeccion[i], hecha: distintas >= metasColeccion[i])),
        ],
      ]),
      const SizedBox(height: 10),
      if (proxima != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(radio),
          child: LinearProgressIndicator(value: distintas / proxima, minHeight: 4, backgroundColor: p.suave, color: p.acento),
        ),
        const SizedBox(height: 6),
        Text(tr('Faltan ${proxima - distintas} para $proxima', '${proxima - distintas} to go for $proxima'),
            style: numeros(context, tamano: 12, color: p.textoSuave)),
      ] else
        Text(tr('Colección completa', 'Collection complete'), style: numeros(context, tamano: 12, weight: FontWeight.w800, color: p.acento)),
    ]);
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.meta, {required this.hecha});

  final int meta;
  final bool hecha;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Semantics(
      label: tr('$meta cartas${hecha ? ', conseguido' : ''}', '$meta cards${hecha ? ', unlocked' : ''}'),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: p.tarjeta,
          border: Border.all(color: hecha ? p.acento : p.borde, width: hecha ? 2 : 1),
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Column(children: [
          Opacity(opacity: hecha ? 1 : .3, child: const Emoji('🏆', tamano: 22)),
          const SizedBox(height: 4),
          Text('$meta', style: numeros(context, tamano: 13, weight: FontWeight.w800, color: hecha ? p.texto : p.textoSuave)),
        ]),
      ),
    );
  }
}

/// La apertura: el sobre se rasga y las cartas se voltean una a una.
/// Sin movimiento salen todas volteadas; con movimiento simple aparecen juntas.
class AbrirSobre extends StatefulWidget {
  const AbrirSobre({super.key, required this.sobre, required this.antes, required this.alCerrar, this.quieta = false});

  final SobreAbierto sobre;

  /// La colección antes de abrir, para saber las repetidas gastadas.
  final Map<int, MiCarta> antes;
  final VoidCallback alCerrar;

  /// Para las capturas: ya terminada.
  final bool quieta;

  @override
  State<AbrirSobre> createState() => _AbrirSobreState();
}

class _AbrirSobreState extends State<AbrirSobre> with SingleTickerProviderStateMixin {
  static const _rasgar = 700;
  static const _voltear = 450;

  late final AnimationController _c = AnimationController(vsync: this);
  Movimiento? _modo;

  int get _total => _rasgar + widget.sobre.cartas.length * _voltear;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_modo != null) return;
    _modo = widget.quieta ? Movimiento.nada : movimiento(context);
    switch (_modo!) {
      case Movimiento.nada:
        _c.value = 1;
      case Movimiento.simple:
        _c.duration = const Duration(milliseconds: 300);
        _c.forward();
      case Movimiento.completo:
        _c.duration = Duration(milliseconds: _total);
        _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sobre = widget.sobre;
    final sobreFalso = (id: 0, tipo: sobre.tipo, origen: 'diario');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Tocar adelanta hasta el final; ya terminado, cierra.
      onTap: () => _c.isCompleted ? widget.alCerrar() : _c.value = 1,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final completo = _modo == Movimiento.completo;
          final t = _c.value * _total;
          final rasgado = completo ? (t / _rasgar).clamp(0.0, 1.0) : 1.0;
          double vuelta(int i) => completo ? ((t - _rasgar - i * _voltear) / _voltear).clamp(0.0, 1.0) : 1.0;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Expanded(
                child: Center(
                  child: rasgado < 1
                      ? _SobreRasgandose(sobre: sobreFalso, avance: rasgado)
                      : Opacity(
                          opacity: _modo == Movimiento.simple ? _c.value : 1,
                          child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 14, children: [
                            for (var i = 0; i < sobre.cartas.length; i++)
                              _CartaQueSale(c: sobre.cartas[i], antes: widget.antes[sobre.cartas[i].n], vuelta: vuelta(i)),
                          ]),
                        ),
                ),
              ),
              Text(_c.isCompleted ? tr('TOCA PARA CERRAR', 'TAP TO CLOSE') : tr('TOCA PARA SALTAR', 'TAP TO SKIP'),
                  style: numeros(context, tamano: 12, weight: FontWeight.w700, color: Colors.white70).copyWith(letterSpacing: 2)),
            ]),
          );
        },
      ),
    );
  }
}

class _SobreRasgandose extends StatelessWidget {
  const _SobreRasgandose({required this.sobre, required this.avance});

  final Sobre sobre;
  final double avance;

  @override
  Widget build(BuildContext context) {
    final dibujo = SizedBox(width: 260, child: DibujoSobre(sobre: sobre));
    return Stack(clipBehavior: Clip.none, children: [
      ClipRect(clipper: const _Recorte(desde: DibujoSobre.corte), child: dibujo),
      Transform.translate(
        offset: Offset(avance * 70, -avance * 110),
        child: Transform.rotate(
          angle: avance * .5,
          child: Opacity(opacity: 1 - avance, child: ClipRect(clipper: const _Recorte(hasta: DibujoSobre.corte), child: dibujo)),
        ),
      ),
    ]);
  }
}

class _Recorte extends CustomClipper<Rect> {
  const _Recorte({this.desde, this.hasta});

  final double? desde;
  final double? hasta;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, desde ?? 0, size.width, hasta ?? size.height);

  @override
  bool shouldReclip(_Recorte old) => old.desde != desde || old.hasta != hasta;
}

/// Una carta del sobre: de espaldas hasta que [vuelta] pasa la mitad. Abajo dice NUEVA, MEJORABLE o +1 REPETIDA.
class _CartaQueSale extends StatelessWidget {
  const _CartaQueSale({required this.c, required this.antes, required this.vuelta});

  final CartaAbierta c;
  final MiCarta? antes;
  final double vuelta;

  static const ancho = 96.0;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final mia = (n: c.n, copias: c.copias, nivel: c.nivel, gastadas: antes?.gastadas ?? 0);
    final mejorable = !c.nueva && puedeMejorar(nivel: c.nivel, copias: c.copias, gastadas: mia.gastadas);
    final (texto, color) = c.nueva
        ? (tr('NUEVA', 'NEW'), p.acento)
        : mejorable
            ? (tr('MEJORABLE', 'UPGRADABLE'), verdeNuclear)
            : (tr('+1 REPETIDA', '+1 DUPLICATE'), Colors.white70);
    final deFrente = vuelta >= .5;
    final cara = deFrente
        ? CartaVisual(n: c.n, mia: mia, ancho: ancho)
        : Container(
            width: ancho,
            height: ancho * 4 / 3,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black, border: Border.all(color: p.acento, width: 2), borderRadius: BorderRadius.circular(radio)),
            child: const Emoji('🃏', tamano: 36),
          );
    // De 0 a .5 gira la espalda, de .5 a 1 la cara.
    final angulo = deFrente ? (1 - vuelta) * math.pi : vuelta * math.pi;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .001)
          ..rotateY(angulo),
        child: cara,
      ),
      const SizedBox(height: 6),
      Opacity(
        opacity: deFrente ? 1 : 0,
        child: Text(texto, style: numeros(context, tamano: 11, weight: FontWeight.w900, color: color).copyWith(letterSpacing: 1.2)),
      ),
    ]);
  }
}
