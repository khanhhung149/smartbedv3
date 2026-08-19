import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert_out.dart';
import 'alerts_repository_provider.dart';

// Fetches alert history for a specific device, newest-first.
final alertHistoryProvider =
    FutureProvider.family<List<AlertOut>, String>((ref, deviceId) async {
  final repo = ref.read(alertsRepositoryProvider);
  final list = await repo.getHistory(deviceId);
  // Sort newest first — backend may return in insertion order
  list.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
  return list;
});
