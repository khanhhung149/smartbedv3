import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

// Theme derived from Stitch Tailwind design tokens.
// Border radius defaults: rounded = 16px, rounded-lg = 32px, rounded-xl = 48px, rounded-full = 9999px
// Typography: Inter (google_fonts), mapped from Tailwind text-* scale.
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: _colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: _textTheme(base.textTheme),
    );
  }

  static ColorScheme get _colorScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        tertiaryContainer: AppColors.tertiaryContainer,
        onTertiaryContainer: AppColors.onTertiaryContainer,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        surfaceContainerHighest: AppColors.surfaceContainerHighest,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        inverseSurface: AppColors.inverseSurface,
        onInverseSurface: AppColors.inverseOnSurface,
        inversePrimary: AppColors.inversePrimary,
        surfaceTint: AppColors.surfaceTint,
      );

  static TextTheme _textTheme(TextTheme base) {
    // Inter mapped to Material text roles. Sizes match Tailwind text-* scale.
    final inter = GoogleFonts.interTextTheme(base).apply(
      bodyColor: AppColors.onSurface,
      displayColor: AppColors.onSurface,
    );
    return inter;
  }
}

// Tailwind text-* → logical pixels (1:1 mapping per spec)
abstract final class AppTextSize {
  static const double xs = 12;    // text-xs
  static const double sm = 14;    // text-sm
  static const double base = 16;  // text-base
  static const double lg = 18;    // text-lg
  static const double xl = 20;    // text-xl
  static const double xl2 = 24;   // text-2xl
  static const double xl3 = 30;   // text-3xl
  static const double xl4 = 36;   // text-4xl
  static const double xl5 = 48;   // text-5xl
}

// Tailwind font-weight → Flutter FontWeight
abstract final class AppFontWeight {
  static const FontWeight medium = FontWeight.w500;    // font-medium
  static const FontWeight semiBold = FontWeight.w600; // font-semibold
  static const FontWeight bold = FontWeight.w700;     // font-bold
  static const FontWeight black = FontWeight.w900;    // font-black
}

// Tailwind border-radius tokens
abstract final class AppRadius {
  static const double defaultRadius = 16;  // rounded (DEFAULT 1rem)
  static const double lg = 32;             // rounded-lg (2rem)
  static const double xl = 48;             // rounded-xl (3rem)
  static const double full = 9999;         // rounded-full

  static BorderRadius get defaultBr =>
      BorderRadius.circular(defaultRadius);
  static BorderRadius get lgBr => BorderRadius.circular(lg);
  static BorderRadius get xlBr => BorderRadius.circular(xl);
  static BorderRadius get fullBr => BorderRadius.circular(full);

  // rounded-t-[32px]: top corners only, 32px
  static BorderRadius get topLg => const BorderRadius.only(
        topLeft: Radius.circular(32),
        topRight: Radius.circular(32),
      );

  // rounded-[20px] used in login/register inputs
  static BorderRadius get input => BorderRadius.circular(20);
}
