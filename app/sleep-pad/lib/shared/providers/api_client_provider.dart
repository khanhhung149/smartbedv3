import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import 'app_env_provider.dart';

// Riverpod provider for ApiClient.
// Reads apiBaseUrl from appEnvProvider so flavor drives the base URL.
// Consumers: any repository or service that needs authenticated HTTP.
final apiClientProvider = Provider<ApiClient>((ref) {
  final env = ref.watch(appEnvProvider);
  return ApiClient(baseUrl: env.apiBaseUrl);
});
