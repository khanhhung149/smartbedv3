/// Một dòng lịch sử từ GET /api/events. Khớp `store.Event` bên Go.
class Event {
  final int id;

  /// Epoch **MILI-giây** từ thiết bị (contract: firmware/mqtt/README.md — `ts` là unix_ms).
  /// **0 = không có giờ thật** — node publish trước khi NTP sync. Hiển thị phải dùng
  /// [hasTime], đừng format thẳng kẻo ra 1970.
  final int ts;

  /// motion | presence | ac_cmd
  final String kind;

  /// "true"/"false" cho motion+presence; "on"/"off" cho ac_cmd.
  final String value;

  /// voice-node | room-node | backend
  final String source;

  const Event({
    required this.id,
    required this.ts,
    required this.kind,
    required this.value,
    required this.source,
  });

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: (j['id'] as num?)?.toInt() ?? 0,
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        kind: j['kind'] as String? ?? '',
        value: j['value'] as String? ?? '',
        source: j['source'] as String? ?? '',
      );

  bool get hasTime => ts > 0;

  // ts ĐÃ là mili-giây — không nhân 1000 nữa (nhân là ra năm ~58.000).
  DateTime? get time => hasTime ? DateTime.fromMillisecondsSinceEpoch(ts) : null;

  /// true khi value mang nghĩa "bật/có" — dùng để chọn màu/icon.
  bool get isPositive => value == 'true' || value == 'on';

  static const kindMotion = 'motion';
  static const kindPresence = 'presence';
  static const kindAcCmd = 'ac_cmd';
}
