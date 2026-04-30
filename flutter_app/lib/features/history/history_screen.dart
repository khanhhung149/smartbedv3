import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../shared/widgets/alert_bell_button.dart';
import '../data/providers/history_provider.dart';
import '../data/providers/selected_device_provider.dart';
import '../home/device_selector_sheet.dart';
import 'history_chart_panel.dart';
import 'history_summary_strip.dart';

// History screen: segmented Day/Week/Month tabs with fl_chart cards.
// Source: sleep_history_synced/code.html
// Layout: fixed translucent app bar → tab bar → summary strip → 3 chart cards
//         → canonical AppBottomNav (History active).

const List<String> _ranges = ['day', 'week', 'month'];
const List<String> _rangeLabels = ['Day', 'Week', 'Month'];

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _selectedTab = 1; // Default: Week (matches HTML design)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _ranges.length,
      vsync: this,
      initialIndex: _selectedTab,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, _openDeviceSheet, deviceAsync.valueOrNull?.displayName),
      body: Column(
        children: [
          // Spacer below fixed app bar (~72px) + tab bar (~48px)
          const SizedBox(height: 120),
          // Tab bar (not inside AppBar to keep AppBar translucent separately)
          _buildTabBar(),
          Expanded(
            child: deviceAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryContainer,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Failed to load device: $e',
                  style: GoogleFonts.inter(color: AppColors.error),
                ),
              ),
              data: (device) {
                if (device == null) {
                  return Center(
                    child: Text(
                      'No device selected.',
                      style: GoogleFonts.inter(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return _HistoryTabView(
                  deviceId: device.deviceId,
                  range: _ranges[_selectedTab],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0x33859492), // outline-variant/20
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: List.generate(
          _rangeLabels.length,
          (i) => Tab(
            child: Text(
              _rangeLabels[i],
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: _selectedTab == i
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
        labelColor: AppColors.primaryContainer, // #5EE7DF
        unselectedLabelColor: const Color(0xFF8B96A5),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(
            color: AppColors.primaryContainer,
            width: 2,
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
    );
  }
}

// ── Tab content (one per range) ──────────────────────────────────────────────

class _HistoryTabView extends ConsumerWidget {
  const _HistoryTabView({
    required this.deviceId,
    required this.range,
  });

  final String deviceId;
  final String range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(
      historyProvider((deviceId: deviceId, range: range)),
    );

    return historyAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryContainer,
          strokeWidth: 2,
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.error_outline,
                  size: 40, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Could not load history',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      data: (history) {
        if (history.points.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.bar_chart,
                    size: 40, color: AppColors.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Not enough data yet',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sleep data will appear here once your device has been monitoring.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              HistorySummaryStrip(data: history),
              const SizedBox(height: 24),
              HistoryChartPanel(data: history, range: range),
            ],
          ),
        );
      },
    );
  }
}

// ── App bar ──────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(
  BuildContext context,
  VoidCallback onDeviceTap,
  String? deviceName,
) {
  // Account for status bar / Dynamic Island so the 72px toolbar row isn't
  // squeezed to overflow.
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
                const SizedBox(width: 48),
                // Center: title + device chip (absolutely centered)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sleep History',
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
                                deviceName ?? 'No device',
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
                const AlertBellButton(color: Color(0xFF8B96A5)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

