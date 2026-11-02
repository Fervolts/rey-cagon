
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../chat.dart' show aceptoReglas, nombreSala;
import '../animaciones.dart';
import '../compartir.dart';
import '../emoji.dart';
import '../genero.dart';
import '../idioma.dart';
import '../main.dart' show db, textoError;
import '../tema.dart';
import 'control.dart';
import 'fila.dart' show textoEnUnaLinea;
import 'formato.dart';
import 'moneda_app.dart';
import 'motor.dart';
import 'tarjeta_cartera.dart';

// Compartir cartera: el estado de cuenta del Imperio en el chat (los números los pone el servidor)
// o como imagen para historias (los números salen de esta partida).

/// Un renglón de MOVIMIENTOS del estado de cuenta: un edificio, cuántos tiene y lo que produce por segundo.
class MovimientoCartera {
  const MovimientoCartera(this.edificio, this.cantidad, this.mps);

  final Edificio edificio;
  final int cantidad;
  final double mps;
}

/// Lo que sale en la imagen para historias. Se arma de la partida al abrir la hoja.
class DatosCartera {
  const DatosCartera({
    required this.saldo,
    required this.mps,
    required this.pujo,
    required this.mjTotal,
    required this.rollos,
    required this.jaladas,
    this.movimientos = const [],
    this.otros = 0,
    this.otrosMps = 0,
    this.cuenta = '0000',
    this.fecha,
  });

  /// Renglones de edificios que caben en la imagen; el resto va junto en "y N más".
  static const maxMovimientos = 4;

  factory DatosCartera.de(Imperio im, int ahora, {String? cuenta}) {
    final todos = [
      for (final e in edificios)
        if (im.cantidad(e.id) > 0) MovimientoCartera(e, im.cantidad(e.id), im.mpsEdificio(e.id, ahora)),
    ]..sort((a, b) => b.mps.compareTo(a.mps));
    final resto = todos.skip(maxMovimientos);
    return DatosCartera(
      saldo: im.saldo,
      mps: im.mps(ahora),
      pujo: im.valorPujo(ahora),
      mjTotal: im.partida.mjTotal,
      rollos: im.partida.rollos,
      jaladas: im.partida.jaladas,
      movimientos: todos.take(maxMovimientos).toList(),
      otros: resto.length,
      otrosMps: resto.fold(0, (s, m) => s + m.mps),
      cuenta: cuenta ?? '0000',
      fecha: DateTime.fromMillisecondsSinceEpoch(ahora),
    );
  }

  final double saldo, mps, pujo, mjTotal;
  final int rollos, jaladas;

  /// Los edificios que más producen, de mayor a menor (hasta [maxMovimientos]).
  final List<MovimientoCartera> movimientos;

  /// Cuántos edificios más tiene fuera de [movimientos] y lo que producen juntos.
  final int otros;
  final double otrosMps;

  /// Las 4 cifras de la cuenta de mentira (`cuentaDe`).
  final String cuenta;
  final DateTime? fecha;
}

/// Fecha del estado de cuenta: 31/10/2026 en español, 10/31/2026 en inglés.
String fechaBanco(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return enIngles ? '${dos(f.month)}/${dos(f.day)}/${f.year}' : '${dos(f.day)}/${dos(f.month)}/${f.year}';
}

const _yaPresumio = 'Espera un rato para volver a presumir tu cartera';
const _sinImperio = 'Todavía no tienes Imperio';

/// Hoja con las dos formas de presumir la cartera: EN EL CHAT y FUERA DE LA APP. Es la ventanilla del
/// "Banco del Trono": cabecera del banco, el estado de cuenta saliendo de la impresora y dos comprobantes.
Future<void> compartirCartera(BuildContext context, ControlImperio c) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
      builder: (context) => _HojaCartera(c, DatosCartera.de(c.imperio, DateTime.now().millisecondsSinceEpoch, cuenta: cuentaDe(_miId()))),
    );

/// El id de la sesión para sacar la cuenta de mentira; sin Supabase listo (pruebas) sale la cuenta de nadie.
String? _miId() {
  try {
    return db.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
}

class _HojaCartera extends StatefulWidget {
  const _HojaCartera(this.c, this.datos);

  final ControlImperio c;
  final DatosCartera datos;

  @override
  State<_HojaCartera> createState() => _HojaCarteraState();
}

class _HojaCarteraState extends State<_HojaCartera> {
  final _historia = GlobalKey();
  bool _ocupado = false;

  void _aviso(ScaffoldMessengerState? m, String texto) => m
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _alChat() async {
    if (_ocupado) return;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    if (!await aceptoReglas(context) || !mounted) return;
    setState(() => _ocupado = true);
    try {
      // El servidor lee la fila guardada: primero se guarda lo de ahora.
      await widget.c.guardarParaCartera();
      await db.from('mensajes').insert({
        'sala': 'global',
        'tarjeta': {'tipo': 'cartera'},
      });
      widget.c.compartioCartera('chat');
      nav.pop();
      _aviso(mensajero, tr('Publicado en $nombreSala 🚽', 'Posted in $nombreSala 🚽'));
    } catch (e) {
      final mensaje = e is PostgrestException ? e.message : null;
      _aviso(
        mensajero,
        mensaje == _yaPresumio
            ? tr('Ya la presumiste hace poco. Espera unos minutos.', 'You just showed it off. Wait a few minutes.')
            : mensaje == _sinImperio
                ? tr('Tu Imperio todavía no está guardado. Prueba en un rato.', "Your Empire isn't saved yet. Try again in a while.")
                : textoError(e),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _fuera() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final ok = await compartirImagen(context, _historia,
        nombre: 'rey-cagon-cartera.png',
        texto: tr('Mi Imperio en Rey Cagón. ¿Tú cuánto tienes? https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon',
            'My Empire in King of the Throne. How much do you have? https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon'));
    if (ok) {
      widget.c.compartioCartera('fuera');
    } else {
      _aviso(mensajero, tr('No se pudo compartir', 'Could not share'));
    }
    if (mounted) setState(() => _ocupado = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final d = widget.datos;
    final (fondoCab, letraCab) = cabeceraBanco(context);
    String mj(double v) => formatoMj(v, ingles: enIngles);
    final rotulo = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: p.textoSuave);
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 11, color: p.texto, letterSpacing: 1);
    final ancho = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        // La imagen para historias se arma fuera de la pantalla para poder capturarla.
        Positioned(
          left: -2 * HistoriaCartera.ancho - ancho,
          top: 0,
          child: RepaintBoundary(key: _historia, child: HistoriaCartera(widget.datos)),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera del banco.
                Container(
                  color: fondoCab,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border.all(color: letraCab), borderRadius: BorderRadius.circular(radio)),
                      child: const Emoji('🏛️', tamano: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        textoEnUnaLinea(tr('BANCO DEL TRONO', 'BANK OF THE THRONE'),
                            TextStyle(color: letraCab, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
                        Text(tr('Ventanilla de presumir', 'Show-off window'),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: letraCab.withValues(alpha: .75), fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(border: Border.all(color: letraCab)),
                      child: Text(_ocupado ? tr('PROCESANDO', 'PROCESSING') : tr('ABIERTO', 'OPEN'),
                          style: TextStyle(fontFamily: 'monospace', color: letraCab, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                  ]),
                ),
                SizedBox(
                  height: 2,
                  child: _ocupado ? LinearProgressIndicator(minHeight: 2, color: acento, backgroundColor: p.borde) : null,
                ),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _impreso(
                    context,
                    fondoCab,
                    Container(
                      width: 99,
                      height: 176,
                      decoration: BoxDecoration(border: Border.all(color: p.bordeFuerte)),
                      child: FittedBox(
                        child: SizedBox(width: HistoriaCartera.ancho, height: HistoriaCartera.alto, child: HistoriaCartera(d)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 4),
                      Text(tr('TITULAR', 'HOLDER'), style: rotulo),
                      textoEnUnaLinea(tr(segun('SU MAJESTAD EL REY', 'SU MAJESTAD LA REINA'), segun('HIS MAJESTY THE KING', 'HER MAJESTY THE QUEEN')),
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: p.texto)),
                      const SizedBox(height: 8),
                      Text(tr('CUENTA', 'ACCOUNT'), style: rotulo),
                      textoEnUnaLinea(cuentaEnmascarada(d.cuenta), mono),
                      const SizedBox(height: 8),
                      LineaPerforada(color: p.bordeFuerte),
                      const SizedBox(height: 8),
                      Text(tr('SALDO DISPONIBLE', 'AVAILABLE BALANCE'), style: rotulo),
                      const SizedBox(height: 2),
                      montoMj(mj(d.saldo), numeros(context, tamano: 26, weight: FontWeight.w900)),
                      textoEnUnaLinea('+${mj(d.mps)} MJ/s · ${fechaBanco(d.fecha ?? DateTime.now())}', mono.copyWith(color: p.textoSuave, fontSize: 10)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                Text(tr('ELIGE LA OPERACIÓN', 'PICK A TRANSACTION'), style: rotulo),
                const SizedBox(height: 6),
                _Comprobante(
                  numero: '01',
                  emoji: '🚽',
                  tipo: tr('DEPÓSITO', 'DEPOSIT'),
                  titulo: tr('EN EL CHAT', 'IN THE CHAT'),
                  texto: tr('Tu estado de cuenta en $nombreSala', 'Your account statement in $nombreSala'),
                  alTocar: _ocupado ? null : _alChat,
                ),
                const SizedBox(height: 8),
                _Comprobante(
                  numero: '02',
                  emoji: '📱',
                  tipo: tr('RETIRO EN IMAGEN', 'PRINTED COPY'),
                  titulo: tr('FUERA DE LA APP', 'OUTSIDE THE APP'),
                  texto: tr('Imagen para historias', 'Image for your stories'),
                  alTocar: _ocupado ? null : _fuera,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// El estado de cuenta saliendo de la ranura de la impresora: baja desde la raya de arriba (completo),
/// aparece con un fundido (simple) o ya está ahí (nada).
Widget _impreso(BuildContext context, Color ranura, Widget hoja) {
  final m = movimiento(context);
  final Widget cuerpo = switch (m) {
    Movimiento.nada => hoja,
    Movimiento.simple => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        builder: (_, v, h) => Opacity(opacity: v, child: h),
        child: hoja,
      ),
    Movimiento.completo => ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, h) => FractionalTranslation(translation: Offset(0, v - 1), child: h),
          child: hoja,
        ),
      ),
  };
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 107, height: 4, color: ranura),
    cuerpo,
  ]);
}

/// Comprobante de operación: talón con el emoji y el número, perforado, y la operación.
class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.numero, required this.emoji, required this.tipo, required this.titulo, required this.texto, required this.alTocar});

  final String numero, emoji, tipo, titulo, texto;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 10, color: p.textoSuave, letterSpacing: 1, fontWeight: FontWeight.w700);
    return Material(
      color: p.tarjeta,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.bordeFuerte), borderRadius: BorderRadius.circular(radio)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 60,
              color: p.suave,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Emoji(emoji, tamano: 28),
                const SizedBox(height: 4),
                Text('Nº $numero', style: mono),
              ]),
            ),
            LineaPerforada(color: p.bordeFuerte, vertical: true),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${tr('OPERACIÓN', 'TRANSACTION')} $numero · $tipo', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 9.5)),
                  const SizedBox(height: 2),
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 15, color: p.texto)),
                  Text(texto, style: TextStyle(fontSize: 12, color: p.textoSuave)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_forward, size: 18, color: alTocar == null ? p.textoSuave : p.texto),
            ),
          ]),
        ),
      ),
    );
  }
}

/// La imagen para historias (360x640, como la de la racha): el estado de cuenta del "Banco del Trono" impreso
/// en papel dentado, con los movimientos (MJ/s por edificio, rollos, jaladas), el saldo, el sello y el código.
class HistoriaCartera extends StatelessWidget {
  const HistoriaCartera(this.d, {super.key});

  static const ancho = 360.0;
  static const alto = 640.0;

  final DatosCartera d;

  @override
  Widget build(BuildContext context) {
    String mj(double v) => formatoMj(v, ingles: enIngles);
    const tinta = tintaBanco;
    final suave = tinta.withValues(alpha: .6);
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 11, color: tinta, letterSpacing: .5);
    final rotulo = TextStyle(color: suave, fontSize: 9.5, letterSpacing: 1.5, fontWeight: FontWeight.w800);
    const concepto = TextStyle(color: tinta, fontSize: 12, fontWeight: FontWeight.w700);
    final valor = numeros(context, tamano: 12, weight: FontWeight.w800, color: tinta);
    Widget renglon(String c, String v, {String? emoji, bool fuerte = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: RenglonBanco(c, v,
              emoji: emoji,
              estiloConcepto: fuerte ? concepto.copyWith(fontWeight: FontWeight.w900) : concepto,
              estiloValor: fuerte ? valor.copyWith(fontWeight: FontWeight.w900) : valor),
        );
    Widget dato(String titulo, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Row(children: [
            SizedBox(width: 62, child: Text(titulo, style: mono.copyWith(color: suave, fontSize: 10))),
            Expanded(child: textoEnUnaLinea(texto, mono.copyWith(fontWeight: FontWeight.w700))),
          ]),
        );
    Widget perforado() => const Padding(padding: EdgeInsets.symmetric(vertical: 7), child: LineaPerforada(color: Color(0x66171513)));
    final fecha = d.fecha ?? DateTime.now();
    final compacta = '${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}';
    return SizedBox(
      width: ancho,
      height: alto,
      child: ColoredBox(
        color: const Color(0xFF0B0A09),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Column(
            children: [
              Expanded(
                child: PapelDentado(
                  color: papelBanco,
                  arriba: true,
                  diente: 12,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Cabecera del banco.
                        Container(
                          color: tinta,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: Row(children: [
                            const Emoji('🏛️', tamano: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                textoEnUnaLinea(tr('BANCO DEL TRONO', 'BANK OF THE THRONE'),
                                    TextStyle(color: acento, fontWeight: FontWeight.w900, letterSpacing: 2.5, fontSize: 15)),
                                Text(tr('Sucursal Rey Cagón · Desde siempre', 'King of the Throne branch · Since forever'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 9.5)),
                              ]),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Expanded(
                            child: Text(tr('ESTADO DE CUENTA', 'ACCOUNT STATEMENT'),
                                maxLines: 1, style: const TextStyle(color: tinta, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 15)),
                          ),
                          Text(fechaBanco(fecha), style: mono.copyWith(color: suave)),
                        ]),
                        const SizedBox(height: 6),
                        dato(tr('TITULAR', 'HOLDER'),
                            tr(segun('SU MAJESTAD EL REY', 'SU MAJESTAD LA REINA'), segun('HIS MAJESTY THE KING', 'HER MAJESTY THE QUEEN'))),
                        dato(tr('CUENTA', 'ACCOUNT'), cuentaEnmascarada(d.cuenta)),
                        dato(tr('TIPO', 'TYPE'), tr('CORRIENTE DE MOJONES', 'CHECKING · TURDS')),
                        perforado(),
                        Row(children: [
                          Expanded(child: Text(tr('MOVIMIENTOS', 'TRANSACTIONS'), style: rotulo)),
                          Text('MJ/S', style: rotulo),
                        ]),
                        const SizedBox(height: 2),
                        if (d.movimientos.isEmpty) renglon(tr('Sin edificios todavía', 'No buildings yet'), '0', emoji: '🚽'),
                        for (final m in d.movimientos)
                          renglon('${tr(m.edificio.nombreEs, m.edificio.nombreEn)} x${formatoCantidad(m.cantidad, ingles: enIngles)}', '+${mj(m.mps)}',
                              emoji: m.edificio.emoji),
                        if (d.otros > 0)
                          renglon(tr('Y ${d.otros} ${d.otros == 1 ? 'edificio' : 'edificios'} más', 'And ${d.otros} more'), '+${mj(d.otrosMps)}'),
                        renglon(tr('TOTAL MJ/S', 'TOTAL MJ/S'), '+${mj(d.mps)}', fuerte: true),
                        perforado(),
                        renglon(tr('MJ POR PUJO', 'MJ PER TAP'), mj(d.pujo), emoji: '💩'),
                        renglon(tr('ROLLOS DE ORO', 'GOLDEN ROLLS'), formatoCantidad(d.rollos, ingles: enIngles), emoji: '🧻'),
                        renglon(tr('JALADAS DE CADENA', 'CHAIN FLUSHES'), formatoCantidad(d.jaladas, ingles: enIngles), emoji: '🚽'),
                        renglon(tr('GANADO EN TOTAL', 'EARNED IN TOTAL'), mj(d.mjTotal), emoji: '💰'),
                        const Spacer(),
                        // Saldo con el sello encima.
                        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Expanded(
                            child: Container(
                              color: acento,
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tr('SALDO DISPONIBLE', 'AVAILABLE BALANCE'),
                                    style: TextStyle(color: acentoTexto, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
                                montoMj(mj(d.saldo), numeros(context, tamano: 34, weight: FontWeight.w900, color: acentoTexto)),
                              ]),
                            ),
                          ),
                          Transform.translate(offset: const Offset(-14, 0), child: const _Sello()),
                        ]),
                        const SizedBox(height: 10),
                        CodigoBarras(semilla: int.tryParse(d.cuenta) ?? 0, color: tinta, alto: 36),
                        const SizedBox(height: 2),
                        Text('RC ${d.cuenta} $compacta 00', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 9.5, letterSpacing: 3, color: suave)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Emoji('🚽', tamano: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('¿Tú cuánto tienes?', 'How much do you have?'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                        Text(tr('Rey Cagón en Google Play', 'King of the Throne on Google Play'),
                            style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sello de goma "PAGADO POR EL REY" (o la reina), torcido como cuando lo ponen a mano.
class _Sello extends StatelessWidget {
  const _Sello();

  @override
  Widget build(BuildContext context) {
    final tinta = tintaBanco.withValues(alpha: .8);
    return Transform.rotate(
      angle: -.22,
      child: Container(
        width: 84,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(border: Border.all(color: tinta, width: 2)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(border: Border.all(color: tinta)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            textoEnUnaLinea(tr('PAGADO', 'PAID'), TextStyle(color: tinta, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 2),
                alineacion: Alignment.center),
            textoEnUnaLinea(tr(segun('POR EL REY', 'POR LA REINA'), segun('BY THE KING', 'BY THE QUEEN')),
                TextStyle(color: tinta, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 1), alineacion: Alignment.center),
          ]),
        ),
      ),
    );
  }
}
