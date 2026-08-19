# ESP32 Home Presence Detection + Auto AC + Voice

Hệ IoT phân tán: phát hiện hiện diện bằng **radar 24GHz (LD2410C)**, **ESP32 tự quyết bật/tắt điều hòa qua
IR Daikin**, **ra lệnh giọng nói tiếng Việt** qua ASR self-host, và **app Android** giám sát/điều khiển.

**Status** (2026-08-10): ✅ **E2E CHẠY THẬT** — radar → presence → fusion tại board → **IR Daikin vào COOL**;
voice (mic → whisper → `ac_cmd`) chạy; backend + lịch sử SQLite + app Android xong; OTA cả 2 node.
🔬 In-progress: custom Vietnamese wakeword ("Vừng ơi") training + edge inference on voice-node (ESP32-S3, 5.4ms latency, model not yet wired into main.cpp).
⏳ Còn: in ướm vỏ hộp 3D.

## Kiến trúc

```
radar-node (S2 Mini) ─ home/room/presence (retain) ─┬─→ Mosquitto ─→ Go backend ─ REST/WS ─→ App
  LD2410C native UART  home/door/motion ────────────┤                 (CHỈ hiển thị      Android
                       tele/<T>/SENSOR ─────────────┼──────────────→   + lịch sử SQLite)
                                                    │
voice-node (S3-DevKit N16R8) ─ SUB presence ─→ fusion tại BOARD ─→ IR Daikin152 (GPIO8) ─→ Điều hòa
  INMP441 mic ─ WebSocket audio ────────→ /api/voice/stream ─→ asr (whisper) ─→ ac_cmd
  (wakeword "Vừng ơi" on-device: microWakeWord + esp-nn, benchmark 5.4ms, integration pending)
```

**ESP32 là bộ não duy nhất**: voice-node nghe presence rồi tự quyết AC. Backend **không** tự phát `ac_cmd`
theo occupancy (2 nơi cùng quyết thì lệch nhau) — chỉ chuyển tiếp lệnh **tay/voice**.

Chi tiết: [`docs/system-architecture.md`](./docs/system-architecture.md).

## Directory Map

| Thư mục | Nội dung |
|---------|----------|
| `backend/` | Go: MQTT + state machine + REST/WS + `internal/voice/` + `internal/store/` (SQLite lịch sử) |
| `asr/` | Python FastAPI + faster-whisper (ASR self-host) |
| `app/` | Flutter Android: Home / History / Analytics / Thiết bị / Settings |
| `firmware/` | PlatformIO: **`radar-node`** (ESP-IDF thuần) + **`voice-node`** (arduino+espidf); `mqtt/` |
| `hardware/` | Vỏ hộp in 3D: OpenSCAD + STL (`vo-hop-modular.scad`) |
| `scripts/` | `wsl-portproxy.ps1` (chỉ cần khi broker chạy trong WSL) |
| `docs/` | Tài liệu kỹ thuật |
| `plans/` | Log pha + quyết định |

## Documentation

| Doc | Cho | Nội dung |
|-----|-----|----------|
| [`docs/project-overview-pdr.md`](./docs/project-overview-pdr.md) | Product | Vấn đề, scope, quyết định, metrics |
| [`docs/system-architecture.md`](./docs/system-architecture.md) | Designer | Sơ đồ, MQTT/voice contract, fusion tại board, API |
| [`docs/codebase-summary.md`](./docs/codebase-summary.md) | Dev mới | Cấu trúc code, module, file thật |
| [`docs/code-standards.md`](./docs/code-standards.md) | Contributor | Quy ước đặt tên, pattern, test |
| [`docs/project-roadmap.md`](./docs/project-roadmap.md) | PM | Trạng thái pha, việc còn treo |
| [`docs/system-wiring.md`](./docs/system-wiring.md) | Phần cứng | Pinout, đấu nối, cảnh báo điện |

## Setup

### Backend + ASR
```bash
cd backend
docker compose up            # backend (:8080) + asr (faster-whisper)
curl http://localhost:8080/healthz
```
Config qua env (`.env.example`: `MQTT_*`, `ASR_URL`, timing, `DB_PATH`).

### Broker
Mô hình A: **Docker Desktop publish port ra Windows host** (broker LAN `192.168.1.120:1883`, auth) — không
cần portproxy. Nếu chạy broker trong WSL thì IP đổi mỗi restart → dùng `scripts/wsl-portproxy.ps1`.

### Firmware
```bash
# Lần đầu (USB)
cd firmware/radar-node && pio run -e lolin_s2_mini -t upload   # S2: giữ nút 0, tap RST, thả 0
cd firmware/voice-node && pio run -e esp32s3_kws   -t upload

# Sau đó nạp qua WiFi (OTA) — khỏi tháo dây nguồn
export OTA_PASSWORD='...'
cd firmware/radar-node && pio run -e lolin_s2_mini_ota -t upload
cd firmware/voice-node && pio run -e esp32s3_kws_ota   -t upload
```
Secrets: copy `include/config.h.example` → `config.h`, điền WiFi/MQTT/OTA password.

Hai node ghim **cùng** platform pioarduino 55.03.311 (ESP-IDF 5.5.5) cho khỏi lệch toolchain, nhưng
khác framework: radar-node là **ESP-IDF thuần** (không thư viện Arduino nào), voice-node là
`arduino, espidf` vì cần WebSockets + IRremoteESP8266. Hệ quả: OTA của radar-node không phải espota
mà là POST `firmware.bin` qua `curl` tới endpoint HTTP trên board (`upload_command` trong
`platformio.ini`) — cần có `curl`. `curl http://radar-node.local/` trả về bản đang chạy.

> WSL: nạp qua `usbipd attach --wsl --auto-attach --busid <id>`. S2 native-USB CDC **đổi cổng khi reset**
> (`ttyACM0`→`ttyACM1`) → cần `--auto-attach`; lần upload đầu hay fail, chạy lại là được.
> `pio device monitor` **không chạy** trong shell non-interactive (`termios: Inappropriate ioctl`) → dùng pyserial.

### App (Flutter Android)
```bash
cd app && flutter build apk --release
```

## MQTT Topics

| Topic | Hướng | Retain | Nội dung |
|-------|-------|--------|----------|
| `home/room/presence` | radar-node → backend **+ voice-node** | ✅ | presence theo radar (heartbeat 30s). **Nguồn presence duy nhất** |
| `home/room/presence` (will) | broker khi radar-node rớt | ✅ | `{"present":false}` — hết kẹt "thấy người" khi S2 mất điện |
| `home/door/motion` | radar-node → backend | — | event cử động (throttle 1s) → Analytics |
| `home/room/sample` | radar-node → backend | — | **mẫu 10Hz Phase 01** — schema CSV take-home (`t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity`) + kênh raw radar (moving/still distance+energy) + cờ `uart_ok`. `t` epoch ms gắn tại MCU; radar không đo được kênh nào thì ghi 0. Vào bảng SQLite `samples`, giữ 30 đêm |
| `tele/<T>/SENSOR` | radar-node → app | — | số liệu radar Detect/Moving/Static (3s). App coi **quá 15s không có = mất tín hiệu** (`tele/<T>/LWT` kẹt "Online" nên không tin được) |
| `home/room/ac_cmd` | backend/app → voice-node | — | AC on/off **tay/voice** (không phải auto) |

Xem live: `docker exec -it home-mqtt mosquitto_sub -u homeuser -P homepass123 -t '#' -v`

## API

```bash
curl http://localhost:8080/api/state
curl 'http://localhost:8080/api/events?limit=50'
curl 'http://localhost:8080/api/samples?from_ms=1753000000000&to_ms=1753001000000'   # mẫu 10Hz (cửa sổ ≤ 48h)
curl -X POST http://localhost:8080/api/ac -H 'Content-Type: application/json' -d '{"cmd":"on"}'
# WebSocket state:  ws://localhost:8080/api/ws        (PHẢI /api/ws, không phải /ws)
# WebSocket audio:  ws://localhost:8080/api/voice/stream  (PCM 16k mono 16-bit LE)
# Dashboard local:  http://localhost:8080/dashboard/   (realtime + xem lại một đêm)
```

## Testing
```bash
cd backend && go test ./...                            # state machine + parse lệnh voice + store
cd firmware/radar-node && pio run -e lolin_s2_mini     # compile check
cd app && flutter analyze
```

> **Bài học:** test tự động từng để lọt 3 bug — chỉ lộ khi nhìn **app/thiết bị thật**. Với firmware/IR,
> bằng chứng là **serial + payload trên broker + phản ứng thiết bị**, không phải test pass.

## Còn treo

| Việc | Ảnh hưởng | Trạng thái |
|------|-----------|-----------|
| Wakeword integration (main.cpp loop + MFCC feature parity) | Kích hoạt voice chỉ khi nghe "Vừng ơi", giảm latency từ backend | 🔬 model trained, inference verified (5.4ms), feature extraction parity validation pending |
| In ướm vỏ hộp `hardware/vo-hop-base.stl` | Chiều cao khe USB / lỗ LED IR còn là giả định | ⏳ in thử rồi chỉnh |
| Đấu nguồn chung Topo A + (board WROOM cũ) tụ 470-1000µF | 1 cốc sạc nuôi 2 board | ⏳ việc tay |

## Gotcha phần cứng (đã trả giá)

- **LD2410 cần GND chung** với board đọc nó — mất GND chung thì UART chết (Moving=0) dù BLE vẫn mượt.
- **LED IR vô hình với mắt** — kiểm bằng camera điện thoại (thấy nháy tím). Module IR chạy **5V** (3V3 bị
  under-drive, tầm ngắn).
- **IR Daikin**: remote **ARC480A47 = họ DAIKIN152** → `IRDaikin152`. Không cần học mã/TSOP.
- **WROOM brownout tại `WiFi.mode()`**: biên nguồn 5V mỏng (diode nối tiếp → 4.7V). Firmware **không** phải
  nguyên nhân (đã chứng minh bằng swap board). Fix: tụ 470-1000µF hoặc board khác.
- **Đừng hàn radar đè cổng USB-C** của S2 (gây chập/nóng).

## Security (MVP / LAN-only)
🔒 MQTT auth (no TLS) · REST/WS no auth (LAN) · **audio không rời LAN** (ASR self-host) · OTA có password.
⚠️ Trước internet: TLS/mTLS MQTT, auth API, siết CORS, rate-limit.

## Roadmap

| Phase | Trạng thái |
|-------|-----------|
| 1: Presence (radar-node native UART → MQTT) | ✅ chạy thật |
| 2: Go backend + voice endpoint + ASR + SQLite lịch sử | ✅ chạy thật |
| 3: voice-node (mic + fusion tại board + IR Daikin) | ✅ chạy thật, **AC vào COOL** |
| 4: Flutter app Android | ✅ APK chạy, tab Thiết bị có staleness 15s |
| 5: OTA 2 node | ✅ |
| 6: Vỏ hộp in 3D modular | ⏳ STL xong, chưa in ướm |

Chi tiết: [`docs/project-roadmap.md`](./docs/project-roadmap.md).

---
**Last updated**: 2026-08-10
