# System Architecture

> Cập nhật: 2026-07-16 (rev2). Kiến trúc hiện tại: **2 node vật lý**; **PIR ở voice-node, radar ở room-node → fusion tại BACKEND**; voice stream → ASR self-host. (Rev1 từng để fusion tại board — đã đảo theo quyết định dời PIR sang ESP32, xem `plans/260716-1433-relocate-pir-to-voice-node-backend-fusion/`.)

## High-Level Overview

Bốn lớp:

1. **Sensor Tier** (Firmware):
   - **Room node** (Wemos S2 Mini): LD2410 radar → `home/room/presence` (radar-based); IR learn/blast điều khiển điều hòa.
   - **Voice node** (ESP32-WROOM-32): INMP441 I2S mic → VAD → stream audio; **PIR (GPIO27) → `home/door/motion`**.
2. **Broker Tier** (MQTT): Mosquitto (auth, no TLS, LAN-only).
3. **Logic Tier** (Go backend): nhận motion(voice-node)+presence(radar), **fuse → occupied** (state machine), endpoint voice WebSocket, phát `ac_cmd`, REST/WS cho client.
4. **ASR Tier** (Python `asr/`): faster-whisper self-host, transcribe audio → text (audio không rời LAN).

> **Fusion ở backend** (không còn tại board): PIR và radar nằm ở 2 board khác nhau nên occupancy được gộp ở backend — VÀO khi `presence=true` + có `motion` trong `EnterWindow`; RA khi `presence=false` giữ ≥ `ExitTimeout`. Đánh đổi: presence occupancy phụ thuộc backend chạy.

```
┌─ Room node — S2 Mini ────────────────────────┐   ┌─ Voice node — WROOM-32 ──────────┐
│  LD2410 radar (OUT GPIO16, UART 33/18)       │   │  INMP441 I2S (26/25/34)          │
│  IR recv GPIO15 · IR blast GPIO5 · NVS       │   │  VAD năng lượng tại board        │
│  ENTER radar giữ≥1.5s / EXIT radar im≥3s     │   │  stream PCM 16k mono 16-bit → WS │
│   pub home/room/presence (radar, retain)     │   │  PIR (GPIO27) → home/door/motion │
│   sub home/room/ac_cmd, home/room/ac_learn   │   └───────┬──────────────────┬───────┘
└───────────────┬──────────────────────────────┘  audio WS│           MQTT motion│
                │ MQTT presence + ac                       │                      │
                ▼                                          ▼                      ▼
   ┌─────────────────────────────┐          ┌────────────────────────────┐   ┌───────────┐
   │  Mosquitto broker (:1883)   │◄─────────│  Go backend (:8080)        │◄──│ (motion   │
   │  auth, no TLS, LAN          │─────────►│  FUSE motion+presence →    │   │  qua      │
   └─────────────────────────────┘ presence │    occupied (state machine)│   │  broker)  │
                                    + ac_cmd │  /api/voice/stream (WS)    │   └───────────┘
                                             │  → WAV → asr:/transcribe   │
                                             │  → ParseVietCommand→ac_cmd │
                                             │  + REST/WS                 │
                                             └──────────────┬─────────────┘
                                                            ▼
                                             ┌──────────────────────────────┐
                                             │  asr/ (faster-whisper, :9000) │
                                             │  model small, cpu, int8       │
                                             └──────────────────────────────┘
```

> **Door node cũ** (`firmware/door-node/`) đã nghỉ hưu cho MVP 1 phòng — logic PIR gộp vào room node. File giữ lại làm tham chiếu ISR, không flash riêng.

---

## MQTT Topic Contract

Payload JSON, timestamp Unix milliseconds (`ts`). `ts=0` nghĩa NTP chưa sync (ngay sau boot).

| Topic | Hướng | QoS | Retain | Payload | Ý nghĩa |
|-------|-------|-----|--------|---------|---------|
| `home/room/presence` | Room node (radar) → Broker → Backend | 1 | **Yes** | `{"ts":<ms>,"present":true\|false}` | Presence theo **radar** (ENTER radar giữ ≥1.5s, EXIT radar im ≥3s). Retain để client vào sau lấy ngay trạng thái. |
| `home/door/motion` | **Voice node (PIR)** → Broker → Backend | 1 | No | `{"ts":<ms>,"motion":true}` | Cạnh lên PIR (GPIO27, throttle ~1s). Backend dùng để fuse (ENTER cần motion+presence). |
| `home/room/ac_cmd` | Backend → Broker → Room | 1 | No | `{"cmd":"on"\|"off"}` | Lệnh AC (từ voice ASR hoặc REST). Room node phát IR đã học. |
| `home/room/ac_learn` | Backend → Broker → Room | 1 | No | `{"button":"on"\|"off"}` | Mở cửa sổ học IR 15s. Room node capture raw IR → NVS. |

Audio **không** đi qua MQTT — voice node nối WebSocket trực tiếp tới backend `/api/voice/stream`.

---

## Fusion ở backend (motion voice-node + presence room-node)

PIR (voice-node) và radar (room-node) ở 2 board khác nhau → occupancy gộp ở **backend** (`internal/statemachine`). Đánh đổi: presence occupancy phụ thuộc backend chạy (mất tính "đúng khi broker/backend sập").

**Room node — presence theo radar** (`firmware/room-node`, `#define`):
| Tham số | Mặc định | Vai trò |
|---|---|---|
| `PRESENCE_HOLD_MS` | 1500 | Radar giữ HIGH liên tục bấy lâu → `present=true` |
| `RADAR_DEBOUNCE_MS` | 3000 | Radar rớt HIGH trong khoảng này vẫn coi "còn thấy" → `present=false` sau đó |
| `STATUS_HEARTBEAT_MS` | 2000 | Nhịp in `[hb]` trạng thái ra Serial khi bench-test (0 = tắt) |

**Voice node — motion theo PIR** (`firmware/voice-node`): PIR GPIO27 interrupt RISING → pub `home/door/motion` (throttle `MOTION_PUBLISH_THROTTLE_MS`=1000). `INPUT_PULLDOWN` để chân chưa nối không bắn interrupt ma.

**Backend — fusion** (`statemachine.evaluate`, `EnterWindow`=15s, `ExitTimeout`=60s):
```
OnMotion(ts):   lastMotionAt = now
OnPresence(p):  present = p; nếu p=false → bắt đầu đếm exit
evaluate():
  VÀO: present=true & (now - lastMotionAt) ≤ EnterWindow → occupied=true → ac_cmd "on"
  RA : occupied & present=false giữ ≥ ExitTimeout → occupied=false → ac_cmd "off"
```

### Vì sao fuse cả PIR lẫn radar?
- **PIR đơn lẻ**: chuyển động tắt khi ngồi yên → mất người → thoát nhầm.
- **Radar đơn lẻ**: LD2410 nhạy, giữ presence khi ngồi yên nhưng dễ bắt gió/xuyên tường (false-positive).
- **Cả hai (fuse ở backend)**: presence=radar giữ khi tĩnh; motion=PIR xác nhận có người thật → VÀO cần cả hai → chắc hơn, chống radar báo xuyên tường.

---

## Luồng Voice → AC

```
Voice node: mic I2S → RMS > VAD_THRESHOLD → mở WS → gửi PCM 16k mono 16-bit LE
            im lặng SILENCE_MS → ngừng gửi (giữ WS mở)
Backend /api/voice/stream (internal/voice/stream.go):
   đọc frame → utteranceBuffer.feed()
   read-deadline = ASR_SILENCE_MS mỗi lần Read → hết hạn = kết thúc câu → flush
   (byte cap ASR_MAX_UTTER_MS; flush câu cuối khi client đóng)
   → dựng WAV header → asr_client POST multipart tới ASR_URL /transcribe
   → text tiếng Việt → ParseVietCommand(text) → "on"/"off"
   → mqttclient.PublishACCmd() → home/room/ac_cmd
Room node nhận ac_cmd → sendAC() phát IR đã học → điều hòa bật/tắt.
```

`ParseVietCommand` (internal/voice/command.go): chuẩn hoá + bỏ dấu, khớp "bật/tắt" + "điều hòa/điều hoà/máy lạnh". Test: `command_test.go`.

ASR service (`asr/app.py`): FastAPI + faster-whisper `WhisperModel(small, cpu, int8)`, `POST /transcribe` (multipart WAV) → `{"text":...}`, `GET /healthz`.

---

## Backend API (REST/WS)

| Method | Path | Mục đích |
|--------|------|----------|
| GET | `/healthz` | Liveness + trạng thái MQTT |
| GET | `/api/state` | Occupancy + AC hiện tại |
| POST | `/api/ac` | Lệnh AC tay: `{"cmd":"on"/"off"}` → pub `ac_cmd` |
| POST | `/api/ac/learn` | Mở học IR: `{"button":"on"/"off"}` → pub `ac_learn` |
| GET | `/api/ws` | WebSocket broadcast state |
| GET | `/api/voice/stream` | **WebSocket audio** (PCM 16k mono 16-bit LE) → ASR → `ac_cmd` |

`config.LoadVoice()` thêm cấu hình voice mà không đổi chữ ký `NewRouter`/`Load` cũ.

### State machine (Phase 2 — nay là điểm fusion)
`Idle / Occupied / ExitWait` với `ENTER_WINDOW_S=15`, `EXIT_TIMEOUT_S=60`. Nhận `motion`(voice-node PIR) + `presence`(room-node radar) → **fuse thành occupied** (VÀO cần cả hai; RA khi presence=false đủ lâu). Thiết kế 3-tier gốc vốn cho door-PIR + room-radar nên khớp — dời PIR sang voice-node không đổi topic → backend không cần sửa code.

---

## Config (Environment)

| Biến | Mặc định | Ghi chú |
|------|----------|---------|
| `MQTT_HOST` / `MQTT_PORT` / `MQTT_USER` / `MQTT_PASS` | — / 1883 | Broker |
| `HTTP_ADDR` | `:8080` | Listen |
| `ENTER_WINDOW_S` / `EXIT_TIMEOUT_S` | 15 / 60 | State machine |
| `ASR_URL` | — | Endpoint faster-whisper (vd `http://asr:9000/transcribe`) |
| `ASR_SILENCE_MS` | ~800 | Read-deadline kết thúc câu |
| `ASR_MAX_UTTER_MS` | — | Trần độ dài 1 câu (byte cap) |
| `VOICE_SAMPLE_RATE` | 16000 | Sample rate PCM |

Secrets (WiFi/MQTT trong `config.h`, `.env`, `passwd`) đều gitignore.

---

## Deployment

```
Linux/WSL host (LAN)
├─ Mosquitto (home-mqtt, :1883)          # docker
├─ Go backend (:8080)                    # docker compose (backend/)
└─ asr (faster-whisper, :9000 internal)  # docker compose, volume cache model
Room node (WiFi) ─┐
Voice node (WiFi) ┴─ tới host qua LAN (192.168.1.x)
```

Bật full: `cd backend && docker compose up` (backend + asr). Chỉ quan sát presence: `docker exec -it home-mqtt mosquitto_sub -u homeuser -P homepass123 -t 'home/#' -v`.

---

## Security (MVP / LAN-only)

| Mục | Trạng thái |
|-----|-----------|
| MQTT TLS | ❌ (LAN-only; thêm trước khi lộ internet) |
| MQTT auth | ✅ user/pass |
| REST/WS auth | ❌ (giả định LAN) |
| Audio ra ngoài | ✅ Không — ASR self-host, audio ở LAN |
| IR codes | ✅ Chỉ local NVS trên room node |

Trước khi lộ internet: thêm TLS/mTLS MQTT, auth API, siết CORS, rate-limit.

---

## Hardware & Wiring

Pinout chi tiết + cảnh báo điện: [`docs/system-wiring.md`](./system-wiring.md).

- **Room node**: S2 Mini + LD2410 (OUT GPIO16, UART 33/18) + IR recv (GPIO15) + IR blast (GPIO5).
- **Voice node**: WROOM-32 + INMP441 (SCK26/WS25/SD34, L/R→GND) + PIR (GPIO27 → motion).
- **Broker**: Mosquitto (container `home-mqtt`).

---

## Trạng thái nghiệm thu (2026-07-16)

| Hạng mục | Trạng thái |
|----------|-----------|
| Room node radar → `presence` (radar-only) | ✅ nghiệm thu HW (serial `[hb]` + MQTT); firmware radar-only build pass |
| Backend fuse motion+presence → occupied | ✅ code verify (build/vet/test xanh, không cần sửa); ⏳ E2E |
| Backend voice + ASR (build/vet/test) | ✅ xanh (chưa E2E audio thật) |
| Voice node firmware (MQTT + PIR + audio, build) | ✅ pass; ⏳ chưa hàn mic + chưa verify PIR trên board |
| **PIR trên voice-node (WROOM GPIO27) → motion** | ⏳ chưa verify — con PIR từng cắm ngược trên S2 gây nóng bỏng (nghi hỏng); phải đấu đúng 5V/GND/IN + thử/thay |
| **IR receiver + blaster (GPIO15/GPIO5)** | ⏳ **chưa có phần cứng** — firmware sẵn sàng, chưa đấu mạch → `ac_cmd`→IR chưa chạy được |
| E2E voice → whisper → ac_cmd → IR | ⏳ chưa chạy (chờ IR + mic) |

**Đã phát hiện:** (1) mối hàn radar OUT→GPIO16 **chập chờn** → hàn lại chắc + gỡ khỏi cổng USB-C. (2) PIR cắm ngược trên S2 gây nóng bỏng → đã dời sang voice-node GPIO27; đấu lại cẩn thận theo chữ in chân.

---

## Related Docs

- [`project-overview-pdr.md`](./project-overview-pdr.md) — scope & quyết định
- [`codebase-summary.md`](./codebase-summary.md) — cấu trúc code
- [`system-wiring.md`](./system-wiring.md) — đấu nối phần cứng
- [`project-roadmap.md`](./project-roadmap.md) — tiến độ pha
