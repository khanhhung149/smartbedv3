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

  @override
  Future<String> verifyEmail(String email, String otp) async {
    try {
      final res = await _client.dio.post(
        '/auth/verify-email',
        data: {'email': email, 'otp': otp},
      );
      final token = res.data['access_token'] as String;
      await _storage.writeToken(token);
      return token;
    } on DioException catch (e) {
      throw AuthException(_mapDioError(e, isRegister: false));
    }
  }

  @override
  Future<void> resendOtp(String email) async {
    try {
      await _client.dio.post('/auth/resend-otp', data: {'email': email});
    } on DioException catch (e) {
      throw AuthException(_mapDioError(e, isRegister: false));
    }
  }

  @override
  Future<void> forgotPassword(String email) async {
    try {
      await _client.dio.post('/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) {
        throw const AuthException("Couldn't reach server. Check your connection.");
      }
      // Backend always returns 204 regardless of whether email exists; ignore other errors.
    }
  }

  @override
  Future<void> resetPassword(String email, String otp, String password) async {
    try {
      await _client.dio.post(
        '/auth/reset-password',
        data: {'email': email, 'otp': otp, 'password': password},
      );
    } on DioException catch (e) {
      throw AuthException(_mapDioError(e, isRegister: false));
    }
  }

  String _mapDioError(DioException e, {required bool isRegister}) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return "Couldn't reach server. Check your connection.";
    }
    if (status == 400) return 'Invalid or expired code.';
    if (status == 401) return 'Invalid credentials.';
    if (status == 403) return 'Please verify your email first.';
    if (status == 409 && isRegister) return 'Email already registered.';
    if (status == 422) return 'Invalid input. Check your details.';
    if (status == 429) return 'Too many attempts. Try again later.';
    return 'Something went wrong (${status ?? 'unknown'}). Try again.';
  }
}
