// Pantalla "ÍCONO DE LA APP": los 5 íconos, los bloqueados con 🔒 y cómo ganarlos. La lógica vive en icono_app.dart.
import 'package:flutter/material.dart';

import 'emoji.dart';
import 'icono_app.dart';
import 'idioma.dart';
import 'tema.dart';

class PantallaIconoApp extends StatefulWidget {
  const PantallaIconoApp({super.key});

  @override
  State<PantallaIconoApp> createState() => _EstadoPantallaIconoApp();
}

class _EstadoPantallaIconoApp extends State<PantallaIconoApp> {
  Set<String> _ganados = {'normal'};
  String _puesto = 'normal';
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final puesto = await iconoPuesto();
    final datos = await cargadorDatosIcono();
    if (!mounted) return;
    setState(() {
      _puesto = puesto;
      _ganados = iconosGanados(datos);
      _cargando = false;
    });
  }

  Future<void> _elegir(IconoApp i) async {
    if (i.id == _puesto) return;
    if (!iconoDisponible(i.id, _ganados, _puesto)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔒 ${comoGanarIcono(i)}')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Cambiar el ícono', 'Change the icon')),
        content: Text(tr(
            'El teléfono puede tardar unos segundos en cambiarlo, y según tu launcher la app puede cerrarse. Si pasa, ábrela otra vez.',
            'The phone may take a few seconds to change it, and depending on your launcher the app may close. If it does, open it again.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Cambiar', 'Change'))),
        ],
      ),
    );
    if (ok != true) return;
    final hecho = await ponerIcono(i);
    if (!mounted) return;
    if (hecho) {
      setState(() => _puesto = i.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('No se pudo cambiar el ícono.', "Couldn't change the icon."))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('ÍCONO DE LA APP', 'APP ICON'))),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: conBordeAbajo(context, const EdgeInsets.symmetric(vertical: 8)),
              children: [
                for (final i in iconosApp)
                  ListTile(
                    leading: Emoji(iconoDisponible(i.id, _ganados, _puesto) ? i.emoji : '🔒', tamano: 32),
                    title: Text(nombreIcono(i)),
                    subtitle: Text(iconoDisponible(i.id, _ganados, _puesto) ? (i.id == _puesto ? tr('Puesto ahora', 'In use') : comoGanarIcono(i)) : comoGanarIcono(i)),
                    trailing: i.id == _puesto ? const Icon(Icons.check) : null,
                    onTap: () => _elegir(i),
                  ),
              ],
            ),
    );
  }
}
