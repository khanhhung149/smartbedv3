# Project Roadmap

**Owner**: Solo developer (hung)  
**Current version**: 2026-08-10  
**Last major update**: Pivoted wakeword integration to Phase 7 (2026-08-10)

## Phase Summary

| Phase | Name | Status | Key Deliverable | Shipped |
|-------|------|--------|-----------------|---------|
| 1 | Radar Presence Detection | ✅ Complete | LD2410C → MQTT `home/room/presence` | 2026-04 |
| 2 | Backend + State Machine + API | ✅ Complete | Go server REST/WS, SQLite history | 2026-05 |
| 3 | Voice-Node Fusion + IR | ✅ Complete | ESP32 auto AC + manual override | 2026-06 |
| 4 | Flutter App | ✅ Complete | 5-tab UI, Riverpod state mgmt | 2026-07 |
| 5 | OTA Firmware Update | ✅ Complete | PlatformIO OTA for 2 nodes | 2026-07 |
| 6 | Voice Command Input (ASR) | ✅ Complete | Whisper Vietnamese → ParseVietCommand | 2026-07 |
| 7 | Wakeword Detection (Edge) | 🔬 In Progress | Custom Vietnamese "Vừng ơi" on-device inference | 2026-08 |
| 8 | Hardware Enclosure | ⏳ Pending | 3D print modular case (STL ready) | Q3 2026 |
| 9 | LLM Conversation Backend | 📋 Deferred | Free-form chat (Gemini API) + history tab | Post-Phase 7 |
| 10 | IR Learning + Remote Config | 📋 Backlog | Store arbitrary IR codes in NVS, app remote tab | Backlog |

## Phase Details

### Phase 1: Radar Presence Detection ✅

**Dates**: 2026-03 to 2026-04  
**Goal**: Proof of concept — radar detects occupancy via MQTT

**Deliverables**:
- [x] radar-node code (LD2410C native UART → Mosquitto)
- [x] MQTT topic contract (`home/room/presence` retained)
- [x] Docker Mosquitto broker setup

**Result**: Radar reliably detects presence through walls (5m range), published to LAN MQTT, ~50ms latency.

---

### Phase 2: Backend + State Machine + API ✅

**Dates**: 2026-04 to 2026-05  
**Goal**: Backend observes sensor data, serves API for app

**Deliverables**:
- [x] Go server (chi router, MQTT client, state machine mirror)
- [x] REST API (`/api/state`, `/api/events`, `/api/ac`)
- [x] WebSocket `/api/ws` for realtime state push
- [x] SQLite store (events table, 5000-row cap)
- [x] Unit tests (state machine transitions, MQTT parsing, SQL)

**Acceptance**: State snapshot matches radar heartbeat within 1s; history logs all state changes; WebSocket delta updates at <100ms latency.

**Result**: Backend stable, no crashes in 30+ days of testing.

---

### Phase 3: Voice-Node Fusion + IR ✅

**Dates**: 2026-05 to 2026-06  
**Goal**: ESP32 auto-decides AC on/off, fires IR directly

**Deliverables**:
- [x] voice-node state machine (`EnterWindow` 15s, `ExitTimeout` 60s, hysteresis)
- [x] IR Daikin152 protocol via IRremoteESP8266 library
- [x] MQTT subscription to `home/room/presence`
- [x] Manual override (5-min grace window)
- [x] Hardware tests: presence → IR fire in <100ms

**Risk resolved**: Dual decision-makers (backend + board) eliminated in favor of single board decider.

**Result**: AC fully autonomous when WiFi is stable; manual overrides protected from immediate revert.

---

### Phase 4: Flutter App ✅

**Dates**: 2026-06 to 2026-07  
**Goal**: Mobile UI for status + manual control + history

**Deliverables**:
- [x] Flutter 3.24 + Riverpod state management
- [x] 5 tabs: Home (state + buttons), Devices (radar diagnostics), Analytics (usage), History (events), Settings (config)
- [x] REST + WebSocket clients
- [x] Direct MQTT for device polling (independent of backend)
- [x] Android APK build (release)

**Acceptance**: App stable on Nokia G42 Android 13; realtime state updates <1s; no crashes.

**Result**: App deployed to phone, daily driver use.

---

### Phase 5: OTA Firmware Update ✅

**Dates**: 2026-06 to 2026-07  
**Goal**: Update node firmware without USB

**Deliverables**:
- [x] PlatformIO OTA protocol (ArduinoOTA library)
- [x] `esp32dev_ota` and `lolin_s2_mini_ota` environments
- [x] Password-protected upload
- [x] Fallback: USB flash manually if OTA breaks WiFi
- [x] Tested: 3+ OTA cycles per node without data loss

**Result**: Nodes can be updated from desktop; no physical access needed.

---

### Phase 6: Voice Command Input (ASR) ✅

**Dates**: 2026-06 to 2026-07  
**Goal**: Process Vietnamese voice commands (on/off)

**Deliverables**:
- [x] INMP441 mic on voice-node
- [x] PCM16 WebSocket stream to backend `/api/voice/stream`
- [x] VAD-based utterance detection (silence/max/min thresholds)
- [x] ASR service (Whisper "small" model)
- [x] Vietnamese command parser (`ParseVietCommand`)
- [x] MQTT relay (`home/room/ac_cmd`)

**Testing**: score_samples.py scores 100 test utterances; on/off recognition >95%, zero false flips.

**Risk known**: Voice command confirmation not yet implemented (if misheard, wrong AC state).

**Result**: "Bật" → AC on, "Tắt" → AC off, latency <3s end-to-end.

---

### Phase 7: Wakeword Detection (Edge) 🔬 **IN PROGRESS**

**Dates**: 2026-08-10 to TBD  
**Goal**: Only process voice when "Vừng ơi" is detected (custom Vietnamese wakeword)

**Scope**:
- Enable fast, on-device wakeword inference (reduce backend load, avoid false positives)
- Retain custom Vietnamese phrase (not using ESPHome's WakeNet, which is Mandarin-biased)

**Deliverables** (planned):
- [x] microWakeWord framework training (Colab notebook)
- [x] Custom Vietnamese "Vừng ơi" model trained (tflite, ~30KB)
- [x] esp32s3_kws environment (ESP-IDF + Arduino hybrid)
- [x] Inference benchmark: 5.4ms (budget 30ms) ✅
- [ ] MFCC feature extraction parity validation (Python↔C++)
- [ ] Wire model into main.cpp loop
- [ ] Test on hardware: wakeword → mic stream; non-match → no stream

**Blockers**:
1. **Feature extraction parity**: Python training pipeline (likely librosa MFCC) vs C++ firmware (esp-dsp). Must verify pixel-perfect match on 100 test frames before merge.
2. **Model path unclear**: gen-model-header.py suggests `.h` file was generated, but working tree was corrupted (34 files deleted 2026-08-10). Phase 1 investigation will locate model in git history.

**Risk**: Silent failure mode if feature params diverge (model won't wake, no error message).

**Success criteria**:
- Numerical validation: MFCC feature arrays identical between Python↔C++ ±0.001
- Hardware test: wakeword utterance triggers mic stream; silence doesn't

**Next steps**:
1. Scout git history for trained `.tflite` model
2. Extract training config (FFT size, hop length, mfcc_num, window type, energy norm)
3. Implement C++ MFCC extractor (esp-dsp or porting Python librosa)
4. Validate 100-frame feature parity
5. Integrate into main.cpp event loop
6. Test on hardware

---

### Phase 8: Hardware Enclosure ⏳

**Dates**: TBD (after wakeword stable)  
**Goal**: 3D print modular case for voice-node

**Deliverables** (in progress):
- [x] OpenSCAD design (3-part modular: base + face + lid)
- [x] STL generation
- [x] Collision-check script (CGAL-based)
- [ ] Iterate on print fit (USB-C port height, IR LED aperture alignment)
- [ ] Final print + assembly

**Current blocker**: USB-C port clearance geometry TBD; enclosure tested with esp32dev WROOM, now must adjust for S3-DevKit.

**Timeline**: Q3 2026 (after core firmware stable).

---

### Phase 9: LLM Conversation Backend 📋 **DEFERRED**

**Dates**: TBD (post-Phase 7)  
**Goal**: Open-ended voice conversation, not just AC commands

**Scope** (negotiated but deferred):
- User says: "Vừng ơi, tầm nhìn sáng hôm nay không" (wakeword + question)
- Backend: wakeword detected → mic stream continues → Whisper transcription → Gemini LLM call → text response logged
- App: new "Chat" tab shows conversation history (SQLite + frontend rendering)
- AC logic: unchanged (only ParseVietCommand triggers IR, LLM responses are read-only)

**Why deferred**:
- Depends on Phase 7 (wakeword must be rock-solid first)
- Adds Gemini API cost/latency
- Requires SQLite schema change (new `conversation` table)
- Changes security boundary (LLM sees user queries)

**When to restart**: After Phase 7 is shipped, user signals readiness.

---

### Phase 10: IR Learning + Remote Config 📋 **BACKLOG**

**Dates**: TBD  
**Goal**: Store arbitrary AC remote codes, not just Daikin152

**Deliverables**:
- [ ] IR receiver (RX) on voice-node combo module (currently unused)
- [ ] Learning mode: app sends `/api/ac/learn` → voice-node enters learn, waits for IR signal
- [ ] NVS storage: custom IR code map
- [ ] App remote tab: buttons for learned codes
- [ ] Risk: IR learning can brick the device if button is held too long (RF interference)

**Why backlog**: Hardware supports it, but MP scope unclear (one AC unit vs. learn multiple codes). Defer until Phase 8+ is complete.

---

## Known Risks & Mitigations

| Risk | Severity | Impact | Mitigation |
|------|----------|--------|-----------|
| MFCC feature extraction parity (Phase 7) | High | Wakeword won't fire; silent failure | Numerical validation before merge |
| WiFi drop → backend unreachable | Medium | App goes offline, but AC stays autonomous | On-device state machine runs regardless |
| Concurrent Claude sessions corrupting working tree | Medium | Lose recent changes, git history safe | Sequential session protocol (not MVP) |
| SQLite 5000-row cap exceeded | Low | History stops logging | Implement rolling window (delete old rows) |
| OTA breaks WiFi code path | Low | Board reboots, OTA hangs, need USB reflash | Fallback firmware in NVS or fallback env |
| Daikin AC protocol changes (remote update) | Very Low | IR commands ignored (rare) | IR learning mode + manual remote as backup |

---

## Success Metrics (Phase Completion Checklist)

### Phase 7 (Current) Completion Criteria

- [ ] Model file located and verified in git history (`git show HEAD:firmware/voice-node/...`)
- [ ] MFCC feature extraction parameters documented (FFT size, hop length, mfcc_num, etc.)
- [ ] C++ MFCC extractor implemented and numerically validated (±0.001) vs. Python
- [ ] Model integrated into `firmware/voice-node/src/main.cpp` loop
- [ ] Hardware test: wakeword utterance triggers WebSocket stream; non-match doesn't
- [ ] Zero false positives in 50-test utterance run (background noise, speech, music)
- [ ] Inference latency ≤30ms measured on hardware (already ≤5.4ms benchmark achieved)
- [ ] PR reviewed, commits follow conventional format, zero warnings in `pio check`

### Overall Project Status (Phases 1-6)

- ✅ End-to-end system runs daily
- ✅ Zero crashes in 30+ days
- ✅ Presence detection reliable
- ✅ AC response <200ms latency
- ✅ Voice commands recognized >95%
- ✅ Manual overrides stable
- ✅ OTA proven (3+ cycles)

---

## Future Directions (Post-MVP)

1. **Internet exposure** → Add TLS/mTLS, auth, rate-limiting
2. **Multi-room** → Separate voice-nodes, MQTT namespace expansion
3. **Other appliances** → Extend beyond AC (lights, fan, heater)
4. **Predictive learning** → Train occupancy patterns (come home same time, leave early Friday)
5. **Energy analytics** → Dashboard showing AC run-time cost
6. **Voice confirmation** → "Did you mean turn AC ON? Say yes or no." (disambiguate mishears)

---

**Last updated**: 2026-08-10  
**Next review**: After Phase 7 completion
