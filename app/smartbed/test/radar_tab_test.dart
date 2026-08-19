import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbed_app/core/app_config.dart';
import 'package:smartbed_app/core/app_router.dart';
import 'package:smartbed_app/features/radar/models/snapshot.dart';
import 'package:smartbed_app/features/radar/providers.dart';
import 'package:smartbed_app/features/radar/radar_root_screen.dart';
import 'package:smartbed_app/features/sessions/sessions_providers.dart';
import 'package:smartbed_app/features/sessions/sessions_screen.dart';

/// Cấu hình tối thiểu để cả 2 tab render mà không đụng mạng: radar snapshot trả
/// giá trị tĩnh, sessions trả rỗng (sẽ hiện empty state), MQTT config mặc định.
Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    appConfigProvider.overrideWith(
      (ref) async => const AppConfig(
          baseUrl: 'http://x', deviceId: 'TEST000001', devToken: 't'),
    ),
    sharedPrefsProvider.overrideWithValue(prefs),
    radarSnapshotProvider.overrideWith((ref) async* {
      yield const Snapshot(
        present: true,
        occupied: true,
        acDesired: true,
        lastMotionTs: 0,
        lastPresenceTs: 0,
        lastAcCmd: 'on',
      );
    }),
    radarEventsProvider.overrideWith((ref) async => const []),
    radarWsConnectedProvider.overrideWith((ref) async* {
      yield false;
    }),
    radarMqttConnectedProvider.overrideWith((ref) async* {
      yield false;
    }),
    radarDeviceStatesProvider.overrideWith((ref) async* {
      yield const {};
    }),
    radarDiscoveredTopicsProvider.overrideWith((ref) async* {
      yield const [];
    }),
  ];
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: await _overrides(),
      child: MaterialApp.router(routerConfig: buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => initializeDateFormatting('vi'));

  testWidgets('bottom nav has 2 tabs: Giấc ngủ + Radar', (tester) async {
    await _pumpApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    // NavigationBar label + AppBar title của SessionsScreen cùng chữ "Giấc ngủ".
    expect(find.text('Giấc ngủ'), findsNWidgets(2));
    expect(find.text('Radar'), findsOneWidget);
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('switching to Radar tab shows the radar home (hero + AC)',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Radar'));
    await tester.pumpAndSettle();

    expect(find.byType(RadarRootScreen), findsOneWidget);
    // Snapshot đang trả occupied=true → hero hiện "Có người", AC "Bật".
    expect(find.text('Có người'), findsOneWidget);
    expect(find.text('Điều hoà'), findsWidgets);
  });

  testWidgets('radar home shows empty-state stats when events are empty',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Radar'));
    await tester.pumpAndSettle();

    expect(find.text('Hôm nay'), findsOneWidget);
  });
}
