import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbed_app/core/api_client.dart';
import 'package:smartbed_app/core/app_config.dart';

/// Thiết bị chưa có phiên nào không được làm app nổ.
///
/// Backend Go từng trả `null` cho danh sách rỗng (slice nil encode ra `null`),
/// và client ép thẳng sang List nên văng
/// "type 'Null' is not a subtype of type 'List<dynamic>' in type cast"
/// ngay lần đầu trỏ vào một pad mới. Backend đã sửa để trả `[]`, nhưng client
/// vẫn phải chịu được `null` — đó là lý do bài test này dựng server trả `null`
/// chứ không trả `[]`.
void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('null');
      await req.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  test('backend trả null thì fetchSessions cho danh sách rỗng, không ném', () async {
    final api = ApiClient(AppConfig(
      baseUrl: 'http://${server.address.address}:${server.port}/api',
      deviceId: 'NEWDEVICE',
      devToken: '',
    ));

    final rows = await api.fetchSessions(deviceId: 'NEWDEVICE');
    expect(rows, isEmpty);
  });
}
