# Sensor Characterization — SmartBed v3

- **Status:** live document, filled in as each cluster is bench-tested
- **Started:** 2026-08-14

## What belongs here

**Measured numbers only.** Every figure in this file must trace back to a real reading from real hardware: what was measured, under what conditions, with what method.

A datasheet figure is not a measurement. An estimate is not a measurement. If a number has not been measured yet, the row says **not measured** — it does not say a plausible-looking guess.

This rule exists because it was broken. The previous camera node planned around "~35 KB/frame assumed, not yet measured", and the assumption turned out to matter. A number nobody measured, written down without a label, becomes a fact nobody questions.

Sensors are listed as they get characterized. Most of Phase 01's clusters are still missing.

---

## ESP32-CAM stream node (OV2640)

- **Firmware:** [`firmware/esp32cam-stream/`](../firmware/esp32cam-stream/README.md)
- **Role:** behavior observation for the vision PoC. Bench-test only, never with a real user on the bed (hazard H-25)
- **Measured:** 2026-08-14

### Configuration

| | |
|---|---|
| Sensor | OV2640, AI-Thinker ESP32-CAM board |
| Resolution | VGA 640×480 |
| Encoding | JPEG, quality 12 (0–63 scale, lower = better) |
| Frame buffers | 2, in PSRAM (61440 B each) |
| Transport | MJPEG over HTTP, `multipart/x-mixed-replace`, port 81 |
| Storage | **none** — no SD, no filesystem. Frames exist only in flight |

**One stream client at a time.** The board serves the HTML page (port 80) and the stream (port 81) from two separate HTTP servers, so viewing in a browser no longer blocks the page — but two *stream* readers still cannot coexist. A second reader gets a connection that never delivers data. Close the browser tab before running the PoC.

### Throughput

Measured by counting JPEG start/end markers on the client side over a continuous window. Not derived from the datasheet, not extrapolated.

| Condition | fps | Frame size | Bandwidth |
|---|---|---|---|
| Stream only, empty scene (ceiling), 30 s | 20.3 | 10.0 KB avg (9.9–10.1) | 204 KB/s ≈ 1.67 Mbit/s |
| Stream only, **person in frame**, 25 s | **23.9** | **15.7 KB** avg (11.6–17.2) | 378 KB/s ≈ 3.10 Mbit/s |
| Stream + serving the HTML page on port 80 | 23.2 | not measured | not measured |
| Stream + Pose inference, **empty scene**, 5.5 min | 22.8 | — | — |
| Stream + Pose inference, **person in frame**, 40 s | **8.7** | — | — |

A person in frame makes each JPEG **57% larger** (10.0 → 15.7 KB) and far more variable, because there is real detail to encode instead of a flat wall. The node itself does not slow down — it still pushes ~24 fps.

**Pose inference is the bottleneck, not the camera and not WiFi.** The two rows above make this unambiguous: with a person in frame the stream alone runs at 23.9 fps but the same stream with inference attached drops to 8.7 fps.

This is easy to get backwards. The 22.8 fps measured against an empty ceiling looks like proof that inference is cheap — it is not. With nothing to detect, the model bails out early; with a real person it runs the full 33-landmark regression. **Any figure measured against an empty scene says nothing about inference cost** and must not be quoted as a performance budget.

8.7 fps is still ample for observing sleep posture, where a person changes position over seconds, not milliseconds. It would not be enough for fast motion.

For contrast, the previous node (`esp32cam-node`, SVGA, writing to an SD card) managed ~1.5 fps. The bottleneck was the SD card, not the camera and not WiFi.

### Reliability

| | Result |
|---|---|
| Continuous run, stream + inference | 5.5 min, 7509 frames, **0 read failures**, no crash, no hang |
| Pose detection rate, person in frame | **343/347 frames (99%)**, 33 landmarks each |
| Recovery after the node reboots mid-stream | dropout detected in 3.0 s, reconnected, stream alive ~1 s later |

Note on that 3.0 s: OpenCV's FFMPEG backend defaults to a **30 second** read timeout, and it ignores the timeout when set via `cap.set()` after opening — it must be passed to the `VideoCapture` constructor. Measured both ways: 30.1 s versus 3.0 s. Any client reading this stream needs the same treatment, or it will keep showing a frozen frame for half a minute while believing all is well.

### Network conditions during measurement

| | |
|---|---|
| Band | 2.4 GHz (the ESP32 cannot use 5 GHz) |
| RSSI | −64 dBm |
| Security | WPA2-PSK |
| Channel | 13, BW20 |

### Not measured yet

- **End-to-end latency** (photons → pixels on screen). Needs a person or a moving reference in frame to have anything to compare against.
- **Full-body framing.** The person-in-frame figures above were measured with the camera aimed at a head and shoulders from close range, not at a whole body from above a bed. Landmark quality for actual sleep postures is still unmeasured.
- **Low-light behavior.** See the vision pipeline risks in [`system-architecture.md`](system-architecture.md): the OV2640 has no IR, so this is expected to fail rather than degrade, and that expectation itself is still unmeasured.
- **Thermal behavior over a full night.** The node has only ever run for minutes at a time.

---

## Presence radar (LD2410C) — reliability

- **Firmware:** [`firmware/radar-node/`](../firmware/radar-node/) (Wemos S2 Mini + LD2410C, ESP-IDF thuần)
- **Measured:** 2026-08-25/26, sau khi chuyển stack sang Jetson (192.168.1.125)

### Sự cố phần cứng đã tìm ra và fix

`uart_ok` báo `false` tuyệt đối (`raw_bytes/2s=0`) dù dây GND/TX/RX đo thông mạch tốt và module LD2410C xác nhận sống qua app HLK-LD2410 (BLE độc lập, không qua ESP32). Cách loại trừ từng bước:

1. Đo thông mạch GND giữa board và cảm biến khi **có điện** → báo `OL` (hở mạch) — SAI: đo continuity khi mạch có điện luôn cho kết quả sai. Tắt nguồn đo lại → thông mạch thật.
2. Đo tiếp TX/RX (tắt nguồn) → thông mạch tốt.
3. Test module độc lập qua app HLK-LD2410 (BLE) → module sống, đọc được số liệu thật.
4. Đổi thử chân nhận UART từ GPIO33 sang GPIO35 (giữ nguyên baud 115200, dây, code logic) → `raw_bytes/2s` từ 0 lên 460 ngay lập tức, `uart_ok:true`.

**Kết luận: GPIO33 trên board S2 Mini hỏng vật lý** (không phải GND/baud/code/module) — khả năng do va đập/chập khi thao tác USB nhiều lần. Đã đổi vĩnh viễn sang **GPIO35** (`firmware/radar-node/src/main.c:PIN_RADAR_RX`, `platformio.ini`).

### Độ ổn định kết nối (đo trên Jetson)

| Điều kiện | Kết quả |
|---|---|
| Kết nối liên tục, không rớt | **13.3 phút** (từ lúc connect tới lúc verify cuối), 0 sự kiện disconnect trong log broker |
| Nhịp `seq` | Tăng đều 1 đơn vị/mẫu, không thủng, khớp đúng 10Hz (~100ms/mẫu) trong mọi lần lấy mẫu |
| `boot` counter | Ổn định trong suốt cửa sổ theo dõi (không tự reset ngoài ý muốn) |
| **Chưa đo** | Chạy liên tục 8 tiếng (tiêu chí Phase 01 #1) — chưa thực hiện, xem `plans/reports/` cho kế hoạch |

### Đặc thù USB CDC gốc (ESP32-S2, không liên quan cảm biến)

Board dùng USB CDC gốc (`CONFIG_ESP_CONSOLE_USB_CDC=y`), không có chip UART-USB rời. Nhấn nút RESET thường (soft reset) thường **không** khiến Windows re-enumerate lại COM port; phải rút/cắm lại cáp USB vật lý. Giữ BOOT+RESET (vào bootloader) luôn re-enumerate sạch. Không ảnh hưởng hoạt động WiFi/MQTT của board — chỉ ảnh hưởng khả năng xem log qua cổng USB.

---

## Voice node (ESP32-S3, wakeword + snore, mic INMP441)

- **Firmware:** [`firmware/voice-node/`](../firmware/voice-node/)
- **Measured:** wakeword benchmark trước 2026-08-25 (xem `docs/deployment-guide.md`); snore threshold logic đo lại 2026-08-25/26 sau khi chuyển Jetson

### Wakeword ("Vừng ơi")

| | |
|---|---|
| True-positive rate | 73.3% |
| False-trigger | ~2.48 lần/giờ ở threshold 0.80 |
| Infer time | 6-11ms/lần (đo qua log `[wakeword] infer=`) |

### Snore detection — 5 phiên bản logic đã thử, chỉ 1 phiên bản hoạt động

Model: [`alek6kun/snore-recognition`](https://github.com/alek6kun/snore-recognition) (Apache-2.0), threshold `SNORE_SCORE_THRESHOLD=0.45`. Train trên dataset Khan 2019 (ngáy thu gần, phòng thu sạch) — khác điều kiện mic INMP441 thật của node, nên confidence "ngáy" và "nhiễu" **chồng lấn hoàn toàn** (đo 24/08: ngáy 0.461-0.871, nhiễu 0.461-0.98 — không ngưỡng nào tách được).

Đặc điểm quan trọng của tín hiệu ngáy thật đo được: **score dao động hit-miss-hit-miss mỗi giây** (không liên tục), do ngáy tự ngắt theo nhịp thở.

| Bản | Cơ chế event | Kết quả verify thật |
|---|---|---|
| v1 (hiện tại, production) | 3 hit rời rạc trong 15s (không cần liên tục) | **Bắn được** 2 sự kiện ngáy thật (confidence 0.852, 0.938) ngay lần test đầu |
| v2 | Đợt liên tục ≥3s, không chịu ngắt | 0 sự kiện — burst thật tối đa chỉ đạt 2s rồi reset |
| v3 | Đợt ≥3s, chịu ngắt tối đa 1s | 0 sự kiện sau 85s test |
| v4 | Đợt ≥3s, chịu ngắt tối đa 2s | 0 sự kiện sau 60s test |
| v5 | Đợt ≥2s, chịu ngắt tối đa 2s | Gần đạt nhất (`bursts_in_window` tối đa 2/3) nhưng không ổn định qua 180s test, vẫn 0 sự kiện |

**Bài học:** với tín hiệu ngáy dao động hit-miss mỗi giây, yêu cầu "đợt liên tục" luôn kém nhạy hơn "đếm hit rời rạc trong cùng cửa sổ thời gian" — vì đợt đòi hỏi nhiều sự kiện tách biệt tự kéo dài vài giây, gói gọn trong cùng 1 khung, là điều kiện tổ hợp chặt hơn nhiều. Đã revert về v1, dừng thử biến thể đợt.

| | |
|---|---|
| Infer time (snore) | 75-95ms/lần, giữ mutex dùng chung với wakeword (~105ms tối đa quan sát được) |
| Heap/PSRAM | Ổn định qua các cửa sổ test (không rò rỉ quan sát được): `heapFree≈83xxx B`, `psramFree=8014528 B` không đổi |
| **Chưa đo** | Confidence trên tập ngáy thật lớn hơn (n hiện tại quá nhỏ để kết luận % chính xác thật) |

---

## Sleep pad node (Legact V2, BLE provisioning)

- **Firmware:** [`firmware/sleep-pad-node/`](../firmware/sleep-pad-node/) (ESP32-C3 Super Mini)
- **Measured:** 2026-08-25, pairing qua nRF Connect (BLE thủ công) sau khi chuyển Jetson

| | |
|---|---|
| Provisioning | BLE GATT, quảng bá tên `SleepPad-{6 ký tự cuối MAC}`, 6 characteristic WRITE (WiFi SSID/pass, MQTT host/user/pass/scheme) + 1 STATUS (READ/NOTIFY) + 1 DEVICE_ID (READ) |
| Trạng thái sau ghi đủ 6 WRITE | `waiting → wifi_connecting → wifi_connected → mqtt_connecting → connected`, verify qua Status characteristic |
| **Bẫy đã gặp:** file `dev-config.h` (gitignored, dùng cho bài đo tại chỗ) tự nạp lại WiFi/MQTT cứng vào NVS mỗi khi NVS trống — khiến `erase_flash` một mình không đủ để ép vào lại chế độ BLE provisioning | Phải xoá hẳn file `dev-config.h` khỏi build, không chỉ sửa IP trong đó |
| Pairing tài khoản | **Tách biệt** khỏi BLE provisioning — cần gọi API `/devices/pair` (JWT) riêng để ghi vào bảng `devices`, nếu không MQTT connect được nhưng mọi frame vẫn bị FastAPI drop im lặng (`subscriber.py:107`) |
| **Chưa đo** | Pairing qua app `sleep-pad` thật (đã dùng workaround SQL insert user test để verify pipeline, chưa qua UI thật) |

---

## Other Phase 01 clusters

Not characterized yet: LD2510B radar (đang dùng LD2410C thay thế), piezoelectric pad, SHT10/31, CO₂ sensor.

Add one section per cluster using the shape above: configuration, measured throughput, reliability, conditions during measurement, and an explicit list of what remains unmeasured.

---

## Data-acquisition contract (Phase 01 firmware/collector)

**Measured on hardware, not extrapolated.** These rows record what the current nodes actually deliver into the pipeline, including the gaps the plan's ideal cadence cannot reach with the hardware we have.

### Sleep pad (Legact V2) → `sleeppad/{id}/sec|min`

- **Firmware:** [`sleep_pad_AI/firmware/`](../../sleep_pad_AI/firmware/) (ESP32 + Legact V2 pad)
- **Transport:** MQTT JSON → TimescaleDB (bảng `samples` schema CSV take-home)

| | |
|---|---|
| Cadence | **1 Hz (sec 0x85), 1/min (min 0x86)** — pad là master tự đẩy frame, firmware KHÔNG thể ép thành 10 Hz. 10 Hz là mục tiêu của plan nhưng bị chặn bởi phần cứng pad (xem ghi chú bên dưới) |
| Timestamp | `ts` epoch giây do **MCU** gắn (SNTP sync lúc boot), đẩy trong payload; `ts_pad` = mốc pad báo. Backend ghi `t = ts` (không dùng server now() làm nguồn thời gian) |
| Chống mất mẫu | Ring buffer 64 ô trong firmware — MQTT mất kết nối thì mẫu xếp hàng, đẩy lại khi thông (bỏ cũ nhất nếu đầy) |
| Đánh dấu lỗi | `heart_rate = 0` = dropout (pad báo, không bịa số); `uart_ok` bool trong payload. `presence` suy = status/hr/rr khác 0 |
| Kênh raw | status, sdata, pdata (sec) + movement, snore_count, resp_disorder, pthd, temp (min) + env_temp/humidity (topic /temp) — lưu TẤT CẢ vào `samples` |
| Retention | TimescaleDB `add_retention_policy('samples', 30 days)` — giữ 30 đêm; chunk > 1 ngày được nén |

> **Ghi chú 10 Hz:** Legact V2 là thiết bị master phát frame 0x85 mỗi giây; ESP32 chỉ là khách lắng nghe UART, không có kênh nào để yêu cầu pad phát nhanh hơn. Firmware giữ vòng lặp **10 Hz cố định** (bám mốc tuyệt đối, không jitter) để đọc UART + drain ring buffer, nhưng số mẫu thực tế là 1 Hz theo nhịp pad. Để có 10 Hz thật phải thay cảm biến (vd radar ở cluster khác).

### Presence radar (LD2410C) → `home/room/sample`

- **Firmware:** [`firmware/radar-node/`](../firmware/radar-node/) (Wemos S2 Mini + LD2410C, ESP-IDF thuần)
- **Transport:** MQTT JSON → Go backend SQLite (bảng `samples`)

| | |
|---|---|
| Cadence | **10 Hz cố định** (`SAMPLE_TICK_MS = 100`), bám mốc tuyệt đối |
| Timestamp | `t` epoch **mili-giây** do MCU gắn (`net_epoch_ms`), không gắn ở Linux |
| Chống mất mẫu | Ring buffer 64 mẫu (~6.4 s) trong firmware — MQTT nghẽn thì xếp hàng, drain khi thông |
| Đánh dấu lỗi | `uart_ok` bool; UART radar chết → các kênh số liệu (moving/still) không đáng tin, `presence` vẫn đúng từ chân OUT. Kênh radar không đo được (hr_bpm, resp_amplitude, weight_kg, spo2, temp_c, humidity) ghi 0 — không bịa số |
| Kênh raw | moving_dist_cm, moving_energy, still_dist_cm, still_energy (lưu tất cả) |
| Retention | Go `RetainNights(30)` mỗi giờ — giữ 30 đêm theo mốc UTC nửa đêm; trần tuyệt đối 11M mẫu |

> **Ghi chú LD2410C vs LD2510B:** plan tổng chốt LD2510B (track 2 người + vị trí); cụm này hiện dùng **LD2410C** (quyết định chủ repo, dùng phần cứng đang có). Hệ quả đã đo/ghi nhận: không có kênh 2 người, không có tọa độ, không có HR/resp. Các cột đó trong `samples` luôn 0/NULL kèm cờ — đúng quy tắc "không bịa số". Nâng cấp lên LD2510B là thay phần cứng + thêm parser, schema không đổi.

### Dashboard local

| Repo | URL | Dữ liệu |
|---|---|---|
| sleep_pad_AI | `/dashboard` (FastAPI static + JWT) | realtime 2 phút + xem lại một đêm từ bảng `samples` |
| esp32-presence-ac | `/dashboard` (Go embed) | realtime 60 s + xem lại một đêm từ SQLite `samples` |

Cả hai chạy ngay trên máy thu (Jetson), không cần app mobile. Không làm đẹp — công cụ engineer debug.
