# ESP32 Home Presence Detection + Automatic AC Control

A distributed IoT system for detecting room occupancy (motion + presence sensors) and automatically controlling air conditioning via infrared learning.

**Status**: MVP code-complete (firmware compiles, backend verified); hardware integration pending.

## Quick Start

### Architecture

```
┌─ Firmware (2x ESP32-S2)
│  ├─ Door Node: PIR motion sensor
│  └─ Room Node: LD2410 radar + IR learning/blaster
│
├─ MQTT Broker (Mosquitto, authenticated)
│
└─ Go Backend: REST API + WebSocket + state machine
```

See [`docs/system-architecture.md`](./docs/system-architecture.md) for detailed diagram and data flow.

### Current Phase

**Phase 1 & 2** (MVP):
- ✅ Firmware code written and compiles clean
- ✅ Go backend code written, unit tests passing, end-to-end verified against simulated MQTT
- ⏳ Awaiting hardware verification of ESP32-S2 nodes (GPIO7 safety check required before soldering)

**Phase 3 & 4** (Future):
- Voice node with ASR (deferred, provider decision pending)
- Flutter mobile app (not started)

## Directory Map

| Directory | Purpose |
|-----------|---------|
| `backend/` | Go REST API, state machine, MQTT client (~874 LOC, 11 files) |
| `firmware/` | PlatformIO projects for door and room nodes (~520 LOC, 2 nodes) + Mosquitto broker config |
| `docs/` | Technical documentation (this README, architecture, roadmap, standards) |
| `plans/` | Implementation phase logs and decision records |

## Documentation

Start here based on your needs:

| Document | For | Contents |
|----------|-----|----------|
| [`docs/project-overview-pdr.md`](./docs/project-overview-pdr.md) | Product leads | Problem statement, scope, key decisions, success metrics |
| [`docs/system-architecture.md`](./docs/system-architecture.md) | System designers | Architecture diagram, MQTT contract, data flows, REST API |
| [`docs/codebase-summary.md`](./docs/codebase-summary.md) | New developers | Code structure, entry points, module responsibilities |
| [`docs/code-standards.md`](./docs/code-standards.md) | Contributors | Naming conventions, Go/firmware patterns, testing strategy |
| [`docs/project-roadmap.md`](./docs/project-roadmap.md) | Project managers | Phase status, open action items, blocking issues |
| [`docs/system-wiring.md`](./docs/system-wiring.md) | Hardware integrators | Pin diagrams, sensor wiring, MQTT topics (Vietnamese) |

## Setup

### Backend (Go)

```bash
cd backend

# Build locally
go build ./cmd/server

# Or via Docker
docker-compose up -d

# Check health
curl http://localhost:8080/healthz
curl http://localhost:8080/api/state
```

**Requirements**: Go 1.24+ or Docker  
**Config**: Environment variables (see [`docs/codebase-summary.md`](./docs/codebase-summary.md#configuration-environment-variables))

### Firmware (ESP32)

```bash
cd firmware

# Door node
cd door-node
pio run -t upload  # Requires PlatformIO CLI + USB serial connection

# Room node
cd ../room-node
pio run -t upload
```

**Requirements**: PlatformIO CLI + Wemos S2 Mini boards + sensors  
**Secrets**: Copy `include/config.h.example` to `config.h`, fill in WiFi/MQTT credentials

### MQTT Broker

```bash
cd firmware/mqtt
docker-compose up -d

# Verify
mosquitto_sub -h localhost -u test -P test -t '$SYS/#'
```

**Status**: Mosquitto 2 with authentication, no TLS (LAN-only MVP).

## API Examples

```bash
# Get occupancy state
curl http://localhost:8080/api/state
# {"state":"occupied","present":true,"ac_on":true,...}

# Turn AC on (manual override)
curl -X POST http://localhost:8080/api/ac -H "Content-Type: application/json" -d '{"cmd":"on"}'

# Initiate IR learning for AC "on" button
curl -X POST http://localhost:8080/api/ac/learn -H "Content-Type: application/json" -d '{"button":"on"}'

# WebSocket for real-time updates
wscat -c ws://localhost:8080/ws
# Will receive state updates on every change
```

## MQTT Topics

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `home/door/motion` | Door → Backend | PIR motion events |
| `home/room/presence` | Room → Backend | LD2410 presence state (retained) |
| `home/room/ac_cmd` | Backend → Room | AC on/off commands |
| `home/room/ac_learn` | Backend → Room | Trigger IR learning window |

See [`docs/system-architecture.md`](./docs/system-architecture.md#mqtt-topic-contract) for full details.

## Development

### Code Conventions

- **Backend (Go)**: Idiomatic Go, interfaces at point of use, table-driven tests
- **Firmware (C++)**: English identifiers, Vietnamese comments, camelCase functions, SCREAMING_SNAKE_CASE constants

See [`docs/code-standards.md`](./docs/code-standards.md) for full style guide.

### Testing

```bash
# Backend
cd backend
go test ./...  # 6/6 state machine tests passing

# Firmware
cd firmware/door-node
pio run        # Compile check (no unit tests yet; integration test via MQTT)
```

### Contributing

1. Read [`docs/code-standards.md`](./docs/code-standards.md) before coding
2. Adhere to naming conventions and patterns documented there
3. Add tests for new behavior (Go) or verify MQTT output (firmware)
4. Update `docs/` if behavior, API, or architecture changed
5. Follow commit messages: descriptive, no AI references

## Current Blockers

| Blocker | Impact | Status |
|---------|--------|--------|
| **GPIO7 safety check on ESP32-S2** | Phase 1 hardware | Door node PIR wiring pending boot-pin verification |
| **Real hardware flash test** | Phase 1 & 2 integration | Firmware untested on actual boards |
| **Timing parameter tuning** | Phase 2 accuracy | Enter/exit windows (15s/60s) need real-world validation |
| **ASR provider decision** | Phase 3 blocking | Voice node architecture depends on Whisper vs. cloud ASR choice |

See [`docs/project-roadmap.md`](./docs/project-roadmap.md) for detailed phase status and action items.

## Security Notes

🔒 **Current (MVP/LAN-only)**:
- MQTT auth: Username/password (no TLS)
- REST API: No auth (LAN-only assumption)
- CORS: Wide open (intentional MVP)
- IR codes: Stored locally on room node only

⚠️ **Before internet exposure**:
- [ ] Add TLS/mTLS to MQTT broker
- [ ] Add API authentication (tokens or OAuth)
- [ ] Tighten CORS to specific frontend origin
- [ ] Add rate limiting to REST endpoints

## Known Limitations

- Single room (no multi-room support yet)
- No event history (in-memory state only; SQLite deferred as YAGNI)
- No firmware OTA updates (manual USB flash only)
- Voice control deferred (Phase 3, not started)
- Mobile app deferred (Phase 4, not started)

## Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| Backend can't connect to Mosquitto | `docker ps \| grep mosquitto` | Ensure `docker-compose up -d` in `firmware/mqtt/` |
| Room node not receiving ac_cmd | `mosquitto_sub -t 'home/room/ac_cmd'` | Check room node MQTT subscription code |
| IR blaster not firing | Test GPIO5 directly with LED | Verify transistor driver circuit and NVS storage |
| PIR not triggering | Check GPIO7 with multimeter | Confirm no boot-strap conflict |

More at [`docs/system-architecture.md#monitoring--troubleshooting`](./docs/system-architecture.md#monitoring--troubleshooting).

## Roadmap

| Phase | Status | Timeline |
|-------|--------|----------|
| 1: Two-node presence + AC (firmware) | ✅ Code done, ⏳ HW pending | Q3 2026 |
| 2: Go backend | ✅ Code done, ✅ verified | Q3 2026 |
| 3: Voice node + ASR | 🔴 Deferred | Q3 2026+ (decision pending) |
| 4: Flutter app | 🔴 Not started | Q4 2026+ |

See [`docs/project-roadmap.md`](./docs/project-roadmap.md) for details.

## Author

Solo IoT project by Vietnamese engineer. Code identifiers in English; firmware comments in Vietnamese (intentional convention documented in [`docs/code-standards.md`](./docs/code-standards.md)).

## License

(To be determined; project currently undeclared)

---

**Last updated**: 2026-07-14  
**Next review**: After Phase 1 hardware verification
