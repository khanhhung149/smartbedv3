import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Log MQTT thô — xem đúng payload thiết bị gửi để soi/hiệu chỉnh cách đọc LD2410.
class MqttLogScreen extends ConsumerWidget {
  const MqttLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(radarMqttLogProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log MQTT'),
        backgroundColor: RadarTheme.bg,
        elevation: 0,
      ),
      body: log.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Chưa có message. Thiết bị phải bật MQTT và trỏ về broker '
                  'này. App đang nghe tele/+/# và stat/+/#.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: log.length,
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (_, i) {
                final e = log[i];
                final t = e.time;
                final hh = t.hour.toString().padLeft(2, '0');
                final mm = t.minute.toString().padLeft(2, '0');
                final ss = t.second.toString().padLeft(2, '0');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.topic,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: RadarTheme.accent)),
                        ),
                        Text('$hh:$mm:$ss',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      e.payload,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: RadarTheme.ink),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
