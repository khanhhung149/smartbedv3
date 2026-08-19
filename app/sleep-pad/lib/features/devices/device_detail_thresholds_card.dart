import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Alert thresholds preview card shown on device detail screen.
// Receives pre-fetched AsyncValue; edit CTA navigates to /alerts.

class DeviceDetailThresholdsCard extends StatelessWidget {
  const DeviceDetailThresholdsCard({
    super.key,
    required this.thresholdsAsync,
    required this.onEdit,
  });

  // AsyncValue<ThresholdOut> — typed as dynamic to avoid cross-feature import.
  final AsyncValue thresholdsAsync;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Alert Thresholds',
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.lg,
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.onSurface)),
            GestureDetector(
              onTap: onEdit,
              child: Text('Edit',
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      fontWeight: AppFontWeight.medium,
                      color: AppColors.primaryContainer)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: AppRadius.defaultBr,
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monitor_heart_outlined,
                  color: AppColors.primaryContainer, size: 22),
            ),
            const SizedBox(width: 16),
            thresholdsAsync.when(
              loading: () => Text('Loading…',
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      color: AppColors.onSurfaceVariant)),
              error: (_, __) => Text('Unavailable',
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      color: AppColors.onSurfaceVariant)),
              data: (t) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HR: ${t.hrLow.round()}–${t.hrHigh.round()} bpm  ·  '
                    'RR: ${t.rrLow.round()}–${t.rrHigh.round()} brpm',
                    style: GoogleFonts.inter(
                        fontSize: AppTextSize.base,
                        color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text('Active notifications enabled',
                      style: GoogleFonts.inter(
                          fontSize: AppTextSize.sm,
                          color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
