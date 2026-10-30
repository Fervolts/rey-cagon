import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'emoji.dart';
import 'genero.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accesorios.dart';
import 'animaciones.dart';
import 'avisos.dart';
import 'cagadon.dart';
import 'calendario.dart';
import 'chat.dart' show abrirReporteDeError;
import 'comunidad.dart';
import 'idioma.dart';
import 'logros.dart';
import 'placer.dart';
import 'main.dart' show conReintento, db, escucharCagadas, esDeRed, textoError;
import 'push.dart';
import 'recordatorio.dart';
import 'tema.dart';
import 'tips.dart';
import 'tipos.dart';
import 'vivo.dart';
import 'vitrina.dart';
import 'widget.dart';

const avataresGratis = ['💩', '👑', '🧻', '🚽', '🐻', '🦍', '🐷', '🐸', '🦄', '🤡', '🙂', '👻', '🔥', '🌶️', '🍑', '🦖'];

String _fecha(DateTime d) => '${d.day}/${d.month}/${d.year}';

class PantallaPerfil extends StatefulWidget {
  const PantallaPerfil({super.key, required this.usuarioId});

  final String usuarioId;

  @override
  State<PantallaPerfil> createState() => _PantallaPerfilState();
}

class _PantallaPerfilState extends State<PantallaPerfil> {
  Map<String, dynamic>? _p;
  bool _ocupado = false;
  bool _bloqueado = false;
  // Género del perfil propio: no sale en el RPC perfil porque nadie más lo ve.
  String? _genero;
  DateTime? _generoCambiado;
  // Lo que alimenta la vitrina (y el mapa del mes en el propio).
  List<({DateTime cuando, int? tipo, int? peso})>? _cagadas;
  int _victorias = 0;
  // Logros de eventos guardados, si el dueño y quien mira tienen el lado secreto, y los
  // secretos recién ganados que la vitrina revela con animación (solo en el propio).
  Set<String> _claves = {};
  bool _ladoSecreto = false, _verLadoSecreto = false;
  Set<String> _nuevos = {};
  late final VoidCallback _soltar;

  bool get _esMio => widget.usuarioId == db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _cargar();
    _soltar = escucharCagadas('perfil', _cargar);
  }

  @override
  void dispose() {
    _soltar();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final (rows, bloqueo) = await conReintento(() => (
            db.rpc('perfil', params: {'uid': widget.usuarioId}),
            db.from('bloqueos').select('bloqueado').eq('bloqueado', widget.usuarioId).maybeSingle(),
          ).wait);
      final g = _esMio
          ? await db.from('profiles').select('genero, genero_cambiado, placer_desbloqueado').eq('id', widget.usuarioId).maybeSingle()
          : null;
      final (cagadas, ganados) = _esMio ? await (cagadasPropias(widget.usuarioId), victorias(widget.usuarioId)).wait : await _vitrinaAjena();
      // logrosDe no falla: si la tabla no existe todavía, vuelve con lo del teléfono.
      final claves = cagadas == null ? <String>{} : await logrosDe(widget.usuarioId);
      final (lado, verLado) = await _ladosSecretos(g);
      final nuevos = cagadas != null && _esMio ? await _secretosNuevos(cagadas, ganados, claves, lado) : <String>{};
      if (mounted) {
        setState(() {
          _cagadas = cagadas;
          _victorias = ganados;
          _claves = claves;
          _ladoSecreto = lado;
          _verLadoSecreto = verLado;
          _nuevos = nuevos;
          _p = (rows as List).firstOrNull;
          _bloqueado = bloqueo != null;
          _genero = g?['genero'];
          _generoCambiado = DateTime.tryParse(g?['genero_cambiado'] ?? '')?.toLocal();
        });
      }
    } catch (e) {
      if (_p == null || !esDeRed(e)) _mensaje(textoError(e));
    }
  }

  /// La vitrina de otro: si falla, el perfil sale igual, sin vitrina.
  Future<(List<({DateTime cuando, int? tipo, int? peso})>?, int)> _vitrinaAjena() async {
    try {
      return await (cagadasPropias(widget.usuarioId), victorias(widget.usuarioId)).wait;
    } catch (_) {
      return (null, 0);
    }
  }

  /// Si el dueño tiene el lado secreto y si quien mira también. Si falla, ninguno: así no se
  /// enseña de más a quien no lo tiene.
  Future<(bool, bool)> _ladosSecretos(Map<String, dynamic>? g) async {
    if (_esMio) {
      final lado = g?['placer_desbloqueado'] == true;
      return (lado, lado);
    }
    try {
      final yo = db.auth.currentUser!.id;
      final filas = await db.from('profiles').select('id, placer_desbloqueado').inFilter('id', [yo, widget.usuarioId]);
      bool tiene(String id) => filas.any((f) => f['id'] == id && f['placer_desbloqueado'] == true);
      return (tiene(widget.usuarioId), tiene(yo));
    } catch (_) {
      return (false, false);
    }
  }

  /// Los secretos propios: avisa con el toast los que no avisaron y devuelve los que faltan por
  /// revelar en la vitrina.
  Future<Set<String>> _secretosNuevos(
      List<({DateTime cuando, int? tipo, int? peso})> cagadas, int ganados, Set<String> claves, bool lado) async {
    final secretos = [
      for (final t in trofeos(cagadas: cagadas, total: 0, victorias: ganados, favorito: null, claves: claves, ladoSecreto: lado))
        if (t.grupo == Grupo.secreto) t.clave,
    ];
    _avisarCuandoSeVea(await porAvisar(secretos));
    return porRevelar(secretos);
  }

  /// YO se arma al abrir la app aunque esté en otra pestaña: el toast espera a que se vea.
  void _avisarCuandoSeVea(List<String> claves) {
    if (claves.isEmpty || !mounted) return;
    final visible = TickerMode.getValuesNotifier(context);
    if (visible.value.enabled) return avisarLogrosSecretos(context, claves);
    void ver() {
      if (!visible.value.enabled) return;
      visible.removeListener(ver);
      if (mounted) avisarLogrosSecretos(context, claves);
    }

    visible.addListener(ver);
  }

  void _mensaje(String texto) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Bloquear: deja de verlo en los rankings y se cortan los follows en los dos sentidos.
  Future<void> _alternarBloqueo() async {
    try {
      if (_bloqueado) {
        await db.from('bloqueos').delete().eq('bloqueador', db.auth.currentUser!.id).eq('bloqueado', widget.usuarioId);
        _mensaje(tr('Desbloqueado', 'Unblocked'));
      } else {
        await db.from('bloqueos').insert({'bloqueado': widget.usuarioId});
        _mensaje(tr('Bloqueado. Ya no lo verás en tus rankings.', "Blocked. You won't see them on your leaderboards anymore."));
      }
      await _cargar();
    } catch (e) {
      _mensaje(textoError(e));
    }
  }

  // El primero es lo que se guarda en reportes.motivo; el segundo, lo que se ve.
  List<(String, String)> get _motivos => [
        ('Username o bio ofensivos', tr('Username o bio ofensivos', 'Offensive username or bio')),
        ('Acoso', tr('Acoso', 'Harassment')),
        ('Spam o trampas', tr('Spam o trampas', 'Spam or cheating')),
        ('Otro', tr('Otro', 'Other')),
      ];

  Future<void> _reportar() async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('¿Por qué lo reportas?', 'Why are you reporting them?')),
        children: [
          for (final (valor, etiqueta) in _motivos)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, valor), child: Text(etiqueta)),
        ],
      ),
    );
    if (motivo == null) return;
    try {
      await db.from('reportes').insert({'reportado': widget.usuarioId, 'motivo': motivo});
      _mensaje(tr('Gracias. Lo vamos a revisar.', "Thanks. We'll look into it."));
    } catch (e) {
      _mensaje(textoError(e));
    }
  }

  Future<void> _seguir() async {
    setState(() => _ocupado = true);
    try {
      if (_p!['lo_sigo'] == true) {
        await db.from('follows').delete().eq('follower', db.auth.currentUser!.id).eq('followed', widget.usuarioId);
      } else {
        await db.from('follows').insert({'followed': widget.usuarioId});
      }
      await _cargar();
    } catch (e) {
      _mensaje(textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _elegirIdioma() async {
    final valor = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, nombre) in [('auto', tr('El del teléfono', "Phone's language")), ('es', 'Español'), ('en', 'English')])
            ListTile(
              title: Text(nombre),
              trailing: idiomaElegido == v ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, v),
            ),
        ]),
      ),
    );
    if (valor != null && valor != idiomaElegido) await elegirIdioma(valor);
  }

  String _nombreTema(ThemeMode m) => switch (m) {
        ThemeMode.light => tr('Claro', 'Light'),
        ThemeMode.dark => tr('Oscuro', 'Dark'),
        ThemeMode.system => tr('El del teléfono', "Phone's setting"),
      };

  Future<void> _elegirTema() async {
    final modo = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
            ListTile(
              title: Text(_nombreTema(m)),
              trailing: temaElegido.value == m ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, m),
            ),
        ]),
      ),
    );
    if (modo != null) await elegirTema(modo);
    if (mounted) setState(() {});
  }

  String _nombreMovimientoElegido() => switch (movimientoElegido.value) {
        'completo' => nombreMovimiento(Movimiento.completo),
        'simple' => nombreMovimiento(Movimiento.simple),
        'nada' => nombreMovimiento(Movimiento.nada),
        _ => tr('Automáticas · ${nombreMovimiento(movimientoDelTelefono).toLowerCase()} en este teléfono',
            'Automatic · ${nombreMovimiento(movimientoDelTelefono).toLowerCase()} on this phone'),
      };

  Future<void> _elegirMovimiento() async {
    final valor = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, nombre, detalle) in [
            ('auto', tr('Automáticas', 'Automatic'), tr('Según lo que aguante el teléfono', 'Depending on what the phone can handle')),
            ('completo', nombreMovimiento(Movimiento.completo), tr('El mojón vuela al inodoro', 'The poop flies into the toilet')),
            ('simple', nombreMovimiento(Movimiento.simple), tr('Un brinco, para teléfonos lentos', 'A little hop, for slow phones')),
            ('nada', nombreMovimiento(Movimiento.nada), tr('Nada se mueve', 'Nothing moves')),
          ])
            ListTile(
              title: Text(nombre),
              subtitle: Text(detalle),
              trailing: movimientoElegido.value == v ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, v),
            ),
        ]),
      ),
    );
    if (valor != null) {
      await elegirMovimiento(valor);
      if (mounted) setState(() {});
    }
  }

  /// Fecha desde la que puede volver a cambiar el género, o null si puede ya.
  DateTime? get _proximoCambioGenero {
    final c = _generoCambiado;
    if (_genero == null || c == null) return null;
    final proximo = DateTime(c.year + 1, c.month, c.day, c.hour, c.minute);
    return proximo.isAfter(DateTime.now()) ? proximo : null;
  }

  Future<void> _elegirGenero() async {
    final bloqueado = _proximoCambioGenero;
    final valor = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 0, 16, 16)),
        children: [
          Text(tr('¿REY O REINA?', 'KING OR QUEEN?'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            bloqueado != null
                ? tr('Ya lo cambiaste este año. Próximo cambio: ${_fecha(bloqueado)}', 'You already changed it this year. Next change: ${_fecha(bloqueado)}')
                : _genero == null
                    ? tr('Elige uno. Después solo lo puedes cambiar una vez al año.', 'Pick one. After that you can only change it once a year.')
                    : tr('Solo lo puedes cambiar una vez al año.', 'You can only change it once a year.'),
            style: TextStyle(color: paleta(context).textoSuave),
          ),
          const SizedBox(height: 12),
          ElegirGenero(valor: _genero, onTap: bloqueado != null ? null : (g) => Navigator.pop(context, g)),
        ],
      ),
    );
    if (valor == null || valor == _genero || !mounted) return;
    if (_genero != null) {
      final hasta = _fecha(DateTime.now().add(const Duration(days: 365)));
      final si = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('¿Cambiar a ${generos[valor]!.$2}?', 'Change to ${generos[valor]!.$2}?')),
          content: Text(tr('No lo vas a poder cambiar otra vez hasta el $hasta.', "You won't be able to change it again until $hasta.")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCELAR', 'CANCEL'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('CAMBIAR', 'CHANGE'))),
          ],
        ),
      );
      if (si != true) return;
    }
    try {
      await db.from('profiles').update({'genero': valor}).eq('id', widget.usuarioId);
      await guardarGenero(valor);
      await _cargar();
    } on PostgrestException catch (e) {
      _mensaje(trServidor(e.message));
    } catch (e) {
      _mensaje(textoError(e));
    }
  }

  Future<void> _editar() async {
    final cambio = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Sin arrastre de la hoja: arrastrar el avatar mueve lentes y sombrero.
      enableDrag: false,
      builder: (_) => _EditarPerfil(perfil: _p!),
    );
    if (cambio == true) await _cargar();
  }

  Future<void> _salir() async {
    cancelarRecordatorio().catchError((_) {});
    limpiarWidget().catchError((_) {});
    await olvidarTelefono().catchError((_) {});
    await db.auth.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Borra la cuenta y todo lo suyo (cagadas, follows, teléfonos) después de confirmar.
  Future<void> _borrarCuenta() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Borrar tu cuenta?', 'Delete your account?')),
        content: Text(tr('Se borran tu perfil, todas tus cagadas y tus seguidores. No se puede deshacer.', 'Your profile, all your poops and your followers get deleted. This cannot be undone.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('CANCELAR', 'CANCEL'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('BORRAR', 'DELETE')),
          ),
        ],
      ),
    );
    if (seguro != true) return;
    try {
      cancelarRecordatorio().catchError((_) {});
      limpiarWidget().catchError((_) {});
      await db.rpc('borrar_mi_cuenta');
      await db.auth.signOut().catchError((_) {});
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _mensaje(tr('No se pudo borrar la cuenta: $e', "Couldn't delete the account: $e"));
    }
  }

  /// Abre ajustes: todo lo que antes estaba debajo del perfil propio.
  void _abrirAjustes() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StatefulBuilder(builder: (context, setLocal) {
            // Después de cambiar algo, el subtítulo de la fila se actualiza.
            VoidCallback luego(Future<void> Function() f) => () async {
                  await f();
                  if (context.mounted) setLocal(() {});
                };
            return Scaffold(
              appBar: AppBar(title: Text(tr('AJUSTES', 'SETTINGS'))),
              body: ListView(
                padding: conBordeAbajo(context, const EdgeInsets.symmetric(vertical: 8)),
                children: [
                const FilaComunidad(),
                ListTile(
                  leading: Emoji(generos[_genero]?.$1 ?? '🫅', tamano: 32),
                  title: Text(tr('Género', 'Gender')),
                  subtitle: Text(_genero == null
                      ? tr('Sin elegir', 'Not chosen')
                      : _proximoCambioGenero == null
                          ? '${generos[_genero]!.$2} · ${generos[_genero]!.$3}'
                          : tr('${generos[_genero]!.$2} · se cambia el ${_fecha(_proximoCambioGenero!)}',
                              '${generos[_genero]!.$2} · can change on ${_fecha(_proximoCambioGenero!)}')),
                  trailing: Icon(_proximoCambioGenero == null ? Icons.chevron_right : Icons.lock_outline),
                  onTap: luego(_elegirGenero),
                ),
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: const Text('Idioma / Language'),
                  subtitle: Text(switch (idiomaElegido) {
                    'es' => 'Español',
                    'en' => 'English',
                    _ => tr('El del teléfono', "Phone's language"),
                  }),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: luego(_elegirIdioma),
                ),
                ListTile(
                  leading: const Icon(Icons.contrast),
                  title: Text(tr('Tema', 'Theme')),
                  subtitle: Text(_nombreTema(temaElegido.value)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: luego(_elegirTema),
                ),
                ListTile(
                  leading: const Icon(Icons.animation),
                  title: Text(tr('Animaciones', 'Animations')),
                  subtitle: Text(_nombreMovimientoElegido()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: luego(_elegirMovimiento),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: Text(tr('Hecho por ahimismito Studios C.A', 'Made by ahimismito Studios C.A')),
                  subtitle: const Text('ahimismito.com'),
                  onTap: () => launchUrl(Uri.parse('https://ahimismito.com'), mode: LaunchMode.externalApplication),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(tr('Créditos y licencias', 'Credits and licenses')),
                  onTap: () async {
                    final info = await PackageInfo.fromPlatform();
                    if (!context.mounted) return;
                    showLicensePage(
                      context: context,
                      applicationName: tr('Rey Cagón', 'King of the Throne'),
                      applicationVersion: info.version,
                      applicationLegalese: '© 2026 ahimismito Studios C.A\nahimismito.com',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(tr('Cerrar sesión', 'Log out')),
                  onTap: _salir,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Color(0xFFB3261E)),
                  title: Text(tr('Borrar mi cuenta', 'Delete my account'), style: const TextStyle(color: Color(0xFFB3261E))),
                  onTap: _borrarCuenta,
                ),
                ],
              ),
            );
          }),
        ),
      );

  /// La pestaña YO: quién es, cuánto lleva, sus trofeos y el mes, con Tips y la Lectura a mano.
  Widget _yo() {
    final p = _p;
    final colores = paleta(context);
    final texto = Theme.of(context).textTheme;
    final total = p == null ? 0 : (p['cagadas'] as num?)?.toInt() ?? (p['total'] as num).toInt();
    final d = siguienteDesbloqueo(total);
    Widget caja(Object? valor, String nombre) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: colores.tarjeta, border: Border.all(color: colores.borde)),
            child: Column(
              children: [
                Contador(valor is num ? valor.toInt() : 0, estilo: numeros(context, tamano: 24, weight: FontWeight.w900)),
                Rotulo(nombre),
              ],
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('YO', 'ME')),
        actions: [
          if (p != null) IconButton(icon: const Icon(Icons.edit), tooltip: tr('Editar', 'Edit'), onPressed: _editar),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: tr('Ajustes', 'Settings'), onPressed: _abrirAjustes),
        ],
      ),
      body: p == null
          ? const Cargando()
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
                children: [
                  // Con 10 o más y sin el secreto, a veces la tarjeta trae una esquina doblada.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                  Row(
                    children: [
                      Padding(
                        // Aire para el sombrero y la mascota, que se salen del círculo.
                        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                        // Easter egg: 10 toques seguidos y protesta (logro secreto).
                        child: CoronaTocable(alGanar: _cargar, child: Balanceo(child: Avatar(p, tamano: 96))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['username'], maxLines: 2, overflow: TextOverflow.ellipsis, style: texto.headlineSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${tituloPorTotal(total)} · ${tr('desde', 'since')} ${_fecha(DateTime.parse(p['desde']).toLocal())}',
                              style: TextStyle(color: colores.textoSuave, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr('${p['seguidores']} seguidores · ${p['siguiendo']} siguiendo', '${p['seguidores']} followers · ${p['siguiendo']} following'),
                              style: numeros(context, tamano: 13, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                      Positioned(right: -16, bottom: 0, child: EsquinaSecreta(total: total)),
                    ],
                  ),
                  if ((p['bio'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(p['bio'])),
                  Row(
                    children: [
                      caja(p['hoy'], tr('hoy', 'today')),
                      const SizedBox(width: 6),
                      caja(p['semana'], tr('semana', 'week')),
                      const SizedBox(width: 6),
                      caja(p['mes'], tr('mes', 'month')),
                      const SizedBox(width: 6),
                      caja(total, tr('total', 'total')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_cagadas == null)
                    const Padding(padding: EdgeInsets.all(24), child: Cargando())
                  else ...[
                    Builder(builder: (context) {
                      final lista = trofeos(
                        cagadas: _cagadas!,
                        total: total,
                        victorias: _victorias,
                        favorito: p['tipo_favorito'],
                        seguidores: (p['seguidores'] as num?)?.toInt() ?? 0,
                        siguiendo: (p['siguiendo'] as num?)?.toInt() ?? 0,
                        claves: _claves,
                        ladoSecreto: _ladoSecreto,
                      );
                      return Vitrina(trofeos: lista, nuevos: _nuevos, porEncontrar: secretosPorEncontrar(lista));
                    }),
                    const SizedBox(height: 20),
                    MapaDelMes(
                      cagadas: _cagadas!,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PantallaCalendario(usuarioId: widget.usuarioId, nombre: tr('mí', 'me'))),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Emoji('💡', tamano: 32),
                    title: Text(tr('Tips para cagar mejor', 'Tips to poop better')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaTips())),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Emoji('🧻', tamano: 32),
                    title: Text(tr('Lectura del Baño', 'Bathroom Reading')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaAvisos())),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: d == null ? const Emoji('🏆', tamano: 32) : Opacity(opacity: .4, child: Emoji(d.emoji, tamano: 32)),
                    title: Text(d == null ? tr('Lo desbloqueaste todo', 'You unlocked everything') : tr('Próximo: ${d.nombre}', 'Next: ${d.nombre}')),
                    subtitle: d == null ? null : Text(d.minimo - total == 1 ? tr('Te falta 1 cagada', 'You need 1 more poop') : tr('Te faltan ${d.minimo - total} cagadas', 'You need ${d.minimo - total} more poops')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _editar,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(tr('Reportar un error', 'Report a bug')),
                    subtitle: Text(tr('Le llega directo al equipo', 'Goes straight to the team')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => abrirReporteDeError(context),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_esMio) return _yo();
    final p = _p;
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('PERFIL', 'PROFILE')),
        actions: [
          if (p != null)
            PopupMenuButton<String>(
              tooltip: tr('Más opciones', 'More options'),
              onSelected: (o) => o == 'reportar' ? _reportar() : _alternarBloqueo(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'reportar', child: Text(tr('Reportar', 'Report'))),
                PopupMenuItem(value: 'bloquear', child: Text(_bloqueado ? tr('Desbloquear', 'Unblock') : tr('Bloquear', 'Block'))),
              ],
            ),
        ],
      ),
      body: p == null
          ? const Cargando()
          : ListView(
              padding: conBordeAbajo(context, const EdgeInsets.all(16)),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 36, bottom: 8),
                  child: Center(child: Balanceo(child: Avatar(p, tamano: 96))),
                ),
                Text(p['username'],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: texto.headlineSmall),
                if ((p['bio'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(p['bio'], textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 4),
                Text(tr('Cagando desde el ${_fecha(DateTime.parse(p['desde']).toLocal())}', 'Pooping since ${_fecha(DateTime.parse(p['desde']).toLocal())}'),
                    textAlign: TextAlign.center, style: texto.bodySmall),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Numero(valor: p['seguidores'], texto: tr('seguidores', 'followers')),
                    const SizedBox(width: 32),
                    _Numero(valor: p['siguiendo'], texto: tr('siguiendo', 'following')),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_bloqueado)
                  Center(
                    child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                      p['lo_sigo'] == true
                          ? OutlinedButton(onPressed: _ocupado ? null : _seguir, child: Text(tr('DEJAR DE SEGUIR', 'UNFOLLOW')))
                          : FilledButton(onPressed: _ocupado ? null : _seguir, child: Text(tr('SEGUIR', 'FOLLOW'))),
                      // Solo se reta a gente que sigues.
                      if (p['lo_sigo'] == true)
                        FilledButton.icon(
                          onPressed: () => retar(context, widget.usuarioId, p['username']),
                          icon: const Text('⚔️'),
                          label: Text(tr('RETAR', 'CHALLENGE')),
                        ),
                    ]),
                  ),
                FutureBuilder<int>(
                  future: victorias(widget.usuarioId),
                  builder: (context, v) => (v.data ?? 0) == 0
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(tr('🏆 ${v.data} Cagadón${v.data == 1 ? '' : 'es'} ganado${v.data == 1 ? '' : 's'}', '🏆 ${v.data} Poop-Off${v.data == 1 ? '' : 's'} won'),
                              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      runSpacing: 12,
                      children: [
                        _Numero(valor: p['hoy'], texto: tr('hoy', 'today')),
                        _Numero(valor: p['semana'], texto: tr('semana', 'week')),
                        _Numero(valor: p['mes'], texto: tr('mes', 'month')),
                        _Numero(valor: p['anio'], texto: tr('año', 'year')),
                        _Numero(valor: p['total'], texto: tr('total', 'total')),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: Emoji(tipoEmoji(p['tipo_favorito']), tamano: 36),
                  title: Text(tr('Especialidad de la casa', 'House specialty')),
                  subtitle: Text(tipos[p['tipo_favorito']]?.$2 ?? tr('Todavía no se sabe', 'Nobody knows yet')),
                ),
                // Su vitrina, sin los "secretos por encontrar" (eso es cosa suya). Los del lado
                // secreto solo salen si quien mira también lo tiene.
                if (_cagadas != null && !_bloqueado) ...[
                  const SizedBox(height: 8),
                  Vitrina(
                    trofeos: trofeos(
                      cagadas: _cagadas!,
                      total: (p['total'] as num?)?.toInt() ?? 0,
                      victorias: _victorias,
                      favorito: p['tipo_favorito'],
                      seguidores: (p['seguidores'] as num?)?.toInt() ?? 0,
                      siguiendo: (p['siguiendo'] as num?)?.toInt() ?? 0,
                      claves: _claves,
                      ladoSecreto: _ladoSecreto,
                      verLadoSecreto: _verLadoSecreto,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: Text(tr('Ver calendario', 'View calendar')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PantallaCalendario(usuarioId: widget.usuarioId, nombre: p['username']),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.valor, required this.texto});

  final Object? valor;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Text('$valor', style: Theme.of(context).textTheme.titleLarge),
            Rotulo(texto),
          ],
        ),
      );
}

class _EditarPerfil extends StatefulWidget {
  const _EditarPerfil({required this.perfil});

  final Map<String, dynamic> perfil;

  @override
  State<_EditarPerfil> createState() => _EditarPerfilState();
}

class _EditarPerfilState extends State<_EditarPerfil> {
  late final _usuario = TextEditingController(text: widget.perfil['username']);
  late final _bio = TextEditingController(text: widget.perfil['bio'] ?? '');
  late final Map<String, dynamic> _puesto = {
    for (final k in ['avatar', 'sombrero', 'lentes', 'mascota', ..._ajustes])
      k: widget.perfil[k],
  };
  // Qué se está moviendo con el dedo en la vista previa: 'lentes', 'sombrero' o null.
  String? _moviendo;
  // El scroll se congela solo mientras el dedo está sobre el avatar, no todo el rato que dura
  // MOVER: si no, en pantallas chicas nadie llega a GUARDAR.
  bool _dedoEnAvatar = false;
  static const _ajustes = ['lentes_x', 'lentes_y', 'sombrero_x', 'sombrero_y', 'lentes_escala', 'sombrero_escala'];
  static const _vista = 120.0;
  bool _ocupado = false;
  bool _secreto = secretoAbierto.value;

  @override
  void initState() {
    super.initState();
    db
        .from('profiles')
        .select('placer_desbloqueado')
        .eq('id', db.auth.currentUser!.id)
        .maybeSingle()
        .then((r) => mounted ? setState(() => _secreto = _secreto || r?['placer_desbloqueado'] == true) : null)
        .catchError((_) => null);
  }

  int get _total => (widget.perfil['total'] as num?)?.toInt() ?? 0;

  Future<void> _guardar() async {
    setState(() => _ocupado = true);
    try {
      await db.from('profiles').update({
        'username': _usuario.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        ..._puesto,
      }).eq('id', db.auth.currentUser!.id);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      final texto = e.code == '23505'
          ? tr('Ese username ya existe', 'That username already exists')
          : e.code == '23514'
              ? tr('Username de 2 a 24 letras, bio de máximo 140', 'Username 2 to 24 characters, bio up to 140')
              : trServidor(e.message);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _arrastrar(PointerMoveEvent d) {
    final r = _moviendo!;
    final actual = posicion(_puesto, r);
    setState(() {
      _puesto['${r}_x'] = (actual.x + d.delta.dx / _vista).clamp(-.5, 1.5);
      _puesto['${r}_y'] = (actual.y + d.delta.dy / _vista).clamp(-.5, 1.5);
    });
  }

  /// Fila de opciones de una ranura. Lo bloqueado se ve apagado con las cagadas que pide.
  Widget _ranura(String titulo, String ranura) {
    final opciones = [
      if (ranura == 'avatar')
        for (final a in avataresGratis) (emoji: a, minimo: 0)
      else
        (emoji: null, minimo: 0),
      for (final d in desbloqueos.where((d) => d.ranura == ranura)) (emoji: d.emoji, minimo: d.minimo),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Rotulo(titulo),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final o in opciones)
                ChoiceChip(
                  label: o.emoji == null
                      ? const SizedBox.square(dimension: 28, child: Icon(Icons.block, size: 22))
                      : o.minimo > _total
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              Opacity(opacity: .3, child: Emoji(o.emoji!, tamano: 28)),
                              const SizedBox(width: 4),
                              Text('${o.minimo}', style: numeros(context, tamano: 12, color: paleta(context).textoSuave)),
                            ])
                          : Emoji(o.emoji!, tamano: 28),
                  selected: _puesto[ranura] == o.emoji,
                  showCheckmark: false,
                  onSelected: o.minimo > _total
                      ? (_) => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('Se desbloquea a las ${o.minimo} cagadas. Llevas $_total.', 'Unlocks at ${o.minimo} poops. You have $_total.'))))
                      : (_) => setState(() {
                          _puesto[ranura] = o.emoji;
                          // Avatar nuevo: vuelven a la posición calibrada para él.
                          if (ranura == 'avatar') {
                            for (final k in _ajustes) {
                              _puesto[k] = null;
                            }
                          }
                        }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paleta(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
       Flexible(child: SingleChildScrollView(
        physics: _moviendo != null && _dedoEnAvatar ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('EDITAR PERFIL', 'EDIT PROFILE'), style: Theme.of(context).textTheme.titleLarge),
            Padding(
              padding: const EdgeInsets.only(top: 48, bottom: 16),
              child: Center(
                // Listener y no GestureDetector: no compite con el scroll de la hoja, que se
                // congela mientras se mueve algo.
                child: Listener(
                  onPointerDown: (_) => setState(() => _dedoEnAvatar = true),
                  onPointerUp: (_) => setState(() => _dedoEnAvatar = false),
                  onPointerCancel: (_) => setState(() => _dedoEnAvatar = false),
                  onPointerMove: _moviendo == null ? null : _arrastrar,
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.all(_vista * .35),
                    child: Avatar({..._puesto, 'cagadas': _total}, tamano: _vista),
                  ),
                ),
              ),
            ),
            if (_puesto['lentes'] != null || _puesto['sombrero'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in ['lentes', 'sombrero'])
                      if (_puesto[r] != null)
                        ChoiceChip(
                          label: Text(enIngles ? 'MOVE ${r == 'lentes' ? 'GLASSES' : 'HAT'}' : 'MOVER ${r.toUpperCase()}'),
                          selected: _moviendo == r,
                          onSelected: (si) => setState(() => _moviendo = si ? r : null),
                        ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final k in _ajustes) {
                          _puesto[k] = null;
                        }
                      }),
                      child: Text(tr('RESTABLECER', 'RESET')),
                    ),
                  ],
                ),
              ),
            if (_moviendo != null) ...[
              Text(tr('Arrastra sobre el avatar para mover ${_moviendo == 'lentes' ? 'los lentes' : 'el sombrero'}.', 'Drag on the avatar to move the ${_moviendo == 'lentes' ? 'glasses' : 'hat'}.'),
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              Row(
                children: [
                  Rotulo(tr('Tamaño', 'Size')),
                  Expanded(
                    child: Slider(
                      min: .4,
                      max: 2.5,
                      value: escala(_puesto, _moviendo!).clamp(.4, 2.5),
                      onChanged: (v) => setState(() => _puesto['${_moviendo}_escala'] = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _ranura(tr('Avatar', 'Avatar'), 'avatar'),
            _ranura(tr('Sombrero', 'Hat'), 'sombrero'),
            _ranura(tr('Lentes', 'Glasses'), 'lentes'),
            _ranura(tr('Mascota', 'Pet'), 'mascota'),
            // Solo para quien ya encontró el secreto (en Tips o en la esquina de YO).
            if (_secreto)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Rotulo(tr('Secretos · coming soon', 'Secrets · coming soon')),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final v in [1, 7])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Opacity(opacity: .3, child: iconoPlacer(v, tamano: 44)),
                        ),
                      Expanded(
                        child: Text(tr('Accesorios que salen de tus cagadas placenteras y destructivas.', 'Accessories that come from your pleasurable and destructive poops.'),
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                enIngles
                    ? 'Your pet goes for a walk at $mascotaSeMueve poops. Your avatar turns '
                        '${efectosAvatar.map((e) => '${e.nombre.replaceFirst(' avatar', '').toLowerCase()} at ${e.minimo}').join(', ')}.'
                    : 'Tu mascota sale a pasear a las $mascotaSeMueve cagadas. Tu avatar se vuelve '
                        '${efectosAvatar.map((e) => '${e.nombre.replaceFirst('Avatar ', '')} a las ${e.minimo}').join(', ')}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextField(
              controller: _usuario,
              maxLength: 24,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _bio,
              maxLength: 140,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Bio'),
            ),
          ],
        ),
       )),
        // GUARDAR fijo abajo, siempre a la vista y encima de la barra del sistema.
        Container(
          padding: conBordeAbajo(context, const EdgeInsets.fromLTRB(16, 10, 16, 10)),
          decoration: BoxDecoration(color: Theme.of(context).bottomSheetTheme.backgroundColor ?? p.fondo, border: Border(top: BorderSide(color: p.borde))),
          child: FilledButton(onPressed: _ocupado ? null : _guardar, child: Text(tr('GUARDAR', 'SAVE'))),
        ),
      ]),
    );
  }
}

/// Buscar gente por username para seguirla.
class PantallaBuscar extends StatefulWidget {
  const PantallaBuscar({super.key});

  @override
  State<PantallaBuscar> createState() => _PantallaBuscarState();
}

class _PantallaBuscarState extends State<PantallaBuscar> {
  List<Map<String, dynamic>> _gente = [];
  Set<String> _sigo = {};
  String _q = '';

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    _q = q;
    final yo = db.auth.currentUser!.id;
    try {
      var consulta = db.from('profiles').select('id, username, avatar, sombrero, lentes, mascota, cagadas, lentes_x, lentes_y, sombrero_x, sombrero_y, lentes_escala, sombrero_escala').neq('id', yo);
      if (q.trim().isNotEmpty) {
        // % y _ son comodines en ilike: se escapan para buscar el texto tal cual.
        final limpio = q.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
        consulta = consulta.ilike('username', '%$limpio%');
      }
      final (gente, sigo, bloqueados) = await (
        consulta.order('username').limit(50),
        db.from('follows').select('followed').eq('follower', yo),
        db.from('bloqueos').select('bloqueado'),
      ).wait;
      if (!mounted || q != _q) return;
      final fuera = {for (final b in bloqueados) b['bloqueado'] as String};
      setState(() {
        _gente = List<Map<String, dynamic>>.from(gente).where((g) => !fuera.contains(g['id'])).toList();
        _sigo = {for (final f in sigo) f['followed'] as String};
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(textoError(e))));
    }
  }

  Future<void> _toggle(String id) async {
    final yo = db.auth.currentUser!.id;
    try {
      if (_sigo.contains(id)) {
        await db.from('follows').delete().eq('follower', yo).eq('followed', id);
      } else {
        await db.from('follows').insert({'followed': id});
      }
      await _buscar(_q);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(textoError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('BUSCAR AMIGOS', 'FIND FRIENDS'))),
      body: ListView(
        padding: conBordeAbajo(context, const EdgeInsets.all(16)),
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Username'),
            onChanged: _buscar,
          ),
          const SizedBox(height: 8),
          if (_gente.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Nadie por aquí 🫥', 'Nobody here 🫥'), textAlign: TextAlign.center)),
          for (final g in _gente)
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PantallaPerfil(usuarioId: g['id'])),
              ).then((_) => _buscar(_q)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Avatar(g, tamano: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        g['username'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Ancho fijo: el botón no se encoge ni empuja el nombre.
                    SizedBox(
                      width: 116,
                      height: 40,
                      child: _sigo.contains(g['id'])
                          ? OutlinedButton(
                              onPressed: () => _toggle(g['id']),
                              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                              child: Text(tr('SIGUIENDO', 'FOLLOWING')),
                            )
                          : FilledButton(
                              onPressed: () => _toggle(g['id']),
                              style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                              child: Text(tr('SEGUIR', 'FOLLOW')),
                            ),
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
