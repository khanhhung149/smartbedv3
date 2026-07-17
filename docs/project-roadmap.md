# Project Roadmap

> Cập nhật: 2026-07-17.

> **ĐÊM 16→17/07**: Phase 4 (**app Flutter Android**) và **lịch sử event SQLite** XONG
> (`089b42a`, `1ec80bd`, `ea6e318`, đã push). Toolchain Flutter+Android dựng từ số 0
> trong WSL, build ra APK release thật → `C:\Users\HP\Desktop\dieu-hoa-thong-minh.apk`.
> **Việc duy nhất còn lại của MVP: cắm PIR** (cần tay người).
> Xem `plans/260716-2055-flutter-app-and-event-history/`.

## Overview

Bốn pha tăng dần: (1) presence + AC trên room node (**radar → presence**), (2) Go backend + endpoint voice + ASR (**fuse motion+presence**), (3) voice node WROOM-32 (**mic + PIR**), (4) Flutter app.

**Trạng thái**: Phase 1 radar → presence **nghiệm thu HW**. Phase 2 backend + **voice E2E NGHIỆM THU** (nói "bật/tắt điều hòa" → whisper → `ac_cmd on/off` đúng, 2026-07-16 chiều). Phase 3 mic INMP441 hàn + chạy thật. **IR bỏ khỏi scope** (không làm phần cứng; giữ code, `ac_cmd` là đích). **PIR để mai** (con cũ chết do cắm ngược). Phase 4 chưa bắt đầu.

> **Nâng cấp 2026-07-15/16** (`plans/260715-2047-...` → `plans/260716-1433-relocate-pir-to-voice-node-backend-fusion/`):
> - Gộp còn **2 node vật lý**. **PIR dời sang voice-node (WROOM-32 GPIO27), radar ở room-node → fusion về BACKEND** (16/07, đảo từ "fuse tại board" sau khi PIR cắm ngược trên S2 gây nóng). Door-node nghỉ hưu.
> - Voice: ASR = **faster-whisper self-host** (`asr/`); backend voice endpoint `/api/voice/stream` + VAD + parse lệnh Việt → `ac_cmd` (xong, review APPROVE). Firmware voice-node build xong (audio+MQTT+PIR).
> - **16/07**: flash room-node HW thật, radar → presence chạy đúng qua serial `[hb]` + MQTT.

---

## Phase 1: Presence + AC (Room node — radar → presence)

**Status**: ✅ CODE-COMPLETE · ✅ **RADAR → PRESENCE NGHIỆM THU HW (2026-07-16)** · ⏳ hàn lại radar + IR

### Deliverables
| Component | Status | Ghi chú |
|-----------|--------|---------|
| Room node firmware (radar → presence + IR, radar-only) | ✅ Code + build (`lolin_s2_mini`, Flash ~61%) | `firmware/room-node/src/main.cpp` (PIR đã gỡ, dời voice-node) |
| Presence theo radar | ✅ Nghiệm thu | ENTER radar giữ ≥`PRESENCE_HOLD_MS`=1500; EXIT radar im ≥`RADAR_DEBOUNCE_MS`=3000. Fusion motion+presence ở backend |
| Debug heartbeat `[hb]` + chờ USB-CDC boot | ✅ Thêm 16/07 | `STATUS_HEARTBEAT_MS`=2000 |
| MQTT broker | ✅ `home-mqtt` :1883 (auth) | |
| Door node | ⚠️ Nghỉ hưu | `firmware/door-node/` giữ tham chiếu ISR |

### Đã nghiệm thu (2026-07-16, HW thật)
- ✅ Flash S2 Mini qua usbipd (bootloader tay: giữ BOOT + tap RST).
- ✅ Boot + WiFi (`mp`) + MQTT (`home-mqtt`) + NTP sync (timestamp thật).
- ✅ Radar `=1` khi có người, `=0` khi trống (giữ 168s liên tục — không báo giả).
- ✅ `present` VÀO khi radar giữ; RA ~3s sau radar hết (`RADAR_DEBOUNCE_MS`).
- ✅ Pub `home/room/presence` true/false tới broker (khớp serial).

### Còn treo (phần cứng)
1. **Hàn lại radar OUT→GPIO16** — mối chập chờn (từng đọc HIGH giả khi hở; LED module tắt mà GPIO16 vẫn 1). Gỡ radar khỏi vị trí đè cổng USB-C (mầm chập).
2. **IR receiver + blaster** — chưa có phần cứng (GPIO15/5 firmware dành sẵn) → `ac_cmd`→IR chưa chạy được.
3. **PIR** → nay thuộc Phase 3 (voice-node GPIO27). **E2E fusion** cần backend + cả 2 node publish.

### Success Criteria
- [x] Room node flash + boot + WiFi + MQTT + NTP
- [x] Radar publish presence đổi trạng thái đúng (radar-only)
- [x] Phòng trống → `present:false`; có người → `present:true`
- [ ] Backend fuse motion(voice-node)+presence(radar) → occupied đúng
- [ ] IR learn/blast verify với điều hòa thật (chờ phần cứng IR)

---

## Phase 2: Go Backend + Voice Endpoint + ASR

**Status**: ✅ CODE-COMPLETE, build/vet/test xanh · ✅ **VOICE E2E NGHIỆM THU (2026-07-16)** — nói "bật/tắt điều hòa" → whisper → publish `ac_cmd on/off` đúng.

> **Bug đã vá khi E2E:** `stream.go` dùng read-deadline (`context.WithTimeout` cho `conn.Read`) để dò im lặng → `coder/websocket` ĐÓNG WS khi ctx Read hết hạn (WS rớt mỗi 800ms). Sửa: goroutine đọc (ctx nền) + ticker `flushIfSilent`; bỏ gate `energyThreshold` (device đã tự VAD). ASR thêm `vad_filter` + `condition_on_previous_text=False` + `initial_prompt` (mồi từ vựng lệnh — cú chốt độ chính xác).

### Deliverables
| Component | Status |
|-----------|--------|
| Config (env, `LoadVoice()`) | ✅ |
| MQTT client (paho, reconnect, `PublishACCmd`) | ✅ |
| State machine (Idle/Occupied/ExitWait) | ✅ + test |
| REST API (`/healthz`, `/api/state`, `/api/ac`, `/api/ac/learn`) | ✅ |
| WebSocket state (`/api/ws`) | ✅ |
| **Voice endpoint `/api/voice/stream`** (utterance buffer, read-deadline VAD, WAV, byte cap) | ✅ |
| **ASR service `asr/`** (FastAPI + faster-whisper `small`/cpu/int8) | ✅ |
| `ParseVietCommand` (bật/tắt điều hòa/máy lạnh) | ✅ 9 case test pass |
| Docker: backend + asr (volume cache model) | ✅ |

### Verification
- ✅ `go build/vet/test ./...` xanh (state machine + voice command; không phá test cũ).
- ✅ Review APPROVE_WITH_MINORS: 2 MAJOR (VAD flush theo frame; mất câu cuối khi đóng) đã fix.
- ⏳ E2E audio thật (cần voice node có mic).

### Còn treo
1. **E2E voice**: `docker compose up` (backend+asr) → voice node stream → whisper → `ac_cmd`.
2. **Tune timing** `ENTER_WINDOW_S`/`EXIT_TIMEOUT_S` (occupancy fuse ở backend từ motion+presence).

---

## Phase 3: Voice Node (WROOM-32 + INMP441 + PIR)

**Status**: ✅ **MIC HÀN + CHẠY THẬT (2026-07-16)** — audio stream → whisper → `ac_cmd` E2E OK. Chân I2S phải `ONLY_RIGHT` (driver ESP32 đảo LEFT/RIGHT), gain `>>11`, VAD 2500. · ⏳ **PIR để mai** (con cũ chết do cắm ngược 5V/GND — thử con khác trên GPIO27).

Chốt: board **WROOM-32** (2 nhân); **không ASR trên board** (không PSRAM); **VAD năng lượng trên device**; **stream WS PCM 16k mono 16-bit LE** tới `/api/voice/stream`; ASR = whisper `small` self-host. **PIR dời về đây** (GPIO27) → pub `home/door/motion` (fusion ở backend).

### Deliverables
| Item | Status |
|------|--------|
| Firmware I2S INMP441 (SCK26/WS25/SD34) | ✅ build pass |
| VAD năng lượng RMS + stream WS | ✅ |
| **MQTT client + PIR GPIO27 → `home/door/motion`** | ✅ build pass |
| WiFi/WS/MQTT reconnect | ✅ |
| Hàn mic thật + đấu PIR (đúng chữ in, con cũ nghi hỏng) | ⏳ |
| Tune `VAD_THRESHOLD` (placeholder 800) | ⏳ thực địa |
| E2E: nói "bật/tắt điều hòa" → AC | ⏳ |

### Success Criteria
- [ ] PIR GPIO27 kích → pub `home/door/motion`; audio stream không hồi quy
- [ ] Serial thấy RMS tăng khi nói, stream=true khi vượt ngưỡng
- [ ] Backend nhận đủ chunk, whisper trả text đúng câu
- [ ] "bật/tắt điều hòa" → điều hòa thật bật/tắt (E2E qua Phase 1 + 2 + IR)
- [ ] Mất WiFi/backend → reconnect, không treo

---

## Phase 4: Flutter App

**Status**: ✅ **CODE-COMPLETE (2026-07-17)** — analyze sạch, 12/12 test xanh (4 test gọi
backend thật), APK release build được. ⏳ chưa cài lên máy Android thật.

Stack thực tế: **Flutter 3.44.6 + Riverpod 3.x + `http` + `web_socket_channel` +
`shared_preferences`** (dùng `http` thay Dio — chỉ 3 endpoint, YAGNI).
`app/` trong repo. **UI học IR bỏ** — IR đã ngoài scope.

| Màn | Nguồn dữ liệu | Status |
|---|---|---|
| Trang chủ — occupancy realtime + bật/tắt AC | `/api/state` (snapshot đầu) + `/api/ws` (push) + `POST /api/ac` | ✅ |
| Lịch sử | `GET /api/events` | ✅ |
| Cài đặt — IP backend + thử kết nối | `/healthz` | ✅ |

**Chốt kỹ thuật:**
- **iOS KHÔNG build được trên Windows** (cần macOS+Xcode; cài lên iPhone thật còn cần
  Apple Dev $99/năm). User xài iOS nhưng chốt **Android trước**.
- Quyền INTERNET phải khai ở manifest `main` — `flutter create` chỉ đặt ở `debug`/`profile`
  nên **bản release sẽ không có mạng**. Đã verify bằng dump APK.
- `network_security_config` cho phép cleartext: backend LAN không TLS, Android 9+ chặn HTTP.
- `ts=0` hiện **"không rõ giờ"** — message retained mang ts=0 khi node publish trước NTP sync.
- WS chỉ push KHI ĐỔI → phải lấy snapshot đầu bằng REST.

### Success Criteria
- [x] `flutter analyze` sạch, `flutter test` xanh
- [x] APK release build được + có quyền INTERNET
- [x] Parse đúng dữ liệu THẬT từ backend (test live)
- [ ] Cài lên máy Android thật, Home đổi realtime khi vào/ra phòng
- [ ] Nút bật/tắt AC → thấy `ac_cmd` ở broker
- [ ] iOS (chờ có máy Mac)

---

## Timeline & Priority

| Phase | Ưu tiên | Trạng thái |
|-------|---------|-----------|
| 1 | 🟥 Cao nhất | ✅ Radar→presence nghiệm thu HW; ⏳ hàn lại radar OUT→GPIO16 |
| 2 | 🟥 Cao nhất | ✅ Nghiệm thu E2E voice + **lịch sử SQLite** |
| 3 | 🟥 Cao nhất | ✅ Mic chạy thật; ⏳ **PIR — việc DUY NHẤT còn lại của MVP** |
| 4 | 🟨 Trung bình | ✅ Code-complete + APK; ⏳ cài máy thật |

## Open Questions & Decisions Pending

| Câu hỏi | Ảnh hưởng | Timeline |
|---------|-----------|----------|
| Hàn lại radar OUT→GPIO16 + gỡ khỏi USB-C | Ổn định presence P1 | Ngay |
| Đo áp PIR + đấu đúng chữ in trên voice-node GPIO27 (con cũ nghi hỏng) | Fusion đủ 2 sensor P3 | Khi đấu PIR |
| Tune `VAD_THRESHOLD` + độ trễ whisper (`small` vs `tiny`) | UX voice P3 | Khi có mic |
| Tune `ENTER/EXIT` window | Chính xác P2 | Sau khi có PIR |
| TLS/mTLS MQTT + auth API | Security | Trước internet |
| SQLite event history | Scope P2 | YAGNI, revisit nếu cần |

---

## Related Docs
- [`project-overview-pdr.md`](./project-overview-pdr.md)
- [`system-architecture.md`](./system-architecture.md)
- [`codebase-summary.md`](./codebase-summary.md)
- [`system-wiring.md`](./system-wiring.md)
