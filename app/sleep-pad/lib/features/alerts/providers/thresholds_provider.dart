import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/threshold_out.dart';
import 'alerts_repository_provider.dart';

// Fetches thresholds for a specific device (family-scoped by deviceId).
// Invalidate to refetch after a successful PUT.
final thresholdsProvider =
    FutureProvider.family<ThresholdOut, String>((ref, deviceId) async {
  final repo = ref.read(alertsRepositoryProvider);
  return repo.getThresholds(deviceId);
});
