import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'workbench_colors.dart';

ThemeData buildWorkbenchTheme() {
  const colors = WorkbenchColors(
    app: Color(0xFF181818),
    chrome: Color(0xFF181818),
    canvas: Color(0xFF1F1F1F),
    elevated: Color(0xFF222222),
    input: Color(0xFF313131),
    inputHover: Color(0xFF3C3C3C),
    borderSubtle: Color(0xFF2B2B2B),
    borderDefault: Color(0xFF3C3C3C),
    fgDefault: Color(0xFFCCCCCC),
    fgStrong: Color(0xFFFFFFFF),
    fgMuted: Color(0xFF9D9D9D),
    fgInactive: Color(0xFF868686),
    fgPlaceholder: Color(0xFF989898),
    accentPrimary: Color(0xFF0078D4),
    accentPrimaryHover: Color(0xFF026EC1),
    statusError: Color(0xFFF85149),
    statusSuccess: Color(0xFF2EA043),
    aiCommandBg: Color(0x66264778),
    aiCommandFg: Color(0xFF85B6FF),
    aiEditedFileFg: Color(0xFFE2C08D),
  );

  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colors.app,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF0078D4),
      surface: Color(0xFF1F1F1F),
      onSurface: Color(0xFFCCCCCC),
    ),
    dividerColor: colors.borderSubtle,
    extensions: const [colors],
  );

  final textTheme = GoogleFonts.ubuntuTextTheme(base.textTheme).apply(
    bodyColor: colors.fgDefault,
    displayColor: colors.fgStrong,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.chrome,
      foregroundColor: colors.fgDefault,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: colors.fgStrong,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.input,
      hintStyle: TextStyle(color: colors.fgPlaceholder, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colors.accentPrimary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accentPrimary,
        foregroundColor: colors.fgStrong,
        minimumSize: const Size(88, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accentPrimary,
        minimumSize: const Size(44, 44),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.elevated,
      contentTextStyle: textTheme.bodyMedium,
    ),
  );
}

TextStyle workbenchMonoStyle(
  BuildContext context, {
  double size = 13,
  Color? color,
}) {
  return GoogleFonts.ubuntuMono(
    fontSize: size,
    height: 1.5,
    color: color ?? context.workbenchColors.fgDefault,
  );
}
