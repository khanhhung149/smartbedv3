import 'package:flutter_test/flutter_test.dart';
import 'package:home_ac/services/api_client.dart';

/// Test gọi BACKEND THẬT để bắt lệch contract giữa app và Go — unit test parse JSON
/// tự gõ không phát hiện được khi backend đổi tên field.
///
/// Backend không chạy thì tự SKIP (không làm đỏ suite). Muốn chạy thật:
///   cd backend && docker compose up -d
///   cd app && flutter test
///
/// Chạy trên Dart VM của máy nên localhost OK; máy Android thật thì phải IP LAN.
void main() {
  const baseUrl = 'http://localhost:8080';

  late ApiClient api;
  var backendUp = false;

  setUpAll(() async {
    final probe = ApiClient(baseUrl);
    backendUp = await probe.healthy();
    probe.close();
  });

  setUp(() => api = ApiClient(baseUrl));
  tearDown(() => api.close());

  /// Bỏ qua khi backend không chạy — báo skip rõ ràng thay vì fail mù mờ.
  bool skipIfDown() {
    if (!backendUp) {
      markTestSkipped('backend không chạy ở $baseUrl — bỏ qua test live');
      return true;
    }
    return false;
  }

  test('GET /api/state parse được dữ liệu thật', () async {
    if (skipIfDown()) return;
    final s = await api.getState();
    // Không khẳng định giá trị (tuỳ phòng lúc chạy), chỉ cần parse không ném lỗi và
    // field đúng kiểu — đó là thứ vỡ khi backend đổi contract.
    expect(s.lastAcCmd, isA<String>());
    expect(s.lastMotionTs, isA<int>());
  });

  test('GET /api/events parse được dữ liệu thật', () async {
    if (skipIfDown()) return;
    final events = await api.getEvents(limit: 5);
    for (final e in events) {
      expect(e.id, greaterThan(0));
      expect(['motion', 'presence', 'ac_cmd'], contains(e.kind),
          reason: 'backend trả kind lạ "${e.kind}" — app chưa biết hiển thị');
    }
  });

  test('phân trang before= chỉ trả event cũ hơn', () async {
    if (skipIfDown()) return;
    final first = await api.getEvents(limit: 1);
    if (first.isEmpty) return; // DB rỗng, không có gì để phân trang
    final second = await api.getEvents(limit: 1, before: first.first.id);
    for (final e in second) {
      expect(e.id, lessThan(first.first.id));
    }
  });

  // Không cần backend: URL chết luôn báo lỗi tiếng Việt, không ném stack trace thô ra UI.
  test('URL sai báo lỗi tiếng Việt', () async {
    final bad = ApiClient('http://192.0.2.1:9999'); // TEST-NET-1, chắc chắn không tồn tại
    await expectLater(
      bad.getState(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('Không kết nối được'))),
    );
    bad.close();
  });
}
