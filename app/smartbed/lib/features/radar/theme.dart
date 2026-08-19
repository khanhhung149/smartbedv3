import 'package:flutter/material.dart';

/// Design tokens cho tab Radar — port từ app esp32-presence-ac nhưng theo dark
/// theme M3 của SmartBed (app đọc trong bóng tối). Giữ đúng bảng màu dữ liệu
/// (green = có người, blue = điều hoà, amber = chuyển động, red = lỗi) để không
/// phải học lại ý nghĩa màu khi đổi tab.
abstract final class RadarTheme {
  static const bg = Color(0xFF0E1016);
  static const surface = Color(0xFF171B25);
  static const ink = Color(0xFFE7EAF3);
  static const inkSoft = Color(0xFF9AA0B0);

  static const accent = Color(0xFF7C9BF8);
  static const green = Color(0xFF16A34A);
  static const blue = Color(0xFF0EA5E9);
  static const amber = Color(0xFFE8B34B);
  static const red = Color(0xFFDC2626);

  static const radius = 20.0;
  static const radiusSm = 14.0;

  static List<BoxShadow> get shadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Thẻ nổi tối — cùng bo góc/bóng với thẻ của màn Giấc ngủ để hai tab liền mạch.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: RadarTheme.surface,
          borderRadius: BorderRadius.circular(RadarTheme.radius),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: RadarTheme.shadow,
        ),
        child: child,
      );
}

/// Badge xu hướng "↗ +8%". [percent] null = CHƯA ĐỦ DỮ LIỆU → không hiện gì.
class TrendBadge extends StatelessWidget {
  final double? percent;
  const TrendBadge({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    if (percent == null) return const SizedBox.shrink();
    final up = percent! >= 0;
    final color = up ? RadarTheme.green : RadarTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            '${up ? '+' : ''}${percent!.toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Định dạng Duration sang "2g 15p" — ngắn, hợp số liệu trong thẻ.
String fmtDuration(Duration d) {
  if (d.inMinutes < 1) return '0p';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}p';
  return m == 0 ? '${h}g' : '${h}g ${m}p';
}
