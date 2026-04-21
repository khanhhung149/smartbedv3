# Brainstorm: Sleep Pad ESP32 POC Dashboard

**Date:** 2026-04-10
**Status:** Approved

## Problem Statement
Connect sleep pad LSM-800-TP (Legact Pro V2 protocol) to ESP32 via UART, parse binary frames, serve realtime dashboard on ESP32's built-in web server.

## Constraints
- POC only — show data on web, no advanced features
- Realtime view only, no data persistence
- ESP32 dev board, Arduino/PlatformIO framework
- Self-hosted web server on ESP32

## Chosen Approach: Arduino/PlatformIO + ESPAsyncWebServer + WebSocket

### Architecture
- UART RX on GPIO16/17 at 115200 baud
- State machine parser for 0x85 (per-sec) and 0x86 (per-min) frames
- ESPAsyncWebServer with WebSocket for realtime push
- Single HTML page in PROGMEM (no SPIFFS)
- JSON payloads over WebSocket

### Data Parsed
- **0x85** (1s): status, heart_rate, respiration_rate, SDATA, PDATA
- **0x86** (1min): status, heart_rate, respiration_rate, body_movement, snore_count, resp_disorder, PTHD, TEMP

### Project Structure
```
src/
├── main.cpp           # Setup + loop
├── uart-parser.h/cpp  # Frame parsing state machine
├── web-server.h/cpp   # AsyncWebServer + WebSocket
└── dashboard.h        # HTML/JS/CSS PROGMEM
```

### Not in Scope
- Sending commands to sleep pad
- Data persistence / history
- OTA updates
- Authentication
- mDNS

## Risks
- UART buffer overflow → mitigated with sufficient buffer + fast loop
- WiFi/WebSocket blocking UART → mitigated by async web server
