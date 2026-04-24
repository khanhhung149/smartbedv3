import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../device_repository.dart';
import '../models/device_out.dart';

// Fetches all devices owned by the current user.
// Invalidate after pairing or removing a device to trigger a refresh.
final devicesListProvider = FutureProvider<List<DeviceOut>>((ref) async {
  final repo = DeviceRepository();
  return repo.getMyDevices();
});
