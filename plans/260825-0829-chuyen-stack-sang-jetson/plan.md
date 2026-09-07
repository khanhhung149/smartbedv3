---
status: completed
branch: master
blockedBy: []
blocks: []
---

# Plan: chuyển stack presence-ac + sleeppad từ laptop sang Jetson

- **Bối cảnh:** [brainstorm 260825](../reports/brainstorm-260825-0822-chuyen-stack-laptop-sang-jetson-report.md), kế thừa quyết định từ [brainstorm 260820](../reports/brainstorm-phase01-8h-run-readiness-260820-0900-seq-counter-sqlite-durability-jetson-portability-report.md).
- **Jetson:** IP `192.168.1.125`, hostname `mp-desktop`, user `mp`, arch `aarch64`, JetPack cài xong, chưa có Docker.
- **SSH:** đã setup xong, verify OK (`ssh mp@192.168.1.125` không cần password).
- **Phạm vi:** cả 2 hệ (presence-ac + sleeppad). KHÔNG bao gồm: GPU/MediaPipe (Phase 05 riêng), ASR bắt buộc phải chạy ngay (có thể hoãn).

## Phases

| # | File | Nội dung |
|---|---|---|
| 1 | [phase-01-chuan-bi-jetson.md](./phase-01-chuan-bi-jetson.md) | Docker + IP tĩnh Jetson |
| 2 | [phase-02-dua-code-va-secrets.md](./phase-02-dua-code-va-secrets.md) | git clone + copy secrets thật |
| 3 | [phase-03-build-va-chay-stack.md](./phase-03-build-va-chay-stack.md) | Build image arm64, docker compose 2 hệ, DB trên NVMe |
| 4 | [phase-04-flash-firmware-va-app.md](./phase-04-flash-firmware-va-app.md) | Flash lại config.h node, cập nhật app nếu hardcode IP |
| 5 | [phase-05-xac-nhan.md](./phase-05-xac-nhan.md) | Chạy thử, xác nhận dữ liệu vào đúng DB Jetson |

## Acceptance criteria

- Cả 2 broker (1883/1884) chạy trên Jetson, không đụng cổng.
- DB (SQLite + TimescaleDB) ghi trên NVMe, không phải thẻ SD gốc.
- Node ESP32 (radar-node, sleep-pad-node, voice-node nếu bật) publish thẳng tới Jetson, dashboard/app nhận dữ liệu real-time.
- Dev vẫn thực hiện từ laptop qua SSH, không cần thao tác trực tiếp tại Jetson.

## Rủi ro chính

- Build `cloud/asr` (faster-whisper) trên arm64 có thể thiếu wheel — không chặn tiêu chí chính, có thể hoãn sang sau.
- DB volume Postgres không copy tay được giữa x86↔arm64 — phải `pg_dump`/`pg_restore` nếu cần giữ dữ liệu cũ.
- Quên đổi `MQTT_HOST` ở 1 trong các node sẽ làm node đó "mất tích" âm thầm (không lỗi biên dịch, chỉ không kết nối được).

## Câu hỏi tồn đọng

Không còn — đã chốt trong Validation Log bên dưới.

## Validation Log

### Verification Results (2026-08-25)
- Tier: Full (5 phase) — sample check trên các claim về file path, volume, app config.
- Claims checked: 6 | Verified: 4 | Failed: 2 | Unverified: 0
- Failures:
  - Phase 3: claim "sửa bind-mount path trong docker-compose.yml" — SAI. DB dùng named volumes (`home-data:/data`, `postgres_data:/var/lib/postgresql/data`), không phải bind-mount. Đã sửa thành đổi Docker daemon `data-root`.
  - Phase 4: claim "sửa `api_client.dart`/`app_router.dart` nếu hardcode IP" — SAI file. baseUrl thật nằm ở `app/smartbed/lib/core/app_config.dart:23` (`--dart-define=API_BASE_URL`) và override được ngay trong app qua SharedPreferences, không bắt buộc rebuild. Đã sửa lại phase.

### Interview (2026-08-25)
1. Migrate dữ liệu đêm đo cũ? → **Không migrate**, bắt đầu dữ liệu mới trên Jetson. Data cũ vẫn còn nguyên trên laptop nếu cần xem lại.
2. `cloud/asr` lỗi wheel aarch64 thì sao? → **Phải debug ngay** trong Phase 3, không hoãn — voice-node cần chuyển trọn vẹn cùng đợt này. Đã cập nhật Phase 3 (Implementation Steps, Success Criteria, Risk Assessment).
3. Cần check volume cũ trước khi đổi `data-root`? → **Không cần**, Jetson chưa chạy Docker lần nào (xác nhận hiện trạng đầu phiên).

### Whole-Plan Consistency Sweep (2026-08-25)
Đọc lại `plan.md` + toàn bộ 5 phase file sau khi sửa. Không còn tham chiếu tới "bind-mount path" hay "api_client.dart/app_router.dart" ở đâu khác trong plan. Không phát hiện mâu thuẫn còn sót. Sẵn sàng cook.

