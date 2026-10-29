import 'dart:async';

import 'package:flutter/material.dart';

import 'idioma.dart';
import 'tema.dart';

// Los rankings cierran a la medianoche de Venezuela (UTC-4, sin horario de verano), igual que
// date_trunc en el servidor: la semana empieza el lunes.
const _caracas = Duration(hours: -4);

Map<String, String> get periodos => {
      'week': tr('Semana', 'Week'),
      'month': tr('Mes', 'Month'),
      'year': tr('Año', 'Year'),
    };

/// Cuándo cierra el periodo que está corriendo, en UTC.
DateTime cierreDe(String periodo, [DateTime? ahora]) {
  // La hora de Caracas guardada en los campos de una fecha UTC, para sacar día y mes de allá.
  final c = (ahora ?? DateTime.now()).toUtc().add(_caracas);
  final hoy = DateTime.utc(c.year, c.month, c.day);
  final fin = switch (periodo) {
    'week' => hoy.add(Duration(days: 8 - c.weekday)),
    'month' => DateTime.utc(c.year, c.month + 1),
    'year' => DateTime.utc(c.year + 1),
    _ => hoy.add(const Duration(days: 1)),
  };
  return fin.subtract(_caracas);
}

/// "3 d 4 h", "5 h 12 min" o "12 min".
String cuantoFalta(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
}

/// Debajo de las pestañas del ranking: cuánto le queda al periodo. El último día se pone rojo.
class ContadorCierre extends StatefulWidget {
  const ContadorCierre({super.key, required this.periodo});

  final String periodo;

  @override
  State<ContadorCierre> createState() => _ContadorCierreState();
}

class _ContadorCierreState extends State<ContadorCierre> {
  late final Timer _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final falta = cierreDe(widget.periodo).difference(DateTime.now().toUtc());
    final urgente = falta.inHours < 24;
    final color = urgente ? const Color(0xFFE5484D) : paleta(context).textoSuave;
    final cual = switch (widget.periodo) {
      'week' => tr('La semana', 'The week'),
      'month' => tr('El mes', 'The month'),
      _ => tr('El año', 'The year'),
    };
    return Row(
      children: [
        Icon(urgente ? Icons.alarm : Icons.hourglass_bottom, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            tr('$cual cierra en ${cuantoFalta(falta)}', '$cual closes in ${cuantoFalta(falta)}'),
            style: numeros(context, tamano: 13, weight: urgente ? FontWeight.w800 : FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}
