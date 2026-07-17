import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/snapshot.dart';
import '../providers.dart';
import '../services/api_client.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(snapshotProvider);
    final wsUp = ref.watch(wsConnectedProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phòng ngủ'),
        actions: [_ConnectionDot(connected: wsUp)],
      ),
      body: snapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(snapshotProvider),
        ),
        data: (snap) => _HomeBody(snap: snap),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  final Snapshot snap;
  const _HomeBody({required this.snap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(snapshotProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OccupancyCard(snap: snap),
          const SizedBox(height: 16),
          _AcCard(snap: snap),
          const SizedBox(height: 16),
          _DetailCard(snap: snap),
        ],
      ),
    );
  }
}

/// Thẻ chính: phòng có người hay không (theo backend fusion, không phải radar thô).
class _OccupancyCard extends StatelessWidget {
  final Snapshot snap;
  const _OccupancyCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    final occupied = snap.occupied;
    final color = occupied ? Colors.green : Colors.blueGrey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(occupied ? Icons.person : Icons.person_outline,
                size: 72, color: color),
            const SizedBox(height: 12),
            Text(
              occupied ? 'Có người' : 'Phòng trống',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // present = radar thô lúc này; occupied = kết luận của backend. Hiện cả hai
            // để khi lệch nhau còn biết đường debug (radar thấy nhưng chưa có motion).
            Text(
              snap.present ? 'Radar đang thấy người' : 'Radar không thấy ai',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AcCard extends ConsumerStatefulWidget {
  final Snapshot snap;
  const _AcCard({required this.snap});

  @override
  ConsumerState<_AcCard> createState() => _AcCardState();
}

class _AcCardState extends ConsumerState<_AcCard> {
  bool _busy = false;

  Future<void> _send(bool on) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setAc(on);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã gửi lệnh ${on ? "bật" : "tắt"} điều hoà')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.snap.acDesired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.ac_unit,
                    color: on ? Colors.lightBlue : Colors.blueGrey),
                const SizedBox(width: 8),
                Text('Điều hoà', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(on ? 'ĐANG BẬT' : 'ĐANG TẮT',
                    style: TextStyle(
                        color: on ? Colors.lightBlue : Colors.blueGrey,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _send(true),
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Bật'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _send(false),
                    icon: const Icon(Icons.power_off),
                    label: const Text('Tắt'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Lệnh tay có thể bị ghi đè khi phòng đổi trạng thái.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final Snapshot snap;
  const _DetailCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          _row('Lệnh AC gần nhất',
              snap.lastAcCmd.isEmpty ? '—' : snap.lastAcCmd),
          _row('Chuyển động gần nhất', _ago(snap.lastMotionTs)),
          _row('Radar cập nhật', _ago(snap.lastPresenceTs)),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => ListTile(
        dense: true,
        title: Text(k),
        trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
      );

  /// ts=0 nghĩa là thiết bị publish trước khi NTP sync → không có giờ thật,
  /// hiện "chưa có" chứ không format ra 1970.
  static String _ago(int ts) {
    if (ts <= 0) return 'chưa có';
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
    if (d.isNegative) return 'vừa xong';
    if (d.inSeconds < 60) return '${d.inSeconds}s trước';
    if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
    if (d.inHours < 24) return '${d.inHours} giờ trước';
    return '${d.inDays} ngày trước';
  }
}

class _ConnectionDot extends StatelessWidget {
  final bool connected;
  const _ConnectionDot({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 10, color: connected ? Colors.green : Colors.grey),
          const SizedBox(width: 6),
          Text(connected ? 'Trực tiếp' : 'Mất kết nối',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
