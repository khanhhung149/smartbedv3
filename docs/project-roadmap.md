# Project Roadmap

> Cập nhật: **2026-07-24**.

> ## 🎉 MVP CHẠY THẬT ĐẦY ĐỦ (24/07)
> Chuỗi E2E hoàn chỉnh: **radar → presence → fusion tại board → IR Daikin → điều hòa vào COOL**, và
> **voice** (nói "bật điều hòa" → whisper → `ac_cmd` → IR). Backend + lịch sử SQLite + app Android + OTA
> 2 node đều xong.
>
> **Thay đổi kiến trúc so với 17/07:**
> - **PIR BỎ khỏi hệ.** Radar cấp presence trực tiếp, không cần PIR.
> - **Fusion đảo về BOARD**: voice-node nghe `home/room/presence` rồi tự bắn IR. Backend **không** tự
>   publish `ac_cmd` nữa (2 nơi cùng quyết thì lệch nhau → ESP32 là bộ não duy nhất).
> - **IR TRỞ LẠI scope và ĐÃ CHẠY**: dùng protocol Daikin có sẵn (`IRDaikin152`, remote ARC480A47), không
>   cần học mã/TSOP. Module IR phải chạy **5V**.
> - **`firmware/radar-node` thay `room-node`**: S2 đọc LD2410C **native UART @256000** (Moving/Static thật),
>   không ESP-NOW, không firmware bên thứ ba.
> - Thêm **vỏ hộp in 3D modular** (`hardware/vo-hop-modular.scad`).

## Overview

Sáu pha: (1) presence từ radar-node, (2) Go backend + voice + ASR + lịch sử SQLite, (3) voice-node
(mic + **fusion tại board** + IR Daikin), (4) Flutter app Android, (5) OTA 2 node, (6) vỏ hộp in 3D.

**Trạng thái**: Phase 1-5 ✅ **chạy thật**. Phase 6 ⏳ STL xong chưa in ướm.
Việc code còn treo: **không có**. Staleness tab "Thiết bị" (15s im lặng ⇒ "Mất tín hiệu") đã làm 26/07 —
cần thiết vì will đã dời sang `presence` nên `tele/<T>/LWT` kẹt "Online"; còn lại là việc tay (in vỏ, hàn nguồn).

> **Nâng cấp 2026-07-15/16** (`plans/260715-2047-...` → `plans/260716-1433-relocate-pir-to-voice-node-backend-fusion/`):
> - Gộp còn **2 node vật lý**. **PIR dời sang voice-node (WROOM-32 GPIO27), radar ở room-node → fusion về BACKEND** (16/07, đảo từ "fuse tại board" sau khi PIR cắm ngược trên S2 gây nóng). Door-node nghỉ hưu.
> - Voice: ASR = **faster-whisper self-host** (`asr/`); backend voice endpoint `/api/voice/stream` + VAD + parse lệnh Việt → `ac_cmd` (xong, review APPROVE). Firmware voice-node build xong (audio+MQTT; PIR sau đó bị BỎ — xem mục 24/07 ở đầu file).
> - **16/07**: flash room-node HW thật, radar → presence chạy đúng qua serial `[hb]` + MQTT.

---

## Phase 1: Presence (radar-node — LD2410C native UART → MQTT)

**Status**: ✅ **CHẠY THẬT (23-24/07)** — thay hoàn toàn `room-node` cũ.

### Deliverables
| Component | Status | Ghi chú |
|-----------|--------|---------|
| `firmware/radar-node` (LD2410C native UART) | ✅ chạy thật (`lolin_s2_mini`, Flash ~60%) | OUT G16 + UART TX33/RX18 @256000 |
| Presence theo radar | ✅ nghiệm thu qua broker | `PRESENCE_HOLD_MS`=300; heartbeat 30s; retain |
| `home/door/motion` (Analytics) | ✅ verify broker | throttle 1s |
| `tele/<T>/SENSOR` cho app | ✅ | 3s; Detect/Moving/Static thật |
| **MQTT will `present:false`** | ✅ flash + verify | S2 rớt → broker bắn vắng (~15-20s) |
| OTA | ✅ | env `lolin_s2_mini_ota`, password đồng bộ voice-node |
| `room-node` / `door-node` | ⚠️ Nghỉ hưu | giữ tham chiếu, **không flash** |

### Đã nghiệm thu (HW thật)
- ✅ Flash qua usbipd (`--auto-attach` vì S2 đổi cổng khi reset).
- ✅ WiFi (`mp`) + MQTT + NTP; presence true/false đúng trên broker.
- ✅ **Moving/Static đổi liên tục** khi quơ tay (sau khi fix **GND chung**).
- ✅ Rút nguồn S2 → will `present:false` → app hết kẹt "thấy người".

### Bài học phần cứng
1. **Mất GND chung** khi tách nguồn → `Moving=0` dù `Detect=1`, app BLE HLK vẫn mượt → không phải module hỏng.
2. **Đừng hàn radar đè cổng USB-C** (đã gây chập/nóng ở bản trước).

### Success Criteria
- [x] radar-node flash + boot + WiFi + MQTT + NTP
- [x] Publish presence đổi trạng thái đúng
- [x] Phòng trống → `present:false`; có người → `present:true`
- [x] Moving/Static (UART) có số thật, đổi liên tục
- [x] Will bắn `present:false` khi board rớt

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

## Phase 3: voice-node (WROOM-32 + INMP441 + **fusion tại board** + IR Daikin)

**Status**: ✅ **CHẠY THẬT ĐẦY ĐỦ (24/07)** — mic → VAD → whisper → `ac_cmd` → **IR Daikin vào COOL**.
I2S phải `ONLY_RIGHT` (driver ESP32 đảo LEFT/RIGHT), gain `>>11`, VAD 2500. **PIR đã BỎ.**

Chốt: board **WROOM-32** (2 nhân); **không ASR trên board** (không PSRAM); **VAD năng lượng trên device**;
**stream WS PCM 16k mono 16-bit LE**; ASR = whisper `small` self-host. **Fusion tại board** — sub
`home/room/presence` rồi tự bắn IR (ESP32 là bộ não duy nhất).

### Deliverables
| Item | Status |
|------|--------|
| Firmware I2S INMP441 (SCK26/WS25/SD34) | ✅ chạy thật |
| VAD năng lượng RMS + stream WS | ✅ (RMS max ~28000 khi nói, VAD trigger đúng) |
| **Fusion tại board**: sub presence → occupied (ENTER 800ms / EXIT 60s / link timeout 90s) | ✅ |
| **IR Daikin** `IRDaikin152` GPIO4, module 5V | ✅ **AC vào COOL 25°C quạt AUTO** |
| Sub `home/room/ac_cmd` (lệnh tay/voice) | ✅ |
| WiFi/WS/MQTT reconnect | ✅ |
| OTA (`esp32dev_ota`) | ✅ |
| Purge Tasmota + bỏ PIR khỏi firmware | ✅ |

### Success Criteria
- [x] Serial thấy RMS tăng khi nói, `streaming=true` khi vượt ngưỡng
- [x] Backend nhận đủ chunk, whisper trả text đúng câu
- [x] "bật điều hòa" → `[ir] Daikin ON (25C)` → **điều hòa thật vào COOL**
- [x] presence từ radar-node → `[fusion] occupied → 1` → IR ON tự động
- [x] radar-node chết (>90s không presence) → coi vắng, AC không chạy vĩnh viễn
- [x] Mất WiFi/backend → reconnect, không treo

### Bài học
- **LED IR vô hình với mắt** → soi camera điện thoại. Mất nhiều lượt debug vì tưởng mạch chết.
- **Module IR phải cấp 5V** (nhãn 5V, tầm 1-2m); 3V3 under-drive → tầm ngắn.
- **ARC480A47 = họ DAIKIN152** → `IRDaikin152` đúng protocol, không cần học mã/TSOP.
- **WROOM brownout tại `WiFi.mode()`** là **phần cứng** (biên nguồn mỏng), không phải firmware — chứng minh
  bằng swap board mới: cùng firmware, 0 brownout. Đừng thử lại lever TX power/CPU freq.

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
| 1 — radar-node presence | 🟥 Cao nhất | ✅ **chạy thật** (kèm will `present:false`) |
| 2 — backend + voice + ASR + SQLite | 🟥 Cao nhất | ✅ **chạy thật** |
| 3 — voice-node fusion + IR Daikin | 🟥 Cao nhất | ✅ **chạy thật, AC vào COOL** |
| 4 — Flutter app Android | 🟨 Trung bình | ✅ APK chạy trên máy thật, tab Thiết bị có staleness 15s |
| 5 — OTA 2 node | 🟩 Thấp | ✅ |
| 6 — Vỏ hộp in 3D modular | 🟩 Thấp | ⏳ STL xong, **chưa in ướm** |

## Open Questions & Decisions Pending

| Câu hỏi | Ảnh hưởng | Timeline |
|---------|-----------|----------|
| **In ướm `vo-hop-base.stl`** → chốt chiều cao khe USB / lỗ LED IR | Vỏ hộp P6 | Khi in |
| Ngưỡng staleness 15s có hợp WiFi nhà không (nháy "Mất tín hiệu" khi mạng chớp?) | Tab Thiết bị | Sau vài ngày dùng |
| Đấu nguồn chung Topo A (hàn S2 5V→WROOM VIN) | 1 cốc sạc nuôi 2 board | Việc tay |
| Tune `ENTER_STABLE_MS`/`EXIT_TIMEOUT_MS` tại voice-node | Trải nghiệm auto AC | Sau khi dùng thực tế |
| Motion: đổi từ throttle 1/s sang rising-edge only | Kích thước DB lịch sử | Nếu DB phình |
| Xoá `selftest.cpp` + `[env:selftest]` (chẩn đoán throwaway) | Dọn repo | Khi chắc không cần |
| `/api/ac/learn` + `home/room/ac_learn` (legacy, vô tác dụng) | Dọn contract | Khi dọn |
| TLS/mTLS MQTT + auth API | Security | Trước internet |

---

## Related Docs
- [`project-overview-pdr.md`](./project-overview-pdr.md)
- [`system-architecture.md`](./system-architecture.md)
- [`codebase-summary.md`](./codebase-summary.md)
- [`system-wiring.md`](./system-wiring.md)
