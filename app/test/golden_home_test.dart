import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_ac/models/event.dart';
import 'package:home_ac/models/snapshot.dart';
import 'package:home_ac/providers.dart';
import 'package:home_ac/screens/analytics_screen.dart';
import 'package:home_ac/screens/home_screen.dart';
import 'package:home_ac/theme.dart';

/// Render UI ra ảnh để (1) bắt lỗi tràn layout — Flutter ném exception khi overflow,
/// (2) xem trước mà không phải cài APK lên máy.
///
///   flutter test --update-goldens test/golden_home_test.dart
///   → ảnh ở test/goldens/
///
/// Dữ liệu ở đây là giả LẬP CHO TEST (không phải dữ liệu thật trong app) — cần bố cục
/// xác định để ảnh so sánh được giữa các lần chạy.
void main() {
  final now = DateTime(2026, 7, 17, 12);
  int id = 0;
  Event ev(String kind, String value, DateTime t) => Event(
        id: ++id,
        ts: t.millisecondsSinceEpoch,  // contract: ts là MILI-giây
        kind: kind,
        value: value,
        source: kind == Event.kindMotion ? 'voice-node' : 'room-node',
      );

  final events = [
    ev(Event.kindAcCmd, 'on', DateTime(2026, 7, 17, 11, 0)),
    ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 10, 30)),
    for (var h = 7; h <= 11; h++)
      for (var i = 0; i < h % 4 + 1; i++)
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 17, h, i * 7)),
    // Hôm qua — để badge xu hướng có mốc so sánh
    ev(Event.kindPresence, 'false', DateTime(2026, 7, 16, 12, 0)),
    ev(Event.kindPresence, 'true', DateTime(2026, 7, 16, 10, 0)),
    ev(Event.kindAcCmd, 'off', DateTime(2026, 7, 16, 11, 30)),
    ev(Event.kindAcCmd, 'on', DateTime(2026, 7, 16, 10, 15)),
    for (var h = 8; h <= 11; h++) ev(Event.kindMotion, 'true', DateTime(2026, 7, 16, h, 5)),
  ].reversed.toList(); // backend trả mới nhất trước

  const snap = Snapshot(
    present: true,
    occupied: true,
    acDesired: true,
    lastMotionTs: 1784260800000,   // MILI-giây (contract firmware/mqtt/README.md)
    lastPresenceTs: 1784260800000,
    lastAcCmd: 'on',
  );

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          snapshotProvider.overrideWith((ref) => Stream.value(snap)),
          eventsProvider.overrideWith((ref) async => events),
          wsConnectedProvider.overrideWith((ref) => Stream.value(true)),
          // Ghim giờ: không có nó thì stats đọc đồng hồ thật, event test (đề ngày
          // 17/07 12:00) thành "tương lai" và khoảng đang mở bị bỏ → chart trống.
          nowProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(backgroundColor: AppTheme.bg, body: child),
        ),
      );

  testWidgets('Trang chủ render không tràn layout', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 13 Pro
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    // Có nội dung thật, không phải màn lỗi.
    expect(find.text('Có người'), findsOneWidget);
    expect(find.text('Điều hoà'), findsWidgets);
    expect(find.text('Hôm nay'), findsOneWidget);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home.png'),
    );
  });

  testWidgets('Phân tích render chart không tràn layout', (tester) async {
    tester.view.physicalSize = const Size(1170, 2900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const AnalyticsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Phân tích'), findsOneWidget);
    expect(find.text('Hoạt động theo giờ'), findsOneWidget);

    await expectLater(
      find.byType(AnalyticsScreen),
      matchesGoldenFile('goldens/analytics.png'),
    );
  });

  testWidgets('Trạng thái rỗng hiện lời giải thích, không bịa số', (tester) async {
    tester.view.physicalSize = const Size(1170, 2900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsProvider.overrideWith((ref) async => <Event>[]),
          snapshotProvider.overrideWith((ref) => Stream.value(Snapshot.empty)),
          wsConnectedProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa ghi nhận chuyển động nào hôm nay'), findsOneWidget);
    expect(find.text('Chưa đủ dữ liệu để vẽ'), findsOneWidget);
  });
}
