import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pending_invite_out.dart';
import '../models/share_out.dart';
import '../models/shared_device_out.dart';
import 'sharing_repository_provider.dart';

// Devices shared with the current user (viewed as a guest)
final mySharedDevicesProvider =
    FutureProvider<List<SharedDeviceOut>>((ref) async {
  final repo = ref.read(sharingRepositoryProvider);
  return repo.getMySharedDevices();
});

// Pending invites for the current user's email — need Accept/Decline.
final pendingInvitesProvider =
    FutureProvider<List<PendingInviteOut>>((ref) async {
  final repo = ref.read(sharingRepositoryProvider);
  return repo.getPendingInvites();
});

// All shares for a specific device (owner only) — used in device_detail
final deviceSharesProvider =
    FutureProvider.family<List<ShareOut>, String>((ref, deviceId) async {
  final repo = ref.read(sharingRepositoryProvider);
  return repo.getDeviceShares(deviceId);
});
