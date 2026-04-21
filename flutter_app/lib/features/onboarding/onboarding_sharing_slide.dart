import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Slide 3 — onboarding_sharing/code.html
// Layout: full-bleed illustration top 530px (same pattern),
// content: "Share peace of mind" heading, body text.
class OnboardingSharingSlide extends StatelessWidget {
  const OnboardingSharingSlide({super.key});

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
                    colors: [Color(0xFF0D1520), Color(0xFF101419)],
                  ),
                ),
              ),
              // Gradient: from-transparent via-background/40 to-background
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.background.withValues(alpha: 0.4),
                      AppColors.background,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              Center(
                child: Icon(
                  Icons.people_rounded,
                  size: 120,
                  color: AppColors.primaryContainer.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ),

        // Content area — flex-1 px-8 pb-12 bg-background
        Expanded(
          child: Container(
            width: double.infinity,
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title — text-3xl font-bold text-on-surface
                Text(
                  'Share peace of mind',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.xl3, // text-3xl = 30sp
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16), // mb-4
                // Body — text-base text-secondary leading-relaxed
                Text(
                  'Invite family members by email. They see the same '
                  'realtime data and alerts you do.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    color: AppColors.secondary,
                    height: 1.6,
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
