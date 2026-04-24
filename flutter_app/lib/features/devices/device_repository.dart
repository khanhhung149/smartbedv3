import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import 'models/device_out.dart';
import 'models/device_pair_out.dart';

class DeviceException implements Exception {
  const DeviceException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Handles device-related API calls: pairing and listing owned devices.
// Naming decision: POST /devices/pair is called with a default name ("New Device")
// before BLE provisioning. The success screen then re-calls pair with the user's
// chosen name (backend upserts on device_id — idempotent per protocol doc).
class DeviceRepository {
  DeviceRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // POST /devices/pair — registers/upserts device for this user.
  // Returns DevicePairOut which includes MQTT credentials for BLE provisioning.
  Future<DevicePairOut> pairDevice({
    required String deviceId,
    required String name,
  }) async {
    try {
      final res = await _client.dio.post(
        '/devices/pair',
        data: {'device_id': deviceId, 'name': name},
      );
      return DevicePairOut.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DeviceException(_mapError(e));
    }
  }

  // GET /devices/mine — returns list of devices owned by current user.
  // Uses DeviceOut (no MQTT creds) — those live only in the pairing response.
  Future<List<DeviceOut>> getMyDevices() async {
    try {
      final res = await _client.dio.get('/devices/mine');
      final list = res.data as List<dynamic>;
      return list
          .map((item) => DeviceOut.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw DeviceException(_mapError(e));
    }
  }

  // DELETE /devices/{id} — remove from account + triggers retained MQTT
  // factory_reset so the physical device wipes its NVS on next reconnect.
  Future<void> deleteDevice(String deviceId) async {
    try {
      await _client.dio.delete('/devices/$deviceId');
    } on DioException catch (e) {
      throw DeviceException(_mapError(e));
    }
  }

  String _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return "Couldn't reach server. Check your connection.";
    }
    if (status == 401) return 'Session expired. Please log in again.';
    if (status == 404) return 'Device not found.';
    if (status == 409) return 'Device already paired to another account.';
    return 'Something went wrong (${status ?? 'unknown'}). Try again.';
  }
}
