---
phase: 5
title: "Verify tay E2E"
status: pending
priority: P2
dependencies: [1, 2, 3, 4]
---

# Phase 5: Verify tay E2E

## Overview

Mục Manual của Phase 5 plan gốc. Chạy stack thật + app trên máy thật, xác nhận luồng
`Sleep Pad → MQTT → backend → /ws/user → Home` và `Watch → BLE → POST /watch → /ws/user`.

Test tự động không thay được bước này vì phần lớn rủi ro nằm ở BLE và firmware — vùng
không có test.

## Requirements

- Login → Home hiện pad live + watch synced
- Pad offline → chấm trạng thái đổi
- Watch sync → steps/spo2/bp refresh trong vòng 30s
- Không có lỗi đỏ trong log backend và console app

## Architecture

### Giới hạn đã biết

`idf.py` **không có** trên máy này → không build/flash được firmware ESP-IDF. Hệ quả:

- Mục nhiệt độ môi trường (`/temp` → `pad.temp` + `pad.humidity`) **không verify được ở
  đây**. Cần máy có ESP-IDF toolchain, hoặc một chip đã flash sẵn firmware từ branch.
- Nếu không có chip, ghi rõ mục đó là **chưa verify**, không đánh dấu pass.

Có thể thay thế một phần bằng cách publish thủ công vào topic `sleeppad/{id}/temp` bằng
`mosquitto_pub` để kiểm phần backend + app, nhưng như vậy **không** verify được firmware.

### Watch BLE subsystem

1222 LOC không có test (rủi ro đã chấp nhận ở brainstorm). Bước verify tay này là lớp
bảo vệ duy nhất cho phần đó → làm kỹ luồng pair + sync.

## Related Code Files

**Create**
- `plans/260802-2203-ws-user-phase5-stabilization/reports/e2e-verify-checklist.md` — kết quả thực tế từng mục

**Không sửa** code.

## Implementation Steps

1. Khởi động stack:
   `docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d`
2. Apply `postgres/smart_watch_data.sql` nếu volume đã tồn tại từ trước (`init.sql` chỉ
   chạy lần đầu tạo volume — đây là câu hỏi ops còn treo)
3. Chạy app trên máy thật, login
4. Điền checklist bên dưới, ghi kết quả thật kể cả khi fail

### Checklist

| # | Mục | Kỳ vọng | Kết quả |
|---|---|---|---|
| 1 | Login → Home | Render không lỗi, không còn device selector | |
| 2 | Pad đang chạy | HR/RR cập nhật liên tục, sparkline mọc dần | |
| 3 | Status row | "Sleep Pad · Online" | |
| 4 | Tắt pad, chờ | Chuyển sang Offline | |
| 5 | Bật lại pad | Về Online, số liệu chạy tiếp | |
| 6 | Pair watch qua BLE | Pair thành công, vào màn success | |
| 7 | Watch sync | steps/spo2/bp hiện trên Home trong ≤30s | |
| 8 | Steps so với đồng hồ | Khớp tổng ngày, không phải bucket cuối | |
| 9 | Watch chưa sync | Hiện "Watch · Not synced", không ẩn thiết bị | |
| 10 | Màn History | Có section watch, tab scroll hết | |
| 11 | Alerts + chuông | Hoạt động với primary device | |
| 12 | Kill WS (tắt mạng) | Banner reconnect, tự nối lại | |
| 13 | Nhiệt độ môi trường | `pad.temp` + humidity hiện | **CHẶN nếu không có chip đã flash** |
| 14 | Log backend | Không có exception | |

## Success Criteria

- [ ] Mục 1–12 pass
- [ ] Mục 13 pass **hoặc** ghi rõ chặn kèm lý do (thiếu `idf.py`/thiếu chip)
- [ ] Mục 14 sạch
- [ ] Report checklist đã ghi với kết quả thật
- [ ] Cập nhật Phase 5 trong `plans/260603-0958-user-keyed-realtime-ws/plan.md` → ✅
- [ ] `git merge-tree --write-tree main feat/ws-user-combined` vẫn exit 0

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Không có chip flash firmware branch | Ghi mục 13 là chặn; không đánh dấu pass khống |
| Volume postgres cũ thiếu `smart_watch_data.sql` | Apply thủ công trước khi test; đây là câu hỏi ops còn treo |
| VPN gây cô lập L2 giữa máy dev và ESP32 | Đã gặp trước đây (`docs/session-sync.md`) — tắt VPN trước khi test LAN MQTT |
| Verify tay xong lại có commit mới trên main | Chạy lại `git merge-tree` ở bước cuối |
| Có xu hướng đánh dấu pass cho mục không chạy được | Checklist bắt buộc ghi kết quả thật; "chưa verify" là kết quả hợp lệ |
