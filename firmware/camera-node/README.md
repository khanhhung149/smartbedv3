# camera-node/ — ESP32 (candidate, unconfirmed scope)

**Not to be confused with `firmware/esp32cam-node/`** — that is a separate physical device for Phase 01 (behavior-recording node, ESP32-CAM + VL53L0X, writes video to local SD, bench-test only). This directory is about the Phase 05 camera below, which never writes anything to disk.

Not started. Directory reserved for the firmware-tier surface of Phase 05 (camera + edge-AI).

Image capture, MediaPipe Pose, and rPPG all run on **Jetson Orin** in [`edge/vision/`](../../edge/README.md) — this directory does not process images. `firmware/README.md`'s module table does not list this directory yet; the scope below is inferred from the Phase 05 privacy principles, not an explicit assignment from Michael. **Confirm scope before implementing.**

Candidate jobs, tied to the two privacy rules in [`plans/260713-1019-smartbed-v3-mvp/phase-05-camera-edge-ai.md`](../../plans/260713-1019-smartbed-v3-mvp/phase-05-camera-edge-ai.md) that must hold even with Linux/Jetson down:

| Privacy rule (Phase 05) | Possible firmware role |
|---|---|
| Physical slide cover over the lens, user sees it closed and trusts it's closed | Mechanical by design — may need no firmware at all |
| Hardware LED wired directly to the camera's power rail, lights whenever camera has power | **No software control path by design.** MCU may read the line for telemetry only, must never be able to switch it |

Also unconfirmed: whether the 850 nm IR illuminator needs MCU-precision strobe timing synced to camera exposure — if so, that job belongs here too.
