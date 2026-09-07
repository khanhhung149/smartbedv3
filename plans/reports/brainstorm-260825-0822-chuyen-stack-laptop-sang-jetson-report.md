# Brainstorm — chuyển stack từ laptop sang Jetson (cả 2 hệ)

- **Ngày:** 2026-08-25 · **Branch:** master · **Loại:** brainstorm, chưa implement
- **Bối cảnh:** Jetson đã lên được màn hình (JetPack/OS cài xong), chưa có Docker. Trước đó brainstorm 260820 (xem [báo cáo](./brainstorm-phase01-8h-run-readiness-260820-0900-seq-counter-sqlite-durability-jetson-portability-report.md) mục "Vấn đề 3") đã quyết định KHÔNG chuyển ngay, chỉ chuẩn bị. Hôm nay là bước thực thi.

## Quyết định của user

- Phạm vi: **cả 2 hệ** (presence-ac + sleeppad), không chỉ Hệ A.
- Mạng: **flash lại toàn bộ node** trỏ IP mới của Jetson (không dùng DHCP reservation cũ trên laptop — vì hỏi ra chưa chắc đã từng làm).
- Có thể cài Claude Code trên Jetson (npm, aarch64 Ubuntu — không có rào cản kiến trúc).

## Hiện trạng xác nhận qua code/docs

- 2 stack độc lập trên laptop: Hệ A (presence-ac: Mosquitto:1883 + Go + SQLite), Hệ B (sleeppad: Mosquitto:1884 + FastAPI + TimescaleDB + Redis).
- `MQTT_HOST` compile cứng vào firmware ESP32 (`config.h`, bị gitignore) — đổi máy host bắt buộc flash lại node.
- Image công khai (timescaledb, redis, mosquitto, python, golang) đã xác nhận có bản arm64 (20/08). 3 image tự build (Go backend, FastAPI, ASR) cần build lại trên Jetson; `cloud/asr` (faster-whisper) là rủi ro wheel aarch64 duy nhất, không nằm trên đường đo chính.
- DB không được để trên microSD (khuyến nghị NVMe).
- Không cần NVIDIA Container Toolkit / GPU runtime cho lần chuyển này — presence-ac và sleeppad không chạy GPU workload; MediaPipe/vision là Phase 05 riêng, không nằm trong phạm vi.

## Bổ sung: dev từ laptop, chạy trên Jetson

User hỏi giữa phiên: có thể code trên laptop, đẩy dữ liệu sang Jetson để chạy không. Trả lời: đây chính là mô hình chuẩn, không đổi lộ trình — chỉ làm rõ 2 việc tách biệt:

- **Dev**: vẫn ở laptop, `git push`/`pull`, hoặc SSH/VS Code Remote-SSH vào Jetson để chạy lệnh từ xa — không cần ngồi trực tiếp ở Jetson sau bước cài ban đầu.
- **Runtime**: container chạy trên Jetson. Node ESP32 bắn MQTT thẳng tới IP Jetson (đúng thiết kế bước D), không qua laptop trung gian.

User chọn: thêm bước setup SSH/remote-access laptop→Jetson vào đầu plan.

## Lộ trình đã chốt

**A0. Remote access — ĐÃ XONG (2026-08-25)**
0. SSH key `~/.ssh/id_ed25519` (laptop) đã copy lên Jetson qua `ssh-copy-id`. Jetson: IP `192.168.1.125`, hostname `mp-desktop`, user `mp`, arch `aarch64`. Test `ssh mp@192.168.1.125` không cần password — thành công. Từ đây mọi lệnh trên Jetson chạy qua SSH từ laptop, không cần bàn phím/màn hình cắm trực tiếp.

**A. Chuẩn bị Jetson**
1. Cài Docker Engine + Compose plugin (theo hướng dẫn NVIDIA cho JetPack).
2. Xác định IP Jetson dùng lâu dài (đặt static/DHCP reservation ngay để tránh phải flash lại node lần nữa sau này).

**B. Đưa code sang Jetson**
3. `git clone` repo (không copy tay) — tránh thiếu file untracked.
4. Copy secret thật (`.env` các service, Firebase service account) từ laptop — đọc file gitignored thật, không tự bịa giá trị.

**C. Build & chạy**
5. Build lại 3 image tự build (Go backend, FastAPI, ASR — ASR có thể hoãn nếu voice-node chưa cần ngay).
6. `docker compose up` cả 2 hệ, kiểm tra không đụng cổng 1883/1884, volume DB trỏ NVMe.
7. (Tuỳ chọn) Migrate dữ liệu cũ: `pg_dump`/`pg_restore` cho TimescaleDB, copy trực tiếp file SQLite.

**D. Flash lại node**
8. Sửa `config.h` từng ESP32 (radar-node, sleep-pad-node, voice-node nếu dùng MQTT) → `MQTT_HOST` = IP Jetson, flash lại.
9. `camera-node` không qua MQTT, không cần flash lại — chỉ kiểm tra chỗ nào hardcode URL.
10. Kiểm tra app Flutter (`api_client.dart`, radar base URL qua `--dart-define`) có trỏ IP laptop cũ không.

**E. Xác nhận**
11. Chạy thử ngắn từng node, xác nhận dữ liệu vào đúng DB trên Jetson, cổng đúng, không mất kết nối.

## Next steps

Chuyển sang `/ck:plan` để sinh phase-by-phase chi tiết (nhiều file cấu hình + rủi ro flash firmware thật) và thực thi tuần tự.

## Câu hỏi tồn đọng

- Có cần migrate dữ liệu cũ (đêm đo đã có trên laptop) sang Jetson, hay bắt đầu dữ liệu mới trên Jetson? Chưa chốt trong phiên này — để `/ck:plan` hỏi khi vào phase D/E.
