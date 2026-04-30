import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import 'alert_history_list.dart';

// History tab content — alert history list.
// Rendered by AlertsScreen when selectedTab == 1.
class AlertsHistoryTab extends StatelessWidget {
  const AlertsHistoryTab({super.key, required this.historyAsync});

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
