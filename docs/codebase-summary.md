# Codebase Summary

> Cập nhật: 2026-07-16. Phản ánh kiến trúc 2-node fusion-tại-board + voice→ASR.

## Project Structure

```
project-root/
├── backend/      # Go: MQTT + state machine + REST/WS + voice endpoint
├── asr/          # Python FastAPI + faster-whisper (self-host ASR)
├── firmware/     # PlatformIO ESP32: room-node, voice-node, door-node (retired), mqtt/
├── docs/         # Tài liệu kỹ thuật
├── plans/        # Log pha + quyết định (gitignored trừ template)
├── README.md
└── .gitignore
```

## Backend (Go)

**Location**: `backend/` · **Framework**: Chi router + paho MQTT + coder/websocket + log/slog · **Module**: `github.com/hung/home-backend`
**Status**: ✅ Code-complete, build/vet/test xanh (state machine + voice command). E2E audio thật: ⏳.

```
backend/
├── cmd/server/main.go            # bootstrap: config, MQTT, router, HTTP server
├── internal/
│   ├── api/
│   │   ├── router.go             # Chi router; group /api gồm ws + voice/stream
│   │   ├── handlers.go           # REST: /healthz, /api/state, /api/ac, /api/ac/learn
│   │   ├── handlers_test.go
│   │   ├── ws.go                 # WebSocket hub broadcast state
│   │   └── ws_test.go
│   ├── config/config.go          # env parse: MQTT_*, HTTP_*, timing + LoadVoice() (ASR_*)
│   ├── events/events.go          # struct payload MQTT (Motion, Presence)
│   ├── mqttclient/client.go      # paho wrapper: connect/sub/pub/reconnect, PublishACCmd()
│   ├── statemachine/
│   │   ├── machine.go            # Idle/Occupied/ExitWait (Phase 2)
│   │   └── machine_test.go
│   └── voice/                    # ⭐ MỚI (Phase 2 voice)
│       ├── stream.go             # WS /api/voice/stream: utteranceBuffer, read-deadline VAD, WAV
│       ├── asr_client.go         # POST multipart WAV → ASR_URL
│       ├── command.go            # ParseVietCommand(text) → "on"/"off"
│       └── command_test.go       # 9 case pass
├── Dockerfile                    # multi-stage → distroless
├── docker-compose.yml            # backend + service asr (+ volume cache model)
└── .env.example
```

### Voice pipeline (internal/voice)
- `stream.go`: nhận WS binary PCM 16k mono 16-bit LE → `utteranceBuffer.feed()`; kết thúc câu bằng **read-deadline `ASR_SILENCE_MS`** mỗi `conn.Read`; flush câu cuối khi client đóng; byte cap `ASR_MAX_UTTER_MS`; dựng WAV header.
- `asr_client.go`: POST multipart WAV tới `ASR_URL`, nhận text.
- `command.go`: chuẩn hoá + bỏ dấu, match "bật/tắt" + "điều hòa/điều hoà/máy lạnh" → phát `home/room/ac_cmd`.

### API
| Method | Path | Status |
|--------|------|--------|
| GET | `/healthz` | ✅ |
| GET | `/api/state` | ✅ |
| POST | `/api/ac` | ✅ |
| POST | `/api/ac/learn` | ✅ |
| GET | `/api/ws` | ✅ |
| GET | `/api/voice/stream` | ✅ (chưa E2E audio thật) |

### Config env
`MQTT_HOST/PORT/USER/PASS`, `HTTP_ADDR` (`:8080`), `ENTER_WINDOW_S` (15), `EXIT_TIMEOUT_S` (60), `ASR_URL`, `ASR_SILENCE_MS`, `ASR_MAX_UTTER_MS`, `VOICE_SAMPLE_RATE` (16000).

---

## ASR service (Python)

**Location**: `asr/` · faster-whisper self-host.

```
asr/
├── app.py           # FastAPI: WhisperModel(small, cpu, int8); POST /transcribe (multipart WAV); GET /healthz
├── requirements.txt
└── Dockerfile
```

Chạy như 1 container cạnh backend (docker-compose `asr`). Audio không rời LAN. Model `small` là mặc định; hạ `tiny` nếu CPU chậm.

---

## Firmware (PlatformIO)

**Location**: `firmware/` · 3 project độc lập (không lib chung).

```
firmware/
├── room-node/     # board lolin_s2_mini (ESP32-S2), -DARDUINO_USB_CDC_ON_BOOT=1
│   └── src/main.cpp   # radar → presence + IR learn/blast + MQTT + [hb] heartbeat (radar-only)
├── voice-node/    # board esp32dev (WROOM-32)
│   └── src/main.cpp   # INMP441 I2S + VAD + stream WS PCM 16k + MQTT PIR→motion
├── door-node/     # ⚠️ NGHỈ HƯU (tham chiếu ISR PIR); không flash cho MVP 1 phòng
└── mqtt/          # cấu hình Mosquitto (passwd.example)
```

### Room node — `firmware/room-node/src/main.cpp`
**Board**: Wemos S2 Mini (ESP32-S2). **Status**: ✅ **Nghiệm thu HW 2026-07-16** (radar → presence chạy đúng). Radar-only (PIR đã dời sang voice-node).

| Thành phần | Chân | Vai trò |
|-----------|------|---------|
| LD2410 radar | GPIO16 (OUT digital), UART GPIO33/18 (để dành) | Presence; poll 200ms |
| IR receiver TSOP | GPIO15 | Học mã IR (cửa sổ 15s) — ⏳ chưa có phần cứng |
| IR blaster | GPIO5 → transistor | Phát mã IR đã học — ⏳ chưa có phần cứng |
| NVS | — | Lưu mã IR "on"/"off" (namespace `ac_codes`) |

- Pub `home/room/presence` (theo **radar**, retain). KHÔNG còn pub `home/door/motion` (PIR đã dời đi).
- Sub `home/room/ac_cmd` → `sendAC()`; `home/room/ac_learn` → `startLearn()`.
- Debug: `[hb]` heartbeat mỗi `STATUS_HEARTBEAT_MS`=2000 in `radar/occupied/sinceRadarHigh/wifi/mqtt`; chờ USB-CDC lúc boot để không mất log (đặc thù S2).
- Tham số presence: `PRESENCE_HOLD_MS`=1500 (ENTER radar giữ), `RADAR_DEBOUNCE_MS`=3000 (EXIT radar im).
- Deps: `crankyoldgit/IRremoteESP8266`, `256dpi/MQTT`.

### Voice node — `firmware/voice-node/src/main.cpp`
**Board**: ESP32-WROOM-32 (`esp32dev`). **Status**: ✅ build pass (audio + MQTT + PIR), ⏳ chưa hàn mic + tune VAD + verify PIR.

| Thành phần | Chân | Vai trò |
|-----------|------|---------|
| INMP441 SCK/WS/SD | GPIO26 / 25 / 34 | I2S mic (SD input-only) |
| INMP441 L/R | GND | Kênh trái |
| **PIR** | **GPIO27** (`INPUT_PULLDOWN`, interrupt RISING) | Chuyển động → pub `home/door/motion` |

- Audio: I2S RX 16kHz slot 32-bit → `raw >> 16` PCM16; VAD RMS > `VAD_THRESHOLD` (placeholder 800) → stream WS `/api/voice/stream`; im `SILENCE_MS` → ngừng gửi.
- **MQTT** (`256dpi/MQTT`, client id `voice-node`): PIR cạnh lên → `publishMotion()` → `home/door/motion` (throttle 1s). MQTT chạy song song audio (WROOM 2 nhân).
- WiFi/WS/MQTT reconnect. Deps: `links2004/WebSockets` + `256dpi/MQTT` + I2S driver.

### Secrets
Mỗi node: `include/config.h.example` (check-in) + `include/config.h` (gitignore, WiFi/MQTT/backend host thật).

---

## Shared Patterns

| Mục | Quy ước |
|-----|---------|
| Định danh code | English (camelCase hàm, SCREAMING_SNAKE_CASE hằng) |
| Comment/log | Tiếng Việt (firmware), English (Go) |
| Go test | table-driven, tên scenario (không đánh số chung chung) |
| Firmware | không unit test; verify qua serial `[hb]` + MQTT |

**Không lib firmware chung**: mỗi node standalone (sensor khác nhau, flash/debug độc lập, chấp nhận trùng WiFi/MQTT init cho MVP).

---

## Next Steps

Xem [`project-roadmap.md`](./project-roadmap.md). Việc gần nhất (phần cứng): hàn lại radar OUT→GPIO16 + gỡ khỏi USB-C; nối PIR; hàn INMP441 + tune VAD; E2E voice.
