import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'alerts_app_bar.dart';
import 'alerts_history_tab.dart';
import 'alerts_tab_controls.dart';
import 'alerts_thresholds_tab.dart';
import 'models/threshold_out.dart';
import 'providers/alert_history_provider.dart';
import 'providers/alerts_repository_provider.dart';
import 'providers/thresholds_provider.dart';

// Main alerts body — segmented tab control + save button, shown when a device
// is selected. Keeps threshold edit state and handles save flow.

class AlertsBody extends ConsumerStatefulWidget {
  const AlertsBody({
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
  ConsumerState<AlertsBody> createState() => _AlertsBodyState();
}

class _AlertsBodyState extends ConsumerState<AlertsBody> {
  ThresholdOut? _edited; // null = unchanged
  bool _saving = false;
  String? _saveError;

  @override
  Widget build(BuildContext context) {
    final thresholdsAsync = ref.watch(thresholdsProvider(widget.deviceId));
    final historyAsync = ref.watch(alertHistoryProvider(widget.deviceId));
    final isDirty = _edited != null;

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: buildAlertsAppBar(context),
        body: Column(
          children: [
            const SizedBox(height: 72),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: AlertsSegmentedControl(
                selected: widget.selectedTab,
                labels: const ['Thresholds', 'History'],
                onChanged: widget.onTabChanged,
              ),
            ),
            Expanded(
              child: widget.selectedTab == 0
                  ? AlertsThresholdsTab(
                      thresholdsAsync: thresholdsAsync,
                      onChanged: (t) => setState(() {
                        _edited = t;
                        _saveError = null;
                      }),
                      saveError: _saveError,
                    )
                  : AlertsHistoryTab(historyAsync: historyAsync),
            ),
          ],
        ),
        bottomNavigationBar: widget.selectedTab == 0
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: AlertsSaveButton(
                    isDirty: isDirty,
                    onPressed: isDirty ? () => _save(context) : null,
                  ),
                ),
              )
            : null,
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
