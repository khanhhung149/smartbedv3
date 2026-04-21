import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Slide 2 — onboarding_alerts/code.html
// Layout: full-bleed illustration top 530px, gradient fade to surface-container-lowest,
// bottom content area with title, body, pagination dots, action buttons.
class OnboardingAlertsSlide extends StatelessWidget {
  const OnboardingAlertsSlide({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Illustration area — h-[530px]
        SizedBox(
          height: 530,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0F1820), Color(0xFF0A0E13)],
                  ),
                ),
              ),
              // Gradient overlay: from-transparent to-surface-container-lowest
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.surfaceContainerLowest,
                    ],
                    stops: [0.5, 1.0],
                  ),
                ),
              ),
              Center(
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 120,
                  color: AppColors.primaryContainer.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ),

        // Content area — h-[353px] items-center justify-end px-8 pb-12
        Expanded(
          child: Container(
            width: double.infinity,
            color: AppColors.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title — text-[32px] font-bold text-primary
                Text(
                  "Know if something's off",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.primary,
                    height: 1.25,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16), // space-y-4
                // Body — text-[16px] text-on-surface-variant font-light
                Text(
                  'Set personalized thresholds. Get a notification the moment '
                  'vitals drift outside your safe range.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    fontWeight: FontWeight.w300,
                    color: AppColors.onSurfaceVariant,
                    height: 1.6,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
