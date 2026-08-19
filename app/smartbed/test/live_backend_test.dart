import 'package:flutter_test/flutter_test.dart';
import 'package:smartbed_app/core/api_client.dart';
import 'package:smartbed_app/core/app_config.dart';
import 'package:smartbed_app/data/models/sleep_session.dart';
import 'package:smartbed_app/data/models/timeline_point.dart';

/// Talks to a running backend. Excluded from the default run because it needs
/// one; the point is to prove the parsing layer against what the server really
/// sends, not against a fixture someone wrote to match the code.
///
///   flutter test test/live_backend_test.dart \
///     --dart-define=API_BASE_URL=http://localhost:8000 \
///     --dart-define=DEVICE_ID=TEST000001 \
///     --dart-define=DEV_TOKEN=`<jwt>`
void main() {
  const baseUrl = String.fromEnvironment('API_BASE_URL');
  const deviceId = String.fromEnvironment('DEVICE_ID');
  const token = String.fromEnvironment('DEV_TOKEN');

  test('reads real sessions and a real timeline', () async {
    expect(baseUrl, isNotEmpty, reason: 'pass --dart-define=API_BASE_URL');

    final api = ApiClient(const AppConfig(
      baseUrl: baseUrl,
      deviceId: deviceId,
      devToken: token,
    ));

    final raw = await api.fetchSessions(deviceId: deviceId);
    final sessions = raw.map(SleepSession.fromJson).toList();
    expect(sessions, isNotEmpty);

    final s = sessions.first;
    // ignore: avoid_print
    print('session ${s.id}  ${s.startedAt} -> ${s.endedAt}  '
        'hr_avg=${s.hrAvg}  movement=${s.movementTotal}');
    expect(s.deviceId, deviceId);
    expect(s.hrAvg, isNotNull);

    final tl = await api.fetchTimeline(s.id);
    final points = (tl['points'] as List)
        .cast<Map<String, dynamic>>()
        .map(TimelinePoint.fromJson)
        .toList();
    // ignore: avoid_print
    print('timeline ${points.length} points, '
        'first=${points.first.t} hr=${points.first.hr} '
        'events=${points.first.events.map((e) => e.label).toList()}');
    expect(points, isNotEmpty);
    expect(points.first.onBed, isTrue);
  }, skip: baseUrl.isEmpty
      ? 'live test — pass --dart-define=API_BASE_URL (see app/README.md)'
      : null);
}
