import 'package:flutter_test/flutter_test.dart';
import 'package:home_ac/models/event.dart';
import 'package:home_ac/models/stats.dart';

/// now cố định để test xác định — không phụ thuộc lúc chạy.
final now = DateTime(2026, 7, 17, 12, 0);
final today = DateTime(2026, 7, 17);

int _id = 0;
Event ev(String kind, String value, DateTime t) => Event(
      id: ++_id,
      ts: t.millisecondsSinceEpoch ~/ 1000,
      kind: kind,
      value: value,
      source: 'test',
    );

void main() {
  setUp(() => _id = 0);

  group('computeStats — thời gian ở phòng', () {
    test('cặp presence true→false cộng đúng khoảng', () {
      final s = computeStats([
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 17, 10, 30)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 10, 0)),
      ], now: now);

      expect(s.today.occupied, const Duration(minutes: 30));
    });

    test('phiên đang mở tính tới BÂY GIỜ, không bỏ sót', () {
      // Vào phòng 11:00, chưa ra. now=12:00 → phải là 1 tiếng.
      final s = computeStats([
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 11, 0)),
      ], now: now);

      expect(s.today.occupied, const Duration(hours: 1));
    });

    test('true lặp lại không reset mốc bắt đầu', () {
      final s = computeStats([
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 17, 10, 30)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 10, 15)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 10, 0)),
      ], now: now);

      // Phải tính từ 10:00 (lần true đầu), không phải 10:15.
      expect(s.today.occupied, const Duration(minutes: 30));
    });

    test('false lẻ không có true trước đó thì bỏ qua, không âm', () {
      final s = computeStats([
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 17, 10, 0)),
      ], now: now);

      expect(s.today.occupied, Duration.zero);
    });
  });

  group('computeStats — điều hoà', () {
    test('cặp ac_cmd on→off cộng đúng', () {
      final s = computeStats([
        ev(Event.kindAcCmd, 'off', DateTime(2026, 7, 17, 9, 0)),
        ev(Event.kindAcCmd, 'on', DateTime(2026, 7, 17, 8, 0)),
      ], now: now);

      expect(s.today.acOn, const Duration(hours: 1));
    });
  });

  group('computeStats — chuyển động', () {
    test('đếm đúng và gom theo giờ', () {
      final s = computeStats([
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 17, 8, 15)),
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 17, 8, 5)),
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 17, 9, 30)),
      ], now: now);

      expect(s.today.motionCount, 3);
      expect(s.motionByHour[8], 2);
      expect(s.motionByHour[9], 1);
      expect(s.motionByHour[0], 0);
      expect(s.motionByHour.length, 24);
    });
  });

  group('computeStats — trung thực khi thiếu dữ liệu', () {
    test('không có dữ liệu hôm qua → yesterday=null, KHÔNG phải 0', () {
      final s = computeStats([
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 17, 8, 0)),
      ], now: now);

      expect(s.yesterday, isNull, reason: 'thiếu dữ liệu ≠ bằng 0');
      expect(s.occupiedTrend, isNull, reason: 'không được bịa xu hướng khi chưa biết hôm qua');
      expect(s.motionTrend, isNull);
    });

    test('hôm qua = 0 → trend null, không chia cho 0 ra vô cực', () {
      final s = computeStats([
        // Hôm qua chỉ có motion, không có presence → occupied hôm qua = 0
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 16, 8, 0)),
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 17, 11, 0)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 10, 0)),
      ], now: now);

      expect(s.yesterday, isNotNull);
      expect(s.occupiedTrend, isNull, reason: 'hôm qua=0 thì % vô nghĩa');
    });

    test('có dữ liệu 2 ngày → tính được % thật', () {
      final s = computeStats([
        // Hôm qua ở 1 tiếng
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 16, 11, 0)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 16, 10, 0)),
        // Hôm nay ở 2 tiếng → +100%
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 17, 11, 0)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 9, 0)),
      ], now: now);

      expect(s.yesterday!.occupied, const Duration(hours: 1));
      expect(s.today.occupied, const Duration(hours: 2));
      expect(s.occupiedTrend, 100.0);
    });

    test('event ts=0 bị loại, không tạo khoảng rác từ 1970', () {
      final s = computeStats([
        Event(id: 1, ts: 0, kind: Event.kindPresence, value: 'true', source: 'room-node'),
        ev(Event.kindPresence, 'false', DateTime(2026, 7, 17, 10, 30)),
        ev(Event.kindPresence, 'true', DateTime(2026, 7, 17, 10, 0)),
      ], now: now);

      // Nếu ts=0 lọt vào, occupied sẽ là ~56 NĂM.
      expect(s.today.occupied, const Duration(minutes: 30));
    });

    test('danh sách rỗng không nổ', () {
      final s = computeStats([], now: now);
      expect(s.today.isEmpty, isTrue);
      expect(s.yesterday, isNull);
      expect(s.recentDays, isEmpty);
    });

    test('toàn event ts=0 → coi như rỗng', () {
      final s = computeStats([
        Event(id: 1, ts: 0, kind: Event.kindPresence, value: 'true', source: 'x'),
      ], now: now);
      expect(s.today.isEmpty, isTrue);
    });
  });

  group('computeStats — nhiều ngày', () {
    test('recentDays sắp cũ→mới cho biểu đồ cột', () {
      final s = computeStats([
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 15, 8, 0)),
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 17, 8, 0)),
        ev(Event.kindMotion, 'true', DateTime(2026, 7, 16, 8, 0)),
      ], now: now);

      expect(s.recentDays.length, 3);
      expect(s.recentDays.first.day, DateTime(2026, 7, 15));
      expect(s.recentDays.last.day, DateTime(2026, 7, 17));
    });
  });
}
