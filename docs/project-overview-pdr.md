# Project Overview & PDR

## Project Name
**ESP32-based Home Presence Detection + Automatic AC Control System**

Also referenced as: "Hệ thống presence + AC + voice" in development comments.

## Problem Statement

Manual air conditioning (AC) control in homes is wasteful:
- Users often forget to turn off AC when leaving rooms
- Running AC in unoccupied spaces wastes electricity
- No intelligent occupancy detection triggers AC control

## Solution

A distributed, MQTT-based system that:
1. Detects room occupancy via dual-sensor approach (motion + presence)
2. Automatically controls AC power based on occupancy state
3. Learns AC infrared control codes without external cloud services
4. Provides a REST API and WebSocket interface for monitoring and manual override

## Scope

### MVP Phase (Current - Phases 1-2)
- **Two-node firmware** (Wemos S2 Mini ESP32-S2):
  - Door node: PIR motion sensor (GPIO7)
  - Room node: HLK-LD2410 presence radar (GPIO16) + IR learning/blaster (GPIO5)
- **MQTT broker**: Mosquitto (authenticated, no TLS - LAN-only MVP)
- **Go backend**: State machine for occupancy logic, REST API, WebSocket broadcast
- **Status**: Code complete, firmware not yet hardware-verified, backend verified against simulated MQTT

### Future Phases (Deferred)
- **Phase 3**: Voice node (ESP32-WROOM-32 + INMP441 mic) → backend ASR provider
- **Phase 4**: Flutter mobile app consuming backend REST/WS API

## Key Product Decisions

| Decision | Rationale | Status |
|----------|-----------|--------|
| **Indirect occupancy inference** (motion + presence, not 2 PIRs) | LD2410 radar alone drifts; dual sensor provides reliable debouncing. Cost/complexity optimal for MVP. | Locked |
| **MQTT as transport** | Decouples firmware from backend logic; standard for IoT; enables future device integrations. | Locked |
| **Local-only IR code storage** (no backend sync) | Reduces complexity; room AC is stateful, not highly portable. Revisit if multi-room IR learning needed. | Deferred for later phases |
| **LAN-only (no TLS, no internet exposure)** | MVP expedience; reduces crypto overhead on ESP32. Must add TLS before any remote access. | Documented constraint |
| **Debounce + enter/exit windows** (15s enter, 60s exit) | Prevents flicker from brief room transitions. Configurable; needs real-world tuning. | Proposed, not yet validated |

## Architecture Overview

```
[Door PIR] ──┐
             ├──► MQTT Broker (Mosquitto)  ──► Go Backend  ──► REST/WS API
[Room Radar] ┘                                 (State Machine)
[Room IR]    ─────────────────────────────────────────────────►
```

- **MQTT Topics** (See [`docs/system-architecture.md`](./system-architecture.md) for full contract):
  - `home/door/motion`: PIR events from door node
  - `home/room/presence`: LD2410 presence state (retained)
  - `home/room/ac_cmd`: Backend commands AC on/off
  - `home/room/ac_learn`: Backend triggers IR learn mode

## Non-Goals (Deferred or Out of Scope)

- Cloud connectivity (MVP is LAN-only)
- Multi-room/multi-AC support (single room MVP)
- Voice commands (Phase 3, ASR provider TBD)
- Mobile app (Phase 4, not started)
- Historical event logging (SQLite deferred as YAGNI)
- Advanced ML occupancy detection (direct inference only)

## Open Questions & Decisions Pending Real-World Testing

1. **GPIO7 safety on door-node**: Confirm GPIO7 is not reserved for ESP32-S2 boot-strapping before soldering PIR wiring.
2. **Enter/Exit window tuning**: 15s enter / 60s exit proposed; needs validation against real household movement patterns.
3. **ASR provider (Phase 3)**: Self-hosted Whisper vs. cloud-based ASR undecided; blocks voice node architecture.
4. **Event history**: SQLite persistence initially deferred; may be needed if real-world debugging requires audit log.

## Hardware Manifest

See [`docs/system-wiring.md`](./system-wiring.md) (Vietnamese) for detailed pin-maps and wiring diagrams.

- **Door Node**: Wemos S2 Mini + PIR (HC-SR501)
- **Room Node**: Wemos S2 Mini + HLK-LD2410 (radar) + IR receiver (TSOP38238) + IR blaster (GPIO5 → transistor)
- **Broker**: Raspberry Pi or similar running Mosquitto
- **Backend**: Go service (Docker or native Linux binary)

## Success Metrics

- ✅ Firmware compiles for both nodes without errors
- ⏳ Firmware flashes and runs on real S2 Mini hardware (pending GPIO7 check)
- ✅ Go backend compiles and starts cleanly
- ✅ E2E test: Backend correctly infers occupied/empty state via MQTT events
- ⏳ Real-hardware integration: All nodes communicate via Mosquitto on local network
- ✅ Manual override: REST API ac_cmd endpoint controls IR blaster successfully

## Development Notes

- **Language mix**: Code identifiers are English; firmware comments and logs are Vietnamese (solo developer's native language). This is intentional and documented in [`docs/code-standards.md`](./code-standards.md).
- **Test coverage**: Go backend has 6/6 scenario tests passing. Firmware unit tests deferred pending hardware verification.
- **No persistence**: In-memory state machine only; no database yet (aligns with MVP YAGNI principle).
