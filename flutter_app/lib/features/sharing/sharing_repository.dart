import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import 'models/share_out.dart';
import 'models/shared_device_out.dart';

class SharingException implements Exception {
  const SharingException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Handles all sharing-related API calls.
// Endpoints:
//   POST   /share/invite              → ShareOut
//   POST   /share/{share_id}/accept   → 204
//   GET    /share/my-devices          → [SharedDeviceOut]
//   GET    /share/device/{device_id}  → [ShareOut]  (owner only)
//   DELETE /share/{share_id}          → 204
class SharingRepository {
  SharingRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // Invite a family member by email to view a device.
  Future<ShareOut> invite({
    required String deviceId,
    required String email,
  }) async {
    try {
      final res = await _client.dio.post('/share/invite', data: {
        'device_id': deviceId,
        'email': email,
      });
      return ShareOut.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw SharingException(_mapError(e));
    }
  }

  // Accept a pending invite (invited user calls this).
  Future<void> acceptInvite(String shareId) async {
    try {
      await _client.dio.post('/share/$shareId/accept');
    } on DioException catch (e) {
      throw SharingException(_mapError(e));
    }
  }

  // Get all devices shared with the current user.
  Future<List<SharedDeviceOut>> getMySharedDevices() async {
    try {
      final res = await _client.dio.get('/share/my-devices');
      final list = res.data as List<dynamic>;
      return list
          .map((item) =>
              SharedDeviceOut.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw SharingException(_mapError(e));
    }
  }

  // Get all shares for a device (owner only).
  Future<List<ShareOut>> getDeviceShares(String deviceId) async {
    try {
      final res = await _client.dio.get('/share/device/$deviceId');
      final list = res.data as List<dynamic>;
      return list
          .map((item) => ShareOut.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw SharingException(_mapError(e));
    }
  }

  // Revoke or cancel a share (owner calls revoke, invitee calls cancel/decline).
  Future<void> deleteShare(String shareId) async {
    try {
      await _client.dio.delete('/share/$shareId');
    } on DioException catch (e) {
      throw SharingException(_mapError(e));
    }
  }

  String _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return "Couldn't reach server. Check your connection.";
    }
    if (status == 401) return 'Session expired. Please log in again.';
    if (status == 403) return 'You do not have permission for this action.';
    if (status == 404) return 'Share or device not found.';
    if (status == 409) return 'Already shared with this email.';
    return 'Something went wrong (${status ?? 'unknown'}). Try again.';
  }
}
