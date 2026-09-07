---
phase: 3
title: "Build và chạy stack (cả 2 hệ)"
status: completed
priority: P1
dependencies: [2]
---

# Phase 3: Build và chạy stack (cả 2 hệ)

## Overview
Build 3 image tự build thành arm64 trên Jetson, dựng cả 2 hệ (presence-ac + sleeppad) bằng docker compose, đảm bảo DB nằm trên NVMe và 2 broker không đụng cổng.

## Requirements
- Functional: `docker compose ps` cả 2 stack đều `Up`, healthcheck pass nếu có.
- Non-functional: volume DB (SQLite `cloud/presence-ac`, Postgres `cloud/sleeppad`) trỏ đường dẫn trên NVMe, không phải microSD gốc.

## Architecture
Hệ A (presence-ac): Mosquitto:1883 + Go backend + SQLite.
Hệ B (sleeppad): Mosquitto:1884 + FastAPI + TimescaleDB + Redis.
Build local trên Jetson (không cross-compile từ laptop) để tránh lệch libc/CPU arch.

## Related Code Files
- **Xác nhận qua code:** DB dùng **named volumes** (`home-data:/data` ở presence-ac, `postgres_data:/var/lib/postgresql/data` ở sleeppad) — KHÔNG phải bind-mount đường dẫn cụ thể trong `docker-compose.yml`. Named volume mặc định nằm dưới `/var/lib/docker/volumes/` của Docker daemon.
- Modify: `/etc/docker/daemon.json` trên Jetson (thêm `"data-root": "/mnt/nvme/docker-data"`) — cách chuẩn để đưa toàn bộ named volumes (không riêng DB) sang NVMe mà không đổi `docker-compose.yml`.
- Không modify Dockerfile trừ khi build lỗi do dependency arm64 thiếu.

## Implementation Steps
1. ~~Xác định điểm mount NVMe, set data-root~~ — **KHÔNG CẦN**: verify thực tế cho thấy rootfs Jetson này (`/`) đã nằm trên NVMe (`nvme0n1p1`, 227G, không phải `mmcblk0`/SD). `Docker Root Dir: /var/lib/docker` mặc định đã trên NVMe. Bỏ qua bước đổi `data-root`.
3. `docker compose build` cho Go backend (`cloud/presence-ac`) và FastAPI (`cloud/sleeppad`) trên Jetson — xác nhận build xong không lỗi wheel/arch.
4. Thử build `cloud/asr` (faster-whisper). Nếu lỗi wheel aarch64: **debug ngay tại đây** (tìm wheel arm64 thay thế, build từ source, hoặc đổi base image) — theo quyết định validate 2026-08-25, không hoãn sang sau, phải xong trước khi qua Phase 4.
5. `docker compose up -d` cho cả 2 hệ, set đúng `MQTT_HOST_PORT=1883` (Hệ A) và `MQTT_HOST_PORT`/`MQTT_WS_HOST_PORT` (Hệ B) khác nhau — verify bằng `docker ps` không có port conflict.
6. (Tuỳ chọn, hỏi user trước khi làm) Migrate dữ liệu cũ: copy trực tiếp file SQLite từ laptop; với TimescaleDB dùng `pg_dump` trên laptop → `pg_restore` trên Jetson (không copy volume thư mục Postgres giữa x86/arm64).

## Success Criteria
- [ ] `docker compose ps` cả 2 hệ đều Up, không container restart loop.
- [ ] Cổng 1883 và 1884 đều nghe đúng, không conflict.
- [ ] `docker info | grep "Docker Root Dir"` trỏ đúng path trên NVMe, không phải mmcblk/thẻ SD.
- [ ] `cloud/asr` build thành công trên Jetson (bắt buộc, không hoãn — quyết định validate 2026-08-25).

## Risk Assessment
- `faster-whisper`/`cloud/asr` thiếu wheel aarch64 — phải debug ngay trong phase này (không hoãn), có thể kéo dài thời gian phase nếu wheel không tồn tại sẵn cho aarch64.
- Copy tay volume Postgres giữa 2 kiến trúc CPU sẽ hỏng — chỉ dùng pg_dump/restore.
- Quên đổi volume path vẫn ghi lên SD mặc định — dễ gãy như đã cảnh báo trong brainstorm 260820, phải verify path thật trước khi coi phase xong.

## Kết quả thực thi (2026-08-25)
- **NVMe:** không cần đổi `data-root` — rootfs Jetson (`/`) đã trên `nvme0n1p1` (227G), Docker Root Dir mặc định đã đúng.
- **Build:** `presence-ac` (Go backend + `cloud/asr` faster-whisper) build arm64 thành công không lỗi wheel. `sleeppad` (FastAPI) build arm64 thành công.
- **Chạy lên:** cả 2 hệ Up, healthy. Đổi 2 cổng host so với default để tránh đụng service có sẵn trên Jetson (không phải project này, không đụng):
  - `POSTGRES_HOST_PORT=5433` (5432 bị `llm-gw-postgres` — container không liên quan chiếm từ trước).
  - `FASTAPI_HOST_PORT=8001` (8000 bị 1 python process khác trên Jetson chiếm).
  - `MQTT_HOST_PORT=1884` cho sleeppad đã có sẵn trong `.env.dev`, không đụng cổng 1883 của Hệ A.
- **Migrate dữ liệu cũ:** bỏ qua theo quyết định validate — bắt đầu dữ liệu mới trên Jetson.
- Log xác nhận sạch: `home-backend` "mqtt connected", `sleeppad-fastapi` "Application startup complete", cả 2 không lỗi thật (chỉ warning tính năng optional chưa cấu hình: Postgres liên-hệ ở presence-ac, FCM ở sleeppad — đúng hiện trạng laptop, không phải lỗi mới).
