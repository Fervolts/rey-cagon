import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'idioma.dart';
import 'main.dart' show conReintento, db, ultimosDeSala;
import 'privados.dart' show privadosSinLeer;

/// Los chats con mensajes sin leer que se cuentan aquí. Los privados van aparte (lib/privados.dart).
enum ChatCual { general, soporte }

/// Lo sin leer del chat en un solo lugar: lo leen el puntito de la pestaña BAÑO (lib/main.dart), el
/// botón de chats del muro y las pestañas del panel de chats (lib/chat_panel.dart).
/// General = la sala global y la de tu idioma; Soporte = tu hilo con los admins.
/// Lo visto es el id del último mensaje visto, guardado en SharedPreferences con las claves de siempre
/// ('bano_visto', 'soporte_visto'). Los ids son de una sola secuencia, así que se comparan directo.
/// Un chat cuenta como visto al abrirlo (`VistoMientras`), y mientras sigue abierto lo que llega también.
class ChatSinLeer extends ChangeNotifier {
  ChatSinLeer() {
    privadosSinLeer.addListener(notifyListeners);
  }

  static const _claves = {ChatCual.general: 'bano_visto', ChatCual.soporte: 'soporte_visto'};
  // Más que esto no se cuenta: la placa dice "99+".
  static const tope = 100;

  final _visto = {ChatCual.general: 0, ChatCual.soporte: 0};
  final _cuenta = {ChatCual.general: 0, ChatCual.soporte: 0};
  final _abierto = {ChatCual.general: 0, ChatCual.soporte: 0};
  int _ultimoGlobal = 0, _ultimoIdioma = 0, _ultimoSoporte = 0;
  final _subs = <VoidCallback>[];
  String? _yo;

  int _ultimo(ChatCual c) => c == ChatCual.general ? max(_ultimoGlobal, _ultimoIdioma) : _ultimoSoporte;

  /// Hay mensajes de otros en ese chat desde la última vez que se abrió.
  bool hay(ChatCual c) => _ultimo(c) > _visto[c]!;

  /// Cuántos sin leer, hasta [tope]. Con [hay] y 0 aún no se contó (o falló la red): se muestra un punto.
  int cuenta(ChatCual c) => hay(c) ? _cuenta[c]! : 0;

  /// El puntito de la pestaña BAÑO y del botón de chats del muro.
  bool get hayNuevo => hay(ChatCual.general) || hay(ChatCual.soporte) || privadosSinLeer.value;

  /// Empieza a escuchar (al entrar a la app con sesión). Lo deja [soltar].
  Future<void> iniciar(String yo) async {
    soltar();
    _yo = yo;
    _ultimoGlobal = _ultimoIdioma = _ultimoSoporte = 0;
    final prefs = await SharedPreferences.getInstance();
    if (_yo != yo) return;
    for (final c in ChatCual.values) {
      _visto[c] = max(_visto[c]!, prefs.getInt(_claves[c]!) ?? 0);
    }
    notifyListeners();
    _subs
      ..add(_escuchar('sala', 'global', (id) => _ultimoGlobal = id, ChatCual.general))
      ..add(_escuchar('sala', idioma.value, (id) => _ultimoIdioma = id, ChatCual.general))
      ..add(_escuchar('hilo', yo, (id) => _ultimoSoporte = id, ChatCual.soporte));
  }

  void soltar() {
    for (final s in _subs) {
      s();
    }
    _subs.clear();
    _yo = null;
  }

  // El último mensaje de esa sala. Los propios cuentan como vistos, y lo que llega con el chat abierto también.
  VoidCallback _escuchar(String columna, String valor, void Function(int) poner, ChatCual c) => ultimosDeSala(valor, 1, (filas) {
        if (filas.isEmpty || _yo == null) return;
        final m = filas.first;
        poner(m['id'] as int);
        if (m['user_id'] == _yo || _abierto[c]! > 0) {
          marcar(c);
        } else {
          _contar(c);
        }
        notifyListeners();
      }, columna: columna);

  // Cuántos de otros hay después de lo visto: solo ids, hasta [tope] (barato aunque haya miles).
  Future<void> _contar(ChatCual c) async {
    final yo = _yo, desde = _visto[c]!;
    if (yo == null || !hay(c)) return;
    try {
      final filas = await conReintento(() {
        final q = db.from('mensajes').select('id, user_id').gt('id', desde);
        return (c == ChatCual.general ? q.inFilter('sala', ['global', idioma.value]) : q.eq('hilo', yo)).order('id', ascending: false).limit(tope);
      });
      // Se marcó visto (o cambió la cuenta) mientras tanto: esta cuenta ya no vale.
      if (yo != _yo || desde != _visto[c]) return;
      _cuenta[c] = filas.where((m) => m['user_id'] != yo).length;
      notifyListeners();
    } catch (_) {
      // Sin red: queda el punto sin número; el próximo mensaje vuelve a contar.
    }
  }

  /// Todo lo de ese chat cuenta como visto.
  Future<void> marcar(ChatCual c) async {
    final visto = max(_visto[c]!, _ultimo(c));
    if (visto == _visto[c] && _cuenta[c] == 0) return;
    _visto[c] = visto;
    _cuenta[c] = 0;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_claves[c]!, visto);
  }

  void abrir(ChatCual c) {
    _abierto[c] = _abierto[c]! + 1;
    marcar(c);
  }

  void cerrar(ChatCual c) => _abierto[c] = max(0, _abierto[c]! - 1);
}

final chatSinLeer = ChatSinLeer();

/// Lo que dice la placa de una pestaña: el número, "99+" desde 100, null si no hay número.
String? etiquetaCuenta(int n) => n <= 0 ? null : (n > 99 ? '99+' : '$n');

/// La pestaña con la que abre el panel: la primera con algo sin leer, si no la primera (General).
int pestanaInicial(List<bool> sinLeer) => max(0, sinLeer.indexOf(true));

/// Mientras esto está en pantalla, el chat [cual] cuenta como visto (también lo que llegue).
class VistoMientras extends StatefulWidget {
  const VistoMientras({super.key, required this.cual, required this.child});

  final ChatCual cual;
  final Widget child;

  @override
  State<VistoMientras> createState() => _VistoMientrasState();
}

class _VistoMientrasState extends State<VistoMientras> {
  @override
  void initState() {
    super.initState();
    chatSinLeer.abrir(widget.cual);
  }

  @override
  void dispose() {
    chatSinLeer.cerrar(widget.cual);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
