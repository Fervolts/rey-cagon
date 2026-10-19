import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Mismo lenguaje que Ahí Guardaito: esquinas de 2px, bordes de 1px, sin sombras ni degradados,
// números en mono y un solo acento fuerte (allá lima, aquí amarillo corona).
const radio = 2.0;
const acento = Color(0xFFFFD60A);
const acentoTexto = Color(0xFF111111);

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
  });

  final Color fondo, tarjeta, suave, texto, textoSuave, borde, bordeFuerte, primario, sobrePrimario;

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

  static const oscuro = Paleta(
    fondo: Color(0xFF121110),
    tarjeta: Color(0xFF1A1917),
    suave: Color(0xFF242220),
    texto: Color(0xFFF1EFEB),
    textoSuave: Color(0xFFB0AAA2),
    borde: Color(0xFF34312D),
    bordeFuerte: Color(0xFF6F6962),
    primario: Color(0xFFF1EFEB),
    sobrePrimario: Color(0xFF121110),
  );
}

Paleta paleta(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Paleta.oscuro : Paleta.claro;

/// Números y etiquetas: mono con cifras tabulares.
TextStyle mono(BuildContext context, {double size = 14, FontWeight weight = FontWeight.w600, Color? color}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color ?? paleta(context).texto,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Rótulo de sección: MAYÚSCULAS, mono, espaciado.
class Rotulo extends StatelessWidget {
  const Rotulo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: mono(context, size: 11, weight: FontWeight.w700, color: paleta(context).textoSuave)
            .copyWith(letterSpacing: 1.6),
      );
}

ThemeData tema(Brightness brillo) {
  final p = brillo == Brightness.dark ? Paleta.oscuro : Paleta.claro;
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
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, splashFactory: InkRipple.splashFactory);
  final titulo = GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w800, color: p.texto);

  return base.copyWith(
    // Texto corrido con la letra del sistema; títulos en mono.
    textTheme: base.textTheme.copyWith(
      headlineLarge: titulo.copyWith(fontSize: 32, letterSpacing: -0.5),
      headlineSmall: titulo.copyWith(fontSize: 22, letterSpacing: -0.3),
      titleLarge: titulo.copyWith(fontSize: 18),
    ),
    scaffoldBackgroundColor: p.fondo,
    dividerTheme: DividerThemeData(color: p.borde, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.fondo,
      foregroundColor: p.texto,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: p.borde)),
      titleTextStyle: titulo.copyWith(fontSize: 16, letterSpacing: 1.2),
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
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: cuadrado,
        side: BorderSide(color: p.bordeFuerte),
        foregroundColor: p.texto,
        minimumSize: const Size(64, 44),
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: cuadrado,
        foregroundColor: p.texto,
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: cuadrado)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(cuadrado),
        side: WidgetStatePropertyAll(BorderSide(color: p.bordeFuerte)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primario : p.tarjeta),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.sobrePrimario : p.texto),
        textStyle: WidgetStatePropertyAll(GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: cuadrado,
      side: BorderSide(color: p.bordeFuerte),
      backgroundColor: p.tarjeta,
      selectedColor: acento,
      labelStyle: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: p.texto),
      secondaryLabelStyle: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: acentoTexto),
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
      backgroundColor: p.texto,
      contentTextStyle: GoogleFonts.jetBrainsMono(fontSize: 13, color: p.fondo),
      shape: cuadrado,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.texto, linearTrackColor: p.suave),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.fondo,
      surfaceTintColor: Colors.transparent,
      indicatorColor: acento,
      indicatorShape: cuadrado,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? acentoTexto : p.texto),
      ),
    ),
  );
}
