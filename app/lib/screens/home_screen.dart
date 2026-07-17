import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/snapshot.dart';
import '../models/stats.dart';
import '../providers.dart';
import '../services/api_client.dart';
import '../theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(snapshotProvider);
    final wsUp = ref.watch(wsConnectedProvider).value ?? false;
    final statsAsync = ref.watch(statsProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(snapshotProvider);
          ref.invalidate(eventsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), // chừa chỗ cho nav nổi
          children: [
            const _Greeting(),
            const SizedBox(height: 20),
            snapAsync.when(
              loading: () => const _HeroSkeleton(),
              error: (e, _) => _HeroError(
                message: '$e',
                onRetry: () => ref.invalidate(snapshotProvider),
              ),
              data: (snap) => _HeroCard(snap: snap, wsUp: wsUp),
            ),
            const SizedBox(height: 20),
            if (snapAsync.hasValue) _AcCard(snap: snapAsync.value!),
            const SizedBox(height: 20),
            statsAsync.when(
              loading: () => const AppCard(
                child: SizedBox(
                    height: 120, child: Center(child: CircularProgressIndicator())),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (stats) => _SnapshotCard(stats: stats),
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final greet = h < 11
        ? 'Chào buổi sáng!'
        : h < 14
            ? 'Chào buổi trưa!'
            : h < 18
                ? 'Chào buổi chiều!'
                : 'Chào buổi tối!';
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.cottage_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greet, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text('Phòng ngủ đang thế nào',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero card gradient — vai trò như thẻ "Tokyo forecast" trong Travia: một con số/trạng
/// thái lớn + 3 chip phụ bên dưới.
class _HeroCard extends StatelessWidget {
  final Snapshot snap;
  final bool wsUp;
  const _HeroCard({required this.snap, required this.wsUp});

  @override
  Widget build(BuildContext context) {
    final occupied = snap.occupied;
    // Đổi màu theo trạng thái để liếc là biết, không cần đọc chữ.
    final colors = occupied
        ? [const Color(0xFF16A34A), const Color(0xFF0EA5E9)]
        : [const Color(0xFF6C5CE7), const Color(0xFF8B7BF0)];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Flexible + ellipsis: cỡ chữ hệ thống phóng to hoặc máy màn hẹp sẽ
              // đẩy chip sang phải và tràn Row.
              Flexible(
                child: Text('Trạng thái phòng',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              _LiveChip(wsUp: wsUp),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    occupied ? 'Có người' : 'Trống',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(occupied ? Icons.person_rounded : Icons.bedtime_rounded,
                  color: Colors.white.withValues(alpha: 0.9), size: 32),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            occupied
                ? 'Điều hoà sẽ tự bật khi bạn ở trong phòng'
                : 'Điều hoà tự tắt khi phòng trống',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              // present = radar thô; occupied (số to ở trên) = kết luận backend sau
              // khi gộp với PIR. Hiện cả hai để lệch nhau còn biết đường mà debug.
              Expanded(
                  child: _MiniStat(
                      icon: Icons.sensors_rounded,
                      value: snap.present ? 'Thấy' : 'Không',
                      label: 'Radar')),
              const SizedBox(width: 10),
              Expanded(
                  child: _MiniStat(
                      icon: Icons.ac_unit_rounded,
                      value: snap.acDesired ? 'Bật' : 'Tắt',
                      label: 'Điều hoà')),
              const SizedBox(width: 10),
              Expanded(
                  child: _MiniStat(
                      icon: Icons.directions_walk_rounded,
                      value: _ago(snap.lastMotionTs),
                      label: 'Chuyển động')),
            ],
          ),
        ],
      ),
    );
  }

  /// ts=0 = thiết bị publish trước khi NTP sync → không có giờ thật.
  static String _ago(int ts) {
    if (ts <= 0) return '—';
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts));  // ts đã là mili-giây
    if (d.isNegative || d.inSeconds < 60) return 'vừa xong';
    if (d.inMinutes < 60) return '${d.inMinutes}p';
    if (d.inHours < 24) return '${d.inHours}g';
    return '${d.inDays}n';
  }
}

/// Chip mờ trên hero — như "Jun 12 - Jun 14" trong Travia.
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _MiniStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75), fontSize: 10)),
        ],
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  final bool wsUp;
  const _LiveChip({required this.wsUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle,
              size: 7, color: wsUp ? const Color(0xFF86EFAC) : Colors.white54),
          const SizedBox(width: 5),
          Text(wsUp ? 'Trực tiếp' : 'Mất kết nối',
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
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
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.snap.acDesired;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBox(
                  icon: Icons.ac_unit_rounded,
                  color: AppTheme.blue,
                  active: on),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Điều hoà',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(on ? 'Đang bật' : 'Đang tắt',
                        style: TextStyle(
                            fontSize: 12,
                            color: on ? AppTheme.blue : AppTheme.inkSoft,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: AppTheme.blue,
                onChanged: _busy ? null : (v) => _send(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Lệnh tay có thể bị ghi đè khi phòng đổi trạng thái.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Ô icon bo góc màu nhạt — mẫu "Total bookings/check-ins" trong Travia.
class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;
  const _IconBox({required this.icon, required this.color, this.active = true});

  @override
  Widget build(BuildContext context) {
    final c = active ? color : AppTheme.inkSoft;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: c, size: 21),
    );
  }
}

/// "Performance snapshot" của Travia → số liệu sinh hoạt hôm nay.
class _SnapshotCard extends StatelessWidget {
  final Stats stats;
  const _SnapshotCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Text('Hôm nay', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (stats.yesterday == null)
                Text('chưa có mốc so sánh',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          _StatRow(
            icon: Icons.timer_outlined,
            color: AppTheme.green,
            label: 'Thời gian ở phòng',
            value: fmtDuration(stats.today.occupied),
            trend: stats.occupiedTrend,
          ),
          const SizedBox(height: 14),
          _StatRow(
            icon: Icons.ac_unit_rounded,
            color: AppTheme.blue,
            label: 'Điều hoà chạy',
            value: fmtDuration(stats.today.acOn),
            trend: stats.acOnTrend,
          ),
          const SizedBox(height: 14),
          _StatRow(
            icon: Icons.directions_walk_rounded,
            color: AppTheme.amber,
            label: 'Lần chuyển động',
            value: '${stats.today.motionCount}',
            trend: stats.motionTrend,
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final double? trend;
  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _IconBox(icon: icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink)),
            ],
          ),
        ),
        TrendBadge(percent: trend),
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        height: 230,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
}

class _HeroError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _HeroError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: AppTheme.inkSoft),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      );
}
