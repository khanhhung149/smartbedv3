# edge/ — Jetson Orin (Python)

Perception and AI. Reads sensors, processes signal, runs MediaPipe Pose on the GPU, stages sleep.

**May not command motion.** It sends a *posture request* to the ESP32 handler over UART/CAN, and the handler may refuse. See `docs/system-architecture.md`.

| Module | Phase | Job |
|---|---|---|
| `collector/` | 01 | Receive frames, validate, persist. Store **every channel, including ones nothing consumes yet.** |
| `dashboard/` | 01 | Local real-time charts + replay any night. Engineer debug tool, not customer UI. |
| `sleep/` | 02 | Sleep staging, apnea, snore detection |
| `vision/` | 05 | MediaPipe Pose |

Dropouts are marked explicitly (e.g. `hr_bpm = 0`), never fabricated. Downstream must be able to tell real data from missing data.
