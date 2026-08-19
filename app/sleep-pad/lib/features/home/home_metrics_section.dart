import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/metric_card.dart';
import '../data/models/realtime_data.dart';
import 'home_secondary_metrics.dart';

// Primary metric cards (HR, RR, Temp) + secondary metrics grid.
// Receives latest data snapshot and sparkline buffers from HomeContent state.
class HomeMetricsSection extends StatelessWidget {
  const HomeMetricsSection({
    super.key,
    required this.latest,
    required this.hrHistory,
    required this.rrHistory,
    required this.tempHistory,
  });

  final RealtimeData? latest;
  final List<double> hrHistory;
  final List<double> rrHistory;
  final List<double> tempHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        MetricCard(
          label: l10n.heartRate.toUpperCase(),
          value: latest?.hr,
          unit: 'bpm',
          icon: Symbols.favorite,
          accentColor: AppColors.primaryContainer,
          sparklineValues: List.of(hrHistory),
        ),
        const SizedBox(height: 10),
        MetricCard(
          label: l10n.respiration.toUpperCase(),
          value: latest?.rr,
          unit: 'rpm',
          icon: Symbols.air,
          accentColor: AppColors.secondary,
          sparklineValues: List.of(rrHistory),
        ),
        const SizedBox(height: 10),
        MetricCard(
          label: l10n.temperature.toUpperCase(),
          value: latest?.temp,
          unit: '°C',
          icon: Symbols.thermostat,
          accentColor: const Color(0xFFFFB470),
          sparklineValues: List.of(tempHistory),
        ),
        const SizedBox(height: 10),
        HomeSecondaryMetrics(data: latest),
      ],
    );
  }
}
