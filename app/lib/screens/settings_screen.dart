import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_client.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _ctrl;
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(baseUrlProvider));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Thử kết nối TRƯỚC khi lưu — user gõ nhầm IP thì biết ngay tại đây,
  /// thay vì về Home thấy màn lỗi rồi không hiểu sai ở đâu.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final url = BaseUrlNotifier.normalize(_ctrl.text);
    final api = ApiClient(url);
    final ok = await api.healthy();
    api.close();
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = ok ? 'Kết nối được backend' : 'Không kết nối được $url';
      });
    }
  }

  Future<void> _save() async {
    await ref.read(baseUrlProvider.notifier).set(_ctrl.text);
    // Đổi URL → dựng lại client + tải lại dữ liệu.
    ref.invalidate(eventsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu ${ref.read(baseUrlProvider)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(baseUrlProvider);
    final ok = _testResult?.startsWith('Kết nối được') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Địa chỉ backend',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'http://192.168.1.95:8080',
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Phải là IP LAN của máy chạy backend — điện thoại không dùng được '
            'localhost. Điện thoại và máy phải cùng WiFi.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_find),
                  label: const Text('Thử kết nối'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Lưu'),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.error,
                    color: ok ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_testResult!)),
              ],
            ),
          ],
          const Divider(height: 40),
          ListTile(
            dense: true,
            title: const Text('Đang dùng'),
            subtitle: Text(current),
          ),
          const ListTile(
            dense: true,
            title: Text('Cách hoạt động'),
            subtitle: Text(
              'Radar (room-node) báo có người, PIR (voice-node) báo chuyển động. '
              'Backend gộp hai tín hiệu rồi quyết định bật/tắt điều hoà. '
              'Nói "bật/tắt điều hoà" vào mic cũng điều khiển được.',
            ),
          ),
        ],
      ),
    );
  }
}
