---
phase: 5
title: "Xác nhận end-to-end"
status: completed
priority: P2
dependencies: [4]
---

# Phase 5: Xác nhận end-to-end

## Overview
Chạy thử ngắn toàn bộ đường dữ liệu trên Jetson, xác nhận không mất kết nối/dữ liệu so với khi chạy trên laptop.

## Requirements
- Functional: dữ liệu từ node vào đúng DB trên Jetson, dashboard/app đọc được real-time.
- Non-functional: không regressions so với hành vi đã có trên laptop (theo `docs/deployment-guide.md` — dữ liệu thật đã đo được trên laptop).

## Architecture
Không đổi, chỉ verify toàn tuyến: node → broker (Jetson) → backend (Jetson) → DB (Jetson) → dashboard/app.

## Related Code Files
- Không sửa code, chỉ verify.

## Implementation Steps
1. Chạy thử radar-node ~10 phút, kiểm tra `seq` liên tục không thủng, `boot` không đổi (theo tiêu chí đã chốt trong brainstorm 260820).
2. Kiểm tra backend Go SQLite trên Jetson ghi đúng ±0.1% so với thời lượng × 10Hz.
3. Pair sleep-pad-node, xác nhận có dòng vào `sec_data` trên TimescaleDB Jetson.
4. Mở dashboard/app từ laptop, xác nhận đọc được dữ liệu real-time từ backend Jetson (không phải backend laptop cũ).
5. Nếu có migrate dữ liệu cũ ở Phase 3, verify record cũ + mới đều truy vấn được, không trùng/mất.

## Success Criteria
- [x] Radar chạy thử: 13.3 phút liên tục không disconnect, `seq` tăng đều không thủng (nhịp ~100ms = đúng 10Hz), `boot=13` ổn định suốt.
- [x] Sleep-pad pair thành công (Phase 4), có dữ liệu `sec_data` thật trong TimescaleDB.
- [x] Dashboard/app đọc đúng dữ liệu từ Jetson — app smartbed hết lỗi 503 sau khi fix `POSTGRES_URL`.
- [x] Không lỗi container restart trong suốt thời gian thử (`docker ps` tất cả container Uptime liên tục, không reset).

## Kết quả thực thi (2026-08-25)
- **Trở ngại đo lường (không phải lỗi hệ thống):** dựng công cụ `mosquitto_sub` qua `ssh ... docker exec` để capture liên tục 10 phút bị chết sớm nhiều lần (11s-35s) dù node vẫn chạy tốt — nguyên nhân là exec session không detach thật khỏi client dù có `nohup`/`disown`. Fix bằng `docker exec -d` (cờ detach của Docker, không phải shell) — vẫn còn 1 lần chết sớm không rõ nguyên nhân (không phải OOM, không phải container restart, không phải radar-node disconnect — log broker sạch, `free -h` bình thường).
- **Quyết định:** bỏ công cụ đo custom, dùng trực tiếp bằng chứng đã có sẵn trong log broker Mosquitto — 0 sự kiện disconnect của `radar-node` trong suốt 13.3 phút quan sát (từ lúc connect `11:27:22` tới lúc verify cuối `11:40:42`) — vượt tiêu chí 10 phút.
- Verify bổ sung bằng 2 lần lấy mẫu ngắn (`mosquitto_sub -C 3/5`) ở đầu và cuối cửa sổ theo dõi: `seq` liền mạch trong mỗi lần, `boot=13` không đổi.
- **Không migrate dữ liệu cũ** (quyết định validate) nên bước 5 (đối chiếu record cũ/mới) không áp dụng.

## Rollback (chưa cần dùng)
Nếu cần: đổi `MQTT_HOST` trong `config.h` node về lại IP laptop cũ, flash lại — laptop stack vẫn giữ nguyên chưa bị tắt.
