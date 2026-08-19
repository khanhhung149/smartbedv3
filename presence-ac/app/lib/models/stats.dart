import 'event.dart';

/// Số liệu sinh hoạt suy ra từ lịch sử event.
///
/// Backend chỉ lưu event thô (motion/presence/ac_cmd + ts) và KHÔNG tổng hợp gì —
/// mọi con số ở đây tính phía app. Cố ý: dữ liệu nhỏ (trần 5000 event), tính client
/// thì backend khỏi gánh thêm schema thống kê.
class DayStats {
  final DateTime day;

  /// Tổng thời gian phòng có người (suy từ cặp presence true→false).
  final Duration occupied;

  /// Tổng thời gian điều hoà bật (suy từ cặp ac_cmd on→off).
  final Duration acOn;

  /// Số lần phát hiện chuyển động.
  final int motionCount;

  const DayStats({
    required this.day,
    required this.occupied,
    required this.acOn,
    required this.motionCount,
  });

  bool get isEmpty =>
      occupied == Duration.zero && acOn == Duration.zero && motionCount == 0;
}

/// Kết quả tính toàn bộ, dùng chung cho màn Tổng quan và Phân tích.
class Stats {
  /// Hôm nay.
  final DayStats today;

  /// Hôm qua — null khi chưa có dữ liệu. UI phải ẩn badge xu hướng khi null,
  /// KHÔNG được coi "không có dữ liệu" là 0 rồi khoe +100%.
  final DayStats? yesterday;

  /// Số lần chuyển động theo từng giờ hôm nay (24 phần tử, index = giờ 0-23).
  final List<int> motionByHour;

  /// Vài ngày gần nhất (cũ → mới) cho biểu đồ cột.
  final List<DayStats> recentDays;

  const Stats({
    required this.today,
    required this.yesterday,
    required this.motionByHour,
    required this.recentDays,
  });

  static final empty = Stats(
    today: DayStats(
        day: DateTime.now(),
        occupied: Duration.zero,
        acOn: Duration.zero,
        motionCount: 0),
    yesterday: null,
    motionByHour: List.filled(24, 0),
    recentDays: const [],
  );

  /// % thay đổi thời gian ở phòng so với hôm qua. null = không đủ dữ liệu để nói.
  double? get occupiedTrend => _trend(
      yesterday?.occupied.inMinutes.toDouble(), today.occupied.inMinutes.toDouble());

  double? get acOnTrend =>
      _trend(yesterday?.acOn.inMinutes.toDouble(), today.acOn.inMinutes.toDouble());

  double? get motionTrend =>
      _trend(yesterday?.motionCount.toDouble(), today.motionCount.toDouble());

  /// Hôm qua bằng 0 thì mọi phần trăm đều vô nghĩa (chia cho 0) → trả null,
  /// thà không hiện còn hơn hiện "+∞%".
  static double? _trend(double? prev, double now) {
    if (prev == null || prev == 0) return null;
    return (now - prev) / prev * 100;
  }
}

/// Tính [Stats] từ danh sách event (mới nhất trước, đúng thứ tự backend trả).
///
/// Tách khỏi UI để test được không cần widget/thiết bị.
Stats computeStats(List<Event> events, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  if (events.isEmpty) return Stats.empty;

  // Backend trả mới nhất trước; tính khoảng thời gian cần thứ tự cũ→mới.
  // Bỏ event ts=0 (node publish trước khi NTP sync) — không có giờ thật thì không
  // đưa vào tính toán được, nhét vào sẽ tạo khoảng thời gian rác từ 1970.
  final ordered = events.where((e) => e.hasTime).toList()
    ..sort((a, b) => a.ts.compareTo(b.ts));
  if (ordered.isEmpty) return Stats.empty;

  final today = DateTime(ref.year, ref.month, ref.day);
  final motionByHour = List.filled(24, 0);

  for (final e in ordered) {
    if (e.kind != Event.kindMotion) continue;
    final t = e.time!;
    if (_sameDay(t, today)) motionByHour[t.hour]++;
  }

  // Gom theo ngày để dựng biểu đồ + so hôm nay/hôm qua.
  final days = <DateTime, _DayAcc>{};
  _accumulate(ordered, days, ref);

  DayStats statsFor(DateTime d) {
    final acc = days[d];
    return DayStats(
      day: d,
      occupied: acc?.occupied ?? Duration.zero,
      acOn: acc?.acOn ?? Duration.zero,
      motionCount: acc?.motionCount ?? 0,
    );
  }

  final yesterdayKey = today.subtract(const Duration(days: 1));
  final recent = days.keys.toList()..sort();

  return Stats(
    today: statsFor(today),
    // Không có bản ghi nào của hôm qua = chưa biết, KHÔNG phải bằng 0.
    yesterday: days.containsKey(yesterdayKey) ? statsFor(yesterdayKey) : null,
    motionByHour: motionByHour,
    recentDays: recent.map(statsFor).toList(),
  );
}

class _DayAcc {
  Duration occupied = Duration.zero;
  Duration acOn = Duration.zero;
  int motionCount = 0;
}

/// Quét theo thứ tự thời gian, cộng dồn khoảng "đang bật" vào ngày tương ứng.
void _accumulate(List<Event> ordered, Map<DateTime, _DayAcc> days, DateTime now) {
  DateTime? presenceSince;
  DateTime? acSince;

  void addSpan(DateTime from, DateTime to, bool isAc) {
    if (!to.isAfter(from)) return;
    // Khoảng vắt qua nửa đêm thì cộng vào NGÀY BẮT ĐẦU — đủ chính xác cho mục đích
    // "hôm nay ở phòng bao lâu", không đáng phức tạp thêm để cắt theo ngày.
    final key = DateTime(from.year, from.month, from.day);
    final acc = days.putIfAbsent(key, () => _DayAcc());
    final d = to.difference(from);
    if (isAc) {
      acc.acOn += d;
    } else {
      acc.occupied += d;
    }
  }

  for (final e in ordered) {
    final t = e.time!;
    final key = DateTime(t.year, t.month, t.day);

    switch (e.kind) {
      case Event.kindMotion:
        days.putIfAbsent(key, () => _DayAcc()).motionCount++;
        break;

      case Event.kindPresence:
        if (e.isPositive) {
          presenceSince ??= t; // đã đang "có người" thì giữ mốc cũ
        } else if (presenceSince != null) {
          addSpan(presenceSince, t, false);
          presenceSince = null;
        }
        break;

      case Event.kindAcCmd:
        if (e.isPositive) {
          acSince ??= t;
        } else if (acSince != null) {
          addSpan(acSince, t, true);
          acSince = null;
        }
        break;
    }
  }

  // Khoảng còn mở (đang có người / điều hoà đang bật) tính tới BÂY GIỜ, nếu không
  // phiên đang diễn ra sẽ không được đếm và số liệu hôm nay luôn thiếu.
  if (presenceSince != null) addSpan(presenceSince, now, false);
  if (acSince != null) addSpan(acSince, now, true);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
