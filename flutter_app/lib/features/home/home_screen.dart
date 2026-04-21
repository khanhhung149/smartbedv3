import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../data/models/realtime_data.dart';
import '../data/providers/realtime_provider.dart';
import '../data/providers/selected_device_provider.dart';
import 'device_selector_sheet.dart';
import 'home_secondary_metrics.dart';

// Home screen: realtime dashboard driven by WS stream.
// Source: sleep_pad_home_final_sync/code.html
// Layout: sticky translucent app bar → status hero → primary metric cards →
//         2×2 secondary grid → canonical AppBottomNav.

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
          return _NoDeviceScaffold(onAddDevice: () => context.push('/devices/add'));
        }
        // Key on deviceId so _HomeContent state (including sparkline buffers)
        // resets cleanly when the user switches devices — no readings bleed
        // across devices.
        return _HomeContent(
          key: ValueKey(device.deviceId),
          deviceName: device.name,
          deviceId: device.deviceId,
          onDeviceTap: _openDeviceSheet,
        );
      },
    );
  }
}

// ── No device state ──────────────────────────────────────────────────────────

class _NoDeviceScaffold extends StatelessWidget {
  const _NoDeviceScaffold({required this.onAddDevice});
  final VoidCallback onAddDevice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.sensors_off,
                size: 48, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No device paired',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a Sleep Pad device to get started.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAddDevice,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
              ),
              child: Text('Add Device', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main content (device selected) ──────────────────────────────────────────

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({
    super.key,
    required this.deviceName,
    required this.deviceId,
    required this.onDeviceTap,
  });

  final String deviceName;
  final String deviceId;
  final VoidCallback onDeviceTap;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  // Sparkline buffers live here — reset automatically when parent rebuilds
  // with a new ValueKey(deviceId).
  final List<double> _hrHistory = [];
  final List<double> _rrHistory = [];
  static const int _sparklineMax = 60;
  RealtimeData? _latest;

  @override
  Widget build(BuildContext context) {
    // ref.listen is called inside build but does NOT cause unnecessary
    // rebuilds — it schedules the callback outside the build phase, so
    // setState inside is safe.
    ref.listen<AsyncValue<RealtimeData>>(
      realtimeProvider(widget.deviceId),
      (previous, next) {
        next.whenData((data) {
          if (!mounted) return;
          setState(() {
            _latest = data;
            if (data.hr != null) {
              _hrHistory.add(data.hr!);
              if (_hrHistory.length > _sparklineMax) _hrHistory.removeAt(0);
            }
            if (data.rr != null) {
              _rrHistory.add(data.rr!);
              if (_rrHistory.length > _sparklineMax) _rrHistory.removeAt(0);
            }
          });
        });
      },
    );
    final streamAsync = ref.watch(realtimeProvider(widget.deviceId));

    final isConnected = streamAsync is! AsyncError;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(widget.deviceName, widget.onDeviceTap),
      body: Column(
        children: [
          // Offline banner
          if (streamAsync is AsyncError)
            _OfflineBanner(message: 'Reconnecting to ${widget.deviceName}…'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top padding to clear sticky app bar (approx 80px)
                  const SizedBox(height: 80),
                  // Status hero band
                  StatusHero(
                    statusCode: _latest?.statusCode,
                    subtitle: isConnected
                        ? 'Device active & monitoring'
                        : 'Signal lost — reconnecting',
                  ),
                  const SizedBox(height: 24),
                  // Primary metric cards (bento 2-col on wide, stacked on narrow)
                  LayoutBuilder(builder: (context, constraints) {
                    if (constraints.maxWidth >= 480) {
                      return Row(
                        children: [
                          Expanded(
                            child: MetricCard(
                              label: 'HEART RATE',
                              value: _latest?.hr,
                              unit: 'bpm',
                              icon: Symbols.favorite,
                              accentColor: AppColors.primaryContainer, // #5EE7DF
                              sparklineValues: List.of(_hrHistory),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: MetricCard(
                              label: 'RESPIRATION',
                              value: _latest?.rr,
                              unit: 'rpm',
                              icon: Symbols.air,
                              accentColor: AppColors.secondary, // #D4BBFF
                              sparklineValues: List.of(_rrHistory),
                            ),
                          ),
                        ],
                      );
                    }
                    // Narrow: stack vertically
                    return Column(
                      children: [
                        MetricCard(
                          label: 'HEART RATE',
                          value: _latest?.hr,
                          unit: 'bpm',
                          icon: Symbols.favorite,
                          accentColor: AppColors.primaryContainer,
                          sparklineValues: List.of(_hrHistory),
                        ),
                        const SizedBox(height: 16),
                        MetricCard(
                          label: 'RESPIRATION',
                          value: _latest?.rr,
                          unit: 'rpm',
                          icon: Symbols.air,
                          accentColor: AppColors.secondary,
                          sparklineValues: List.of(_rrHistory),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 24),
                  // Secondary 2×2 grid
                  HomeSecondaryMetrics(data: _latest),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0, // Home active
        onTap: (i) => _handleNavTap(context, i),
      ),
    );
  }
}

// ── App bar ──────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(
  String deviceName,
  VoidCallback onDeviceTap,
) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(72),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 72,
          color: const Color(0xB3101419), // #101419/70
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                // Left: menu icon
                IconButton(
                  icon: const Icon(Symbols.menu,
                      color: Color(0xFF8B96A5), size: 24),
                  onPressed: () {},
                ),
                // Center: title + device chip
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sleep Pad',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE6EDF3),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: onDeviceTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2E2F),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF234241),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                deviceName,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primaryContainer,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Symbols.arrow_drop_down,
                                size: 14,
                                color: AppColors.primaryContainer,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Right: notifications with dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Symbols.notifications,
                          color: Color(0xFF8B96A5), size: 24),
                      onPressed: () {},
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.error, // #ffb4ab
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.background,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Offline banner ───────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.errorContainer.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.onErrorContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── Nav tap handler ──────────────────────────────────────────────────────────

void _handleNavTap(BuildContext context, int index) {
  switch (index) {
    case 0:
      break; // already on Home
    case 1:
      context.go('/history');
    case 2:
      context.go('/alerts');
    case 3:
      context.go('/devices');
    case 4:
      context.go('/settings');
  }
}
