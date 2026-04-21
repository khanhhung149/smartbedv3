import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_repository.dart';
import '../models/history_response.dart';

// FutureProvider.family keyed by (deviceId, range).
// In-memory cache: Riverpod keeps result alive as long as a widget watches it.
// Re-fetch by invalidating: ref.invalidate(historyProvider((id, range))).

final _repoProvider = Provider<DataRepository>((_) => DataRepository());

final historyProvider = FutureProvider.family<HistoryResponse,
    ({String deviceId, String range})>((ref, params) async {
  final repo = ref.read(_repoProvider);
  return repo.getHistory(params.deviceId, params.range);
});
