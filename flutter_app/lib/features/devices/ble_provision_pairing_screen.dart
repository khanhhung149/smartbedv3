import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'providers/provisioning_provider.dart';

// Screen 3 of BLE provisioning — shows pairing progress with 4 step bullets
// and a sweeping ring animation while the state machine runs.
// Merges ble_provisioning_pairing + device_pairing_progress (identical layout,
// same 4 steps, different ring sizes — using device_pairing_progress ring spec
// with SVG-style progress ring via CustomPainter).
// Decision: single screen, no separate device_pairing_progress_screen.dart.
// Receives {device, ssid, password} map via GoRouter extra.
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

    // Kick off provisioning after first frame so widget tree is built
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

    // Navigate on terminal states
    ref.listen<ProvisioningState>(provisioningProvider, (_, next) {
      if (next is ProvisioningSuccess) {
        context.pushReplacement('/devices/add/success', extra: next);
      } else if (next is ProvisioningFailure) {
        _showFatalErrorAndPop(context, next.reason);
      } else if (next is ProvisioningWifiFailedRetryable) {
        _showRetrySheet(
          context,
          title: 'WiFi connection failed',
          reason:
              "We couldn't connect to \"${next.lastSsid}\". Double-check the "
              'network name and password. The device is still waiting — '
              'no need to rescan.',
          lastSsid: next.lastSsid,
        );
      } else if (next is ProvisioningMqttFailedRetryable) {
        _showRetrySheet(
          context,
          title: 'Server unreachable',
          reason:
              'WiFi is connected but the server at '
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
            _AppBar(onBack: () {
              ref.read(provisioningProvider.notifier).reset();
              context.pop();
            }),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                child: Column(
                  children: [
                    // Sweeping progress ring with bluetooth icon
                    _PairingRing(controller: _ringController),
                    const SizedBox(height: 48),
                    // Headline
                    Text(
                      'Pairing with your device...',
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
                    // 4-step status checklist
                    _StepList(state: state),
                    const SizedBox(height: 32),
                    Text(
                      'This usually takes 10\u201330 seconds',
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

  // Fatal path: BLE session lost, can't retry in place — user must restart.
  void _showFatalErrorAndPop(BuildContext context, String reason) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Provisioning failed',
            style: GoogleFonts.inter(
                color: AppColors.onSurface,
                fontWeight: AppFontWeight.semiBold)),
        content: Text(reason,
            style: GoogleFonts.inter(
                color: AppColors.onSurfaceVariant, fontSize: AppTextSize.sm)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(provisioningProvider.notifier).reset();
              context.go('/devices');
            },
            child: Text('Back to devices',
                style: GoogleFonts.inter(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // Retry path: BLE still alive, user edits WiFi + retries without rescan.
  void _showRetrySheet(
    BuildContext context, {
    required String title,
    required String reason,
    required String lastSsid,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RetrySheet(
        title: title,
        reason: reason,
        initialSsid: lastSsid,
        onRetry: (ssid, password) {
          Navigator.of(context).pop();
          ref.read(provisioningProvider.notifier).retryWithCreds(
                ssid: ssid,
                password: password,
              );
        },
        onCancel: () async {
          Navigator.of(context).pop();
          await ref.read(provisioningProvider.notifier).cancel();
          if (context.mounted) context.go('/devices');
        },
      ),
    );
  }
}

// ── Retry bottom sheet ──────────────────────────────────────────────────────

class _RetrySheet extends StatefulWidget {
  const _RetrySheet({
    required this.title,
    required this.reason,
    required this.initialSsid,
    required this.onRetry,
    required this.onCancel,
  });

  final String title;
  final String reason;
  final String initialSsid;
  final void Function(String ssid, String password) onRetry;
  final VoidCallback onCancel;

  @override
  State<_RetrySheet> createState() => _RetrySheetState();
}

class _RetrySheetState extends State<_RetrySheet> {
  late final TextEditingController _ssid =
      TextEditingController(text: widget.initialSsid);
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xl,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
              )),
          const SizedBox(height: 8),
          Text(widget.reason,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              )),
          const SizedBox(height: 20),
          TextField(
            controller: _ssid,
            style: GoogleFonts.inter(color: AppColors.onSurface),
            decoration: _decoration('WiFi name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            style: GoogleFonts.inter(color: AppColors.onSurface),
            decoration: _decoration('WiFi password').copyWith(
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                    color: AppColors.onSurfaceVariant, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text('Cancel',
                    style: GoogleFonts.inter(color: AppColors.onSurface)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () {
                  final s = _ssid.text.trim();
                  final p = _password.text;
                  if (s.isEmpty || p.isEmpty) return;
                  widget.onRetry(s, p);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Retry',
                    style: GoogleFonts.inter(fontWeight: AppFontWeight.semiBold)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  const _AppBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surfaceContainerLowest.withValues(alpha: 0.7),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Opacity(
              opacity: 0.6,
              child: Icon(
                Icons.arrow_back,
                color: AppColors.secondary,
                size: 24,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Setup Sleep Pad',
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.semiBold,
                    color: const Color(0xFFE6EDF3),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'STEP 2 OF 3',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.secondary.withValues(alpha: 0.6),
                    fontWeight: AppFontWeight.medium,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

// Circular progress ring with sweeping stroke + bluetooth icon in center.
// Matches device_pairing_progress SVG ring: r=46, strokeDasharray=289,
// strokeDashoffset=144 (50% fill).
class _PairingRing extends StatelessWidget {
  const _PairingRing({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sweeping ring via CustomPaint
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) => CustomPaint(
              size: const Size(200, 200),
              painter: _RingPainter(progress: controller.value),
            ),
          ),
          // Central icon
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.bluetooth_searching,
              color: AppColors.primaryContainer,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }
}

// Draws background track + animated sweep arc for the pairing ring.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background track
    final trackPaint = Paint()
      ..color = AppColors.surfaceContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, trackPaint);

    // Sweep arc
    final sweepPaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.primaryContainer, AppColors.primary],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const startAngle = -1.5707963; // -90 degrees
    const sweepAngle = 3.141592; // 180 degrees sweep (half circle always visible)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + progress * 6.283185, // full rotation
      sweepAngle,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ── Step list ───────────────────────────────────────────────────────────────

enum _StepStatus { done, active, pending }

class _StepList extends StatelessWidget {
  const _StepList({required this.state});
  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final steps = _resolveSteps(state);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepItem(label: steps[i].label, status: steps[i].status),
            if (i < steps.length - 1) const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  List<({String label, _StepStatus status})> _resolveSteps(
      ProvisioningState s) {
    // Map state machine states to step statuses
    final isDone = s is ProvisioningSuccess;
    final isFailed = s is ProvisioningFailure;

    bool wifiDone = isDone ||
        s is ProvisioningConnectingWifi ||
        s is ProvisioningConnectingMqtt;
    bool wifiActive = s is ProvisioningFetchingDeviceId ||
        s is ProvisioningSelected ||
        s is ProvisioningPairedWithBackend;
    bool connectingActive = s is ProvisioningConnectingWifi;
    bool mqttActive = s is ProvisioningConnectingMqtt;
    bool mqttDone = isDone;
    final finalizingDone = isDone;

    if (isFailed) {
      // Show progress frozen at current step on failure
      wifiDone = false;
      wifiActive = false;
    }

    return [
      (
        label: 'Saved WiFi credentials',
        status: wifiDone
            ? _StepStatus.done
            : (wifiActive ? _StepStatus.active : _StepStatus.done),
      ),
      (
        label: 'Connecting to WiFi',
        status: connectingActive
            ? _StepStatus.active
            : (wifiDone || mqttActive || mqttDone
                ? _StepStatus.done
                : _StepStatus.pending),
      ),
      (
        label: 'Connecting to server',
        status: mqttActive
            ? _StepStatus.active
            : (mqttDone ? _StepStatus.done : _StepStatus.pending),
      ),
      (
        label: 'Finalizing',
        status: finalizingDone ? _StepStatus.done : _StepStatus.pending,
      ),
    ];
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.label, required this.status});
  final String label;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepIcon(status: status),
        const SizedBox(width: 16),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: AppTextSize.lg,
            fontWeight: AppFontWeight.medium,
            color: switch (status) {
              _StepStatus.done => AppColors.onSurface,
              _StepStatus.active => AppColors.primaryContainer,
              _StepStatus.pending =>
                AppColors.onSurface.withValues(alpha: 0.4),
            },
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.status});
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _StepStatus.done => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            color: AppColors.primaryContainer,
            size: 18,
          ),
        ),
      _StepStatus.active => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primaryContainer,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D5EE7DF), // rgba(94,231,223,0.3)
                blurRadius: 12,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      _StepStatus.pending => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.outlineVariant,
              width: 2,
            ),
          ),
        ),
    };
  }
}
