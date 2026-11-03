import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ajustes_avisos.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'imperio/telemetria.dart';
import 'main.dart' show db;
import 'tema.dart';

// Cuántos push te llegaron en 7 días (RPC push_resumen_mio, migración avisos_menos) y la tarjeta "Ordena tus avisos"
// del inicio. Sin la RPC en el servidor no hay números ni tarjeta: nada falla.

/// La tarjeta sale con al menos tantos avisos en 7 días...
const minimoAvisosTarjeta = 25;

/// ...y, si la descartó, vuelve a salir pasados estos días.
const diasTarjetaOculta = 14;

/// SharedPreferences: cuándo la descartó (ms desde epoch).
const prefTarjetaAvisos = 'avisos_tarjeta_descartada';

/// Lo que devuelve push_resumen_mio: total de envíos (no de teléfonos), por categoría de push_ajustes y cuántas de
/// las categorías tiene prendidas.
class ResumenAvisos {
  const ResumenAvisos({required this.total, required this.porCategoria, required this.prendidas, required this.categorias});

  final int total;
  final Map<String, int> porCategoria;
  final int prendidas;
  final int categorias;

  bool get todasPrendidas => prendidas >= categorias;

  /// Cuántos llegaron de esa categoría (0 si ninguno).
  int de(String clave) => porCategoria[clave] ?? 0;

  /// null si no tiene la forma esperada.
  static ResumenAvisos? desdeJson(Object? json) {
    if (json is! Map) return null;
    final total = json['total'];
    final prendidas = json['prendidas'];
    final categorias = json['categorias'];
    if (total is! num || prendidas is! num || categorias is! num) return null;
    final por = json['por_categoria'];
    return ResumenAvisos(
      total: total.toInt(),
      prendidas: prendidas.toInt(),
      categorias: categorias.toInt(),
      porCategoria: {
        if (por is Map)
          for (final e in por.entries)
            if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
      },
    );
  }
}

/// Lee el resumen propio. null = no se pudo (sin sesión, sin red o la RPC todavía no existe).
Future<ResumenAvisos?> cargarResumenAvisos() async {
  try {
    return ResumenAvisos.desdeJson(await db.rpc('push_resumen_mio'));
  } catch (_) {
    return null;
  }
}

/// La tarjeta sale si tiene todas las categorías prendidas, le llegaron al menos [minimoAvisosTarjeta] en 7 días y no
/// la descartó en los últimos [diasTarjetaOculta] días.
bool debeMostrarTarjetaAvisos(ResumenAvisos? resumen, DateTime? descartadaEn, DateTime ahora) {
  if (resumen == null || !resumen.todasPrendidas || resumen.total < minimoAvisosTarjeta) return false;
  return !descartadaHacePoco(descartadaEn, ahora);
}

/// La descartó hace menos de [diasTarjetaOculta] días.
bool descartadaHacePoco(DateTime? descartadaEn, DateTime ahora) =>
    descartadaEn != null && ahora.difference(descartadaEn) < const Duration(days: diasTarjetaOculta);

/// La categoría que más avisos mandó (en el orden de [categoriasAvisos] si empatan); null si ninguna mandó.
String? categoriaQueMasManda(ResumenAvisos resumen) {
  String? mejor;
  var n = 0;
  for (final (clave, _, _, _) in categoriasAvisos) {
    if (resumen.de(clave) > n) {
      mejor = clave;
      n = resumen.de(clave);
    }
  }
  return mejor;
}

String _deLaCategoria(String clave) => switch (clave) {
      'cagadas' => tr('de cagadas de amigos', "from friends' poops"),
      'rachas' => tr('de RAMPAGE y HEXAKILL', 'from RAMPAGE and HEXAKILL'),
      'ganadores' => tr('de ganadores', 'about winners'),
      'cierres' => tr('de fin de periodo', 'about periods ending'),
      'chat' => tr('del Baño', 'from the Bathroom'),
      'retos' => tr('de retos', 'about challenges'),
      'seguidores' => tr('de nuevos seguidores', 'about new followers'),
      'imperio' => tr('del Imperio', 'from your Empire'),
      _ => '',
    };

/// "Esta semana te llegaron 47 avisos: 30 de cagadas de amigos. Elige cuáles quieres."
String textoTarjetaAvisos(ResumenAvisos resumen) {
  final total = resumen.total;
  final clave = categoriaQueMasManda(resumen);
  final detalle = clave == null ? '' : ': ${resumen.de(clave)} ${_deLaCategoria(clave)}';
  return tr(
    'Esta semana te llegaron $total ${total == 1 ? 'aviso' : 'avisos'}$detalle. Elige cuáles quieres.',
    'This week you got $total ${total == 1 ? 'alert' : 'alerts'}$detalle. Pick the ones you want.',
  );
}

/// Anota un evento de telemetría (en las pruebas, uno falso).
typedef AnotarEvento = void Function(String evento, Map<String, Object?> datos);

void _anotarDeVerdad(String evento, Map<String, Object?> datos) {
  Telemetria.instancia.registrar(evento, datos);
  // Fuera del Imperio nadie vacía la cola cada 60 s: se manda ya (no lanza; si falla, espera al próximo vaciar).
  Telemetria.instancia.vaciar();
}

/// Tarjeta del inicio "Ordena tus avisos": cuántos push le llegaron y un botón a Ajustes de notificaciones.
/// No ocupa nada si no le toca salir. Telemetría: avisos_tarjeta_ve / _abre / _descarta.
class TarjetaOrdenaAvisos extends StatefulWidget {
  const TarjetaOrdenaAvisos({super.key, this.cargar, this.ahora, this.anotar, this.abrirAjustes});

  /// Para pruebas: por defecto, la base, el reloj, la telemetría y la pantalla de ajustes.
  final Future<ResumenAvisos?> Function()? cargar;
  final DateTime Function()? ahora;
  final AnotarEvento? anotar;
  final Future<void> Function(BuildContext context)? abrirAjustes;

  @override
  State<TarjetaOrdenaAvisos> createState() => _TarjetaOrdenaAvisosState();
}

class _TarjetaOrdenaAvisosState extends State<TarjetaOrdenaAvisos> {
  ResumenAvisos? _resumen;
  bool _vista = false;

  DateTime get _ahora => (widget.ahora ?? DateTime.now)();
  AnotarEvento get _anotar => widget.anotar ?? _anotarDeVerdad;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<DateTime?> _descartadaEn() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(prefTarjetaAvisos);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cargar() async {
    final descartada = await _descartadaEn();
    // Descartada hace poco: ni pregunta al servidor.
    if (descartadaHacePoco(descartada, _ahora)) {
      if (mounted && _resumen != null) setState(() => _resumen = null);
      return;
    }
    ResumenAvisos? resumen;
    try {
      resumen = await (widget.cargar ?? cargarResumenAvisos)();
    } catch (_) {}
    if (!mounted) return;
    final sale = debeMostrarTarjetaAvisos(resumen, descartada, _ahora);
    setState(() => _resumen = sale ? resumen : null);
    if (sale && !_vista) {
      _vista = true;
      _anotar('avisos_tarjeta_ve', {'total': resumen!.total, 'categoria': categoriaQueMasManda(resumen)});
    }
  }

  Future<void> _abrir() async {
    final r = _resumen;
    _anotar('avisos_tarjeta_abre', {'total': r?.total});
    final abrir = widget.abrirAjustes ??
        (context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PantallaAjustesAvisos()));
    await abrir(context);
    // Al volver: si apagó alguna, la tarjeta ya no sale.
    if (mounted) await _cargar();
  }

  Future<void> _descartar() async {
    _anotar('avisos_tarjeta_descarta', {'total': _resumen?.total});
    setState(() => _resumen = null);
    try {
      await (await SharedPreferences.getInstance()).setInt(prefTarjetaAvisos, _ahora.millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumen;
    if (r == null) return const SizedBox.shrink();
    final p = paleta(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const ValueKey('tarjeta_ordena_avisos'),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        decoration: BoxDecoration(color: p.tarjeta, border: Border.all(color: p.bordeFuerte, width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Emoji('📱', tamano: 18),
            const SizedBox(width: 8),
            Expanded(child: Rotulo(tr('Ordena tus avisos', 'Sort your alerts'))),
            IconButton(
              key: const ValueKey('tarjeta_avisos_descartar'),
              onPressed: _descartar,
              tooltip: tr('No ahora', 'Not now'),
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(textoTarjetaAvisos(r), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('tarjeta_avisos_abrir'),
                onPressed: _abrir,
                child: Text(tr('ELEGIR AVISOS', 'PICK ALERTS')),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
