import 'package:flutter_test/flutter_test.dart';
import 'package:smartbed_app/core/api_client.dart';
import 'package:smartbed_app/core/app_config.dart';
import 'package:smartbed_app/data/local/session_cache.dart';
import 'package:smartbed_app/data/session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stands in for the network. Each test sets exactly one behaviour, so a
/// failure names the branch it came from.
class _FakeApi extends ApiClient {
  _FakeApi({this.sessions, this.error})
      : super(const AppConfig(baseUrl: '', deviceId: '', devToken: ''));

  final List<Map<String, dynamic>>? sessions;
  final Object? error;

  @override
  Future<List<Map<String, dynamic>>> fetchSessions({
    required String deviceId,
    int limit = 30,
  }) async {
    if (error != null) throw error!;
    return sessions!;
  }
}

Map<String, dynamic> sessionJson(String id, {Map<String, dynamic>? extra}) => {
      'id': id,
      'device_id': 'TEST000001',
      'started_at': '2026-08-18T15:00:00Z',
      'ended_at': '2026-08-18T22:59:59Z',
      'duration_s': 28799,
      'hr_avg': 62.19,
      'hr_min': 52,
      'hr_max': 70,
      'rr_avg': 15.0,
      'movement_total': 717,
      'snore_total': 96,
      'resp_disorder_total': 7,
      'sit_up_count': 3,
      'wake_count': 4,
      ...?extra,
    };

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SessionCache cache;

  setUp(() async {
    cache = await SessionCache.open(path: inMemoryDatabasePath);
  });

  tearDown(() async => cache.close());

  test('network succeeds — returns fresh data and fills the cache', () async {
    final repo = SessionRepository(
      api: _FakeApi(sessions: [sessionJson('a')]),
      cache: cache,
    );
    final result = await repo.sessions('TEST000001');

    expect(result.isStale, isFalse);
    expect(result.items.single.id, 'a');
    expect((await cache.readSessions('TEST000001')).single.id, 'a');
  });

  test('network fails with a warm cache — returns cached data marked stale',
      () async {
    await SessionRepository(
      api: _FakeApi(sessions: [sessionJson('a')]),
      cache: cache,
    ).sessions('TEST000001');

    final offline = SessionRepository(
      api: _FakeApi(error: const ApiUnavailableException('no route to host')),
      cache: cache,
    );
    final result = await offline.sessions('TEST000001');

    expect(result.isStale, isTrue);
    expect(result.items.single.id, 'a');
    expect(result.cachedAt, isNotNull);
  });

  test('network fails with an empty cache — returns empty, does not throw',
      () async {
    final repo = SessionRepository(
      api: _FakeApi(error: const ApiUnavailableException('no route to host')),
      cache: cache,
    );
    final result = await repo.sessions('TEST000001');

    expect(result.isStale, isTrue);
    expect(result.items, isEmpty);
  });

  test('an expired token surfaces instead of hiding behind cached data',
      () async {
    // A stale-looking screen would send the user hunting for a network problem
    // that does not exist. The fix is theirs to make, so they must be told.
    final repo = SessionRepository(
      api: _FakeApi(error: const DevTokenExpiredException()),
      cache: cache,
    );
    expect(() => repo.sessions('TEST000001'),
        throwsA(isA<DevTokenExpiredException>()));
  });

  test('a field the app does not know about survives the cache round trip',
      () async {
    final repo = SessionRepository(
      api: _FakeApi(sessions: [
        sessionJson('a', extra: {'presence': 2, 'ac_on': true}),
      ]),
      cache: cache,
    );
    await repo.sessions('TEST000001');

    final cached = (await cache.readSessions('TEST000001')).single;
    expect(cached.raw['presence'], 2);
    expect(cached.raw['ac_on'], isTrue);
    expect(cached.hrAvg, closeTo(62.19, 0.001));
  });

  test('null and zero stay distinguishable', () async {
    final repo = SessionRepository(
      api: _FakeApi(sessions: [
        sessionJson('a', extra: {'hr_avg': null, 'snore_total': 0}),
      ]),
      cache: cache,
    );
    final s = (await repo.sessions('TEST000001')).items.single;

    expect(s.hrAvg, isNull);
    expect(s.snoreTotal, 0);
  });
}
