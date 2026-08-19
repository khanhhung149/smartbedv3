import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/event.dart';
import '../models/snapshot.dart';

/// Lỗi gọi backend — gói lại để UI hiện thông báo tiếng Việt thay vì stack trace.
class RadarApiException implements Exception {
  final String message;
  RadarApiException(this.message);
  @override
  String toString() => message;
}

/// Client REST tới backend Go. Base URL do user đặt trong Settings (IP LAN của máy
/// chạy backend) — máy Android KHÔNG dùng được localhost.
class RadarApiClient {
  final String baseUrl;
  final http.Client _http;

  RadarApiClient(this.baseUrl, {http.Client? client})
      : _http = client ?? http.Client();

  static const _timeout = Duration(seconds: 8);

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<Snapshot> getState() async {
    final r = await _get('/api/state');
    return Snapshot.fromJson(jsonDecode(r) as Map<String, dynamic>);
  }

  /// before = id của event cuối trang trước; 0/null = trang đầu.
  Future<List<Event>> getEvents({int limit = 50, int? before}) async {
    final q = {'limit': '$limit'};
    if (before != null && before > 0) q['before'] = '$before';
    final r = await _get('/api/events', q);
    final body = jsonDecode(r) as Map<String, dynamic>;
    final list = body['events'] as List? ?? [];
    return list
        .map((e) => Event.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Bật/tắt AC bằng tay. Backend publish MQTT; state machine vẫn tự điều khiển tiếp
  /// nên lệnh tay có thể bị ghi đè khi phòng đổi trạng thái — đó là thiết kế, không phải lỗi.
  Future<void> setAc(bool on) async {
    final res = await _http
        .post(
          _uri('/api/ac'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'cmd': on ? 'on' : 'off'}),
        )
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw RadarApiException(_explain(res.statusCode, res.body));
    }
  }

  Future<bool> healthy() async {
    try {
      final r = await _get('/healthz');
      return (jsonDecode(r) as Map<String, dynamic>)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<String> _get(String path, [Map<String, String>? q]) async {
    late http.Response res;
    try {
      res = await _http.get(_uri(path, q)).timeout(_timeout);
    } catch (e) {
      throw RadarApiException('Không kết nối được backend ($baseUrl). Kiểm tra IP trong Cài đặt và cùng WiFi.');
    }
    if (res.statusCode != 200) {
      throw RadarApiException(_explain(res.statusCode, res.body));
    }
    return res.body;
  }

  /// Dịch lỗi HTTP sang câu tiếng Việt hiểu được. Backend trả {"error":"..."} ở thân.
  String _explain(int code, String body) {
    String detail = '';
    try {
      detail = (jsonDecode(body) as Map<String, dynamic>)['error'] as String? ?? '';
    } catch (_) {}
    if (code == 503) {
      return detail.isNotEmpty ? detail : 'Backend chưa bật lịch sử.';
    }
    return 'Backend trả lỗi $code${detail.isNotEmpty ? ': $detail' : ''}';
  }

  void close() => _http.close();
}
