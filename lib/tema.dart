import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _cafe = Color(0xFF7B4A2A);
const oro = Color(0xFFF2B705);
const plata = Color(0xFFB8BCC4);
const bronce = Color(0xFFCD7F32);

ThemeData tema(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: _cafe, brightness: brillo);
  if (!oscuro) {
    // Crema en vez del gris rosado que sale del seed.
    scheme = scheme.copyWith(
      surface: const Color(0xFFFFF8F1),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFCF1E6),
      surfaceContainer: const Color(0xFFF7EADC),
      surfaceContainerHigh: const Color(0xFFF1E2D2),
    );
  }
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final redondo = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
  return base.copyWith(
    // Nunito se baja la primera vez y queda en caché; sin internet cae a la letra del sistema.
    textTheme: GoogleFonts.nunitoTextTheme(base.textTheme),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: redondo,
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(shape: redondo),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        textStyle: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}
