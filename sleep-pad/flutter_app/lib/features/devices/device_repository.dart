import 'models/device_out.dart';
import 'models/device_pair_out.dart';

// Abstract interface for device-related API operations.
// Concrete implementation: DeviceRepositoryImpl in device_repository_impl.dart
// Riverpod provider: providers/device_repository_provider.dart
abstract class DeviceRepository {
  Future<DevicePairOut> pairDevice({
    required String deviceId,
    required String name,
  });
  Future<List<DeviceOut>> getMyDevices();
  Future<void> deleteDevice(String deviceId);
}
