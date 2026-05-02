// Abstract interface for authentication operations.
// Concrete implementation: AuthRepositoryImpl in auth_repository_impl.dart
// Riverpod provider: providers/auth_repository_provider.dart
abstract class AuthRepository {
  Future<String> register(String email, String password);
  Future<String> login(String email, String password);
  Future<void> logout();
  Future<String> verifyEmail(String email, String otp);
  Future<void> resendOtp(String email);
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String email, String otp, String password);
}
