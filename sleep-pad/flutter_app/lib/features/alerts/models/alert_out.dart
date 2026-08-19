// Response model for GET /alerts/{device_id}/history items.
// Fields match backend AlertOut schema exactly.
class AlertOut {
  const AlertOut({
    required this.id,
    required this.deviceId,
    required this.metric,
    required this.value,
    required this.threshold,
    required this.triggeredAt,
  });

  final String id;
  final String deviceId;
  // e.g. "hr_high", "hr_low", "rr_high", "rr_low", "resp_disorder"
  final String metric;
  final double value;
  final double threshold;
  final DateTime triggeredAt;

  factory AlertOut.fromJson(Map<String, dynamic> json) => AlertOut(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        metric: json['metric'] as String,
        value: (json['value'] as num).toDouble(),
        threshold: (json['threshold'] as num).toDouble(),
        triggeredAt: DateTime.parse(json['triggered_at'] as String),
      );

  // Human-readable metric label e.g. "Heart Rate high"
  String get label {
    switch (metric) {
      case 'hr_high':
        return 'Heart Rate high';
      case 'hr_low':
        return 'Heart Rate low';
      case 'rr_high':
        return 'Respiration Rate high';
      case 'rr_low':
        return 'Respiration Rate low';
      case 'resp_disorder':
        return 'Sleep Disturbance';
      default:
        return metric;
    }
  }

  // Unit string per metric
  String get unit {
    if (metric.startsWith('hr')) return 'bpm';
    if (metric.startsWith('rr')) return 'brpm';
    return '/min';
  }

  // Whether this is a high-side alert (coral) vs low (amber) vs disturbance (red)
  AlertSeverity get severity {
    if (metric.endsWith('_high')) return AlertSeverity.high;
    if (metric.endsWith('_low')) return AlertSeverity.low;
    return AlertSeverity.disturbance;
  }
}

enum AlertSeverity { high, low, disturbance }
