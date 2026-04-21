import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'models/alert_out.dart';

// Alert history list widget.
// Source: alerts_history_dark_mode_fix/code.html — history list section.
// Each row: colored dot + metric label + value/limit subtitle + relative time.
// Empty state: centered checkmark + caption text.
class AlertHistoryList extends StatelessWidget {
  const AlertHistoryList({super.key, required this.alerts});

  final List<AlertOut> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const _EmptyState();
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _AlertRow(
        alert: alerts[i],
        onTap: () => context.push('/alerts/${alerts[i].deviceId}/detail',
            extra: alerts[i]),
      ),
    );
  }
}

// ── Single alert row ──────────────────────────────────────────────────────────

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.onTap});

  final AlertOut alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dotColor = _dotColor(alert.severity);
    final shadowColor = dotColor.withValues(alpha: 0.3);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        // bg-[#121821] rounded-[20px] p-5
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored dot
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Label + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.label,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.base,
                      fontWeight: AppFontWeight.semiBold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${alert.value.round()} ${alert.unit}  •  limit ${alert.threshold.round()}',
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Relative time
            Text(
              _relativeTime(alert.triggeredAt),
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xs,
                fontWeight: AppFontWeight.medium,
                color: AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _dotColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.high:
        return AppColors.error; // coral #ffb4ab
      case AlertSeverity.low:
        return AppColors.tertiaryFixed; // amber #ffdea5
      case AlertSeverity.disturbance:
        return AppColors.errorContainer; // red #93000a
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // Source: alerts_history_empty_state/code.html
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Symbols.check_circle,
                size: 40,
                color: AppColors.primaryContainer,
                fill: 1,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No alerts yet.',
              style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "That's good news.",
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
