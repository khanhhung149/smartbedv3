# firmware/ — ESP32

**One MCU family for the whole system.** ESP32 (variants allowed: ESP32-S3, ESP8266 for light jobs like WLED). No STM32, no second MCU family — a small team cannot feed two toolchains.

This is the only tier allowed to drive an actuator, and the only tier that stays safe when Linux hangs.

| Module | Phase | Job |
|---|---|---|
| `sensor-node/` | 01 | Read sensors, timestamp at the MCU, 10 Hz fixed loop, ring buffer, push frames to Jetson |
| `esp32cam-node/` | amendment (replaces Phase 01's "Camera nhiệt" cluster, see `plans/260813-0934-esp32cam-vl53l0x-camera-node/`) | OV2640 capture + VL53L0X distance over shared SCCB bus, local SD only, bench-test only |
| `mech-handler/` | 04 | **The** mechanical handler. Position control, current sensing, stall detect, e-stop, command throttling, watchdog, auto-calibrate. Holds veto power over Linux. |

Three things this tier must do even with Linux dead: **emergency stop, stall detection, hold position on power loss.**

Toolchain: **PlatformIO with `framework = espidf`** (not Arduino) — decided 2026-08-13 when `esp32cam-node/` was added, following the precedent already proven in `esp32-presence-ac/firmware/voice-node/`. Applies project-wide, not just this node.
