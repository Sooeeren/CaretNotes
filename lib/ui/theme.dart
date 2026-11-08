import 'package:flutter/material.dart';

/// Extra surface tokens the Material scheme doesn't name.
class AppTokens extends ThemeExtension<AppTokens> {
  /// The "desk" behind note pages.
  final Color desk;

  /// 1px separators and card outlines.
  final Color hairline;

  /// Secondary text (dates, counts, captions).
  final Color muted;

  /// Selected nav item / tool background.
  final Color selectedFill;

  const AppTokens({required this.desk, required this.hairline, required this.muted, required this.selectedFill});

  static AppTokens of(BuildContext context) {
    final t = Theme.of(context);
    return t.extension<AppTokens>() ??
        AppTokens(
          desk: t.colorScheme.surfaceContainerHighest,
          hairline: t.colorScheme.outlineVariant,
          muted: t.colorScheme.onSurfaceVariant,
          selectedFill: t.colorScheme.onSurface.withValues(alpha: 0.06),
        );
  }

  @override
  AppTokens copyWith({Color? desk, Color? hairline, Color? muted, Color? selectedFill}) => AppTokens(
        desk: desk ?? this.desk,
        hairline: hairline ?? this.hairline,
        muted: muted ?? this.muted,
        selectedFill: selectedFill ?? this.selectedFill,
      );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      desk: Color.lerp(desk, other.desk, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
    );
  }
}

/// Calm "paper and ink" look: graphite neutrals, one restrained accent used only
/// for the current tool and the primary action, tight radii, thin outlined icons.
ThemeData buildTheme(Color accent, Brightness brightness) {
  final dark = brightness == Brightness.dark;

  // Neutrals (slightly warm graphite, never pure black).
  final bg = dark ? const Color(0xFF1A1B1E) : const Color(0xFFF6F5F3);
  final panel = dark ? const Color(0xFF202125) : const Color(0xFFFFFFFF);
  final raised = dark ? const Color(0xFF26272C) : const Color(0xFFFFFFFF);
  final field = dark ? const Color(0xFF2A2B30) : const Color(0xFFEFEEEB);
  final ink = dark ? const Color(0xFFE8E6E3) : const Color(0xFF1F2023);
  final muted = dark ? const Color(0xFF9E9CA0) : const Color(0xFF6B6A6E);
  final hairline = dark ? const Color(0xFF33343A) : const Color(0xFFE3E1DD);

  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    surface: bg,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceContainerLowest: dark ? const Color(0xFF151618) : Colors.white,
    surfaceContainerLow: panel,
    surfaceContainer: raised,
    surfaceContainerHigh: field,
    surfaceContainerHighest: dark ? const Color(0xFF303136) : const Color(0xFFE7E5E1),
    outline: dark ? const Color(0xFF5A5A60) : const Color(0xFFB9B7B2),
    outlineVariant: hairline,
  );

  const radius = 10.0;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final text = base.textTheme.apply(fontFamily: 'Segoe UI Variable Text', bodyColor: ink, displayColor: ink).copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: 'Segoe UI Variable Display', fontWeight: FontWeight.w600, fontSize: 20, letterSpacing: -0.2, color: ink),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontFamily: 'Segoe UI Variable Text', fontWeight: FontWeight.w600, fontSize: 15, color: ink),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontFamily: 'Segoe UI Variable Text', fontWeight: FontWeight.w600, fontSize: 13.5, color: ink),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontFamily: 'Segoe UI Variable Text', fontSize: 14, color: ink),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontFamily: 'Segoe UI Variable Text', fontSize: 13.5, color: ink),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontFamily: 'Segoe UI Variable Text', fontSize: 12, color: muted),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontFamily: 'Segoe UI Variable Text', fontWeight: FontWeight.w600, fontSize: 13, color: ink),
        labelMedium: base.textTheme.labelMedium?.copyWith(fontFamily: 'Segoe UI Variable Text', fontSize: 12, color: muted),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: 'Segoe UI Variable Text',
    fontFamilyFallback: const ['Segoe UI', 'Roboto'],
    textTheme: text,
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: muted, size: 20),
    extensions: [
      AppTokens(
        desk: dark ? const Color(0xFF141517) : const Color(0xFFE6E4E0),
        hairline: hairline,
        muted: muted,
        selectedFill: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
      ),
    ],
    cardTheme: CardThemeData(
      elevation: 0,
      color: panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: hairline)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: text.titleLarge,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: raised,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: hairline)),
      textStyle: text.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      isDense: true,
      hintStyle: TextStyle(color: muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent, width: 1.2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(color: dark ? const Color(0xFFE8E6E3) : const Color(0xFF2A2B2F), borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: dark ? const Color(0xFF1A1B1E) : Colors.white, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), side: BorderSide(color: hairline)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), foregroundColor: muted),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), side: BorderSide(color: hairline)),
    sliderTheme: const SliderThemeData(trackHeight: 3),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(muted.withValues(alpha: 0.35)),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: accent, selectionColor: accent.withValues(alpha: 0.25), selectionHandleColor: accent),
  );
}
