import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'providers/ble_scan_provider.dart';

// Screen 1 of BLE provisioning flow — scans for nearby SleepPad-* devices.
// Matches ble_device_scan/code.html: device cards + animated radar spinner.
class BleScanScreen extends ConsumerStatefulWidget {
  const BleScanScreen({super.key});

  @override
  ConsumerState<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends ConsumerState<BleScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;
  // Deduplicated map of device address → scan result
  final Map<String, ScanResult> _devices = {};
  // Gates stream subscription — without granted permissions, flutter_blue_plus
  // returns zero scan results silently on Android 12+, confusing the user.
  bool _permissionsGranted = false;
  bool _permissionRequested = false;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _requestBlePermissions();
  }

  Future<void> _requestBlePermissions() async {
    // iOS: flutter_blue_plus triggers the OS native Bluetooth prompt the
    // first time a scan starts (NSBluetoothAlwaysUsageDescription in
    // Info.plist). permission_handler's bluetoothScan/Connect are
    // Android-only and return denied on iOS — bypass them so the scan
    // can start and the OS prompt fires.
    if (Platform.isIOS) {
      if (!mounted) return;
      setState(() {
        _permissionsGranted = true;
        _permissionRequested = true;
      });
      return;
    }

    // Android 12+: runtime BLUETOOTH_SCAN + BLUETOOTH_CONNECT + location.
    final results = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final allGranted = results.values.every((s) => s.isGranted);
    if (!mounted) return;
    setState(() {
      _permissionsGranted = allGranted;
      _permissionRequested = true;
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _onDeviceTapped(ScanResult result) {
    FlutterBluePlus.stopScan();
    context.push('/devices/add/wifi', extra: result.device);
  }

  String _signalLabel(int rssi, AppLocalizations l10n) {
    if (rssi >= -60) return l10n.strongSignal;
    if (rssi >= -75) return l10n.moderateSignal;
    return l10n.weakSignal;
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return AppColors.primaryContainer; // teal dot — strong
    if (rssi >= -75) return AppColors.tertiaryContainer; // amber dot — moderate
    return AppColors.outline; // grey — weak
  }

  @override
  Widget build(BuildContext context) {
    // Only subscribe after permissions are granted — a BLE scan kicked off
    // without the right runtime permissions yields no results on Android 12+.
    if (_permissionsGranted) {
      ref.listen<AsyncValue<ScanResult>>(bleScanProvider, (_, next) {
        next.whenData((result) {
          if (mounted) {
            setState(() {
              _devices[result.device.remoteId.str] = result;
            });
          }
        });
      });
    }

    final l10n = AppLocalizations.of(context)!;
    final isScanning = ref.watch(bleIsScanningProvider).valueOrNull ?? false;

    final showPermissionDeniedBanner =
        _permissionRequested && !_permissionsGranted;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onClose: () => context.pop()),
            _ProgressBar(isScanning: isScanning && _permissionsGranted),
            Expanded(
              child: showPermissionDeniedBanner
                  ? _PermissionDeniedBanner(
                      onRetry: _requestBlePermissions,
                      onOpenSettings: openAppSettings,
                    )
                  : _Body(
                      devices: _devices.values.toList(),
                      isScanning: isScanning,
                      radarController: _radarController,
                      onDeviceTapped: _onDeviceTapped,
                      signalLabel: (rssi) => _signalLabel(rssi, l10n),
                      signalColor: _signalColor,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionDeniedBanner extends StatelessWidget {
  const _PermissionDeniedBanner({
    required this.onRetry,
    required this.onOpenSettings,
  });
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_disabled,
              size: 56, color: AppColors.outline),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.bluetoothPermissionNeeded,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.bluetoothPermissionDescription,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextButton(onPressed: onRetry, child: Text(AppLocalizations.of(context)!.retry)),
          TextButton(
            onPressed: onOpenSettings,
            child: Text(AppLocalizations.of(context)!.openSettings),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Close button (teal)
          _IconBtn(
            icon: Icons.close,
            color: AppColors.primaryContainer,
            onTap: onClose,
          ),
          // Title only — no subtitle needed on the scan screen.
          Text(
            AppLocalizations.of(context)!.addDevice,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.lg,
              fontWeight: AppFontWeight.semiBold,
              color: const Color(0xFFE6EDF3),
              letterSpacing: -0.3,
            ),
          ),
          // Notifications button (muted)
          _IconBtn(
            icon: Icons.notifications_outlined,
            color: AppColors.navInactive,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.isScanning});
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    // w-1/3 pulsing gradient progress bar — step 1 of 3
    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(color: AppColors.surfaceContainerHigh),
          FractionallySizedBox(
            widthFactor: 1 / 3,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.devices,
    required this.isScanning,
    required this.radarController,
    required this.onDeviceTapped,
    required this.signalLabel,
    required this.signalColor,
  });

  final List<ScanResult> devices;
  final bool isScanning;
  final AnimationController radarController;
  final void Function(ScanResult) onDeviceTapped;
  final String Function(int rssi) signalLabel;
  final Color Function(int rssi) signalColor;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (devices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 16),
              child: Text(
                AppLocalizations.of(context)!.nearbyDevices,
                style: GoogleFonts.inter(
                  fontSize: AppTextSize.xs,
                  fontWeight: AppFontWeight.medium,
                  color: AppColors.outline,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...devices.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DeviceCard(
                    result: r,
                    onTap: () => onDeviceTapped(r),
                    signalLabel: signalLabel(r.rssi),
                    signalColor: signalColor(r.rssi),
                  ),
                )),
            const SizedBox(height: 16),
          ],
          // Scanning status indicator — animated radar
          _ScanningStatus(controller: radarController),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.result,
    required this.onTap,
    required this.signalLabel,
    required this.signalColor,
  });

  final ScanResult result;
  final VoidCallback onTap;
  final String signalLabel;
  final Color signalColor;

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.advertisementData.advName;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              // Bluetooth icon in teal circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bluetooth,
                  color: AppColors.primaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.base,
                        fontWeight: AppFontWeight.bold,
                        color: const Color(0xFFE6EDF3),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: signalColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          signalLabel,
                          style: GoogleFonts.inter(
                            fontSize: AppTextSize.sm,
                            color: AppColors.navInactive,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.navInactive,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningStatus extends StatelessWidget {
  const _ScanningStatus({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.7,
        child: Column(
          children: [
            const SizedBox(height: 48),
            RotationTransition(
              turns: controller,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: const Icon(
                  Icons.radar,
                  color: AppColors.outline,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.searchingForDevices,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                fontWeight: AppFontWeight.medium,
                color: AppColors.outline,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
