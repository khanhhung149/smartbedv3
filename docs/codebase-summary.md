# Codebase Summary

## Project Structure Overview

```
project-root/
├── backend/           # Go REST API + state machine (874 LOC, 11 files)
├── firmware/          # PlatformIO ESP32 firmware (520 LOC across 2 nodes)
├── docs/             # Technical documentation (this file, system-wiring.md, etc.)
├── plans/            # Implementation phases and decision logs
├── .gitignore        # VCS configuration
├── .repomixignore    # Codebase indexing exclusions
├── README.md         # Project overview (root level)
└── (stuffs/)         # NOT part of this project; ignore in documentation
```

## Backend (Go)

**Location**: `backend/`  
**LOC**: ~874 across 11 files  
**Framework**: Chi router + paho MQTT client  
**Go version**: 1.24  
**Status**: ✅ All phases complete; end-to-end verified against simulated MQTT

### Directory Layout
```
backend/
├── cmd/
│   └── server/
│       └── main.go          # Entry point: config load, MQTT wire-up, HTTP server
├── internal/
│   ├── api/
│   │   ├── handler.go       # Chi router + REST endpoints
│   │   ├── ws.go            # WebSocket hub for state broadcasts
│   │   └── interface.go     # StateProvider/Publisher interfaces (test decoupling)
│   ├── config/
│   │   └── config.go        # Env var parsing (MQTT_*, HTTP_*, timing params)
│   ├── events/
│   │   └── events.go        # MQTT payload structs (Motion, Presence)
│   ├── mqttclient/
│   │   └── client.go        # Paho wrapper: connect, subscribe, publish, reconnect
│   └── statemachine/
│       ├── machine.go       # Occupancy logic (Enter/Exit, debounce, AC commands)
│       └── machine_test.go  # 6/6 tests passing
├── Dockerfile                # Multi-stage: golang:1.24 → distroless
└── docker-compose.yml        # Service definition + .env_file reference
```

### Key Modules

| Module | Responsibility | Key Types |
|--------|-----------------|-----------|
| `cmd/server/main.go` | Bootstrap: config load, MQTT client init, state machine wiring, HTTP server start, graceful shutdown on signal | — |
| `internal/config` | Environment variable parsing, validation, defaults (MQTT_HOST, MQTT_PORT, HTTP_ADDR, timing params) | `Config` struct |
| `internal/events` | MQTT JSON payload definitions | `Motion`, `Presence` structs |
| `internal/mqttclient` | Paho MQTT client wrapper, auto-reconnect, subscription management, publish with timeout | `Client` |
| `internal/statemachine` | Occupancy logic: tick-based state machine (Idle → Occupied → Idle), debounce, enter/exit windows, AC command emission | `Machine`, `State`, `Config` |
| `internal/api/handler` | Chi REST router: `/healthz`, `/api/state`, `/api/ac`, `/api/ac/learn` | `Handler` |
| `internal/api/ws` | WebSocket hub: broadcasts state snapshot on change | `Hub`, `Client` |

### API Endpoints

| Method | Path | Purpose | Status |
|--------|------|---------|--------|
| GET | `/healthz` | Liveness check (MQTT connection status) | ✅ Implemented |
| GET | `/api/state` | Returns current occupancy state + AC status | ✅ Implemented |
| POST | `/api/ac` | Command AC on/off: `{"cmd":"on"/"off"}` | ✅ Implemented |
| POST | `/api/ac/learn` | Trigger IR learn mode: `{"button":"on"/"off"}` | ✅ Implemented |
| GET | `/ws` | WebSocket: subscribe to state changes | ✅ Implemented |

### Configuration (Environment Variables)

| Variable | Default | Required | Purpose |
|----------|---------|----------|---------|
| `MQTT_HOST` | — | Yes | Broker hostname/IP |
| `MQTT_PORT` | 1883 | No | Broker port |
| `MQTT_USER` | — | Yes | Auth username |
| `MQTT_PASS` | — | Yes | Auth password |
| `MQTT_CLIENT_ID` | `home-backend` | No | Client identifier |
| `ENTER_WINDOW_S` | 15 | No | Seconds to infer enter (motion within window) |
| `EXIT_TIMEOUT_S` | 60 | No | Seconds to infer exit (no presence) |
| `HTTP_ADDR` | `:8080` | No | Listen address:port |

### State Machine Logic

**States**: `Idle`, `Occupied`, `ExitWait`

**Transitions**:
- `Idle` → `Occupied`: presence=true AND motion within `ENTER_WINDOW_S`
- `Occupied` → `ExitWait`: presence=false (start timer)
- `ExitWait` → `Idle`: exit timer expires (continuous absence for `EXIT_TIMEOUT_S`)
- AC command emitted only on state change (no redundant publishes)

### Testing

- **Test file**: `internal/statemachine/machine_test.go`
- **Coverage**: 6 scenario tests, all passing (enter, exit, debounce, flicker handling)
- **Approach**: Table-driven with scenario names (not generic test numbers)
- **Verification**: End-to-end tested against real Mosquitto broker with simulated `mosquitto_pub` events

### Deployment

- **Docker**: Multi-stage build (compile in golang:1.24, runtime in distroless)
- **Docker Compose**: Service runs with `env_file .env` (secrets not in git)
- **Net**: `host.docker.internal` to reach Mosquitto on host machine

---

## Firmware (PlatformIO)

**Location**: `firmware/`  
**LOC**: ~520 across 2 independent node projects (no shared library)  
**Board**: lolin_s2_mini (Wemos S2 Mini, ESP32-S2)  
**Framework**: Arduino with PlatformIO  
**Status**: ⏳ Code complete, compiles clean; NOT yet flashed/verified on real hardware

### Directory Layout
```
firmware/
├── door-node/
│   ├── src/
│   │   └── main.cpp         # PIR motion sensor + MQTT publish
│   ├── include/
│   │   └── config.h.example # WIFI/MQTT secrets template
│   └── platformio.ini       # Build config for lolin_s2_mini
├── room-node/
│   ├── src/
│   │   └── main.cpp         # LD2410 radar + IR learn/send + MQTT
│   ├── include/
│   │   └── config.h.example # WIFI/MQTT secrets template
│   └── platformio.ini       # Build config for lolin_s2_mini
└── mqtt/
    ├── docker-compose.yml   # Mosquitto broker (eclipse-mosquitto:2)
    └── README.md            # MQTT topic contract + test commands
```

### Node 1: Door (PIR Motion Sensor)

**File**: `firmware/door-node/src/main.cpp` (~112 LOC)

| Component | Pin | Purpose |
|-----------|-----|---------|
| PIR Sensor | GPIO7 | Interrupt + debounce 2000ms |
| MQTT Client | — | Publish to `home/door/motion` |

**Publish Contract**:
- Topic: `home/door/motion`
- QoS: 1
- Retain: false
- Payload: `{"ts": 1234567890, "motion": true}`
- Frequency: On change (GPIO7 edge trigger)

**Dependencies**:
- 256dpi/MQTT@^2.5 (chosen over PubSubClient for robust QoS1 support)

### Node 2: Room (LD2410 Radar + IR Control)

**File**: `firmware/room-node/src/main.cpp` (~246 LOC)

| Component | Pin | Purpose |
|-----------|-----|---------|
| LD2410 Radar | GPIO16 (digital out) + UART (GPIO33/18) | Presence detection, polling every 200ms |
| IR Receiver | GPIO15 | TSOP38238 IR sensor for learn mode (15s window) |
| IR Blaster | GPIO5 → transistor | Send learned IR codes to AC |
| NVS Storage | — | Persist learned codes per key ("on"/"off") |

**Publish Contract**:
- Topic: `home/room/presence`
- QoS: 1
- Retain: true
- Payload: `{"ts": 1234567890, "present": true}`
- Frequency: On change (polling detects state transition)

**Subscribe Contract**:
- Topic: `home/room/ac_cmd` — Backend commands: `{"cmd": "on"/"off"}` → decode + sendAC(key)
- Topic: `home/room/ac_learn` — Backend triggers: `{"button": "on"/"off"}` → startLearn(key)

**IR Learning**:
- Triggered by `ac_learn` MQTT message
- 15-second window: capture raw IR from user's AC remote
- Store in NVS Preferences (per key: "on", "off")
- No sync to backend (explicit MVP decision; revisit for multi-room support)

**Dependencies**:
- crankyoldgit/IRremoteESP8266@^2.8.6 (for raw IR capture/replay)
- 256dpi/MQTT@^2.5 (same as door node)

### MQTT Broker

**Location**: `firmware/mqtt/`

**Service**: Eclipse Mosquitto 2 via Docker

**Configuration**:
- Auth required: `allow_anonymous false`
- Credentials: Read from env (injected via docker-compose)
- TLS: Disabled (LAN-only MVP; must add before internet exposure)
- Topics: Documented in `firmware/mqtt/README.md`

**Test Commands**:
```bash
mosquitto_pub -h localhost -u user -P pass -t home/door/motion -m '{"ts":1234,"motion":true}'
mosquitto_sub -h localhost -u user -P pass -t home/room/presence
```

### Secrets & Configuration

Each node has:
- `include/config.h.example` (checked in): template with placeholder values
- `include/config.h` (gitignored): actual secrets (WIFI_SSID, WIFI_PASS, MQTT_HOST/PORT/USER/PASS)

### Known Issues & Blockers

| Issue | Impact | Status |
|-------|--------|--------|
| GPIO7 bootstrap check | May conflict with ESP32-S2 boot-strapping; must verify before soldering door-node PIR | ⏳ Pending hardware check |
| LD2410 UART parsing | Currently MVP uses digital pin only; full UART parsing deferred | ⏳ Deferred to phase 2 |
| No hardware flash test | Code compiles clean but untested on real S2 Mini | ⏳ Pending hardware |

---

## Shared Patterns

### Language & Naming Conventions

| Aspect | Convention | Rationale |
|--------|-----------|-----------|
| Code identifiers | English (camelCase for functions, SCREAMING_SNAKE_CASE for constants) | Cross-language consistency, maintainability |
| Comments & logs | Vietnamese (in firmware), English (in Go) | Matches developer's native language and Go ecosystem norm |
| File names | kebab-case (Go internal packages), no special rules (firmware .cpp) | Project consistency |

### No Shared Firmware Library

Each node (door, room) is a standalone PlatformIO project. Rationale:
- Different sensor sets (PIR vs. radar vs. IR)
- Simpler dependency management per node
- Easier to flash/debug independently
- Acceptable duplication for MVP (MQTT client, WiFi init)

### Error Handling

- **Go**: slog structured logging (not shown in this summary but present in code)
- **Firmware**: Serial print for debugging; MQTT reconnect loop on broker failure

### Testing Strategy

- **Go**: Table-driven unit tests with scenario names; state machine fully tested
- **Firmware**: No unit tests yet (depends on hardware; integration test via MQTT expected)

---

## Summary Statistics

| Component | LOC | Files | Status |
|-----------|-----|-------|--------|
| Backend (Go) | ~874 | 11 | ✅ Code-complete, end-to-end verified |
| Firmware (both nodes) | ~520 | 2 | ⏳ Code-complete, hardware pending |
| Documentation | — | This file + system-wiring.md | ⏳ Expanding |
| **Total** | **~1394** | **13+** | **⏳ MVP code-complete** |

## Next Steps

See [`docs/project-roadmap.md`](./project-roadmap.md) for detailed phase tracking and open action items.
