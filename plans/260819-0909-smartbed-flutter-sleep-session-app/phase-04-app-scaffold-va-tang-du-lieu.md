---
phase: 4
title: "App — scaffold Flutter, core, repository, cache sqflite"
status: completed
priority: P2
dependencies: [3]
repo: smartbedv3
---

# Phase 04: App — scaffold Flutter, core, repository, cache sqflite

## Overview
Dựng project Flutter ở `smartbedv3/app/`, tầng core (api client + config + theme + router) và tầng dữ liệu (repository + cache sqflite). Chưa có màn hình nghiệp vụ nào — pha này chỉ để `GET /sessions` chạy được và cache được.

## Requirements
- Functional: gọi được `/sessions` và `/timeline` bằng dev token, lưu kết quả vào sqflite, đọc lại được khi không có mạng.
- Non-functional: layout responsive từ đầu (plan `phase-06` yêu cầu tablet + phone dùng chung code).
- Non-functional: Flutter 3.44.6 / Dart 3.12.2 (bản đang cài trên máy).
- Non-functional: **không** commit dev token vào git.

## Architecture

```
smartbedv3/app/
  lib/
    core/
      api_client.dart        # dio + interceptor gắn dev token + bắt 401
      app_config.dart        # baseUrl, deviceId, devToken — đọc từ --dart-define
      app_theme.dart
      app_router.dart        # go_router
      breakpoints.dart       # compact < 600dp <= expanded
    data/
      models/
        sleep_session.dart
        timeline_point.dart
      local/
        session_cache.dart   # sqflite: 2 bảng
      session_repository.dart
    features/                # Phase 05, 06
    main.dart
  test/
```

**Gói:** `dio` · `flutter_riverpod` · `go_router` · `fl_chart` · `sqflite` · `path` · `intl`
Cùng bộ đã chứng minh chạy được ở `sleep_pad_AI/flutter_app`, nhưng code viết mới (quyết định #1).

**Vì sao sqflite chứ không drift:** 2 bảng, không quan hệ phức tạp. Drift kéo theo `build_runner` + codegen — chi phí không đổi lấy gì ở quy mô này.

```sql
-- session_cache.dart
CREATE TABLE sessions (
  id TEXT PRIMARY KEY, device_id TEXT, started_at INTEGER, ended_at INTEGER,
  payload TEXT,            -- JSON nguyên bản của server
  cached_at INTEGER
);
CREATE TABLE timeline_points (
  session_id TEXT, t INTEGER, payload TEXT,
  PRIMARY KEY (session_id, t)
);
```
Lưu `payload` JSON nguyên bản có chủ đích: server thêm cột (presence/env) là app cũ **không vỡ**, chỉ bỏ qua khoá lạ. Đây là chỗ đổi lấy tính mở rộng bằng một chút dư thừa — chấp nhận.

**Luồng repository (offline, quyết định #10 của brainstorm):**
```
đọc cache → trả ngay (UI có gì đó để vẽ)
  → gọi mạng
      → thành công: ghi đè cache, phát lại
      → thất bại:   giữ cache, bật cờ isStale
```

**Cấu hình:** `--dart-define=API_BASE_URL=... --dart-define=DEV_TOKEN=... --dart-define=DEVICE_ID=...`
Không có file chứa token trong repo. Thêm dòng vào `.gitignore` cho mọi `*.env` phòng hờ.

**401:** interceptor bắt riêng, đẩy lên UI dưới dạng thông báo "Dev token hết hạn — lấy token mới" (R5). Không im lặng, không retry vô hạn.

## Related Code Files
- Create: toàn bộ `smartbedv3/app/` (chạy `flutter create`)
- Modify: `smartbedv3/app/README.md` — thay nội dung "Not started" bằng hướng dẫn chạy thật
- Modify: `smartbedv3/.gitignore` — mục Flutter (`app/build/`, `app/.dart_tool/`, `*.env`)

## Implementation Steps
1. `flutter create --project-name smartbed_app --platforms=android app`
   (giữ nguyên thư mục `app/` và `app/README.md` đang có — `flutter create` không xoá README)
2. `pubspec.yaml`: thêm gói ở trên, `environment: sdk: ^3.12.0`
3. `core/app_config.dart`: đọc `String.fromEnvironment`, có giá trị mặc định trỏ `http://10.0.2.2:8080` (localhost của host nhìn từ emulator Android)
4. `core/api_client.dart`: dio + `Authorization: Bearer` + interceptor 401 → `DevTokenExpiredException`
5. `data/models/`: `fromJson`/`toJson`, giữ `Map<String,dynamic> raw` để không mất khoá lạ
6. `data/local/session_cache.dart`: mở DB, tạo 2 bảng, `upsertSessions` / `readSessions` / `upsertTimeline` / `readTimeline`
7. `data/session_repository.dart`: luồng cache-trước ở trên, trả `({List<SleepSession> items, bool isStale})`
8. `test/`: unit test cho `session_repository` với api client giả — 3 case: có mạng, mất mạng có cache, mất mạng không cache
9. `flutter analyze && flutter test`

## Success Criteria
- [ ] `flutter analyze` sạch, `flutter test` xanh
- [ ] Chạy trên emulator, log in ra danh sách phiên lấy từ `/sessions` thật (chưa cần UI đẹp)
- [ ] Tắt mạng emulator → repository vẫn trả dữ liệu từ cache, `isStale == true`
- [ ] Xoá app data → mất mạng → repository trả rỗng, **không crash**
- [ ] `git status` không thấy token hay file build nào
- [ ] Thêm một khoá lạ vào JSON server giả → app không vỡ

## Risk Assessment
- **Emulator không thấy backend:** Android emulator dùng `10.0.2.2` cho localhost của host; máy thật cần IP LAN. Ghi cả hai vào README, đây là chỗ mất thời gian kinh điển.
- **Bắt đầu vẽ UI trước khi tầng dữ liệu chạy:** cấm. Pha này đóng bằng log ra console, không bằng màn hình.
- **R5:** dev token 30 ngày. Nếu 401 bị nuốt, triệu chứng sẽ là "app trống rỗng không rõ lý do".
