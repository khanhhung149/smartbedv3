import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:smartbed_app/core/app_config.dart';
import 'package:smartbed_app/core/app_theme.dart';
import 'package:smartbed_app/data/models/sleep_session.dart';
import 'package:smartbed_app/data/models/timeline_point.dart';
import 'package:smartbed_app/data/session_repository.dart';
import 'package:smartbed_app/features/session_detail/session_detail_screen.dart';
import 'package:smartbed_app/features/session_detail/widgets/bed_state_band.dart';
import 'package:smartbed_app/features/session_detail/widgets/event_markers.dart';
import 'package:smartbed_app/features/session_detail/widgets/timeline_chart.dart';
import 'package:smartbed_app/features/sessions/sessions_providers.dart';
import 'package:smartbed_app/features/sessions/widgets/disclaimer_footer.dart';

import 'session_repository_test.dart' show sessionJson;

Map<String, dynamic> pointJson(
  DateTime t, {
  double? hr = 62,
  bool onBed = true,
  List<int> events = const [4],
}) =>
    {
      't': t.toUtc().toIso8601String(),
      'hr': hr,
      'rr': 15.0,
      'movement': 1,
      'snore': 0,
      'resp_disorder': 0,
      'bed_state': onBed ? 'on_bed' : 'off_bed',
      'events': events,
    };

Widget _host(List<TimelinePoint> points) => ProviderScope(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) async => const AppConfig(
              baseUrl: 'http://x', deviceId: 'TEST000001', devToken: 't'),
        ),
        sessionsProvider.overrideWith(
          (ref) async => RepoResult(
            items: [SleepSession.fromJson(sessionJson('a'))],
            isStale: false,
          ),
        ),
        timelineProvider.overrideWith(
          (ref, id) async => RepoResult(items: points, isStale: false),
        ),
      ],
      child: const MaterialApp(home: SessionDetailScreen(sessionId: 'a')),
    );

/// The default 800x600 test surface is shorter than this screen, and ListView
/// only builds what fits. Without a taller viewport the chart is never
/// constructed and every finder below reports a false negative.
void useTallSurface(WidgetTester tester, {double width = 800}) {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async => initializeDateFormatting('vi'));

  final base = DateTime.utc(2026, 8, 18, 15);

  testWidgets('data — draws the chart, the occupancy band and the disclaimer',
      (tester) async {
    useTallSurface(tester);
    final points = [
      for (var i = 0; i < 120; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
    ];
    await tester.pumpWidget(_host(points));
    await tester.pumpAndSettle();

    expect(find.byType(TimelineChart), findsOneWidget);
    expect(find.byType(BedStateBand), findsOneWidget);
    expect(find.text(kWellnessDisclaimer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty timeline — says so instead of drawing a blank chart',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(find.byType(TimelineChart), findsNothing);
    expect(find.textContaining('Chưa có diễn biến'), findsOneWidget);
  });

  test('a gap breaks the line into separate segments instead of bridging it',
      () {
    // 60 minutes, then a 40-minute hole, then 60 more. Joining across the hole
    // would draw a heart rate nobody measured.
    final points = [
      for (var i = 0; i < 60; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
      for (var i = 100; i < 160; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
    ];
    final segments = TimelineChart.segments(points, (p) => p.hr);

    expect(segments.length, 2);
    expect(segments.first.length, 60);
    expect(segments.last.length, 60);
  });

  test('a null metric also breaks the line', () {
    final points = [
      for (var i = 0; i < 10; i++)
        TimelinePoint.fromJson(
          pointJson(base.add(Duration(minutes: i)), hr: i == 5 ? null : 62),
        ),
    ];
    final segments = TimelineChart.segments(points, (p) => p.hr);

    expect(segments.length, 2);
    expect(segments.fold<int>(0, (a, s) => a + s.length), 9);
  });

  testWidgets('the bed band paints on/off exactly as bed_state says',
      (tester) async {
    useTallSurface(tester);
    // Three buckets with a clear on → off → on pattern, no data gaps.
    final points = [
      for (var i = 0; i < 30; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
      for (var i = 30; i < 40; i++)
        TimelinePoint.fromJson(
          pointJson(base.add(Duration(minutes: i)), onBed: false),
        ),
      for (var i = 40; i < 70; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
    ];
    await tester.pumpWidget(_host(points));
    await tester.pumpAndSettle();

    final band = find.byType(BedStateBand);
    expect(band, findsOneWidget);

    // Cells live inside the band's ClipRRect; the legend swatches below are
    // also Containers, so scope to the ClipRRect to count only the cells.
    final bandBox = find.descendant(
      of: band,
      matching: find.byType(ClipRRect),
    );
    final cells = tester.widgetList<Container>(find.descendant(
      of: bandBox,
      matching: find.byType(Container),
    ));
    final onCells = cells.where((c) => c.color == MetricColors.onBed).length;
    final offCells = cells.where(
      (c) => c.color != MetricColors.onBed && c.color != null,
    ).length;
    expect(onCells, 60);
    expect(offCells, 10);
  });

  testWidgets('event markers list the right events at the right clock times',
      (tester) async {
    useTallSurface(tester);
    final sitUpAt = base.add(const Duration(hours: 9, minutes: 12));
    final snore1At = base.add(const Duration(hours: 10, minutes: 40));
    final snore2At = base.add(const Duration(hours: 12, minutes: 5));
    final points = [
      for (var i = 0; i < 120; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
      TimelinePoint.fromJson(pointJson(sitUpAt, events: [3])),
      TimelinePoint.fromJson(pointJson(snore1At, events: [7])),
      TimelinePoint.fromJson(pointJson(snore2At, events: [7])),
    ];
    await tester.pumpWidget(_host(points));
    await tester.pumpAndSettle();

    // The marker renders local clock time, and `fromJson` converts to local —
    // compute the expectation the same way instead of hardcoding a timezone.
    final fmt = DateFormat('HH:mm', 'vi');
    // Grouped by type, with a count and the local clock time of each hit.
    // Scope to the EventMarkers subtree — the chart's own axis can contain the
    // same clock string.
    final markers = find.byType(EventMarkers);
    expect(find.text('Ngồi dậy · 1 lần'), findsOneWidget);
    expect(find.text('Ngáy · 2 lần'), findsOneWidget);
    expect(
      find.descendant(
        of: markers,
        matching: find.textContaining(fmt.format(sitUpAt.toLocal())),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: markers,
        matching: find.textContaining(fmt.format(snore1At.toLocal())),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: markers,
        matching: find.textContaining(fmt.format(snore2At.toLocal())),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the page never scrolls sideways at 360dp', (tester) async {
    useTallSurface(tester, width: 360);

    final points = [
      for (var i = 0; i < 480; i++)
        TimelinePoint.fromJson(pointJson(base.add(Duration(minutes: i)))),
    ];
    await tester.pumpWidget(_host(points));
    await tester.pumpAndSettle();

    // The one horizontal scroller must be the chart's own box, not the page.
    final horizontal = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((w) => w.scrollDirection == Axis.horizontal);
    expect(horizontal.length, 1);
    expect(tester.takeException(), isNull);
  });
}
