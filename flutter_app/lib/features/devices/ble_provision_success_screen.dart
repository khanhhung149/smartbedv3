import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../data/providers/selected_device_provider.dart';
import '../sharing/providers/sharing_providers.dart';
import 'providers/devices_list_provider.dart';
import 'providers/provisioning_provider.dart';

// Screen 4 of BLE provisioning — success state with device name input.
// Matches ble_provisioning_success/code.html:
//   large check_circle hero + ripple rings + Device ID badge + name input + CTA.
// Receives ProvisioningSuccess via GoRouter extra.
class BleProvisionSuccessScreen extends ConsumerStatefulWidget {
  const BleProvisionSuccessScreen({super.key, required this.successState});

  final ProvisioningSuccess successState;

  @override
  ConsumerState<BleProvisionSuccessScreen> createState() =>
      _BleProvisionSuccessScreenState();
}

class _BleProvisionSuccessScreenState
    extends ConsumerState<BleProvisionSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final AnimationController _rippleController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: "New Device");
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  Future<void> _onSaveAndGoHome() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(provisioningProvider.notifier).renameDevice(
            deviceId: widget.successState.deviceId,
            newName: name,
          );
    } finally {
      if (mounted) {
        // Invalidate all device-related providers so Home/History/Alerts pick
        // up the newly-paired device instead of their previously cached empty
        // state.  selectedDeviceProvider is the critical one — its cached
        // "no device" value is what makes those tabs show empty after pair.
        ref.read(provisioningProvider.notifier).reset();
        ref.invalidate(devicesListProvider);
        ref.invalidate(selectedDeviceProvider);
        ref.invalidate(mySharedDevicesProvider);
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: SafeArea(
        child: Stack(
          children: [
            // Ambient glow
            Positioned(
              top: MediaQuery.of(context).size.height * 0.15,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 256,
                  height: 256,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  ),
                  // blur via IgnorePointer so it doesn't intercept taps
                ),
              ),
            ),
            Column(
              children: [
                _AppBar(onBack: () => context.pop()),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 160),
                    child: Column(
                      children: [
                        // Hero checkmark with ripple rings
                        _SuccessHero(controller: _rippleController),
                        const SizedBox(height: 48),
                        // Typography block
                        Text(
                          'Sleep Pad is ready',
                          style: GoogleFonts.inter(
                            fontSize: AppTextSize.xl4,
                            fontWeight: AppFontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Device ID badge
                        _DeviceIdBadge(
                          deviceId: widget.successState.deviceId,
                        ),
                        const SizedBox(height: 64),
                        // Name input
                        _NameInput(controller: _nameController),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Fixed bottom CTA
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomCta(
                onTap: _isSaving ? null : _onSaveAndGoHome,
                isLoading: _isSaving,
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
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(
              Icons.arrow_back,
              color: AppColors.navInactive,
              size: 24,
            ),
          ),
          Text(
            'Setup Sleep Pad',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.lg,
              fontWeight: AppFontWeight.bold,
              color: const Color(0xFFE6EDF3),
              letterSpacing: -0.3,
            ),
          ),
          Text(
            '3 of 3',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              fontWeight: AppFontWeight.semiBold,
              color: AppColors.primaryContainer,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// Large green check_circle with two ping-style ripple rings.
// Outer ring: 160px, inner outer: 200px border per Stitch HTML.
class _SuccessHero extends StatelessWidget {
  const _SuccessHero({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ripple ring (ping)
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              // offset by 1s so rings are staggered
              final t1 = controller.value;
              final t2 = (controller.value + 0.33) % 1.0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: (1.0 - t1).clamp(0, 1),
                    child: SizedBox(
                      width: 160 + t1 * 40,
                      height: 160 + t1 * 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: (1.0 - t2).clamp(0, 1),
                    child: SizedBox(
                      width: 160 + t2 * 40,
                      height: 160 + t2 * 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Outer ring container
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.15),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 40,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x4D5EE7DF), // rgba(94,231,223,0.3)
                    blurRadius: 30,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.onPrimaryFixed,
                size: 64,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceIdBadge extends StatelessWidget {
  const _DeviceIdBadge({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.15),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.blur_on,
            color: AppColors.primaryContainer,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'Device ID: $deviceId',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.onSurfaceVariant,
              fontWeight: AppFontWeight.medium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '\u00b7',
              style: GoogleFonts.inter(color: AppColors.outline),
            ),
          ),
          Text(
            'Connected',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.primaryFixedDim,
              fontWeight: AppFontWeight.medium,
            ),
          ),
        ],
      ),
    );
  }
}

class _NameInput extends StatelessWidget {
  const _NameInput({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            'Give it a name',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              fontWeight: AppFontWeight.medium,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.lg,
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Master Bedroom',
              hintStyle: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                color: AppColors.outlineVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              suffixIcon: const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Icon(
                  Icons.edit_outlined,
                  color: AppColors.outlineVariant,
                  size: 20,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 52),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
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
      ],
    );
  }
}

class _BottomCta extends StatelessWidget {
  const _BottomCta({required this.onTap, required this.isLoading});
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x000B0F14),
            Color(0xFF0B0F14),
            Color(0xFF0B0F14),
          ],
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryContainer],
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x405EE7DF), // rgba(94,231,223,0.25)
                blurRadius: 30,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: MaterialButton(
            onPressed: onTap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            padding: EdgeInsets.zero,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimaryFixed,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Save and go home',
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.lg,
                          fontWeight: AppFontWeight.semiBold,
                          color: AppColors.onPrimaryFixed,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.home,
                        color: AppColors.onPrimaryFixed,
                        size: 20,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
