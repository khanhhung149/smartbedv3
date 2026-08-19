import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../data/models/timeline_point.dart';

/// When the notable events happened, in reading order.
///
/// A chart shows shape; this answers "what time did I sit up". Only the codes
/// worth surfacing appear — `asleep` and `movement` fire almost every bucket and
/// would bury the rest.
class EventMarkers extends StatelessWidget {
  const EventMarkers({super.key, required this.points});

  final List<TimelinePoint> points;

  static const _shown = <SleepEvent, (IconData, Color)>{
    SleepEvent.sitUp: (Icons.airline_seat_recline_normal, MetricColors.sitUp),
    SleepEvent.awake: (Icons.wb_twilight, MetricColors.wake),
    SleepEvent.snore: (Icons.graphic_eq, MetricColors.snore),
    SleepEvent.weakBreathing: (Icons.air, MetricColors.respDisorder),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('HH:mm', 'vi');

    // Group by type so three wake-ups read as "3 lần tỉnh 01:12 · 03:40 · 05:05"
    // instead of a wall of identically-shaped chips.
    final marks = <SleepEvent, List<DateTime>>{};
    for (final p in points) {
      for (final e in p.events) {
        if (_shown.containsKey(e)) marks.putIfAbsent(e, () => []).add(p.t);
      }
    }
    if (marks.isEmpty) {
      return Text('Không ghi nhận sự kiện đáng chú ý',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in SleepEvent.values)
          if (marks.containsKey(e)) ...[
            _EventGroup(
              icon: _shown[e]!.$1,
              color: _shown[e]!.$2,
              label: e.label,
              times: marks[e]!.map(fmt.format).toList(),
            ),
            if (e != SleepEvent.values.last) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _EventGroup extends StatelessWidget {
  const _EventGroup({
    required this.icon,
    required this.color,
    required this.label,
    required this.times,
  });

  final IconData icon;
  final Color color;
  final String label;
  final List<String> times;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = times.length;
    final title = count > 1 ? '$label · $count lần' : '$label · 1 lần';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    for (final t in times)
                      Text(t, style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}