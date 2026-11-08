import 'package:flutter/material.dart';

/// Soft, rounded, friendly look inspired by (not copied from) Samsung Notes.
ThemeData buildTheme(Color accent, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness, primary: accent);
  final dark = brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF17191D) : const Color(0xFFF5F5F7);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      surface: surface,
      surfaceContainerLowest: dark ? const Color(0xFF111316) : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF1E2126) : Colors.white,
      surfaceContainer: dark ? const Color(0xFF23262C) : const Color(0xFFEFEFF3),
      surfaceContainerHigh: dark ? const Color(0xFF2A2E35) : const Color(0xFFE8E8EE),
      onPrimary: Colors.white,
    ),
    scaffoldBackgroundColor: surface,
    fontFamily: 'Segoe UI',
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1E2126) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    popupMenuTheme: PopupMenuThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF23262C) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    ),
  );
}
