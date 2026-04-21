import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../sharing_repository.dart';
import '../models/share_out.dart';
import '../models/shared_device_out.dart';

// Repository singleton
final sharingRepositoryProvider = Provider<SharingRepository>(
  (_) => SharingRepository(),
);

// Devices shared with the current user (viewed as a guest)
final mySharedDevicesProvider =
    FutureProvider<List<SharedDeviceOut>>((ref) async {
  final repo = ref.read(sharingRepositoryProvider);
  return repo.getMySharedDevices();
});

// All shares for a specific device (owner only) — used in device_detail
final deviceSharesProvider =
    FutureProvider.family<List<ShareOut>, String>((ref, deviceId) async {
  final repo = ref.read(sharingRepositoryProvider);
  return repo.getDeviceShares(deviceId);
});
