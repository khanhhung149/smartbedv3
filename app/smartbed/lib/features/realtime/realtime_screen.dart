import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'realtime_models.dart';
import 'realtime_providers.dart';
import 'sparkline.dart';

/// Xem số trực tiếp từ sleep pad, cập nhật mỗi giây.
///
/// Bố cục theo app tham chiếu (`Sleep-Tech-AI/sleep-pad-ai`, `features/home`):
/// hero trạng thái → hai thẻ chính HR/RR kèm sparkline → lưới chỉ số phụ.
/// KHÔNG có ô movement/snores như bản gốc: hai số đó nằm trong khung theo phút
/// mà chế độ TAOSG của pad không phát, nên hiện ô rỗng sẽ là bịa chỗ trống.
class RealtimeScreen extends ConsumerStatefulWidget {
  const RealtimeScreen({super.key});

  @override
  ConsumerState<RealtimeScreen> createState() => _RealtimeScreenState();
}

class _RealtimeScreenState extends ConsumerState<RealtimeScreen> {
  static const _historyLen = 60;   // 60 mẫu ở 1Hz = một phút gần nhất
  final List<double> _hr = [];
  final List<double> _rr = [];
  DateTime? _lastPlotted;

  void _record(RealtimeSample s) {
    // Chỉ ghi khi mốc thời gian đổi — provider hỏi mỗi giây nhưng backend có thể
    // trả lại đúng mẫu cũ nếu pad chưa đẩy khung mới; vẽ lại nó sẽ làm sparkline
    // phẳng giả tạo.
    if (_lastPlotted == s.t) return;
    _lastPlotted = s.t;
    _hr.add((s.heartRate ?? 0).toDouble());
    _rr.add(s.respRate ?? 0);
    if (_hr.length > _historyLen) _hr.removeAt(0);
    if (_rr.length > _historyLen) _rr.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(realtimeSampleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Trực tiếp')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.cloud_off,
          text: 'Không đọc được backend.\n$e',
          onRetry: () => ref.invalidate(realtimeSampleProvider),
        ),
        data: (s) {
          if (s == null) {
            return const _Message(
              icon: Icons.hourglass_empty,
              text: 'Thiết bị chưa gửi mẫu nào.',
            );
          }
          _record(s);
          return _Body(sample: s, hr: _hr, rr: _rr);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.sample, required this.hr, required this.rr});
  final RealtimeSample sample;
  final List<double> hr, rr;

  @override
  Widget build(BuildContext context) {
    final stale = sample.isStale(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusHero(sample: sample, stale: stale),
        const SizedBox(height: 12),
        _MetricCard(
          label: 'NHỊP TIM',
          value: sample.heartRate?.toString(),
          unit: 'bpm',
          icon: Icons.favorite,
          series: hr,
        ),
        const SizedBox(height: 10),
        _MetricCard(
          label: 'NHỊP THỞ',
          value: sample.respRate?.toStringAsFixed(1),
          unit: 'rpm',
          icon: Icons.air,
          series: rr,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SmallMetric(label: 'SDATA', value: sample.sdata?.toString())),
            const SizedBox(width: 10),
            Expanded(child: _SmallMetric(label: 'PDATA', value: sample.pdata?.toString())),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Nhịp tim và nhịp thở chỉ ra số sau khoảng 25 giây nằm yên liên tục — '
          'hiện “—” hoặc 0 trước đó là đúng, không phải lỗi đọc.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.sample, required this.stale});
  final RealtimeSample sample;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = sample.t;
    String two(int v) => v.toString().padLeft(2, '0');
    return Card(
      color: stale
          ? scheme.errorContainer
          : (sample.onBed ? scheme.primaryContainer : scheme.surfaceContainerHighest),
      child: ListTile(
        leading: Icon(stale ? Icons.signal_wifi_off : Icons.bed, size: 32),
        title: Text(stale ? 'Mất tín hiệu' : sample.statusLabel,
            style: Theme.of(context).textTheme.headlineSmall),
        subtitle: Text('Mẫu lúc ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.series,
  });
  final String label, unit;
  final String? value;
  final IconData icon;
  final List<double> series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Text(value ?? '—', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(width: 6),
              Text(unit, style: Theme.of(context).textTheme.bodyMedium),
            ]),
            const SizedBox(height: 8),
            Sparkline(values: series, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Text(value ?? '—', style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
              ],
            ],
          ),
        ),
      );
}
