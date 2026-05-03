import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'ble_pairing_app_bar.dart';
import 'ble_pairing_dialogs.dart';
import 'ble_pairing_progress_checklist.dart';
import 'ble_pairing_ring_animation.dart';
import 'providers/provisioning_provider.dart';
import '../../l10n/app_localizations.dart';

// Screen 3 of BLE provisioning — pairing progress with 4-step checklist
// and a sweeping ring animation while the state machine runs.
// Receives {device, ssid, password} via GoRouter extra.
class BleProvisionPairingScreen extends ConsumerStatefulWidget {
  const BleProvisionPairingScreen({
    super.key,
    required this.device,
    required this.ssid,
    required this.password,
  });

  final BluetoothDevice device;
  final String ssid;
  final String password;

  @override
  ConsumerState<BleProvisionPairingScreen> createState() =>
      _BleProvisionPairingScreenState();
}

class _BleProvisionPairingScreenState
    extends ConsumerState<BleProvisionPairingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Kick off provisioning after first frame so widget tree is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(provisioningProvider.notifier).startProvisioning(
            device: widget.device,
            ssid: widget.ssid,
            wifiPassword: widget.password,
          );
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(provisioningProvider);

    ref.listen<ProvisioningState>(provisioningProvider, (_, next) {
      if (next is ProvisioningSuccess) {
        context.pushReplacement('/devices/add/success', extra: next);
      } else if (next is ProvisioningFailure) {
        _showFatalError(context, next.reason);
      } else if (next is ProvisioningWifiFailedRetryable) {
        _showRetrySheet(
          context,
          title: 'WiFi connection failed',
          reason: "We couldn't connect to \"${next.lastSsid}\". Double-check "
              'the network name and password. The device is still waiting — '
              'no need to rescan.',
          lastSsid: next.lastSsid,
        );
      } else if (next is ProvisioningMqttFailedRetryable) {
        _showRetrySheet(
          context,
          title: 'Server unreachable',
          reason: 'WiFi is connected but the server at '
              '${next.pairOut.mqttHost} is not responding. Check your server '
              'URL in Settings, or try different WiFi.',
          lastSsid: next.lastSsid,
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            BlePairingAppBar(onBack: () {
              ref.read(provisioningProvider.notifier).reset();
              context.pop();
            }),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                child: Column(
                  children: [
                    BlePairingRing(controller: _ringController),
                    const SizedBox(height: 48),
                    Text(
                      AppLocalizations.of(context)!.pairingWithDevice,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.xl4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 40),
                    BlePairingProgressChecklist(state: state),
                    const SizedBox(height: 32),
                    Text(
                      AppLocalizations.of(context)!.pairingDuration,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.sm,
                        color: AppColors.outline,
                        fontWeight: AppFontWeight.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fatal path: BLE session lost, must restart from device scan.
  void _showFatalError(BuildContext context, String reason) {
    showBlePairingFatalError(context, reason, onBack: () {
      Navigator.of(context).pop();
      ref.read(provisioningProvider.notifier).reset();
      context.go('/devices');
    });
  }

  // Retry path: BLE still alive, user edits WiFi credentials and retries.
  void _showRetrySheet(
    BuildContext context, {
    required String title,
    required String reason,
    required String lastSsid,
  }) {
    showBlePairingRetrySheet(
      context,
      title: title,
      reason: reason,
      lastSsid: lastSsid,
      onRetry: (ssid, password) {
        ref.read(provisioningProvider.notifier).retryWithCreds(
              ssid: ssid,
              password: password,
            );
      },
      onCancel: () async {
        await ref.read(provisioningProvider.notifier).cancel();
        if (context.mounted) context.go('/devices');
      },
    );
  }
}
