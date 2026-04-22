---
phase: 01
status: completed
priority: medium
effort: small
sub_project: firmware
---

# Phase 01: Firmware Sleep Pad Mock

## Context Links

- Brainstorm: `plans/reports/brainstorm-260422-0140-firmware-sleep-pad-mock.md`
- Sleep pad protocol: `Legact Pro_V2 data transfer protocol en20230130_1.pdf`
- Existing parser (reused): `firmware/src/uart-parser.h`, `firmware/src/uart-parser.cpp`
- Platform plan phase 05 (completed, firmware baseline): `plans/260420-2039-sleep-pad-full-platform/phase-05-esp32-ble-mqtt.md`

## Overview

Priority: **medium** (unblocks smoke test on-bench; not shipping to users)
Status: **completed** (2026-04-22)

Single phase, ~145 LOC total. Adds compile-flag-gated sleep-pad data generator. ESP32 synthesizes raw Legact Pro V2 binary frames and feeds them byte-by-byte to the existing parser, so the full pipeline (BLE provisioning → WiFi → MQTT publish → parser state machine → backend ingest → app realtime) is exercised without a physical sleep pad.

## Key Insights

- **Why byte-level feed instead of direct callback:** Parser state machine (WAIT_HEADER → READ_FRAME) is Phase 05-modified — byte-feed proves it still decodes correctly. Calling `parser.onSecData(data)` directly would bypass the parser entirely and miss regressions.
- **Why compile flag instead of runtime toggle:** Mock only wanted in dev. Runtime toggle = always-present code = wasted flash in prod. Compile flag = zero overhead via `#ifdef`.
- **Offline scenario caveat:** Mock's "Offline" phase just stops publishing for 70s. ESP32 stays TCP-connected to broker, so MQTT LWT does NOT fire. App's offline banner still works because it reads Redis `device:{id}:online` TTL (set by backend MQTT subscriber, expires 70s after last publish). Accepted — for true LWT testing, manually `WiFi.disconnect()` or reset the board. Documented in brainstorm.

## Requirements

- Compile flag `MOCK_SLEEPPAD` toggles mock on/off
- New PlatformIO env `esp32dev-mock` extends base `esp32dev` with `-DMOCK_SLEEPPAD=1`
- Mock generates protocol-compliant raw binary frames (match byte positions in Legact Pro V2 spec)
- 4 scenarios auto-cycled by `millis()` elapsed time
- Random walk generator (HR clamp [30,180], RR clamp [5,40])
- Non-blocking tick: does not stall `mqtt_loop()` or 60s heartbeat
- Zero overhead in production build (all mock code under `#ifdef MOCK_SLEEPPAD`)
- Each file <200 LOC

## Architecture

```
Mock build:  Serial2 ─╳ (unused)  ┌──────────────┐   ┌─────────┐   ┌───────┐
                                  │ mock-sleeppad│ ─▶│ parser  │──▶│ MQTT  │
                                  │   tick()     │   │ feed()  │   │pub    │
                                  └──────────────┘   └─────────┘   └───────┘

Prod build:  Serial2 ─▶ parser.feed() ─▶ MQTT pub   (mock module not compiled in)
```

Scenario state machine — single `uint32_t` start_ms + `millis() - start_ms` → scenario index:

```
elapsed (ms)  │ Scenario        │ HR range │ Status distribution   │ 0x86 extras
──────────────┼─────────────────┼──────────┼───────────────────────┼─────────────────────
0      –120k  │ NormalSleep     │ 60 ± 3   │ SLEEP 90%, MVMT 10%  │ movement 0-2
120k   –180k  │ MovementSpike   │ 65 ± 3   │ MOVEMENT 70%, SLEEP  │ movement 10+, snore 3-5, resp_disorder 1-2
180k   –240k  │ AlertTrigger    │ 130-140  │ WEAK_BREATHING 30%   │ resp_disorder 6-10
240k   –310k  │ Offline         │ ─        │ ─ (no publish)        │ ─
310k   +      │ NormalSleep2    │ same as NormalSleep                              → loop back
```

Wrap at end → start a new cycle by resetting `start_ms`.

## Related Code Files

**To create:**
- `firmware/src/mock-sleeppad.h` (~25 LOC)
- `firmware/src/mock-sleeppad.cpp` (~120 LOC)

**To modify:**
- `firmware/platformio.ini` — add `[env:esp32dev-mock]` inheriting from `esp32dev`
- `firmware/src/main.cpp` — add `#ifdef MOCK_SLEEPPAD` branches in `setup()` and `loop()`

**To keep unchanged:**
- `firmware/src/uart-parser.h`, `firmware/src/uart-parser.cpp`
- `firmware/src/ble-provisioning.*`, `firmware/src/mqtt-client.*`, `firmware/src/nvs-config.*`
- `firmware/include/config.h`

## Implementation Steps

1. **platformio.ini** — append env:
   ```ini
   [env:esp32dev-mock]
   extends = env:esp32dev
   build_flags = ${env:esp32dev.build_flags} -DMOCK_SLEEPPAD=1
   ```

2. **mock-sleeppad.h** — API surface:
   ```cpp
   #pragma once
   #include <Arduino.h>

   enum class MockScenario : uint8_t {
       NormalSleep, MovementSpike, AlertTrigger, Offline,
   };

   void mock_init(const char* device_id);      // cache device_id, reset timer + RNG seed
   void mock_tick(void (*feed_byte)(uint8_t)); // emit bytes when due; callback forwards to parser
   ```

3. **mock-sleeppad.cpp** — implementation:
   - File-static: `s_device_id[10]`, `s_start_ms`, `s_next_sec_emit_ms`, `s_next_min_emit_ms`, `s_hr`, `s_rr`
   - `current_scenario()`: returns enum based on `millis() - s_start_ms`, wraps at 310s
   - `random_walk_hr()`, `random_walk_rr()`: clamped walks per scenario baseline
   - `pick_status()`: sample from weighted distribution per scenario (return uint8_t 0x01…0x08)
   - `emit_sec_frame(feed)`: build [0x7D][0x85][len lo][len hi][10B device_id][12B content][0x0D] and call `feed(b)` per byte
   - `emit_min_frame(feed)`: same shape with 0x86 + 15B content
   - `mock_tick`: if scenario == Offline return; else emit sec every 1000ms, min every 60000ms

4. **main.cpp** — gate existing Serial2 drain behind `#ifndef`, add mock call:
   ```cpp
   #ifdef MOCK_SLEEPPAD
   #include "mock-sleeppad.h"
   static void feed_parser(uint8_t b) { parser.feed(b); }
   #endif

   void setup() {
       // ... existing setup ...
       #ifdef MOCK_SLEEPPAD
       mock_init(DEVICE_ID);
       Serial.println("[Mock] SLEEP PAD MOCK ACTIVE — bypassing UART");
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

5. **Build verify:** `cd firmware && python3 -m platformio run -e esp32dev-mock` → expect SUCCESS + flash usage printed. Compare with `-e esp32dev` baseline (expect <2KB diff).

6. **Commit** — single commit: `feat(firmware): add MOCK_SLEEPPAD compile flag + 4-scenario data generator`

## Todo

- [x] Append `[env:esp32dev-mock]` to `firmware/platformio.ini`
- [x] Write `firmware/src/mock-sleeppad.h` (enum + 2 prototypes)
- [x] Write `firmware/src/mock-sleeppad.cpp` (frame builder + scenario state machine + random walk)
- [x] Modify `firmware/src/main.cpp` — `#ifdef MOCK_SLEEPPAD` branches in setup/loop
- [x] `platformio run -e esp32dev-mock` → SUCCESS (flash 49.9%, 1569969 B)
- [x] `platformio run -e esp32dev` still SUCCESS (no regression in prod build)
- [x] Reviewer Offline-burst fix applied (mock-sleeppad.cpp:187-189 fast-forward timers)
- [ ] Flash to ESP32, Serial logs show `[Mock] SLEEP PAD MOCK ACTIVE` + scenario transitions (deferred — hardware smoke test)
- [x] Git commit

## Success Criteria

- **Build:** `pio run -e esp32dev-mock` → SUCCESS; flash Δ <2KB vs `esp32dev` baseline
- **Production untouched:** `pio run -e esp32dev` still SUCCESS with zero byte size change
- **Runtime (smoke test):**
  - Serial shows `[Mock] SLEEP PAD MOCK ACTIVE`
  - Every 1s: `[0x85]` line logged (existing parser callback)
  - Every 60s: `[0x86]` line logged
  - At t≈2:00 mark: status codes switch to MOVEMENT, resp_disorder increments
  - At t≈3:00 mark: HR readings jump to 130+
  - At t≈4:00 mark: logs go silent (Offline scenario) for ~70s
  - At t≈5:10 mark: logs resume (NormalSleep2)
- **Downstream (after provisioned + MQTT connected):**
  - Backend `sec_data` rows appear every 1s for device
  - Backend `min_data` rows appear every 60s
  - Alert engine fires `hr_high` alert at ~3:15 mark (default threshold 120)
  - App Home shows offline indicator during 4:00–5:10 window (Redis TTL expired)

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Frame byte layout wrong → parser drops frames silently | Reference Legact Pro V2 spec PDF + existing parser code; log 1st decoded frame's fields to Serial and eyeball |
| Random walk drifts outside realistic range | `constrain(hr, 30, 180)` + `constrain(rr, 5, 40)` at each step |
| Blocking tick stalls mqtt_loop() | Strict `millis()` comparison, no `delay()`; each `mock_tick` returns quickly when nothing due |
| `esp32dev-mock` env mis-inherits → base env changes leak in | Test both env builds separately before commit |
| Offline scenario behaves unexpectedly (ESP32 still TCP-connected) | Documented caveat — Redis TTL still expires so app offline-banner path works |

## Security Considerations

None significant — mock build only flashed in dev, no user-facing data affected. If mock build accidentally flashed to a production unit, generated data would just look fake until firmware reflashed. No secrets involved.

## Next Steps

1. Implement per this phase
2. Flash ESP32 with `esp32dev-mock` build
3. Follow earlier local smoke-test runbook (brainstorm `brainstorm-260421-1541-*` if written, else walk through manually):
   - Backend Docker stack up
   - iPhone + Mac same WiFi
   - Flutter iOS build + install
   - Register/login, BLE provision the mock-firmware ESP32
   - Observe scenarios unfold over ~5 minutes
4. Journal findings — any scenario needs tuning, any downstream bugs exposed by the mock
