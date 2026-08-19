import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/history_response.dart';
import 'data_repository_provider.dart';

// FutureProvider.family keyed by (deviceId, range).
// In-memory cache: Riverpod keeps result alive as long as a widget watches it.
// Re-fetch by invalidating: ref.invalidate(historyProvider((id, range))).
final historyProvider = FutureProvider.family<HistoryResponse,
    ({String deviceId, String range})>((ref, params) async {
  final repo = ref.read(dataRepositoryProvider);
  return repo.getHistory(params.deviceId, params.range);
});
