import 'package:dio/dio.dart';
import 'auth_storage.dart';
import 'constants.dart';

// Dio HTTP client with JWT Bearer interceptor.
// All requests to protected endpoints automatically include Authorization header.
class ApiClient {
  ApiClient({AuthStorage? storage})
      : _storage = storage ?? AuthStorage() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_JwtInterceptor(_storage));
  }

  final AuthStorage _storage;
  late final Dio _dio;

  Dio get dio => _dio;
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
