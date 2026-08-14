# Hazard Analysis — SmartBed v3

- **Status:** DRAFT — needs Michael's approval (Phase 00 definition of done)
- **Date:** 2026-07-13
- **Scope:** every way this machine can hurt the person lying on it

---

## Why this document exists

SmartBed puts motors, mains power, heat, and a sealed air volume around a person who is **unconscious and cannot protect themselves**. A sleeping user will not pull their hand out of a pinch point, will not notice CO₂ rising, and will not hear an alarm.

That is the entire reason for the architecture in `../system-architecture.md`. Every constraint there traces back to a row in the table below.

**Severity scale**

| | Meaning |
|---|---|
| **S1** | Can kill or permanently injure |
| **S2** | Can injure — medical attention needed |
| **S3** | Harm, discomfort, or product failure without lasting injury |

---

## Mechanical — motion, crushing, entrapment

| ID | Hazard | Sev | Mitigation | Phase | Verify |
|---|---|---|---|---|---|
| **H-01** | Plate lifts while the person is **asleep** and crushes or bends them into an unsafe posture | **S1** | Automatic motion is **forbidden while asleep** — the default, not an option. Handler enforces it, so no caller can bypass it. Motion only while awake or on explicit command. | 04 | Simulated sleep state in the state machine; handler must reject `POSTURE_REQUEST` with `ASLEEP` |
| **H-02** | Hand, arm, or leg **pinched between two adjacent plates** at their boundary | **S1** | Collision simulation in CAD across *every* combination of plate positions, before steel is cut. Soft limits by combination, not per-plate. Current-based stall detection. | 04 | Insert a block of wood at every plate boundary; actuator must stop <200 ms and reverse |
| **H-03** | Limb, bedding, or a pet **caught under a plate edge** as it descends | **S1** | Current-based stall detection on every channel. Sudden current spike = obstruction → stop and reverse. Slow speed keeps the energy low enough for detection to act in time. | 04 | Obstruction test at every plate, every direction |
| **H-04** | **Power loss mid-lift** — plate free-falls onto the person | **S1** | Self-locking lead-screw or ball-screw mechanism. No pneumatics, no hydraulics — they leak, they lose pressure, they drop. Locking is mechanical, not electrical. | 04 | Cut power abruptly under 100 kg load; drop must be <5 mm |
| **H-05** | **Linux hangs mid-motion**; actuator keeps running | **S1** | ESP32 watchdog. No heartbeat for 500 ms → all motion stops. ESP32 does not depend on Linux to be safe. | 04 | Pull the UART cable mid-lift |
| **H-06** | **Command flooding** — a buggy plugin, template, or AI loop drives erratic motion | **S2** | Handler throttles internally. Flood protection lives *inside* the handler, not in callers. | 04 | Fire 1000 commands/sec at the handler; must throttle, not thrash |
| **H-07** | **Encoder drift** — system believes it is at 40%, is actually at 70%, drives past the physical limit | **S2** | Auto-calibration: an uncommanded stop within the outer 15% of travel *is* the limit → resync to 0/100%. Plus hard mechanical stops as a physical backstop. Soft limit and hard limit are independent layers. | 04 | Deliberately desync the encoder; system must self-correct on the next limit contact |
| **H-08** | **E-stop out of reach** of the person lying down — useless in the one situation it exists for | **S1** | E-stop must be **within reach of someone lying on the bed**. It cuts actuator power **in hardware**, not through software. | 04 | Press it from a lying position; oscilloscope must show power gone <100 ms |
| **H-09** | **Frame collapses** under load | **S1** | Static load 150 kg with a safety factor of at least 2. Force and travel **recomputed from scratch** for the 3-plate design — the 2023 figures (500 N / 50 cm) describe a 10-point design and mean nothing here. | 04 | Load test to design limit before anyone lies on it |
| **H-10** | Actuator **noise wakes the sleeper** — the product defeats its own purpose | **S3** | Small arc, slow speed, low noise as hard requirements. Measure real dB **at head position**, not at the motor. Do not trust the datasheet. | 04 | dB meter at the head of the bed |

---

## Air, heat, and entrapment in the pod

| ID | Hazard | Sev | Mitigation | Phase | Verify |
|---|---|---|---|---|---|
| **H-11** | **CO₂ accumulates** in the sealed pod through the night | **S1** | Extraction fan + membrane + CO₂ sensor. Continuous monitoring. | 03 | CO₂ <1000 ppm after 8 h of a real person sleeping with the pod closed |
| **H-12** | Software, a template, or AI intent **switches the ventilation off** | **S1** | Physically impossible to express: the capability contract lets software **only increase** fan speed. "Turn the fan off" is not a representable command for any caller. Enforced at the contract boundary, not by caller discipline. | 03 | Attempt to write fan speed to 0 through the API, a template, and an AI intent; all three must be rejected |
| **H-13** | **Door / lid locks shut** and traps the person, especially during a power cut | **S1** | Lock is **fail-open**: loss of power releases it. It cannot latch someone in. | 03 | Cut power with the lid closed; it must release |
| **H-14** | **Thermal runaway** — heating or cooling drives the person to hyperthermia or hypothermia while asleep | **S2** | Hard temperature bounds in firmware, not just in software. Independent over/under-temperature cut-out that does not route through the AI tier. | 03 | Command an out-of-range temperature; firmware must clamp it |
| **H-15** | **Condensation** from the monoblock aircon drips onto electronics | **S2** | Drainage designed in; electronics mounted above any condensation path; IP-rated enclosures in the wet zone. | 03 | Run cooling at maximum against high humidity; inspect |
| **H-16** | **Negative ion generator produces ozone** — a respiratory irritant in a sealed volume | **S2** | Select an ion generator with a verified low ozone output. Measure ozone in the pod under real running conditions. *Note: an ion generator is a completely different device from an oxygen concentrator.* | 03 | Ozone measurement inside the closed pod |

---

## Electrical and fire

| ID | Hazard | Sev | Mitigation | Phase | Verify |
|---|---|---|---|---|---|
| **H-17** | **Electric shock** — mains power beside a person, in a humid enclosure | **S1** | RCD/RCBO protection. Mains isolated from the occupant zone. Only low voltage in reach. Proper earthing. | 00/04 | Insulation and earth-continuity testing |
| **H-18** | **Oxygen-enriched atmosphere makes ordinary materials flammable** — beside power supplies, a display, and motors | **S1** | **The oxygen concentrator is cut.** This is not mitigated; it is designed out. At 96% O₂ in a sealed pod, materials that do not normally burn readily will. A 500 ml extinguisher is not a risk control. | — (cut) | Not applicable — the device is not in the system |
| **H-19** | **Actuator driver or PSU overheats and ignites** | **S1** | Current limiting per channel. Thermal cut-outs. Fused supplies. Derate against continuous-duty ratings, not peak. | 04 | Thermal imaging during the 500-cycle load test |
| **H-20** | Boards **powered from a laptop** brown out, causing random faults that appear as ghost bugs and are never root-caused | **S2** | **Always give circuits their own power supply. Never power a board from a laptop.** This is a standing rule for the whole project, not per-phase advice. | all | Bench discipline; review |

---

## Information — the hazards that are not physical

| ID | Hazard | Sev | Mitigation | Phase | Verify |
|---|---|---|---|---|---|
| **H-21** | A user reads "apnea detected" as a **medical diagnosis**, trusts it, and does not see a doctor. Or the inverse: the bed reports nothing, and they ignore genuine symptoms. | **S1** | **Wellness device. No medical claims.** Every metric is labelled *"tham khảo, không dùng chẩn đoán"*. The words "diagnose", "measure blood pressure", and "detect disease" appear nowhere in the UI or marketing. A sleep-medicine advisor must review any health claim before publication — **that role has been vacant since 10/2025.** | 02 | Copy review of every metric surface |
| **H-22** | **AI misresolves intent** — "I'm cold" leads to a dangerous action | **S2** | AI may only act through the capability manifest, whose declared constraints bound every action. The AI cannot exceed the contract, because it has no path around it. Motion intents remain subject to the handler's veto. | 06 | Adversarial intent tests against the manifest |
| **H-23** | **Biometric sleep data leaks** — heart rate, breathing, and presence, per night, per identifiable person | **S2** | Recorded data never enters git (`.gitignore` blocks it). Encrypt at rest. Offline-first: the bed works with no cloud at all. Get explicit consent before anything is uploaded. | 01/06 | Security review before the cloud tier ships |
| **H-24** | An engineer **disables a safety check to get a demo working** and it never gets re-enabled | **S2** | Safety logic lives inside the handler and the contract, where turning it off is a visible, reviewable code change — not a config flag or a commented-out line in a caller. | all | Code review; the safety gate below is signed, not assumed |
| **H-25** | **The camera node's live video stream** (ESP32-CAM serving MJPEG over HTTP, bench-test only — see `plans/260814-1237-esp32cam-stream-mediapipe-poc/`) is mistaken for a shipped production policy, or is opened by any other device on the LAN — the stream has no authentication. | **S2** | **The firmware has no storage tier at all** — no SD, no filesystem, no `fopen`. Frames exist only in flight and are gone when the board loses power, so there is nothing to leak after the fact and no build flag to get wrong. The node runs only on the isolated bench network, only during the engineer bench-test period, never with a real user on the bed. It is powered off when not actively in use. | amendment camera-node (01) | `grep -ri "sdmmc\|fatfs\|f_open\|fopen\|esp_vfs" firmware/esp32cam-stream/src/` → zero results; board physically unpowered outside test sessions |

---

## Retired hazards

A hazard leaves this document only when the thing that caused it is gone from the design. Removals are recorded here so a reader who remembers an ID can find out what happened to it — and so anyone who reintroduces the hardware knows exactly which hazard comes back with it.

| ID | Was | Retired | Why — and what brings it back |
|---|---|---|---|
| **H-26** | The camera node's flash LED flickers during sleep. On the AI-Thinker ESP32-CAM, GPIO4 drives the white flash LED and was also the only pin left for VL53L0X's I2C SDA line (confirmed 13/08: every other header pin was claimed by SD/I2C, GPIO12 unsafe as a boot-strapping pin, GPIO16 taken by PSRAM). Every I2C transaction toggled SDA and visibly flickered the LED — not a code bug, not disableable in firmware. Mitigation had been: physically remove the LED or its resistor before any board runs near a sleeping person. | 2026-08-14 | **VL53L0X was dropped from the design** (see `plans/260814-1237-esp32cam-stream-mediapipe-poc/`). With no I2C on the node, GPIO4 is never toggled and the LED stays dark. **If VL53L0X — or any I2C device on GPIO4 — is ever added back to an AI-Thinker board, H-26 returns unchanged and its hardware mitigation is mandatory again.** |

---

## Safety gate — no shortcuts

Nobody lies on this bed until **all six** pass:

1. Dummy load (100 kg sandbag) — **500 cycles, zero faults**.
2. E-stop cuts actuator power in **<100 ms**, verified on an oscilloscope. Button **within reach of the person lying down**.
3. Stall detection by current: obstruct every plate → actuator stops **<200 ms** and reverses.
4. Abrupt power loss: actuator holds. **No free fall.** Door lock **fails open**.
5. CO₂ **<1000 ppm** after 8 h with a person sleeping and the pod closed.
6. Checklist **signed by name**, stored in `docs/safety/`.

**The first person to lie on this bed is an engineer, not a customer.**

---

## Open questions

1. Sleep-medicine advisor **vacant since 10/2025** (GS Dương Quý Sỹ). H-21 cannot be fully closed without one. Blocks any public health claim.
2. Is an RCBO already present in the lab supply, or does it need to be specified into the BOM? (H-17)
3. Ozone limit for the ion generator — which standard do we hold it to? (H-16)
4. Who signs the safety gate — Michael, or an external assessor?
