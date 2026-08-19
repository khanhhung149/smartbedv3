import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'models/threshold_out.dart';
import 'threshold_form.dart';

// Thresholds tab content — form + save error display.
// Rendered by AlertsScreen when selectedTab == 0.
class AlertsThresholdsTab extends StatelessWidget {
  const AlertsThresholdsTab({
    super.key,
    required this.thresholdsAsync,
    required this.onChanged,
    this.saveError,
  });

  final AsyncValue<ThresholdOut> thresholdsAsync;
  final ValueChanged<ThresholdOut> onChanged;
  final String? saveError;

  @override
  Widget build(BuildContext context) {
    return thresholdsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(
              color: AppColors.primaryContainer, strokeWidth: 2)),
      error: (e, _) => Center(
          child: Text('Failed to load thresholds: $e',
              style: GoogleFonts.inter(color: AppColors.error))),
      data: (thresholds) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alerts fire when vitals stay outside these ranges for over a minute.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            ThresholdForm(initial: thresholds, onChanged: onChanged),
            if (saveError != null) ...[
              const SizedBox(height: 12),
              Text(saveError!,
                  style: GoogleFonts.inter(
                      color: AppColors.error, fontSize: AppTextSize.sm)),
            ],
          ],
        ),
      ),
    );
  }
}
