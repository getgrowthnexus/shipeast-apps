import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'se_colors.dart';
import 'se_spacing.dart';
import 'se_typography.dart';

/// ShipEast Design System — assembled [ThemeData] for light and dark.
///
/// Backward-compatible aliases (`AppTheme.primary`, `AppTheme.dark`, …) are
/// kept so screens not yet migrated to the SEDS tokens keep compiling; new
/// code should reference [SeColors] / [SeType] / [SeSpacing] directly.
class AppTheme {
  AppTheme._();

  // ── Backward-compatible aliases (point into the SEDS ramp) ───────────────
  static const Color primary = SeColors.brandAction; // action red — carries white text
  static const Color primaryLight = SeColors.brandSoft;
  static const Color dark = SeColors.ink900;
  static const Color gray = SeColors.ink500;
  static const Color lightGray = SeColors.surface50;
  static const Color inputBg = SeColors.field;
  static const Color inputBorder = SeColors.ink200;

  static TextTheme _textTheme(Color hi, Color lo) {
    final base = GoogleFonts.figtreeTextTheme();
    return base.copyWith(
      displayLarge: SeType.display.copyWith(color: hi),
      displayMedium: SeType.h1.copyWith(color: hi),
      headlineMedium: SeType.h2.copyWith(color: hi),
      headlineSmall: SeType.h3.copyWith(color: hi),
      titleLarge: SeType.title.copyWith(color: hi),
      titleMedium: SeType.title.copyWith(color: hi),
      bodyLarge: SeType.body.copyWith(color: hi),
      bodyMedium: SeType.body.copyWith(color: lo),
      bodySmall: SeType.bodyS.copyWith(color: lo),
      labelLarge: SeType.label.copyWith(color: hi),
      labelMedium: SeType.label.copyWith(color: lo),
      labelSmall: SeType.eyebrow.copyWith(color: lo),
    );
  }

  static ThemeData get theme => _build(
        brightness: Brightness.light,
        bg: SeColors.surface50,
        card: SeColors.surface0,
        textHi: SeColors.ink900,
        textLo: SeColors.ink500,
        border: SeColors.ink200,
        brand: SeColors.brandAction, // action red — white text clears AA
        fieldFill: SeColors.field,
      );

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        bg: SeColors.darkBg,
        card: SeColors.darkCard,
        textHi: SeColors.darkTextHi,
        textLo: SeColors.darkTextLo,
        border: SeColors.darkBorder,
        brand: SeColors.brandAction,
        fieldFill: SeColors.darkCardRaised,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color card,
    required Color textHi,
    required Color textLo,
    required Color border,
    required Color brand,
    required Color fieldFill,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: SeColors.red500,
      brightness: brightness,
    ).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      surface: card,
      onSurface: textHi,
      error: SeColors.danger,
      secondary: SeColors.info,
      tertiary: SeColors.warning,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: border,
      splashFactory: InkRipple.splashFactory,
      textTheme: _textTheme(textHi, textLo),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: textHi,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: SeType.h3.copyWith(color: textHi),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: SeRadius.sheetTop),
        showDragHandle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: SeType.body.copyWith(color: SeColors.ink400),
        border: OutlineInputBorder(
          borderRadius: SeRadius.inputRadius,
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: SeRadius.inputRadius,
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: SeRadius.inputRadius,
          borderSide: const BorderSide(color: SeColors.brandAction, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: SeRadius.inputRadius,
          borderSide: const BorderSide(color: SeColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: SeRadius.inputRadius,
          borderSide: const BorderSide(color: SeColors.danger, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SeColors.ink900,
        contentTextStyle: SeType.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: SeRadius.all(SeRadius.sm)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SeColors.brandAction,
      ),
      // Buttons are PILLS now (see SeRadius). These theme any raw Material
      // buttons; the app's primary CTA is the custom SeButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SeColors.brandAction,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: SeType.title,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SeColors.brandAction,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: SeType.title,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          side: BorderSide(color: border, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: SeType.title,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: SeType.title,
        ),
      ),
    );
  }
}
