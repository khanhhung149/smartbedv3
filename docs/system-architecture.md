# System Architecture — SmartBed v3

- **Status:** DRAFT — needs Michael's approval (Phase 00 definition of done)
- **Date:** 2026-07-13
- **Source:** onboarding meeting 13/07 (`docs/meetings/260713-1259-onboarding-khanh-hung-smartbed-v3/`)
- **Supersedes:** the 2023 spec PDF, which is stale

---

## 1. The positioning drives the architecture

SmartBed is a **framework**, not a bed. That is not marketing — it is a structural constraint, and it produces three architectural requirements that would otherwise look like over-engineering:

1. **Every input and output is addressable from outside.** If a capability cannot be named, discovered, and invoked by a third party, it does not exist as far as the framework is concerned. This is why there is a capability manifest (§5) rather than a hardcoded app.
2. **Every data channel is recorded, including ones nothing consumes today.** A developer two years from now will need a signal we did not think to use. Disk is cheaper than data we failed to capture. Channels get cut only when they are *physically wrong* or *break non-contact* — never for being "unused".
3. **Control is expressed as intent, not as motor commands.** "Too bright", "a bit warm" — the AI resolves intent into actions against the capability manifest. This is why the public surface is a set of described capabilities, not an RPC list.

---

## 2. Three tiers

| Tier | Runs on | Job | Hard constraint |
|---|---|---|---|
| **Safety / real-time** | ESP32 | Actuators, e-stop, stall detection by current, interlocks, watchdog | Does not depend on Linux. If Linux dies, this tier is still safe. One MCU family only. |
| **Perception / AI** | Jetson Orin | Sensor ingest, signal processing, MediaPipe Pose on GPU, sleep staging, intent resolution | **May not command motion.** Sends *requests*; the ESP32 may refuse. |
| **UX / Cloud** | Tablet (Flutter), K8s | Display, reports, user profile, template loading | Offline-first. No network must never mean no sleep. |

### 2.1 Why Linux may not drive an actuator

Linux is not a real-time OS. A kernel stall of 200 ms is ordinary and unremarkable — unless an actuator is pressing down on a sleeping person, in which case it is an injury. No amount of careful Python removes this; it is a property of the scheduler.

So the boundary is drawn at the hardware level. The ESP32 owns motion. Jetson may only *ask*.

Three things the ESP32 must still do with Linux completely hung:

1. **Emergency stop**
2. **Stall detection** (current spike → stop and reverse)
3. **Hold position on power loss**

If a design change would break any of those three, the design change is wrong.

---

## 3. The mechanical handler

There is exactly **one** module that touches an actuator: the handler, in `firmware/mech-handler/`. Nothing else in the system — not Jetson, not the app, not a template, not a developer's plugin — may address a motor directly.

Safety logic lives **inside** the handler, not scattered across callers. A caller cannot forget to check something it never had access to.

```
Jetson (Linux)              ESP32 handler (real-time)          Actuator
    │                              │                               │
    │  "raise head plate to 40%"   │  Checks, in order:            │
    ├──── posture request ────────►│   1. watchdog alive?          │
    │                              │   2. person asleep?           │──► PWM / H-bridge
    │                              │   3. beyond soft limit?       │
    │◄──── ACCEPT / REJECT ────────┤   4. current abnormal?        │◄── current (ADC)
    │      (+ reason)              │   5. commands flooding?       │◄── encoder (position)
    │                              │                               │
    │                              │  E-STOP ──────────────────────┤  (cuts power in hardware,
    │                              │                               │   not through software)
```

The handler holds **veto power**. Linux hung, disconnected, or compromised still means the actuator sits still.

### 3.1 Position feedback and auto-calibration

The system must know *where it is* (as a percentage), not merely that it is moving. Encoders provide this.

**Auto-calibration pattern** (proven in production on Michael's home automatic-door system):

> If an actuator **stops on its own** — not because anyone commanded a stop — while within the outer **15%** of its travel, that stop *is* the physical limit. Sync that position to 0% or 100%.

This removes limit switches and manual calibration entirely. If the encoder drifts a few percent, the next contact with the end of travel corrects it. Algorithm replacing hardware: cheaper, and fewer things to break.

### 3.2 Default: no automatic motion while someone is asleep

In v3, automatic motion is **forbidden while the person is asleep**. Adjustment happens only while they are awake, or on an explicit command. Closed-loop anti-snore posture (Phase 06) does not change this default — it must earn an exception with evidence, and it must be gated by the safety record.

---

## 4. The link between Jetson and ESP32

Transport: **UART** to start (CAN if noise or multi-node addressing demands it later — the framing below survives either).

This is a two-way, asynchronous, framed protocol. It is deliberately boring.

### 4.1 Frame

```
┌──────┬──────┬──────┬─────────┬──────────────┬────────┐
│ SOF  │ TYPE │ LEN  │  SEQ    │   PAYLOAD    │ CRC16  │
│ 0xA5 │ 1 B  │ 1 B  │  1 B    │   0-255 B    │  2 B   │
└──────┴──────┴──────┴─────────┴──────────────┴────────┘
```

- `SEQ` — wraps at 255. Lets each side detect loss without a retransmit protocol.
- `CRC16` — CCITT, over `TYPE..PAYLOAD`. A corrupt frame is dropped, never guessed at.
- Unknown `TYPE` is ignored, not fatal. This is how the protocol stays extensible.

### 4.2 Message types

| Type | Direction | Meaning |
|---|---|---|
| `0x01 SENSOR_FRAME` | ESP32 → Jetson | One 10 Hz sample (§6) |
| `0x10 POSTURE_REQUEST` | Jetson → ESP32 | Requested plate positions, in % |
| `0x11 POSTURE_VERDICT` | ESP32 → Jetson | ACCEPT, or REJECT + reason code |
| `0x12 MOTION_STATE` | ESP32 → Jetson | Live position %, current draw, moving/idle/faulted |
| `0x20 HEARTBEAT` | Jetson → ESP32 | Liveness, every 200 ms |
| `0x21 FAULT` | ESP32 → Jetson | E-stop hit, stall, over-current, limit breach |

### 4.3 Watchdog

Jetson sends `HEARTBEAT` every **200 ms**. If the ESP32 sees no heartbeat for **500 ms**, it stops all motion. Not "reduces speed" — stops.

Verification: pull the UART cable out mid-lift. Motion must stop.

### 4.4 Rejection is normal, not exceptional

`POSTURE_VERDICT` returning REJECT is an ordinary outcome and the Jetson side must treat it as such. Every reject carries a machine-readable reason (`ASLEEP`, `SOFT_LIMIT`, `OVERCURRENT`, `FLOODING`, `WATCHDOG`, `ESTOP`, `FAULTED`). A caller that retries blindly on reject is a bug — and the handler's flood protection will throttle it anyway.

---

## 5. The public contract — what makes this a framework

Internal bus on the Jetson: **MQTT**. External surface: **REST + WebSocket** over that bus, plus a **capability manifest**.

Home Assistant and Node-RED are deliberately **not** used. They are strong tools, but they assume a human drags boxes around to build automations. The target here is AI resolving intent, and HA would become an obstacle. (Michael has run the replacement pattern in production at home: MQTT + AI function-calling, driving lights, aircon, and doors from natural speech.)

### 5.1 Addressing

Every input and output has a stable address:

```
smartbed/sensor/radar/presence
smartbed/sensor/radar/respiration_rate
smartbed/sensor/piezo/bcg
smartbed/sensor/env/co2
smartbed/actuator/plate/head/position
smartbed/actuator/light/scene
smartbed/actuator/fan/speed
```

### 5.2 The capability manifest

Each capability is declared once, in a machine-readable descriptor: address, type, unit, range, whether it is readable/writable, and **a natural-language description**.

That description field is not documentation garnish — it is what lets an LLM enumerate what the bed can do and resolve "it's too bright in here" into a write against `smartbed/actuator/light/scene`. The manifest **is** the function-calling schema. This is the single mechanism that serves the open API, the AI autopilot, and the template platform at once.

```jsonc
{
  "address": "smartbed/actuator/fan/speed",
  "type": "number",
  "unit": "percent",
  "range": [0, 100],
  "access": "rw",
  "description": "Extraction fan speed. Raises air exchange and lowers CO2.",
  "constraints": ["software may only INCREASE this value; it may never switch the fan off"]
}
```

### 5.3 Constraints are part of the contract

Note the `constraints` field above. Ventilation is the worked example: **software may only raise fan speed, never turn the fan off.** A sealed pod with a person breathing in it is a CO₂ hazard, and no template, plugin, or AI intent may ever be allowed to express "turn off the ventilation".

Safety rules of this kind belong in the contract, where they are enforced for every caller, rather than in each caller's good intentions.

### 5.4 Templates

Templates are **plain text**, not code — the whole point is that a person who is not a programmer can write one. AI converts the text into system logic expressed against the capability manifest.

A template can therefore only ever do what the manifest permits. Template capability and system safety are enforced at the same boundary, which is why the manifest carries constraints rather than the template engine carrying a sandbox.

---

## 6. Sensor data flow

ESP32 samples at a **fixed 10 Hz**, timestamps **at the MCU** — never at Linux, whose clock and scheduling cannot be trusted for this — and ring-buffers to survive Linux being busy.

The record schema matches the take-home CSV exactly, so the simulated 10 Hz data already exercised by the recruiting exercise is drop-in replaceable with real data:

```
t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity
```

**Dropouts are marked, never invented.** A sensor dropout is written as an explicit sentinel (e.g. `hr_bpm = 0`), so downstream can always distinguish measured from missing. Fabricating a plausible value to keep a chart smooth destroys the dataset for the AI work that is the entire point of collecting it.

Persistence: SQLite to start (TimescaleDB if volume demands). Rotate per night, compress, keep the last 30 nights locally.

### 6.1 Sensors

| Sensor | Bus | Position | Yields |
|---|---|---|---|
| HLK-**LD2510B** radar, 24 GHz | UART | Head of bed, aimed down | Presence, **true position**, **multi-person tracking**, respiration amplitude, coarse heart rate |
| **Piezoelectric pad** | ADC | Under mattress, torso | Presence, BCG, movement, turning over |
| SHT10/31 | I2C | In pod, out of the breath stream | Temperature, humidity |
| **Omnidirectional mic** | I2S | Head of bed | Breathing, snoring, ambient noise |
| CO₂ | I2C | In pod | Ventilation interlock (§5.3) |
| **ESP32-CAM (OV2640) + VL53L0X** | SCCB (I2C, shared with camera config) | Aimed at sleep area | Behavior video (JPEG frames, bench-test only, local SD — not synced to this pipeline), distance-to-person |

Two upgrades from the 2023 spec worth stating plainly, because they are easy to "correct" back by mistake:

- **LD2510B, not LD2410B.** The 2410B reports only an approximate distance. The 2510B tracks **several people at once with true positions** — required for a double bed, and for telling a person lying down apart from a person walking past.
- **Piezo pad, not a 150 kg loadcell.** The piezo yields BCG, which a loadcell cannot, and does not drift with temperature. Cheaper and simpler to mount.

A third change, decided 2026-08-13 and out of scope for this file's original 13/07 sign-off: the **Thermal / MLX90614** row above is replaced by the camera node. The original cluster's real purpose was observing sleep behavior, not measuring temperature — an MLX90614 cannot substitute for that, and an RGB camera cannot measure temperature. See `plans/260813-0934-esp32cam-vl53l0x-camera-node/` for the full decision record. **This channel does not go through the MQTT bus or the capability manifest (§5)** — video stays on the node's own local SD card, and only during the engineer bench-test period (never once a real user is on the bed, matching the five privacy rules in Phase 05).

---

## 7. Cut from the spec — and why

Recorded so nobody re-proposes them in three months. Full reasoning in `plans/260713-1019-smartbed-v3-mvp/phase-07-deferred-oxy-eeg-huyet-ap.md`.

| Cut | Reason |
|---|---|
| **Oxygen concentrator** | 96% O₂ in a sealed pod makes ordinary materials readily flammable, next to power supplies, an LCD, and motors. A 500 ml extinguisher is not a risk control. |
| **Non-contact EEG through the pillow** | The source paper measures 2 µVrms at **0.2 mm**. Through a pillow and hair is centimetres. The SNR collapses. Research-grade, not MVP-grade. |
| **Blood pressure (MPS20N400D)** | Wrong component — it is an industrial gas pressure sensor. It cannot measure blood pressure. |
| **MAX30102 (SpO₂)** | Requires skin contact, which breaks the non-contact premise. If genuinely needed: a detachable accessory. |
| **MQ303B** | Measures alcohol. Contributes nothing to sleep. |
| **Coral USB** | Redundant with the Jetson; constrains models to int8 TFLite. |
| **Blockchain / NFT / token** | Solves no customer problem and creates legal exposure. |
| **10-point lift** | v3 ships 3 plates. Reopen when data shows 3 is insufficient. |

---

## 8. Open questions

1. Transport: UART or CAN? UART to start; the frame format survives the switch. Revisit if electrical noise from the actuators corrupts frames.
2. Storage: SQLite or TimescaleDB? Start with SQLite; migrate on measured volume, not on speculation.
3. BOM ceiling is unset (see the handoff brief). Component choices are provisional until Michael sets it.
4. Music copyright (thầy Nguyên Minh) is **not cleared**. Cannot ship audio content until it is.
