import 'package:dio/dio.dart';

import 'app_config.dart';

/// The dev token expired or was rejected.
///
/// Distinguished from any other failure because the fix is specific and the
/// user can perform it: fetch a new token and paste it into settings. Folding
/// it into a generic network error would leave the app looking empty for no
/// stated reason.
class DevTokenExpiredException implements Exception {
  const DevTokenExpiredException();

  @override
  String toString() => 'DevTokenExpiredException';
}

/// The request reached no server, or the server failed.
class ApiUnavailableException implements Exception {
  const ApiUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'ApiUnavailableException: $message';
}

class ApiClient {
  ApiClient(this.config, {Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = config.baseUrl
      ..connectTimeout = const Duration(seconds: 8)
      ..receiveTimeout = const Duration(seconds: 15)
      ..headers['Authorization'] = 'Bearer ${config.devToken}';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          if (e.response?.statusCode == 401) {
            handler.reject(
              DioException(
                requestOptions: e.requestOptions,
                error: const DevTokenExpiredException(),
                response: e.response,
              ),
            );
            return;
          }
          handler.next(e);
        },
      ),
    );
  }

  final AppConfig config;
  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchSessions({
    required String deviceId,
    int limit = 30,
  }) async {
    final res = await _get('/sessions', {'device_id': deviceId, 'limit': limit});
    // Thiết bị chưa có phiên nào là chuyện bình thường, không phải lỗi — backend
    // đã sửa để trả `[]`, nhưng client không nên nổ nếu gặp `null`. Ép thẳng sang
    // List từng làm app văng "type 'Null' is not a subtype of type 'List<dynamic>'"
    // ngay khi trỏ vào một pad mới chưa qua đêm nào.
    if (res == null) return const [];
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchTimeline(
    String sessionId, {
    String bucket = '1m',
  }) async {
    final res = await _get('/sessions/$sessionId/timeline', {'bucket': bucket});
    return res as Map<String, dynamic>;
  }

  Future<dynamic> _get(String path, Map<String, dynamic> query) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return res.data;
    } on DioException catch (e) {
      final inner = e.error;
      if (inner is DevTokenExpiredException) throw inner;
      throw ApiUnavailableException(e.message ?? 'request failed');
    }
  }
}
