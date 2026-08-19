import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../data/local/session_cache.dart';
import '../../data/models/sleep_session.dart';
import '../../data/models/timeline_point.dart';
import '../../data/session_repository.dart';

/// Config is read once and re-read whenever the settings screen invalidates it,
/// which is what makes a retarget take effect without a rebuild.
final appConfigProvider = FutureProvider<AppConfig>((ref) => AppConfig.load());

final sessionCacheProvider = FutureProvider<SessionCache>((ref) async {
  final cache = await SessionCache.open();
  ref.onDispose(cache.close);
  return cache;
});

final sessionRepositoryProvider = FutureProvider<SessionRepository>((ref) async {
  final config = await ref.watch(appConfigProvider.future);
  final cache = await ref.watch(sessionCacheProvider.future);
  return SessionRepository(api: ApiClient(config), cache: cache);
});

final sessionsProvider =
    FutureProvider<RepoResult<List<SleepSession>>>((ref) async {
  final config = await ref.watch(appConfigProvider.future);
  final repo = await ref.watch(sessionRepositoryProvider.future);
  return repo.sessions(config.deviceId);
});

final timelineProvider = FutureProvider.family<
    RepoResult<List<TimelinePoint>>, String>((ref, sessionId) async {
  final repo = await ref.watch(sessionRepositoryProvider.future);
  return repo.timeline(sessionId);
});

/// Re-reads config and refetches. Called after saving settings and by pull to
/// refresh, so both paths go through exactly one code path.
void refreshSessions(WidgetRef ref) {
  ref.invalidate(appConfigProvider);
  ref.invalidate(sessionsProvider);
}
