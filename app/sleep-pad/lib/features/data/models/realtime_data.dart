// RealtimeData: merged view of a sec or min frame streamed via WS.
// Field names match the backend payload exactly (see backend/app/mqtt/parser.py
// SecDataPayload / MinDataPayload) — using different names breaks parsing.
// All optional fields are nullable because min frames carry movement/snore
// while sec frames do not.
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
    this.temp,
  });

  final String deviceId;
  // Device timestamp (seconds since boot) — int per protocol.
  final int ts;
  final double? hr;
  final double? rr;
  final double? sdata;
  final double? pdata;
  final int? movement;
  final int? snore;
  final int? respDisorder;
  final int? statusCode;
  // Body temperature in °C (only present on min frames).
  final double? temp;

  factory RealtimeData.fromJson(Map<String, dynamic> json) => RealtimeData(
        deviceId: json['device_id'] as String? ?? '',
        ts: (json['ts'] as num?)?.toInt() ?? 0,
        // Backend → Flutter field mapping.  Do NOT rename — the producer side
        // uses the protocol names (heart_rate, resp_rate, status, snore_count).
        hr: (json['heart_rate'] as num?)?.toDouble(),
        rr: (json['resp_rate'] as num?)?.toDouble(),
        sdata: (json['sdata'] as num?)?.toDouble(),
        pdata: (json['pdata'] as num?)?.toDouble(),
        movement: (json['movement'] as num?)?.toInt(),
        snore: (json['snore_count'] as num?)?.toInt(),
        respDisorder: (json['resp_disorder'] as num?)?.toInt(),
        statusCode: (json['status'] as num?)?.toInt(),
        temp: (json['temp'] as num?)?.toDouble(),
      );
}
