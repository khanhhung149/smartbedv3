import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_ac/models/device.dart';
import 'package:home_ac/models/event.dart';
import 'package:home_ac/models/snapshot.dart';
import 'package:home_ac/providers.dart';

void main() {
  group('Snapshot.fromJson', () {
    test('đọc đúng payload thật của GET /api/state', () {
      // Payload này copy từ backend đang chạy thật, không phải bịa.
      final j = jsonDecode('''
        {"present":true,"occupied":true,"ac_desired":true,
         "last_motion_ts":1784214584,"last_presence_ts":1784214584,"last_ac_cmd":"on"}
      ''') as Map<String, dynamic>;

      final s = Snapshot.fromJson(j);
      expect(s.present, isTrue);
      expect(s.occupied, isTrue);
      expect(s.acDesired, isTrue);
      expect(s.lastMotionTs, 1784214584);
      expect(s.lastAcCmd, 'on');
    });

    test('thiếu field thì về default thay vì ném lỗi', () {
      final s = Snapshot.fromJson(jsonDecode('{}') as Map<String, dynamic>);
      expect(s.present, isFalse);
      expect(s.lastAcCmd, '');
      expect(s.lastMotionTs, 0);
    });
  });

  group('Event', () {
    test('đọc đúng payload thật của GET /api/events', () {
      final j = jsonDecode(
              '{"id":4,"ts":1784214584,"kind":"ac_cmd","value":"on","source":"backend"}')
          as Map<String, dynamic>;
      final e = Event.fromJson(j);
      expect(e.id, 4);
      expect(e.kind, Event.kindAcCmd);
      expect(e.isPositive, isTrue);
      expect(e.hasTime, isTrue);
      expect(e.time, isNotNull);
    });

    // Chặn tái phát bug đơn vị: contract MQTT (firmware/mqtt/README.md) quy định ts là
    // MILI-giây. Trước đây app nhân thêm 1000 -> mọi event từ phần cứng thật hiện năm
    // ~58.000. Không phát hiện được vì test cũ tự bơm ts bằng GIÂY.
    test('ts là MILI-giây, không nhân thêm 1000', () {
      final e = Event.fromJson(
          jsonDecode('{"id":1,"ts":1784214584000,"kind":"motion","value":"true","source":"voice-node"}')
              as Map<String, dynamic>);
      expect(e.time!.year, 2026, reason: 'nhân 1000 lần nữa sẽ ra năm ~58.000');
      expect(e.time, DateTime.fromMillisecondsSinceEpoch(1784214584000));
    });

    test('ts=0 phải coi là KHÔNG có giờ, không phải 1970', () {
      // Message retained trên broker mang ts=0 khi node publish trước lúc NTP sync.
      // Nếu coi 0 là giờ hợp lệ thì lịch sử hiện "01/01 07:00" — sai và khó hiểu.
      final e = Event.fromJson(
          jsonDecode('{"id":1,"ts":0,"kind":"presence","value":"true","source":"room-node"}')
              as Map<String, dynamic>);
      expect(e.hasTime, isFalse);
      expect(e.time, isNull);
    });

    test('isPositive phân biệt đúng true/on với false/off', () {
      Event mk(String v) => Event(id: 1, ts: 1, kind: 'x', value: v, source: 's');
      expect(mk('true').isPositive, isTrue);
      expect(mk('on').isPositive, isTrue);
      expect(mk('false').isPositive, isFalse);
      expect(mk('off').isPositive, isFalse);
    });
  });

  group('DeviceState độ tươi', () {
    // Bug thật: rút nguồn radar-node thì tab "Thiết bị" vẫn hiện "Có người" mãi.
    // tele/<T>/LWT kẹt "Online" (will đã dời sang home/room/presence, MQTT chỉ cho
    // 1 will/kết nối) nên lastSeen là dấu hiệu DUY NHẤT nói thiết bị đã chết.
    const t0 = 1784214584000;
    const live = DeviceState(
      topic: 'radar_phong',
      online: true,
      occupied: true,
      movingDistance: 120,
      movingEnergy: 40,
      staticDistance: 80,
      staticEnergy: 20,
      lastSeenMs: t0,
    );

    test('còn trong ngưỡng thì giữ nguyên số liệu', () {
      expect(live.staleAt(t0 + 14000), isFalse);
      final v = live.viewAt(t0 + 14000);
      expect(v.occupied, isTrue);
      expect(v.online, isTrue);
      expect(v.movingDistance, 120);
    });

    test('quá ngưỡng thì offline, occupied null, số liệu cũ bị bỏ', () {
      expect(live.staleAt(t0 + 16000), isTrue);
      final v = live.viewAt(t0 + 16000);
      expect(v.online, isFalse, reason: 'LWT nói Online nhưng board đã chết');
      expect(v.occupied, isNull, reason: 'không được nói "Có người" nữa');
      expect(v.movingDistance, isNull);
      expect(v.movingEnergy, isNull);
      expect(v.staticDistance, isNull);
      expect(v.staticEnergy, isNull);
      expect(v.lastSeenMs, t0, reason: 'vẫn cần để hiện "x phút trước"');
    });

    test('chưa nhận message nào thì coi là cũ', () {
      expect(const DeviceState(topic: 'x').staleAt(t0), isTrue);
    });

    // Chốt lý do viewAt dựng object mới: copyWith CỐ Ý giữ giá trị cũ khi tham số
    // null, nên không thể dùng nó để xoá occupied.
    test('copyWith(occupied: null) không xoá được — nên viewAt phải dựng mới', () {
      expect(live.copyWith(occupied: null).occupied, isTrue);
    });
  });

  group('BaseUrlNotifier.normalize', () {
    test('tự thêm http:// khi user chỉ gõ IP', () {
      expect(BaseUrlNotifier.normalize('192.168.1.95:8080'),
          'http://192.168.1.95:8080');
    });

    test('bỏ dấu / thừa ở cuối — nếu không URL sẽ thành //api/state', () {
      expect(BaseUrlNotifier.normalize('http://192.168.1.95:8080/'),
          'http://192.168.1.95:8080');
      expect(BaseUrlNotifier.normalize('http://192.168.1.95:8080///'),
          'http://192.168.1.95:8080');
    });

    test('giữ nguyên https và cắt khoảng trắng', () {
      expect(BaseUrlNotifier.normalize('  https://abc.com  '), 'https://abc.com');
    });
  });
}
