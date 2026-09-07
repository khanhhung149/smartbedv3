import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../sessions/sessions_providers.dart';
import 'realtime_models.dart';

/// Nhịp hỏi backend. Pad phát 1Hz nên hỏi nhanh hơn cũng không có số mới.
const _pollInterval = Duration(seconds: 1);

/// Dòng mẫu mới nhất, hỏi lại mỗi giây.
///
/// Dùng poll chứ không WebSocket: backend Go có sẵn `/api/ws` nhưng nó phát
/// trạng thái phòng của radar, không phải dữ liệu pad — thêm một kênh mới chỉ
/// để tiết kiệm vài request mỗi giây trong LAN là không đáng.
///
/// Trả null nghĩa là thiết bị chưa gửi mẫu nào — khác với lỗi gọi, nên màn hình
/// nói được "chưa có dữ liệu" thay vì báo hỏng.
final realtimeSampleProvider = StreamProvider.autoDispose<RealtimeSample?>((ref) async* {
  final config = await ref.watch(appConfigProvider.future);
  final client = http.Client();
  ref.onDispose(client.close);

  while (true) {
    final uri = Uri.parse('${config.baseUrl}/realtime')
        .replace(queryParameters: {'device_id': config.deviceId});
    final res = await client.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw RealtimeApiException('Backend trả HTTP ${res.statusCode}');
    }
    final body = res.body.trim();
    if (body.isEmpty || body == 'null') {
      yield null;
    } else {
      yield RealtimeSample.fromJson(jsonDecode(body) as Map<String, dynamic>);
    }
    await Future<void>.delayed(_pollInterval);
  }
});

/// Lỗi gọi backend — gói lại để UI hiện thông báo tiếng Việt thay vì stack trace.
class RealtimeApiException implements Exception {
  RealtimeApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
