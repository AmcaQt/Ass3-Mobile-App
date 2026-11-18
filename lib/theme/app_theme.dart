import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // light
  static const paper = Color(0xFFECEDEA);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1E2326);
  static const muted = Color(0xFF5D646A);
  static const line = Color(0xFFD3D6D2);
  // dark
  static const paperDark = Color(0xFF15191B);
  static const surfaceDark = Color(0xFF1F2427);
  static const inkDark = Color(0xFFE8EAE6);
  static const mutedDark = Color(0xFF9BA3A8);
  static const lineDark = Color(0xFF2E3437);
  // ISO safety status (same in both modes, tuned to read on both)
  static const safe = Color(0xFF2E8B57);
  static const warning = Color(0xFFF2B705);
  static const danger = Color(0xFFC8312B);
}

enum LabStatus { safe, warning, danger }

extension LabStatusX on LabStatus {
  Color get color => switch (this) {
    LabStatus.safe => AppColors.safe,
    LabStatus.warning => AppColors.warning,
    LabStatus.danger => AppColors.danger,
  };
  // text on top of the status color: yellow needs dark text, others white
  Color get onColor => this == LabStatus.warning ? AppColors.ink : Colors.white;
  String get label => name.toUpperCase();
}

class AppTheme {
  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color fg,
    required Color muted,
    required Color line,
  }) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final text = GoogleFonts.barlowTextTheme(base.textTheme)
        .apply(bodyColor: fg, displayColor: fg);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: fg,
        onPrimary: bg,
        secondary: fg,
        onSecondary: bg,
        error: AppColors.danger,
        onError: Colors.white,
        surface: surface,
        onSurface: fg,
        outline: line,
        onSurfaceVariant: muted,
      ),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        titleTextStyle: GoogleFonts.barlowCondensed(
            fontSize: 22, fontWeight: FontWeight.w600, color: fg, letterSpacing: 0.5),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: line),
        ),
      ),
      dividerColor: line,
    );
  }

  static final light = _build(
    brightness: Brightness.light,
    bg: AppColors.paper, surface: AppColors.surface,
    fg: AppColors.ink, muted: AppColors.muted, line: AppColors.line,
  );

  static final dark = _build(
    brightness: Brightness.dark,
    bg: AppColors.paperDark, surface: AppColors.surfaceDark,
    fg: AppColors.inkDark, muted: AppColors.mutedDark, line: AppColors.lineDark,
  );
}