// RealtimeData: maps the sec_data row streamed via WS /ws/{device_id}?token=...
// All fields are nullable — sensor may emit partial frames.
class RealtimeData {
  const RealtimeData({
    required this.deviceId,
    required this.ts,
    this.hr,
    this.rr,
    this.sdata,
    this.pdata,
    this.movement,
    this.snore,
    this.respDisorder,
    this.statusCode,
  });

  final String deviceId;
  final String ts;
  final double? hr;
  final double? rr;
  // Raw signal amplitude (percentage displayed as-is)
  final double? sdata;
  // Piezo voltage reading
  final double? pdata;
  // Movement intensity (0–100)
  final int? movement;
  // Snore event count in this second
  final int? snore;
  // Respiration disorder flag count
  final int? respDisorder;
  // ESP32 status code 0x01–0x08
  final int? statusCode;

  factory RealtimeData.fromJson(Map<String, dynamic> json) => RealtimeData(
        deviceId: json['device_id'] as String? ?? '',
        ts: json['ts'] as String? ?? '',
        hr: (json['hr'] as num?)?.toDouble(),
        rr: (json['rr'] as num?)?.toDouble(),
        sdata: (json['sdata'] as num?)?.toDouble(),
        pdata: (json['pdata'] as num?)?.toDouble(),
        movement: json['movement'] as int?,
        snore: json['snore'] as int?,
        respDisorder: json['resp_disorder'] as int?,
        statusCode: json['status_code'] as int?,
      );
}
