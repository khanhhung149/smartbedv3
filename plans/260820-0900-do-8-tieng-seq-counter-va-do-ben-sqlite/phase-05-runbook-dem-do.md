---
phase: 5
title: "Runbook đêm đo 8 tiếng"
status: completed
priority: P1
dependencies: [2, 3, 4]
---

# Phase 05: Runbook đêm đo 8 tiếng

## Overview
Tài liệu vận hành để một người **không viết code** chạy được đêm đo và đọc được kết quả, phủ cả hai đường ống.

## Requirements

**Chức năng**
- Thứ tự bật đủ hai stack, tránh va cổng 1883/1884.
- Danh sách kiểm trước khi đi ngủ — mỗi mục có lệnh cụ thể và output mong đợi.
- Truy vấn sáng hôm sau cho **cả hai** đường, kèm bảng đọc kết quả.
- Ghi rõ điều gì làm đêm đo mất giá trị.

**Phi chức năng**
- Đặt trong `docs/` (quy trình vận hành, không phải plan).
- Lệnh chạy được nguyên văn, không phải mô tả chung chung.

## Architecture

Nội dung theo bốn khối:

### 1. Chuẩn bị (chiều hôm trước)
- Nguồn: ổ cắm riêng trên bench rig, một adapter 5V/2A mỗi node, cáp USB ngắn lõi dày. **Không lấy nguồn từ laptop** (quy tắc chốt 13/07 — laptop ngủ là cắt nguồn).
- Máy host: tắt sleep/hibernate. Đây là mắt xích duy nhất phải thức suốt đêm.
- Địa chỉ host khớp `MQTT_HOST` của từng node (Phase 04).

### 2. Bật hệ
```
cloud/mqtt        → broker presence-ac (1883)
cloud/presence-ac → backend Go (8080), consumer đường A
cloud/sleeppad    → broker 1884 + FastAPI + Postgres + Redis, đường B
```
Ghi rõ node nào trỏ broker nào. Cổng 1883/1884 đã từng va — `.env.dev` phải set `MQTT_HOST_PORT`/`MQTT_WS_HOST_PORT`.

### 3. Kiểm trước khi đi ngủ

| Kiểm | Lệnh | Mong đợi |
|---|---|---|
| Node A đang publish | `mosquitto_sub -t 'home/room/sample' -C 5` | 5 dòng, `seq` tăng đều |
| Đồng hồ MCU đã sync | trường `t` trong payload | epoch ms hợp lý, không phải 0 |
| Backend đang ghi | đếm dòng `samples` cách nhau 60s | chênh ≈ 600 |
| WAL đang bật | `PRAGMA journal_mode` | `wal` |
| **Node B đã pair** | truy vấn bảng `devices` | có dòng khớp `device_id` |
| Node B đang vào DB | đếm `sec_data` cách nhau 60s | chênh ≈ 60 |

Mục "đã pair" là bẫy nghiêm trọng nhất: `subscriber.py:108` **drop im lặng** mọi frame từ thiết bị chưa pair. Bỏ qua mục này thì sáng ra 0 dòng, trông y hệt mất 100%.

### 4. Sáng hôm sau

**Đường A (radar, 10Hz, SQLite)** — dùng `seq`:

| Hiện tượng | Kết luận | Hướng sửa |
|---|---|---|
| `seq` thủng lỗ, `ts` liền mạch | mất trên đường | WiFi / QoS0 / broker |
| `seq` liền, `ts` nhảy quãng | MCU trượt nhịp | vòng lặp, UART radar |
| `boot` tăng giữa đêm | MCU reset | nguồn, brownout, watchdog |
| `seq = NULL` | firmware chưa cập nhật | flash lại |

Số mẫu kỳ vọng: 8h × 10Hz = **288.000**. Ngưỡng đạt: mất dưới 0,1% ⇒ không quá **288 mẫu**.

**Đường B (sleep-pad, 1Hz, TimescaleDB)** — không có `seq`, và **`time` không đáng tin**: pad trôi đồng hồ, firmware không gửi frame sync 0x0B (`subscriber.py:_insert_sec`). Đếm theo `received_at`, gom theo phút, tìm phút thiếu khung. Kỳ vọng 8h × 1Hz = **28.800** khung.

### 4b. Lịch bốn đêm

<!-- Updated: Validation Session 1 - đêm đầu chỉ soát thiết bị, không tính vào tiêu chí 5 -->

Tiêu chí 5 cần 3 đêm dữ liệu thật. Chốt ở phiên validate 20/08: **đêm đầu chỉ soát thiết bị**, không tính điểm.

| Đêm | Vai trò | Xử lý khi hỏng |
|---|---|---|
| 1 | Soát thiết bị — chạy đủ quy trình, mục đích là lộ lỗi vận hành | Sửa rồi chạy lại đêm 1, không tính vào 3 đêm |
| 2, 3, 4 | Tính điểm cho tiêu chí 1 và tiêu chí 5 | Hỏng đêm nào chạy bù đêm đó |

Runbook phải ghi rõ đêm đang chạy là đêm nào, để không nhầm đêm soát thành đêm tính điểm.

### 5. Điều làm đêm đo mất giá trị
- Máy host ngủ hoặc reboot.
- Cúp điện (WAL + `synchronous=NORMAL` mất các transaction chưa checkpoint).
- Flash lại firmware giữa đêm (`boot` nhảy, `seq` reset).
- Không có người nằm thật — radar không có gì để đo.
- Copy mỗi file `.db` mà bỏ file `-wal`/`-shm`.

## Related Code Files
- Create: `docs/runbook-dem-do-8-tieng.md`
- Modify: `docs/sensor-characterization.md` — trỏ sang runbook ở mục radar

## Implementation Steps
1. Viết `docs/runbook-dem-do-8-tieng.md` theo năm khối trên.
2. Chạy thử **từng lệnh** trong runbook trên hệ thật, sửa lệnh nào sai. Runbook chưa chạy thử là runbook chưa xong.
3. Thêm liên kết từ `docs/sensor-characterization.md`.
4. `bash scripts/check-doc-links.sh`.

## Success Criteria
- [ ] Mọi lệnh trong runbook đã chạy thật, không phải viết ra từ trí nhớ
- [ ] Phủ cả hai đường ống, kèm bẫy "chưa pair" và bẫy `time` không đáng tin
- [ ] Có bảng đọc kết quả ba nguyên nhân cho đường A
- [ ] `check-doc-links.sh` sạch
- [ ] Người không viết code đọc và làm theo được
- [ ] Có mục lịch bốn đêm, phân biệt đêm soát với đêm tính điểm

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Runbook viết từ trí nhớ, lệnh sai lúc 11h đêm | Bước 2 bắt buộc chạy thử từng lệnh |
| Hai stack va cổng | Ghi bảng cổng rõ ràng; `.env.dev` đã có biến override |
| Runbook lệch khi code đổi | Trỏ tới file:line thay vì chép lại logic |
