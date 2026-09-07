---
phase: 3
title: "Firmware radar-node — phát seq + boot"
status: completed
priority: P1
dependencies: [1]
---

# Phase 03: Firmware `radar-node` — phát `seq` + `boot`

## Overview
Thêm số thứ tự mẫu và số lần khởi động vào payload `home/room/sample`, và nới buffer để payload không bị cắt cụt.

## Requirements

**Chức năng**
- `seq` tăng đúng 1 mỗi mẫu **được dựng**, kể cả mẫu đi vào ring buffer.
- `boot` đọc từ NVS lúc khởi động, +1, ghi lại, giữ nguyên suốt phiên chạy.
- Mẫu phát lại từ ring buffer giữ nguyên `seq` gốc — không đánh số lại.

**Phi chức năng**
- Không đổi nhịp `SAMPLE_TICK_MS 100`.
- Không đổi QoS0 của topic sample.
- Payload không bao giờ bị `snprintf` cắt cụt.

## Architecture

### Nới buffer — bắt buộc, không phải tuỳ chọn

Payload xấu nhất hiện tại (mọi trường ở giá trị dài nhất) là **224 byte**. Thêm `,"seq":4294967295` (17B) và `,"boot":4294967295` (18B) ⇒ **259 byte** (+NUL = 260), vượt `SAMPLE_RB_LEN` 256.

`snprintf` cắt cụt **im lặng**: JSON hỏng ⇒ `json.Unmarshal` phía Go lỗi ⇒ mẫu bị drop. Triệu chứng sẽ là "mất mẫu ngẫu nhiên khi giá trị radar lớn", cực khó truy — đúng loại lỗi mà phase này sinh ra để diệt.

`SAMPLE_RB_LEN` 256 → **288**. RAM tĩnh: 64 × 288 = 18,4KB (ESP32-S2 có 320KB SRAM).

### `boot` trong NVS

NVS đã được `nvs_flash_init()` trong `app_main`. Thêm một namespace nhỏ:

```c
// boot_count tăng mỗi lần khởi động. Không có nó thì seq quay về 0 sau reset
// và số thứ tự trùng lại — không phân biệt được reset với mất mẫu.
static uint32_t boot_count_bump(void);  // đọc, +1, ghi lại, trả giá trị mới
```

Ghi NVS đúng **một lần** lúc boot — không ghi trong vòng lặp (flash có hạn số lần xoá).

### Thứ tự tăng `seq`

`seq` tăng trong `build_sample_json`, tức mỗi lần một mẫu được **dựng**. Mẫu vào ring buffer đã mang sẵn `seq` trong chuỗi JSON nên `sample_drain` phát lại không đụng gì.

Điểm cần chú ý: `publish_sample` thoát sớm khi `!net_time_ready()` — **trước** khi dựng payload. Nghĩa là mẫu bỏ qua lúc chờ NTP sẽ không tiêu tốn `seq`. Đúng như mong muốn: `seq` bắt đầu từ mẫu đầu tiên có mốc thời gian thật, nên lỗ hổng `seq` luôn có nghĩa là mất mẫu, không phải "đang chờ đồng hồ".

## Related Code Files
- Modify: `firmware/radar-node/src/main.c` — `SAMPLE_RB_LEN`, `build_sample_json`, biến `seq`/`boot`, `boot_count_bump`
- Modify: `docs/presence-ac/README.md` — mô tả contract topic `home/room/sample`
- Modify: `docs/sensor-characterization.md` — mục "Presence radar (LD2410C)"

## Implementation Steps

1. `SAMPLE_RB_LEN` 256 → 288, kèm comment ghi rõ phép tính 224 + 17 + 18 = 259, cộng NUL là 260 và vì sao lấy dư.
2. Thêm `static uint32_t s_sample_seq;` và `static uint32_t s_boot_count;`.
3. Viết `boot_count_bump()` dùng `nvs_open`/`nvs_get_u32`/`nvs_set_u32`/`nvs_commit`. Khoá chưa tồn tại ⇒ bắt đầu từ 0.
4. Gọi trong `app_main` sau `nvs_flash_init()`, log giá trị ra để soi được lúc bench.
5. `build_sample_json`: thêm `"seq":%u,"boot":%u` và `s_sample_seq++`.
6. Build: `idf.py build` — kiểm không có cảnh báo truncation.

## Success Criteria
- [ ] Build sạch, không cảnh báo `-Wformat-truncation`
- [ ] Bench: 1000 mẫu liên tiếp, `seq` tăng đều không thủng, `boot` không đổi
- [ ] Reset board giữa chừng: `boot` tăng đúng 1, `seq` quay về 0
- [ ] Payload ở giá trị radar lớn nhất vẫn là JSON hợp lệ (backend parse được, không drop)
- [ ] Ngắt WiFi 5 giây rồi nối lại: mẫu phát bù từ ring buffer giữ nguyên `seq` gốc, không đánh số lại

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Quên nới buffer ⇒ cắt cụt im lặng | Bước 1 làm trước tiên; success criteria có ca giá trị lớn nhất |
| Ghi NVS trong vòng lặp làm mòn flash | Chỉ gọi `boot_count_bump` một lần trong `app_main` |
| `seq` tràn `uint32` | 4,29 tỷ mẫu ở 10Hz là ~13,6 năm. Không xử lý |
| Firmware cũ và mới chạy lẫn trên cùng broker | Cột nullable từ Phase 01 chịu được; mẫu từ node cũ có `seq = NULL` |
