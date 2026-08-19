import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/sleep_session.dart';
import 'metric_tile.dart';

/// One night, ordered by what someone waking up actually wants to know:
/// which night, how long, then the numbers.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.session, this.onTap});

  final SleepSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayFmt = DateFormat('dd/MM', 'vi');
    final timeFmt = DateFormat('HH:mm', 'vi');
    final start = session.startedAt;
    final end = session.endedAt;

    final title = end == null
        ? 'Đêm ${dayFmt.format(start)}'
        : 'Đêm ${dayFmt.format(start)} → ${dayFmt.format(end)}';
    final range = end == null
        ? '${timeFmt.format(start)} – đang diễn ra'
        : '${timeFmt.format(start)} – ${timeFmt.format(end)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // The duration sits on a tinted pill so the eye lands on it
                  // first — it is the headline number of a night.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      Fmt.durationShort(session.durationS) ?? '—',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      range,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const Divider(height: 20),
              // Two columns keep tiles readable at 360dp where a single row of
              // five would force every label to truncate.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MetricTile(
                          label: 'Nhịp tim TB',
                          value: Fmt.int0(session.hrAvg),
                          unit: 'bpm',
                          icon: MetricIdentity.heart.$1,
                          color: MetricIdentity.heart.$2,
                        ),
                        const SizedBox(height: 14),
                        MetricTile(
                          label: 'Trở mình',
                          value: Fmt.int0(session.movementTotal),
                          icon: MetricIdentity.movement.$1,
                          color: MetricIdentity.movement.$2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MetricTile(
                          label: 'Nhịp thở TB',
                          value: Fmt.num1(session.rrAvg),
                          unit: 'lần/phút',
                          icon: MetricIdentity.breath.$1,
                          color: MetricIdentity.breath.$2,
                        ),
                        const SizedBox(height: 14),
                        MetricTile(
                          label: 'Ngáy',
                          value: Fmt.int0(session.snoreTotal),
                          icon: MetricIdentity.snore.$1,
                          color: MetricIdentity.snore.$2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}