import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/realtime/realtime_screen.dart';
import '../features/radar/radar_root_screen.dart';
import '../features/radar/screens/settings_screen.dart';
import '../features/session_detail/session_detail_screen.dart';
import '../features/sessions/sessions_screen.dart';
import '../features/settings/settings_screen.dart';

/// Bottom nav 2 tab: Giấc ngủ (sessions) + Radar (presence/AC). Hai nhánh con
/// giữ state riêng qua indexed stack; chi tiết phiên/cài đặt push chồng lên.
GoRouter buildRouter() => GoRouter(
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => _AppShell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const SessionsScreen(),
                  routes: [
                    GoRoute(
                      path: 'session/:id',
                      builder: (context, state) => SessionDetailScreen(
                          sessionId: state.pathParameters['id']!),
                    ),
                    GoRoute(
                      path: 'settings',
                      builder: (context, state) => const SettingsScreen(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/realtime',
                  builder: (context, state) => const RealtimeScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/radar',
                  builder: (context, state) => const RadarRootScreen(),
                  routes: [
                    GoRoute(
                      path: 'settings',
                      builder: (context, state) => const RadarSettingsScreen(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// Scaffold dùng chung cho 2 tab — NavigationBar M3 tối, giữ nguyên state từng tab.
class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(
          i,
          initialLocation: i == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime),
            label: 'Giấc ngủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Trực tiếp',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Radar',
          ),
        ],
      ),
    );
  }
}
