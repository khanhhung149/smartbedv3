import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../shared/widgets/alert_bell_button.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../data/models/realtime_data.dart';
import '../data/providers/history_provider.dart';
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
          deviceName: device.displayName,
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
  final List<double> _tempHistory = [];
  // All three sparklines share a 60-point / 1-minute-bucketed window.  The
  // WS stream (per-second) appends live points on top of the preload.
  static const int _sparklineMax = 60;
  static const int _tempSparklineMax = 60;
  RealtimeData? _latest;

  @override
  void initState() {
    super.initState();
    // Preload last 1 hour from DB so sparklines (+ temp value) aren't empty
    // for the 60s it takes the first min frame to arrive.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final history = await ref
            .read(historyProvider((deviceId: widget.deviceId, range: 'hour'))
                .future);
        if (!mounted) return;
        setState(() {
          for (final p in history.points) {
            if (p.hr != null) _hrHistory.add(p.hr!);
            if (p.rr != null) _rrHistory.add(p.rr!);
            if (p.temp != null) _tempHistory.add(p.temp!);
          }
          // Pin temp to the last value so the card shows a number immediately
          // (WS min frame won't arrive for up to 60s).
          final lastTemp = history.points
              .where((p) => p.temp != null)
              .map((p) => p.temp!)
              .lastOrNull;
          if (lastTemp != null) {
            _latest = RealtimeData(
              deviceId: widget.deviceId,
              ts: 0,
              temp: lastTemp,
            );
          }
        });
      } catch (_) {
        // Preload failure is non-fatal — WS stream will fill buffers over time.
      }
    });
  }

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
            // Merge so fields present only on min frames (movement, snore,
            // temp) survive the interleaved sec frames that don't carry them.
            _latest = RealtimeData(
              deviceId: data.deviceId,
              ts: data.ts,
              hr: data.hr ?? _latest?.hr,
              rr: data.rr ?? _latest?.rr,
              sdata: data.sdata ?? _latest?.sdata,
              pdata: data.pdata ?? _latest?.pdata,
              movement: data.movement ?? _latest?.movement,
              snore: data.snore ?? _latest?.snore,
              respDisorder: data.respDisorder ?? _latest?.respDisorder,
              statusCode: data.statusCode ?? _latest?.statusCode,
              temp: data.temp ?? _latest?.temp,
            );
            if (data.hr != null) {
              _hrHistory.add(data.hr!);
              if (_hrHistory.length > _sparklineMax) _hrHistory.removeAt(0);
            }
            if (data.rr != null) {
              _rrHistory.add(data.rr!);
              if (_rrHistory.length > _sparklineMax) _rrHistory.removeAt(0);
            }
            if (data.temp != null) {
              _tempHistory.add(data.temp!);
              if (_tempHistory.length > _tempSparklineMax) {
                _tempHistory.removeAt(0);
              }
            }
          });
        });
      },
    );
    final streamAsync = ref.watch(realtimeProvider(widget.deviceId));

    final connection = switch (streamAsync) {
      AsyncError() => DeviceLinkState.disconnected,
      AsyncData() when _latest != null => DeviceLinkState.connected,
      _ => DeviceLinkState.connecting,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, widget.deviceName, widget.onDeviceTap),
      body: Column(
        children: [
          if (streamAsync is AsyncError)
            _OfflineBanner(message: 'Reconnecting to ${widget.deviceName}…'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 72 + MediaQuery.of(context).padding.top + 4),
                  StatusHero(
                    statusCode: _latest?.statusCode,
                    connection: connection,
                  ),
                  const SizedBox(height: 10),
                  MetricCard(
                    label: 'HEART RATE',
                    value: _latest?.hr,
                    unit: 'bpm',
                    icon: Symbols.favorite,
                    accentColor: AppColors.primaryContainer,
                    sparklineValues: List.of(_hrHistory),
                  ),
                  const SizedBox(height: 10),
                  MetricCard(
                    label: 'RESPIRATION',
                    value: _latest?.rr,
                    unit: 'rpm',
                    icon: Symbols.air,
                    accentColor: AppColors.secondary,
                    sparklineValues: List.of(_rrHistory),
                  ),
                  const SizedBox(height: 10),
                  MetricCard(
                    label: 'TEMPERATURE',
                    value: _latest?.temp,
                    unit: '°C',
                    icon: Symbols.thermostat,
                    accentColor: const Color(0xFFFFB470),
                    sparklineValues: List.of(_tempHistory),
                  ),
                  const SizedBox(height: 10),
                  HomeSecondaryMetrics(data: _latest),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── App bar ──────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(
  BuildContext context,
  String deviceName,
  VoidCallback onDeviceTap,
) {
  // Add the status-bar inset so the 72px toolbar isn't squeezed by the notch.
  final topInset = MediaQuery.of(context).padding.top;
  final totalHeight = 72 + topInset;
  return PreferredSize(
    preferredSize: Size.fromHeight(totalHeight),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: totalHeight,
          color: const Color(0xB3101419), // #101419/70
          padding: EdgeInsets.only(top: topInset, left: 8, right: 8),
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                // Left: reserved spacer (menu removed — shell's nav already
                // covers discovery; keeping width matches bell button size
                // so title stays centered).
                const SizedBox(width: 48),
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
                // Right: shared bell — dot only when unread alerts exist,
                // tap navigates to /alerts.
                const AlertBellButton(color: Color(0xFF8B96A5)),
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

