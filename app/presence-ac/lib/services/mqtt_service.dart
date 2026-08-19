import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/device.dart';

/// Cấu hình broker MQTT. Mật khẩu là của broker LAN nội bộ — lưu prefs, KHÔNG commit.
class MqttConfig {
  final String host;
  final int port;
  final String username;
  final String password;

  const MqttConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  MqttConfig copyWith({String? host, int? port, String? username, String? password}) =>
      MqttConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
      );

  bool get isValid => host.isNotEmpty && port > 0;

  static const empty = MqttConfig(host: '', port: 1883, username: '', password: '');
}

/// Một dòng log MQTT thô — dùng để soi payload thật của thiết bị mà hiệu chỉnh parser.
class MqttLogEntry {
  final DateTime time;
  final String topic;
  final String payload;
  const MqttLogEntry(this.time, this.topic, this.payload);
}

/// Client MQTT dùng chung: kết nối broker qua TCP, nghe mọi topic thiết bị, dựng
/// [DeviceState] theo từng thiết bị, và poll `STATUS 10` để có dữ liệu gần thời gian
/// thực dù thiết bị đặt chu kì publish chậm.
class MqttService {
  final MqttConfig config;
  MqttService(this.config);

  MqttServerClient? _client;
  Timer? _pollTimer;
  Timer? _retry;
  Timer? _freshTick;
  bool _closed = false;

  final _conn = StreamController<bool>.broadcast();
  final _states = StreamController<Map<String, DeviceState>>.broadcast();
  final _discovered = StreamController<List<String>>.broadcast();
  final _log = StreamController<List<MqttLogEntry>>.broadcast();

  final Map<String, DeviceState> _stateMap = {};
  final Set<String> _discoveredSet = {};
  final List<MqttLogEntry> _logBuf = [];
  List<String> _polled = const [];

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  Map<String, DeviceState> get currentStates => Map.unmodifiable(_stateMap);
  List<String> get currentDiscovered => _discoveredSet.toList()..sort();
  List<MqttLogEntry> get currentLog => List.unmodifiable(_logBuf);

  Stream<bool> get connection => _conn.stream;
  Stream<Map<String, DeviceState>> get states => _states.stream;
  Stream<List<String>> get discovered => _discovered.stream;
  Stream<List<MqttLogEntry>> get log => _log.stream;

  Future<void> connect() async {
    if (_closed || !config.isValid) return;
    _retry?.cancel();
    _startFreshnessTick();

    final id = 'home_ac_${Random().nextInt(1 << 31)}';
    final c = MqttServerClient.withPort(config.host, id, config.port);
    c.logging(on: false);
    c.setProtocolV311();
    c.keepAlivePeriod = 20;
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = true;
    c.onConnected = _onConnected;
    c.onDisconnected = _onDisconnected;
    c.connectionMessage =
        MqttConnectMessage().withClientIdentifier(id).startClean();
    _client = c;

    try {
      await c.connect(
        config.username.isEmpty ? null : config.username,
        config.password.isEmpty ? null : config.password,
      );
    } catch (_) {
      _conn.add(false);
      _scheduleRetry();
      return;
    }
    c.updates?.listen(_onMessage);
  }

  void _onConnected() {
    // Bắt trọn topic thiết bị theo kiểu tele/stat prefix (prefix đứng đầu).
    for (final t in const ['tele/+/#', 'stat/+/#']) {
      _client?.subscribe(t, MqttQos.atMostOnce);
    }
    _conn.add(true);
    _startPoll();
    _pollNow();
  }

  void _onDisconnected() {
    _conn.add(false);
    // autoReconnect của mqtt_client tự nối lại; chỉ cần phản ánh trạng thái.
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), connect);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final ev in events) {
      final msg = ev.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      _logAdd(ev.topic, payload);
      _route(ev.topic, payload);
    }
    _states.add(currentStates);
    _discovered.add(currentDiscovered);
  }

  void _route(String topic, String payload) {
    final parts = topic.split('/');
    if (parts.length < 3) return;
    final dev = parts[1]; // %topic%
    final leaf = parts.sublist(2).join('/');
    _discoveredSet.add(dev);
    final cur = _stateMap[dev] ?? DeviceState(topic: dev);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (leaf == 'LWT') {
      // Báo Offline (will của thiết bị) thì bỏ luôn số đọc cũ — giữ lại chỉ tổ hiện
      // "Có người" của một cái xác. radar-node KHÔNG đi đường này (will đã dành cho
      // home/room/presence, MQTT chỉ cho 1 will) nên nó chết theo độ tươi lastSeen.
      _stateMap[dev] = payload.toLowerCase().contains('online')
          ? cur.copyWith(online: true, lastSeenMs: now)
          : DeviceState(topic: dev, lastSeenMs: now);
      return;
    }
    if (leaf == 'SENSOR' || leaf == 'RESULT' || leaf.startsWith('STATUS')) {
      Map<String, dynamic> j;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) return;
        j = decoded.cast<String, dynamic>();
      } catch (_) {
        return;
      }
      _stateMap[dev] = cur.applySensor(j).copyWith(online: true);
    }
  }

  void _logAdd(String topic, String payload) {
    _logBuf.insert(0, MqttLogEntry(DateTime.now(), topic, payload));
    if (_logBuf.length > 300) {
      _logBuf.removeRange(300, _logBuf.length);
    }
    _log.add(currentLog);
  }

  /// Phát lại state mỗi giây dù không có message mới.
  ///
  /// Thiếu nhịp này thì lúc thiết bị chết stream im hẳn (chỗ duy nhất emit là
  /// `_onMessage`) → UI đứng nguyên ở trạng thái cuối, "Có người" mãi mãi. Việc
  /// đánh giá tươi/cũ nằm ở [DeviceState.viewAt], đây chỉ là đồng hồ để UI tính lại.
  void _startFreshnessTick() {
    _freshTick?.cancel();
    _freshTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_closed || _stateMap.isEmpty) return;
      _states.add(currentStates);
    });
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollNow());
  }

  /// Bắn `cmnd/<topic>/STATUS 10` để thiết bị publish ngay khối cảm biến — không
  /// phải chờ TelePeriod (mặc định 300s). Payload "10" = Status 10.
  void _pollNow() {
    if (!isConnected) return;
    for (final t in _polled) {
      final b = MqttClientPayloadBuilder()..addString('10');
      _client?.publishMessage('cmnd/$t/STATUS', MqttQos.atMostOnce, b.payload!);
    }
  }

  /// Danh sách topic thiết bị đã thêm cần poll. Gọi lại mỗi khi thêm/xoá thiết bị.
  void setPolledTopics(List<String> topics) {
    _polled = List.of(topics);
    _pollNow();
  }

  /// Gửi lệnh MQTT bất kỳ, vd cmnd="POWER", payload="TOGGLE".
  void sendCommand(String topic, String cmnd, String payload) {
    if (!isConnected) return;
    final b = MqttClientPayloadBuilder()..addString(payload);
    _client?.publishMessage('cmnd/$topic/$cmnd', MqttQos.atMostOnce, b.payload!);
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    _pollTimer?.cancel();
    _freshTick?.cancel();
    try {
      _client?.disconnect();
    } catch (_) {}
    _conn.close();
    _states.close();
    _discovered.close();
    _log.close();
  }

  /// Thử kết nối nhanh cho nút "Thử kết nối" ở Cài đặt. Trả 'ok' hoặc mô tả lỗi.
  static Future<String> test(MqttConfig cfg) async {
    if (!cfg.isValid) return 'Chưa nhập host';
    final id = 'home_ac_test_${Random().nextInt(1 << 31)}';
    final c = MqttServerClient.withPort(cfg.host, id, cfg.port);
    c.logging(on: false);
    c.setProtocolV311();
    c.connectTimeoutPeriod = 4000;
    c.connectionMessage =
        MqttConnectMessage().withClientIdentifier(id).startClean();
    try {
      final s = await c.connect(
        cfg.username.isEmpty ? null : cfg.username,
        cfg.password.isEmpty ? null : cfg.password,
      );
      final ok = s?.state == MqttConnectionState.connected;
      c.disconnect();
      return ok ? 'ok' : 'Broker từ chối (${s?.returnCode})';
    } catch (e) {
      c.disconnect();
      return 'Lỗi: $e';
    }
  }
}
