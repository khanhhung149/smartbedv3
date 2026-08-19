import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../data/models/timeline_point.dart';

/// A strip showing occupancy across the night, on the same X axis as the charts.
///
/// Three states, not two: on bed, off bed, and no data. Painting a dropout the
/// same colour as "off bed" would assert the bed was empty when nothing was
/// recorded at all.
class BedStateBand extends StatelessWidget {
  const BedStateBand({super.key, required this.points});

  final List<TimelinePoint> points;

  /// Buckets further apart than this had no data between them.
  static const Duration _gapThreshold = Duration(minutes: 3);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) return const SizedBox.shrink();

    final onColor = MetricColors.onBed;
    final offColor = theme.colorScheme.surfaceContainerHighest;

    final cells = <Widget>[];
    DateTime? prev;
    for (final p in points) {
      if (prev != null && p.t.difference(prev).abs() > _gapThreshold) {
        cells.add(Expanded(
          flex: p.t.difference(prev).inMinutes.clamp(1, 10000),
          child: const _GapCell(),
        ));
      }
      cells.add(Expanded(
        flex: 1,
        child: Container(color: p.onBed ? onColor : offColor),
      ));
      prev = p.t;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bed_outlined, size: 14, color: onColor),
            const SizedBox(width: 5),
            Text('Trên giường', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(height: 20, child: Row(children: cells)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _Legend(color: onColor, label: 'Trên giường'),
            _Legend(color: offColor, label: 'Rời giường'),
            const _Legend(color: null, label: 'Không có dữ liệu'),
          ],
        ),
      ],
    );
  }
}

class _GapCell extends StatelessWidget {
  const _GapCell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.35),
        border: Border.symmetric(
          vertical: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color? color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: color == null
                ? Border.all(color: theme.dividerColor, width: 1)
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style:
                theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
      ],
    );
  }
}
