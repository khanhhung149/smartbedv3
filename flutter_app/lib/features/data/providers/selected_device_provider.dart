import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants.dart';
import '../../devices/models/device_pair_out.dart';
import '../../devices/device_repository.dart';

// Persists + exposes the active device selection.
// On first load reads last_device_id from secure storage; falls back to
// first device in /devices/mine if no persisted value.

class SelectedDeviceNotifier extends AsyncNotifier<DevicePairOut?> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<DevicePairOut?> build() async {
    final devices = await DeviceRepository().getMyDevices();
    if (devices.isEmpty) return null;

    final lastId = await _storage.read(key: AppConstants.lastDeviceIdKey);
    if (lastId != null) {
      final match = devices.where((d) => d.deviceId == lastId).toList();
      if (match.isNotEmpty) return match.first;
    }
    // Default to first device
    return devices.first;
  }

  // Devices list used by bottom sheet selector.
  Future<List<DevicePairOut>> listDevices() => DeviceRepository().getMyDevices();

  Future<void> selectDevice(DevicePairOut device) async {
    state = AsyncData(device);
    await _storage.write(
      key: AppConstants.lastDeviceIdKey,
      value: device.deviceId,
    );
  }
}

final selectedDeviceProvider =
    AsyncNotifierProvider<SelectedDeviceNotifier, DevicePairOut?>(
  SelectedDeviceNotifier.new,
);
