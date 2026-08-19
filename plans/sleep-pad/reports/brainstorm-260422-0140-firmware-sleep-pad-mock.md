# Brainstorm: Firmware Sleep Pad Mock

**Date:** 2026-04-22
**Status:** Approved

## Problem Statement

Smoke-test toàn platform (ESP32 → MQTT → backend → Flutter app) nhưng chưa có sleep pad LSM-800-TP vật lý. Cần 1 cách cho ESP32 tự generate telemetry realistic để pipeline downstream có data test.

## Requirements

- ESP32 firmware phải chạy đúng như production: BLE GATT provisioning, WiFi connect, MQTT publish, LWT, client_id = device_id
- Data output match đúng Legact Pro V2 binary protocol (0x85 + 0x86 frames) — byte-for-byte
- Exercise UART parser state machine (WAIT_HEADER → READ_FRAME) — không bypass
- Enable/disable qua compile flag, zero runtime overhead trong production build
- Cover 4 scenarios phủ happy path + edge cases (normal / movement / alert / offline)

## Evaluated Approaches

### A — Firmware self-mock (compile flag) ✓ CHOSEN
Compile flag `MOCK_SLEEPPAD` trong platformio.ini. Khi bật, firmware skip UART read, thay bằng synthetic frame generator. Generator tạo raw binary bytes matching protocol, feed vào `parser.feed(byte)` để state machine chạy đầy đủ.

**Pros:** Không cần thêm hardware. ESP32 + BLE + MQTT chạy y như production. Parser được test. Zero prod overhead. Dev thực hiện chỉ với ESP32 trên bàn.
**Cons:** Offline scenario không fire MQTT LWT thật (ESP32 vẫn connected TCP — chỉ ngừng publish). Acceptable — Redis online TTL vẫn expire đúng.

### B — External UART emulator (ESP32 thứ 2 hoặc USB-TTL dongle)
1 thiết bị phụ phát bytes qua GPIO16 của ESP32 target.

**Pros:** Realistic đến bit-level qua dây UART thật.
**Cons:** Cần thêm hardware + wiring. Overkill cho smoke test.

### C — Python MQTT publisher (skip ESP32)
Script publish thẳng vào Mosquitto giả làm device.

**Pros:** Đơn giản nhất, chạy không cần hardware.
**Cons:** Mất hoàn toàn ESP32/BLE/MQTT/parser coverage. Không phù hợp smoke-test goal là prove full pipeline.

## Final Recommendation

**Option A — Firmware self-mock.** Match smoke-test goal 100%. ~145 LOC firmware code, gated bởi `#ifdef MOCK_SLEEPPAD`, không ảnh hưởng production build.

## Design

### Compile flag
`platformio.ini` thêm env mới:
```ini
[env:esp32dev-mock]
extends = env:esp32dev
build_flags = ${env:esp32dev.build_flags} -DMOCK_SLEEPPAD=1
```

Run `pio run -e esp32dev-mock -t upload` để flash mock build. `esp32dev` env không đổi — cho hardware thật sau này.

### New files
- `firmware/src/mock-sleeppad.h` (~25 LOC) — scenarios enum + 2 function prototypes
- `firmware/src/mock-sleeppad.cpp` (~120 LOC) — frame builder + random walk + timer + scenario switch

### main.cpp changes
```cpp
#ifdef MOCK_SLEEPPAD
#include "mock-sleeppad.h"
static void feed_parser(uint8_t b) { parser.feed(b); }
#endif

void setup() {
    // ...
    #ifdef MOCK_SLEEPPAD
    mock_init(DEVICE_ID);
    Serial.println("[Mock] SLEEP PAD MOCK ACTIVE");
    #endif
}

void loop() {
    #ifndef MOCK_SLEEPPAD
    while (Serial2.available()) parser.feed((uint8_t)Serial2.read());
    #else
    mock_tick(feed_parser);
    #endif
    mqtt_loop();
    // ... existing heartbeat ...
}
```

### Scenario timeline (5m10s/cycle, auto-repeat)

| t (m:s)     | Scenario         | HR       | Status                | 0x86 extras                                       |
|-------------|------------------|----------|-----------------------|---------------------------------------------------|
| 0:00–2:00   | Normal sleep     | 60±3     | 0x04 SLEEP 90%        | movement 0-2, snore 0, resp_disorder 0            |
| 2:00–3:00   | Movement spike   | 65±3     | 0x02 MOVEMENT 70%     | movement 10+, snore 3-5, resp_disorder 1-2        |
| 3:00–4:00   | Alert trigger    | 130-140  | 0x08 WEAK_BREATHING 30% | resp_disorder 6-10                              |
| 4:00–5:10   | Offline          | —        | —                     | (no publish → Redis TTL expires → app offline)    |
| 5:10→end    | Normal sleep 2   | 60±3     | 0x04 SLEEP            | (baseline)                                        |

### Frame format (match protocol byte-for-byte)
```
[0x7D][frame_type][len_lo][len_hi][10B device_id ASCII][content][0x0D]
```
- frame_type = 0x85 (sec, 12B content) hoặc 0x86 (min, 15B content)
- len = total frame size (1+1+2+10+content+1)
- Emit byte-by-byte qua `parser.feed()` để state machine test đủ

### Random walk
```cpp
static uint8_t next_hr(uint8_t baseline, uint8_t cur) {
    int delta = (int)(random(0, 7)) - 3;  // -3..+3
    int next = (int)cur + delta;
    if (abs(next - baseline) > 8) next = baseline + (delta > 0 ? 8 : -8);
    return constrain(next, 30, 180);
}
```
RR: σ=1, clamp [5, 40]. Status sampled từ weighted distribution per scenario.

### Timing
Mock tick uses `millis()` so MQTT loop + heartbeat unaffected. Non-blocking.

## Risks

| Risk | Mitigation |
|------|-----------|
| Protocol mismatch với sleep pad thật sau này | Validated parser vs real device Apr 10 POC; generator follows protocol doc byte positions |
| Random walk drift ngoài realistic range | Clamp HR [30,180], RR [5,40] |
| BLE + WiFi + mock cùng chạy gây memory issue | Mock init sau khi BLE stop — same call order như real UART path |
| Offline scenario không fire LWT thật | Accepted — Redis `device:{id}:online` TTL vẫn expire → app shows offline. For true LWT test, manually `ESP.restart()` hoặc `WiFi.disconnect()` — out of scope |

## Success Metrics

- `pio run -e esp32dev-mock` → SUCCESS, flash size tăng <2KB
- Serial output hiển thị `[Mock] SLEEP PAD MOCK ACTIVE` + status code per scenario
- Backend `sec_data` rows xuất hiện mỗi 1s cho device
- Backend `min_data` rows mỗi 60s
- App Home screen update HR/RR realtime
- Sau 3 phút mark: Alert engine fires `hr_high` alert (default threshold 120)
- Sau 4 phút mark: App Home shows offline banner

## Next Steps

1. Create implementation plan via `/ck:plan` — single-phase plan covering: compile flag setup + mock-sleeppad.h/.cpp + main.cpp integration + build verify + on-device smoke test
2. Implement per plan
3. Execute smoke test per existing runbook (draft in earlier brainstorm on local testing)

## Unresolved

- Flag variant naming: `esp32dev-mock` vs `esp32dev-sim` vs `esp32dev-dev`? (Chose `esp32dev-mock` — clearest intent)
- Should mock also support custom timings via build_flags (e.g. `-DMOCK_SCENARIO_DURATION=30`)? Defer — YAGNI.
