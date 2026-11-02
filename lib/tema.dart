import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'imperio/estilos.dart';

// Estilo: esquinas de 2px, bordes de 1px, sin sombras ni degradados, letra del sistema
// con cifras tabulares y un solo color de acento. El acento y la paleta cambian con el tema de la tienda de estilo
// del Imperio (lib/imperio/tienda_estilo.dart); el Clásico es el amarillo de siempre.
const radio = 2.0;
const _amarillo = Color(0xFFFFD60A);
const _amarilloTexto = Color(0xFF111111);

/// El acento del tema en uso (amarillo en el Clásico). No es constante: cambia al elegir otro tema.
Color get acento => _paletaEstilo().acento;

/// Texto encima del acento, con contraste para cada tema.
Color get acentoTexto => _paletaEstilo().acentoTexto;

class Paleta {
  const Paleta({
    required this.fondo,
    required this.tarjeta,
    required this.suave,
    required this.texto,
    required this.textoSuave,
    required this.borde,
    required this.bordeFuerte,
    required this.primario,
    required this.sobrePrimario,
    this.acento = _amarillo,
    this.acentoTexto = _amarilloTexto,
  });

  final Color fondo, tarjeta, suave, texto, textoSuave, borde, bordeFuerte, primario, sobrePrimario;

  /// El único color de acento del tema y el texto que va encima.
  final Color acento, acentoTexto;

  static const claro = Paleta(
    fondo: Color(0xFFF7F6F3),
    tarjeta: Color(0xFFFFFFFF),
    suave: Color(0xFFEFEDE8),
    texto: Color(0xFF171513),
    textoSuave: Color(0xFF5C5751),
    borde: Color(0xFFDEDBD5),
    bordeFuerte: Color(0xFF8C867E),
    primario: Color(0xFF171513),
    sobrePrimario: Color(0xFFFFFFFF),
  );

  // En oscuro el acento amarillo es el color principal (botones y selección).
  static const oscuro = Paleta(
    fondo: Color(0xFF0E0E0D),
    tarjeta: Color(0xFF181816),
    suave: Color(0xFF23221F),
    texto: Color(0xFFF2F0EC),
    textoSuave: Color(0xFFA8A39B),
    borde: Color(0xFF2E2C29),
    bordeFuerte: Color(0xFF5E5953),
    primario: _amarillo,
    sobrePrimario: _amarilloTexto,
  );

  // Temas de la tienda de estilo. Cada uno tiene su brillo fijo (ver _brilloEstilo) y un solo acento, que también
  // es el color principal (botones y selección).
  static const porcelana = Paleta(
    fondo: Color(0xFFF3F7FA),
    tarjeta: Color(0xFFFFFFFF),
    suave: Color(0xFFE3ECF3),
    texto: Color(0xFF10202E),
    textoSuave: Color(0xFF4C6070),
    borde: Color(0xFFD0DCE6),
    bordeFuerte: Color(0xFF7A90A3),
    primario: Color(0xFF1F6FB2),
    sobrePrimario: Color(0xFFFFFFFF),
    acento: Color(0xFF1F6FB2),
    acentoTexto: Color(0xFFFFFFFF),
  );

  static const cloaca = Paleta(
    fondo: Color(0xFF0C130D),
    tarjeta: Color(0xFF131D14),
    suave: Color(0xFF1B281C),
    texto: Color(0xFFE4F2DF),
    textoSuave: Color(0xFF93A88D),
    borde: Color(0xFF243425),
    bordeFuerte: Color(0xFF4E6A4C),
    primario: Color(0xFF9BE22A),
    sobrePrimario: Color(0xFF0C130D),
    acento: Color(0xFF9BE22A),
    acentoTexto: Color(0xFF0C130D),
  );

  static const papel = Paleta(
    fondo: Color(0xFFF6F1E7),
    tarjeta: Color(0xFFFFFCF5),
    suave: Color(0xFFECE5D6),
    texto: Color(0xFF2B2723),
    textoSuave: Color(0xFF6B645B),
    borde: Color(0xFFDED6C6),
    bordeFuerte: Color(0xFF978E80),
    primario: Color(0xFF726C64),
    sobrePrimario: Color(0xFFFFFFFF),
    acento: Color(0xFF726C64),
    acentoTexto: Color(0xFFFFFFFF),
  );

  // Los 4 verdes de la pantalla del GameBoy (la tarjeta es un paso entre los dos más oscuros).
  static const gameboy = Paleta(
    fondo: Color(0xFF0F380F),
    tarjeta: Color(0xFF184518),
    suave: Color(0xFF306230),
    texto: Color(0xFF9BBC0F),
    textoSuave: Color(0xFF8BAC0F),
    borde: Color(0xFF306230),
    bordeFuerte: Color(0xFF8BAC0F),
    primario: Color(0xFF9BBC0F),
    sobrePrimario: Color(0xFF0F380F),
    acento: Color(0xFF9BBC0F),
    acentoTexto: Color(0xFF0F380F),
  );

  static const neon = Paleta(
    fondo: Color(0xFF07060A),
    tarjeta: Color(0xFF110F16),
    suave: Color(0xFF1C1923),
    texto: Color(0xFFF5EEFA),
    textoSuave: Color(0xFFA99AB6),
    borde: Color(0xFF2A2433),
    bordeFuerte: Color(0xFF5D4F6B),
    primario: Color(0xFFFF2BD6),
    sobrePrimario: Color(0xFF07060A),
    acento: Color(0xFFFF2BD6),
    acentoTexto: Color(0xFF07060A),
  );

  static const marmol = Paleta(
    fondo: Color(0xFFF8F7F4),
    tarjeta: Color(0xFFFFFFFF),
    suave: Color(0xFFEEECE7),
    texto: Color(0xFF1E1C19),
    textoSuave: Color(0xFF5F5A52),
    borde: Color(0xFFE0DCD3),
    bordeFuerte: Color(0xFF9A9283),
    primario: Color(0xFFC9A227),
    sobrePrimario: Color(0xFF1A1712),
    acento: Color(0xFFC9A227),
    acentoTexto: Color(0xFF1A1712),
  );

  static const oro = Paleta(
    fondo: Color(0xFF0B0A07),
    tarjeta: Color(0xFF15130D),
    suave: Color(0xFF201C12),
    texto: Color(0xFFF6EED8),
    textoSuave: Color(0xFFB0A483),
    borde: Color(0xFF2E2818),
    bordeFuerte: Color(0xFF6B5D35),
    primario: Color(0xFFD4AF37),
    sobrePrimario: Color(0xFF0B0A07),
    acento: Color(0xFFD4AF37),
    acentoTexto: Color(0xFF0B0A07),
  );
}

/// Paleta de cada tema de la tienda (el Clásico no está: usa claro u oscuro según el teléfono o Perfil).
const Map<String, Paleta> _paletasEstilo = {
  'tema_porcelana': Paleta.porcelana,
  'tema_cloaca': Paleta.cloaca,
  'tema_papel': Paleta.papel,
  'tema_gameboy': Paleta.gameboy,
  'tema_neon': Paleta.neon,
  'tema_marmol': Paleta.marmol,
  'tema_oro': Paleta.oro,
};

const Set<String> _temasClaros = {'tema_porcelana', 'tema_papel', 'tema_marmol'};

/// Ids de los temas que tienen colores aquí (para el test y la tienda).
Iterable<String> get temasConColores => _paletasEstilo.keys;

/// Brillo fijo del tema, o null si sigue al teléfono o a Perfil (el Clásico).
Brightness? brilloDeEstilo(String id) =>
    _paletasEstilo.containsKey(id) ? (_temasClaros.contains(id) ? Brightness.light : Brightness.dark) : null;

/// Tema de la tienda de estilo en uso (id de lib/imperio/estilos.dart).
final estiloTema = ValueNotifier<String>(temaClasico);

// El Clásico tiene el mismo acento en claro y en oscuro.
Paleta _paletaEstilo() => _paletasEstilo[estiloTema.value] ?? Paleta.claro;

/// Paleta de un tema para la muestra de la tienda (el Clásico, en claro).
Paleta muestraDeTema(String id) => _paletasEstilo[id] ?? Paleta.claro;

/// Paleta para un brillo: la del tema en uso si su brillo coincide; si no (el lado secreto fuerza oscuro), la clásica.
Paleta paletaPara(Brightness brillo) {
  final p = _paletasEstilo[estiloTema.value];
  if (p != null && brilloDeEstilo(estiloTema.value) == brillo) return p;
  return brillo == Brightness.dark ? Paleta.oscuro : Paleta.claro;
}

/// Modo para MaterialApp: el brillo fijo del tema o, en el Clásico, lo elegido en Perfil.
ThemeMode modoDeTema() => switch (brilloDeEstilo(estiloTema.value)) {
      Brightness.light => ThemeMode.light,
      Brightness.dark => ThemeMode.dark,
      null => temaElegido.value,
    };

/// Relleno con el borde de abajo del sistema sumado (barra de gestos o botones). Con la app de
/// extremo a extremo, todo lo que no está sobre la barra de pestañas lo necesita.
EdgeInsets conBordeAbajo(BuildContext context, EdgeInsets e) =>
    e.copyWith(bottom: e.bottom + MediaQuery.paddingOf(context).bottom);

Paleta paleta(BuildContext context) => paletaPara(Theme.of(context).brightness);

const _tabular = [FontFeature.tabularFigures()];

/// Números: letra del sistema con cifras tabulares para que las columnas cuadren.
TextStyle numeros(BuildContext context, {double tamano = 14, FontWeight weight = FontWeight.w600, Color? color}) =>
    TextStyle(
      fontSize: tamano,
      fontWeight: weight,
      color: color ?? paleta(context).texto,
      fontFeatures: _tabular,
    );

/// Rótulo de sección: MAYÚSCULAS, chico y espaciado.
class Rotulo extends StatelessWidget {
  const Rotulo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: numeros(context, tamano: 11, weight: FontWeight.w700, color: paleta(context).textoSuave)
            .copyWith(letterSpacing: 1.2),
      );
}

/// Claro, oscuro o el del teléfono. Se elige en Perfil.
final temaElegido = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Claves en SharedPreferences: el tema de la tienda en uso y la copia local de los estilos comprados
/// (la llena lib/imperio/estilos_mios.dart).
const prefTemaEstilo = 'tema_estilo';
const prefEstilosComprados = 'estilos_comprados';

Future<void> iniciarTema() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    temaElegido.value = ThemeMode.values.byName(prefs.getString('tema') ?? 'system');
    // Un tema que no está en la copia local de lo comprado (o que ya no existe) vuelve al Clásico.
    final id = prefs.getString(prefTemaEstilo) ?? temaClasico;
    final comprados = (prefs.getStringList(prefEstilosComprados) ?? const <String>[]).toSet();
    estiloTema.value = _paletasEstilo.containsKey(id) && tieneEstilo(comprados, id) ? id : temaClasico;
  } catch (_) {}
}

/// Pone un tema de la tienda (o el Clásico) y lo guarda. Quien llama ya revisó que lo tengas.
Future<void> elegirEstiloTema(String id) async {
  final nuevo = _paletasEstilo.containsKey(id) ? id : temaClasico;
  if (estiloTema.value != nuevo) {
    estiloTema.value = nuevo;
    _repintarTodo();
  }
  try {
    await (await SharedPreferences.getInstance()).setString(prefTemaEstilo, nuevo);
  } catch (_) {}
}

// El acento se lee como getter (no de Theme), así que hay widgets que no se enteran del cambio: se reconstruye
// todo el árbol después del cuadro en que MaterialApp toma el tema nuevo.
void _repintarTodo() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    void marcar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(marcar);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(marcar);
  });
}

Future<void> elegirTema(ThemeMode modo) async {
  temaElegido.value = modo;
  _repintarTodo();
  try {
    await (await SharedPreferences.getInstance()).setString('tema', modo.name);
  } catch (_) {}
}

const _emojisNuevos = ['EmojiNuevos'];

ThemeData tema(Brightness brillo) {
  final p = paletaPara(brillo);
  final acento = p.acento, acentoTexto = p.acentoTexto;
  final scheme = ColorScheme(
    brightness: brillo,
    primary: p.primario,
    onPrimary: p.sobrePrimario,
    primaryContainer: acento,
    onPrimaryContainer: acentoTexto,
    secondary: p.textoSuave,
    onSecondary: p.fondo,
    secondaryContainer: p.suave,
    onSecondaryContainer: p.texto,
    tertiary: acento,
    onTertiary: acentoTexto,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: p.fondo,
    onSurface: p.texto,
    onSurfaceVariant: p.textoSuave,
    surfaceContainerLowest: p.tarjeta,
    surfaceContainerLow: p.tarjeta,
    surfaceContainer: p.tarjeta,
    surfaceContainerHigh: p.suave,
    surfaceContainerHighest: p.suave,
    outline: p.bordeFuerte,
    outlineVariant: p.borde,
  );
  final cuadrado = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio));
  final conBorde = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radio),
    side: BorderSide(color: p.borde),
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
    // Emojis nuevos que el teléfono no sabe dibujar (ver pubspec.yaml).
    fontFamilyFallback: _emojisNuevos,
  );
  final titulo = TextStyle(fontWeight: FontWeight.w800, color: p.texto, fontFeatures: _tabular, fontFamilyFallback: _emojisNuevos);
  TextStyle boton(double tamano, {double espacio = 0.6, Color? color}) =>
      TextStyle(fontSize: tamano, fontWeight: FontWeight.w700, letterSpacing: espacio, color: color);

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: titulo.copyWith(fontSize: 32, letterSpacing: -1),
      headlineSmall: titulo.copyWith(fontSize: 22, letterSpacing: -0.5),
      titleLarge: titulo.copyWith(fontSize: 18, letterSpacing: -0.2),
    ),
    scaffoldBackgroundColor: p.fondo,
    dividerTheme: DividerThemeData(color: p.borde, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.fondo,
      foregroundColor: p.texto,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: p.borde)),
      titleTextStyle: titulo.copyWith(fontSize: 17, letterSpacing: 0.4),
    ),
    cardTheme: CardThemeData(elevation: 0, color: p.tarjeta, shape: conBorde, margin: EdgeInsets.zero),
    listTileTheme: ListTileThemeData(shape: cuadrado),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.tarjeta,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radio), borderSide: BorderSide(color: p.bordeFuerte)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radio), borderSide: BorderSide(color: p.bordeFuerte)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radio), borderSide: BorderSide(color: p.texto, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: cuadrado,
        minimumSize: const Size(64, 52),
        textStyle: boton(15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: cuadrado,
        side: BorderSide(color: p.bordeFuerte),
        foregroundColor: p.texto,
        minimumSize: const Size(64, 44),
        textStyle: boton(14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: cuadrado,
        foregroundColor: p.texto,
        textStyle: boton(14, espacio: 0.3),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: cuadrado)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(cuadrado),
        side: WidgetStatePropertyAll(BorderSide(color: p.bordeFuerte)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primario : p.tarjeta),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.sobrePrimario : p.texto),
        textStyle: WidgetStatePropertyAll(boton(12, espacio: 0.8)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: cuadrado,
      side: BorderSide(color: p.bordeFuerte),
      backgroundColor: p.tarjeta,
      selectedColor: acento,
      labelStyle: boton(12, espacio: 0.8, color: p.texto),
      secondaryLabelStyle: boton(12, espacio: 0.8, color: acentoTexto),
      checkmarkColor: acentoTexto,
    ),
    dialogTheme: DialogThemeData(shape: conBorde, backgroundColor: p.tarjeta),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: p.tarjeta,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radio))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.horizontal, // se quitan deslizando hacia un lado
      backgroundColor: p.texto,
      contentTextStyle: TextStyle(fontSize: 14, color: p.fondo),
      shape: cuadrado,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.texto, linearTrackColor: p.suave),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.fondo,
      surfaceTintColor: Colors.transparent,
      indicatorColor: acento,
      indicatorShape: cuadrado,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(boton(11, espacio: 0.8)),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? acentoTexto : p.texto),
      ),
    ),
  );
}
