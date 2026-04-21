import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Slide 1 — onboarding_sleep_monitoring/code.html
// Layout: full-bleed illustration top 530px, gradient fade to bg,
// content area below with title + body text.
class OnboardingSleepSlide extends StatelessWidget {
  const OnboardingSleepSlide({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Illustration area — h-[530px], gradient overlay fades to #0B0F14
        SizedBox(
          height: 530,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Placeholder for the 3D illustration image.
              // In production replace with actual asset or network image.
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0D1520),
                      Color(0xFF0B1018),
                      Color(0xFF0B0F14),
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
              ),
              // Gradient overlay: from-transparent to-[#0B0F14] — fade bottom
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xFF0B0F14)],
                    stops: [0.5, 1.0],
                  ),
                ),
              ),
              // Centered icon as illustration stand-in
              Center(
                child: Icon(
                  Icons.bed_rounded,
                  size: 120,
                  color: AppColors.primaryContainer.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ),

        // Content area — rounded-t-xl bg-[#0B0F14], -mt-6
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 40), // px-8 pb-10
            decoration: const BoxDecoration(
              color: Color(0xFF0B0F14),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              children: [
                // Text content — items-center text-center space-y-4
                Text(
                  'Monitor sleep,\nwithout wearables',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.primaryContainer, // text-primary-container
                    height: 1.25,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16), // space-y-4
                Text(
                  'A sensor under the mattress tracks heart rate, '
                  'breathing, and sleep quality silently through the night.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.base, // text-[16px]
                    color: AppColors.secondary,  // text-secondary
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
