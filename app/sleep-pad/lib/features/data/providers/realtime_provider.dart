import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../shared/providers/app_env_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../models/realtime_data.dart';

// WebSocket StreamProvider.family keyed by deviceId.
// Emits RealtimeData on each valid frame; filters ping heartbeats.
// Reconnects with exponential backoff (1s → 2s → 4s … max 30s).
// On auth failure (1008 / 4401), stops retrying and emits an error.
// Channel is closed when the provider is disposed via ref.onDispose.

// Private exception type surfaced when the server closes the WS with an auth
// failure code. We distinguish this from transient network errors so the
// retry loop gives up instead of hammering the server with a stale JWT.
class _WebSocketAuthFailure implements Exception {
  const _WebSocketAuthFailure();
}

final realtimeProvider =
    StreamProvider.family<RealtimeData, String>((ref, deviceId) async* {
  // Cancellation flag flipped when the provider is disposed (device switch,
  // logout, route pop). The retry loop checks it between iterations so we
  // don't re-open a socket after the caller has moved on.
  var cancelled = false;
  WebSocketChannel? activeChannel;

  ref.onDispose(() {
    cancelled = true;
    try {
      activeChannel?.sink.close(ws_status.goingAway);
    } catch (_) {
      // Best-effort close — already-closed sinks throw harmlessly.
    }
  });

  int delaySeconds = 1;

  while (!cancelled) {
    // Re-read JWT on every reconnect so a re-login picks up the fresh token
    // and old tokens don't cause eternal 1008 loops.
    final token = await _readFreshToken(ref);
    if (token == null || token.isEmpty) {
      return; // user logged out mid-stream — stop cleanly
    }

    WebSocketChannel? channel;
    try {
      final uri = Uri.parse(
        '${ref.read(appEnvProvider).wsBaseUrl}/ws/$deviceId?token=$token',
      );
      debugPrint('[WSS] Connecting → $uri');
      channel = WebSocketChannel.connect(uri);
      activeChannel = channel;

      await for (final raw in channel.stream) {
        if (cancelled) break;
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        if (json['type'] == 'ping') {
          debugPrint('[WSS] ping received');
          continue; // keepalive — drop
        }
        // Reset backoff on first real frame of this connection.
        delaySeconds = 1;
        debugPrint('[WSS] data frame: $json');
        yield RealtimeData.fromJson(json);
      }

      // Stream closed by server. Inspect close code to decide auth vs. retry.
      final closeCode = channel.closeCode;
      debugPrint('[WSS] stream closed — code=$closeCode');
      if (closeCode == 1008 || closeCode == 4401 || closeCode == 4403) {
        throw const _WebSocketAuthFailure();
      }
    } on _WebSocketAuthFailure {
      debugPrint('[WSS] auth failure — stopping retry');
      rethrow;
    } catch (e) {
      debugPrint('[WSS] error: $e — retrying in ${delaySeconds}s');
    } finally {
      try {
        await channel?.sink.close();
      } catch (_) {}
      if (identical(activeChannel, channel)) activeChannel = null;
    }

    if (cancelled) return;

    debugPrint('[WSS] reconnecting in ${delaySeconds}s…');
    // Exponential backoff, max 30s.
    await Future<void>.delayed(Duration(seconds: delaySeconds));
    delaySeconds = (delaySeconds * 2).clamp(1, 30);
  }
});

Future<String?> _readFreshToken(Ref ref) async {
  final inMemory = ref.read(authProvider);
  if (inMemory != null && inMemory.isNotEmpty) return inMemory;
  return ref.read(authStorageProvider).readToken();
}
