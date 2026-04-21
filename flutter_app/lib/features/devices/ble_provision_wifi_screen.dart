import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';

// Screen 2 of BLE provisioning — user enters WiFi SSID + password.
// Matches ble_provisioning_wifi/code.html: wifi icon hero, glass inputs, CTA.
// Receives BluetoothDevice via GoRouter extra parameter.
class BleProvisionWifiScreen extends ConsumerStatefulWidget {
  const BleProvisionWifiScreen({super.key, required this.device});

  final BluetoothDevice device;

  @override
  ConsumerState<BleProvisionWifiScreen> createState() =>
      _BleProvisionWifiScreenState();
}

class _BleProvisionWifiScreenState
    extends ConsumerState<BleProvisionWifiScreen>
    with SingleTickerProviderStateMixin {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _ssidError;
  String? _passwordError;

  // Pulse animation for the wifi icon rings
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _ssidError =
          _ssidController.text.trim().isEmpty ? 'Network name is required' : null;
      _passwordError = null; // password may be empty (open networks)
    });
    return _ssidError == null;
  }

  void _onContinue() {
    if (!_validate()) return;
    context.push(
      '/devices/add/pairing',
      extra: {
        'device': widget.device,
        'ssid': _ssidController.text.trim(),
        'password': _passwordController.text,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(onBack: () => context.pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // Wifi icon with pulsing rings
                    _WifiHero(pulseAnim: _pulseAnim),
                    const SizedBox(height: 40),
                    // Title + subtitle
                    Text(
                      'Give your Sleep Pad WiFi',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.xl3,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your Sleep Pad will use this network to send data to the cloud.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.sm,
                        color: AppColors.secondary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 48),
                    // SSID input
                    _GlassInput(
                      controller: _ssidController,
                      hint: 'Network Name (SSID)',
                      prefixIcon: Icons.router_outlined,
                      errorText: _ssidError,
                      onChanged: (_) {
                        if (_ssidError != null) {
                          setState(() => _ssidError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    // Password input
                    _GlassInput(
                      controller: _passwordController,
                      hint: 'Password',
                      prefixIcon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      showToggle: true,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      errorText: _passwordError,
                    ),
                    const SizedBox(height: 64),
                    PrimaryButton(label: 'Continue', onPressed: _onContinue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      color: AppColors.background.withValues(alpha: 0.7),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(
              Icons.arrow_back,
              color: AppColors.secondary,
              size: 24,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Setup Sleep Pad',
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.lg,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '1 OF 3',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.secondary,
                    letterSpacing: 1.2,
                    fontWeight: AppFontWeight.medium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24), // spacer to balance back button
        ],
      ),
    );
  }
}

class _WifiHero extends StatelessWidget {
  const _WifiHero({required this.pulseAnim});
  final Animation<double> pulseAnim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer pulse ring
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Opacity(
              opacity: pulseAnim.value * 0.2,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          // Inner pulse ring
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Opacity(
              opacity: pulseAnim.value * 0.1,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          // Background circle
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi,
              color: AppColors.primary,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  const _GlassInput({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.showToggle = false,
    this.onToggle,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final bool showToggle;
  final VoidCallback? onToggle;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: AppRadius.defaultBr,
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            onChanged: onChanged,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.base,
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                fontSize: AppTextSize.base,
                color: AppColors.secondary.withValues(alpha: 0.5),
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(prefixIcon, color: AppColors.secondary, size: 20),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 52),
              suffixIcon: showToggle
                  ? IconButton(
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                      onPressed: onToggle,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: AppRadius.defaultBr,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.defaultBr,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.defaultBr,
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xs,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
