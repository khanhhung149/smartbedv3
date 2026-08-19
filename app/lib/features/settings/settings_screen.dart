import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../sessions/sessions_providers.dart';

/// Retarget the app without a rebuild.
///
/// Exists because a build-time `--dart-define` is the wrong granularity for a
/// 30-day token: it expires mid-testing and nobody wants a toolchain to paste a
/// new one. Values written here override the compiled defaults.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _baseUrl = TextEditingController();
  final _deviceId = TextEditingController();
  final _devToken = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _baseUrl.dispose();
    _deviceId.dispose();
    _devToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: config.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (cfg) {
          if (!_loaded) {
            _baseUrl.text = cfg.baseUrl;
            _deviceId.text = cfg.deviceId;
            _devToken.text = cfg.devToken;
            _loaded = true;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Kết nối', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ backend',
                  helperText: 'Emulator Android: http://10.0.2.2:8000 · '
                      'Máy thật: http://<IP LAN của máy chủ>:8000',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _deviceId,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _devToken,
                decoration: const InputDecoration(
                  labelText: 'Dev token (JWT)',
                  helperText: 'Lấy bằng POST /auth/login. Hạn 30 ngày.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  await AppConfig.save(
                    AppConfig(
                      baseUrl: _baseUrl.text.trim(),
                      deviceId: _deviceId.text.trim(),
                      devToken: _devToken.text.trim(),
                    ),
                  );
                  if (!context.mounted) return;
                  refreshSessions(ref);
                  Navigator.of(context).pop();
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }
}
