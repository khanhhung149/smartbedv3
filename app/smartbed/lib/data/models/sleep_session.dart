/// Một đêm, đã dựng thành phiên phía backend.
///
/// `null` và `0` là hai chuyện khác nhau và phải giữ được sự khác nhau đó tới
/// tận UI: `null` = không đủ dữ liệu hợp lệ để tính, hiện thành `—`.
/// `hr_avg = 0` không bao giờ là giá trị hợp lệ (xem hợp đồng API).
class SleepSession {
  const SleepSession({
    required this.id,
    required this.deviceId,
    required this.startedAt,
    required this.endedAt,
    required this.durationS,
    required this.hrAvg,
    required this.hrMin,
    required this.hrMax,
    required this.rrAvg,
    required this.movementTotal,
    required this.snoreTotal,
    required this.respDisorderTotal,
    required this.sitUpCount,
    required this.wakeCount,
    required this.raw,
  });

  final String id;
  final String deviceId;
  final DateTime startedAt;

  /// `null` = phiên đang diễn ra: người vẫn trên giường ở lần dựng gần nhất.
  /// Khi đó [durationS] cũng `null`.
  final DateTime? endedAt;
  final int? durationS;

  final double? hrAvg;
  final int? hrMin;
  final int? hrMax;
  final double? rrAvg;
  final int? movementTotal;
  final int? snoreTotal;
  final int? respDisorderTotal;
  final int? sitUpCount;
  final int? wakeCount;

  /// JSON nguyên bản như backend trả về.
  ///
  /// Giữ lại để khoá mới (`presence`, `temp`, `ac_on`…) sống sót qua vòng
  /// cache mà không cần đổi schema — quy tắc mở rộng của hợp đồng API.
  final Map<String, dynamic> raw;

  bool get isOngoing => endedAt == null;

  static double? _double(Object? v) => v == null ? null : (v as num).toDouble();
  static int? _int(Object? v) => v == null ? null : (v as num).toInt();

  factory SleepSession.fromJson(Map<String, dynamic> json) => SleepSession(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.parse(json['ended_at'] as String).toLocal(),
        durationS: _int(json['duration_s']),
        hrAvg: _double(json['hr_avg']),
        hrMin: _int(json['hr_min']),
        hrMax: _int(json['hr_max']),
        rrAvg: _double(json['rr_avg']),
        movementTotal: _int(json['movement_total']),
        snoreTotal: _int(json['snore_total']),
        respDisorderTotal: _int(json['resp_disorder_total']),
        sitUpCount: _int(json['sit_up_count']),
        wakeCount: _int(json['wake_count']),
        raw: json,
      );
}
