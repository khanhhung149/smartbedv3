# SmartBed v3

Non-contact sleep platform. **Not a bed — a framework.**

Many sensor inputs, many control outputs, all addressable from outside. Developers extend it; users load behaviour templates written as plain text that AI converts into system logic. Everything below serves that positioning.

> **Wellness device. No medical claims.** Every output (apnea, respiration, sleep stage) is labelled *"tham khảo, không dùng chẩn đoán"*. No "diagnose", "blood pressure", or "detect disease" in UI or marketing.

## Repo layout

| Dir | Runs on | Contents |
|---|---|---|
| `firmware/` | ESP32 | Sensor nodes, mechanical handler, safety, e-stop. **The only layer allowed to drive an actuator.** |
| `edge/` | Jetson Orin | Sensor collection, signal processing, MediaPipe Pose, sleep staging, local dashboard |
| `cloud/` | K8s | Backend, user profiles, template registry |
| `app/` | Flutter | Tablet + phone client (Android/iOS). Phase 06. |
| `mech/` | — | CAD for the 3-plate lift frame |
| `presence-ac/` | ESP32 + Go | Presence/AC/voice system. Its `backend/` is **the backend the app talks to today** (`:8080`, prefix `/api`) |
| `sleep-pad/` | ESP32 + Python | Sleep-pad platform. Its FastAPI tier **owns MQTT ingest** — every row in Postgres arrives through it |
| `docs/` | — | Architecture, safety, meeting minutes, sensor characterisation |
| `plans/` | — | Phased implementation plan |

### `presence-ac/` and `sleep-pad/` were separate repos

Both were merged in with `git subtree`, full history and authorship intact (213 commits, 9 authors).
The original clones still exist and still carry their remotes:

| Prefix here | Origin | Note |
|---|---|---|
| `presence-ac/` | `github.com/khanhhung149/esp32-presence-ac` (private, effectively solo) | |
| `sleep-pad/` | `github.com/Sleep-Tech-AI/sleep-pad-ai` (**org repo, 7 contributors**) | Merged from branch `feat/sleep-sessions` |

**`sleep-pad/` is a live team codebase, not a fork to abandon.** Work done only here will silently
diverge from what Michael and the team push to `Sleep-Tech-AI`. Either push changes back from the
original clone, or agree with the team that this repo becomes the source of truth. Choosing neither
is how two codebases quietly stop matching.

Secrets did not come along — `.env`, `.env.dev` are gitignored by design. Copy them from the
original clones before running either stack.

## Read first

1. [`plans/260713-1019-smartbed-v3-mvp/plan.md`](plans/260713-1019-smartbed-v3-mvp/plan.md) — the phased plan (00 → 07)
2. [`docs/system-architecture.md`](docs/system-architecture.md) — 3 tiers and the contract between them
3. [`docs/safety/hazard-analysis.md`](docs/safety/hazard-analysis.md) — every way this machine can hurt someone
4. [`plans/reports/handoff-260713-1628-smartbed-v3-to-new-claude-project.md`](plans/reports/handoff-260713-1628-smartbed-v3-to-new-claude-project.md) — project context brief

`docs/smartbed-mvp-specs-2023-original.pdf` is the **2023** spec. It is two years stale, contains four wrong components, and is kept for reference only. It is **not** the spec — the meeting minutes of 2026-07-13 are.

## The three rules that are not negotiable

1. **The Linux/AI tier never commands motion directly.** Jetson *requests* a posture; the ESP32 may refuse. Linux is not real-time — a 200 ms kernel stall while an actuator presses on a sleeping person is an injury.
2. **All motion goes through the mechanical handler module.** Nothing else touches an actuator. Safety logic lives *inside* the handler, not scattered upstream.
3. **Nobody lies on the bed before the safety gate passes** (`docs/safety/hazard-analysis.md`). The first person on it is an engineer, not a customer.

## Hardware rule

**Always give circuits their own power supply. Never power a board from a laptop.** Brown-outs cause random faults that cost days to debug.

## Status

Phase 00 (foundation, BOM, safety framing) — in progress. Nothing is built yet.
