import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../data/providers/selected_device_provider.dart';
import 'device_selector_sheet.dart';
import 'home_content.dart';
import 'home_no_device_view.dart';

// Home screen: device guard → realtime dashboard.
// Source: sleep_pad_home_final_sync/code.html
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  void _openDeviceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const DeviceSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(selectedDeviceProvider);

    return deviceAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryContainer,
            strokeWidth: 2,
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            'Failed to load device: $e',
            style: GoogleFonts.inter(color: AppColors.error),
          ),
        ),
      ),
      data: (device) {
        if (device == null) {
          return HomeNoDeviceView(
              onAddDevice: () => context.push('/devices/add'));
        }
        // Key on deviceId so HomeContent state (sparkline buffers) resets
        // cleanly when user switches devices — no readings bleed across devices.
        return HomeContent(
          key: ValueKey(device.deviceId),
          deviceName: device.displayName,
          deviceId: device.deviceId,
          onDeviceTap: _openDeviceSheet,
        );
      },
    );
  }
}
