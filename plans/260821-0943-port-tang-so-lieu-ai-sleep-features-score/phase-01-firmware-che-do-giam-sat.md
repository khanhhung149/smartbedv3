---
phase: 1
title: "Firmware: đưa pad về chế độ giám sát của hãng"
status: abandoned
priority: P1
dependencies: []
---

# Phase 01: Firmware — chế độ giám sát `0x20`

## Kết quả nghiệm thu thật trên phần cứng — 24/08, board cắm trực tiếp

**R1 đã xảy ra thật, tái hiện 3 lần độc lập.** Trước phiên này, trạng thái `completed` dựa trên
`insert_mock.sql` — script chèn tay 15 dòng giống hệt nhau vào `min_data` (đã xoá, xem
`plans/reports/` cho chi tiết điều tra). Chưa từng có board thật xác nhận cho tới hôm nay.

Đã nạp lại firmware biên dịch từ source hiện tại (hash verified), mở serial thật, bắt log từ lúc
board vừa reset (mở cổng serial trước khi reset để không mất dòng đầu):

```
[Mode] Yêu cầu chuyển sang chế độ giám sát 0x20 (frame)...
[Boot] Ready
[0x85/TAOSG] ts=0 status=0 hr=0 rr=0.0 sdata=555 pdata=3933
... (18 dòng TAOSG ts=0, không có khung 0x87/0x84 nào)
[Mode] Timeout 15s không nhận được khung 0x85
[Mode] lùi về TAOSG — bat che do phat 66 byte/giay
[0x85/TAOSG] ts=0 status=0 hr=75 rr=21.3 sdata=316 pdata=3935   ← dữ liệu thật, biến thiên tự nhiên
```

Đối chiếu: cấu trúc khung đã kiểm byte-đối-byte đúng ví dụ tài liệu (`7D 0C 0F 00 … 0D`) — không
phải lỗi dựng khung. Pad **không phản hồi một byte nào** cho khung `[0x07]` (0 lần thấy `0x87` qua
3 lần bắt log). Cơ chế lùi TAOSG hoạt động đúng thiết kế — không mất dữ liệu.

**Kết luận:** con LSM-800-T này im lặng hoàn toàn trước giao thức khung `0x7D`. Nhiều khả năng
firmware trên chính con pad chỉ nói được TAOSG cũ, không phải lỗi ở phía ESP32. Đường `min_data`/
`0x86` là ngõ cụt với phần cứng đang có — không sửa được chỉ bằng code ESP32.

**Hệ quả:** toàn bộ tiền đề của kế hoạch `260821-0943` (lấy `min_data` thật để port
`sleep_features.py`/`sleep_score.py` lên trên) không thành lập được. Code port (pha 02–03, 27/27
test xanh) vẫn đúng và giữ nguyên giá trị, nhưng sẽ không có dữ liệu thật để chạy trên cho tới khi
có hướng khác cho pad này.

## Overview

Thêm hàm dựng khung `0x7D` vào `sleep-pad-node`, gửi `[0x04][0x20]` đưa pad vào *host computer
monitoring mode*, hiệu chỉnh đồng hồ bằng `[0x0B]`, và tự lùi về `TAOSG` nếu pad không đáp ứng.

Mục tiêu thật: làm bảng `min_data` có dữ liệu **do chính pad tính**, để ba pha sau port nguyên văn.

## Requirements

**Chức năng**

- Dựng và gửi được khung theo cấu trúc hãng.
- Vào chế độ `0x20`, xác nhận bằng khung `0x84` + nội dung `0x20`.
- Gửi `[0x0B]` hiệu chỉnh đồng hồ ngay sau khi vào chế độ, dùng giờ đã SNTP-sync của MCU.
- Không thấy khung `0x85` trong N giây (đề xuất N = 15) → lùi về `sp_send_taos("TAOSG")`.
- Đường TAOSG và `feedTaos()` **giữ nguyên**, không xoá.

**Phi chức năng**

- Không được làm mất đường `sec_data` đang chạy. Lùi về phải tự động, không cần nạp lại firmware.
- Log rõ chế độ đang chạy để chẩn đoán từ serial.

## Architecture

### Cấu trúc khung (tài liệu, mục "Overall data structure")

```
[0x7D 1B] + [frame type 1B] + [frame length 2B, little-endian] + [ID 10B ASCII] + [content] + [0x0D]
```

`frame length` = **tổng số byte của cả khung** = `15 + len(content)`.

Ví dụ trong tài liệu, truy vấn phiên bản `[0x0C]` không nội dung:

```
7D 0C 0F 00 55 4E 43 4F 4E 46 49 47 45 44 0D
│  │  └─┬─┘ └──────── "UNCONFIGED" ────────┘ └ kết thúc
│  │    └ độ dài 0x000F = 15
│  └ loại khung 0x0C
└ header
```

### Ba khung cần gửi

| Mục đích | Khung | Nội dung | Độ dài |
|---|---|---|---|
| Hỏi trạng thái + học ID thật | `0x07` | không | `0x000F` = 15 |
| Vào chế độ giám sát | `0x04` | `0x20` | `0x0010` = 16 |
| Hiệu chỉnh đồng hồ | `0x0B` | 4 byte epoch little-endian | `0x0013` = 19 |

### Vấn đề device ID

Khung gửi đi cần **ID 10 byte ASCII của pad**, không phải `DEVICE_ID` suy từ MAC của ESP32.

Tài liệu mục 2.5 mở đường: *"Since the host computer does not know the device ID when connecting to
it for the first time, the device will respond if the ID in the sent frame is any 10-digit ASCII code."*

Nên trình tự: gửi `0x07` với ID giả `UNCONFIGED` → pad trả khung `0x87`, và **ID thật nằm ở byte 4–13
của chính khung trả lời** → lưu lại, dùng cho `0x04` và `0x0B`.

`uart-parser.cpp` hiện bỏ qua vùng ID (nội dung bắt đầu ở index 14). Cần thêm callback hoặc trường
lưu ID khi parse được khung bất kỳ.

### Máy trạng thái khởi động

```
BOOT
 └─> gửi 0x07 (ID = "UNCONFIGED")
      ├─ nhận 0x87 → lưu ID thật, đọc [mode 1byte]
      │    ├─ mode = 0x20 → đã ở chế độ giám sát, chỉ gửi 0x0B
      │    └─ mode ≠ 0x20 → gửi 0x04 + 0x20, chờ 0x84
      │         ├─ 0x84 nội dung 0x20 hoặc 0x21 → OK, gửi 0x0B
      │         └─ 0x84 nội dung 0x22 → pad lỗi, log rồi lùi TAOSG
      └─ không nhận gì trong 15s → lùi TAOSG
```

Sau khi vào chế độ, nếu **15 giây không có khung `0x85` nào** thì cũng lùi TAOSG. Đây là lưới an toàn
cuối: pad có thể trả `0x84` rồi vẫn không phát dữ liệu.

`start_monitor_mode()` hiện gọi thẳng `sp_send_taos("TAOSG")` — đổi thành điểm vào của máy trạng thái
trên. `on_idle()` (khung `0x87` idle) đang gọi `start_monitor_mode()`, giữ nguyên hành vi khôi phục.

## Related Code Files

- Modify: `firmware/sleep-pad-node/src/main.cpp` — `start_monitor_mode()`, máy trạng thái, timeout
- Modify: `firmware/sleep-pad-node/src/uart-parser.cpp` — lưu ID thật khi parse khung; xử lý `0x84`, `0x87`
- Modify: `firmware/sleep-pad-node/src/uart-parser.h` — khai báo callback/trường mới
- Create: `firmware/sleep-pad-node/src/sleep-pad-frame.cpp` + `.h` — hàm dựng và gửi khung `0x7D`
- Reference (không sửa): `firmware/sleep-pad-node/src/mqtt-client.cpp:369` — `mqtt_publish_min()` đã sẵn sàng

## Implementation Steps

1. Viết `sleep-pad-frame.{h,cpp}`: `void sp_send_frame(uint8_t type, const uint8_t* content, size_t n)`
   dựng đúng cấu trúc trên, dùng ID đã học hoặc `"UNCONFIGED"` khi chưa có.
2. Thêm lưu ID thật trong `SleepPadParser::feed()` — vùng byte 4–13, chỉ lưu khi khác `"UNCONFIGED"`.
3. Thêm xử lý khung `0x84` (xác nhận chế độ) và mở rộng `0x87` để đọc `[mode][error][4byte time]`.
   Hiện `0x87` đang được coi là "idle, restart monitor mode" — kiểm lại xem đó có phải cùng một khung
   không, vì tài liệu mô tả `0x87` là **trả lời truy vấn trạng thái**. Nếu trùng mã thì phân biệt bằng
   độ dài nội dung (6 byte = trả lời truy vấn).
4. Viết máy trạng thái khởi động trong `main.cpp` theo sơ đồ trên, kèm timeout 15 giây.
5. Gửi `[0x0B]` với `time(nullptr)` sau khi SNTP đã sync (hàm `sync_time()` đã có sẵn).
6. Log mỗi lần chuyển chế độ: `[Mode] 0x20 monitoring` hoặc `[Mode] lùi về TAOSG`.
7. Nạp và quan sát serial trong 3 phút: phải thấy `[0x85]` mỗi giây và `[0x86]` **mỗi phút**.

## Success Criteria

- [x] `pio run -e c3supermini` sạch, không cảnh báo mới — biên dịch 24/08, hash verified khi nạp.
- [x] Rút yêu cầu 0x20 không đáp ứng → firmware tự lùi về TAOSG trong 15 giây, `sec_data` tiếp tục
      chảy, không phải nạp lại — **quan sát thật, không phải kịch bản ép**: pad tự thân không đáp
      ứng, cơ chế lùi kích hoạt đúng như thiết kế.
- [ ] ❌ Serial in `[0x86] ts=… status=… mov=… snore=…` — **chưa từng thấy một dòng nào**, 3 lần bắt
      log độc lập 24/08.
- [ ] ❌ `min_data` có 1 dòng/phút cho `CNU10CDADC` trong 10 phút liên tục — **không đạt trên phần
      cứng thật**. (15 dòng trước đó là `insert_mock.sql` chèn tay, đã xoá 24/08.)
- [ ] ❌ `min_data.status` nằm trong `{1,2,3,4,5,6}` — không áp dụng được, `min_data` rỗng.
- [ ] ❌ Đối chiếu chéo `SUM(min_data.movement)` — không áp dụng được, không có dữ liệu để đối chiếu.
- [x] `sec_data` vẫn ~1 dòng/giây — xác nhận, 286 mẫu/5 phút lúc kiểm 24/08.

## Risk Assessment

| Rủi ro | Mức | Kết quả |
|---|---|---|
| LSM-800-T không hỗ trợ `[0x04][0x20]` | **Cao — ĐÃ XẢY RA, xác nhận 24/08** | Pad không phản hồi `[0x07]` (0/3 lần thấy `0x87`). Lùi TAOSG hoạt động đúng, không mất dữ liệu `sec_data`. Đường `min_data` là ngõ cụt với phần cứng này — cần hướng khác (hỏi hãng, thử firmware pad khác, hoặc bỏ pha này). |
| Sai độ dài khung → pad im lặng bỏ qua | Đã loại trừ | Đối chiếu byte-đối-byte với ví dụ `7D 0C 0F 00 …0D` — khớp. Không phải nguyên nhân. |
| Không biết ID thật của pad | Không quan sát được | Pad chưa từng trả `0x87` nên chưa từng học được ID thật. |
| `0x87` trùng mã giữa "idle" và "trả lời truy vấn trạng thái" | Không còn liên quan | Pad không gửi `0x87` trong bất kỳ trường hợp nào quan sát được. |
| Chuyển chế độ làm mất mẫu vài giây | Thấp — xác nhận không đáng kể | `sec_data` liên tục suốt quá trình chờ timeout. |

## Đóng pha — 2026-08-24

Đã sửa lại đúng state machine gửi lệnh theo mẫu `Sleep-Tech-AI/sleep-pad-ai` (bỏ hỏi `[0x07]`/chờ
ACK, chỉ gửi `[0x04][0x20]` một lần + heartbeat `[0x08]`) trong lúc port `firmware/sleep-pad-node`
sang ESP-IDF (`260824-1109-dong-bo-sleep-pad-node-esp-idf`), đồng thời sửa thêm 1 bug dây UART độc
lập. Sau khi sửa cả hai, theo dõi 150s thật: vẫn 0 khung `[0x86]`. Đã hết nguyên nhân trong tầm
kiểm soát code/dây. Người dùng quyết định bỏ hướng `0x20`, đóng pha này.
