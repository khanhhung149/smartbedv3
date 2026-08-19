import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/analytics_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/pill_nav.dart';

/// Root của tab Radar: tự quản lý 4 màn con qua PillNav (giữ state từng tab bằng
/// IndexedStack). Cài đặt radar nằm trong SettingsScreen chung của app.
class RadarRootScreen extends ConsumerStatefulWidget {
  const RadarRootScreen({super.key});

  @override
  ConsumerState<RadarRootScreen> createState() => _RadarRootScreenState();
}

class _RadarRootScreenState extends ConsumerState<RadarRootScreen> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    DevicesScreen(),
    AnalyticsScreen(),
    HistoryScreen(),
  ];

  static const _items = [
    NavItem(Icons.grid_view_rounded, 'Tổng quan'),
    NavItem(Icons.sensors_rounded, 'Thiết bị'),
    NavItem(Icons.insights_rounded, 'Phân tích'),
    NavItem(Icons.history_rounded, 'Lịch sử'),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(radarDevicePollBinderProvider); // giữ poll MQTT sống suốt app
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: PillNav(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: _items,
      ),
    );
  }
}
