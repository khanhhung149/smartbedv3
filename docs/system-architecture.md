# System Architecture

> Cập nhật: **2026-07-24 (rev3)**. Kiến trúc hiện tại: **2 node WiFi độc lập**; **radar-node cấp presence
> duy nhất**, **voice-node là BỘ NÃO AC** (nghe presence → tự bắn IR Daikin); **backend CHỈ hiển thị + lưu
> lịch sử + chuyển tiếp lệnh tay/voice**, không tự quyết AC. PIR đã bỏ khỏi hệ. IR learn/NVS bỏ (dùng
> protocol Daikin có sẵn). Rev2 (16/07) từng fuse ở backend + dùng PIR — đã thay.

## High-Level Overview

Bốn lớp:

1. **Sensor Tier** (Firmware):
   - **radar-node** (Wemos S2 Mini): LD2410C đọc **native UART** → `home/room/presence` + `home/door/motion`
     + `tele/<T>/SENSOR` (số liệu radar cho app).
   - **voice-node** (ESP32-S3-CAM N16R8): INMP441 I2S mic → VAD → stream audio; **subscribe presence → fusion
     tại board → bắn IR Daikin** (GPIO8).
2. **Broker Tier** (MQTT): Mosquitto (auth, no TLS, LAN-only).
3. **Logic Tier** (Go backend): nhận presence/motion/ac_cmd → state machine nuôi `/api/state` + `/api/ws`,
   **lưu lịch sử SQLite** (`/api/events`), endpoint voice WebSocket → ASR → `ac_cmd`. **KHÔNG tự bắn ac_cmd.**
4. **ASR Tier** (Python `asr/`): faster-whisper self-host (audio không rời LAN).

> **Fusion ở BOARD** (đảo lại so với rev2): voice-node nghe `home/room/presence` rồi tự quyết bật/tắt AC.
> Lý do: nếu cả backend lẫn board cùng quyết thì chúng lệch nhau, không biết tin bên nào → chốt **ESP32 là
> bộ não duy nhất**. Backend sập thì AC vẫn chạy đúng.

```
┌─ radar-node — S2 Mini ───────────────────┐   ┌─ voice-node — ESP32-S3-CAM ───────┐
│  LD2410C: OUT G16 · UART TX33/RX18       │   │  INMP441 I2S (SCK5/WS6/SD7)       │
│  @256000 · presence hold 300ms           │   │  VAD năng lượng tại board         │
│  pub home/room/presence (retain,QoS1)    │   │  stream PCM 16k mono → WS backend │
│  pub home/door/motion (event)            │   │  SUB home/room/presence           │
│  pub tele/<T>/SENSOR (3s, cho app)       │   │  → fusion → IR Daikin152 (GPIO4)  │
│  WILL: presence {"present":false}        │   │  SUB home/room/ac_cmd (lệnh tay)  │
│  ArduinoOTA                              │   │  ArduinoOTA                       │
└───────────────┬──────────────────────────┘   └────────┬─────────────────┬────────┘
                │ MQTT                          audio WS│          MQTT   │
                ▼                                       ▼                 ▼
   ┌─────────────────────────────┐        ┌────────────────────────────────────┐
   │  Mosquitto broker (:1883)   │◄──────►│  Go backend (:8080)                │
   │  auth, no TLS, LAN          │        │  statemachine → /api/state, /api/ws│
   └─────────────────────────────┘        │  SQLite lịch sử → /api/events      │
                                          │  /api/voice/stream (WS) → WAV      │
                                          │  → ASR → ParseVietCommand → ac_cmd │
                                          └──────────────┬─────────────────────┘
                                                         ▼
                                          ┌──────────────────────────────┐
                                          │ asr/ (faster-whisper, :9000) │
                                          │ model small, cpu, int8       │
                                          └──────────────────────────────┘
                                   Flutter app (Android) → REST /api/* + WS
                                   + đọc MQTT trực tiếp (tab "Thiết bị")
```

> **Node nghỉ hưu:** `firmware/door-node/` (PIR) và `firmware/room-node/` (bản S2 cũ, ESP-NOW/IR-learn) giữ
> làm tham chiếu, **không flash**. Bản đang chạy trên S2 là `firmware/radar-node/`.

---

## MQTT Topic Contract

Payload JSON, timestamp Unix milliseconds (`ts`). `ts=0` = NTP chưa sync.

| Topic | Hướng | QoS | Retain | Payload | Ý nghĩa |
|-------|-------|-----|--------|---------|---------|
| `home/room/presence` | radar-node → Broker → backend **+ voice-node** | 1 | **Yes** | `{"ts":<ms>,"present":bool}` | Presence theo radar (OUT giữ ≥300ms). Retain + heartbeat 30s. **Nguồn presence DUY NHẤT.** |
| `home/room/presence` (**will**) | Broker (khi radar-node rớt) | 1 | Yes | `{"present":false}` | MQTT will: S2 mất điện/WiFi → broker tự bắn `present:false` (~15-20s theo keepalive) → hết kẹt "thấy người". |
| `home/door/motion` | radar-node → backend | 1 | No | `{"ts":<ms>,"motion":true}` | Event cử động (throttle 1s) → backend lưu → app Analytics đếm. |
| `tele/<DEVICE_TOPIC>/SENSOR` | radar-node → app | 0 | No | `{"LD2410":{"Detect":..,"Moving":{..},"Static":{..}}}` | Số liệu radar mỗi 3s cho tab "Thiết bị" của app (đọc MQTT trực tiếp). |
| `cmnd/<T>/STATUS` / `stat/<T>/STATUS10` | app ↔ radar-node | 0 | No | `"10"` / `{"StatusSNS":{...}}` | App poll trạng thái tức thời. |
| `home/room/ac_cmd` | backend/app → voice-node | 1 | No | `{"cmd":"on"\|"off"}` | Lệnh AC **TAY** (REST `/api/ac` hoặc voice ASR). Backend KHÔNG tự phát theo occupancy. |

Audio **không** qua MQTT — voice-node nối WebSocket tới `/api/voice/stream`.

`home/room/ac_learn` **đã bỏ** (Daikin dùng protocol có sẵn trong IRremoteESP8266, không cần học mã).
Endpoint `/api/ac/learn` còn trong code nhưng vô tác dụng với voice-node hiện tại.

---

## Fusion & chính sách AC — tại voice-node (board)

`firmware/voice-node` subscribe `home/room/presence`, tự quyết:

| Tham số | Mặc định | Vai trò |
|---|---|---|
| `ENTER_STABLE_MS` | 800 | presence=true liên tục 0.8s → `occupied` → bắn IR ON |
| `EXIT_TIMEOUT_MS` | 60000 | vắng 60s → `occupied=false` → bắn IR OFF |
| `RADAR_LINK_TIMEOUT_MS` | 90000 | Không nhận presence 90s → coi radar-node chết → coi như VẮNG (chống AC chạy vĩnh viễn) |
| `STATUS_HEARTBEAT_MS` | 2000 | Nhịp log `[hb]` ra Serial |

**radar-node — presence** (`firmware/radar-node`):

| Tham số | Mặc định | Vai trò |
|---|---|---|
| `PRESENCE_HOLD_MS` | 300 | OUT HIGH liên tục bấy lâu → `present=true` |
| `PRESENCE_HEARTBEAT_MS` | 30000 | Republish presence định kỳ (link sống + ghi đè retained cũ) |
| `TELE_PERIOD_MS` | 3000 | Nhịp `tele/<T>/SENSOR` cho app |
| `MOTION_THROTTLE_MS` | 1000 | Chặn flood `home/door/motion` |

**App — tab "Thiết bị"** (`app/lib/models/device.dart`, `app/lib/services/mqtt_service.dart`):

| Tham số | Mặc định | Vai trò |
|---|---|---|
| `DeviceState.staleAfter` | 15000 | Quá bấy lâu không có message ⇒ "Mất tín hiệu": `online=false`, `occupied=null`, bỏ số liệu cũ. Radar đẩy SENSOR 3s + app poll `STATUS 10` 2s ⇒ 15s là lỡ ~5 nhịp |
| nhịp phát lại state | 1000 | Emit lại state mỗi giây dù không có message — không có nó thì thiết bị chết là stream im, UI đứng ở "Có người" |

**Backend statemachine** vẫn tính `occupied` (`EnterWindow`=15s, `ExitTimeout`=60s) nhưng **chỉ để hiển thị**
(`/api/state`, `/api/ws`) và ghi lịch sử — không phát lệnh.

---

## Điều khiển IR — Daikin

**Không học mã, không cần TSOP.** Dùng protocol có sẵn:

- Remote thật: **ARC480A47** → thuộc họ **DAIKIN152** → class `IRDaikin152` (verify trong library:
  `ir_Daikin.h` map ARC480A5/A14 → DAIKIN152).
- Mặc định khi bật: **COOL, 25°C, quạt AUTO** (`AC_DEFAULT_MODE/TEMP/FAN`). Daikin gửi **trọn 35 byte
  trạng thái** mỗi lần → bật là phải set đủ mode/temp/fan, không có "lệnh bật" riêng.
- Chân phát: **GPIO4** (GPIO5 là strapping — không dùng).
- Module IR chạy **5V** (nhãn: 5V, tầm 1–2m, 940nm). Cấp 3V3 bị under-drive → tầm ngắn.
- **LED IR vô hình với mắt** — kiểm bằng cách chĩa camera điện thoại vào LED, thấy nháy tím.

---

## Backend API (REST/WS)

| Method | Path | Mục đích |
|--------|------|----------|
| GET | `/healthz` | Liveness + trạng thái MQTT |
| GET | `/api/state` | Occupancy + AC hiện tại (hiển thị) |
| GET | `/api/events?limit=&before=` | **Lịch sử event** từ SQLite, mới nhất trước (503 nếu không có DB) |
| POST | `/api/ac` | Lệnh AC tay → pub `ac_cmd` |
| POST | `/api/ac/learn` | (legacy, vô tác dụng với voice-node hiện tại) |
| GET | `/api/ws` | WebSocket broadcast state — **phải là `/api/ws`**, không phải `/ws` |
| GET | `/api/voice/stream` | WebSocket audio (PCM 16k mono 16-bit LE) → ASR → `ac_cmd` |

Lịch sử lưu bằng `modernc.org/sqlite` (pure Go, không CGO). Kind: `presence` / `motion` / `ac_cmd`.

---

## Luồng Voice → AC

```
voice-node: mic I2S → RMS > VAD_THRESHOLD(2500) → mở WS → gửi PCM 16k mono LE
            im lặng SILENCE_MS(800) → ngừng gửi (giữ WS mở)
backend /api/voice/stream → utteranceBuffer → WAV → ASR /transcribe
            → text → ParseVietCommand → "on"/"off" → pub home/room/ac_cmd
voice-node nhận ac_cmd → sendAC() → IRDaikin152 → điều hòa vào COOL 25°C
```

`MIC_SHIFT=11` (nâng gain INMP441 ~32x so >>16; RMS nền ~160-1200, tiếng nói ~4800-8000+).

---

## Nạp firmware — OTA

Cả 2 node đã có `ArduinoOTA` (password trong `config.h`, **không commit**). Nạp USB 1 lần để kích hoạt, sau
đó nạp qua WiFi. Partition **không đổi** (default 1.25MB đã có 2 slot OTA).

```bash
export OTA_PASSWORD='...'
cd firmware/radar-node && pio run -e lolin_s2_mini_ota -t upload   # S2
cd firmware/voice-node && pio run -e esp32s3           -t upload   # S3 (qua cổng TTL)
```

Giữ env USB (`lolin_s2_mini` / `esp32dev`) làm **đường lui** — bản nào làm chết WiFi thì OTA bó tay.

---

## Nguồn điện (Topo A)

**S2 là board nguồn**: cốc sạc ≥2A → USB-C của **S2**; kéo **5V + GND từ S2 sang chân 5V của S3**.
Chỉ chung 5V+GND, **không chung 3V3**. Không cắm USB của S3 khi dây liên board còn nối (2 nguồn đánh
nhau) → đó là lý do cần OTA.

Bắn IR làm 5V tụt **4.6 → 4.0V** (khung Daikin kéo ~150ms ở ~0.1A ⇒ đường nguồn có cỡ 6Ω nối tiếp).
Chưa gây hỏng: 3.3V vẫn giữ và `esp_reset_reason()` chưa bao giờ ra 9. **Tụ KHÔNG cứu được** tải dài
150ms — cần ~30.000µF; tụ chỉ cứu xung cỡ mili-giây (xem mục brownout WROOM bên dưới).

> Con WROOM cũ brownout tại `WiFi.mode()` do biên nguồn mỏng; **swap sang WROOM mới thì hết** (cùng
> firmware, 0 brownout, chạy trọn mic→VAD→IR). Firmware không phải nguyên nhân — đừng đổ cho TX power/CPU freq.

---

## Config (Environment)

| Biến | Mặc định | Ghi chú |
|------|----------|---------|
| `MQTT_HOST` / `MQTT_PORT` / `MQTT_USER` / `MQTT_PASS` | — / 1883 | Broker |
| `HTTP_ADDR` | `:8080` | Listen |
| `ENTER_WINDOW_S` / `EXIT_TIMEOUT_S` | 15 / 60 | State machine (hiển thị) |
| `ASR_URL` / `ASR_SILENCE_MS` / `ASR_MAX_UTTER_MS` | — / ~800 / — | ASR |
| `VOICE_SAMPLE_RATE` | 16000 | PCM |
| `DB_PATH` | — | SQLite lịch sử event |

Secrets (`config.h`, `.env`, `passwd`, OTA password) đều gitignore.

---

## Deployment

```
Windows host + Docker Desktop (Mô hình A: publish port ra host, KHÔNG portproxy)
├─ Mosquitto (home-mqtt, :1883)          # broker LAN 192.168.1.120
├─ Go backend (:8080)
└─ asr (faster-whisper, :9000 internal)
radar-node (WiFi "mp") ─┐
voice-node (WiFi "mp")  ┴─ tới host qua LAN
Flutter app (Android)   ── REST/WS backend + MQTT trực tiếp
```

> Nếu chạy broker trong WSL thì IP WSL đổi mỗi lần restart → ESP32 mất broker; Win10 không hỗ trợ mirrored
> networking, phải dùng `scripts/wsl-portproxy.ps1`. **Mô hình A (Docker Desktop) tránh hẳn vấn đề này.**

---

## Security (MVP / LAN-only)

| Mục | Trạng thái |
|-----|-----------|
| MQTT TLS | ❌ (LAN-only) |
| MQTT auth | ✅ user/pass |
| REST/WS auth | ❌ (giả định LAN) |
| Audio ra ngoài | ✅ Không — ASR self-host |
| OTA password | ✅ có trên cả 2 node (không commit) |

Trước khi lộ internet: TLS/mTLS MQTT, auth API, siết CORS, rate-limit.

---

## Hardware & Wiring

Pinout chi tiết + cảnh báo điện: [`system-wiring.md`](./system-wiring.md). Vỏ hộp: `hardware/`.

- **radar-node**: S2 Mini + LD2410C (OUT G16, TX→G33, RX→G18, VCC 5V, **GND phải chung** — mất GND chung
  thì UART chết dù BLE vẫn chạy).
- **voice-node**: ESP32-S3-CAM N16R8 + INMP441 (**SCK5/WS6/SD7**, L/R→GND, SD có pull-down) + IR blaster
  **GPIO8 (5V)**. Chân I2S buộc đổi vì bản đồ GPIO của S3 khác: 22-25 không tồn tại, 26-32 là bus SPI
  flash, 33-37 bị PSRAM octal chiếm.
- **Vỏ hộp**: `hardware/vo-hop-modular.scad` — xếp lớp modular 3 mảnh (base/face/lid), PETG thành 3mm,
  ghép vít M3 góc. S3 bắt 2 vít **M2.5** (pitch 23, trụ Ø8 cao 10); S2 bắt 2 vít M2 (pitch **20**, trụ Ø7);
  radar + mic ngửa gắn dưới nắp (cửa sổ radar chừa 1.5mm cho 24GHz). Bản vỏ sò cũ `vo-so.scad` giữ làm lui.

---

## Trạng thái nghiệm thu (2026-07-24)

| Hạng mục | Trạng thái |
|----------|-----------|
| radar-node → presence + motion + SENSOR | ✅ chạy thật, verify qua broker |
| Will `present:false` khi S2 rớt | ✅ đã flash + verify broker |
| voice-node: presence → fusion → IR | ✅ E2E chạy (`[fusion] occupied→1` → `[ir] Daikin ON`) |
| Voice: mic → VAD → ASR → ac_cmd → IR | ✅ chạy (RMS max ~28000, VAD trigger, IR fire) |
| **IR Daikin vào COOL** | ✅ **đã vào Cool** (ARC480A47=Daikin152 + module IR 5V + chĩa sát) |
| Backend `/api/events` + SQLite | ✅ |
| App Android (Home/Settings/History/Thiết bị/Analytics) | ✅ APK build ra Desktop |
| OTA 2 node | ✅ có code + env; radar-node đã đồng bộ OTA password |
| WROOM brownout | ⛔ lịch sử — WROOM chết hẳn 29/07, voice-node đã sang ESP32-S3 |
| **App staleness tab "Thiết bị"** | ✅ 15s không message ⇒ "Mất tín hiệu" (`DeviceState.viewAt` + nhịp phát lại 1s). Đo trên broker thật 28/07: lật sau **15.1s**, 13 lần phát trong lúc im lặng (`test/mqtt_live_test.dart`) |
| Vỏ hộp modular | ⏳ v4 (ESP32-S3): đã in ướm khay S3 — chân GPIO chạm sàn ở trụ 8mm nên nâng lên 10. Còn **3 số chưa đo**: pitch 2 cổng USB-C (12.5), pitch 2 lỗ vít (23), tâm lỗ tới mép bo (3). Sai pitch USB thì **face phải in lại** |

---

## Related Docs

- [`project-overview-pdr.md`](./project-overview-pdr.md) — scope & quyết định
- [`codebase-summary.md`](./codebase-summary.md) — cấu trúc code
- [`system-wiring.md`](./system-wiring.md) — đấu nối phần cứng
- [`project-roadmap.md`](./project-roadmap.md) — tiến độ pha
