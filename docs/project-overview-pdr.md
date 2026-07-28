# Project Overview & PDR

> Cập nhật: **2026-07-24**. MVP chạy thật đầy đủ (radar → IR Daikin COOL + voice + app).

## Project Name
**ESP32 Home Presence Detection + Automatic AC Control + Voice**

## Problem Statement

Điều khiển điều hòa thủ công gây lãng phí: quên tắt khi rời phòng, chạy AC ở phòng trống tốn điện, không có phát hiện hiện diện đủ tin cậy để tự động hoá.

## Solution

Hệ phân tán qua MQTT:
1. Phát hiện hiện diện bằng **radar 24GHz LD2410C** (giữ presence cả khi ngồi yên — PIR đã bỏ vì tắt khi
   không cử động, và con PIR cũ chết do cắm ngược).
2. Tự bật/tắt điều hòa theo occupancy — **quyết định tại ESP32**, phát IR bằng protocol Daikin có sẵn.
3. **Ra lệnh bằng giọng nói tiếng Việt** ("bật/tắt điều hòa") → ASR self-host → điều khiển AC.
4. REST/WebSocket + **app Android** giám sát + điều khiển tay + lịch sử.

## Scope

### 2 node vật lý (MVP 1 phòng)
- **radar-node** (Wemos S2 Mini): LD2410C **native UART** (OUT G16, TX G33, RX G18) → `home/room/presence`
  (retain) + `home/door/motion` + `tele/<T>/SENSOR` cho app.
- **voice-node** (ESP32-WROOM-32): INMP441 I2S mic → VAD → stream audio; **subscribe presence → fusion tại
  board → IR Daikin (GPIO4, module 5V)**.
- **Fusion tại BOARD** (không ở backend): ESP32 là bộ não duy nhất, backend sập AC vẫn chạy đúng.

### Backend + ASR
- **Go backend**: nhận presence/motion/ac_cmd → state machine (**chỉ để hiển thị**), REST/WS, **lịch sử
  SQLite** (`/api/events`), **endpoint voice `/api/voice/stream`**. KHÔNG tự publish `ac_cmd`.
- **ASR** (`asr/`): faster-whisper self-host (`small`, cpu, int8) — audio không rời LAN.

### App
- **Flutter Android**: Home (occupancy/AC realtime qua WS) · History (`/api/events`) · Analytics ·
  **Thiết bị** (đọc MQTT trực tiếp, hiện số liệu radar) · Settings.

### Broker
- Mosquitto (auth, no TLS, LAN-only), Docker Desktop publish ra host (Mô hình A).

### Ngoài scope
- **iOS** (cần macOS+Xcode). Multi-room. TLS/auth API (LAN-only MVP).

## Key Product Decisions

| Quyết định | Lý do | Trạng thái |
|-----------|-------|-----------|
| **Fusion TẠI BOARD** (voice-node nghe presence → tự bắn IR) | Nếu cả backend lẫn board cùng quyết thì lệch nhau, không biết tin bên nào → **ESP32 là bộ não duy nhất**; backend sập AC vẫn đúng | ✅ Chốt 23/07 (đảo lại từ "ở backend") |
| **BỎ PIR khỏi hệ** | PIR tắt khi ngồi yên (thoát nhầm), con cũ chết do cắm ngược. Radar giữ presence cả khi tĩnh → đủ | ✅ Chốt |
| **IR Daikin bằng protocol có sẵn** (`IRDaikin152`, không học mã/TSOP) | Remote ARC480A47 thuộc họ DAIKIN152 → dùng thẳng library, khỏi phần cứng thu IR. Mặc định COOL 25°C quạt AUTO | ✅ Chạy thật 24/07 |
| **radar-node đọc LD2410C native UART** (thay ESP-NOW / firmware bên thứ ba) | Lấy được Moving/Static distance+energy thật cho app; 1 board tự nối WiFi+MQTT, ít mắt xích | ✅ Chốt 23/07 |
| **2 node** (S2 presence / WROOM voice+IR) thay all-in-one | Radar đã hàn sẵn S2 Mini; mic ngốn CPU → WROOM 2 nhân; presence nhẹ → S2 1 nhân đủ | ✅ Chốt |
| **ASR = faster-whisper self-host** (không cloud) | Miễn phí, audio ở LAN (riêng tư), tiếng Việt tốt | ✅ Chốt, backend xong |
| **VAD năng lượng trên device** (không wake-word/nút bấm) | Đơn giản cho MVP; chỉ stream khi có tiếng | ✅ Chốt |
| **Audio qua WebSocket** (không MQTT) | MQTT không hợp stream audio | ✅ Chốt |
| **MQTT làm transport** cho presence/AC | Decouple firmware↔backend, chuẩn IoT | ✅ Chốt |
| **Lịch sử event SQLite ở backend** (`modernc.org/sqlite`, pure Go) | App cần History + Analytics; state in-memory mất khi restart. Pure-Go driver để không cần CGO trong Docker | ✅ Chạy thật |
| **App Android trước, iOS sau** | iOS cần macOS+Xcode+Apple Dev; user chấp nhận chờ | ✅ APK chạy |
| **LAN-only, no TLS** | MVP; thêm TLS trước khi lộ internet | Ràng buộc ghi nhận |

## Architecture (tóm tắt)

```
[radar-node]  ── home/room/presence (retain) ──┬─ MQTT ─ Go backend (hiển thị + SQLite) ─ REST/WS ─ App
  LD2410C UART   home/door/motion ─────────────┤
                 tele/<T>/SENSOR ──────────────┼──────────────────────────────────────────────────→ App
[voice-node]  ── SUB presence → FUSION tại board → IR Daikin152 (GPIO4) → điều hòa COOL 25°C
  INMP441 mic ── WebSocket audio → /api/voice/stream → asr (whisper) → ac_cmd → voice-node
```

Chi tiết contract: [`system-architecture.md`](./system-architecture.md).

## Non-Goals (deferred / out of scope)
- Cloud connectivity (MVP LAN-only)
- Multi-room / multi-AC (single room MVP)
- **iOS app** (cần macOS + Xcode + Apple Dev)
- Wake-word offline (dùng VAD; wake-word là mở rộng sau)
- PIR (đã bỏ — radar đủ)

## Open Questions

1. **Vỏ hộp**: chiều cao thật của cổng USB-C (WROOM/S2) và tâm LED IR — phải in ướm mới chốt được.
2. **Đấu nguồn chung Topo A**: hàn 2 dây S2→WROOM VIN (việc tay).
3. **Ngưỡng staleness 15s** đã chốt theo lý thuyết (SENSOR 3s + poll 2s ⇒ lỡ ~5 nhịp); nếu WiFi nhà hay
   chớp làm tab nháy "Mất tín hiệu" thì nới lên 20-30s.

## Hardware Manifest

Pin chi tiết: [`system-wiring.md`](./system-wiring.md).
- **radar-node**: Wemos S2 Mini + HLK-LD2410C (OUT G16 + UART 33/18, VCC 5V, **GND chung**).
- **voice-node**: ESP32-WROOM-32 + INMP441 (I2S 26/25/34) + module IR Transmitter **5V** (DAT→GPIO4).
- **Remote AC tham chiếu**: Daikin **ARC480A47** → protocol DAIKIN152.
- **Broker/Backend/ASR**: Windows host + Docker Desktop (broker LAN 192.168.1.120).
- **Vỏ hộp**: in 3D PETG, Bambu Lab A1, 3 mảnh modular (`hardware/vo-hop-modular.scad`).

## Success Metrics

- ✅ Firmware radar-node & voice-node compile + **chạy thật**
- ✅ radar → `presence`/`motion`/`SENSOR` tới broker, timestamp khớp
- ✅ Backend compile + test xanh; lịch sử SQLite sống qua restart; `/api/events` phân trang
- ✅ **E2E voice**: "bật điều hòa" → whisper → `ac_cmd` → `[ir] Daikin ON`
- ✅ **E2E AC**: điều hòa **vào COOL 25°C** thật bằng IR
- ✅ App Android: Home realtime qua WS, History, Analytics, Thiết bị (radar qua MQTT)
- ✅ OTA cả 2 node (nạp qua WiFi)
- ✅ Rút nguồn S2 → will `present:false` → Home hết "Có người"
- ✅ Tab "Thiết bị" tự chuyển "Mất tín hiệu" sau 15s im lặng — đo trên broker thật: **15.1s** (⏳ còn lại: nhìn bằng mắt trên điện thoại)
- ⏳ In ướm vỏ hộp

## Development Notes
- **Ngôn ngữ**: định danh English; comment/log firmware tiếng Việt (chủ ý — xem [`code-standards.md`](./code-standards.md)).
- **Test**: Go state machine + parse lệnh voice + store pass. Firmware verify qua **serial + payload broker
  thật + phản ứng thiết bị** — test tự động từng để lọt 3 bug chỉ lộ khi nhìn app/thiết bị thật.
- **Persistence**: state machine in-memory; **lịch sử event có SQLite** (`internal/store`, pure-Go driver).
