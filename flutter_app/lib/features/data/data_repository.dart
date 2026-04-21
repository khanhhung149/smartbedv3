import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import 'models/realtime_data.dart';
import 'models/history_response.dart';

class DataException implements Exception {
  const DataException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Handles all /data/* API calls.
// WS connection is managed separately in realtime_provider.dart.
class DataRepository {
  DataRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  // GET /data/{device_id}/realtime — latest sec_data row snapshot.
  Future<RealtimeData> getRealtime(String deviceId) async {
    try {
      final res = await _client.dio.get('/data/$deviceId/realtime');
      return RealtimeData.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DataException(_mapError(e));
    }
  }

  // GET /data/{device_id}/history?range=day|week|month
  Future<HistoryResponse> getHistory(String deviceId, String range) async {
    try {
      final res = await _client.dio.get(
        '/data/$deviceId/history',
        queryParameters: {'range': range},
      );
      return HistoryResponse.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DataException(_mapError(e));
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
    return e.response?.data?['detail']?.toString() ?? 'Unexpected error.';
  }
}
