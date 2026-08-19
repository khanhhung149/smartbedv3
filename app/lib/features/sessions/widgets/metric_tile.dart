import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';

/// One labelled number, shared by the night card and the detail header.
///
/// `value == null` renders an em dash, never a zero. The two mean different
/// things — "we could not measure this" versus "this happened zero times" —
/// and collapsing them would report something the pad never observed.
///
/// The optional `icon` gives each metric a recognisable glyph and a tinted
/// colour, so a row of tiles can be scanned by shape, not read digit by digit.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.color,
  });

  final String label;
  final String? value;
  final String? unit;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurface;
    final missing = value == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: tint.withValues(alpha: 0.85)),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: missing
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                      : tint,
                ),
              ),
            ),
            if (unit != null && !missing) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Formatting helpers shared by every screen that shows a session.
class Fmt {
  const Fmt._();

  static String? num1(double? v) => v?.toStringAsFixed(1);

  static String? int0(num? v) => v?.round().toString();

  /// "7 giờ 11 phút" — reads as a night's length, not as a duration field.
  static String? duration(int? seconds) {
    if (seconds == null) return null;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '$m phút';
    return '$h giờ $m phút';
  }

  /// Compact duration for tight rows: "7g11" — only used where the full form
  /// would overflow (card range row at 360dp).
  static String? durationShort(int? seconds) {
    if (seconds == null) return null;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h == 0 ? '${m}p' : '${h}g${m.toString().padLeft(2, '0')}';
  }
}

/// Icons and colours wired to the same palette as the detail charts, so the
/// list screen and the chart screen cannot disagree about what a metric is.
abstract final class MetricIdentity {
  static const heart = (Icons.favorite_outline, MetricColors.heart);
  static const breath = (Icons.air, MetricColors.breath);
  static const movement = (Icons.directions_walk, MetricColors.movement);
  static const snore = (Icons.graphic_eq, MetricColors.snore);
  static const respDisorder = (Icons.airline_stops, MetricColors.respDisorder);
  static const sitUp = (Icons.airline_seat_recline_normal, MetricColors.sitUp);
  static const wake = (Icons.wb_twilight, MetricColors.wake);
}