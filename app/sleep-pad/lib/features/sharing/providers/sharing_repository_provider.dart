import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/api_client_provider.dart';
import '../sharing_repository.dart';
import '../sharing_repository_impl.dart';

// Injects SharingRepositoryImpl via the abstract SharingRepository interface.
// Override in tests with: sharingRepositoryProvider.overrideWithValue(MockSharingRepository())
final sharingRepositoryProvider = Provider<SharingRepository>((ref) {
  return SharingRepositoryImpl(client: ref.read(apiClientProvider));
});
