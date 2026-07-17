import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/event.dart';
import 'models/snapshot.dart';
import 'models/stats.dart';
import 'services/api_client.dart';
import 'services/ws_client.dart';

/// URL backend. Máy Android không dùng được localhost → phải là IP LAN của máy chạy
/// backend. Giá trị này user sửa trong màn Cài đặt.
const kDefaultBaseUrl = 'http://192.168.1.95:8080';
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
