import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/timeline_point.dart';
import '../sessions/sessions_providers.dart';
import '../sessions/widgets/disclaimer_footer.dart';
import '../sessions/widgets/empty_state.dart';
import '../sessions/widgets/metric_tile.dart';
import '../sessions/widgets/stale_data_banner.dart';
import 'session_detail_providers.dart';
import 'widgets/bed_state_band.dart';
import 'widgets/event_markers.dart';
import 'widgets/summary_header.dart';
import 'widgets/timeline_chart.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionByIdProvider(sessionId));
    final timeline = ref.watch(timelineProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          session.valueOrNull == null
              ? 'Chi tiết đêm'
              : 'Đêm ${DateFormat('dd/MM', 'vi').format(session.value!.startedAt)}',
        ),
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          if (s == null) {
            return const EmptyState(title: 'Không tìm thấy phiên này');
          }
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              timeline.maybeWhen(
                data: (r) => r.isStale
                    ? const StaleDataBanner()
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SummaryHeader(session: s),
              ),
              const SizedBox(height: 20),
              timeline.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyState(title: 'Không đọc được diễn biến', detail: '$e'),
                ),
                data: (r) => r.items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: EmptyState(
                          title: 'Chưa có diễn biến cho đêm này',
                          detail: 'Phiên có tóm tắt nhưng chưa có dữ liệu theo phút.',
                        ),
                      )
                    : _Timeline(points: r.items),
              ),
              const DisclaimerFooter(),
            ],
          );
        },
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.points});

  final List<TimelinePoint> points;

  @override
  Widget build(BuildContext context) {
    // The layer list is the extension point: presence or room temperature is a
    // new entry here, not a change to TimelineChart.
    final layers = [
      ChartLayer(
        label: 'Nhịp tim',
        unit: 'bpm',
        value: (p) => p.hr,
        color: MetricIdentity.heart.$2,
        icon: MetricIdentity.heart.$1,
      ),
      ChartLayer(
        label: 'Nhịp thở',
        unit: 'lần/phút',
        value: (p) => p.rr,
        color: MetricIdentity.breath.$2,
        icon: MetricIdentity.breath.$1,
      ),
      ChartLayer(
        label: 'Cử động',
        unit: 'lần',
        value: (p) => p.movement?.toDouble(),
        color: MetricIdentity.movement.$2,
        icon: MetricIdentity.movement.$1,
        asBars: true,
        height: 70,
      ),
      ChartLayer(
        label: 'Ngáy',
        unit: 'lần',
        value: (p) => p.snore?.toDouble(),
        color: MetricIdentity.snore.$2,
        icon: MetricIdentity.snore.$1,
        asBars: true,
        height: 70,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text('Diễn biến trong đêm',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Chạm vào biểu đồ để xem giá trị theo giờ',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // The chart scrolls inside this box. The page must never scroll
          // sideways, which is what the 360dp acceptance criterion checks.
          TimelineChart(
            points: points,
            layers: layers,
            bedStateBand: BedStateBand(points: points),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Sự kiện',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          EventMarkers(points: points),
        ],
      ),
    );
  }
}
