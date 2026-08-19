import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/device.dart';
import 'models/event.dart';
import 'models/snapshot.dart';
import 'models/stats.dart';
import 'services/api_client.dart';
import 'services/mqtt_service.dart';
import 'services/ws_client.dart';

/// URL backend. Máy Android không dùng được localhost → phải là IP LAN của máy chạy
/// backend. Giá trị này user sửa trong màn Cài đặt.
const kDefaultBaseUrl = 'http://192.168.1.120:8080';
const _prefsKeyBaseUrl = 'base_url';

/// Nạp SharedPreferences 1 lần lúc khởi động (override ở main.dart).
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('phải override trong main()'),
);

/// URL backend đang dùng: đọc từ prefs lúc build, ghi lại khi đổi.
class BaseUrlNotifier extends Notifier<String> {
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

final baseUrlProvider =
    NotifierProvider<BaseUrlNotifier, String>(BaseUrlNotifier.new);

/// Client REST — dựng lại khi đổi URL.
final apiProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(ref.watch(baseUrlProvider));
  ref.onDispose(client.close);
  return client;
});

/// WS — dựng lại khi đổi URL.
final wsProvider = Provider<WsClient>((ref) {
  final ws = WsClient(ref.watch(baseUrlProvider))..connect();
  ref.onDispose(ws.dispose);
  return ws;
});

final wsConnectedProvider = StreamProvider<bool>(
  (ref) => ref.watch(wsProvider).connection,
);

/// Trạng thái phòng: lấy snapshot đầu bằng REST (WS chỉ push KHI ĐỔI, nên mở app lúc
/// yên tĩnh sẽ không nhận gì), sau đó nghe WS.
final snapshotProvider = StreamProvider<Snapshot>((ref) async* {
  final api = ref.watch(apiProvider);
  try {
    yield await api.getState();
  } catch (_) {
    yield Snapshot.empty;
  }
  yield* ref.watch(wsProvider).snapshots;
});

/// Lịch sử event, tự tải lại khi đổi URL hoặc khi user kéo refresh.
/// Lấy 500 (trần backend) để chart có đủ nhiều ngày; 100 chỉ đủ vài giờ khi phòng bận.
final eventsProvider = FutureProvider<List<Event>>(
  (ref) => ref.watch(apiProvider).getEvents(limit: 500),
);

/// Nguồn thời gian — tiêm được để test/golden xác định. Không có nó thì computeStats
/// đọc đồng hồ thật và kết quả đổi theo lúc chạy.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Số liệu sinh hoạt tính từ lịch sử. Tính lại mỗi khi event đổi.
final statsProvider = Provider<AsyncValue<Stats>>((ref) {
  final now = ref.watch(nowProvider);
  return ref.watch(eventsProvider).whenData((e) => computeStats(e, now: now()));
});

// ---------------------------------------------------------------------------
// Thiết bị MQTT trực tiếp (tách khỏi luồng backend ở trên).
// ---------------------------------------------------------------------------

const _prefsMqttHost = 'mqtt_host';
const _prefsMqttPort = 'mqtt_port';
const _prefsMqttUser = 'mqtt_user';
const _prefsMqttPass = 'mqtt_pass';
const _prefsDevices = 'devices';

/// Broker mặc định = cùng máy chạy backend (192.168.1.120), cổng MQTT chuẩn.
/// User/pass để trống — user tự nhập ở Cài đặt (đây là bí mật, không nhúng sẵn).
class MqttConfigNotifier extends Notifier<MqttConfig> {
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

final mqttConfigProvider =
    NotifierProvider<MqttConfigNotifier, MqttConfig>(MqttConfigNotifier.new);

/// Client MQTT dùng chung — dựng lại khi đổi cấu hình broker.
final mqttServiceProvider = Provider<MqttService>((ref) {
  final svc = MqttService(ref.watch(mqttConfigProvider))..connect();
  ref.onDispose(svc.dispose);
  return svc;
});

// Các stream dưới đây phát ngay giá trị hiện tại rồi mới nghe tiếp — người nghe muộn
// (đổi tab quay lại) vẫn thấy trạng thái mới nhất, không phải chờ message kế.
final mqttConnectedProvider = StreamProvider<bool>((ref) async* {
  final s = ref.watch(mqttServiceProvider);
  yield s.isConnected;
  yield* s.connection;
});

final deviceStatesProvider = StreamProvider<Map<String, DeviceState>>((ref) async* {
  final s = ref.watch(mqttServiceProvider);
  yield s.currentStates;
  yield* s.states;
});

final discoveredTopicsProvider = StreamProvider<List<String>>((ref) async* {
  final s = ref.watch(mqttServiceProvider);
  yield s.currentDiscovered;
  yield* s.discovered;
});

final mqttLogProvider = StreamProvider<List<MqttLogEntry>>((ref) async* {
  final s = ref.watch(mqttServiceProvider);
  yield s.currentLog;
  yield* s.log;
});

/// Danh sách thiết bị đã thêm, lưu bền trong prefs (JSON).
class DevicesNotifier extends Notifier<List<MqttDevice>> {
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

final devicesProvider =
    NotifierProvider<DevicesNotifier, List<MqttDevice>>(DevicesNotifier.new);

/// Bơm danh sách topic cần poll xuống service; tự đồng bộ khi thêm/xoá thiết bị
/// hoặc khi service dựng lại (đổi broker). Watch provider này ở gốc app để giữ sống.
final devicePollBinderProvider = Provider<void>((ref) {
  final svc = ref.watch(mqttServiceProvider);
  final devices = ref.watch(devicesProvider);
  svc.setPolledTopics(devices.map((d) => d.topic).toList());
});
