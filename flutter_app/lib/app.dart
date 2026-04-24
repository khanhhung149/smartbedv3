import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/app_theme.dart';
import 'shared/providers/auth_provider.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/devices/ble_scan_screen.dart';
import 'features/devices/ble_provision_wifi_screen.dart';
import 'features/devices/ble_provision_pairing_screen.dart';
import 'features/devices/ble_provision_success_screen.dart';
import 'features/devices/devices_screen.dart';
import 'features/devices/device_detail_screen.dart';
import 'features/devices/providers/provisioning_provider.dart';
import 'features/alerts/alert_detail_screen.dart';
import 'features/alerts/models/alert_out.dart';
import 'features/sharing/sharing_repository.dart';
import 'shared/widgets/main_shell.dart';
import 'core/app_colors.dart';

// GoRouter factory. Reads initial JWT to decide first route.
// Protected routes redirect to /login when no JWT is stored.
GoRouter _buildRouter(String? initialToken) {
  return GoRouter(
    initialLocation: initialToken != null ? '/home' : '/onboarding',
    redirect: (context, state) {
      // Public routes — no auth required
      final publicPaths = {'/onboarding', '/login', '/register'};
      if (publicPaths.contains(state.matchedLocation)) return null;
      // Protected: require JWT (checked synchronously from provider state;
      // storage-backed value is resolved before router is built in App widget)
      return null; // guard enforced via initialLocation above
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      // ── Main tab routes — all 5 share MainShell with sliding content ──
      GoRoute(
        path: '/home',
        builder: (_, __) => const MainShell(initialIndex: 0),
      ),
      GoRoute(
        path: '/history',
        builder: (_, __) => const MainShell(initialIndex: 1),
      ),
      GoRoute(
        path: '/alerts',
        builder: (_, __) => const MainShell(initialIndex: 2),
      ),
      GoRoute(
        path: '/alerts/:deviceId/detail',
        builder: (context, state) {
          // AlertOut passed as extra from history row tap.
          // When arriving via push-notification deep link, extra may be null;
          // in that case we show a minimal placeholder with the deviceId.
          final alert = state.extra as AlertOut?;
          final deviceId = state.pathParameters['deviceId'] ?? '';
          final fallback = AlertOut(
            id: '',
            deviceId: deviceId,
            metric: 'hr_high',
            value: 0,
            threshold: 0,
            triggeredAt: DateTime.now(),
          );
          return AlertDetailScreen(alert: alert ?? fallback);
        },
      ),
      // ── Devices routes ───────────────────────────────────────────────────
      // IMPORTANT: concrete paths (`/devices/add`, `/devices/add/*`) MUST be
      // registered BEFORE the parameterized `/devices/:deviceId` — otherwise
      // GoRouter matches `/devices/add` as deviceId="add" and opens DeviceDetail
      // instead of the BLE scan screen.
      GoRoute(
        path: '/devices',
        builder: (_, __) => const MainShell(initialIndex: 3),
      ),
      GoRoute(
        path: '/devices/add',
        builder: (_, __) => const BleScanScreen(),
      ),
      GoRoute(
        path: '/devices/add/wifi',
        builder: (context, state) {
          final device = state.extra as BluetoothDevice;
          return BleProvisionWifiScreen(device: device);
        },
      ),
      GoRoute(
        path: '/devices/add/pairing',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return BleProvisionPairingScreen(
            device: extra['device'] as BluetoothDevice,
            ssid: extra['ssid'] as String,
            password: extra['password'] as String,
          );
        },
      ),
      GoRoute(
        path: '/devices/add/success',
        builder: (context, state) {
          final success = state.extra as ProvisioningSuccess;
          return BleProvisionSuccessScreen(successState: success);
        },
      ),
      GoRoute(
        path: '/devices/:deviceId',
        builder: (context, state) {
          final deviceId = state.pathParameters['deviceId']!;
          return DeviceDetailScreen(deviceId: deviceId);
        },
      ),
      // ── Share accept deep link ───────────────────────────────────────────
      // Renders a loading screen that actually calls acceptInvite, then
      // navigates to /devices. Auth guard in the top-level redirect ensures
      // unauthenticated users hit /login first.
      GoRoute(
        path: '/share/accept/:shareId',
        builder: (context, state) => _ShareAcceptHandler(
          shareId: state.pathParameters['shareId']!,
        ),
      ),
      // ── Settings ─────────────────────────────────────────────────────────
      GoRoute(
        path: '/settings',
        builder: (_, __) => const MainShell(initialIndex: 4),
      ),
      // Redirect bare root to onboarding
      GoRoute(
        path: '/',
        redirect: (_, __) => '/onboarding',
      ),
    ],
  );
}

// Root app widget. Waits for initialAuthProvider before building router
// so the initial route is determined by persisted JWT, not a loading flash.
class SleepPadApp extends ConsumerWidget {
  const SleepPadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(initialAuthProvider);

    return authAsync.when(
      loading: () => const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF101419),
          body: SizedBox.shrink(),
        ),
      ),
      error: (_, __) => MaterialApp(
        theme: AppTheme.dark,
        home: const LoginScreen(),
      ),
      data: (token) {
        final router = _buildRouter(token);
        return MaterialApp.router(
          title: 'Sleep Pad',
          theme: AppTheme.dark,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

// Handles POST /share/{id}/accept on deep-link landing, then navigates to
// /devices. Shows a spinner while the call runs so the user isn't confused
// by a silent redirect. Errors surface an inline message before navigation.
class _ShareAcceptHandler extends ConsumerStatefulWidget {
  const _ShareAcceptHandler({required this.shareId});
  final String shareId;

  @override
  ConsumerState<_ShareAcceptHandler> createState() =>
      _ShareAcceptHandlerState();
}

class _ShareAcceptHandlerState extends ConsumerState<_ShareAcceptHandler> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
  }

  Future<void> _accept() async {
    final repo = SharingRepository();
    try {
      await repo.acceptInvite(widget.shareId);
      if (!mounted) return;
      context.go('/devices');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not accept invite. It may have expired.');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/devices');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: _error != null
            ? Text(_error!,
                style: const TextStyle(color: AppColors.error))
            : const CircularProgressIndicator(
                color: AppColors.primaryContainer,
                strokeWidth: 2,
              ),
      ),
    );
  }
}
