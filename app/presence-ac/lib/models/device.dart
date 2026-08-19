import 'dart:convert';

/// Thiết bị MQTT đã thêm — chỉ cần MQTT `topic` để biết nghe/gửi lệnh ở đâu.
/// `ip` tuỳ chọn, chỉ để mở web UI; điều khiển/đọc đều đi qua MQTT.
class MqttDevice {
  final String topic; // MQTT topic, vd "radar_phong_khach"
  final String name; // tên hiển thị do user đặt
  final String? ip;

  const MqttDevice({required this.topic, required this.name, this.ip});

  Map<String, dynamic> toJson() =>
      {'topic': topic, 'name': name, if (ip != null && ip!.isNotEmpty) 'ip': ip};

  factory MqttDevice.fromJson(Map<String, dynamic> j) {
    final t = (j['topic'] as String?) ?? '';
    final n = (j['name'] as String?)?.trim();
    return MqttDevice(
      topic: t,
      name: (n != null && n.isNotEmpty) ? n : t,
      ip: (j['ip'] as String?)?.trim(),
    );
  }

  static List<MqttDevice> listFromJson(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => MqttDevice.fromJson((e as Map).cast<String, dynamic>()))
          .where((d) => d.topic.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String listToJson(List<MqttDevice> l) =>
      jsonEncode(l.map((e) => e.toJson()).toList());
}

/// Trạng thái chạy của 1 thiết bị, dựng dần từ MQTT.
///
/// Parser CỐ Ý KHOAN DUNG: payload LD2410 mỗi firmware một khác (Detect vs
/// Presence, Moving/Static lồng nhau vs phẳng...). Không rõ thì để null thay vì
/// đoán bừa. Mở màn "Log MQTT" xem payload THẬT của thiết bị rồi tinh chỉnh lại.
class DeviceState {
  final String topic;
  final bool online; // từ LWT (Online/Offline)
  final bool? occupied; // có người; null = chưa xác định được
  final int? movingDistance; // cm
  final int? movingEnergy; // 0-100
  final int? staticDistance;
  final int? staticEnergy;
  final int lastSeenMs; // giờ máy nhận message gần nhất

  const DeviceState({
    required this.topic,
    this.online = false,
    this.occupied,
    this.movingDistance,
    this.movingEnergy,
    this.staticDistance,
    this.staticEnergy,
    this.lastSeenMs = 0,
  });

  /// copyWith giữ giá trị cũ khi tham số null — nghĩa là "không có tin mới thì giữ
  /// nguyên", đúng ý khi mỗi message chỉ mang một phần dữ liệu.
  DeviceState copyWith({
    bool? online,
    bool? occupied,
    int? movingDistance,
    int? movingEnergy,
    int? staticDistance,
    int? staticEnergy,
    int? lastSeenMs,
  }) =>
      DeviceState(
        topic: topic,
        online: online ?? this.online,
        occupied: occupied ?? this.occupied,
        movingDistance: movingDistance ?? this.movingDistance,
        movingEnergy: movingEnergy ?? this.movingEnergy,
        staticDistance: staticDistance ?? this.staticDistance,
        staticEnergy: staticEnergy ?? this.staticEnergy,
        lastSeenMs: lastSeenMs ?? this.lastSeenMs,
      );

  /// Không nhận message nào trong khoảng này thì coi thiết bị đã chết. Radar đẩy
  /// `tele/<T>/SENSOR` mỗi 3s và app poll `STATUS 10` mỗi 2s → 15s là đã bỏ lỡ ~5
  /// nhịp: đủ chắc để kết luận, mà không nháy offline khi mạng chớp một cái.
  static const staleAfter = Duration(seconds: 15);

  bool staleAt(int nowMs) =>
      lastSeenMs <= 0 || nowMs - lastSeenMs > staleAfter.inMilliseconds;

  /// Bản dùng để hiển thị. Quá [staleAfter] không thấy tin thì KHÔNG dùng số liệu
  /// cũ nữa: `online=false`, `occupied=null`, cự ly/năng lượng về null.
  ///
  /// Độ tươi là cách DUY NHẤT app biết radar chết: `tele/<T>/LWT` kẹt "Online"
  /// vĩnh viễn vì MQTT chỉ cho 1 will/kết nối và will đã dành cho
  /// `home/room/presence` (backend cần nó hơn). Dựng object mới thay vì copyWith
  /// vì copyWith cố ý giữ giá trị cũ khi tham số null — không xoá được gì.
  DeviceState viewAt(int nowMs) => staleAt(nowMs)
      ? DeviceState(topic: topic, lastSeenMs: lastSeenMs)
      : this;

  /// Cập nhật từ JSON của `tele/../SENSOR`, `stat/../RESULT` hoặc `stat/../STATUS10`.
  DeviceState applySensor(Map<String, dynamic> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ld = _findLd2410(json);
    if (ld == null) return copyWith(lastSeenMs: now);

    final moving = _asMap(ld['Moving']) ?? _asMap(ld['moving']);
    final stat = _asMap(ld['Static']) ??
        _asMap(ld['Stationary']) ??
        _asMap(ld['static']);

    final mDist = _asInt(moving?['Distance'] ?? ld['MovingDistance'] ?? ld['Distance']);
    final mEng = _asInt(moving?['Energy'] ?? ld['MovingEnergy']);
    final sDist = _asInt(stat?['Distance'] ?? ld['StaticDistance']);
    final sEng = _asInt(stat?['Energy'] ?? ld['StaticEnergy']);

    // Ưu tiên cờ trạng thái tường minh; không có thì suy từ năng lượng/cự ly.
    bool? occ = _truthy(ld['Detect'] ??
        ld['Presence'] ??
        ld['Occupancy'] ??
        ld['Occupied'] ??
        ld['Target'] ??
        ld['State']);
    if (occ == null) {
      final anyNum =
          mEng != null || sEng != null || mDist != null || sDist != null;
      if (anyNum) {
        occ = (mEng ?? 0) > 0 ||
            (sEng ?? 0) > 0 ||
            (mDist ?? 0) > 0 ||
            (sDist ?? 0) > 0;
      }
    }

    return copyWith(
      occupied: occ,
      movingDistance: mDist,
      movingEnergy: mEng,
      staticDistance: sDist,
      staticEnergy: sEng,
      lastSeenMs: now,
    );
  }

  /// Tìm object LD2410 trong SENSOR/StatusSNS, không phân biệt hoa thường.
  static Map<String, dynamic>? _findLd2410(Map<String, dynamic> j) {
    // `Status 10` bọc trong {"StatusSNS":{...}}.
    final root = _asMap(j['StatusSNS']) ?? j;
    for (final e in root.entries) {
      if (e.key.toLowerCase().contains('ld2410')) {
        final m = _asMap(e.value);
        if (m != null) return m;
      }
    }
    // Có bản để field nằm thẳng ở root (Detect/Moving...): trả root để thử tiếp.
    return root;
  }

  static Map<String, dynamic>? _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : null;

  static int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static bool? _truthy(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (['1', 'on', 'true', 'yes', 'detected', 'occupied', 'present']
        .contains(s)) {
      return true;
    }
    if (['0', 'off', 'false', 'no', 'clear', 'vacant', 'absent'].contains(s)) {
      return false;
    }
    return null;
  }
}
