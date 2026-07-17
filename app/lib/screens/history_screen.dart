import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử')),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(eventsProvider),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        data: (events) {
          if (events.isEmpty) {
            return const Center(child: Text('Chưa có sự kiện nào'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(eventsProvider),
            child: ListView.separated(
              itemCount: events.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _EventTile(event: events[i]),
            ),
          );
        },
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
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(event.source),
      trailing: Text(
        _when(event),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// Dịch (kind, value) thô của backend sang câu tiếng Việt + icon/màu.
  static (IconData, Color, String) _present(Event e) {
    switch (e.kind) {
      case Event.kindMotion:
        return (Icons.directions_walk, Colors.orange, 'Có chuyển động');
      case Event.kindPresence:
        return e.isPositive
            ? (Icons.person, Colors.green, 'Radar thấy người')
            : (Icons.person_outline, Colors.blueGrey, 'Radar hết thấy');
      case Event.kindAcCmd:
        return e.isPositive
            ? (Icons.ac_unit, Colors.lightBlue, 'Bật điều hoà')
            : (Icons.power_off, Colors.blueGrey, 'Tắt điều hoà');
      default:
        return (Icons.help_outline, Colors.grey, '${e.kind}: ${e.value}');
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
