# Báo cáo hệ thống — 4 node đã chạy được (Hưng)

- **Người báo cáo:** Hưng
- **Mục đích:** mô tả đúng những gì đã chạy thật
- **Phạm vi:** 4 node ESP32 + 2 backend độc lập đã implement và chạy được trên LAN. Không bao gồm cơ khí (Phase 04, chưa có gì) hay Jetson (chưa tham gia đường dữ liệu nào tính đến nay).

---

## Tổng quan hệ thống đã làm

Đã dựng **2 hệ thống độc lập**, mỗi hệ có broker MQTT và backend riêng — không dùng chung stack:

| | Hệ A — presence-ac | Hệ B — sleeppad |
|---|---|---|
| Node ESP32 | `radar-node`, `voice-node` | `sleep-pad-node` |
| Broker MQTT | Mosquitto, cổng **1883** | Mosquitto, cổng **1884**, stack riêng |
| Backend | Go | FastAPI (Python) |
| Lưu trữ | SQLite | TimescaleDB (Postgres) + Redis |
| Nhịp dữ liệu thật | 10Hz (radar) | 1Hz (pad là master, không ép nhanh hơn được) |

`camera-node` (ESP32-CAM MJPEG) chạy độc lập, stream trực tiếp qua HTTP, không qua MQTT, không phụ thuộc 2 hệ trên.

Cả 2 hệ hiện chạy trên **máy dev trong LAN**, chưa có phần nào chạy trên Jetson.

---

## Chi tiết từng node đã implement

### 1. `radar-node` — cảm biến hiện diện + chuyển động (LD2410C)

- Board Wemos S2 Mini, firmware ESP-IDF, vòng lặp 10Hz cố định.
- Có cơ chế chống mất mẫu (`seq`/`boot` counter) — đã đo thật qua broker, parse đúng payload.
- Publish topic `home/room/sample`.
- Dữ liệu thật thu được: `presence`, `moving_energy`, `still_energy`, khoảng cách. `resp_amplitude` và `hr_bpm` hiện luôn = 0 — chip này chưa được khai thác để đo biên độ thở.
- Ghi chú phần cứng: đang dùng chip **LD2410C**, khác với LD2510B trong spec gốc — chưa có multi-person tracking hay toạ độ thật.

### 2. `sleep-pad-node` — theo dõi giường bằng pad thương mại

- ESP32 giao tiếp UART với pad Legact V2.
- Pad tự tính sẵn `heart_rate`, `resp_rate`, `status`, `movement`, `snore_count`, `resp_disorder` — không phải sóng thô, ESP32 chỉ đóng gói lại thành JSON.
- Publish `sleeppad/{device_id}/sec|min|temp`. Nhịp thật 1Hz (giây) + 1/phút, do pad là bên chủ động đẩy dữ liệu.
- `heart_rate = 0` là quy ước dropout đã thống nhất, không phải chỉ số thật.

### 3. `voice-node` — mic + 2 model TFLite Micro

- ESP32-S3-CAM N16R8 + mic INMP441 (I2S).
- Đã chạy đồng thời 2 việc trên cùng 1 luồng audio: nhận diện từ khoá "Vừng ơi" và phát hiện tiếng ngáy.
- Kết quả đo thật: wakeword true-positive 73.3%, false-trigger ~2.48 lần/giờ ở threshold 0.80.
- Vị trí lắp hiện tại: **tại giường** — đây chính là mic dùng cho fusion apnea/snore của Phase 02, không phải mic phòng riêng.

### 4. `camera-node` — stream MJPEG (ESP32-CAM, OV2640)

- Stream trực tiếp qua HTTP, không lưu trữ ở bất kỳ đâu (không SD, không file).
- Đo thật: ~24fps khi stream đơn thuần, ~8.7fps khi chạy kèm MediaPipe Pose (nghẽn ở bước inference, không phải camera hay WiFi).
- Chỉ phục vụ bench-test nội bộ, chưa dùng khi có người thật nằm giường (giới hạn an toàn đã ghi nhận).

---

## Hạ tầng

Để 2 hệ trên chạy được ngoài máy dev hiện tại, cần:

1. **2 broker MQTT** (Mosquitto) độc lập — mỗi hệ 1 broker, không dùng chung.
2. **Backend Go** cho hệ presence-ac — cần SQLite (file volume) là đủ, không cần DB server riêng.
3. **Backend FastAPI** cho hệ sleeppad — cần Postgres (TimescaleDB extension) + Redis chạy cùng.
4. **Service ASR self-host** (`faster-whisper`) cho voice-node — chạy nội bộ, không expose ra ngoài, cần model cache tồn tại qua các lần restart.
5. **Địa chỉ IP/DNS cố định** cho từng broker — địa chỉ này **compile cứng vào firmware** của `radar-node` và `sleep-pad-node`, nên môi trường mới cần chốt IP trước khi Hưng flash lại node trỏ vào đó.
6. **Biến môi trường / secret** theo từng backend (mẫu tham khảo: `cloud/presence-ac/.env.example`, `cloud/sleeppad/.env.prod.example`) — gồm thông tin MQTT, JWT secret, thông tin mail, và file service account Firebase cho push notification.

---

## Hiện trạng chưa hoàn thiện (Michael cần biết khi lên kế hoạch)

| Hạng mục | Hiện trạng |
|---|---|
| Jetson | Chưa tham gia đường dữ liệu nào — toàn bộ đang chạy trên máy dev LAN |
| Radar biên độ thở thô | Chưa implement — `resp_amplitude` luôn trả 0 |
| Radar đa người | Chưa có — đang dùng LD2410C thay vì LD2510B đã chốt trong spec |
| Đêm đo dài hạn | Phần mềm đã sẵn sàng (chống mất mẫu, độ bền ghi DB), nhưng đêm đo 8 tiếng thật chưa chạy được — đang chờ cắm board |
| Cơ khí (Phase 04) | Chưa có CAD, firmware handler, hay actuator nào trong repo |

