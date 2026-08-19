import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/snapshot.dart';

/// Nghe `GET /api/ws` — backend push Snapshot mỗi khi trạng thái đổi.
///
/// Tự nối lại vì rớt WS là chuyện thường trên điện thoại (khoá màn hình, đổi WiFi,
/// backend restart). Backoff tăng dần để không quay vòng đốt pin khi backend chết hẳn.
class WsClient {
  final String baseUrl;
  WsClient(this.baseUrl);

  final _controller = StreamController<Snapshot>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry;
  bool _closed = false;
  int _attempt = 0;

  Stream<Snapshot> get snapshots => _controller.stream;

  /// true/false mỗi khi WS lên/xuống — Home hiện chấm xanh/xám.
  Stream<bool> get connection => _connected.stream;

  void connect() {
    if (_closed) return;
    _retry?.cancel();

    final url = '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/api/ws';
    try {
      _ch = WebSocketChannel.connect(Uri.parse(url));
    } catch (_) {
      _scheduleRetry();
      return;
    }

    _sub = _ch!.stream.listen(
      (data) {
        _attempt = 0; // nhận được data = kết nối thật sự sống
        _connected.add(true);
        try {
          final j = jsonDecode(data as String) as Map<String, dynamic>;
          _controller.add(Snapshot.fromJson(j));
        } catch (_) {
          // Frame rác thì bỏ qua — đừng để 1 message hỏng giết cả stream.
        }
      },
      onError: (_) {
        _connected.add(false);
        _scheduleRetry();
      },
      onDone: () {
        _connected.add(false);
        _scheduleRetry();
      },
      cancelOnError: true,
    );
  }

  /// Backoff 1s → 2s → 4s… trần 30s.
  void _scheduleRetry() {
    if (_closed) return;
    _sub?.cancel();
    _sub = null;
    _ch = null;
    final delay = Duration(seconds: (1 << _attempt).clamp(1, 30));
    if (_attempt < 5) _attempt++;
    _retry = Timer(delay, connect);
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _controller.close();
    _connected.close();
  }
}
