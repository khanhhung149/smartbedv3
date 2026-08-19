import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../providers.dart';
import '../theme.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(radarEventsProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(radarEventsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            Text('Lịch sử', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Mọi sự kiện cảm biến ghi lại',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            eventsAsync.when(
              loading: () => const AppCard(
                child: SizedBox(
                    height: 160, child: Center(child: CircularProgressIndicator())),
              ),
              error: (e, _) => AppCard(
                child: Column(children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 44, color: RadarTheme.inkSoft),
                  const SizedBox(height: 10),
                  Text('$e', textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton(
                      onPressed: () => ref.invalidate(radarEventsProvider),
                      child: const Text('Thử lại')),
                ]),
              ),
              data: (events) {
                if (events.isEmpty) {
                  return const AppCard(
                    child: SizedBox(
                      height: 140,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_rounded,
                                size: 36, color: RadarTheme.inkSoft),
                            SizedBox(height: 10),
                            Text('Chưa có sự kiện nào',
                                style: TextStyle(color: RadarTheme.inkSoft)),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (var i = 0; i < events.length; i++) ...[
                        _EventTile(event: events[i]),
                        if (i != events.length - 1)
                          Divider(
                              height: 1,
                              indent: 68,
                              color: Colors.black.withValues(alpha: 0.05)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Event event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _present(event);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: RadarTheme.ink)),
                const SizedBox(height: 1),
                Text(event.source,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(_when(event), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Dịch (kind, value) thô của backend sang câu tiếng Việt + icon/màu.
  static (IconData, Color, String) _present(Event e) {
    switch (e.kind) {
      case Event.kindMotion:
        return (Icons.directions_walk_rounded, RadarTheme.amber, 'Có chuyển động');
      case Event.kindPresence:
        return e.isPositive
            ? (Icons.person_rounded, RadarTheme.green, 'Radar thấy người')
            : (Icons.person_outline_rounded, RadarTheme.inkSoft, 'Radar hết thấy');
      case Event.kindAcCmd:
        return e.isPositive
            ? (Icons.ac_unit_rounded, RadarTheme.blue, 'Bật điều hoà')
            : (Icons.power_settings_new_rounded, RadarTheme.inkSoft, 'Tắt điều hoà');
      default:
        return (Icons.help_outline_rounded, RadarTheme.inkSoft, '${e.kind}: ${e.value}');
    }
  }

  /// ts=0 = message retained publish trước khi NTP sync → không có giờ thật.
  /// Hiện "không rõ giờ" thay vì format ra 1970 (sai và khó hiểu).
  static String _when(Event e) {
    final t = e.time;
    if (t == null) return 'không rõ giờ';
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay
        ? DateFormat('HH:mm:ss').format(t)
        : DateFormat('dd/MM HH:mm').format(t);
  }
}
