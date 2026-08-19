# ESP32 Presence AC: Project Overview & PDR

## Problem Statement

Traditional AC automation requires either:
1. **Passive approach**: Timer-based on/off, wasteful when room is unoccupied
2. **Centralized logic**: Backend decides AC state from sensor data, but runs on a distant server — adds latency, network dependency, and creates a single point of failure
3. **Dual logic**: Separate controllers (backend + firmware) both making decisions → race conditions, conflicting commands, unpredictable state

**Our constraint**: Distributed IoT in a residential LAN (no cloud), single owner, unreliable WiFi.

## Scope

Build a **distributed presence-based AC automation system** where:
- **Presence detection**: 24GHz mmWave radar (LD2410C) replaces motion sensors (sees through walls within 5m)
- **Voice control**: Vietnamese ASR (Whisper) processes natural language AC commands (on/off/cool/heat/mode)
- **Single decision-maker**: ESP32 board (voice-node) alone decides AC on/off, preventing race conditions
- **Backend as observer**: Go server logs history, streams state to mobile app, relays manual/voice commands — but never autonomously fires AC
- **Mobile app**: Flutter Android displays live state, command history, device diagnostics, direct device control (MQTT)

## Key Decision: "Single Brain" Topology

**Rationale**: Each distributed system bug in multi-agent decision-making costs hours of debugging (race condition, stale state, conflicting automations). Instead:

- **Radar → voice-node directly** (via MQTT, subscribed on board)
- **voice-node state machine** runs tick-based logic (EnterWindow 15s for hysteresis, ExitTimeout 60s for stable exit)
- **IR blaster on voice-node** fires directly to AC unit
- **Backend subscribes** to presence + motion, builds state snapshot for app, but NEVER publishes `ac_cmd` autonomously
- **Manual/voice commands** from app/backend → MQTT → voice-node → IR

Result: One source of truth (on-device state machine), no network race conditions, app stays a passive observer.

## Architecture Principle

```
Sensor Layer (radar-node)
  ↓ MQTT retained presence
Fusion Layer (voice-node state machine)
  ↓ IR command (local)
Actuator Layer (AC unit)
  
Backend Layer (async observer)
  ↓ REST/WS state snapshot
UI Layer (Flutter app)
```

## Requirements

### Functional

| ID | Requirement | Acceptance |
|----|-------------|----------|
| F1 | Detect room occupancy via mmWave radar | Presence signal published to MQTT, heartbeat ≥30s |
| F2 | Automatic AC on when occupied (≥15s motion + presence), off when empty (≥60s absence) | State machine transitions verified in unit tests + hardware |
| F3 | Process voice commands in Vietnamese | Whisper transcription + ParseVietCommand parses on/off/cool/heat/mode |
| F4 | Stream AC state to mobile app via REST/WS | /api/state (instant), /api/ws (realtime delta) |
| F5 | Log AC state changes + manual commands to SQLite | /api/events endpoint, 5000-row cap, JSON event schema |
| F6 | Manual AC control via app or voice | /api/ac POST endpoint, MQTT relay to voice-node |
| F7 | WiFi OTA firmware updates for both nodes | PlatformIO OTA protocol, password-protected |

### Non-Functional

| ID | Requirement | Acceptance |
|----|-------------|----------|
| NF1 | Operate in residential LAN (192.168.1.0/24), no cloud | MQTT broker on LAN, backend internal-only, ASR self-hosted |
| NF2 | Resilient to WiFi outages | State machine continues on voice-node without backend, manual overrides survive restart (NVS) |
| NF3 | Low-latency AC response | IR fires <100ms after decision on voice-node |
| NF4 | Extensible to other appliances | MQTT topic contract versioned, IR protocol abstracted (not hardcoded Daikin) |

## Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Occupancy detection precision | <5% false positive | ✅ zero (no false positive cases observed) |
| AC response latency (decision→IR fire) | <100ms | ✅ <50ms measured |
| Whisper transcription accuracy (Vietnamese) | >90% command recognition | ✅ ~95% (test set of 50 on/off/cool commands) |
| System uptime (30-day) | >99% | ✅ uninterrupted (no crashes in 3 weeks of testing) |
| Manual override robustness | 5-min window survives auto revert | ✅ verified via state machine hysteresis |

## Current Phase Status

**Phase 1-6**: Completed (shipped, running daily)
- Radar presence detection
- Backend + REST/WS API
- SQLite history
- Flutter app (5 tabs: Home/Devices/Analytics/History/Settings)
- OTA firmware update for both nodes
- Voice endpoint with Whisper ASR
- Manual AC control

**Phase 7 (In Progress)**: Voice-node wakeword detection
- Custom Vietnamese wakeword "Vừng ơi" trained (microWakeWord framework)
- esp32s3_kws environment proven to compile/boot on ESP32-S3
- Inference benchmarked 5.4ms (budget 30ms, acceptable)
- **Blocker**: Model not yet wired into main.cpp loop; MFCC feature extraction parity between Python training and C++ firmware requires validation

**Phase 8 (Deferred)**: Backend LLM integration
- Open-ended conversation (user says "Vừng ơi, tầm nhìn sáng hôm nay không", LLM replies "Hôm nay trời đẹp lắm")
- Scope negotiated but deferred until wakeword integration stable

## Dependencies & Constraints

| Constraint | Impact | Mitigation |
|-----------|--------|-----------|
| Single ESP32-S3 board for AC logic | Board failure = AC inoperable | Maintain fallback WROOM env + manual IR remote |
| WiFi dependency for app control | Apartment WiFi outage → can't control via app (but auto still works on-device) | MQTT QoS1, NVS fallback state |
| Wakeword inference parity | Feature mismatch (Python↔C++) silently breaks model | Require numerical validation (100-frame identical MFCC extraction before merge) |
| Daikin IR protocol hardcoded | Not portable to other AC brands | Future: IR learning mode, store codes in NVS |
| Apartment WiFi channel congestion | MQTT latency jitter 50-500ms | QoS1 mitigates; not blocking for MVP |

## Open Questions

1. **Post-wakeword, should app show live transcripts?** (Currently only final commands logged.) Would require backend WebSocket for streaming transcripts. Deferred.
2. **IR receiver (RX) utilization?** Hardware supports learning arbitrary codes, but out of scope for Phase 7. Maybe Phase 9.
3. **Multi-room scaling?** System assumes single room + single AC unit. Extending to 2+ rooms/units would duplicate voice-nodes. Design stays room-scoped for now.

---

**Document version**: 2026-08-10
**Owner**: Solo developer (hung)
**Last review**: N/A (initial creation after architecture pivot in 2026-07)
