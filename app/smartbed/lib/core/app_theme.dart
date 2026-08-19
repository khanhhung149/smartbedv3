import 'package:flutter/material.dart';

/// Metric palette — one semantic colour per physiological channel so a chart
/// line and its label always agree without anyone memorising hex codes.
///
/// Kept outside the `ColorScheme` because these are data colours, not UI
/// colours: they must stay distinguishable from each other and from the
/// surface, and they must not shift when the seed colour changes.
abstract final class MetricColors {
  /// Heart rate.
  static const heart = Color(0xFFFF7A93);

  /// Respiration.
  static const breath = Color(0xFF5BC8AF);

  /// Body movement / turning over.
  static const movement = Color(0xFFE8B34B);

  /// Snoring.
  static const snore = Color(0xFFFF9F5A);

  /// Respiratory disorder events.
  static const respDisorder = Color(0xFFB48CF2);

  /// Sitting up.
  static const sitUp = Color(0xFFF29D6B);

  /// Waking.
  static const wake = Color(0xFF8FB8F2);

  /// Occupancy band "on bed".
  static const onBed = Color(0xFF5BC8AF);
}

/// Dark by default: this app is read in bed, in the dark, first thing after
/// waking. A white screen at that moment is a usability problem, not a taste one.
///
/// Surfaces are layered so depth reads even without shadows: scaffold darkest,
/// card one step up, interactive wells one step more. Borders rather than
/// elevation separate cards on dark, which is why every surface has an outline.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7C9BF8),
    brightness: Brightness.dark,
  ).copyWith(
    surface: const Color(0xFF12151D),
    onSurface: const Color(0xFFE7EAF3),
    surfaceContainerLow: const Color(0xFF171B25),
    surfaceContainer: const Color(0xFF1B202C),
    surfaceContainerHigh: const Color(0xFF222836),
    surfaceContainerHighest: const Color(0xFF2A3243),
    outlineVariant: const Color(0xFF333B4D),
  );

  // Numbers must not jitter when a tile updates — tabular figures keep every
  // digit the same width so a heartbeat of 52→70 does not shove its label.
  const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0E1016),
    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600)
          .merge(tabular),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.72),
      ),
      bodyMedium: base.textTheme.bodyMedium?.merge(tabular),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.66),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      labelStyle: base.textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF0E1016),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge,
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}