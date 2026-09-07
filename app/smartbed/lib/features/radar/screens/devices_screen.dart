import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers.dart';
import '../theme.dart';
import 'add_device_screen.dart';
import 'mqtt_log_screen.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Giữ binder poll sống bao lâu màn này hiển thị (thực ra gốc app cũng watch).
    ref.watch(radarDevicePollBinderProvider);
    final devices = ref.watch(radarDevicesProvider);
    final states = ref.watch(radarDeviceStatesProvider).value ?? const {};
    final connected = ref.watch(radarMqttConnectedProvider).value ?? false;
    // Thiết bị tự dò thấy qua MQTT (tele/stat/+/#) hiện luôn kèm số liệu, chưa cần
    // bấm "Thêm thiết bị". Topic lấy thẳng từ tin nhắn thật — khỏi nhập tay.
    final discovered = ref.watch(radarDiscoveredTopicsProvider).value ?? const [];
    final added = devices.map((d) => d.topic).toSet();
    final auto = [
      for (final t in discovered)
        if (!added.contains(t)) MqttDevice(topic: t, name: t),
    ];
    final visible = [...devices, ...auto];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thiết bị',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 2),
                    Text('Radar LD2410 qua MQTT',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Log MQTT',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MqttLogScreen()),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ConnBanner(connected: connected),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            const _EmptyState()
          else
            ...visible.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _DeviceCard(
                      device: d,
                      state: states[d.topic],
                      auto: !added.contains(d.topic)),
                )),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddDeviceScreen()),
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Thêm thiết bị'),
            style: FilledButton.styleFrom(
              backgroundColor: RadarTheme.ink,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RadarTheme.radiusSm)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnBanner extends StatelessWidget {
  final bool connected;
  const _ConnBanner({required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? RadarTheme.green : RadarTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(RadarTheme.radiusSm),
      ),
      child: Row(
        children: [
          Icon(connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected
                  ? 'Đã kết nối broker MQTT'
                  : 'Chưa kết nối broker — kiểm tra host/tài khoản trong Cài đặt',
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            const Icon(Icons.sensors_off_rounded,
                size: 44, color: RadarTheme.inkSoft),
            const SizedBox(height: 10),
            Text('Chưa có thiết bị nào',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Bấm "Thêm thiết bị" để tự dò trên mạng hoặc nhập MQTT topic của '
              'thiết bị radar LD2410.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

/// Thẻ 1 thiết bị: trạng thái có người to, kèm cự ly/năng lượng radar để hiệu chỉnh.
class _DeviceCard extends ConsumerWidget {
  final MqttDevice device;
  final DeviceState? state;
  final bool auto; // tự dò thấy qua MQTT, chưa được thêm/lưu vào danh sách
  const _DeviceCard(
      {required this.device, required this.state, this.auto = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Áp độ tươi TRƯỚC khi vẽ: tele/<T>/LWT kẹt "Online" nên chỉ lastSeen nói thật.
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = state?.viewAt(now);
    final online = s?.online ?? false;
    // Đã từng thấy mà giờ mất (quá cũ, hoặc LWT báo Offline) — khác hẳn "chưa nghe
    // gì bao giờ" (s == null), lúc đó chỉ là đang chờ tin chứ không phải hỏng.
    final lost = s != null && !online;
    final occ = s?.occupied;
    final Color tint = lost
        ? RadarTheme.red
        : occ == true
            ? RadarTheme.green
            : occ == false
                ? RadarTheme.inkSoft
                : RadarTheme.amber;
    final String label = lost
        ? 'Mất tín hiệu'
        : occ == true
            ? 'Có người'
            : occ == false
                ? 'Trống'
                : 'Chưa rõ';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                    lost
                        ? Icons.sensors_off_rounded
                        : occ == true
                            ? Icons.person_rounded
                            : Icons.sensors_rounded,
                    color: tint,
                    size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                    Text(device.topic,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              _OnlineDot(online: online),
              if (auto)
                TextButton.icon(
                  onPressed: () => ref
                      .read(radarDevicesProvider.notifier)
                      .add(MqttDevice(topic: device.topic, name: device.topic)),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Lưu'),
                )
              else
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'remove') {
                      ref.read(radarDevicesProvider.notifier).remove(device.topic);
                    } else if (v == 'rename') {
                      _rename(context, ref);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                    PopupMenuItem(value: 'remove', child: Text('Xoá')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: tint)),
              const Spacer(),
              Text(_ago(s?.lastSeenMs ?? 0),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _Metric(
                      label: 'Chuyển động',
                      dist: s?.movingDistance,
                      energy: s?.movingEnergy)),
              const SizedBox(width: 10),
              Expanded(
                  child: _Metric(
                      label: 'Đứng yên',
                      dist: s?.staticDistance,
                      energy: s?.staticEnergy)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên thiết bị'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(radarDevicesProvider.notifier).rename(device.topic, name);
    }
  }

  static String _ago(int ms) {
    if (ms <= 0) return 'chưa có dữ liệu';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inSeconds < 5) return 'vừa xong';
    if (d.inSeconds < 60) return '${d.inSeconds}s trước';
    if (d.inMinutes < 60) return '${d.inMinutes}p trước';
    return '${d.inHours}g trước';
  }
}

class _OnlineDot extends StatelessWidget {
  final bool online;
  const _OnlineDot({required this.online});

  @override
  Widget build(BuildContext context) {
    final c = online ? RadarTheme.green : RadarTheme.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: c),
          const SizedBox(width: 5),
          Text(online ? 'Online' : 'Offline',
              style: TextStyle(
                  fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int? dist;
  final int? energy;
  const _Metric({required this.label, required this.dist, required this.energy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: RadarTheme.bg,
        borderRadius: BorderRadius.circular(RadarTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(dist == null ? '—' : '$dist cm',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: RadarTheme.ink)),
          Text(energy == null ? 'năng lượng —' : 'năng lượng $energy',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
