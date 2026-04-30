import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/api_client_provider.dart';
import '../auth_repository.dart';
import '../auth_repository_impl.dart';

// Injects AuthRepositoryImpl via the abstract AuthRepository interface.
// Override in tests with: authRepositoryProvider.overrideWithValue(MockAuthRepository())
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(client: ref.read(apiClientProvider));
});
