import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/primary_button.dart';
import '../data/providers/selected_device_provider.dart';
import 'alert_history_list.dart';
import 'models/threshold_out.dart';
import 'providers/alert_history_provider.dart';
import 'providers/thresholds_provider.dart';
import 'threshold_form.dart';

// Alerts screen: two tabs — Thresholds | History.
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
        return _AlertsBody(
          key: ValueKey(device.deviceId),
          deviceId: device.deviceId,
          deviceName: device.name,
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
      appBar: _alertsAppBar('Alerts'),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTap: (i) => _handleNavTap(context, i),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.notifications_off,
                size: 48, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No device paired',
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
              child: Text('Add Device', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main body (device selected) ───────────────────────────────────────────────

class _AlertsBody extends ConsumerStatefulWidget {
  const _AlertsBody({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.selectedTab,
    required this.onTabChanged,
  });

  final String deviceId;
  final String deviceName;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;

  @override
  ConsumerState<_AlertsBody> createState() => _AlertsBodyState();
}

class _AlertsBodyState extends ConsumerState<_AlertsBody> {
  ThresholdOut? _edited; // null = unchanged
  bool _saving = false;
  String? _saveError;

  @override
  Widget build(BuildContext context) {
    final thresholdsAsync =
        ref.watch(thresholdsProvider(widget.deviceId));
    final historyAsync =
        ref.watch(alertHistoryProvider(widget.deviceId));

    final isDirty = _edited != null;

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: _alertsAppBar(widget.deviceName),
        body: Column(
          children: [
            // Spacer for translucent app bar
            const SizedBox(height: 72),
            // Segmented tab control
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _SegmentedControl(
                selected: widget.selectedTab,
                labels: const ['Thresholds', 'History'],
                onChanged: widget.onTabChanged,
              ),
            ),
            Expanded(
              child: widget.selectedTab == 0
                  ? _ThresholdsTab(
                      thresholdsAsync: thresholdsAsync,
                      onChanged: (t) => setState(() {
                        _edited = t;
                        _saveError = null;
                      }),
                      saveError: _saveError,
                    )
                  : _HistoryTab(historyAsync: historyAsync),
            ),
          ],
        ),
        // Sticky save button above bottom nav
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.selectedTab == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: _SaveButton(
                  isDirty: isDirty,
                  onPressed: isDirty ? () => _save(context) : null,
                ),
              ),
            AppBottomNav(
              currentIndex: 2,
              onTap: (i) => _handleNavTap(context, i),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (_edited == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final repo = ref.read(alertsRepositoryProvider);
      await repo.putThresholds(widget.deviceId, _edited!);
      // Invalidate so thresholdsProvider refetches fresh data
      ref.invalidate(thresholdsProvider(widget.deviceId));
      setState(() {
        _edited = null;
        _saving = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thresholds saved',
                style: GoogleFonts.inter(color: AppColors.onPrimaryFixed)),
            backgroundColor: AppColors.primaryContainer,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.defaultRadius)),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _saveError = e.toString();
      });
    }
  }
}

// ── Thresholds tab ────────────────────────────────────────────────────────────

class _ThresholdsTab extends StatelessWidget {
  const _ThresholdsTab({
    required this.thresholdsAsync,
    required this.onChanged,
    this.saveError,
  });

  final AsyncValue<ThresholdOut> thresholdsAsync;
  final ValueChanged<ThresholdOut> onChanged;
  final String? saveError;

  @override
  Widget build(BuildContext context) {
    return thresholdsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(
              color: AppColors.primaryContainer, strokeWidth: 2)),
      error: (e, _) => Center(
          child: Text('Failed to load thresholds: $e',
              style: GoogleFonts.inter(color: AppColors.error))),
      data: (thresholds) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Caption text
            Text(
              'Alerts fire when vitals stay outside these ranges for over a minute.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            ThresholdForm(initial: thresholds, onChanged: onChanged),
            if (saveError != null) ...[
              const SizedBox(height: 12),
              Text(saveError!,
                  style:
                      GoogleFonts.inter(color: AppColors.error, fontSize: AppTextSize.sm)),
            ],
            const SizedBox(height: 96), // space for sticky save button
          ],
        ),
      ),
    );
  }
}

// ── History tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.historyAsync});

  final AsyncValue<List<dynamic>> historyAsync;

  @override
  Widget build(BuildContext context) {
    return historyAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(
              color: AppColors.primaryContainer, strokeWidth: 2)),
      error: (e, _) => Center(
          child: Text('Failed to load history: $e',
              style: GoogleFonts.inter(color: AppColors.error))),
      data: (alerts) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: AlertHistoryList(alerts: alerts.cast()),
      ),
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  final int selected;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.fullBr,
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.surfaceContainerHigh
                      : Colors.transparent,
                  borderRadius: AppRadius.fullBr,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.medium,
                    color: isActive
                        ? AppColors.primaryContainer
                        : const Color(0xFF8B96A5),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Save button ───────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.isDirty, required this.onPressed});

  final bool isDirty;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isDirty) {
      return PrimaryButton(label: 'Save changes', onPressed: onPressed);
    }
    // Disabled state: surface-container-high bg, muted text, opacity 70
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Opacity(
          opacity: 0.7,
          child: Center(
            child: Text(
              'Save changes',
              style: GoogleFonts.inter(
                fontSize: AppTextSize.base,
                fontWeight: AppFontWeight.semiBold,
                color: const Color(0xFF8B96A5),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

PreferredSizeWidget _alertsAppBar(String title) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          color: const Color(0xB3101419),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Symbols.menu,
                      color: Color(0xFF8B96A5), size: 24),
                  onPressed: () {},
                ),
                Expanded(
                  child: Text(
                    'Alerts',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.lg,
                      fontWeight: AppFontWeight.bold,
                      color: const Color(0xFFE6EDF3),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Symbols.notifications,
                      color: Color(0xFF8B96A5), size: 24),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Nav handler ───────────────────────────────────────────────────────────────

void _handleNavTap(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/home');
    case 1:
      context.go('/history');
    case 2:
      break; // already here
    case 3:
      context.go('/devices');
    case 4:
      context.go('/settings');
  }
}
