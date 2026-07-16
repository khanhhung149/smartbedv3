# ESP32 Home Presence Detection + Auto AC + Voice

Hệ IoT phân tán: phát hiện hiện diện bằng **fusion PIR (voice-node) + radar (room-node), gộp ở backend**, tự điều khiển điều hòa qua IR học được, và **ra lệnh giọng nói tiếng Việt** qua ASR self-host.

**Status** (2026-07-16): Room node radar → presence đã **nghiệm thu phần cứng**. Backend + ASR + voice-node (audio+MQTT+PIR) code-complete, build/test xanh; voice E2E + PIR thật + IR + hàn lại radar còn chờ.

## Kiến trúc

```
Room node (S2 Mini) ── home/room/presence (radar) ──┐
  IR learn/blast ◄── home/room/ac_cmd ──────────────┤
Voice node (WROOM-32) ─ home/door/motion (PIR) ──────┼─ Mosquitto ─ Go backend (FUSE) ─ REST/WS
                     └─ WebSocket audio ─────────────┼──────────→ /api/voice/stream
                                                      └──────────→ asr (faster-whisper) → ac_cmd
```

Chi tiết: [`docs/system-architecture.md`](./docs/system-architecture.md).

## Directory Map

| Thư mục | Nội dung |
|---------|----------|
| `backend/` | Go: MQTT + state machine + REST/WS + `internal/voice/` (endpoint audio) |
| `asr/` | Python FastAPI + faster-whisper (ASR self-host) |
| `firmware/` | PlatformIO: `room-node` (active), `voice-node` (active), `door-node` (retired), `mqtt/` |
| `docs/` | Tài liệu kỹ thuật |
| `plans/` | Log pha + quyết định (gitignored) |

## Documentation

| Doc | Cho | Nội dung |
|-----|-----|----------|
| [`docs/project-overview-pdr.md`](./docs/project-overview-pdr.md) | Product | Vấn đề, scope, quyết định, metrics |
| [`docs/system-architecture.md`](./docs/system-architecture.md) | Designer | Sơ đồ, MQTT/voice contract, fusion, API |
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
Config qua env (xem `.env.example`; `ASR_URL`, `MQTT_*`, timing).

### Broker
```bash
docker ps | grep home-mqtt   # Mosquitto :1883 (auth homeuser/homepass123)
```

### Firmware
```bash
# Room node (S2 Mini) — vào bootloader tay: giữ nút 0, tap RST, thả 0
cd firmware/room-node && pio run -e lolin_s2_mini -t upload
# Voice node (WROOM-32)
cd firmware/voice-node && pio run -e esp32dev -t upload
```
Secrets: copy `include/config.h.example` → `config.h`, điền WiFi/MQTT/backend host.

> WSL: nạp qua `usbipd` (attach board vào WSL). S2 Mini native-USB CDC — xem serial bằng `pio device monitor` (`cat` không đọc được vì cần DTR). Log `[hb]` in trạng thái mỗi 2s.

## MQTT Topics

| Topic | Hướng | Retain | Nội dung |
|-------|-------|--------|----------|
| `home/room/presence` | Room → Backend | ✅ | presence theo radar (backend fuse thêm motion) |
| `home/door/motion` | Voice node (PIR) → Backend | — | cạnh lên PIR (GPIO27) |
| `home/room/ac_cmd` | Backend → Room | — | AC on/off (voice hoặc REST) |
| `home/room/ac_learn` | Backend → Room | — | mở học IR 15s |

Xem live: `docker exec -it home-mqtt mosquitto_sub -u homeuser -P homepass123 -t 'home/#' -v`

## API

```bash
curl http://localhost:8080/api/state
curl -X POST http://localhost:8080/api/ac -H 'Content-Type: application/json' -d '{"cmd":"on"}'
curl -X POST http://localhost:8080/api/ac/learn -H 'Content-Type: application/json' -d '{"button":"on"}'
# WebSocket state:  ws://localhost:8080/api/ws
# WebSocket audio:  ws://localhost:8080/api/voice/stream  (PCM 16k mono 16-bit LE)
```

## Testing
```bash
cd backend && go test ./...     # state machine + 9 case parse lệnh voice
cd firmware/room-node && pio run -e lolin_s2_mini   # compile check
```

## Current Blockers

| Blocker | Ảnh hưởng | Trạng thái |
|---------|-----------|-----------|
| Mối hàn radar OUT→GPIO16 chập chờn + đè cổng USB-C | Độ ổn định presence | ⏳ Hàn lại + gỡ khỏi USB-C |
| PIR dời sang voice-node (GPIO27) — chưa verify, con cũ nghi hỏng (cắm ngược nóng) | Fusion đủ 2 cảm biến | ⏳ Đo áp + đấu đúng chữ in / thay con |
| Mic INMP441 chưa hàn + VAD chưa tune | Voice node | ⏳ Hàn + tune `VAD_THRESHOLD` |
| E2E voice chưa chạy | Luồng voice→AC | ⏳ `docker compose up` + nói thử |

## Security (MVP / LAN-only)
🔒 MQTT auth (no TLS) · REST/WS no auth (LAN) · **audio không rời LAN** (ASR self-host) · IR codes chỉ local NVS.
⚠️ Trước internet: TLS/mTLS MQTT, auth API, siết CORS, rate-limit.

## Roadmap

| Phase | Trạng thái |
|-------|-----------|
| 1: Presence + AC (room node radar-only, fusion ở backend) | ✅ Code + **HW nghiệm thu** (radar); ⏳ IR + hàn lại radar |
| 2: Go backend + voice endpoint + ASR | ✅ Code + test xanh; ⏳ E2E audio |
| 3: Voice node (WROOM-32 + INMP441) | ✅ Firmware build; ⏳ hàn mic + tune + E2E |
| 4: Flutter app | 🔴 Chưa bắt đầu |

Chi tiết: [`docs/project-roadmap.md`](./docs/project-roadmap.md).

---
**Last updated**: 2026-07-16
