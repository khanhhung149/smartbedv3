# Sensor Characterization — SmartBed v3

- **Status:** live document, filled in as each cluster is bench-tested
- **Started:** 2026-08-14

## What belongs here

**Measured numbers only.** Every figure in this file must trace back to a real reading from real hardware: what was measured, under what conditions, with what method.

A datasheet figure is not a measurement. An estimate is not a measurement. If a number has not been measured yet, the row says **not measured** — it does not say a plausible-looking guess.

This rule exists because it was broken. The previous camera node planned around "~35 KB/frame assumed, not yet measured", and the assumption turned out to matter. A number nobody measured, written down without a label, becomes a fact nobody questions.

Sensors are listed as they get characterized. Most of Phase 01's clusters are still missing.

---

## ESP32-CAM stream node (OV2640)

- **Firmware:** [`firmware/esp32cam-stream/`](../firmware/esp32cam-stream/README.md)
- **Role:** behavior observation for the vision PoC. Bench-test only, never with a real user on the bed (hazard H-25)
- **Measured:** 2026-08-14

### Configuration

| | |
|---|---|
| Sensor | OV2640, AI-Thinker ESP32-CAM board |
| Resolution | VGA 640×480 |
| Encoding | JPEG, quality 12 (0–63 scale, lower = better) |
| Frame buffers | 2, in PSRAM (61440 B each) |
| Transport | MJPEG over HTTP, `multipart/x-mixed-replace`, port 81 |
| Storage | **none** — no SD, no filesystem. Frames exist only in flight |

**One stream client at a time.** The board serves the HTML page (port 80) and the stream (port 81) from two separate HTTP servers, so viewing in a browser no longer blocks the page — but two *stream* readers still cannot coexist. A second reader gets a connection that never delivers data. Close the browser tab before running the PoC.

### Throughput

Measured by counting JPEG start/end markers on the client side over a continuous window. Not derived from the datasheet, not extrapolated.

| Condition | fps | Frame size | Bandwidth |
|---|---|---|---|
| Stream only, empty scene (ceiling), 30 s | 20.3 | 10.0 KB avg (9.9–10.1) | 204 KB/s ≈ 1.67 Mbit/s |
| Stream only, **person in frame**, 25 s | **23.9** | **15.7 KB** avg (11.6–17.2) | 378 KB/s ≈ 3.10 Mbit/s |
| Stream + serving the HTML page on port 80 | 23.2 | not measured | not measured |
| Stream + Pose inference, **empty scene**, 5.5 min | 22.8 | — | — |
| Stream + Pose inference, **person in frame**, 40 s | **8.7** | — | — |

A person in frame makes each JPEG **57% larger** (10.0 → 15.7 KB) and far more variable, because there is real detail to encode instead of a flat wall. The node itself does not slow down — it still pushes ~24 fps.

**Pose inference is the bottleneck, not the camera and not WiFi.** The two rows above make this unambiguous: with a person in frame the stream alone runs at 23.9 fps but the same stream with inference attached drops to 8.7 fps.

This is easy to get backwards. The 22.8 fps measured against an empty ceiling looks like proof that inference is cheap — it is not. With nothing to detect, the model bails out early; with a real person it runs the full 33-landmark regression. **Any figure measured against an empty scene says nothing about inference cost** and must not be quoted as a performance budget.

8.7 fps is still ample for observing sleep posture, where a person changes position over seconds, not milliseconds. It would not be enough for fast motion.

For contrast, the previous node (`esp32cam-node`, SVGA, writing to an SD card) managed ~1.5 fps. The bottleneck was the SD card, not the camera and not WiFi.

### Reliability

| | Result |
|---|---|
| Continuous run, stream + inference | 5.5 min, 7509 frames, **0 read failures**, no crash, no hang |
| Pose detection rate, person in frame | **343/347 frames (99%)**, 33 landmarks each |
| Recovery after the node reboots mid-stream | dropout detected in 3.0 s, reconnected, stream alive ~1 s later |

Note on that 3.0 s: OpenCV's FFMPEG backend defaults to a **30 second** read timeout, and it ignores the timeout when set via `cap.set()` after opening — it must be passed to the `VideoCapture` constructor. Measured both ways: 30.1 s versus 3.0 s. Any client reading this stream needs the same treatment, or it will keep showing a frozen frame for half a minute while believing all is well.

### Network conditions during measurement

| | |
|---|---|
| Band | 2.4 GHz (the ESP32 cannot use 5 GHz) |
| RSSI | −64 dBm |
| Security | WPA2-PSK |
| Channel | 13, BW20 |

### Not measured yet

- **End-to-end latency** (photons → pixels on screen). Needs a person or a moving reference in frame to have anything to compare against.
- **Full-body framing.** The person-in-frame figures above were measured with the camera aimed at a head and shoulders from close range, not at a whole body from above a bed. Landmark quality for actual sleep postures is still unmeasured.
- **Low-light behavior.** See the vision pipeline risks in [`system-architecture.md`](system-architecture.md): the OV2640 has no IR, so this is expected to fail rather than degrade, and that expectation itself is still unmeasured.
- **Thermal behavior over a full night.** The node has only ever run for minutes at a time.

---

## Other Phase 01 clusters

Not characterized yet: LD2510B radar, piezoelectric pad, SHT10/31, omnidirectional mic, CO₂ sensor.

Add one section per cluster using the shape above: configuration, measured throughput, reliability, conditions during measurement, and an explicit list of what remains unmeasured.
