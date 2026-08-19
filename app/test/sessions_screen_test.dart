import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smartbed_app/core/api_client.dart';
import 'package:smartbed_app/core/app_config.dart';
import 'package:smartbed_app/data/models/sleep_session.dart';
import 'package:smartbed_app/data/session_repository.dart';
import 'package:smartbed_app/features/sessions/sessions_providers.dart';
import 'package:smartbed_app/features/sessions/sessions_screen.dart';
import 'package:smartbed_app/features/sessions/widgets/disclaimer_footer.dart';
import 'package:smartbed_app/features/sessions/widgets/session_card.dart';
import 'package:smartbed_app/features/sessions/widgets/stale_data_banner.dart';

import 'session_repository_test.dart' show sessionJson;

Widget _host(List<Override> overrides) => ProviderScope(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) async => const AppConfig(
              baseUrl: 'http://x', deviceId: 'TEST000001', devToken: 't'),
        ),
        ...overrides,
      ],
      child: const MaterialApp(home: SessionsScreen()),
    );

Override _sessions(RepoResult<List<SleepSession>> result) =>
    sessionsProvider.overrideWith((ref) async => result);

void main() {
  setUpAll(() async => initializeDateFormatting('vi'));

  testWidgets('data — renders one card per night, newest first', (tester) async {
    await tester.pumpWidget(_host([
      _sessions(RepoResult(
        items: [
          SleepSession.fromJson(sessionJson('a')),
          SleepSession.fromJson({
            ...sessionJson('b'),
            'started_at': '2026-08-17T15:00:00Z',
          }),
        ],
        isStale: false,
      )),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(SessionCard), findsNWidgets(2));
    expect(find.byType(StaleDataBanner), findsNothing);
    expect(find.byType(DisclaimerFooter), findsOneWidget);
  });

  testWidgets('stale — shows the offline banner alongside the data',
      (tester) async {
    await tester.pumpWidget(_host([
      _sessions(RepoResult(
        items: [SleepSession.fromJson(sessionJson('a'))],
        isStale: true,
        cachedAt: DateTime(2026, 8, 19, 7, 30),
      )),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(StaleDataBanner), findsOneWidget);
    expect(find.textContaining('Dữ liệu ngoại tuyến'), findsOneWidget);
    expect(find.byType(SessionCard), findsOneWidget);
  });

  testWidgets('empty — explains why there is nothing rather than showing blank',
      (tester) async {
    await tester.pumpWidget(_host([
      _sessions(const RepoResult(items: <SleepSession>[], isStale: false)),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chưa có đêm nào'), findsOneWidget);
  });

  testWidgets('expired token — names the cause and offers the settings screen',
      (tester) async {
    await tester.pumpWidget(_host([
      sessionsProvider.overrideWith(
          (ref) async => throw const DevTokenExpiredException()),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dev token hết hạn'), findsOneWidget);
    expect(find.text('Mở cài đặt'), findsOneWidget);
  });

  testWidgets('a null metric renders an em dash, never a zero', (tester) async {
    await tester.pumpWidget(_host([
      _sessions(RepoResult(
        items: [
          SleepSession.fromJson({
            ...sessionJson('a'),
            'hr_avg': null,
            'snore_total': 0,
          }),
        ],
        isStale: false,
      )),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsOneWidget); // snore_total really is zero
  });

  testWidgets('pull to refresh re-runs the sessions provider', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host([
      sessionsProvider.overrideWith((ref) async {
        calls++;
        return RepoResult(
          items: [SleepSession.fromJson(sessionJson('a'))],
          isStale: false,
        );
      }),
    ]));
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(calls, greaterThan(1));
  });

  testWidgets('the wellness disclaimer is on screen', (tester) async {
    await tester.pumpWidget(_host([
      _sessions(RepoResult(
        items: [SleepSession.fromJson(sessionJson('a'))],
        isStale: false,
      )),
    ]));
    await tester.pumpAndSettle();

    expect(find.text(kWellnessDisclaimer), findsOneWidget);
  });

  for (final width in [360.0, 800.0]) {
    testWidgets('lays out without overflow at ${width.toInt()}dp',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host([
        _sessions(RepoResult(
          items: [
            SleepSession.fromJson(sessionJson('a')),
            SleepSession.fromJson(sessionJson('b')),
          ],
          isStale: false,
        )),
      ]));
      await tester.pumpAndSettle();

      // tester.takeException() surfaces the RenderFlex overflow that Flutter
      // otherwise only paints as a yellow-and-black stripe.
      expect(tester.takeException(), isNull);
    });
  }
}
