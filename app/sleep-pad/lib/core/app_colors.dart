import 'package:flutter/material.dart';

// Raw color constants extracted from Stitch Tailwind config (identical across all screens).
// Source: docs/stitch_sleep_pad_app_design/*/code.html tailwind.config.theme.extend.colors
abstract final class AppColors {
  // Primary palette
  static const Color primary = Color(0xFFA4FFF8);
  static const Color onPrimary = Color(0xFF003734);
  static const Color primaryFixed = Color(0xFF70F7EF);
  static const Color primaryFixedDim = Color(0xFF4FDAD3);
  static const Color onPrimaryFixed = Color(0xFF00201E);
  static const Color onPrimaryFixedVariant = Color(0xFF00504C);
  static const Color primaryContainer = Color(0xFF5EE7DF);
  static const Color onPrimaryContainer = Color(0xFF006661);
  static const Color inversePrimary = Color(0xFF006A66);

  // Chart accents — used by Home sparklines and History line charts.
  // HR line uses `primaryContainer` (teal #5EE7DF). RR line uses this lavender.
  static const Color rrAccent = Color(0xFFB490F5);

  // Secondary palette
  static const Color secondary = Color(0xFFD4BBFF);
  static const Color onSecondary = Color(0xFF3E1779);
  static const Color secondaryFixed = Color(0xFFEBDCFF);
  static const Color secondaryFixedDim = Color(0xFFD4BBFF);
  static const Color onSecondaryFixed = Color(0xFF260058);
  static const Color onSecondaryFixedVariant = Color(0xFF553291);
  static const Color secondaryContainer = Color(0xFF553291);
  static const Color onSecondaryContainer = Color(0xFFC5A5FF);

  // Tertiary palette
  static const Color tertiary = Color(0xFFFFEDD1);
  static const Color onTertiary = Color(0xFF412D00);
  static const Color tertiaryFixed = Color(0xFFFFDEA5);
  static const Color tertiaryFixedDim = Color(0xFFF2BF59);
  static const Color onTertiaryFixed = Color(0xFF261900);
  static const Color onTertiaryFixedVariant = Color(0xFF5D4200);
  static const Color tertiaryContainer = Color(0xFFFFCB64);
  static const Color onTertiaryContainer = Color(0xFF765500);

  // Error palette
  static const Color error = Color(0xFFFFB4AB);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  // Surface palette
  static const Color surface = Color(0xFF101419);
  static const Color surfaceDim = Color(0xFF101419);
  static const Color surfaceBright = Color(0xFF36393F);
  static const Color surfaceContainerLowest = Color(0xFF0A0E13);
  static const Color surfaceContainerLow = Color(0xFF181C21);
  static const Color surfaceContainer = Color(0xFF1C2025);
  static const Color surfaceContainerHigh = Color(0xFF262A30);
  static const Color surfaceContainerHighest = Color(0xFF31353B);
  static const Color surfaceVariant = Color(0xFF31353B);
  static const Color surfaceTint = Color(0xFF4FDAD3);

  // On-surface
  static const Color onSurface = Color(0xFFE0E2EA);
  static const Color onSurfaceVariant = Color(0xFFBBC9C7);
  static const Color inverseSurface = Color(0xFFE0E2EA);
  static const Color inverseOnSurface = Color(0xFF2D3136);

  // Background
  static const Color background = Color(0xFF101419);
  static const Color onBackground = Color(0xFFE0E2EA);

  // Outline
  static const Color outline = Color(0xFF859492);
  static const Color outlineVariant = Color(0xFF3C4948);

  // Bottom nav specific
  static const Color navActive = Color(0xFF5EE7DF);
  static const Color navInactive = Color(0xFF8B96A5);
  static const Color navActivePill = Color(0xFF1A383A);
  static const Color navBackground = Color(0xFF0A0E13);
}
