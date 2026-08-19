import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../data/providers/selected_device_provider.dart';
import 'alerts_app_bar.dart';
import 'alerts_body.dart';
import '../../l10n/app_localizations.dart';

// Alerts screen: device guard → two tabs (Thresholds | History).
// Source: alerts_settings/code.html + alerts_history_dark_mode_fix/code.html
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  int _tab = 0; // 0 = Thresholds, 1 = History

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(selectedDeviceProvider);

    return deviceAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(
                color: AppColors.primaryContainer, strokeWidth: 2)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: Text('Error: $e',
                style: GoogleFonts.inter(color: AppColors.error))),
      ),
      data: (device) {
        if (device == null) {
          return _NoDeviceBody(onAddDevice: () => context.push('/devices/add'));
        }
        return AlertsBody(
          key: ValueKey(device.deviceId),
          deviceId: device.deviceId,
          deviceName: device.displayName,
          selectedTab: _tab,
          onTabChanged: (i) => setState(() => _tab = i),
        );
      },
    );
  }
}

// ── No device placeholder ─────────────────────────────────────────────────────

class _NoDeviceBody extends StatelessWidget {
  const _NoDeviceBody({required this.onAddDevice});
  final VoidCallback onAddDevice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: buildAlertsAppBar(context),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.notifications_off,
                size: 48, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.noDevicePaired,
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    fontWeight: AppFontWeight.semiBold,
                    color: AppColors.onSurface)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAddDevice,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
              ),
              child: Text(AppLocalizations.of(context)!.addDevice, style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }
}
