import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';
import 'screens/analytics_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';
import 'widgets/pill_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nạp prefs trước khi dựng UI: baseUrl phải có sẵn ngay frame đầu, nếu không
  // app sẽ gọi backend bằng URL mặc định rồi mới đổi → nháy lỗi vô cớ.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const HomeAcApp(),
    ),
  );
}

class HomeAcApp extends StatelessWidget {
  const HomeAcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Điều hoà thông minh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _RootNav(),
    );
  }
}

class _RootNav extends ConsumerStatefulWidget {
  const _RootNav();

  @override
  ConsumerState<_RootNav> createState() => _RootNavState();
}

class _RootNavState extends ConsumerState<_RootNav> {
  int _index = 0;

  // IndexedStack giữ state các màn: đổi tab không dựng lại WS/MQTT hay tải lại lịch sử.
  static const _screens = [
    HomeScreen(),
    DevicesScreen(),
    AnalyticsScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  static const _items = [
    NavItem(Icons.grid_view_rounded, 'Tổng quan'),
    NavItem(Icons.sensors_rounded, 'Thiết bị'),
    NavItem(Icons.insights_rounded, 'Phân tích'),
    NavItem(Icons.history_rounded, 'Lịch sử'),
    NavItem(Icons.settings_rounded, 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    // Giữ liên kết poll MQTT sống suốt vòng đời app, không phụ thuộc tab đang mở.
    ref.watch(devicePollBinderProvider);
    return Scaffold(
      // extendBody để nội dung chạy dưới thanh nav nổi (các màn tự chừa padding dưới).
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
