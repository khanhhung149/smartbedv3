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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer, // #1C2025
        borderRadius: BorderRadius.circular(16), // rounded-lg
      ),
      padding: const EdgeInsets.all(24), // p-6
      child: Stack(
        children: [
          // Subtle glow: absolute -right-6 -top-6 w-32 h-32 bg-color/5 blur-3xl
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.05),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row: icon pill + label + more_horiz (HR only via moreIcon)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icon pill: p-2 bg-color/10 rounded-full
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: accentColor,
                          fill: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const Icon(
                    Symbols.more_horiz,
                    size: 20,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 24), // mb-6
              // Value + unit baseline row
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value != null ? value!.round().toString() : '--',
                    style: GoogleFonts.inter(
                      fontSize: 60, // text-6xl
                      fontWeight: FontWeight.w900, // font-black
                      color: AppColors.onSurface,
                      height: 1.0,
                      letterSpacing: -2.0, // tracking-tighter
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    unit,
                    style: GoogleFonts.inter(
                      fontSize: 18, // text-lg
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16), // mt-4
              // Sparkline
              Sparkline(
                values: sparklineValues,
                color: accentColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
