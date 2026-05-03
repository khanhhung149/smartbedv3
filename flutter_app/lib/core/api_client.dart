import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'auth_storage.dart';

// Dio HTTP client with JWT Bearer interceptor.
// All requests to protected endpoints automatically include Authorization header.
// baseUrl is injected by apiClientProvider (see lib/shared/providers/api_client_provider.dart)
// so the correct flavor URL is used without hardcoding.
class ApiClient {
  ApiClient({required String baseUrl, AuthStorage? storage})
      : _storage = storage ?? AuthStorage() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_JwtInterceptor(_storage));
    if (kDebugMode) _dio.interceptors.add(_DebugLogInterceptor());
  }

  final AuthStorage _storage;
  late final Dio _dio;

  Dio get dio => _dio;
}

class _DebugLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[API] → ${options.method} ${options.uri}');
    if (options.data != null) debugPrint('[API]   body: ${options.data}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('[API] ← ${response.statusCode} ${response.requestOptions.uri}');
    debugPrint('[API]   data: ${response.data}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('[API] ✗ ${err.response?.statusCode ?? err.type} ${err.requestOptions.uri}');
    if (err.response?.data != null) debugPrint('[API]   error: ${err.response?.data}');
    handler.next(err);
  }
}

class _JwtInterceptor extends Interceptor {
  _JwtInterceptor(this._storage);

  final AuthStorage _storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Surface errors to callers — no silent suppression.
    handler.next(err);
  }
}
