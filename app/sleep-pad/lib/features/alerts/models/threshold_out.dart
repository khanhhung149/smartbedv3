// Response model for GET/PUT /alerts/{device_id}/thresholds
// Field types match backend schema (backend/postgres/init.sql):
//   hr_high / hr_low / resp_disorder_count — SMALLINT (int)
//   rr_high / rr_low — REAL (float/double)
class ThresholdOut {
  const ThresholdOut({
    required this.deviceId,
    required this.hrHigh,
    required this.hrLow,
    required this.rrHigh,
    required this.rrLow,
    required this.respDisorderCount,
  });

  final String deviceId;
  final int hrHigh;
  final int hrLow;
  final double rrHigh;
  final double rrLow;
  final int respDisorderCount;

  factory ThresholdOut.fromJson(Map<String, dynamic> json) => ThresholdOut(
        deviceId: json['device_id'] as String,
        hrHigh: (json['hr_high'] as num).toInt(),
        hrLow: (json['hr_low'] as num).toInt(),
        rrHigh: (json['rr_high'] as num).toDouble(),
        rrLow: (json['rr_low'] as num).toDouble(),
        respDisorderCount: (json['resp_disorder_count'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'hr_high': hrHigh,
        'hr_low': hrLow,
        'rr_high': rrHigh,
        'rr_low': rrLow,
        'resp_disorder_count': respDisorderCount,
      };

  ThresholdOut copyWith({
    int? hrHigh,
    int? hrLow,
    double? rrHigh,
    double? rrLow,
    int? respDisorderCount,
  }) =>
      ThresholdOut(
        deviceId: deviceId,
        hrHigh: hrHigh ?? this.hrHigh,
        hrLow: hrLow ?? this.hrLow,
        rrHigh: rrHigh ?? this.rrHigh,
        rrLow: rrLow ?? this.rrLow,
        respDisorderCount: respDisorderCount ?? this.respDisorderCount,
      );
}
