import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../l10n/app_localizations.dart';
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
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 3.0,
      // Order (user request 2026-04-24): Movement + Snores first so they sit
      // right after the Respiration card, then S-Data + P-Data.
      children: [
        _SecondaryTile(
          // Protocol defines body_motion as "number of body movements per
          // minute" (count), not an intensity level — show the raw count.
          label: AppLocalizations.of(context)!.movement,
          value: data?.movement?.toString() ?? '0',
        ),
        _SecondaryTile(
          label: AppLocalizations.of(context)!.snores,
          value: data?.snore?.toString() ?? '0',
        ),
        _SecondaryTile(
          label: AppLocalizations.of(context)!.sData,
          value: data?.sdata != null
              ? '${data!.sdata!.toStringAsFixed(0)}%'
              : '--',
          trendIcon: Symbols.trending_up,
        ),
        _SecondaryTile(
          label: AppLocalizations.of(context)!.pData,
          value: data?.pdata != null
              ? '${data!.pdata!.toStringAsFixed(1)}v'
              : '--',
          trendIcon: Symbols.trending_flat,
        ),
      ],
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.0,
            ),
          ),
          if (trendIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trendIcon, size: 14, color: AppColors.outline),
          ],
        ],
      ),
    );
  }
}
