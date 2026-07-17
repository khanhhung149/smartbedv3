import 'package:flutter/material.dart';

/// Design token — lấy cảm hứng từ shot "Travia" (Layo, Dribbble): nền sáng xám nhạt,
/// thẻ trắng bo góc lớn, đổ bóng rất mềm, hero card gradient, nav dạng viên thuốc nổi.
class AppTheme {
  // Nền xám rất nhạt để thẻ trắng nổi lên — thẻ trắng trên nền trắng thì mất hết chiều sâu.
  static const bg = Color(0xFFF4F5F7);
  static const surface = Colors.white;
  static const ink = Color(0xFF12141A);
  static const inkSoft = Color(0xFF71757F);

  static const accent = Color(0xFF6C5CE7); // tím — màu thương hiệu, dùng cho hero + nhấn
  static const green = Color(0xFF16A34A); // có người / xu hướng tăng
  static const blue = Color(0xFF0EA5E9); // điều hoà
  static const amber = Color(0xFFF59E0B); // chuyển động
  static const red = Color(0xFFDC2626);

  static const radius = 24.0;
  static const radiusSm = 16.0;

  /// Bóng rất nhẹ, khuếch tán rộng — nhiều lớp bóng đậm sẽ làm UI trông rẻ tiền.
  static List<BoxShadow> get shadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          surface: surface,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, color: ink, height: 1.2),
          titleMedium: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: ink),
          bodyMedium: TextStyle(fontSize: 14, color: ink),
          bodySmall: TextStyle(fontSize: 12, color: inkSoft),
        ),
      );
}

/// Thẻ trắng bo góc — dùng chung để mọi thẻ có cùng bo góc/bóng, khỏi lệch nhau.
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: AppTheme.shadow,
        ),
        child: child,
      );
}

/// Badge xu hướng "↗ +8%" như trong Travia.
///
/// [percent] null = CHƯA ĐỦ DỮ LIỆU → không hiện gì. Cố ý: lịch sử mới ghi từ
/// 16/07 nên nhiều ngày chưa có mốc so sánh; hiện "+100%" từ hư không là nói dối.
class TrendBadge extends StatelessWidget {
  final double? percent;
  const TrendBadge({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    if (percent == null) return const SizedBox.shrink();
    final up = percent! >= 0;
    final color = up ? AppTheme.green : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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
