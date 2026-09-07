import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Sparkline nhỏ trong thẻ nhịp tim / nhịp thở.
///
/// Vẽ N mẫu gần nhất thành đường cong mượt — không trục, không nhãn, không chạm.
/// Thông số lấy đúng theo app tham chiếu `Sleep-Tech-AI/sleep-pad-ai`
/// (`lib/shared/widgets/sparkline.dart`) để hai app nhìn giống nhau.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  /// Mẫu gần nhất theo thứ tự thời gian (cũ → mới).
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Một điểm thì không thành đường; trả khung rỗng thay vì vẽ chấm lạc lõng.
    if (values.length < 2) return const SizedBox(height: 48);

    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];

    // Chuỗi phẳng (mọi giá trị bằng nhau, hay gặp khi hr/rr còn 0) làm fl_chart
    // tính khoảng y bằng 0 và đường biến mất. Nới thủ công để nó nằm giữa khung.
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }

    return SizedBox(
      height: 48,
      child: Opacity(
        opacity: 0.70,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            minX: 0,
            maxX: (values.length - 1).toDouble(),
            minY: lo,
            maxY: hi,
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
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
