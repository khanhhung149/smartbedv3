import 'models/alert_out.dart';
import 'models/threshold_out.dart';

// Abstract interface for alert threshold CRUD and alert history operations.
// Concrete implementation: AlertsRepositoryImpl in alerts_repository_impl.dart
// Riverpod provider: providers/alerts_repository_provider.dart
abstract class AlertsRepository {
  Future<ThresholdOut> getThresholds(String deviceId);
  Future<ThresholdOut> putThresholds(String deviceId, ThresholdOut thresholds);
  Future<List<AlertOut>> getHistory(String deviceId);
}
