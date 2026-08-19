import 'package:flutter_test/flutter_test.dart';
import 'package:smartbed_app/core/api_client.dart';
import 'package:smartbed_app/core/app_config.dart';
import 'package:smartbed_app/data/local/session_cache.dart';
import 'package:smartbed_app/data/session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The offline path, exercised against the real backend and the real cache
/// rather than a stub. Fetches for real, then points the same repository at a
/// port nothing is listening on — which is what losing the network looks like
/// from the app's side.
void main() {
  const baseUrl = String.fromEnvironment('API_BASE_URL');
  const deviceId = String.fromEnvironment('DEVICE_ID');
  const token = String.fromEnvironment('DEV_TOKEN');

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a warm cache survives the network going away', () async {
    expect(baseUrl, isNotEmpty, reason: 'pass --dart-define=API_BASE_URL');
    final cache = await SessionCache.open(path: inMemoryDatabasePath);
    addTearDown(cache.close);

    const online = AppConfig(
      baseUrl: baseUrl,
      deviceId: deviceId,
      devToken: token,
    );
    final live = await SessionRepository(api: ApiClient(online), cache: cache)
        .sessions(deviceId);
    expect(live.isStale, isFalse);
    expect(live.items, isNotEmpty);
    final sessionId = live.items.first.id;

    // Prime the timeline too, so the detail screen has something to reopen.
    final liveTimeline =
        await SessionRepository(api: ApiClient(online), cache: cache)
            .timeline(sessionId);
    expect(liveTimeline.isStale, isFalse);
    expect(liveTimeline.items, isNotEmpty);

    final offline = SessionRepository(
      api: ApiClient(online.copyWith(baseUrl: 'http://127.0.0.1:1')),
      cache: cache,
    );

    final cached = await offline.sessions(deviceId);
    expect(cached.isStale, isTrue);
    expect(cached.items.length, live.items.length);
    expect(cached.items.first.id, sessionId);
    expect(cached.cachedAt, isNotNull);

    final cachedTimeline = await offline.timeline(sessionId);
    expect(cachedTimeline.isStale, isTrue);
    expect(cachedTimeline.items.length, liveTimeline.items.length);

    // ignore: avoid_print
    print('offline: ${cached.items.length} phiên + '
        '${cachedTimeline.items.length} điểm timeline đọc lại từ cache, '
        'cachedAt=${cached.cachedAt}');
  }, skip: baseUrl.isEmpty
      ? 'live test — pass --dart-define=API_BASE_URL (see app/README.md)'
      : null);
}
