/// Trạng thái phòng do backend suy ra (fusion motion + presence).
/// Khớp `statemachine.Snapshot` bên Go — xem backend/internal/statemachine/machine.go.
class Snapshot {
  /// Radar thấy người NGAY LÚC NÀY.
  final bool present;

  /// Backend kết luận phòng có người (present + có motion trong EnterWindow).
  /// Khác `present`: chống radar báo giả xuyên tường.
  final bool occupied;

  /// Lệnh AC backend MUỐN (chưa chắc điều hoà đã nhận — chưa có phản hồi ngược).
  final bool acDesired;

  /// Epoch giây từ thiết bị. 0 = thiết bị publish trước khi NTP sync → KHÔNG có giờ thật.
  final int lastMotionTs;
  final int lastPresenceTs;

  final String lastAcCmd;

  const Snapshot({
    required this.present,
    required this.occupied,
    required this.acDesired,
    required this.lastMotionTs,
    required this.lastPresenceTs,
    required this.lastAcCmd,
  });

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        present: j['present'] as bool? ?? false,
        occupied: j['occupied'] as bool? ?? false,
        acDesired: j['ac_desired'] as bool? ?? false,
        lastMotionTs: (j['last_motion_ts'] as num?)?.toInt() ?? 0,
        lastPresenceTs: (j['last_presence_ts'] as num?)?.toInt() ?? 0,
        lastAcCmd: j['last_ac_cmd'] as String? ?? '',
      );

  /// Trạng thái khởi tạo khi chưa gọi được backend.
  static const empty = Snapshot(
    present: false,
    occupied: false,
    acDesired: false,
    lastMotionTs: 0,
    lastPresenceTs: 0,
    lastAcCmd: '',
  );
}
