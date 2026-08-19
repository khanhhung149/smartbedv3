import '../core/api_client.dart';
import 'local/session_cache.dart';
import 'models/sleep_session.dart';
import 'models/timeline_point.dart';

/// Dữ liệu kèm nguồn gốc của nó.
///
/// [isStale] true nghĩa là đọc từ cache vì mạng hỏng — màn hình phải nói ra
/// điều đó thay vì trình bày số cũ như số mới.
class RepoResult<T> {
  const RepoResult({
    required this.items,
    required this.isStale,
    this.cachedAt,
  });

  final T items;
  final bool isStale;

  /// Lúc bản cache này được ghi. Chỉ có nghĩa khi [isStale].
  final DateTime? cachedAt;
}

/// Mạng trước, cache làm lưới an toàn.
///
/// Mất mạng **không** phải lỗi cần ném ra: người dùng vẫn xem lại được đêm đã
/// tải. Token hết hạn thì ngược lại — phải ném, vì chỉ người dùng sửa được và
/// một màn hình "cũ" sẽ khiến họ đi tìm lỗi mạng không tồn tại.
class SessionRepository {
  SessionRepository({required this.api, required this.cache});

  final ApiClient api;
  final SessionCache cache;

  Future<RepoResult<List<SleepSession>>> sessions(String deviceId) async {
    try {
      final raw = await api.fetchSessions(deviceId: deviceId);
      await cache.writeSessions(deviceId, raw);
      return RepoResult(
        items: [for (final s in raw) SleepSession.fromJson(s)],
        isStale: false,
      );
    } on DevTokenExpiredException {
      rethrow;
    } on ApiUnavailableException {
      return RepoResult(
        items: await cache.readSessions(deviceId),
        isStale: true,
        cachedAt: await cache.sessionsCachedAt(deviceId),
      );
    }
  }

  Future<RepoResult<List<TimelinePoint>>> timeline(String sessionId) async {
    try {
      final res = await api.fetchTimeline(sessionId);
      final points =
          (res['points'] as List).cast<Map<String, dynamic>>();
      await cache.writeTimeline(sessionId, points);
      return RepoResult(
        items: [for (final p in points) TimelinePoint.fromJson(p)],
        isStale: false,
      );
    } on DevTokenExpiredException {
      rethrow;
    } on ApiUnavailableException {
      return RepoResult(
        items: await cache.readTimeline(sessionId),
        isStale: true,
        cachedAt: await cache.timelineCachedAt(sessionId),
      );
    }
  }
}
