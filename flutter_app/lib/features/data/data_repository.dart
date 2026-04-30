import 'models/realtime_data.dart';
import 'models/history_response.dart';

// Abstract interface for data fetching operations.
// Concrete implementation: DataRepositoryImpl in data_repository_impl.dart
// Riverpod provider: providers/data_repository_provider.dart
abstract class DataRepository {
  Future<RealtimeData> getRealtime(String deviceId);
  Future<HistoryResponse> getHistory(String deviceId, String range);
}
