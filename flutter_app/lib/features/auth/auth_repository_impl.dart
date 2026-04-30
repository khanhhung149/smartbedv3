import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import 'auth_repository.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Concrete implementation of AuthRepository.
// Handles /auth/register and /auth/login API calls.
// On success, persists JWT via AuthStorage.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required ApiClient client, AuthStorage? storage})
      : _client = client,
        _storage = storage ?? AuthStorage();

  final ApiClient _client;
  final AuthStorage _storage;

  // POST /auth/register — returns registered email on success.
  // Throws AuthException with user-facing message on failure.
  @override
  Future<String> register(String email, String password) async {
    try {
      final res = await _client.dio.post(
        '/auth/register',
        data: {'email': email, 'password': password},
      );
      return res.data['email'] as String;
    } on DioException catch (e) {
      throw AuthException(_mapDioError(e, isRegister: true));
    }
  }

  // POST /auth/login — persists JWT and returns token on success.
  @override
  Future<String> login(String email, String password) async {
    try {
      final res = await _client.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = res.data['access_token'] as String;
      await _storage.writeToken(token);
      return token;
    } on DioException catch (e) {
      throw AuthException(_mapDioError(e, isRegister: false));
    }
  }

  @override
  Future<void> logout() async {
    await _storage.deleteToken();
  }

  String _mapDioError(DioException e, {required bool isRegister}) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return "Couldn't reach server. Check your connection.";
    }
    if (status == 401) return 'Invalid credentials.';
    if (status == 409 && isRegister) return 'Email already registered.';
    if (status == 422) return 'Invalid input. Check your details.';
    return 'Something went wrong (${status ?? 'unknown'}). Try again.';
  }
}
