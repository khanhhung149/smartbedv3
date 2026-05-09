import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Shared onboarding slide layout matching the current Figma export:
// full-bleed hero image, top/bottom fades, then centered text block.
class OnboardingSlideShell extends StatelessWidget {
  const OnboardingSlideShell({
    super.key,
    required this.imageAsset,
    required this.title,
    required this.body,
    this.titleColor = AppColors.primaryContainer,
    this.bodyColor = AppColors.secondary,
    this.imageFit = BoxFit.cover,
    this.imageAlignment = Alignment.topCenter,
  });

  final String imageAsset;
  final String title;
  final String body;
  final Color titleColor;
  final Color bodyColor;
  final BoxFit imageFit;
  final Alignment imageAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 15,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(imageAsset, fit: imageFit, alignment: imageAlignment),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D141E), Color(0x000D141E)],
                    stops: [0, 0.16],
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 106,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFF0B0E13), Color(0x000B0E13)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 10,
          child: Container(
            width: double.infinity,
            color: const Color(0xFF0B0E13),
            padding: const EdgeInsets.fromLTRB(32, 4, 32, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: AppFontWeight.bold,
                    color: titleColor,
                    height: 1.18,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xl,
                      color: bodyColor,
                      height: 1.6,
                      letterSpacing: 0.1,
                    ),
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
