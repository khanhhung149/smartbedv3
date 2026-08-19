import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../shared/widgets/sleep_line_chart.dart';
import '../data/models/history_response.dart';

// Three stacked chart cards: Heart Rate line, Respiration Rate line,
// Sleep Disturbances grouped bar chart.
// Source: sleep_history_synced/code.html lines ~149-299.
// Chart types:
//   - HR: fl_chart LineChart, stroke #5EE7DF, gradient fill
//   - RR: fl_chart LineChart, stroke #B490F5, gradient fill
//   - Disturbances: fl_chart BarChart grouped by color (Movement=emerald,
//     Snore=amber, Resp=coral #FF7F50) — HTML uses stacked bar visual.
//     Decision: grouped BarChart (fl_chart v0.69 supports BarChartGroupData
//     with multiple rods) — closest match to stacked color bars in HTML.

class HistoryChartPanel extends StatelessWidget {
  const HistoryChartPanel({
    super.key,
    required this.data,
    required this.range,
  });

  final HistoryResponse data;
  final String range;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChartCard(
          title: 'Heart rate',
          child: SleepLineChart(
            spots: _hrSpots(),
            lineColor: AppColors.primaryContainer, // #5EE7DF
            range: range,
            minY: 30,
            maxY: 130,
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Respiration rate',
          child: SleepLineChart(
            spots: _rrSpots(),
            lineColor: AppColors.rrAccent,
            range: range,
            minY: 4,
            maxY: 32,
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Sleep disturbances',
          trailing: _DisturbanceLegend(),
          child: _DisturbanceBarChart(points: data.points, range: range),
        ),
      ],
    );
  }

  List<FlSpot> _hrSpots() => _toSpots(
        data.points,
        (p) => p.hr,
      );

  List<FlSpot> _rrSpots() => _toSpots(
        data.points,
        (p) => p.rr,
      );

  static List<FlSpot> _toSpots(
    List<HistoryPoint> points,
    double? Function(HistoryPoint) getter,
  ) {
    final result = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = getter(points[i]);
      if (v != null) result.add(FlSpot(i.toDouble(), v));
    }
    return result;
  }
}

// ── Chart card wrapper ───────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer, // #1C2025
        borderRadius: BorderRadius.circular(20), // rounded-DEFAULT
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      padding: const EdgeInsets.all(20), // p-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onBackground,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

// ── Disturbance bar chart ────────────────────────────────────────────────────

// Renders resp_disorder as a single-color bar chart (coral #FF7F50).
// The HTML shows stacked Movement + Snore + Resp bars, but the backend
// /history endpoint only exposes resp_disorder per point. Movement and snore
// aggregates are not available — single-series bar chart used.
// This is documented as a deviation in the phase report.

class _DisturbanceBarChart extends StatelessWidget {
  const _DisturbanceBarChart({
    required this.points,
    required this.range,
  });

  final List<HistoryPoint> points;
  final String range;

  static const Color _respColor = Color(0xFFFF7F50);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
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

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < points.length; i++) {
      final v = (points[i].respDisorder ?? 0).toDouble();
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: v,
            color: _respColor,
            width: _barWidth(points.length),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(3),
            ),
          ),
        ],
      ));
    }

    final maxY = points
            .map((p) => (p.respDisorder ?? 0).toDouble())
            .fold(0.0, (a, b) => a > b ? a : b)
            .ceilToDouble() +
        2;

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          backgroundColor: Colors.transparent,
          maxY: maxY < 4 ? 10 : maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY < 4 ? 5 : maxY / 2,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.outlineVariant.withValues(alpha: 0.10),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    v.round().toString(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFF8B96A5),
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, meta) =>
                    _xLabel(v, meta, range, points.length),
              ),
            ),
          ),
          barGroups: groups,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceContainerHighest,
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                rod.toY.round().toString(),
                GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _respColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _barWidth(int count) {
    if (count <= 7) return 16;
    if (count <= 30) return 6;
    return 3;
  }
}

Widget _xLabel(double value, TitleMeta meta, String range, int total) {
  final isFirst = (value - meta.min).abs() < 0.5;
  final isLast = (value - meta.max).abs() < 0.5;
  final isMid = (value - (meta.min + meta.max) / 2).abs() < 0.5;
  if (!isFirst && !isLast && !isMid) return const SizedBox.shrink();

  final idx = value.round().clamp(0, total - 1);
  String label;
  switch (range) {
    case 'week':
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      label = days[idx % days.length];
    case 'month':
      label = 'D${idx + 1}';
    default:
      final hour = ((idx / total) * 24).round();
      label = '${hour}h';
  }

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

// ── Disturbance legend ───────────────────────────────────────────────────────

class _DisturbanceLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Movement and Snore buckets not available from API — show Resp only.
        _dot(const Color(0xFFFF7F50), 'Resp'),
      ],
    );
  }

  Widget _dot(Color color, String label) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: const Color(0xFF8B96A5),
            ),
          ),
        ],
      );
}
