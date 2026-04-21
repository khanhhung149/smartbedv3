import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../alerts_repository.dart';
import '../models/threshold_out.dart';

// Repository singleton — recreated if needed per device call.
final alertsRepositoryProvider = Provider<AlertsRepository>(
  (_) => AlertsRepository(),
);

// Fetches thresholds for a specific device (family-scoped by deviceId).
// Invalidate to refetch after a successful PUT.
final thresholdsProvider =
    FutureProvider.family<ThresholdOut, String>((ref, deviceId) async {
  final repo = ref.read(alertsRepositoryProvider);
  return repo.getThresholds(deviceId);
});
