import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_out.dart';
import 'device_repository_provider.dart';

// Fetches all devices owned by the current user.
// Invalidate after pairing or removing a device to trigger a refresh.
final devicesListProvider = FutureProvider<List<DeviceOut>>((ref) async {
  final repo = ref.read(deviceRepositoryProvider);
  return repo.getMyDevices();
});
