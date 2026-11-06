import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const backgroundDark = Color(0xFF0A0C0B);
  static const surfaceDark = Color(0xFF191D1B);
  static const neonGreen = Color(0xFF55FC27);
  static const textLight = Color(0xFFF4F6F3);
  static const textMuted = Color(0xFFA4ADA6);
  static const backgroundLight = Color(0xFFF3F5F1);
  static const surfaceLight = Colors.white;
  static const textDark = Color(0xFF141A15);
  static ThemeData get darkTheme => _theme(Brightness.dark);
  static ThemeData get lightTheme => _theme(Brightness.light);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? neonGreen : const Color(0xFF247510);
    final foreground = dark ? textLight : textDark;
    final surface = dark ? surfaceDark : surfaceLight;
    final scheme = ColorScheme.fromSeed(
      seedColor: neonGreen,
      brightness: brightness,
      primary: primary,
      onPrimary: dark ? textDark : Colors.white,
      surface: surface,
      onSurface: foreground,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? backgroundDark : backgroundLight,
      // Drop-down and popup menus open on the theme surface, so their text
      // (onSurface) stays readable in light and dark mode.
      canvasColor: surface,
      primaryColor: primary,
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme.copyWith(
        headlineLarge: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
          color: foreground,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: foreground,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: foreground),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: foreground),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? backgroundDark : backgroundLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: foreground),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: shape,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: foreground.withValues(alpha: 0.08),
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: foreground.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 52),
          backgroundColor: neonGreen,
          foregroundColor: textDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          backgroundColor: neonGreen,
          foregroundColor: textDark,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: foreground,
          shape: const StadiumBorder(),
          side: BorderSide(color: foreground.withValues(alpha: 0.18)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: primary,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: neonGreen,
        foregroundColor: textDark,
        shape: StadiumBorder(),
        elevation: 2,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: foreground, fontSize: 15),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: shape),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Foreground colour for the current theme; replaces hard-coded white text,
/// which disappeared in light mode.
extension AppInk on BuildContext {
  Color ink([double alpha = 1]) =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: alpha);
}
