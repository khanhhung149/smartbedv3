import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_client.dart';
import '../services/mqtt_service.dart';
import '../theme.dart';

class RadarSettingsScreen extends ConsumerStatefulWidget {
  const RadarSettingsScreen({super.key});

  @override
  ConsumerState<RadarSettingsScreen> createState() => _RadarSettingsScreenState();
}

class _RadarSettingsScreenState extends ConsumerState<RadarSettingsScreen> {
  late final TextEditingController _ctrl;
  String? _testResult;
  bool _testing = false;

  late final TextEditingController _mqttHost;
  late final TextEditingController _mqttPort;
  late final TextEditingController _mqttUser;
  late final TextEditingController _mqttPass;
  String? _mqttTestResult;
  bool _mqttTesting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(radarBaseUrlProvider));
    final cfg = ref.read(radarMqttConfigProvider);
    _mqttHost = TextEditingController(text: cfg.host);
    _mqttPort = TextEditingController(text: cfg.port.toString());
    _mqttUser = TextEditingController(text: cfg.username);
    _mqttPass = TextEditingController(text: cfg.password);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _mqttHost.dispose();
    _mqttPort.dispose();
    _mqttUser.dispose();
    _mqttPass.dispose();
    super.dispose();
  }

  MqttConfig _readMqttForm() => MqttConfig(
        host: _mqttHost.text.trim(),
        port: int.tryParse(_mqttPort.text.trim()) ?? 1883,
        username: _mqttUser.text.trim(),
        password: _mqttPass.text,
      );

  Future<void> _testMqtt() async {
    setState(() {
      _mqttTesting = true;
      _mqttTestResult = null;
    });
    final r = await MqttService.test(_readMqttForm());
    if (mounted) {
      setState(() {
        _mqttTesting = false;
        _mqttTestResult = r == 'ok' ? 'Kết nối được broker' : r;
      });
    }
  }

  Future<void> _saveMqtt() async {
    await ref.read(radarMqttConfigProvider.notifier).set(_readMqttForm());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình MQTT')),
      );
    }
  }

  /// Thử kết nối TRƯỚC khi lưu — user gõ nhầm IP thì biết ngay tại đây, thay vì về
  /// Trang chủ thấy màn lỗi rồi không hiểu sai ở đâu.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final url = RadarBaseUrlNotifier.normalize(_ctrl.text);
    final api = RadarApiClient(url);
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
    await ref.read(radarBaseUrlProvider.notifier).set(_ctrl.text);
    ref.invalidate(radarEventsProvider); // đổi URL → tải lại dữ liệu
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu ${ref.read(radarBaseUrlProvider)}')),
      );
    }
  }

  Widget _mqttField(TextEditingController c, String hint, IconData icon,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      keyboardType: keyboard,
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

  Widget _mqttCard(BuildContext context) {
    final ok = _mqttTestResult == 'Kết nối được broker';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Broker MQTT (thiết bị radar)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _mqttField(_mqttHost, 'Host broker (vd 192.168.1.120)',
              Icons.dns_rounded),
          const SizedBox(height: 10),
          _mqttField(_mqttPort, 'Cổng (1883)', Icons.numbers_rounded,
              keyboard: TextInputType.number),
          const SizedBox(height: 10),
          _mqttField(_mqttUser, 'Tài khoản MQTT', Icons.person_outline_rounded),
          const SizedBox(height: 10),
          _mqttField(_mqttPass, 'Mật khẩu MQTT', Icons.lock_outline_rounded,
              obscure: true),
          const SizedBox(height: 10),
          Text(
            'Tab Thiết bị đọc radar LD2410 qua broker này. Tài khoản/mật khẩu '
            'phải khớp broker — lưu trên máy, không gửi đi đâu khác.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _mqttTesting ? null : _testMqtt,
                  icon: _mqttTesting
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_find_rounded, size: 18),
                  label: const Text('Thử kết nối'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RadarTheme.radiusSm)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveMqtt,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Lưu'),
                  style: FilledButton.styleFrom(
                    backgroundColor: RadarTheme.ink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RadarTheme.radiusSm)),
                  ),
                ),
              ),
            ],
          ),
          if (_mqttTestResult != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: ok ? RadarTheme.green : RadarTheme.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_mqttTestResult!,
                        style: const TextStyle(fontSize: 13))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(radarBaseUrlProvider);
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
                    fillColor: RadarTheme.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RadarTheme.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'http://192.168.1.120:8080',
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
                                  BorderRadius.circular(RadarTheme.radiusSm)),
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
                if (_testResult != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: ok ? RadarTheme.green : RadarTheme.red, size: 18),
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
          _mqttCard(context),
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
