# System Architecture

## High-Level Overview

The system consists of three tiers:

1. **Sensor Tier** (Firmware): Two ESP32-S2 nodes with motion and presence sensors
2. **Broker Tier** (MQTT): Mosquitto broker for inter-device communication
3. **Logic Tier** (Go Backend): Presence state machine, REST API, WebSocket broadcast

Additional tier (planned, not yet implemented):
4. **Voice Tier** (ESP32-WROOM-32): Audio capture and server-side ASR

```
┌─────────────────────────────────────────────────────────────────┐
│                         Sensor Tier (Firmware)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐              ┌──────────────────────────┐ │
│  │  Door Node       │              │    Room Node             │ │
│  │  (S2 Mini)       │              │    (S2 Mini)             │ │
│  ├──────────────────┤              ├──────────────────────────┤ │
│  │ PIR Sensor       │              │ LD2410 Radar             │ │
│  │ (GPIO7)          │              │ (GPIO16)                 │ │
│  │                  │              │                          │ │
│  │ Pub: home/door/  │              │ IR Receiver (GPIO15)     │ │
│  │      motion      │              │ IR Blaster (GPIO5)       │ │
│  │                  │              │ NVS Preferences (IR codes)│ │
│  │                  │              │                          │ │
│  │                  │              │ Pub: home/room/presence  │ │
│  │                  │              │ Sub: home/room/ac_cmd    │ │
│  │                  │              │       home/room/ac_learn │ │
│  └──────────────────┘              └──────────────────────────┘ │
│           │                                   │                   │
└───────────┼───────────────────────────────────┼───────────────────┘
            │                                   │
            └───────────────┬───────────────────┘
                            │ MQTT
                            ▼
        ┌───────────────────────────────────┐
        │      Broker Tier (MQTT)           │
        ├───────────────────────────────────┤
        │   Mosquitto 2                     │
        │   (Authenticated, no TLS/LAN)     │
        │                                   │
        │   Topics:                         │
        │   • home/door/motion (QoS1)       │
        │   • home/room/presence (QoS1, R)  │
        │   • home/room/ac_cmd (QoS1)       │
        │   • home/room/ac_learn (QoS1)     │
        └───────────────────────────────────┘
                            │ MQTT
                            ▼
        ┌───────────────────────────────────┐
        │      Logic Tier (Go Backend)      │
        ├───────────────────────────────────┤
        │                                   │
        │   State Machine                   │
        │   • Presence inference            │
        │   • Occupancy debounce            │
        │   • AC command emission           │
        │                                   │
        │   REST API                        │
        │   • /api/state (GET)              │
        │   • /api/ac (POST)                │
        │   • /api/ac/learn (POST)          │
        │                                   │
        │   WebSocket Hub                   │
        │   • Broadcasts state changes      │
        │                                   │
        └───────────────────────────────────┘
                     │           │
                ┌────┴───────────┴────┐
                ▼                     ▼
        REST Clients            WebSocket Clients
        (e.g., Flutter app)     (e.g., Web UI)
```

---

## MQTT Topic Contract

All messages are JSON (unless otherwise noted). Timestamps are Unix seconds.

| Topic | Direction | QoS | Retain | Payload Schema | Purpose |
|-------|-----------|-----|--------|---|---------|
| `home/door/motion` | Door Node → Broker → Backend | 1 | No | `{"ts": 1234567890, "motion": true}` | PIR detects motion. Backend uses to reset enter-window timer. |
| `home/room/presence` | Room Node → Broker → Backend | 1 **Yes** | `{"ts": 1234567890, "present": true}` | LD2410 presence state (true = motion/occupancy detected). Retained for latecomers. |
| `home/room/ac_cmd` | Backend → Broker → Room Node | 1 | No | `{"cmd": "on"}` or `{"cmd": "off"}` | Backend commands AC on/off. Room node calls `sendAC()` to replay learned IR code. |
| `home/room/ac_learn` | Backend → Broker → Room Node | 1 | No | `{"button": "on"}` or `{"button": "off"}` | Backend initiates 15s IR learn window. Room node captures raw IR and stores in NVS. |

**Notation**: `**Yes**` indicates retained message.

### Message Timing & Frequency

| Topic | Publish Frequency | Trigger |
|-------|---|---|
| `home/door/motion` | On edge (GPIO interrupt) | PIR detects motion (high pulse) |
| `home/room/presence` | On change (polling every 200ms) | LD2410 digital output transitions |
| `home/room/ac_cmd` | On state change (backend logic) | Occupancy state machine transitions to/from Occupied |
| `home/room/ac_learn` | On demand (REST API) | User initiates IR learning via `/api/ac/learn` POST |

---

## Data Flow Examples

### 1. User Enters Room (Occupancy Detection)

```
Time: T=0s
  └─ PIR triggers (GPIO7 interrupt, debounce 2s)
     └─ Door Node publishes: home/door/motion {"motion": true, "ts": T}
        └─ Broker forwards to Backend
           └─ Backend state machine:
              • presence=false, motion=true, within 15s enter window
              • State transitions: Idle → Occupied
              • Emits AC command: home/room/ac_cmd {"cmd": "on"}
              └─ Room node receives ac_cmd
                 └─ Reads stored "on" IR code from NVS
                    └─ Sends IR blaster pulse to AC
                       └─ AC powers on ✓

Time: T=5s
  └─ LD2410 detects presence (occupancy confirmed)
     └─ Room node publishes: home/room/presence {"present": true, "ts": T}
        └─ (State already Occupied; no action)
```

### 2. User Leaves Room (Exit Debounce)

```
Time: T=0s
  └─ LD2410 loses presence (person moves to doorway)
     └─ Room node publishes: home/room/presence {"present": false, "ts": T}
        └─ Backend state machine:
           • presence=false, enter ExitWait state
           • Start 60s exit timer

Time: T=30s
  └─ Person briefly returns to room
     └─ LD2410 detects presence again
        └─ Room node publishes: home/room/presence {"present": true, "ts": T}
           └─ Backend cancels exit timer, returns to Occupied state
              └─ No AC command (already on)

Time: T=65s (if person had stayed gone)
  └─ Exit timer expires (60s continuous absence)
     └─ State transitions: ExitWait → Idle
        └─ Emits AC command: home/room/ac_cmd {"cmd": "off"}
           └─ Room node receives ac_cmd
              └─ Sends IR blaster pulse (learned "off" code)
                 └─ AC powers off ✓
```

### 3. User Learns AC Codes

```
User (via REST API or Web UI):
  POST /api/ac/learn {"button": "on"}
  
Backend:
  └─ Publishes: home/room/ac_learn {"button": "on", "ts": T}
     └─ Room node receives ac_learn message
        └─ Enables IR receiver (GPIO15, TSOP38238)
        └─ Starts 15s capture window
        └─ Waits for user to press AC remote "on" button
           └─ IR receiver captures raw codes
              └─ Stores in NVS Preferences under key "on"
              └─ Sends confirmation via MQTT or just completes silently
                 └─ Backend polls /api/state or waits for AC commands to succeed

(Learned codes persist across power cycles via NVS; not synced to backend)
```

---

## State Machine (Backend Presence Logic)

### States

| State | Meaning | AC Status |
|-------|---------|-----------|
| **Idle** | No occupancy detected | Off (or commanded Off if was on) |
| **Occupied** | Room is occupied; AC should run | On (commanded On if was off) |
| **ExitWait** | Presence lost; waiting for exit timeout | Remains On (no immediate off command) |

### Transitions

```
Idle
  │
  ├─ [presence=true AND motion within ENTER_WINDOW_S]
  │   └─► Occupied (emit AC on)
  │
ExitWait
  │
  ├─ [presence=true] → back to Occupied
  │
  ├─ [exit timer expires]
  │   └─► Idle (emit AC off)
  │
Occupied
  │
  └─ [presence=false]
      └─► ExitWait (start timer)
```

### Parameters (Configurable)

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `ENTER_WINDOW_S` | 15 | Seconds to infer "enter": motion must occur within this window of presence=true state |
| `EXIT_TIMEOUT_S` | 60 | Seconds to infer "exit": presence must stay false for this duration before state transitions to Idle |
| `MOTION_DEBOUNCE_S` | 5 | (Firmware level) PIR debounce period; suppresses flicker from brief motion |

### Why Not Just PIR or Just Radar?

- **PIR alone**: Motion fades with stillness (person sitting = no motion); would incorrectly exit
- **Radar alone**: LD2410 drifts (false presence detection at room boundaries or through walls)
- **Both**: Motion resets enter window, radar provides occupancy confirmation → reliable inference

---

## Backend API (REST Endpoints)

### GET /healthz
**Purpose**: Liveness check  
**Response**:
```json
{
  "status": "ok",
  "mqtt_connected": true
}
```

### GET /api/state
**Purpose**: Fetch current occupancy and AC status  
**Response**:
```json
{
  "state": "occupied",
  "present": true,
  "ac_on": true,
  "last_motion_ts": 1234567890,
  "last_presence_ts": 1234567890
}
```

### POST /api/ac
**Purpose**: Manually command AC on/off (override state machine)  
**Request**:
```json
{
  "cmd": "on"
}
```
**Response**: `{"ok": true}` or error  
**Effect**: Publishes to `home/room/ac_cmd` immediately (state machine respects this)

### POST /api/ac/learn
**Purpose**: Initiate IR code learning  
**Request**:
```json
{
  "button": "on"
}
```
**Response**: `{"ok": true}` or error  
**Effect**: Publishes to `home/room/ac_learn`, room node enters 15s capture window

### GET /ws
**Purpose**: WebSocket for real-time state updates  
**Upgrades to WebSocket**  
**Messages (server → client)**:
```json
{
  "state": "occupied",
  "present": true,
  "ac_on": true,
  "last_motion_ts": 1234567890,
  "last_presence_ts": 1234567890
}
```
Sent whenever state changes or at periodic intervals (e.g., every 5s).

---

## Deployment Architecture

### Development / MVP (Current)

```
┌─────────────────────────────────────────────────────────┐
│ Raspberry Pi or Linux PC (LAN)                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │ Mosquitto Broker │  │ Go Backend (Docker or native)│ │
│  │ (port 1883)      │  │ (port 8080)                  │ │
│  │ Auth required    │  │                              │ │
│  │ No TLS           │  │ Connected to Mosquitto       │ │
│  └──────────────────┘  │ via localhost:1883           │ │
│                        │                              │ │
│                        │ Exposes REST + WebSocket     │ │
│                        └──────────────────────────────┘ │
│           ▲                        ▲                     │
│           │ MQTT (1883)            │ HTTP (8080)        │
│           │                        │                    │
└───────────┼────────────────────────┼──────────────────┘
            │                        │
      ┌─────┴────────┐         ┌─────┴──────────┐
      │              │         │                │
   Door Node      Room Node   Web Browser  (Future) App
    (WiFi)         (WiFi)    or Mobile App
```

### Production / Future (Post-MVP)

- Add TLS/mTLS for MQTT
- Backend behind reverse proxy (nginx)
- Consider cloud MQTT service (AWS IoT Core, HiveMQ Cloud) if internet access needed
- Add authentication/authorization for REST API
- Move voice ASR to dedicated server or cloud service

---

## Security Considerations

### Current (MVP/LAN-only)

| Aspect | Status | Notes |
|--------|--------|-------|
| MQTT TLS | ❌ No | LAN-only; must add before internet exposure |
| MQTT Auth | ✅ Yes | Username/password; credentials in env vars / config.h |
| REST Auth | ❌ No | No API key or token validation; LAN-only assumption |
| WebSocket Auth | ❌ No | Broadcast to any client on same network |
| CORS | ⚠️ Wide open | Intentional MVP; tighten to specific origin before internet |
| IR Code Storage | ✅ Local only | No cloud sync; learned codes stay on room node |

### Before Internet Exposure

1. **Add TLS** to Mosquitto broker
2. **Add mTLS** or authentication tokens to backend API
3. **Tighten CORS** to specific frontend origin
4. **Add rate limiting** to REST endpoints
5. **Audit MQTT topic ACLs** (firewall rules per client)

---

## Known Limitations & Future Work

| Item | Current | Future |
|------|---------|--------|
| Occupancy | Single room (door + room node) | Multi-room with shared broker |
| Voice | Deferred (depends on ASR provider decision) | S3 Mini cannot handle local ASR; needs server-side |
| Mobile App | Not started | Flutter consuming REST/WS API |
| Event History | In-memory only | SQLite persistence (deferred as YAGNI) |
| IR Code Sync | None (local NVS only) | Potential: sync learned codes to backend (future work) |
| Firmware Updates | Manual via USB/Serial | OTA not yet implemented |

---

## Hardware Details

For detailed pin assignments, wiring diagrams, and sensor specifications, see [`docs/system-wiring.md`](./system-wiring.md) (Vietnamese).

**Quick reference**:
- Door Node: S2 Mini + PIR (HC-SR501, GPIO7)
- Room Node: S2 Mini + LD2410 (GPIO16 digital, UART GPIO33/18) + IR receiver (GPIO15) + IR blaster (GPIO5)
- Broker: Mosquitto in Docker or native

---

## Monitoring & Troubleshooting

### Health Checks

1. **MQTT Broker**: `mosquitto_sub -h localhost -u user -P pass -t \$SYS/#` (broker system topics)
2. **Backend API**: `curl http://localhost:8080/healthz` → `{"status":"ok","mqtt_connected":true}`
3. **Presence state**: `curl http://localhost:8080/api/state`

### Common Issues

| Issue | Check | Fix |
|-------|-------|-----|
| Backend can't connect to Mosquitto | `netstat -an \| grep 1883` | Ensure Mosquitto running, firewall allows 1883 |
| Room node not receiving ac_cmd | Subscribe to `home/room/ac_cmd` with mosquitto_sub | Check room node MQTT subscription code |
| IR blaster not firing | Test with direct GPIO toggle | Verify transistor driver, battery on blaster circuit |
| PIR not triggering | Check GPIO7 is not boot-strap pin | See firmware issue tracker |

---

## Related Documentation

- [`docs/project-overview-pdr.md`](./project-overview-pdr.md) — Product decisions and scope
- [`docs/codebase-summary.md`](./codebase-summary.md) — Code structure and modules
- [`docs/code-standards.md`](./code-standards.md) — Naming and style conventions
- [`docs/system-wiring.md`](./system-wiring.md) — Hardware wiring and pinouts (Vietnamese)
- [`docs/project-roadmap.md`](./project-roadmap.md) — Phase tracking and open items
