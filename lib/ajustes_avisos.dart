import 'package:flutter/material.dart';

import 'animaciones.dart';
import 'avisos_resumen.dart';
import 'emoji.dart';
import 'idioma.dart';
import 'main.dart' show conReintento, db, textoError;
import 'tema.dart';

// Qué notificaciones push le llegan a cada quien (public.push_ajustes, RPC push_avisos_mios / push_aviso).
// Apagar una categoría solo quita el push: lo que se guarda en el centro de avisos sigue llegando.
// Anuncios, versión nueva y soporte no se apagan.

/// Lee los interruptores propios: clave → prendido.
typedef CargarAvisos = Future<Map<String, bool>> Function();

/// Cambia uno.
typedef GuardarAviso = Future<void> Function(String clave, bool activo);

/// Las categorías, en el orden en que se muestran: (clave, emoji, nombre, descripción).
List<(String, String, String, String)> get categoriasAvisos => [
      ('cagadas', '💩', tr('Cagadas de tus amigos', "Friends' poops"), tr('Cada vez que alguien que sigues caga', 'Every time someone you follow poops')),
      ('rachas', '🔥', tr('RAMPAGE y HEXAKILL', 'RAMPAGE and HEXAKILL'), tr('Cuando un amigo va por la 5ª o la 6ª del día', 'When a friend hits 5 or 6 in one day')),
      ('ganadores', '🏆', tr('Ganadores', 'Winners'), tr('Quién ganó la semana, el mes y el año entre tus amigos', 'Who won the week, month and year among your friends')),
      ('cierres', '⏳', tr('Fin de periodo', 'Period ending'), tr('Horas antes del cierre: en qué puesto vas y a quién alcanzar', 'Hours before it closes: your spot and who to catch')),
      ('chat', '🚻', tr('Baño', 'Bathroom'), tr('Menciones y respuestas en el chat', 'Mentions and replies in the chat')),
      ('privados', '💌', tr('Privados', 'Private messages'), tr('Mensajes privados que te mandan', 'Private messages sent to you')),
      ('retos', '⚔️', tr('Retos', 'Challenges'), tr('El Cagadón: te retan, aceptan o se acaba', 'The Poop-off: challenged, accepted or over')),
      ('seguidores', '👀', tr('Nuevos seguidores', 'New followers'), tr('Cuando alguien empieza a seguirte', 'When someone starts following you')),
      ('imperio', '🏭', tr('Imperio', 'Empire'), tr('La poceta y la racha de tu Imperio', 'Your Empire\'s toilet and streak')),
    ];

Future<Map<String, bool>> _cargarDeLaBase() async {
  final fila = await conReintento(() => db.rpc('push_avisos_mios'));
  final mapa = (fila as Map?)?.cast<String, dynamic>() ?? const {};
  // 'privados' solo si la base ya la conoce (migración de privados): si no, la fila no sale.
  return {
    for (final (clave, _, _, _) in categoriasAvisos)
      if (clave != 'privados' || mapa.containsKey(clave)) clave: mapa[clave] as bool? ?? true,
  };
}

Future<void> _guardarEnLaBase(String clave, bool activo) =>
    conReintento(() => db.rpc('push_aviso', params: {'p_clave': clave, 'p_activo': activo}));

class PantallaAjustesAvisos extends StatefulWidget {
  const PantallaAjustesAvisos({super.key, this.cargar, this.guardar, this.resumen});

  /// Para pruebas: por defecto, la base.
  final CargarAvisos? cargar;
  final GuardarAviso? guardar;

  /// Cuántos llegaron en 7 días por categoría; null (o sin la RPC) = no se muestra nada.
  final Future<ResumenAvisos?> Function()? resumen;

  @override
  State<PantallaAjustesAvisos> createState() => _PantallaAjustesAvisosState();
}

class _PantallaAjustesAvisosState extends State<PantallaAjustesAvisos> {
  Map<String, bool>? _activos;
  ResumenAvisos? _resumen;
  String? _error;
  final _guardando = <String>{};

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    ResumenAvisos? r;
    try {
      r = await (widget.resumen ?? cargarResumenAvisos)();
    } catch (_) {}
    if (mounted && r != null) setState(() => _resumen = r);
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final activos = await (widget.cargar ?? _cargarDeLaBase)();
      if (mounted) setState(() => _activos = Map.of(activos));
    } catch (e) {
      if (mounted) setState(() => _error = textoError(e));
    }
  }

  Future<void> _cambiar(String clave, bool activo) async {
    final activos = _activos;
    if (activos == null || _guardando.contains(clave)) return;
    final antes = activos[clave] ?? true;
    setState(() {
      activos[clave] = activo;
      _guardando.add(clave);
    });
    try {
      await (widget.guardar ?? _guardarEnLaBase)(clave, activo);
    } catch (e) {
      if (mounted) {
        setState(() => activos[clave] = antes);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(textoError(e))));
      }
    } finally {
      if (mounted) setState(() => _guardando.remove(clave));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final activos = _activos;
    return Scaffold(
      appBar: AppBar(title: Text(tr('NOTIFICACIONES', 'NOTIFICATIONS'))),
      body: activos == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.textoSuave)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _cargar, child: Text(tr('REINTENTAR', 'RETRY'))),
                      ]),
                    ),
            )
          : ListView(
              padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 12, 16, 16)),
              children: [
                Text(
                  tr('Apagar una solo quita el push. Lo que se guarda en LECTURA DEL BAÑO sigue llegando.',
                      'Turning one off only stops the push. What gets saved in BATHROOM READING still shows up.'),
                  style: TextStyle(color: p.textoSuave, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: p.tarjeta,
                    border: Border.all(color: p.borde),
                    borderRadius: BorderRadius.circular(radio),
                  ),
                  child: Column(children: [
                    for (final (i, (clave, emoji, nombre, descripcion)) in categoriasAvisos.indexed)
                      if (clave != 'privados' || activos.containsKey(clave)) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: p.borde),
                      _FilaInterruptor(
                        key: ValueKey('aviso_$clave'),
                        emoji: emoji,
                        nombre: nombre,
                        descripcion: descripcion,
                        enSemana: _resumen?.de(clave),
                        activo: activos[clave] ?? true,
                        onCambio: (v) => _cambiar(clave, v),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
    );
  }
}

class _FilaInterruptor extends StatelessWidget {
  const _FilaInterruptor({super.key, required this.emoji, required this.nombre, required this.descripcion, this.enSemana, required this.activo, required this.onCambio});

  final String emoji, nombre, descripcion;

  /// Cuántos push de esta categoría le llegaron en 7 días (null = no se sabe, no se muestra).
  final int? enSemana;
  final bool activo;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Semantics(
      toggled: activo,
      label: nombre,
      child: InkWell(
        onTap: () => onCambio(!activo),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Emoji(emoji, tamano: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(descripcion, style: TextStyle(color: p.textoSuave, fontSize: 13)),
                if (enSemana != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    tr('$enSemana en 7 días', '$enSemana in 7 days'),
                    style: numeros(context, tamano: 11, weight: FontWeight.w700, color: p.textoSuave),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            _Interruptor(activo: activo),
          ]),
        ),
      ),
    );
  }
}

/// Interruptor cuadrado: borde de 1px, cuadrito que se corre, acento cuando está prendido.
class _Interruptor extends StatelessWidget {
  const _Interruptor({required this.activo});

  final bool activo;

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    final duracion = movimiento(context) == Movimiento.nada ? Duration.zero : const Duration(milliseconds: 120);
    return AnimatedContainer(
      duration: duracion,
      width: 44,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: activo ? acento : p.suave,
        border: Border.all(color: activo ? acentoTexto : p.bordeFuerte),
        borderRadius: BorderRadius.circular(radio),
      ),
      child: AnimatedAlign(
        duration: duracion,
        alignment: activo ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: activo ? acentoTexto : p.bordeFuerte,
            borderRadius: BorderRadius.circular(radio),
          ),
        ),
      ),
    );
  }
}
