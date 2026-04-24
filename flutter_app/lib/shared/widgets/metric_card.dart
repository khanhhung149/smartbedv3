import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import 'sparkline.dart';

// Large primary metric card (HR or RR).
// Source: sleep_pad_home_final_sync/code.html lines ~145-187 (bento-style cards).
// Attributes:
//   - bg surface-container (#1C2025), rounded-lg (16px), p-6
//   - Icon in colored pill (p-2, bg color/10, rounded-full)
//   - Label: 12sp uppercase tracking-wider on-surface-variant
//   - Value: 60sp font-black tracking-tighter on-surface
//   - Unit: 18sp on-surface-variant font-medium
//   - Sparkline: h-12 opacity-70 at bottom
//   - Subtle radial blur glow top-right corner

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accentColor,
    required this.sparklineValues,
  });

  final String label;
  // null shows '--'
  final double? value;
  final String unit;
  final IconData icon;
  // #5EE7DF for HR, #D4BBFF for RR
  final Color accentColor;
  final List<double> sparklineValues;

  @override
  Widget build(BuildContext context) {
    // Compact layout: icon + label + value + unit on one row, sparkline below.
    // Saves ~80px per card vs the original bento layout — lets Home fit HR,
    // Respiration, Status, Movement + Snores all above the fold.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: accentColor, fill: 1),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                value != null
                    ? (value! % 1 == 0
                        ? value!.round().toString()
                        : value!.toStringAsFixed(1))
                    : '--',
                style: GoogleFonts.inter(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  height: 1.0,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (sparklineValues.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: Sparkline(values: sparklineValues, color: accentColor),
            ),
          ],
        ],
      ),
    );
  }
}
