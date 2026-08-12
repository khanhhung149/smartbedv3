# System Architecture & API Contracts

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ SENSOR LAYER                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  radar-node (S2)        door-node (S2)          room-node (S2) │
│  ┌──────────────────┐   ┌──────────────┐        ┌──────────┐  │
│  │ LD2410C          │   │ PIR sensor   │        │ LD2410C  │  │
│  │ → MQTT publish   │   │ → MQTT       │        │ (no WiFi)│  │
│  └────────┬─────────┘   │   publish    │        └────┬─────┘  │
│           │             └──────┬───────┘             │         │
│      presence,              motion          ESP-NOW relay     │
│      motion                                      │              │
└───────────┼────────────────────────────────────────┼──────────┘
            │                                         │
            │ MQTT (QoS1)                             │ ESP-NOW
            │                                         │ (P2P, no WiFi)
            ▼                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ FUSION LAYER                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  voice-node (S3) — SINGLE DECISION MAKER                       │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ State Machine:                                         │    │
│  │  • Presence (MQTT subscribed)                         │    │
│  │  • Motion (MQTT subscribed)                           │    │
│  │  • Occupancy (tick-based EnterWindow/ExitTimeout)    │    │
│  │  • AC decision (on/off only, not auto)               │    │
│  │                                                       │    │
│  │ INMP441 mic                                           │    │
│  │  → WebSocket PCM16 → backend /api/voice/stream       │    │
│  │  → Whisper ASR → ParseVietCommand                    │    │
│  │  → MQTT ac_cmd relay                                 │    │
│  │                                                       │    │
│  │ IR blaster → Daikin AC unit (GPIO8)                  │    │
│  └────────┬───────────────────────────┬──────────────────┘    │
│           │                           │                       │
│           │ IR command                │ Fusion state          │
│           │ (GPIO8 pulse train)       │ (retained MQTT)       │
└───────────┼───────────────────────────┼──────────────────────┘
            │                           │
            ▼ (direct, <100ms)          │
        ┌────────────┐                   │
        │ AC Unit    │                   │
        │ (Daikin)   │                   │
        └────────────┘                   │
                                         ▼ MQTT
┌─────────────────────────────────────────────────────────────────┐
│ BACKEND LAYER (Observer)                                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Go Server (:8080)                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ API:                                                    │   │
│  │  • GET /api/state → Snapshot                          │   │
│  │  • WS /api/ws → realtime state delta                  │   │
│  │  • POST /api/ac → manual AC cmd → MQTT relay          │   │
│  │  • GET /api/events → SQLite history                   │   │
│  │  • WS /api/voice/stream → PCM16 upload (voice-node)   │   │
│  │  • POST /api/ac/learn → IR learning mode              │   │
│  │                                                        │   │
│  │ State Machine (mirrors voice-node for display only)   │   │
│  │ SQLite Store (5000-row cap, JSON events)              │   │
│  │ MQTT Client (subscriber to presence/motion/ac_cmd)    │   │
│  └────────────┬────────────────────────────────────┬──────┘   │
│               │                                    │           │
│               ▼ REST/WS                           ▼ ASR call   │
└───────────────┼────────────────────────────────────┼───────────┘
                │                                    │
                │                                    │ localhost:9000
                ▼                                    │
        ┌──────────────┐                            ▼
        │ Flutter App  │                      ┌─────────────┐
        │ (Android)    │                      │ ASR Service │
        └──────────────┘                      │ (Whisper)   │
                                              └─────────────┘
```

## Component Details

### Voice-Node (Decision Maker)

**Hardware**: ESP32-S3-DevKit-1 N16R8  
**Primary role**: Fuse presence + motion → decide AC on/off  

**State Machine Logic** (`firmware/voice-node/src/main.cpp`):

```
EnterWindow (15 seconds)
  ↓
  Presence = true + motion within 15s → Occupied = true → IR on
  
ExitTimeout (60 seconds)
  ↓
  Presence = false (retained ≥60s) → Occupied = false → IR off

Hysteresis:
  Manual override → 5-min grace period before auto can revert
```

**Subscriptions** (MQTT):
- `home/room/presence`: Occupancy signal (retained, heartbeat ≥30s)
- `home/room/ac_cmd`: Manual AC command (backend/app relay)

**Publications** (local):
- IR blaster GPIO8 (Daikin152 protocol, no MQTT for this)

**Wakeword gate ("Vừng ơi")** (`ENABLE_WAKEWORD`, env `esp32s3_kws`): TFLite Micro model gates
LISTENING→STREAMING before audio is uploaded to backend for command parsing. Runs unconditionally every
I2S frame regardless of state (avoids model/frontend cold-start cost).

- `WAKEWORD_THRESHOLD = 0.80`, `WAKEWORD_COOLDOWN_MS = 1200` (blocks re-trigger on trailing/residual
  score right after an utterance ends — without it, one real utterance could log as several triggers).
- Real on-device measurement (2026-08-11/12, ESP32-S3-CAM N16R8, real install location): **true-positive
  73.3%** (22/30 counted "Vừng ơi" utterances), **false-trigger ~2.48/h** (5 in a 2h quiet baseline + 1
  in a 25-min deliberate-noise segment — room noise was NOT the main driver, both conditions landed at a
  similar rate).
- Threshold kept at 0.80 rather than raised: true-positive and false-positive score distributions overlap
  almost completely across 0.80–0.99, so no single threshold separates them without a heavy true-positive
  cost (e.g. raising to 0.90 would cut false-triggers to ~0.83/h but crash true-positive to ~30%). A false
  trigger only opens `STREAMING` (forwards audio to backend); the backend's independent command-parsing
  step still has to match a real AC phrase before firing IR, so the practical cost of the current rate is
  wasted bandwidth/battery, not spurious AC actions.
- End-to-end verified: "Vừng ơi, bật điều hoà" → wakeword trigger → STREAMING → backend command parse →
  MQTT `home/room/ac_cmd` → `[ir] Daikin ON`.

### Radar-Node (Sensor Layer)

**Hardware**: ESP32-S2 Mini + LD2410C (24GHz mmWave)  

**Publishes**:
| Topic | Payload | Retain | Notes |
|-------|---------|--------|-------|
| `home/room/presence` | `{"ts":..., "present":true\|false}` | ✅ | Heartbeat ≥30s, immediate change on detection |
| `home/room/presence` (LWT) | `{"ts":..., "present":false}` | ✅ | Broker fills this on disconnect (node goes silent) |
| `home/door/motion` | `{"ts":..., "motion":true}` | ❌ | Event-based, throttle 1s (not state) |
| `tele/<board>/SENSOR` | Tasmota-style: `{"Detect":..., "Moving":..., "Static":...}` | ❌ | Radar raw values, 3s interval |

**Subscriptions**: None (pure publisher)

### Backend Server (Observer)

**Language**: Go  
**Entry**: `cmd/server/main.go` (port 8080, CORS open for LAN MVP)  

**Subscriptions** (MQTT):
- `home/room/presence`: Builds presence snapshot
- `home/door/motion`: Logs motion events
- `home/room/ac_cmd`: Mirrors manual AC commands to history

**REST API**:

```
GET /healthz
  Response: 200 OK
  Purpose: k8s/docker liveness probe (not used in MVP)

GET /api/state
  Response: 200 {
    "present": bool,
    "occupied": bool,
    "ac_desired": bool,
    "last_motion_ts": unix_ms,
    "last_presence_ts": unix_ms,
    "last_ac_cmd": "on" | "off"
  }
  Purpose: Instant state snapshot for app Home tab

GET /api/events?limit=50&before=<ts>
  Response: 200 [
    {
      "id": 1,
      "ts": unix_ms,
      "type": "ac_state" | "motion" | "voice_cmd",
      "payload": JSON
    },
    ...
  ]
  Purpose: Historical event log (pagination via `before`)

POST /api/ac
  Body: {"cmd": "on" | "off"}
  Response: 202 Accepted
  Side-effect: Publishes to MQTT `home/room/ac_cmd` → voice-node → IR fire
  Purpose: Manual AC control from app or voice (backend never fires on its own)

POST /api/ac/learn
  Body: {"button": "on" | "off"}
  Response: 202
  Side-effect: Publishes to MQTT `home/room/ac_learn` → voice-node stores IR code in NVS
  Purpose: IR learning mode (hold real remote button, store arbitrary code)
```

**WebSocket API**:

```
WS /api/ws
  On connect: send current Snapshot
  On presence/motion/ac change: send delta
  Example: {"ac_desired": true, "ts": ...}
  Purpose: Realtime state for app (low-latency Home tab updates)

WS /api/voice/stream
  Client (voice-node) uploads: chunked PCM16 16kHz mono 16-bit LE
  Server: buffers with VAD (silence/max/min duration guards)
  On utterance: POST to ASR service, parse response, relay ac_cmd if match
  Purpose: Voice command ingestion pipeline
```

### ASR Service (Python FastAPI)

**Runs**: Separate container (http://asr:9000)  
**Model**: Whisper "small" (CPU int8 quantization)  

```
POST /transcribe
  Body: multipart/form-data
    file: <WAV 16k mono 16-bit LE>
  Response: 200 {"text": "bật điều hòa"}
  Processing:
    1. Load model (cached, ~150ms)
    2. Whisper inference (variable, 1-3s per audio)
    3. Return text (no further parsing)
  Purpose: Transcribe Vietnamese speech
```

**Tuning**:
- `vad_filter=True`: Skip silence (faster inference)
- `initial_prompt="bật, tắt, mát, nóng, chế độ"`: Bias towards AC keywords
- Language: Vietnamese (not auto-detect)

### Flutter App (Observer)

**Tabs**:

| Tab | Data Source | Purpose |
|-----|-------------|---------|
| **Home** | `/api/ws` (realtime) + `/api/state` (fallback) | AC state, manual buttons, override countdown |
| **Devices** | Direct MQTT to broker (mqtt_client pkg) | Radar diagnostics (`tele/.../SENSOR`), independent of backend |
| **Analytics** | `/api/events` (computed client-side) | Daily usage, uptime, command frequency |
| **History** | `/api/events` (paginated) | Event log, filters by type |
| **Settings** | SharedPreferences | Backend URL + broker config |

**State Management**: Riverpod (providers manage API clients, MQTT connection, WebSocket subscription)

## MQTT Topic Contract

**Canonical source**: `firmware/mqtt/README.md` (source of truth)

**Summary**:

| Topic | Direction | Payload | Retain | QoS |
|-------|-----------|---------|--------|-----|
| `home/room/presence` | radar-node → backend/voice-node | `{"ts":..., "present":bool}` | ✅ | 1 |
| `home/door/motion` | radar-node → backend | `{"ts":..., "motion":bool}` | ❌ | 1 |
| `tele/<board>/SENSOR` | radar-node → app | Tasmota-style | ❌ | 1 |
| `home/room/ac_cmd` | backend/app → voice-node | `{"cmd":"on"\|"off"}` | ❌ | 1 |
| `home/room/ac_learn` | backend/app → voice-node | `{"button":"on"\|"off"}` | ❌ | 1 |
| `home/room/snore_event` | voice-node → backend | `{"ts":0,"confidence":0-1,"duration_ms":int}` | ❌ | 1 |

**All timestamps**: Unix epoch in **milliseconds** (not seconds). Exception: `snore_event` — voice-node
has no NTP sync, `ts` is `millis()` (relative uptime, NOT unix epoch — see contract note in
`firmware/mqtt/README.md`).

**`snore_event` is a placeholder scaffold** (2026-08-12, see
`docs/voice-node-snore-wakeword-architecture.md`): `confidence` is normalized RMS, not a trained model
score — no real snore detection exists yet. Verifies the buffer→task→Event Manager→MQTT pipeline only.

## Voice Command Parsing

**Location**: `backend/internal/voice/command.go`

**Input**: Transcribed text (Vietnamese)

**Logic**:
```
"bật" / "mở" → cmd="on"
"tắt" / "đóng" → cmd="off"
"mát" → mode="cool"
"nóng" → mode="heat"
"chế độ ..." → specific mode
"lạnh hơn" / "nóng hơn" → temperature delta (not implemented, MVP constraint)
```

**Fallback**: If phrase ambiguous or unrecognized → reject (don't guess)

**Risk**: Mishearing "off" as "on" (or vice versa) = toggle at wrong time. Mitigation: ask user to confirm in future phase.

## State Consistency

**Voice-node is authoritative**:
- Backend state machine is a **mirror** (for UI display only)
- If backend diverges, voice-node state machine is source of truth
- Bridge: MQTT topics are the signal flow (presence → voice-node decides → backend observes)

**No race conditions**:
- Only voice-node publishes IR commands
- Backend never autonomously publishes `ac_cmd`
- Manual/voice commands → backend → MQTT → voice-node → IR (single path)

## Latency Budget

| Operation | Max Latency | Current Measured |
|-----------|-------------|------------------|
| Motion → MQTT publish | 2s (debounce) | <100ms |
| Presence → MQTT | 30s (heartbeat) or immediate | <50ms |
| MQTT → voice-node subscribe | 200ms (WiFi) | ~100ms |
| Occupancy decision (state machine tick) | 100ms | <10ms |
| Decision → IR fire | 100ms (IR timing) | <50ms |
| **End-to-end (motion→IR fire)** | **3s** | **<200ms** |

## Security Posture (MVP / LAN-only)

⚠️ **Current** (acceptable for LAN):
- MQTT: auth (no TLS) ✅
- REST/WS: no auth (LAN only) ⚠️
- Audio: stays in LAN (self-hosted ASR) ✅
- OTA: password-protected ✅

🔒 **Before internet exposure** (not MVP):
- MQTT: TLS/mTLS, firewall to LAN only
- REST/WS: token auth, rate-limiting
- CORS: restrict to known origin
- Secrets: rotate OTA password regularly

## Scalability Constraints

**Current design assumes**:
- Single room + single AC unit
- Single voice-node (decision maker)
- <50 events/day (5000-row SQLite cap)
- LAN WiFi (no WAN load)

**Multi-room extension** would require:
- Separate voice-node per room
- MQTT namespace (e.g., `home/room1/presence`, `home/room2/presence`)
- App UI to select active room
- **Design stays single-room scoped for MVP**

---

**Last updated**: 2026-08-10
**Critical files**: `firmware/mqtt/README.md`, `backend/internal/statemachine/machine.go`, `backend/internal/voice/command.go`
