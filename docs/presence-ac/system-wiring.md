# System Wiring — Physical GPIO Pinout & Hazards

**Last Updated**: 2026-08-18  
**Scope**: Physical hardware assembly only — GPIO pins, power connections, soldering hazards, electrical constraints. For software architecture (MQTT topics, state machines, API contracts), see [`docs/system-architecture.md`](./system-architecture.md).

---

## What Changed from Previous Doc

The old `docs/system-wiring.md` (2026-07-24 rev4) claimed **"2 boards WiFi + shared power (S2 was
board source)"** — power is now independent per board, which is the part that still matters.

Board count went 2 → 4 → 2 again: `room-node` (ESP-NOW relay) and `door-node` (PIR) were retired
2026-08-18 and their firmware deleted. Presence comes from `radar-node` alone, motion from its
LD2410 UART. If returning from git history, ignore both the old shared-power topology and the
4-board one.

---

## System Overview: 2 Independent ESP32 Boards

Each board runs on its own USB-C power. **No hardwired inter-board power sharing** (old 2-board shared 5V is gone).

| Board | Microcontroller | Sensors | Power | Communication |
|-------|---|---|---|---|
| **voice-node** | ESP32-S3-DevKitC-1 N16R8 | INMP441 mic, IR transmitter | USB-C 5V | WiFi + MQTT (audio to backend WS) |
| **radar-node** | Wemos S2 Mini | LD2410C radar | USB-C 5V | WiFi + MQTT (native UART to sensor) |

---

## Pin Tables by Node

### Board 1: Voice-Node (ESP32-S3-DevKitC-1 N16R8)

**Environment**: `firmware/voice-node/platformio.ini`  
**Source**: `firmware/voice-node/src/main.cpp` lines 1–68

The WROOM-32 board and its `esp32dev` env were dropped 2026-08-18; GPIO4 remains the code default for IR
but every build now overrides it to GPIO8 (see `platformio.ini`).

#### I2S Microphone (INMP441)

| INMP441 Pin | → ESP32-S3 GPIO | Notes |
|---|---|---|
| **SCK** (BCLK, clock) | **GPIO5** | I2S bit clock output from ESP |
| **WS** (LRCL, word select) | **GPIO6** | I2S frame sync output from ESP |
| **SD** (DOUT, serial data) | **GPIO7** | I2S data in from mic (input-only safe) |
| **L/R** (channel select) | **GND** | Selects left channel; **do not change** |
| **VDD** (power) | **3V3** | **NEVER 5V** — destroys mic preamp |
| **GND** | **GND** | Audio return path |

**Why these pins on S3?**  
GPIO map of ESP32-S3 differs from ESP32 classic:
- GPIO22–25 do not exist
- GPIO26–32 are SPI flash bus (reserved)
- GPIO33–37 are PSRAM octal (reserved)

WROOM-32 used GPIO26/25/34 — all forbidden on S3. Pins 5/6/7 are safe across all S3 variants.

**CFG_I2S_CHAN**: Defaults to `I2S_CHANNEL_FMT_ONLY_RIGHT` (microphone drives right channel only, with L/R tied to GND). Verified 2026-07-30: `ONLY_LEFT` on S3 measured RMS=0.0 absolute (with SD pulldown in code) → mic is not driving left. **Do not switch**.

#### IR Transmitter (Daikin AC Control)

| Pin | → ESP32-S3 GPIO | Notes |
|---|---|---|
| **IN** (signal) | **GPIO8** | IR modulation output (3.3V logic) |
| **VCC** (power) | **5V** | Module is rated 5V (gives 1–2m range) |
| **GND** | **GND** | |

**Why GPIO8?**  
- GPIO4 is the default (safe on both WROOM and S3).
- On this specific board (ESP32-S3-CAM N16R8), GPIO4–7 are on the camera header with tight pin spacing → hard to hand-solder.
- GPIO8 sits in a normal GPIO row → easier soldering.
- GPIO8 is not a strapping pin and not reserved.

**IR Module**: diymore PCB0100 (2-channel, 940nm, 5V-rated). Used as 1-signal module: both LEDs tied to single IN pin (GPIO8). Unmodified.

#### Strapping Pins (Boot Constraints)

| Pin | Status | Constraint |
|---|---|---|
| **GPIO0** | Strapping | Must be HIGH at boot (internal pullup) or BOOT pin held. If pulled LOW at boot → bootloader mode. |
| **GPIO3** | Strapping | Must be HIGH at boot (internal pullup). Low level → download mode. |
| **GPIO45** | Strapping | Must be HIGH at boot. Low level blocks boot. |
| **GPIO46** | Strapping | Must be HIGH at boot. Low level blocks boot. |

**Implication**: Do not use GPIO0, 3, 45, 46 for peripherals that actively pull LOW at runtime. IR LED pulling GPIO to LOW = board will not boot.

---

### Board 2: Radar-Node (Wemos S2 Mini, ESP32-S2)

**Source**: `firmware/radar-node/src/main.c` lines 1–22 (ESP-IDF thuần) + `src/ld2410.c` (parser UART)  
**Sensor**: LD2410C 24GHz millimeter-wave radar

#### LD2410C Wiring

| LD2410C Pin | → S2 GPIO | Notes |
|---|---|---|
| **OUT** (presence digital) | **GPIO16** | HIGH when target detected (INPUT_PULLDOWN in firmware) |
| **TX** (data transmit) | **GPIO35** | Radar sends data at 115200 baud (connect to S2 RX). Was GPIO33 until 2026-08-25 — that pin failed physically on this board, moved to GPIO35. |
| **RX** (command input) | **GPIO18** | S2 sends config commands at 115200 baud (S2 TX → this pin) |
| **VCC** (power) | **5V** (VBUS) | Radar requires 5V for full range |
| **GND** | **GND** | **MUST share common GND with S2** (see hazards) |

**UART Baud**: 115200 — verified 2026-08-24 via the official HLK-LD2410 BLE config app on this
exact module. NOT the 256000 datasheet default; this unit's firmware/config differs (previously
documented as 256000, wrong for this board — see Hazard #8 below).

**Protocol**:
- On boot, firmware opens the UART read-only — it never sends config commands (radar keeps its own settings)
- Firmware reads **both** OUT pin (debounced) and UART (for distance/energy) as presence signal
- UART failure: ON pin still works, only loses distance/energy diagnostics
- GPIO16 failure: firmware stops reporting presence entirely

---

## Power Supply

### Independent USB-C Per Board

```
Each board:
  Cốc sạc (≥2A) ─USB-C─► Board USB-C
                          ├─ 5V rail (powers board logic + peripheral VCC)
                          └─ GND (signal return)
```

**No inter-board power links** anymore. Each board powers itself independently.

**Why change from old "S2 as board source"?**  
Old design (2026-07-24): S2 sourced 5V to WROOM via shared wire.
- WROOM has a USB diode dropping ~0.3V → VIN only saw 4.7V → risky dropout.
- S2 native 5V = 5.0V, so it was chosen as source.
- **Reason for change**: Complicates deployment (must plug S2 first, careful cable order). Independent USB per board is simpler and safer.

### No More Shared Power Rail

- **NEVER** tie multiple boards' 5V rails together (will cause diode conflicts, slow brownout, watchdog reset).
- Each board has its own USB-C with dedicated charger or hub. Minimum 2A per port for stable 5V.
- GND is **not** shared between boards (each is isolated by its USB hub's GND).
- If a signal ever crosses boards, only the **signal GPIO** travels; power stays isolated.

---

## Hazards & Lessons Learned

All warnings below have been encountered and verified in production (not theoretical). Specific dates and symptoms included.

### 1. LD2410 Ground Must Be Shared with Host Board

**Date**: 2026-07-23 (production assembly)  
**Symptom**: `Moving=0, Static=0` in UART output, but `Detect=1` stays on. App's HLK BLE shows radar energy smooth and continuous. **UART reads garbage, BLE works fine** → not a dead sensor.

**Root cause**: Common-mode ground missing between S2 and radar module. UART is differential (needs GND return path). BLE is analog (uses its own EM coupling).

**Fix**: Solder GND wire from radar module to **the same S2 board reading it**. If powering radar from a different board's 5V, the GND return path must still come back to the sensor's I/O host.

**Universal rule**: Power a sensor from the same board that reads its GPIO/UART. Don't split power source and signal host.

### 2. IR Transmitter Module Requires 5V (Verified, Not 3.3V)

**Module**: diymore PCB0100, labeled 5V, 940nm, 1–2m range.

**Voltage**: 5V is **correct** and tested. Feeding 3.3V under-drives the LED array → short range.

- **Signal pin (IN)**: Always 3.3V logic (GPIO drives this).
- **Power pin (VCC)**: 5V supply only. Feeding 3.3V here degrades range.

**Old doc error**: An earlier revision incorrectly stated "3.3V only." That was overridden once before to 5V. **Do not regress**. Principle: module label is your spec; 5V + 3.3V logic is correct.

### 3. IR LED is Invisible to Naked Eye — Use Phone Camera to Verify

**Wavelength**: 940nm (infrared, beyond human vision).

**Verification**: Aim phone camera (most sensors show IR in near-infrared) at the LED while firmware fires. You should see faint purple/white flicker. **If you see nothing and think the circuit is dead, try the camera test first** — firmware may be firing correctly.

**Debug time saved**: Multiple hours wasted assuming "LED not lit = dead circuit" when firmware was operating fine.

### 4. Strapping Pins Block Boot

**ESP32-S3 strapping pins**: GPIO0, 3, 45, 46 (must be HIGH at boot, or board enters bootloader/download mode).

**Risk**: Peripherals that actively pull LOW → board won't boot. In voice-node, IR LED on GPIO8 is fine. **Never put IR on GPIO3 or GPIO45** (would lock board in boot failure loop).

**Verification**: After moving IR to a new pin, short-circuit the signal to GND with an external wire. If board still boots, the pin is safe. If it freezes, it's a strapping pin.

### 5. Mic Orientation: Inverted = Hears Enclosure, Not Room

**Module**: INMP441 circular Ø10 board (MEMS chip on bottom, solder pads on top).

**Type**: Bottom-port microphone (sound inlet on **same face as printed labels**, not opposite face).

**Correct orientation**:
- Solder pad face **UP** against enclosure ceiling
- MEMS chip face **DOWN** into internal cavity
- Sound inlet hole receives room sound

**Inverted orientation** (common mistake):
- Solder pad face DOWN (away from ceiling)
- MEMS chip face UP (exposed to cavity)
- Sound inlet receives only cavity acoustics, not room sound
- **Sealing gasket tighter makes it worse** (more trapped air = more cavity resonance)

**Solder blob compensation**: Solder pads are on the same face, so the joint raises that edge off the mounting surface. Use **soft 2-sided foam tape**, not a rigid printed shim — foam flexes around solder blob, rigid shims don't.

**Wire routing**: Route mic wire out through the mic bracket's side channel, **not bent around the board edge** (strain relief).

**Re-verify after changes**: Enclosure changed to v4, board changed WROOM→S3, since this note was written. Mic module itself may be unchanged, but **confirm orientation against the real enclosure before final assembly**.

### 6. No USB Power to Flashed Board While Inter-Board Cables Connected

When powering one board from another board's 5V rail (old topology, no longer used), do not plug the dependent board's USB at the same time. Two 5V sources fight each other.

**Current design (independent USB per board)**: Not an issue, but noted for historical clarity.

### 7. LD2410 Module Placement Away From USB-C Port

**Date**: Early board revisions (pre-2026-07-23)  
**Incident**: Soldering radar module directly over the USB-C port caused electrical short to 5V rail.

**Rule**: Allocate at least 5mm clearance between radar module and any USB connector. Use board layout or flexible wiring to keep the module away from the port.

### 8. LD2410 UART Silently Dead — GND Loose AND Wrong Baud, Independently

**Date**: 2026-08-24
**Symptom**: `home/room/sample` MQTT always `"uart_ok":false`, `moving_dist_cm`/`motion` stuck at
0. `presence` (OUT pin, GPIO16) kept working fine. HLK-LD2410 BLE app showed the module detecting
motion normally. App's "Chuyển động" (motion) card showed `—` forever.

**Root cause — two independent faults found in sequence, both required fixing**:
1. GND between the radar module and S2 had gone loose (continuity check confirmed open, not
   just high-resistance). A temporary raw-byte counter added to `ld2410_task()` showed
   `raw_bytes/2s=0` — literally zero bytes reaching the UART, worse than the "garbage data"
   symptom in Hazard #1 above. Re-seating/re-soldering GND brought bytes in, but frames still
   didn't decode (`uart_ok` stayed false).
2. Firmware had `RADAR_BAUD` hardcoded to 256000 (the datasheet default), but this specific
   module's actual configured baud — read directly off the module via the official HLK-LD2410
   BLE app (Bluetooth link, independent of the S2's UART) — was 115200. Changing `RADAR_BAUD` to
   match fixed decoding immediately (`uart_ok:true`, real `moving_dist_cm`/`moving_energy`
   values).

**Diagnostic method that worked**: added a temporary `ESP_LOGI` in `ld2410_task()` logging raw
byte count + last-valid-frame age every 2s. This separates "wire/GND dead" (0 bytes) from
"wire fine but baud/frame mismatch" (bytes arrive, 0 valid frames) — don't guess between these,
instrument and read the real number. Removed after diagnosis; don't leave debug logs in
production `ld2410.c`.

**Lesson**: BLE-based radar apps (HLK-LD2410 config tool) validate the sensor chip itself, NOT
the UART link to your host board — they use a completely separate radio path. A working BLE app
reading does not rule out a dead/misconfigured UART. Check the UART baud directly against the
module (BLE app config screen), don't trust the datasheet default once a module has been
field-configured or is a different revision.

---

## Physical Placement

Không có thông số khoảng cách/góc lắp đặt đã đo hoặc chốt trong repo cho mục này — mọi con số
kiểu "khoảng cách X m, góc Y°" là suy đoán chung chung, không phải số liệu đã kiểm chứng, nên bị
lược khỏi bản rewrite này để tránh lẫn với các mục hazards ở trên (những mục đó ĐỀU có ngày/số
liệu thật). Xem `docs/system-architecture.md` cho sơ đồ enclosure v4 hiện tại; nếu cần hướng dẫn
lắp đặt vật lý cụ thể, ghi lại từ lần lắp thật rồi bổ sung vào đây (đúng phong cách hazards ở trên
— có ngày, có số đo, không viết mô tả suông).

---

## Flashing Firmware

Each board has USB (TTL) for initial flashing and a fallback OTA path (WiFi).

### Voice-Node (ESP32-S3)

```bash
# USB (first time or fallback)
pio run -e esp32s3_kws -t upload

# OTA (after WiFi configured)
export OTA_PASSWORD='...'  # from include/config.h
pio run -e esp32s3_kws_ota -t upload
```

**USB caveat**: Board has two USB-C ports (TTL and OTA native). **Plug into TTL port only** (the one labeled TTL or next to the CH340 chip). Native USB port causes re-enumeration on every reset (known issue with S3-CAM).

### Radar-Node (Wemos S2 Mini)

```bash
# USB (first time or fallback)
pio run -e lolin_s2_mini -t upload

# OTA (after WiFi configured)
export OTA_PASSWORD='...'
pio run -e lolin_s2_mini_ota -t upload
```

**OTA path differs from voice-node**: radar-node runs plain ESP-IDF, which has no espota receiver.
The `_ota` env POSTs `firmware.bin` to the board's own HTTP endpoint instead (`curl`, see
`upload_command` in `platformio.ini` and `firmware/radar-node/src/ota.c`). `curl` must be on PATH.
`curl http://radar-node.local/` answers with the running build's version — a quick liveness check.

**S2 USB caveat**: Native USB port re-enumerates on reset (`ttyACM0` → `ttyACM1`). On WSL, use `usbipd attach --wsl --auto-attach --busid <id>` for auto re-attach. First upload may fail; running again usually succeeds.

## Verification Checklist After Soldering

| Check | Method | Passed? |
|---|---|---|
| **IR fires** | Aim phone camera at IR LED, watch for faint purple/white flicker while firmware runs | ☐ |
| **IR command sent** | Serial monitor on voice-node: `[ir] Daikin ON (25C)` (or `OFF`) printed — see `main.cpp` line 303 | ☐ |
| **Radar present signal** | MQTT client: `mosquitto_sub -t 'home/room/presence'` shows `{"present":true\|false}` updating | ☐ |
| **Radar UART alive** | Subscribe `tele/<DEVICE>/SENSOR`: see `"Detect":1`, `"Moving":N`, `"Static":N` values changing with motion | ☐ |
| **Missing LD2410 GND** | If `"Moving":0,"Static":0` but `"Detect":1` and BLE app shows energy smooth → **check GND wire, not dead sensor** | ☐ |
| **Presence reaches voice-node** | Serial monitor on voice-node: nod/wave near radar → `[hb] presence=1 ... seq=N` increments (`main.cpp` line 534) | ☐ |
| **Mic receives audio** | Serial monitor: speak near mic → `RMS=... nen=... nguong=600 state=LISTENING ws=up`; say "Vừng ơi" → `[wakeword] TRIGGER ... -> STREAMING` (ngưỡng 600 = `VAD_THRESHOLD_MIN`, đo thực địa 31/07 — nay dùng để cắt cuối câu và học nền nhiễu, không phải để mở stream) | ☐ |
| **Mic receives audio** (env `esp32s3_kws`, wakeword) | Serial monitor: nói "Vừng ơi" → `[wakeword] TRIGGER score=0.XXX -> STREAMING` (`main.cpp` line 596) | ☐ |
| **Voice E2E** | Nói lệnh AC rõ ràng → Serial log `[ir] Daikin ON (25C)` xuất hiện sau khi utterance kết thúc | ☐ |

---

## Related Documentation

- **`docs/system-architecture.md`**: Logical architecture, MQTT topics, state machines, API contracts (software view)
- **`firmware/voice-node/src/main.cpp`** (lines 1–68): Full hardware comments and strapping pin explanation
- **`firmware/radar-node/src/main.c`** (lines 1–22): GPIO layout and presence rules
- **`firmware/radar-node/src/ld2410.c`**: LD2410 UART frame format, offset by offset
- **`plans/260810-0843-voice-node-wakeword-gate/phase-01-*`**: IR module verification (diymore PCB0100 specs, 2026-08-10)

---

**Last verified**: 2026-08-18 by reading all firmware source files  
**Status**: Reflects current git HEAD (`master` branch)
