import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/primary_button.dart';
import 'models/alert_out.dart';
import '../../l10n/app_localizations.dart';

// Alert detail screen — accessed via push-notification deep link or history row tap.
// Source: alert_detail/code.html
// Route: /alerts/:deviceId/detail (AlertOut passed as extra)
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.alert});

  final AlertOut alert;

  @override
  Widget build(BuildContext context) {
    final bannerColor = _bannerColor(alert.severity);
    final bannerBorderColor = bannerColor.withValues(alpha: 0.3);
    final iconBg = _iconBg(alert.severity);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTap: (i) => _handleNavTap(context, i),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 100, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero banner
            _HeroBanner(
              alert: alert,
              bannerColor: bannerColor,
              bannerBorderColor: bannerBorderColor,
              iconBg: iconBg,
            ),
            const SizedBox(height: 24),
            // Info grid
            _InfoGrid(alert: alert),
            const SizedBox(height: 24),
            // Chart section (abstract spike representation)
            _ChartSection(alert: alert),
            const SizedBox(height: 32),
            // CTA buttons
            PrimaryButton(
              label: 'View in History',
              onPressed: () => context.go('/alerts'),
            ),
            const SizedBox(height: 12),
            _SecondaryButton(
              label: 'Adjust threshold',
              onPressed: () => context.go('/alerts'),
            ),
          ],
        ),
      ),
    );
  }

  Color _bannerColor(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.high:
        return AppColors.errorContainer; // #93000a tinted
      case AlertSeverity.low:
        return AppColors.tertiaryContainer.withValues(alpha: 0.2);
      case AlertSeverity.disturbance:
        return AppColors.errorContainer;
    }
  }

  Color _iconBg(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.high:
      case AlertSeverity.disturbance:
        return AppColors.errorContainer;
      case AlertSeverity.low:
        return AppColors.tertiaryContainer;
    }
  }

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/history');
      case 2:
        context.go('/alerts');
      case 3:
        context.go('/devices');
      case 4:
        context.go('/settings');
    }
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(BuildContext context) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          color: const Color(0xB3101419),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Symbols.arrow_back,
                      color: AppColors.primaryContainer, size: 24),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/alerts');
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.alertDetail,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.lg,
                      fontWeight: AppFontWeight.semiBold,
                      color: AppColors.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 48), // balance back button
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Hero banner ───────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.alert,
    required this.bannerColor,
    required this.bannerBorderColor,
    required this.iconBg,
  });

  final AlertOut alert;
  final Color bannerColor;
  final Color bannerBorderColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    // rounded-xl bg-error-container/20 border border-error-container/30 p-6
    return Container(
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.defaultRadius + 4),
        border: Border.all(color: bannerBorderColor),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: const Icon(Symbols.warning,
                color: AppColors.onErrorContainer, size: 36, fill: 1),
          ),
          const SizedBox(height: 16),
          Text(
            alert.label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.xl2,
              fontWeight: AppFontWeight.bold,
              color: AppColors.error,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${alert.value.round()} ${alert.unit} for 1 minute, threshold ${alert.threshold.round()}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info grid ─────────────────────────────────────────────────────────────────

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.alert});
  final AlertOut alert;

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(alert.triggeredAt);
    return Row(
      children: [
        Expanded(child: _InfoCell(label: 'TIME', value: timeStr)),
        const SizedBox(width: 16),
        Expanded(
            child: _InfoCell(
                label: 'DEVICE', value: alert.deviceId.toUpperCase())),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    final prefix = isToday ? 'Today' : 'Yesterday';
    return '$prefix, $h:$m $amPm';
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xs,
                fontWeight: AppFontWeight.medium,
                color: AppColors.onSurfaceVariant,
                letterSpacing: 1,
              )),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                fontWeight: AppFontWeight.medium,
                color: AppColors.onSurface,
              )),
        ],
      ),
    );
  }
}

// ── Chart section ─────────────────────────────────────────────────────────────

class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.alert});
  final AlertOut alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.defaultRadius + 4),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What happened',
              style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 24),
          // Abstract SVG-style spike chart drawn with CustomPaint
          SizedBox(
            height: 192,
            child: CustomPaint(painter: _SpikePainter(alert: alert)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatOffsetTime(alert.triggeredAt, -5),
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.xs,
                      color: AppColors.onSurfaceVariant)),
              Text(_formatOffsetTime(alert.triggeredAt, 5),
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.xs,
                      color: AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatOffsetTime(DateTime base, int offsetMinutes) {
    final t = base.add(Duration(minutes: offsetMinutes));
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final amPm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $amPm';
  }
}

// Draws an abstract heart-rate spike chart matching alert_detail HTML SVG.
class _SpikePainter extends CustomPainter {
  const _SpikePainter({required this.alert});
  final AlertOut alert;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background container
    final bgPaint = Paint()..color = AppColors.surfaceContainer;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
      bgPaint,
    );

    // Grid lines (4 horizontal, opacity 10%)
    final gridPaint = Paint()
      ..color = AppColors.onSurface.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (int i = 1; i <= 4; i++) {
      final y = h * i / 5;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Threshold dashed line at 1/3 height
    final threshY = h / 3;
    final dashPaint = Paint()
      ..color = AppColors.error.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    _drawDashedLine(canvas, Offset(0, threshY), Offset(w, threshY), dashPaint);

    // Threshold label
    // (skipped for brevity — threshold text shown in hero banner)

    // Spike path matching HTML: M 0,40 L 20,42 L 40,38 L 50,10 L 60,35 L 80,39 L 100,40
    // Normalized to canvas size
    final points = [
      Offset(0, h * 40 / 50),
      Offset(w * 0.2, h * 42 / 50),
      Offset(w * 0.4, h * 38 / 50),
      Offset(w * 0.5, h * 10 / 50),
      Offset(w * 0.6, h * 35 / 50),
      Offset(w * 0.8, h * 39 / 50),
      Offset(w, h * 40 / 50),
    ];

    // Fill gradient under line
    final fillPath = Path()..moveTo(0, h);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(w, h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.error.withValues(alpha: 0.15),
          AppColors.error.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = AppColors.error
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(linePath, linePaint);
  }

  void _drawDashedLine(
      Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 8.0;
    const dashSpace = 6.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = (dx * dx + dy * dy);
    if (len == 0) return;
    final uDx = dx / len;
    final uDy = dy / len;
    double dist = 0;
    bool drawing = true;
    double x = start.dx;
    double y = start.dy;
    final total = dx.abs();
    while (dist < total) {
      final step = drawing ? dashWidth : dashSpace;
      final nextDist = (dist + step).clamp(0.0, total);
      if (drawing) {
        canvas.drawLine(
          Offset(x, y),
          Offset(start.dx + uDx * nextDist * total,
              start.dy + uDy * nextDist * total),
          paint,
        );
      }
      x = start.dx + (nextDist / total) * dx;
      y = start.dy + (nextDist / total) * dy;
      dist = nextDist;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(_SpikePainter old) => old.alert.id != alert.id;
}

// ── Secondary outline button ──────────────────────────────────────────────────

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.outline.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full)),
          foregroundColor: AppColors.onSurface,
        ),
        child: Text(label,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.base,
              fontWeight: AppFontWeight.medium,
              color: AppColors.onSurface,
            )),
      ),
    );
  }
}
