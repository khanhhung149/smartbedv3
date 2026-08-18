# Codebase Structure Overview

**Purpose**: Onboarding guide for new developers — how code is organized, where to find things, key modules.

## High-Level Structure

```
esp32-presence-ac/
├── backend/           Go server: REST API, MQTT subscriptions, state machine, SQLite history
├── firmware/          PlatformIO: 4 node binaries (radar-node, voice-node, door-node, room-node)
├── app/               Flutter Android: 5-tab UI, Riverpod state mgmt
├── asr/               Python FastAPI: Whisper-based transcription service
├── hardware/          OpenSCAD enclosure designs + collision-check scripts
├── scripts/           Wakeword training toolchain + deployment helpers
├── plans/             Decision logs, implementation phase docs
└── docs/              Technical documentation
```

## Backend (`backend/`)

**Language**: Go 1.23  
**Framework**: chi router (lightweight, no framework bloat)  
**Entry point**: `cmd/server/main.go`

### Key Modules

| Module | Path | Responsibility |
|--------|------|-----------------|
| **api** | `internal/api/` | HTTP routes, WebSocket handlers, CORS middleware |
| **statemachine** | `internal/statemachine/` | Tick-based occupancy logic (EnterWindow/ExitTimeout hysteresis) |
| **mqttclient** | `internal/mqttclient/` | Paho MQTT client, subscribes presence/motion, publishes ac_cmd |
| **voice** | `internal/voice/` | WebSocket audio streaming, VAD, utterance buffering, ASR worker, Vietnamese command parsing |
| **store** | `internal/store/` | SQLite via modernc.org/sqlite (no CGO), Event model, 5000-row cap |
| **config** | `internal/config/` | Env-based config (MQTT_*, ASR_URL, timing, DB_PATH) |
| **events** | `internal/events/` | Event type definitions (AC state, motion, voice) |

### API Routes

```
GET    /healthz                    → health check
GET    /api/state                  → current state snapshot
GET    /api/events?limit=50        → historical events (paginated)
POST   /api/ac                     → manual AC command (body: {"cmd":"on"})
POST   /api/ac/learn               → IR learning mode
WS     /api/voice/stream           → PCM16 audio upload + transcription
WS     /api/ws                     → state push (realtime deltas)
```

### Database Schema

**Table: events** (~2MB for 5000 rows)
```sql
id INTEGER PRIMARY KEY
ts INTEGER NOT NULL     -- Unix ms, auto-filled if not provided
type TEXT NOT NULL      -- "ac_state", "motion", "voice_cmd"
payload JSON            -- {"cmd":"on","source":"voice"} etc.
```

### Testing

```bash
cd backend && go test ./...
```

Tests cover:
- State machine transitions (presence + motion + timing)
- MQTT parsing (JSON payload validation)
- Voice command parsing (Vietnamese on/off/cool/heat/mode)
- SQLite store (pagination, JSON round-trip)

## Firmware (`firmware/`)

**Framework**: PlatformIO, Arduino core

### Node Map

| Node | MCU | Purpose | Env |
|------|-----|---------|-----|
| **radar-node** | ESP32-S2 Mini | LD2410C radar → MQTT presence/motion | `lolin_s2_mini` / `lolin_s2_mini_ota` |
| **voice-node** | ESP32-S3 (primary) / WROOM-32 (fallback) | INMP441 mic + state machine + IR Daikin + MQTT sub | `esp32s3` / `esp32dev` / `esp32s3_kws` (KWS) |
| **door-node** | ESP32-S2 | PIR interrupt → MQTT motion | `lolin_s2_mini` |
| **room-node** | ESP32-S2 | LD2410C (no WiFi) → ESP-NOW to voice-node | (No OTA/MQTT) |

### voice-node Details

**Primary target**: `esp32s3` (ESP32-S3-DevKit-1 N16R8)
- I2S pins: GPIO5 (SCK), GPIO6 (WS), GPIO7 (SD)
- IR output: GPIO8
- Runs state machine loop (presence logic + auto AC)
- Streams PCM16 WebSocket audio to backend `/api/voice/stream`, plus one `"eou"` text
  frame per utterance so the backend cuts sentences on the node's signal, not on silence
- WebSocket send runs in its own core-0 task (`wsSendTask`) fed by a 128-frame PSRAM
  queue — `sendBIN()` blocks for seconds when TCP stalls, and in `loop()` that stalled
  `i2s_read()` too (see `docs/voice-node-snore-wakeword-architecture.md`)

**Fallback target**: `esp32dev` (WROOM-32)
- Kept as escape hatch if S3 experiment breaks WiFi
- Same logic, different GPIO map

**Experimental target**: `esp32s3_kws` (wakeword inference)
- Platform: Arduino + ESP-IDF hybrid (pioarduino 55.03.311)
- Reason: esp-nn SIMD for wakeword model inference (50ms→5.4ms)
- State: **Compiles & boots, model not yet wired into loop**
- Risk: MFCC feature extraction must match Python training exactly

### Shared Config Pattern

Each node has `include/config.h.example` → copy to `config.h`, fill in:
```c
#define SSID "..."
#define WIFI_PASS "..."
#define MQTT_HOST "192.168.1.100"
#define MQTT_PORT 1883
#define MQTT_USER "homeuser"
#define MQTT_PASS "..."
#define OTA_PASSWORD "..."
```

## App (`app/`)

**Framework**: Flutter 3.24, Riverpod (state mgmt), MQTT client package

### Architecture

- **Providers** (`providers.dart`): Riverpod state containers (backend URL, MQTT broker, WebSocket clients)
- **Screens** (5 tabs):
  - **home_screen**: Live state, manual AC buttons, manual override status
  - **devices_screen**: Direct MQTT to broker (`cmnd/<T>/STATUS`), radar diagnostics
  - **analytics_screen**: Client-computed stats (uptime, daily usage)
  - **history_screen**: Event log from backend `/api/events`
  - **settings_screen**: Backend URL + broker config (SharedPreferences)

- **Services**:
  - `api_client.dart`: REST to backend
  - `ws_client.dart`: WebSocket state subscription
  - `mqtt_service.dart`: Direct MQTT (independent of backend, used for device diagnostics)

### Riverpod Key Providers

```dart
// Config
sharedPrefsProvider          // SharedPreferences instance
apiBaseUrlProvider          // from settings
mqttBrokerProvider          // "192.168.1.100:1883"

// Live data
wsStateProvider             // Subscribes /api/ws, emits Snapshot
eventHistoryProvider        // Polls /api/events
mqttDeviceStatusProvider    // Subscribes tele/<topic>/SENSOR
```

## ASR Service (`asr/`)

**Framework**: Python FastAPI, faster-whisper (CPU int8 inference)

### Endpoint

```
POST /transcribe
Content-Type: multipart/form-data
  file: <WAV 16k mono 16-bit LE>

Response:
  {"text": "bật điều hòa"}
```

### Model Config

```python
# Load model once at startup
model = WhisperModel("small", device="cpu", compute_type="int8")
```

**Tuning**:
- `vad_filter=True`: Skip silence frames (faster)
- `initial_prompt="bật, tắt, mát, nóng, chế độ"`: Bias towards AC keywords
- Language explicitly Vietnamese (not auto-detect)

### Testing

```bash
cd asr && python score_samples.py
```

Scores 100 sample WAV files, flags on/off-flip errors (most dangerous regression).

## Hardware (`hardware/`)

**Design tool**: OpenSCAD (parametric, CGAL-based collision checking)

| File | Purpose |
|------|---------|
| `vo-hop-modular.scad` | 3-part voice-node enclosure (base + face + lid) |
| `vo-hop-sleeppad.scad` | Separate sleep-pad sensor enclosure |
| `check-enclosure-fit.sh` | CGAL intersection test (catches print-breaking geometry) |
| `kiem_va_cham_vo_hop_sleeppad.py` | Python collision checker for sleep-pad |

## Scripts (`scripts/`)

### Wakeword Training Toolchain

| Script | Purpose |
|--------|---------|
| `thu-mau-wakeword.ps1` | Record mic samples (Windows PowerShell, WSL2 has no audio) |
| `sinh-mau-tts-local.py` | Generate synthetic training samples (VieNeu TTS + everai.vn) |
| `kiem-thanh-dieu.py` | Tone quality gate (F0 pitch analysis, rejects bad samples) |
| `train-wakeword-colab.ipynb` | microWakeWord framework training (Colab, avoids WSL OOM) |
| `gen-model-header.py` | Convert `.tflite` → C header for firmware embedding |

### Deployment

| Script | Purpose |
|--------|---------|
| `wsl-portproxy.ps1` | Expose WSL2 MQTT (1883) + HTTP (8080) to Windows host (adapter when broker runs in WSL) |

## Code Patterns & Conventions

### Naming

- **Go**: `package.FunctionName`, `snake_case` for vars, interfaces end in `-er` (e.g., `StateProvider`)
- **Dart**: `ClassName`, `functionName`, `_privateVar`
- **C++/PlatformIO**: `MACRO_CASE`, `functionName`, `m_memberVar` (rare, most are locals)
- **Python**: `snake_case` (PEP-8)

### Error Handling

**Go**:
```go
if err != nil {
    // Log + return, never panic in backend
    log.Printf("error: %v", err)
    http.Error(w, "internal error", 500)
    return
}
```

**Firmware**:
```c
// No exceptions; use Serial.printf for debug, bail out via return 0 or infinite loop
if (!WiFi.begin(SSID, WIFI_PASS)) {
    Serial.println("WiFi fail");
    return 0;
}
```

### Testing

- **Go**: stdlib `testing` package, table-driven tests for edge cases
- **Flutter**: Golden tests for UI (screenshots), Riverpod testing utilities
- **Firmware**: compile check only (no target-platform unit tests); hardware validation via serial monitor + MQTT broker inspection

### Secrets Management

- **Never commit** `config.h`, `.env`, `passwd`
- Use `.example` template files + `.gitignore`
- Environment variables for sensitive config at runtime

### MQTT Payload Format

All payloads are JSON:
```json
{
  "ts": 1700000000000,
  "present": true,
  "cmd": "on",
  "motion": true
}
```

Topics are lowercase kebab-case: `home/room/presence`, `home/door/motion`, `home/room/ac_cmd`.

---

**Last updated**: 2026-08-10
