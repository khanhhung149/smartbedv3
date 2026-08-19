// HistoryResponse: maps GET /data/{device_id}/history?range=day|week|month
class HistoryPoint {
  const HistoryPoint({
    required this.bucket,
    this.hr,
    this.rr,
    this.respDisorder,
    this.temp,
  });

  final DateTime bucket;
  final double? hr;
  final double? rr;
  final int? respDisorder;
  final double? temp;

  factory HistoryPoint.fromJson(Map<String, dynamic> json) => HistoryPoint(
        bucket: DateTime.parse(json['bucket'] as String),
        hr: (json['hr'] as num?)?.toDouble(),
        rr: (json['rr'] as num?)?.toDouble(),
        respDisorder: (json['resp_disorder'] as num?)?.toInt(),
        temp: (json['temp'] as num?)?.toDouble(),
      );
}

class HistoryResponse {
  const HistoryResponse({
    required this.range,
    required this.points,
  });

  final String range;
  final List<HistoryPoint> points;

  factory HistoryResponse.fromJson(Map<String, dynamic> json) =>
      HistoryResponse(
        range: json['range'] as String? ?? '',
        points: (json['points'] as List<dynamic>? ?? [])
            .map((e) => HistoryPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // Convenience: avg HR across all non-null points
  double? get avgHr {
    final vals = points.where((p) => p.hr != null).map((p) => p.hr!).toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  // Convenience: avg RR across all non-null points
  double? get avgRr {
    final vals = points.where((p) => p.rr != null).map((p) => p.rr!).toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  // Convenience: total disturbance count
  int get totalDisturbances =>
      points.fold(0, (sum, p) => sum + (p.respDisorder ?? 0));
}
