/// Mã sự kiện thô của giao thức Legact (tr.4 §2.4.1).
///
/// Giá trị số là của giao thức, không phải của app — đừng đánh số lại theo thứ
/// tự khai báo. Mã lạ bị bỏ qua thay vì làm vỡ cả point.
enum SleepEvent {
  offBed(1, 'Rời giường'),
  movement(2, 'Cử động'),
  sitUp(3, 'Ngồi dậy'),
  asleep(4, 'Ngủ'),
  awake(5, 'Tỉnh'),
  heavyObject(6, 'Vật nặng'),
  snore(7, 'Ngáy'),
  weakBreathing(8, 'Thở yếu');

  const SleepEvent(this.code, this.label);

  final int code;
  final String label;

  static SleepEvent? fromCode(int code) {
    for (final e in SleepEvent.values) {
      if (e.code == code) return e;
    }
    return null;
  }
}

/// Một bucket trên trục thời gian của một đêm.
///
/// Bucket rỗng **vắng mặt** khỏi mảng chứ không phải `null`: một đêm 8 tiếng ở
/// `bucket=1m` trả 480 point, đoạn mất dữ liệu 40 phút trả 440. Người vẽ phải
/// để trống chỗ đó — nối liền là bịa dữ liệu.
class TimelinePoint {
  const TimelinePoint({
    required this.t,
    required this.hr,
    required this.rr,
    required this.movement,
    required this.snore,
    required this.respDisorder,
    required this.onBed,
    required this.events,
    required this.raw,
  });

  final DateTime t;
  final double? hr;
  final double? rr;
  final int? movement;
  final int? snore;
  final int? respDisorder;

  /// Suy từ luật `hr > 0 OR rr > 0` phía backend, **không** từ mã status.
  /// Đây là suy luận chưa kiểm chứng — xem cảnh báo cuối hợp đồng API.
  final bool onBed;

  final List<SleepEvent> events;
  final Map<String, dynamic> raw;

  static double? _double(Object? v) => v == null ? null : (v as num).toDouble();
  static int? _int(Object? v) => v == null ? null : (v as num).toInt();

  factory TimelinePoint.fromJson(Map<String, dynamic> json) => TimelinePoint(
        t: DateTime.parse(json['t'] as String).toLocal(),
        hr: _double(json['hr']),
        rr: _double(json['rr']),
        movement: _int(json['movement']),
        snore: _int(json['snore']),
        respDisorder: _int(json['resp_disorder']),
        onBed: json['bed_state'] == 'on_bed',
        events: [
          for (final c in (json['events'] as List? ?? const []))
            ?SleepEvent.fromCode((c as num).toInt()),
        ],
        raw: json,
      );
}
