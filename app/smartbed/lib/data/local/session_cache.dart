import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/sleep_session.dart';
import '../models/timeline_point.dart';

/// Bản sao cục bộ của những đêm đã tải.
///
/// Lưu **JSON nguyên bản** chứ không tách cột cho từng chỉ số: hợp đồng API cho
/// phép backend thêm khoá bất cứ lúc nào, và cột cứng sẽ nuốt mất khoá mới ở
/// vòng cache. Chỉ những thứ cần để truy vấn mới lên thành cột.
class SessionCache {
  SessionCache._(this._db);

  final Database _db;

  static Future<SessionCache> open({String? path}) async {
    final db = await databaseFactory.openDatabase(
      path ?? await _defaultPath(),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE sessions (
              id         TEXT PRIMARY KEY,
              device_id  TEXT NOT NULL,
              started_at TEXT NOT NULL,
              json       TEXT NOT NULL,
              cached_at  TEXT NOT NULL
            )
          ''');
          await db.execute(
              'CREATE INDEX sessions_by_device ON sessions(device_id, started_at DESC)');
          await db.execute('''
            CREATE TABLE timelines (
              session_id TEXT PRIMARY KEY,
              json       TEXT NOT NULL,
              cached_at  TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    return SessionCache._(db);
  }

  static Future<String> _defaultPath() async =>
      '${await databaseFactory.getDatabasesPath()}/sessions.db';

  Future<void> writeSessions(
      String deviceId, List<Map<String, dynamic>> raw) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = _db.batch();
    // Xoá theo thiết bị rồi ghi lại: phiên bị backend bỏ đi phải biến mất khỏi
    // cache, nếu không màn hình sẽ giữ một đêm không còn tồn tại.
    batch.delete('sessions', where: 'device_id = ?', whereArgs: [deviceId]);
    for (final s in raw) {
      batch.insert(
        'sessions',
        {
          'id': s['id'],
          'device_id': deviceId,
          'started_at': s['started_at'],
          'json': jsonEncode(s),
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<SleepSession>> readSessions(String deviceId) async {
    final rows = await _db.query(
      'sessions',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'started_at DESC',
    );
    return [
      for (final r in rows)
        SleepSession.fromJson(
            jsonDecode(r['json'] as String) as Map<String, dynamic>),
    ];
  }

  Future<DateTime?> sessionsCachedAt(String deviceId) async {
    final rows = await _db.query(
      'sessions',
      columns: ['cached_at'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['cached_at'] as String).toLocal();
  }

  Future<void> writeTimeline(
      String sessionId, List<Map<String, dynamic>> points) async {
    await _db.insert(
      'timelines',
      {
        'session_id': sessionId,
        'json': jsonEncode(points),
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TimelinePoint>> readTimeline(String sessionId) async {
    final rows = await _db.query('timelines',
        where: 'session_id = ?', whereArgs: [sessionId], limit: 1);
    if (rows.isEmpty) return const [];
    final list = jsonDecode(rows.first['json'] as String) as List;
    return [
      for (final p in list) TimelinePoint.fromJson(p as Map<String, dynamic>),
    ];
  }

  Future<DateTime?> timelineCachedAt(String sessionId) async {
    final rows = await _db.query('timelines',
        columns: ['cached_at'],
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['cached_at'] as String).toLocal();
  }

  Future<void> close() => _db.close();
}
