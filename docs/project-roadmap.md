# Project Roadmap

## Overview

The project is organized into four phases that build incrementally: a two-node MVP for presence detection and AC control, a backend state machine, a voice-capable node, and a mobile app frontend.

**Current Status**: Phase 1 & 2 code-complete; firmware hardware verification pending; backend end-to-end verified.

> **Cập nhật 2026-07-15 — nâng cấp fusion + voice** (xem `plans/260715-2047-sensor-fusion-presence-voice-node/`):
> - **Kiến trúc gộp còn 2 node vật lý:** PIR gộp vào node radar (S2 Mini) → **fusion PIR+radar NGAY TẠI BOARD** (không chỉ ở backend). Door-node riêng nghỉ hưu cho MVP 1 phòng. Firmware room-node đã cập nhật, build pass — chờ verify phần cứng.
> - **Voice (Phase 3) chốt hướng + làm phần backend:** ASR = **faster-whisper self-host** (container `asr/` cạnh backend). Backend voice endpoint `/api/voice/stream` + VAD + parse lệnh Việt → `ac_cmd` **đã xong, build/test xanh, review APPROVE**. Còn lại: firmware voice-node WROOM-32 (đang làm) + verify phần cứng.

---

## Phase 1: Two-Node Presence + AC Control (MVP Firmware)

**Status**: ✅ **CODE-COMPLETE** | ⏳ **HARDWARE VERIFICATION PENDING**

**Objective**: Implement dual-sensor occupancy detection (motion + presence) and AC IR control on two Wemos S2 Mini nodes over MQTT.

### Deliverables

| Component | Status | Notes |
|-----------|--------|-------|
| Door Node (PIR firmware) | ✅ Code done, PlatformIO compiles clean | `firmware/door-node/src/main.cpp` (112 LOC) |
| Room Node (Radar + IR firmware) | ✅ Code done, PlatformIO compiles clean | `firmware/room-node/src/main.cpp` (246 LOC) |
| MQTT Broker Config | ✅ Done | `firmware/mqtt/docker-compose.yml` + Mosquitto auth |
| MQTT Topic Contract | ✅ Documented | 4 topics: motion, presence (retained), ac_cmd, ac_learn |

### Open Action Items (Blocking Hardware Flash)

1. **⚠️ GPIO7 Bootstrap Safety Check** (CRITICAL)
   - **Issue**: Door node uses GPIO7 for PIR interrupt. ESP32-S2 may use GPIO7 for boot-strapping; soldering PIR without verification risks bricking node.
   - **Action**: Before soldering PIR hardware, confirm ESP32-S2 boot-strapping pins via datasheet or community verification.
   - **Owner**: Developer (pending hardware inspection)
   - **Blockers**: Firmware flashing on real hardware

2. **Flash & Verify on Real Hardware**
   - **Action**: Once GPIO7 confirmed safe, flash firmware to both S2 Mini boards via USB serial.
   - **Acceptance**: Both nodes boot, connect to WiFi, connect to Mosquitto, publish/subscribe to correct topics.
   - **Owner**: Developer
   - **Depends on**: GPIO7 check

3. **Integration Test: MQTT End-to-End**
   - **Action**: Trigger PIR, verify motion event reaches Mosquitto and backend. Trigger presence, verify ac_cmd is published back.
   - **Acceptance**: Full occupancy → AC on, then unoccupied → AC off cycle works.
   - **Owner**: Developer
   - **Depends on**: Hardware flash + Phase 2 backend running

### Risks

- **GPIO7 conflict** → firmware won't boot on hardware
- **LD2410 radar soldering issues** → presence detection fails
- **IR receiver/blaster wiring** → AC commands not sent

### Success Criteria

- [ ] Door and room nodes flash without errors
- [ ] Both nodes connect to local Mosquitto broker
- [ ] MQTT topics appear in broker (verify with `mosquitto_sub`)
- [ ] PIR triggers publish motion events
- [ ] LD2410 publishes presence state changes
- [ ] Backend receives all MQTT events and transitions state correctly

---

## Phase 2: Go Backend (State Machine + REST API)

**Status**: ✅ **CODE-COMPLETE & VERIFIED** (against simulated MQTT)

**Objective**: Implement presence state machine, REST API, and WebSocket broadcast for clients.

### Deliverables

| Component | Status | Notes |
|-----------|--------|-------|
| Config parsing | ✅ Done | Env vars: MQTT_*, HTTP_*, timing params |
| MQTT client wrapper | ✅ Done | Paho client, auto-reconnect, publish/subscribe |
| State machine | ✅ Done & tested | 6/6 scenario tests passing (enter, exit, debounce, flicker) |
| REST API | ✅ Done | GET /healthz, /api/state; POST /api/ac, /api/ac/learn |
| WebSocket hub | ✅ Done | Broadcasts state snapshot on change |
| Docker image | ✅ Done | Multi-stage build, distroless runtime |

### Verification Status

- ✅ Code compiles cleanly with `go build`
- ✅ All unit tests pass (`go test ./...`)
- ✅ End-to-end test: Simulated MQTT events (via `mosquitto_pub`) trigger correct state transitions
- ✅ Docker image builds and runs with `.env` file
- ⏳ **Pending**: Real firmware integration test (waiting for Phase 1 hardware)

### Open Action Items

1. **Real Firmware Integration Test**
   - **Action**: Once Phase 1 hardware verified, run backend against live door and room nodes.
   - **Acceptance**: Full occupancy/vacancy cycle observed through REST API and WebSocket.
   - **Owner**: Developer
   - **Depends on**: Phase 1 complete

2. **Timing Parameter Tuning**
   - **Action**: Run real-world tests to validate/adjust ENTER_WINDOW_S (15s) and EXIT_TIMEOUT_S (60s).
   - **Rationale**: Current defaults are educated guesses; tuning needed for typical household movement patterns.
   - **Owner**: Developer (post-MVP)
   - **Acceptance**: State machine behavior matches user expectations (no false occupancy/vacancy swings)
   - **Depends on**: Phase 1 hardware

### Known Limitations (Acceptable for MVP)

- In-memory state only (no SQLite persistence)
- No API authentication (LAN-only assumption)
- CORS wide open (will tighten before internet exposure)
- No request rate limiting

### Success Criteria

- [ ] Backend starts without errors: `docker-compose up`
- [ ] `/healthz` reports MQTT connected
- [ ] `/api/state` returns current state
- [ ] `/api/ac` commands AC on/off
- [ ] WebSocket broadcasts state changes in real-time
- [ ] Real firmware integration: E2E occupancy/vacancy cycle works

---

## Phase 3: Voice Node (ESP32-WROOM-32 + INMP441 Microphone)

**Status**: 🟡 **IN PROGRESS** (2026-07-15) — ASR chốt = **faster-whisper self-host**; backend voice endpoint + ASR service **DONE** (build/test xanh); firmware voice-node WROOM-32 đang làm; verify E2E chờ phần cứng. Chi tiết: `plans/260715-2047-sensor-fusion-presence-voice-node/`.
> Các "Open Questions" ASR/wake-word/streaming bên dưới đã được chốt trong plan mới (self-host whisper `small`, VAD năng lượng trên device, WS PCM 16k mono 16-bit LE) — giữ lại đây làm bối cảnh lịch sử.

**Objective**: Add voice wake-word detection ("chào nhân viên ơi" or similar) and send audio to server-side ASR for command interpretation.

### Decision Context

- **Why ESP32-WROOM-32, not S2 Mini?** S2 Mini lacks PSRAM and dual-core needed for local voice processing
- **Why no local ASR?** ESP32-S3 (with PSRAM) could run Whisper, but no ESP-SR support for Vietnamese yet
- **Architecture**: Mic → wake-word detect (local) → audio stream to backend → ASR provider → interpreted command → backend action

### Deliverables (Design Only)

| Item | Status | Notes |
|------|--------|-------|
| Hardware: WROOM-32 + INMP441 | 🔴 Deferred | Chosen board; wiring TBD |
| Wake-word detection | 🔴 Deferred | Local on WROOM-32; model TBD |
| Audio streaming to backend | 🔴 Deferred | Protocol TBD (WebSocket? MQTT? RTP?) |
| ASR provider integration | 🔴 Deferred | Cloud (Google, Azure, AWS) or self-hosted Whisper? **Decision pending** |
| Voice command parser | 🔴 Deferred | Map "bật điều hòa" → AC on, etc. |

### Open Questions

1. **ASR Provider** (BLOCKING)
   - Option A: Self-hosted Whisper (Python server, ~1-2GB VRAM, low cost, full privacy)
   - Option B: Google Cloud Speech-to-Text ($$$ per request, Vietnamese support good, no setup)
   - Option C: Azure Cognitive Services (similar cost/features to Google)
   - **Decision timeline**: Before Phase 3 implementation starts

2. **Wake-Word Model**
   - What phrase to use? (e.g., "Chào nhân viên" = "Hello assistant" in Vietnamese)
   - Local model: PicovoiceWake on WROOM-32 is possible but requires commercial license
   - Alternative: Stream all audio to backend, filter server-side (simpler, less local compute)

3. **Audio Streaming Protocol**
   - Real-time low-latency OPUS codec over WebSocket?
   - Or simple 16-bit PCM chunks?
   - Trade-off: quality vs. bandwidth

### Risks & Constraints

- **Latency**: Voice to command execution must be < 2s for good UX
- **Network**: Voice streaming over WiFi may be noisy (typical WiFi jitter 50-200ms)
- **Privacy**: Streaming audio to external ASR exposes user commands; self-hosted Whisper keeps data local
- **Cost**: Cloud ASR (Google/Azure) can be expensive at scale

### Success Criteria (When Started)

- [ ] Wake-word detection triggers on valid phrase, not on background noise/speech
- [ ] Audio quality sufficient for ASR (clear at 1m, rejected if too noisy)
- [ ] ASR latency < 2s from audio capture to backend action
- [ ] Commands correctly interpreted in Vietnamese
- [ ] Graceful fallback if ASR fails (log + do nothing, user retries)

### Dependencies

- Phase 2 backend must be internet-exposed (or at least accessible from voice node)
- ASR provider account (cloud or self-hosted Whisper server) running

---

## Phase 4: Flutter Mobile App (Future)

**Status**: 🔴 **NOT STARTED** | Deferred until backend is stable

**Objective**: Mobile app (iOS/Android) consuming backend REST and WebSocket APIs.

### Deliverables (Conceptual Only)

| Feature | Status | Notes |
|---------|--------|-------|
| Home screen (occupancy state + AC status) | 🔴 Not started | Real-time via WebSocket |
| Manual AC control (on/off) | 🔴 Not started | POST /api/ac |
| IR learning UI | 🔴 Not started | POST /api/ac/learn + user feedback |
| Settings (timing params, Mosquitto host) | 🔴 Not started | May or may not expose to users |
| Push notifications (optional) | 🔴 Not started | Alert user when room state changes |

### Tech Stack (Proposed)

- **Framework**: Flutter 3.x (cross-platform iOS/Android)
- **State management**: Provider or Riverpod
- **API client**: Dio (HTTP) + WebSocket package
- **Storage**: Hive or Shared Preferences (for app settings)

### Risks

- **Backend API stability**: App will break if backend API changes (versioning strategy needed)
- **Permissions**: WiFi location access, notification permissions per platform
- **Testing**: Device testing on iOS and Android needed (emulator testing insufficient)

### Success Criteria (When Started)

- [ ] App connects to backend API and displays current state
- [ ] AC on/off commands work
- [ ] WebSocket state updates appear in real-time (< 1s latency)
- [ ] IR learning flow is intuitive
- [ ] App gracefully handles backend offline

### Dependencies

- Phase 2 backend stable and RESTful
- Backend API versioning or stability guarantee
- Deployment mechanism (App Store / Google Play or in-house beta)

---

## Timeline & Priority

| Phase | Priority | Est. Start | Blocker | Status |
|-------|----------|------------|---------|--------|
| 1 | 🟥 **Highest** | ✅ Done (code) | GPIO7 check | ⏳ Hardware pending |
| 2 | 🟥 **Highest** | ✅ Done | Phase 1 HW | ✅ Code done, testing pending |
| 3 | 🟨 **Medium** | Q3 2026 | ASR decision | 🔴 Deferred |
| 4 | 🟩 **Low** | Q4 2026 | Phase 2 stable | 🔴 Not started |

---

## Acceptance & Sign-Off

### Phase 1 Complete When

- [ ] Both firmware nodes flash successfully
- [ ] MQTT broker and backend receive correct events
- [ ] Full occupancy/vacancy cycle works end-to-end
- [ ] No unresolved GPIO or wiring issues

### Phase 2 Complete When

- [ ] Backend passes all unit tests
- [ ] E2E test against real firmware nodes passes
- [ ] Timing parameters tuned for real household
- [ ] Backend deployable via Docker Compose

### Phase 3 Decision When

- [ ] ASR provider chosen and evaluated
- [ ] Wake-word model sourced (commercial, open-source, or custom)
- [ ] Audio streaming protocol specified
- [ ] Backend supports voice commands endpoint

### Phase 4 Start When

- [ ] Phase 2 backend is stable (no breaking API changes expected)
- [ ] Phase 3 (if started) is working
- [ ] User feedback available to inform app features

---

## Open Questions & Decisions Pending

| Question | Impact | Timeline |
|----------|--------|----------|
| GPIO7 safety on ESP32-S2 | Phase 1 blocker | Before soldering (~now) |
| Enter/exit window tuning (15s/60s) | Phase 2 accuracy | After Phase 1 hardware |
| ASR provider (self-hosted vs. cloud) | Phase 3 direction | Before Phase 3 starts |
| SQLite event history | Phase 2 scope | Currently YAGNI; revisit if debugging needs arise |
| Multi-room support | Phase 1+ scope | Currently single room; expand if needed |
| TLS/mTLS for MQTT | Security gate | Before any internet exposure |
| API authentication for backend | Security gate | Before any internet exposure |

---

## Related Documentation

- [`docs/project-overview-pdr.md`](./project-overview-pdr.md) — Product scope and decisions
- [`docs/system-architecture.md`](./system-architecture.md) — System design and MQTT contract
- [`docs/codebase-summary.md`](./codebase-summary.md) — Code overview per phase
- [`plans/`](../plans/) — Detailed phase plans and decision logs
