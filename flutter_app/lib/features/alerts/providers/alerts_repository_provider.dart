import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/api_client_provider.dart';
import '../alerts_repository.dart';
import '../alerts_repository_impl.dart';

// Injects AlertsRepositoryImpl via the abstract AlertsRepository interface.
// Override in tests with: alertsRepositoryProvider.overrideWithValue(MockAlertsRepository())
final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  return AlertsRepositoryImpl(client: ref.read(apiClientProvider));
});
