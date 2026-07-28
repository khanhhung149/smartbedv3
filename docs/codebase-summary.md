# Codebase Summary

> Cập nhật: **2026-07-24**. Phản ánh kiến trúc hiện tại: radar-node native UART, **fusion + IR tại
> voice-node** (ESP32 là bộ não), backend chỉ hiển thị + lưu lịch sử, **app Flutter Android**, vỏ hộp 3D.

## Project Structure

```
project-root/
├── backend/      # Go: MQTT + state machine + REST/WS + voice endpoint + SQLite lịch sử
├── asr/          # Python FastAPI + faster-whisper (self-host ASR)
├── app/          # Flutter Android: Home/History/Analytics/Thiết bị/Settings
├── firmware/     # PlatformIO ESP32: radar-node, voice-node (+ room-node, door-node nghỉ hưu), mqtt/
├── hardware/     # Vỏ hộp in 3D: OpenSCAD + STL
├── scripts/      # wsl-portproxy.ps1 (chỉ cần khi broker chạy trong WSL)
├── docs/         # Tài liệu kỹ thuật
├── plans/        # Log pha + quyết định
├── README.md
└── .gitignore
```

## Backend (Go)

**Location**: `backend/` · Chi router + paho MQTT + coder/websocket + slog · Module `github.com/hung/home-backend`
**Status**: ✅ chạy thật (presence/motion/ac_cmd + lịch sử + voice E2E).

```
backend/
├── cmd/server/main.go            # bootstrap: config, MQTT, store, router, HTTP
├── internal/
│   ├── api/
│   │   ├── router.go             # Chi; group /api: state, events, ac, ws, voice/stream
│   │   ├── handlers.go           # REST: /healthz, /api/state, /api/events, /api/ac, /api/ac/learn
│   │   ├── ws.go                 # WS hub broadcast state (đăng ký tại /api/ws)
│   │   └── *_test.go
│   ├── config/config.go          # env: MQTT_*, HTTP_*, timing, LoadVoice() (ASR_*), DB_PATH
│   ├── events/events.go          # payload MQTT (Motion, Presence)
│   ├── mqttclient/client.go      # paho wrapper: sub presence/motion/ac_cmd, PublishACCmd/ACLearn
│   ├── statemachine/machine.go   # occupied (CHỈ để hiển thị — không phát lệnh)
│   ├── store/store.go            # SQLite lịch sử event (modernc.org/sqlite, pure Go)
│   └── voice/                    # stream.go (WS→WAV), asr_client.go, command.go (ParseVietCommand)
├── Dockerfile · docker-compose.yml (backend + asr) · .env.example
```

**Điểm quan trọng:** `main.go` **KHÔNG publish `ac_cmd`** theo occupancy nữa — ESP32 (voice-node) tự quyết.
Backend chỉ chuyển tiếp lệnh **tay** (`POST /api/ac`) và **voice** (whisper → `ParseVietCommand` → `ac_cmd`),
đồng thời nuôi state cho app + ghi lịch sử. Tránh 2 nơi cùng quyết định thì lệch nhau.

### API
| Method | Path | Status |
|--------|------|--------|
| GET | `/healthz` | ✅ |
| GET | `/api/state` | ✅ |
| GET | `/api/events?limit=&before=` | ✅ (503 nếu không có DB) |
| POST | `/api/ac` | ✅ |
| POST | `/api/ac/learn` | ⚠️ legacy — voice-node không dùng IR learn (Daikin protocol sẵn) |
| GET | `/api/ws` | ✅ (**phải** `/api/ws`, không phải `/ws`) |
| GET | `/api/voice/stream` | ✅ E2E chạy |

### Config env
`MQTT_HOST/PORT/USER/PASS`, `HTTP_ADDR` (`:8080`), `ENTER_WINDOW_S` (15), `EXIT_TIMEOUT_S` (60),
`ASR_URL`, `ASR_SILENCE_MS`, `ASR_MAX_UTTER_MS`, `VOICE_SAMPLE_RATE` (16000), `DB_PATH`.

---

## App (Flutter / Android)

**Location**: `app/` · Riverpod + mqtt_client + SharedPreferences. **Status**: ✅ APK build ra Desktop.

```
app/lib/
├── main.dart · theme.dart · providers.dart      # Riverpod wiring
├── models/    device.dart (MqttDevice) · event.dart · snapshot.dart · stats.dart
├── screens/   home_screen · history_screen · analytics_screen
│              devices_screen · add_device_screen · mqtt_log_screen · settings_screen
├── services/  api_client.dart (REST) · ws_client.dart (/api/ws) · mqtt_service.dart
└── widgets/   pill_nav.dart
```

**Hai đường dữ liệu song song:**
1. **Backend** (REST + WS `/api/ws`) → Home (occupancy/AC), History (`/api/events`), Analytics.
2. **MQTT trực tiếp** (`mqtt_service.dart`) → tab **"Thiết bị"**: đọc `tele/<T>/SENSOR` hiện số liệu radar
   (Detect/Moving/Static). Khuôn topic kiểu `tele/stat` giữ nguyên để không phải đổi app.

**Độ tươi (staleness) ở tab "Thiết bị"** — `DeviceState.staleAfter = 15s`:
- `DeviceState.viewAt(now)` (`models/device.dart`): quá 15s không có message ⇒ `online=false`,
  `occupied=null`, bỏ luôn cự ly/năng lượng cũ. Dựng object mới chứ không `copyWith` (copyWith cố ý giữ
  giá trị cũ khi tham số null nên không xoá được gì).
- `MqttService._startFreshnessTick()`: phát lại state **mỗi giây** kể cả khi không có message — thiếu nó
  thì thiết bị chết ⇒ stream im ⇒ UI đứng nguyên ở "Có người".
- `LWT Offline` ⇒ xoá số đọc ngay (không chờ 15s). radar-node không đi đường này vì will đã dành cho
  `home/room/presence`.

> Đã purge tên "Tasmota" khỏi app (`TasmotaDevice`→`MqttDevice`) nhưng **giữ nguyên topic + logic parse +
> key SharedPreferences `devices`** — chỉ đổi tên/chữ, không đổi hành vi.

---

## ASR service (Python)

**Location**: `asr/` — `app.py` (FastAPI + `WhisperModel(small, cpu, int8)`, `POST /transcribe` multipart WAV,
`GET /healthz`), `requirements.txt`, `Dockerfile`. Chạy cạnh backend qua docker-compose. Audio không rời LAN.

---

## Firmware (PlatformIO)

```
firmware/
├── radar-node/    # ⭐ ĐANG CHẠY trên S2 Mini — LD2410C native UART → MQTT
│   ├── src/main.cpp · src/selftest.cpp (chẩn đoán UART, throwaway)
│   └── platformio.ini  # env: lolin_s2_mini · lolin_s2_mini_ota · selftest
├── voice-node/    # ⭐ ĐANG CHẠY trên WROOM-32 — mic + fusion + IR Daikin
│   └── platformio.ini  # env: esp32dev · esp32dev_ota
├── room-node/     # ⚠️ NGHỈ HƯU (bản S2 cũ: ESP-NOW/IR-learn) — không flash
├── door-node/     # ⚠️ NGHỈ HƯU (tham chiếu ISR PIR)
└── mqtt/          # cấu hình Mosquitto (passwd.example)
```

### radar-node — `firmware/radar-node/src/main.cpp`
**Board**: Wemos S2 Mini (`lolin_s2_mini`, `-DARDUINO_USB_CDC_ON_BOOT=1`). **Status**: ✅ chạy thật.

| Thành phần | Chân | Vai trò |
|-----------|------|---------|
| LD2410C OUT | GPIO16 | Presence digital (hold 300ms) |
| LD2410C TX→RX | GPIO33 / GPIO18 | UART @**256000** đọc Moving/Static distance+energy |
| LD2410C VCC/GND | 5V / **GND chung** | ⚠️ Mất GND chung → UART chết dù BLE vẫn chạy |

- Pub: `home/room/presence` (retain, QoS1, heartbeat 30s) · `home/door/motion` (throttle 1s) ·
  `tele/<T>/SENSOR` (3s) · trả lời `cmnd/<T>/STATUS` → `stat/<T>/STATUS10`.
- **MQTT will** = `home/room/presence` `{"present":false}` retain → S2 rớt thì broker tự bắn vắng
  (~15-20s theo keepalive). Đánh đổi: `tele/<T>/LWT` không còn là will (kẹt "Online") → app dựa vào
  staleness 15s ở tab "Thiết bị" (đã làm).
- `build_src_filter` loại `selftest.cpp` khỏi firmware chính (nó có setup/loop riêng).
- Deps: `ncmreynolds/ld2410`, `256dpi/MQTT`. OTA: `ArduinoOTA` (env `lolin_s2_mini_ota`).

### voice-node — `firmware/voice-node/src/main.cpp`
**Board**: ESP32-WROOM-32 (`esp32dev`). **Status**: ✅ chạy thật (mic → VAD → ASR → IR; IR vào COOL).

| Thành phần | Chân | Vai trò |
|-----------|------|---------|
| INMP441 SCK/WS/SD | GPIO26 / 25 / 34 | I2S mic (L/R→GND) |
| IR blaster | **GPIO4** (module 5V) | `IRDaikin152` — GPIO5 là strapping, không dùng |
| PIR | (GPIO27, **đã bỏ**) | Không còn gắn interrupt |

- **Fusion tại board**: sub `home/room/presence` → `ENTER_STABLE_MS`=800 bật / `EXIT_TIMEOUT_MS`=60000 tắt /
  `RADAR_LINK_TIMEOUT_MS`=90000 (radar chết → coi vắng, chống AC chạy mãi).
- Sub `home/room/ac_cmd` (lệnh tay/voice) → `sendAC()`.
- Audio: I2S 16kHz slot 32-bit → PCM16 với `MIC_SHIFT=11`; VAD `RMS > 2500`; im `SILENCE_MS`=800 → ngừng gửi.
- `build_flags` chỉ biên dịch Daikin (`-D_IR_ENABLE_DEFAULT_=false`, `SEND_DAIKIN/DAIKIN152=true`) — bỏ
  hàng trăm protocol không dùng (board đã ~75% flash).
- Deps: `links2004/WebSockets`, `256dpi/MQTT`, `crankyoldgit/IRremoteESP8266`. OTA: env `esp32dev_ota`.

### Secrets
Mỗi node: `include/config.h.example` (check-in) + `include/config.h` (**gitignore** — WiFi/MQTT/OTA password thật).

---

## Hardware (vỏ hộp in 3D)

**Location**: `hardware/` · OpenSCAD → STL → Bambu Studio. **Vật liệu: PETG, thành 3mm** (máy Bambu A1 hở,
không in PC-ABS/ASA).

```
hardware/
├── vo-hop-modular.scad          # ⭐ HIỆN TẠI (v3) — part="base"|"face"|"lid"|"assembly"|"exploded"|"layout"
├── vo-hop-{base,face,lid}.stl   # 3 mảnh IN RỜI
├── vo-hop-tach-roi.png          # ảnh tách rời + lát cắt rãnh trượt (render bằng OpenSCAD)
├── vo-hop-LAP-RAP-xem-thoi.stl  # bản đã lắp — CHỈ ĐỂ XEM, không in
└── vo-so.scad + vo-so-*.stl     # ⚠️ bản vỏ sò cũ, giữ làm đường lui
```

| Mảnh | Chứa | Ghép bằng |
|---|---|---|
| `base` | WROOM (4 trụ-socket 13mm xỏ pin, 25.4×45.72, lỗ Ø1.4) · S2 (2 trụ vít M2, pitch 18.5) · IR (2 gờ) · khe USB-C S2 ở vách sau (nguồn) · 4 trụ góc Ø8 · rãnh trượt face | — |
| `face` | Khe USB-C WROOM + lỗ LED IR Ø6.5 | **KHÔNG vít** — thả từ trên vào rãnh, nắp đè giữ |
| `lid` | Cửa sổ radar (chừa **1.5mm** cho 24GHz) + cradle radar ngửa + vòng đỡ mic Ø10 + lỗ thu âm | 4 vít M3 vào **ren đồng ép nhiệt** (lỗ chờ Ø4.2) |

**Vì sao face không vít**: trụ in đứng ⇒ đường lớp nằm ngang ⇒ vít bắt ngang là lực **tách lớp**, hướng
yếu nhất của FDM. Rãnh trượt đổi toàn bộ tải sang lực cắt dọc theo lớp.

**Kiểm trước khi in**: `scripts/check-enclosure-fit.sh` lấy phép giao khối (CGAL) từng cặp mảnh rồi tính
**thể tích** khối giao. Đếm số mặt KHÔNG đủ — hai mảnh chạm nhau vẫn sinh cả trăm mặt mà thể tích bằng 0.
Bản v2 từng lọt qua mắt thường với `base∩face` 1945mm³ và `base∩lid` 264mm³, tức **cả 3 mảnh đều không
lắp được**. Chạy script này trước mỗi lần in.

⏳ **Chưa in ướm** — chiều cao cổng USB/tâm LED IR còn là giả định.

---

## Shared Patterns

| Mục | Quy ước |
|-----|---------|
| Định danh code | English (camelCase hàm, SCREAMING_SNAKE_CASE hằng) |
| Comment/log | Tiếng Việt (firmware, app), English/Việt (Go) |
| Go test | table-driven, tên scenario |
| Firmware | không unit test; verify qua serial + **sub broker thật** |
| Flutter | Riverpod provider; model immutable + `copyWith` |

**Không lib firmware chung**: mỗi node standalone (flash/debug độc lập).

**Bài học verify:** test tự động từng để lọt 3 bug — chỉ lộ khi **nhìn app/thiết bị thật**. Với firmware/IR,
bằng chứng phải là **serial + payload trên broker + phản ứng của thiết bị**, không phải test pass.

**Test chạy hạ tầng thật** (tự skip khi hạ tầng không có, không làm đỏ suite):

| File | Cần gì | Bắt được gì |
|------|--------|-------------|
| `app/test/api_live_test.dart` | backend ở `localhost:8080` | lệch contract JSON app↔Go |
| `app/test/mqtt_live_test.dart` | broker + `MQTT_HOST/MQTT_USER/MQTT_PASS` | độ tươi tab Thiết bị trên **thời gian thật**: đóng vai radar rồi im, đo lúc lật "Mất tín hiệu" và đếm nhịp phát lại |

```bash
MQTT_HOST=127.0.0.1 MQTT_USER=... MQTT_PASS=... flutter test
```

Credential lấy từ biến môi trường — **không viết vào repo**. Test MQTT live là thứ duy nhất bắt được lỗi
"logic độ tươi đúng nhưng stream không phát lại": timer chỉ sai khi chạy trên đồng hồ thật.

---

## Next Steps

Xem [`project-roadmap.md`](./project-roadmap.md). Việc gần nhất:
1. **In ướm `vo-hop-base.stl`** rồi chỉnh chiều cao khe USB / lỗ IR nếu lệch.
2. Đấu nguồn chung Topo A (S2 5V+GND → WROOM VIN) — việc tay.
