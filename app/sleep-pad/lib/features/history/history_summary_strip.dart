import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../data/models/history_response.dart';

// Summary strip: 3 mini-stat tiles (Avg HR, Avg RR, Disturbances) with trend badges.
// Source: sleep_history_synced/code.html lines ~125-147.
// Attributes:
//   - bg surface-container-low (#181C21), rounded-DEFAULT (20px), p-4
//   - border outline-variant/15
//   - Label: 12sp #8B96A5 uppercase tracking-wider
//   - Value: 24sp font-bold on-background
//   - Trend badge: 12sp, emerald bg/10 or secondary bg/10, px-2 py-1 rounded-full

class HistorySummaryStrip extends StatelessWidget {
  const HistorySummaryStrip({
    super.key,
    required this.data,
  });

  final HistoryResponse data;

  @override
  Widget build(BuildContext context) {
    final avgHr = data.avgHr;
    final avgRr = data.avgRr;
    final disturbances = data.totalDisturbances;

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Avg HR',
            value: avgHr != null ? '${avgHr.round()}' : '--',
            unit: 'bpm',
            // Trend badge: static placeholder — backend doesn't return % delta yet
            trendText: null,
            trendPositive: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Avg RR',
            value: avgRr != null ? '${avgRr.round()}' : '--',
            unit: 'brpm',
            trendText: null,
            trendPositive: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Disturbances',
            value: '$disturbances',
            unit: null,
            trendText: null,
            trendPositive: true,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.trendText,
    required this.trendPositive,
  });

  final String label;
  final String value;
  final String? unit;
  // null = hide trend badge (server doesn't provide delta yet)
  final String? trendText;
  final bool trendPositive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20), // rounded-DEFAULT per history HTML
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF8B96A5),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onBackground,
                          height: 1.1,
                        ),
                      ),
                      if (unit != null)
                        TextSpan(
                          text: ' $unit',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF8B96A5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (trendText != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: trendPositive
                        ? const Color(0xFF34D399).withValues(alpha: 0.10)
                        : AppColors.secondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trendText!,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: trendPositive
                          ? const Color(0xFF34D399)
                          : AppColors.secondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
