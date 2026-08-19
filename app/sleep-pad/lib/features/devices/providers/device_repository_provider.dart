import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/api_client_provider.dart';
import '../device_repository.dart';
import '../device_repository_impl.dart';

// Injects DeviceRepositoryImpl via the abstract DeviceRepository interface.
// Override in tests with: deviceRepositoryProvider.overrideWithValue(MockDeviceRepository())
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepositoryImpl(client: ref.read(apiClientProvider));
});
