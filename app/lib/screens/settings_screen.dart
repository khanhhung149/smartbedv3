import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_client.dart';
import '../theme.dart';

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

  /// Thử kết nối TRƯỚC khi lưu — user gõ nhầm IP thì biết ngay tại đây, thay vì về
  /// Trang chủ thấy màn lỗi rồi không hiểu sai ở đâu.
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
    ref.invalidate(eventsProvider); // đổi URL → tải lại dữ liệu
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

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Text('Cài đặt', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Kết nối tới máy chủ ở nhà',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Địa chỉ backend',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'http://192.168.1.95:8080',
                    prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 10),
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
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_find_rounded, size: 18),
                        label: const Text('Thử kết nối'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSm)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Lưu'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.ink,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSm)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: ok ? AppTheme.green : AppTheme.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_testResult!,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đang dùng', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(current, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 18),
                Text('Hệ thống hoạt động thế nào',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Radar (room-node) báo có người, PIR (voice-node) báo chuyển động. '
                  'Máy chủ gộp hai tín hiệu rồi quyết định bật/tắt điều hoà. '
                  'Nói "bật điều hoà" hoặc "tắt điều hoà" vào mic cũng điều khiển được.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
