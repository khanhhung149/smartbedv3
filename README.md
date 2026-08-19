# SmartBed v3

Non-contact sleep platform. **Not a bed — a framework.**

Many sensor inputs, many control outputs, all addressable from outside. Developers extend it; users load behaviour templates written as plain text that AI converts into system logic. Everything below serves that positioning.

> **Wellness device. No medical claims.** Every output (apnea, respiration, sleep stage) is labelled *"tham khảo, không dùng chẩn đoán"*. No "diagnose", "blood pressure", or "detect disease" in UI or marketing.

## Repo layout

| Dir | Runs on | Contents |
|---|---|---|
| `firmware/` | ESP32 | Every MCU node: `camera-node`, `esp32cam-stream`, `radar-node`, `voice-node`, `sleep-pad-node{,-idf}`. **The only layer allowed to drive an actuator.** |
| `edge/` | Jetson Orin | Sensor collection, signal processing, MediaPipe Pose, sleep staging, local dashboard |
| `cloud/` | server / K8s | Backends and services: `presence-ac` (Go, `:8080`), `sleeppad` (FastAPI, `:8000`), `asr`, `mqtt`, `landing` |
| `app/` | Flutter | Three clients: `smartbed` (this project), `presence-ac`, `sleep-pad` |
| `mech/` | — | CAD for the 3-plate lift frame, plus `presence-ac-enclosure` |
| `docs/` | — | Architecture, safety, meeting minutes, sensor characterisation; `docs/presence-ac/` and `docs/sleep-pad/` hold each merged project's own docs |
| `plans/` | — | Phased implementation plan; `plans/sleep-pad/` holds the sleep-pad plans |
| `scripts/` | — | Repo tooling, plus `scripts/presence-ac/` |

**Which backend does the app actually call?** `cloud/presence-ac` (Go, `:8080`, prefix `/api`).
`cloud/sleeppad` is not on that path but **owns MQTT ingest** — every row in Postgres arrives
through it, so it is not legacy and cannot be switched off.

### Two projects were merged into this layout

`esp32-presence-ac` and `sleep-pad-ai` were separate repos, merged with `git subtree` (full history
and authorship intact — 214 commits, 9 authors), then their files were redistributed into the tier
folders above. The original clones still exist and still carry their remotes:

| Merged from | Origin | Now lives in |
|---|---|---|
| `esp32-presence-ac` | `github.com/khanhhung149/esp32-presence-ac` (private, effectively solo) | `cloud/presence-ac`, `firmware/{radar,voice}-node`, `app/presence-ac`, `docs/presence-ac`, `mech/presence-ac-enclosure` |
| `sleep-pad-ai` | `github.com/Sleep-Tech-AI/sleep-pad-ai` (**org repo, 7 contributors**) | `cloud/sleeppad`, `firmware/sleep-pad-node{,-idf}`, `app/sleep-pad`, `docs/sleep-pad`, `plans/sleep-pad` |

**Redistributing the files gave up `git subtree push`.** Because no single prefix holds either
project's tree any more, changes made here cannot be pushed back automatically. The only route to
`Sleep-Tech-AI` is the original clone at `/mnt/d/sleep_pad_AI`. That repo is a live team codebase —
work done only here will silently diverge from what Michael and the team push. Decide which repo is
the source of truth; choosing neither is how two codebases quietly stop matching.

`docs/sleep-pad/ci/deploy.yml` is the team's deploy workflow, **parked as documentation on purpose**.
It runs on the self-hosted runner `sleeptech-host` and deploys their production; putting it back
under `.github/workflows/` would let this repo fire a deploy at their infrastructure.

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
