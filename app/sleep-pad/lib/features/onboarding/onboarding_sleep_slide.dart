import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'onboarding_slide_shell.dart';

class OnboardingSleepSlide extends StatelessWidget {
  const OnboardingSleepSlide({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingSlideShell(
      imageAsset: 'assets/onboarding/onboarding_step_1.png',
      title: l10n.monitorSleepTagline,
      body: l10n.onboardingSleepSubtitle,
      imageAlignment: Alignment.topCenter,
    );
  }
}
