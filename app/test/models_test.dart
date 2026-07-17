import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
