import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stats.dart';
import '../providers.dart';
import '../theme.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(radarStatsProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(radarEventsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            Text('Phân tích', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Nhịp sinh hoạt suy từ cảm biến',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            statsAsync.when(
              loading: () => const AppCard(
                child: SizedBox(
                    height: 200, child: Center(child: CircularProgressIndicator())),
              ),
              error: (e, _) => AppCard(
                child: Column(children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 44, color: RadarTheme.inkSoft),
                  const SizedBox(height: 10),
                  Text('$e', textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton(
                      onPressed: () => ref.invalidate(radarEventsProvider),
                      child: const Text('Thử lại')),
                ]),
              ),
              data: (stats) => Column(
                children: [
                  _HourlyActivityCard(stats: stats),
                  const SizedBox(height: 20),
                  _DailyOccupancyCard(stats: stats),
                  const SizedBox(height: 20),
                  _AcRatioCard(stats: stats),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cột: số lần chuyển động theo giờ hôm nay → thấy được mình hoạt động lúc nào.
class _HourlyActivityCard extends StatelessWidget {
  final Stats stats;
  const _HourlyActivityCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final data = stats.motionByHour;
    final maxV = data.fold<int>(0, (m, v) => v > m ? v : m);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _IconBox(icon: Icons.directions_walk_rounded, color: RadarTheme.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hoạt động theo giờ',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('Số lần chuyển động hôm nay',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 18),
          if (maxV == 0)
            const _Empty(
              icon: Icons.nightlight_round,
              text: 'Chưa ghi nhận chuyển động nào hôm nay',
              hint: 'PIR chưa lắp — chờ cắm vào GPIO27 của voice-node',
            )
          else
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceBetween,
                  maxY: (maxV * 1.25).ceilToDouble(),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.black.withValues(alpha: 0.05), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        // 24 nhãn thì chật kín — chỉ hiện mỗi 6 giờ.
                        getTitlesWidget: (v, _) => v.toInt() % 6 == 0
                            ? Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('${v.toInt()}h',
                                    style: const TextStyle(
                                        fontSize: 10, color: RadarTheme.inkSoft)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, _, r, _) => BarTooltipItem(
                        '${g.x}h: ${r.toY.toInt()} lần',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  barGroups: List.generate(
                    24,
                    (h) => BarChartGroupData(x: h, barRods: [
                      BarChartRodData(
                        toY: data[h].toDouble(),
                        color: RadarTheme.amber,
                        width: 7,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cột: thời gian ở phòng theo ngày.
class _DailyOccupancyCard extends StatelessWidget {
  final Stats stats;
  const _DailyOccupancyCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    // Chỉ lấy 7 ngày cuối — dài hơn thì cột chật, mà lịch sử cũng mới có từ 16/07.
    final days = stats.recentDays.length > 7
        ? stats.recentDays.sublist(stats.recentDays.length - 7)
        : stats.recentDays;
    final maxH = days.fold<double>(
        0, (m, d) => d.occupied.inMinutes / 60 > m ? d.occupied.inMinutes / 60 : m);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _IconBox(icon: Icons.calendar_today_rounded, color: RadarTheme.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Thời gian ở phòng',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('${days.length} ngày gần nhất',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 18),
          if (days.isEmpty || maxH == 0)
            const _Empty(
              icon: Icons.insights_rounded,
              text: 'Chưa đủ dữ liệu để vẽ',
              hint: 'Lịch sử mới bắt đầu ghi từ 16/07 — vài ngày nữa sẽ đầy',
            )
          else
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxH * 1.25).ceilToDouble(),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.black.withValues(alpha: 0.05), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}g',
                            style: const TextStyle(
                                fontSize: 10, color: RadarTheme.inkSoft)),
                      ),
                    ),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= days.length) return const SizedBox.shrink();
                          final d = days[i].day;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('${d.day}/${d.month}',
                                style: const TextStyle(
                                    fontSize: 10, color: RadarTheme.inkSoft)),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, _, r, _) => BarTooltipItem(
                        fmtDuration(days[g.x].occupied),
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  barGroups: List.generate(
                    days.length,
                    (i) => BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: days[i].occupied.inMinutes / 60,
                        color: RadarTheme.green,
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vòng: tỉ lệ thời gian điều hoà chạy so với thời gian ở phòng hôm nay.
/// Đây là con số đáng quan tâm nhất — nó nói tiền điện có bị đốt lúc phòng trống không.
class _AcRatioCard extends StatelessWidget {
  final Stats stats;
  const _AcRatioCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final occ = stats.today.occupied.inMinutes.toDouble();
    final ac = stats.today.acOn.inMinutes.toDouble();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _IconBox(icon: Icons.bolt_rounded, color: RadarTheme.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Điều hoà vs có mặt',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('Hôm nay', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 18),
          if (ac == 0 && occ == 0)
            const _Empty(
              icon: Icons.pie_chart_outline_rounded,
              text: 'Chưa có dữ liệu hôm nay',
              hint: 'Số liệu xuất hiện khi radar ghi nhận có người',
            )
          else
            Row(
              children: [
                SizedBox(
                  height: 110,
                  width: 110,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 32,
                      sections: [
                        PieChartSectionData(
                          value: ac == 0 ? 0.001 : ac,
                          color: RadarTheme.blue,
                          radius: 18,
                          showTitle: false,
                        ),
                        PieChartSectionData(
                          // Phần ở phòng mà KHÔNG bật điều hoà.
                          value: (occ - ac).clamp(0, double.infinity) == 0
                              ? 0.001
                              : (occ - ac).clamp(0, double.infinity),
                          color: RadarTheme.green.withValues(alpha: 0.35),
                          radius: 18,
                          showTitle: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Legend(
                          color: RadarTheme.blue,
                          label: 'Điều hoà chạy',
                          value: fmtDuration(stats.today.acOn)),
                      const SizedBox(height: 10),
                      _Legend(
                          color: RadarTheme.green.withValues(alpha: 0.35),
                          label: 'Ở phòng, không bật',
                          value: fmtDuration(stats.today.occupied - stats.today.acOn)),
                      const SizedBox(height: 10),
                      if (occ > 0)
                        Text('${(ac / occ * 100).clamp(0, 999).toStringAsFixed(0)}% thời gian ở phòng có điều hoà',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _Legend({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: RadarTheme.ink)),
              ],
            ),
          ),
        ],
      );
}

/// Trạng thái rỗng — nói THẬT là chưa có dữ liệu, kèm lý do. Thà trống còn hơn
/// vẽ số bịa cho đẹp.
class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String hint;
  const _Empty({required this.icon, required this.text, required this.hint});

  // Không ghim chiều cao: chữ dài / cỡ chữ hệ thống lớn sẽ tràn dọc. Để Column tự co
  // theo nội dung, chỉ đệm khoảng trống hai đầu.
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: RadarTheme.inkSoft.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: RadarTheme.inkSoft)),
            const SizedBox(height: 4),
            Text(hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: RadarTheme.inkSoft.withValues(alpha: 0.8))),
          ],
        ),
      );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBox({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      );
}
