import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'onboarding_slide_shell.dart';

class OnboardingAlertsSlide extends StatelessWidget {
  const OnboardingAlertsSlide({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingSlideShell(
      imageAsset: 'assets/onboarding/onboarding_step_2.png',
      title: l10n.knowIfSomethingOff,
      body: l10n.alertsSubtitle,
      titleColor: AppColors.primary,
      bodyColor: AppColors.onSurfaceVariant,
      imageAlignment: Alignment.topCenter,
    );
  }
}
