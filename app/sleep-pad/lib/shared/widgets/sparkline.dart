import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

// Tiny inline sparkline for the HR/RR metric cards.
// Renders last N readings as a smooth line chart — no axes, no labels.
// Source: sleep_pad_home_final_sync/code.html — SVG waveform placeholder
// in the metric cards (h-12, opacity-70).
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
  });

  // Recent data points in chronological order (oldest → newest).
  final List<double> values;
  // Line + gradient tint color (primary for HR, secondary for RR).
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();

    final spots = List.generate(
      values.length,
      (i) => FlSpot(i.toDouble(), values[i]),
    );

    return SizedBox(
      height: 48, // h-12
      child: Opacity(
        opacity: 0.70, // opacity-70
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            minX: 0,
            maxX: (values.length - 1).toDouble(),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: color,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
