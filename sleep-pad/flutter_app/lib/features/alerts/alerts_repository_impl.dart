import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import 'alerts_repository.dart';
import 'models/alert_out.dart';
import 'models/threshold_out.dart';

class AlertsException implements Exception {
  const AlertsException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Concrete implementation of AlertsRepository.
// Handles alert threshold CRUD and alert history fetching.
// Endpoints:
//   GET  /alerts/{device_id}/thresholds → ThresholdOut
//   PUT  /alerts/{device_id}/thresholds → ThresholdOut (partial body ok)
//   GET  /alerts/{device_id}/history    → [AlertOut]
class AlertsRepositoryImpl implements AlertsRepository {
  AlertsRepositoryImpl({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<ThresholdOut> getThresholds(String deviceId) async {
    try {
      final res = await _client.dio.get('/alerts/$deviceId/thresholds');
      return ThresholdOut.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AlertsException(_mapError(e));
    }
  }

  @override
  Future<ThresholdOut> putThresholds(
    String deviceId,
    ThresholdOut thresholds,
  ) async {
    try {
      final res = await _client.dio.put(
        '/alerts/$deviceId/thresholds',
        data: thresholds.toJson(),
      );
      return ThresholdOut.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AlertsException(_mapError(e));
    }
  }

  @override
  Future<List<AlertOut>> getHistory(String deviceId) async {
    try {
      final res = await _client.dio.get('/alerts/$deviceId/history');
      final list = res.data as List<dynamic>;
      return list
          .map((item) => AlertOut.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AlertsException(_mapError(e));
    }
  }

  String _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return "Couldn't reach server. Check your connection.";
    }
    if (status == 401) return 'Session expired. Please log in again.';
    if (status == 404) return 'Device or thresholds not found.';
    return 'Something went wrong (${status ?? 'unknown'}). Try again.';
  }
}
