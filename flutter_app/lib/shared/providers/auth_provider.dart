import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_storage.dart';

// Auth state: null = unauthenticated, non-null string = JWT token
class AuthNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setToken(String token) => state = token;

  void clearToken() => state = null;
}

final authStorageProvider = Provider<AuthStorage>((_) => AuthStorage());

final authProvider = NotifierProvider<AuthNotifier, String?>(AuthNotifier.new);

// Async provider that reads the persisted JWT on app start.
// Used by GoRouter redirect to determine initial route.
final initialAuthProvider = FutureProvider<String?>((ref) async {
  final storage = ref.read(authStorageProvider);
  return storage.readToken();
});

// Reads the persisted user email from secure storage.
// Returns null if not logged in yet.
final userEmailProvider = FutureProvider<String?>((ref) async {
  // Re-run whenever auth state changes (login/logout).
  ref.watch(authProvider);
  final storage = ref.read(authStorageProvider);
  return storage.readEmail();
});
