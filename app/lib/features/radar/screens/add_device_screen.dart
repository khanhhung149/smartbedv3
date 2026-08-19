import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers.dart';
import '../theme.dart';

/// Thêm thiết bị: tự dò các thiết bị đang publish lên broker (qua MQTT wildcard,
/// thay cho mDNS — tin cậy hơn vì thiết bị vốn đã phải nói MQTT), hoặc nhập tay topic.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  final _topicCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();

  @override
  void dispose() {
    _topicCtrl.dispose();
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _add(String topic, {String? name, String? ip}) async {
    final t = topic.trim();
    if (t.isEmpty) return;
    await ref.read(radarDevicesProvider.notifier).add(MqttDevice(
          topic: t,
          name: (name == null || name.trim().isEmpty) ? t : name.trim(),
          ip: ip?.trim(),
        ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Đã thêm $t')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(radarMqttConnectedProvider).value ?? false;
    final discovered = ref.watch(radarDiscoveredTopicsProvider).value ?? const [];
    final added = ref.watch(radarDevicesProvider).map((d) => d.topic).toSet();
    final candidates = discovered.where((t) => !added.contains(t)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thêm thiết bị'),
        backgroundColor: RadarTheme.bg,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('Tự dò trên mạng',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!connected)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 18, color: RadarTheme.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chưa kết nối broker. Cấu hình MQTT ở tab Cài đặt trước.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else if (candidates.isEmpty)
            AppCard(
              child: Column(
                children: [
                  const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 12),
                  Text(
                    'Đang chờ thiết bị publish… Thiết bị phải bật MQTT và trỏ '
                    'về broker này thì mới hiện. Chưa thấy thì nhập tay bên dưới.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final t in candidates)
                    ListTile(
                      leading: const Icon(Icons.sensors_rounded,
                          color: RadarTheme.accent),
                      title: Text(t),
                      trailing: TextButton(
                        onPressed: () => _add(t),
                        child: const Text('Thêm'),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text('Nhập tay', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(_topicCtrl, 'MQTT topic (vd radar_phong_khach)',
                    Icons.tag_rounded),
                const SizedBox(height: 12),
                _field(_nameCtrl, 'Tên hiển thị (tuỳ chọn)',
                    Icons.label_outline_rounded),
                const SizedBox(height: 12),
                _field(_ipCtrl, 'IP web UI (tuỳ chọn, vd 192.168.1.34)',
                    Icons.language_rounded),
                const SizedBox(height: 8),
                Text(
                  'Topic = MQTT topic của thiết bị. App nghe '
                  'tele/<topic>/SENSOR và bắn cmnd/<topic>/STATUS để đọc radar.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _add(_topicCtrl.text,
                        name: _nameCtrl.text, ip: _ipCtrl.text),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Thêm thiết bị'),
                    style: FilledButton.styleFrom(
                      backgroundColor: RadarTheme.ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(RadarTheme.radiusSm)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon) => TextField(
        controller: c,
        autocorrect: false,
        decoration: InputDecoration(
          filled: true,
          fillColor: RadarTheme.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RadarTheme.radiusSm),
            borderSide: BorderSide.none,
          ),
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
        ),
      );
}
