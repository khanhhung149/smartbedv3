# firmware/ — ESP32

**One MCU family for the whole system.** ESP32 (variants allowed: ESP32-S3, ESP8266 for light jobs like WLED). No STM32, no second MCU family — a small team cannot feed two toolchains.

This is the only tier allowed to drive an actuator, and the only tier that stays safe when Linux hangs.

| Module | Phase | Job |
|---|---|---|
| `sensor-node/` | 01 | Read sensors, timestamp at the MCU, 10 Hz fixed loop, ring buffer, push frames to Jetson |
| `esp32cam-stream/` | amendment (replaces Phase 01's "Camera nhiệt" cluster, see `plans/260814-1237-esp32cam-stream-mediapipe-poc/`) | OV2640 → MJPEG stream over HTTP on the LAN, for the vision PoC. Bench-test only. **No disk write anywhere** — no SD, no filesystem |
| `mech-handler/` | 04 | **The** mechanical handler. Position control, current sensing, stall detect, e-stop, command throttling, watchdog, auto-calibrate. Holds veto power over Linux. |

Three things this tier must do even with Linux dead: **emergency stop, stall detection, hold position on power loss.**

Toolchain: **PlatformIO with `framework = espidf`** (not Arduino) — decided 2026-08-13 when the first camera node was added, following the precedent already proven in `firmware/voice-node/`. Applies project-wide, not just this node. Pin the platform version in `platformio.ini` (`platform = espressif32@55.3.311`); letting it resolve to the default broke a build once already.
