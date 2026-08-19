import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/timeline_point.dart';

/// One stacked band of the night chart.
///
/// The stack is data, not code: adding presence or room temperature later means
/// appending a ChartLayer, not editing this file.
class ChartLayer {
  const ChartLayer({
    required this.label,
    required this.unit,
    required this.value,
    required this.color,
    this.asBars = false,
    this.height = 110,
    this.icon,
  });

  final String label;
  final String unit;

  /// null means the metric is missing for that bucket — the point is skipped,
  /// leaving a hole rather than a line drawn through data nobody recorded.
  final double? Function(TimelinePoint) value;
  final Color color;
  final bool asBars;
  final double height;
  final IconData? icon;
}

/// Vertically stacked layers over one shared X axis.
///
/// The axis is computed once here and handed to every layer. If each layer
/// derived its own, they would drift by a few pixels and every conclusion read
/// off the chart by comparing bands would be wrong.
class TimelineChart extends StatelessWidget {
  const TimelineChart({
    super.key,
    required this.points,
    required this.layers,
    required this.bedStateBand,
  });

  final List<TimelinePoint> points;
  final List<ChartLayer> layers;
  final Widget bedStateBand;

  /// Two consecutive buckets further apart than this are a dropout, not a step.
  static const Duration _gapThreshold = Duration(minutes: 3);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final minX = points.first.t.millisecondsSinceEpoch.toDouble();
    final maxX = points.last.t.millisecondsSinceEpoch.toDouble();
    final span = (maxX - minX).abs() < 1 ? 1.0 : maxX - minX;

    // ~1.6dp per minute keeps a full night readable and scrollable inside its
    // own box; the page itself never scrolls sideways.
    final minutes = span / 60000;
    final chartWidth = (minutes * 1.6).clamp(320.0, 4000.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = chartWidth < constraints.maxWidth
            ? constraints.maxWidth
            : chartWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final layer in layers) ...[
                  _LayerBox(
                    layer: layer,
                    points: points,
                    minX: minX,
                    maxX: maxX,
                  ),
                  const SizedBox(height: 12),
                ],
                bedStateBand,
                const SizedBox(height: 6),
                _AxisLabels(points: points),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Splits the series wherever a bucket is missing, so fl_chart draws separate
  /// lines instead of bridging the hole.
  static List<List<FlSpot>> segments(
    List<TimelinePoint> points,
    double? Function(TimelinePoint) value,
  ) {
    final out = <List<FlSpot>>[];
    var current = <FlSpot>[];
    DateTime? prev;
    for (final p in points) {
      final v = value(p);
      final broken = v == null ||
          (prev != null && p.t.difference(prev).abs() > _gapThreshold);
      if (broken) {
        if (current.length > 1) out.add(current);
        current = <FlSpot>[];
        prev = v == null ? null : p.t;
        if (v == null) continue;
      }
      current.add(FlSpot(p.t.millisecondsSinceEpoch.toDouble(), v));
      prev = p.t;
    }
    if (current.length > 1) out.add(current);
    return out;
  }
}

/// Tooltip body shared by every interactive layer, so all charts agree on how
/// a value is presented: the time first (that is the question being asked),
/// then the value with its unit.
String _tooltipLine(DateTime t, String valueWithUnit) {
  final fmt = DateFormat('HH:mm', 'vi');
  return '${fmt.format(t)}  ·  $valueWithUnit';
}

class _LayerBox extends StatelessWidget {
  const _LayerBox({
    required this.layer,
    required this.points,
    required this.minX,
    required this.maxX,
  });

  final ChartLayer layer;
  final List<TimelinePoint> points;
  final double minX;
  final double maxX;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = points.map(layer.value).whereType<double>().toList();
    if (values.isEmpty) {
      return SizedBox(
        height: layer.height,
        child: Center(
          child: Text('${layer.label}: không có dữ liệu',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ),
      );
    }
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo) < 1 ? 1.0 : (hi - lo) * 0.15;

    final tooltipBg = theme.colorScheme.surfaceContainerHighest;
    final tooltipText = theme.colorScheme.onSurface;

    DateTime timeAt(double x) =>
        DateTime.fromMillisecondsSinceEpoch(x.round(), isUtc: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (layer.icon != null) ...[
              Icon(layer.icon, size: 14, color: layer.color),
              const SizedBox(width: 5),
            ],
            Text('${layer.label} (${layer.unit})',
                style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: layer.height,
          child: layer.asBars
              ? BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: hi + pad,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => tooltipBg,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final i = group.x;
                          if (i < 0 || i >= points.length) return null;
                          return BarTooltipItem(
                            _tooltipLine(points[i].t, '${rod.toY.round()}'),
                            TextStyle(color: tooltipText, fontSize: 11),
                          );
                        },
                      ),
                    ),
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      for (var i = 0; i < points.length; i++)
                        if ((layer.value(points[i]) ?? 0) > 0)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: layer.value(points[i])!,
                              color: layer.color,
                              width: 2,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ]),
                    ],
                  ),
                )
              : LineChart(
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    minY: lo - pad,
                    maxY: hi + pad,
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => tooltipBg,
                        getTooltipItems: (spots) => [
                          for (final s in spots)
                            LineTooltipItem(
                              _tooltipLine(timeAt(s.x), '${s.y.round()}'),
                              TextStyle(color: tooltipText, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: (hi + pad - (lo - pad)) / 2,
                          getTitlesWidget: (v, meta) => Text(
                            v.round().toString(),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: theme.dividerColor.withValues(alpha: 0.25),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      for (final seg
                          in TimelineChart.segments(points, layer.value))
                        LineChartBarData(
                          spots: seg,
                          isCurved: false,
                          color: layer.color,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          // A soft fill under the line turns a trace into a
                          // shape the eye can weigh against other bands.
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                layer.color.withValues(alpha: 0.28),
                                layer.color.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _AxisLabels extends StatelessWidget {
  const _AxisLabels({required this.points});

  final List<TimelinePoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('HH:mm', 'vi');
    final style =
        theme.textTheme.labelSmall?.copyWith(color: theme.hintColor);

    // Four evenly spaced time labels instead of just the two ends, so the
    // reader can orient a scrolled band without counting back from the right.
    final n = points.length;
    if (n < 4) {
      return Padding(
        padding: const EdgeInsets.only(left: 30),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(fmt.format(points.first.t), style: style),
            Text(fmt.format(points.last.t), style: style),
          ],
        ),
      );
    }
    final idxs = [
      0,
      (n - 1) ~/ 3,
      (2 * (n - 1)) ~/ 3,
      n - 1,
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final i in idxs) Text(fmt.format(points[i].t), style: style),
        ],
      ),
    );
  }
}