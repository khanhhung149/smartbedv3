import 'models/pending_invite_out.dart';
import 'models/share_out.dart';
import 'models/shared_device_out.dart';

// Abstract interface for sharing-related API operations.
// Concrete implementation: SharingRepositoryImpl in sharing_repository_impl.dart
// Riverpod provider: providers/sharing_repository_provider.dart
abstract class SharingRepository {
  Future<ShareOut> invite({required String deviceId, required String email});
  Future<void> acceptInvite(String shareId);
  Future<List<PendingInviteOut>> getPendingInvites();
  Future<List<SharedDeviceOut>> getMySharedDevices();
  Future<List<ShareOut>> getDeviceShares(String deviceId);
  Future<void> deleteShare(String shareId);
}
