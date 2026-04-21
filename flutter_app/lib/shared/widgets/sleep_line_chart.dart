import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';

// fl_chart LineChart wrapper styled to match sleep_history_synced/code.html.
// Dark theme: transparent bg, subtle horizontal grid lines, no vertical lines.
// Gradient fill below line (color @ 30% opacity → transparent).
// Source SVG charts: stroke #5EE7DF (HR), #B490F5 (RR).

class SleepLineChart extends StatelessWidget {
  const SleepLineChart({
    super.key,
    required this.spots,
    required this.lineColor,
    required this.range,
    this.minY,
    this.maxY,
  });

  final List<FlSpot> spots;
  // #5EE7DF for HR, #B490F5 for RR
  final Color lineColor;
  // 'day' | 'week' | 'month' — used to format X-axis labels
  final String range;
  final double? minY;
  final double? maxY;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'Not enough data yet',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 160, // h-40
      child: LineChart(
        LineChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _horizontalInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.outlineVariant.withValues(alpha: 0.10),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value.round().toString(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.navInactive,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (value, meta) =>
                    _bottomLabel(value, meta, range, spots),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceContainerHighest,
              tooltipRoundedRadius: 8,
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      s.y.toStringAsFixed(1),
                      GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: lineColor,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.30),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _horizontalInterval {
    if (maxY != null && minY != null && maxY! - minY! > 0) {
      return (maxY! - minY!) / 2;
    }
    return 20;
  }
}

// X-axis label formatter: show day abbreviation (week), hour (day), date (month).
Widget _bottomLabel(
  double value,
  TitleMeta meta,
  String range,
  List<FlSpot> spots,
) {
  // Only render at first, middle and last to avoid crowding
  final isFirst = value == meta.min;
  final isLast = value == meta.max;
  final isMid = (value - (meta.min + meta.max) / 2).abs() < 0.5;
  if (!isFirst && !isLast && !isMid) return const SizedBox.shrink();

  String label = '';
  // spots index maps to X value — not time-aware here; caller passes epoch
  // seconds as X values for proper label rendering.
  final idx = value.round().clamp(0, spots.length - 1);
  // Label generation is positional; full date formatting requires passing
  // DateTime list — see history_chart_panel.dart which passes pre-formatted labels.
  label = _rangeLabel(range, idx, spots.length);

  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 10,
        color: const Color(0xFF8B96A5),
      ),
    ),
  );
}

String _rangeLabel(String range, int idx, int total) {
  switch (range) {
    case 'week':
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[idx % days.length];
    case 'month':
      // Show day number roughly
      return 'D${idx + 1}';
    case 'day':
    default:
      // Show hour number based on position
      final hour = ((idx / total) * 24).round();
      return '${hour}h';
  }
}
