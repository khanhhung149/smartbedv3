import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_ac/models/device.dart';
import 'package:home_ac/services/mqtt_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Test chạy [MqttService] THẬT trên broker THẬT rồi đóng vai radar chết giữa chừng.
///
/// Cái này bắt được thứ unit test không bao giờ thấy: khi thiết bị im, stream có
/// tiếp tục phát không. Logic độ tươi đúng mà thiếu nhịp phát lại thì UI vẫn đứng
/// nguyên "Có người" — chính là bug gốc, và nó chỉ lộ khi timer chạy trên thời gian thật.
///
/// Không có broker/credential thì tự SKIP. Muốn chạy thật:
///   MQTT_HOST=192.168.1.120 MQTT_USER=... MQTT_PASS=... flutter test test/mqtt_live_test.dart
///
/// Credential lấy từ biến môi trường, KHÔNG viết vào repo.
void main() {
  final host = Platform.environment['MQTT_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['MQTT_PORT'] ?? '') ?? 1883;
  final user = Platform.environment['MQTT_USER'] ?? '';
  final pass = Platform.environment['MQTT_PASS'] ?? '';

  // Topic riêng cho lần chạy này, publish KHÔNG retain → không để rác trên broker.
  final testTopic = 'livetest_radar_$pid';

  var brokerUp = false;

  setUpAll(() async {
    try {
      final s = await Socket.connect(host, port,
          timeout: const Duration(seconds: 2));
      s.destroy();
      brokerUp = true;
    } catch (_) {
      brokerUp = false;
    }
  });

  test(
    'radar im lặng → app tự lật sang mất tín hiệu sau ~15s (broker thật)',
    () async {
      if (!brokerUp || user.isEmpty) {
        markTestSkipped(
            'không có broker ở $host:$port hoặc thiếu MQTT_USER/MQTT_PASS — bỏ qua test live');
        return;
      }

      final svc = MqttService(
        MqttConfig(host: host, port: port, username: user, password: pass),
      );

      // Bản ghi mọi lần stream phát, kèm mốc thời gian để đo được nhịp.
      final emits = <({DateTime at, DeviceState? raw})>[];
      final sub = svc.states.listen((m) {
        emits.add((at: DateTime.now(), raw: m[testTopic]));
      });

      await svc.connect();
      expect(svc.isConnected, isTrue, reason: 'không nối được broker $host:$port');

      // Client thứ hai đóng vai radar-node đang sống.
      final pubId = 'livetest_pub_$pid';
      final pub = MqttServerClient.withPort(host, pubId, port)
        ..logging(on: false)
        ..setProtocolV311()
        ..keepAlivePeriod = 20
        ..connectionMessage =
            MqttConnectMessage().withClientIdentifier(pubId).startClean();
      await pub.connect(user, pass);

      void publishSensor() {
        final b = MqttClientPayloadBuilder()
          ..addString(jsonEncode({
            'LD2410': {
              'Detect': 1,
              'Moving': {'Distance': 120, 'Energy': 40},
              'Static': {'Distance': 80, 'Energy': 20},
            }
          }));
        pub.publishMessage(
            'tele/$testTopic/SENSOR', MqttQos.atMostOnce, b.payload!);
      }

      // Sống 3 giây, nhịp 500ms.
      final beat = Timer.periodic(const Duration(milliseconds: 500), (_) => publishSensor());
      publishSensor();
      await Future<void>.delayed(const Duration(seconds: 3));
      beat.cancel();
      final diedAt = DateTime.now();

      // Trong lúc còn sống phải thấy dữ liệu thật, đúng như radar gửi.
      final alive = svc.currentStates[testTopic];
      expect(alive, isNotNull, reason: 'service không nhận được SENSOR nào');
      expect(alive!.viewAt(DateTime.now().millisecondsSinceEpoch).occupied, isTrue);
      expect(alive.movingDistance, 120);
      expect(alive.staticEnergy, 20);

      // Từ đây KHÔNG publish nữa — đúng cảnh rút nguồn S2.
      emits.clear();
      DateTime? flippedAt;
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final st = svc.currentStates[testTopic];
        if (st != null && st.staleAt(DateTime.now().millisecondsSinceEpoch)) {
          flippedAt = DateTime.now();
          break;
        }
      }

      expect(flippedAt, isNotNull, reason: 'quá 25s vẫn chưa coi là mất tín hiệu');
      final silentFor = flippedAt!.difference(diedAt).inMilliseconds / 1000;
      expect(silentFor, greaterThanOrEqualTo(14.5),
          reason: 'lật quá sớm ($silentFor s) — WiFi chớp một cái là nháy nhầm');
      expect(silentFor, lessThanOrEqualTo(18.0),
          reason: 'lật quá muộn ($silentFor s) — người dùng nhìn số liệu ma quá lâu');

      // Nửa hay quên: stream PHẢI tiếp tục phát dù không còn message nào tới.
      // Không có nhịp này thì UI không bao giờ vẽ lại, dù logic độ tươi đúng.
      final silentEmits = emits.where((e) => e.at.isAfter(diedAt)).length;
      expect(silentEmits, greaterThanOrEqualTo(10),
          reason: 'chỉ $silentEmits lần phát trong ~15s im lặng — nhịp 1s chết');

      // Và cái UI thực sự vẽ phải sạch số liệu cũ.
      final shown = svc.currentStates[testTopic]!
          .viewAt(DateTime.now().millisecondsSinceEpoch);
      expect(shown.online, isFalse);
      expect(shown.occupied, isNull);
      expect(shown.movingDistance, isNull);
      expect(shown.staticEnergy, isNull);

      await sub.cancel();
      svc.dispose();
      pub.disconnect();
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'mở app khi board đã chết: LWT retained "Online" nói dối, độ tươi vẫn bắt được',
    () async {
      if (!brokerUp || user.isEmpty) {
        markTestSkipped('không có broker ở $host:$port — bỏ qua test live');
        return;
      }

      // Dựng đúng hiện trường trên broker thật: LWT retained "Online" của một thiết
      // bị đã chết. radar-node để lại y hệt vì will của nó dành cho home/room/presence.
      final deadTopic = 'livetest_dead_$pid';
      final pubId = 'livetest_lwt_$pid';
      final pub = MqttServerClient.withPort(host, pubId, port)
        ..logging(on: false)
        ..setProtocolV311()
        ..keepAlivePeriod = 20
        ..connectionMessage =
            MqttConnectMessage().withClientIdentifier(pubId).startClean();
      await pub.connect(user, pass);
      pub.publishMessage(
        'tele/$deadTopic/LWT',
        MqttQos.atLeastOnce,
        (MqttClientPayloadBuilder()..addString('Online')).payload!,
        retain: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final svc = MqttService(
        MqttConfig(host: host, port: port, username: user, password: pass),
      );
      await svc.connect();
      final openedAt = DateTime.now();

      // App tin LWT lúc mở là chuyện bình thường — nhưng KHÔNG được tin mãi.
      DateTime? flippedAt;
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final st = svc.currentStates[deadTopic];
        if (st != null && st.staleAt(DateTime.now().millisecondsSinceEpoch)) {
          flippedAt = DateTime.now();
          break;
        }
      }
      expect(flippedAt, isNotNull,
          reason: 'LWT retained "Online" giữ thiết bị chết ở trạng thái sống mãi');
      expect(flippedAt!.difference(openedAt).inSeconds, lessThanOrEqualTo(18));

      // Trả broker về sạch: xoá retain bằng payload rỗng.
      pub.publishMessage(
        'tele/$deadTopic/LWT',
        MqttQos.atLeastOnce,
        MqttClientPayloadBuilder().payload!,
        retain: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      svc.dispose();
      pub.disconnect();
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
