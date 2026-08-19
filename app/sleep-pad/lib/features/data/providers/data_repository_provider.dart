import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/api_client_provider.dart';
import '../data_repository.dart';
import '../data_repository_impl.dart';

// Injects DataRepositoryImpl via the abstract DataRepository interface.
// Override in tests with: dataRepositoryProvider.overrideWithValue(MockDataRepository())
final dataRepositoryProvider = Provider<DataRepository>((ref) {
  return DataRepositoryImpl(client: ref.read(apiClientProvider));
});
