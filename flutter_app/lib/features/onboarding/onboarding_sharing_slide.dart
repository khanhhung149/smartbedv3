import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'onboarding_slide_shell.dart';

class OnboardingSharingSlide extends StatelessWidget {
  const OnboardingSharingSlide({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingSlideShell(
      imageAsset: 'assets/onboarding/onboarding_step_3.png',
      title: l10n.sharingTitle,
      body: l10n.sharingSubtitle,
      titleColor: AppColors.onSurface,
      bodyColor: AppColors.secondary,
      imageAlignment: Alignment.topCenter,
    );
  }
}
