import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/device.dart';
import 'models/event.dart';
import 'models/snapshot.dart';
import 'models/stats.dart';
import 'services/api_client.dart';
import 'services/mqtt_service.dart';
import 'services/ws_client.dart';

/// URL backend presence/AC. Máy Android không dùng được localhost → phải là IP LAN
/// của máy chạy backend. Giá trị này user sửa trong màn Cài đặt.
///
/// Nạp được từ `--dart-define=RADAR_BASE_URL=...` lúc build để một bản APK phát cho người
/// test là chạy được ngay, không phải gõ tay IP trong Cài đặt. Không đặt thì giữ mặc định cũ.
const kDefaultBaseUrl = String.fromEnvironment(
  'RADAR_BASE_URL',
  defaultValue: 'http://192.168.1.120:8080',
);
const _prefsKeyBaseUrl = 'radar.base_url';

/// Nạp SharedPreferences 1 lần lúc khởi động (override ở main.dart).
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('phải override trong main()'),
);

/// URL backend đang dùng: đọc từ prefs lúc build, ghi lại khi đổi.
class RadarBaseUrlNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.watch(sharedPrefsProvider).getString(_prefsKeyBaseUrl) ??
      kDefaultBaseUrl;

  Future<void> set(String url) async {
    final cleaned = normalize(url);
    await ref.read(sharedPrefsProvider).setString(_prefsKeyBaseUrl, cleaned);
    state = cleaned;
  }

  /// Bỏ dấu / thừa và tự thêm http:// — user gõ tay thì hay thiếu.
  static String normalize(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    return s;
  }
}

final radarBaseUrlProvider =
    NotifierProvider<RadarBaseUrlNotifier, String>(RadarBaseUrlNotifier.new);

/// Client REST presence/AC — dựng lại khi đổi URL.
final radarApiProvider = Provider<RadarApiClient>((ref) {
  final client = RadarApiClient(ref.watch(radarBaseUrlProvider));
  ref.onDispose(client.close);
  return client;
});

/// WS — dựng lại khi đổi URL.
final radarWsProvider = Provider<WsClient>((ref) {
  final ws = WsClient(ref.watch(radarBaseUrlProvider))..connect();
  ref.onDispose(ws.dispose);
  return ws;
});

final radarWsConnectedProvider = StreamProvider<bool>(
  (ref) => ref.watch(radarWsProvider).connection,
);

/// Trạng thái phòng: lấy snapshot đầu bằng REST (WS chỉ push KHI ĐỔI, nên mở app lúc
/// yên tĩnh sẽ không nhận gì), sau đó nghe WS.
final radarSnapshotProvider = StreamProvider<Snapshot>((ref) async* {
  final api = ref.watch(radarApiProvider);
  try {
    yield await api.getState();
  } catch (_) {
    yield Snapshot.empty;
  }
  yield* ref.watch(radarWsProvider).snapshots;
});

/// Lịch sử event, tự tải lại khi đổi URL hoặc khi user kéo refresh.
/// Lấy 500 (trần backend) để chart có đủ nhiều ngày; 100 chỉ đủ vài giờ khi phòng bận.
final radarEventsProvider = FutureProvider<List<Event>>(
  (ref) => ref.watch(radarApiProvider).getEvents(limit: 500),
);

/// Nguồn thời gian — tiêm được để test/golden xác định. Không có nó thì computeStats
/// đọc đồng hồ thật và kết quả đổi theo lúc chạy.
final radarNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Số liệu sinh hoạt tính từ lịch sử. Tính lại mỗi khi event đổi.
final radarStatsProvider = Provider<AsyncValue<Stats>>((ref) {
  final now = ref.watch(radarNowProvider);
  return ref.watch(radarEventsProvider).whenData((e) => computeStats(e, now: now()));
});

// ---------------------------------------------------------------------------
// Thiết bị MQTT trực tiếp (tách khỏi luồng backend ở trên).
// ---------------------------------------------------------------------------

const _prefsMqttHost = 'radar.mqtt_host';
const _prefsMqttPort = 'radar.mqtt_port';
const _prefsMqttUser = 'radar.mqtt_user';
const _prefsMqttPass = 'radar.mqtt_pass';
const _prefsDevices = 'radar.devices';

/// Broker mặc định = cùng máy chạy backend (192.168.1.120), cổng MQTT chuẩn.
/// User/pass để trống — user tự nhập ở Cài đặt (đây là bí mật, không nhúng sẵn).
class RadarMqttConfigNotifier extends Notifier<MqttConfig> {
  @override
  MqttConfig build() {
    final p = ref.watch(sharedPrefsProvider);
    return MqttConfig(
      host: p.getString(_prefsMqttHost) ?? '192.168.1.120',
      port: p.getInt(_prefsMqttPort) ?? 1883,
      username: p.getString(_prefsMqttUser) ?? '',
      password: p.getString(_prefsMqttPass) ?? '',
    );
  }

  Future<void> set(MqttConfig c) async {
    final p = ref.read(sharedPrefsProvider);
    await p.setString(_prefsMqttHost, c.host);
    await p.setInt(_prefsMqttPort, c.port);
    await p.setString(_prefsMqttUser, c.username);
    await p.setString(_prefsMqttPass, c.password);
    state = c;
  }
}

final radarMqttConfigProvider =
    NotifierProvider<RadarMqttConfigNotifier, MqttConfig>(RadarMqttConfigNotifier.new);

/// Client MQTT dùng chung — dựng lại khi đổi cấu hình broker.
final radarMqttServiceProvider = Provider<MqttService>((ref) {
  final svc = MqttService(ref.watch(radarMqttConfigProvider))..connect();
  ref.onDispose(svc.dispose);
  return svc;
});

// Các stream dưới đây phát ngay giá trị hiện tại rồi mới nghe tiếp — người nghe muộn
// (đổi tab quay lại) vẫn thấy trạng thái mới nhất, không phải chờ message kế.
final radarMqttConnectedProvider = StreamProvider<bool>((ref) async* {
  final s = ref.watch(radarMqttServiceProvider);
  yield s.isConnected;
  yield* s.connection;
});

final radarDeviceStatesProvider = StreamProvider<Map<String, DeviceState>>((ref) async* {
  final s = ref.watch(radarMqttServiceProvider);
  yield s.currentStates;
  yield* s.states;
});

final radarDiscoveredTopicsProvider = StreamProvider<List<String>>((ref) async* {
  final s = ref.watch(radarMqttServiceProvider);
  yield s.currentDiscovered;
  yield* s.discovered;
});

final radarMqttLogProvider = StreamProvider<List<MqttLogEntry>>((ref) async* {
  final s = ref.watch(radarMqttServiceProvider);
  yield s.currentLog;
  yield* s.log;
});

/// Danh sách thiết bị đã thêm, lưu bền trong prefs (JSON).
class RadarDevicesNotifier extends Notifier<List<MqttDevice>> {
  @override
  List<MqttDevice> build() =>
      MqttDevice.listFromJson(ref.watch(sharedPrefsProvider).getString(_prefsDevices) ?? '');

  Future<void> _persist() async => ref
      .read(sharedPrefsProvider)
      .setString(_prefsDevices, MqttDevice.listToJson(state));

  Future<void> add(MqttDevice d) async {
    if (state.any((e) => e.topic == d.topic)) return;
    state = [...state, d];
    await _persist();
  }

  Future<void> remove(String topic) async {
    state = state.where((e) => e.topic != topic).toList();
    await _persist();
  }

  Future<void> rename(String topic, String name) async {
    state = [
      for (final e in state)
        e.topic == topic ? MqttDevice(topic: e.topic, name: name, ip: e.ip) : e,
    ];
    await _persist();
  }
}

final radarDevicesProvider =
    NotifierProvider<RadarDevicesNotifier, List<MqttDevice>>(RadarDevicesNotifier.new);

/// Bơm danh sách topic cần poll xuống service; tự đồng bộ khi thêm/xoá thiết bị
/// hoặc khi service dựng lại (đổi broker). Watch provider này ở gốc app để giữ sống.
final radarDevicePollBinderProvider = Provider<void>((ref) {
  final svc = ref.watch(radarMqttServiceProvider);
  final devices = ref.watch(radarDevicesProvider);
  svc.setPolledTopics(devices.map((d) => d.topic).toList());
});
