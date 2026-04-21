import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../data/models/realtime_data.dart';

// 2×2 grid of secondary metric tiles: S-Data, P-Data, Movement, Snores.
// Source: sleep_pad_home_final_sync/code.html lines ~190-221 (secondary metrics grid).
// Attributes:
//   - bg surface-container-low (#181C21), rounded-[20px], p-5
//   - Label: 12sp uppercase tracking-wider on-surface-variant
//   - Value: 24sp font-bold on-surface
//   - Trend icon: outline color, text-sm (16sp)

class HomeSecondaryMetrics extends StatelessWidget {
  const HomeSecondaryMetrics({super.key, required this.data});

  final RealtimeData? data;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: [
        _SecondaryTile(
          label: 'S-Data',
          value: data?.sdata != null
              ? '${data!.sdata!.toStringAsFixed(0)}%'
              : '--',
          trendIcon: Symbols.trending_up,
        ),
        _SecondaryTile(
          label: 'P-Data',
          value: data?.pdata != null
              ? '${data!.pdata!.toStringAsFixed(1)}v'
              : '--',
          trendIcon: Symbols.trending_flat,
        ),
        _SecondaryTile(
          label: 'Movement',
          value: _movementLabel(data?.movement),
        ),
        _SecondaryTile(
          label: 'Snores',
          value: data?.snore?.toString() ?? '0',
        ),
      ],
    );
  }

  String _movementLabel(int? movement) {
    if (movement == null) return '--';
    if (movement < 20) return 'Low';
    if (movement < 60) return 'Medium';
    return 'High';
  }
}

class _SecondaryTile extends StatelessWidget {
  const _SecondaryTile({
    required this.label,
    required this.value,
    this.trendIcon,
  });

  final String label;
  final String value;
  final IconData? trendIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow, // #181C21
        borderRadius: BorderRadius.circular(20), // rounded-[20px]
      ),
      padding: const EdgeInsets.all(20), // p-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              ),
              if (trendIcon != null)
                Icon(
                  trendIcon,
                  size: 16,
                  color: AppColors.outline,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
