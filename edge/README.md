# edge/ — Jetson Orin (Python)

Local AI/perception modules that need to run directly on Jetson (low-latency access to live sensor
data, no round-trip to a separate service). **Not** the sensor ingestion path — that already exists
and is not reimplemented here.

**Ingestion/storage (Phase 01) is done by the Docker backends, not by a `collector/` module.**
Sensor nodes publish over MQTT straight to backends running on this same Jetson: the Go backend
(`cloud/presence-ac/`, SQLite) and FastAPI (`cloud/sleeppad/`, TimescaleDB). Both already validate,
persist every channel (including ones nothing consumes yet), mark dropouts explicitly (e.g.
`hr_bpm = 0`, `uart_ok` flag) instead of fabricating data, and retain a rolling window of nights.
Building a separate Python `collector/` here would duplicate that logic for no new capability —
decided 2026-08-26, see `plans/reports/brainstorm-260826-1003-edge-collector-vs-docker-backend-report.md`.
Local real-time charts/replay already exist too (dashboard + Flutter app talking to those backends)
— no separate `dashboard/` module here either.

**Which delegate MediaPipe runs on here is undecided, and "GPU" is not a safe assumption.** Getting MediaPipe onto Jetson aarch64 at all is an open risk that blocks Phase 05 — see *Vision pipeline* in [`../docs/system-architecture.md`](../docs/system-architecture.md) before designing against it.

**May not command motion.** It sends a *posture request* to the ESP32 handler over UART/CAN, and the handler may refuse. See `docs/system-architecture.md`.

| Module | Phase | Job |
|---|---|---|
| `sleep/` | 02 | Sleep staging, apnea, snore detection — reads from the existing SQLite/TimescaleDB, does not re-collect |
| `vision/` | 05 | MediaPipe Pose |

Dropouts are marked explicitly (e.g. `hr_bpm = 0`), never fabricated. Downstream must be able to tell real data from missing data.
