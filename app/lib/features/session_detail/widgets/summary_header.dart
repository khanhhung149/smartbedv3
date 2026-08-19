import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/sleep_session.dart';
import '../../sessions/widgets/metric_tile.dart';

/// The same numbers as the night card, reusing the same tile widget so the two
/// screens cannot drift in how a null or a unit is rendered.
///
/// The top row is the headline: duration, then the time the pad thinks the
/// person was in bed. Below it a heart-rate strip draws min → avg → max as a
/// range, which is how a reader actually wants to absorb that data — as a band,
/// not three floating numbers.
class SummaryHeader extends StatelessWidget {
  const SummaryHeader({super.key, required this.session});

  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat('HH:mm', 'vi');
    final end = session.endedAt;
    final range = end == null
        ? '${timeFmt.format(session.startedAt)} – đang diễn ra'
        : '${timeFmt.format(session.startedAt)} – ${timeFmt.format(end)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Thời gian nằm trên giường',
                          style: theme.textTheme.labelMedium),
                      const SizedBox(height: 2),
                      Text(
                        range,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Fmt.duration(session.durationS) ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (session.hrAvg != null)
                        Text('nhịp tim TB ${Fmt.int0(session.hrAvg)} bpm',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.hintColor,
                            )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _HeartRateStrip(session: session),
            const Divider(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                MetricTile(
                  label: 'Thấp nhất',
                  value: Fmt.int0(session.hrMin),
                  unit: 'bpm',
                  icon: MetricIdentity.heart.$1,
                  color: MetricIdentity.heart.$2,
                ),
                MetricTile(
                  label: 'Cao nhất',
                  value: Fmt.int0(session.hrMax),
                  unit: 'bpm',
                  icon: MetricIdentity.heart.$1,
                  color: MetricIdentity.heart.$2,
                ),
                MetricTile(
                  label: 'Nhịp thở TB',
                  value: Fmt.num1(session.rrAvg),
                  unit: 'lần/phút',
                  icon: MetricIdentity.breath.$1,
                  color: MetricIdentity.breath.$2,
                ),
                MetricTile(
                  label: 'Trở mình',
                  value: Fmt.int0(session.movementTotal),
                  icon: MetricIdentity.movement.$1,
                  color: MetricIdentity.movement.$2,
                ),
                MetricTile(
                  label: 'Ngáy',
                  value: Fmt.int0(session.snoreTotal),
                  icon: MetricIdentity.snore.$1,
                  color: MetricIdentity.snore.$2,
                ),
                MetricTile(
                  label: 'Rối loạn hô hấp',
                  value: Fmt.int0(session.respDisorderTotal),
                  icon: MetricIdentity.respDisorder.$1,
                  color: MetricIdentity.respDisorder.$2,
                ),
                MetricTile(
                  label: 'Ngồi dậy',
                  value: Fmt.int0(session.sitUpCount),
                  icon: MetricIdentity.sitUp.$1,
                  color: MetricIdentity.sitUp.$2,
                ),
                MetricTile(
                  label: 'Tỉnh giấc',
                  value: Fmt.int0(session.wakeCount),
                  icon: MetricIdentity.wake.$1,
                  color: MetricIdentity.wake.$2,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Heart rate as a band: the grey track is the full possible range, the tinted
/// fill is this night's min→max, and the tick is the average. Reading a night
/// this way shows volatility at a glance — a flat narrow band versus one that
/// swings across half the track.
class _HeartRateStrip extends StatelessWidget {
  const _HeartRateStrip({required this.session});

  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final min = session.hrMin;
    final max = session.hrMax;
    final avg = session.hrAvg;

    if (min == null || max == null || avg == null || max <= min) {
      return const SizedBox.shrink();
    }

    final lo = min.toDouble();
    final hi = max.toDouble();
    final low = lo - (hi - lo) * 0.4;
    final high = hi + (hi - lo) * 0.4;
    final span = high - low;
    final minFrac = ((lo - low) / span).clamp(0.0, 1.0);
    final maxFrac = ((hi - low) / span).clamp(0.0, 1.0);
    final avgFrac = ((avg - low) / span).clamp(0.0, 1.0);

    final heart = MetricIdentity.heart.$2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Nhịp tim trong đêm',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium),
            ),
            const SizedBox(width: 8),
            Text('${Fmt.int0(min)} – ${Fmt.int0(max)} bpm',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: heart.withValues(alpha: 0.9),
                )),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackW = constraints.maxWidth;
                final fillW = (maxFrac - minFrac) * trackW;
                return Stack(
                  children: [
                    // Full possible range (track).
                    Container(color: theme.colorScheme.surfaceContainerHigh),
                    // This night's observed range (fill), inset to min→max.
                    Positioned(
                      left: minFrac * trackW,
                      width: fillW.clamp(0.0, trackW),
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              heart.withValues(alpha: 0.25),
                              heart.withValues(alpha: 0.65),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Average tick, positioned on the full track.
                    Positioned(
                      left: avgFrac * trackW - 1.5,
                      top: -2,
                      bottom: -2,
                      child: Container(width: 3, color: heart),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}