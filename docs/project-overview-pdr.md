# Project Overview & PDR

> Cập nhật: 2026-07-16.

## Project Name
**ESP32 Home Presence Detection + Automatic AC Control + Voice**

## Problem Statement

Điều khiển điều hòa thủ công gây lãng phí: quên tắt khi rời phòng, chạy AC ở phòng trống tốn điện, không có phát hiện hiện diện đủ tin cậy để tự động hoá.

## Solution

Hệ phân tán qua MQTT:
1. Phát hiện hiện diện bằng **fusion PIR + radar** (PIR ở voice-node, radar ở room-node, gộp ở backend — chắc hơn 1 cảm biến).
2. Tự bật/tắt điều hòa theo occupancy (qua IR học được).
3. **Ra lệnh bằng giọng nói tiếng Việt** ("bật/tắt điều hòa") → ASR self-host → điều khiển AC.
4. REST/WebSocket cho client giám sát + điều khiển tay.

## Scope

### 2 node vật lý (MVP 1 phòng)
- **Room node** (Wemos S2 Mini): LD2410 radar (GPIO16) → `home/room/presence` + IR learn/blast (GPIO15/5).
- **Voice node** (ESP32-WROOM-32): INMP441 I2S mic → VAD → stream audio; **PIR (GPIO27) → `home/door/motion`**.
- **Fusion** motion+presence → occupied ở **backend** (state machine).

### Backend + ASR
- **Go backend**: nhận motion+presence, state machine, REST/WS, **endpoint voice `/api/voice/stream`**.
- **ASR** (`asr/`): faster-whisper self-host (`small`, cpu, int8) — audio không rời LAN.

### Broker
- Mosquitto (auth, no TLS, LAN-only).

### Tương lai
- **Phase 4**: Flutter app tiêu thụ REST/WS.

## Key Product Decisions

| Quyết định | Lý do | Trạng thái |
|-----------|-------|-----------|
| **Fusion PIR+radar Ở BACKEND** (PIR dời sang voice-node 2026-07-16) | PIR/radar ở 2 board khác nhau → gộp ở backend (state machine 3-tier gốc). Đánh đổi: presence phụ thuộc backend chạy | ✅ Chốt (đảo từ "tại board") |
| **2 node** (S2 Mini presence+IR / WROOM voice) thay all-in-one | Radar đã hàn sẵn S2 Mini; mic ngốn CPU → WROOM 2 nhân; presence nhẹ → S2 1 nhân đủ | ✅ Chốt |
| **ASR = faster-whisper self-host** (không cloud) | Miễn phí, audio ở LAN (riêng tư), tiếng Việt tốt | ✅ Chốt, backend xong |
| **VAD năng lượng trên device** (không wake-word/nút bấm) | Đơn giản cho MVP; chỉ stream khi có tiếng | ✅ Chốt |
| **Audio qua WebSocket** (không MQTT) | MQTT không hợp stream audio | ✅ Chốt |
| **MQTT làm transport** cho presence/AC | Decouple firmware↔backend, chuẩn IoT | ✅ Chốt |
| **IR lưu local NVS** (không sync backend) | Giảm phức tạp; AC gắn phòng | Deferred multi-room |
| **LAN-only, no TLS** | MVP; thêm TLS trước khi lộ internet | Ràng buộc ghi nhận |

## Architecture (tóm tắt)

```
[Room Radar] ── home/room/presence ──┐
[Voice PIR]  ── home/door/motion ─────┼─ MQTT ─ Go backend (FUSE→occupied) ─ REST/WS
[Room IR]    ◄─ home/room/ac_cmd/learn ┘            │
[Voice mic]  ── WebSocket audio → /api/voice/stream → asr (whisper) → ac_cmd
```

Chi tiết contract: [`system-architecture.md`](./system-architecture.md).

## Non-Goals (deferred / out of scope)
- Cloud connectivity (MVP LAN-only)
- Multi-room / multi-AC (single room MVP)
- Mobile app (Phase 4, chưa bắt đầu)
- Lịch sử sự kiện SQLite (YAGNI)
- Wake-word offline (dùng VAD; wake-word là mở rộng sau)

## Open Questions

1. **Hàn lại radar OUT→GPIO16** (mối chập chờn) + gỡ khỏi cổng USB-C — chặn độ ổn định presence.
2. **PIR thật trên voice-node**: đo mức áp OUT (3.3 cắm thẳng / 5V chia áp) → nối GPIO27. Con PIR từng cắm ngược trên S2 gây nóng bỏng → thử/thay.
3. **Tune `VAD_THRESHOLD`** voice-node với mic thật.
4. **E2E voice**: đo độ trễ whisper trên CPU thật (<2s); hạ `tiny` nếu chậm.

## Hardware Manifest

Pin chi tiết: [`system-wiring.md`](./system-wiring.md).
- **Room node**: S2 Mini + PIR + HLK-LD2410 + TSOP38238 (IR recv) + IR blaster (transistor).
- **Voice node**: WROOM-32 + INMP441.
- **Broker/Backend/ASR**: host Linux/WSL (Docker).

## Success Metrics

- ✅ Firmware room-node & voice-node compile sạch
- ✅ **Room node flash + chạy HW thật; radar+fusion presence đúng (2026-07-16)**
- ✅ Backend compile + test xanh (state machine + voice command)
- ✅ E2E MQTT: presence/motion tới broker, khớp timestamp
- ⏳ E2E voice: "bật/tắt điều hòa" → whisper → ac_cmd → IR
- ⏳ Nối PIR thật + hàn lại radar chắc + hàn mic

## Development Notes
- **Ngôn ngữ**: định danh English; comment/log firmware tiếng Việt (chủ ý — xem [`code-standards.md`](./code-standards.md)).
- **Test**: Go state machine + 9 case parse lệnh voice pass. Firmware verify qua serial `[hb]` + MQTT.
- **No persistence**: state machine in-memory (YAGNI).
