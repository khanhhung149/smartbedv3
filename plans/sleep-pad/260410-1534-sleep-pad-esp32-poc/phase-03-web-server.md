# Phase 03: Web Server + Dashboard

## Priority: High
## Status: Pending

## Overview
ESPAsyncWebServer serving a single HTML page with WebSocket for realtime data push. Dashboard displays current sleep pad readings.

## Requirements
- HTTP GET `/` serves dashboard HTML from PROGMEM
- WebSocket endpoint `/ws` broadcasts JSON on new data
- Auto-reconnect on WebSocket disconnect
- Clean, readable UI showing all parsed fields

## Related Code Files
- Create: `src/web-server.h`
- Create: `src/web-server.cpp`
- Create: `src/dashboard.h` (HTML/CSS/JS as PROGMEM string)

## Implementation Steps

### web-server.h/.cpp
1. `setupWebServer()` — init AsyncWebServer on port 80, register routes
2. `setupWebSocket()` — init AsyncWebSocket on `/ws`, handle connect/disconnect events
3. `broadcastSecData(SleepPadSecData&)` — serialize to JSON, send to all WS clients
4. `broadcastMinData(SleepPadMinData&)` — serialize to JSON, send to all WS clients
5. Use ArduinoJson to build JSON payloads

### dashboard.h (PROGMEM HTML)
1. Single page, no external dependencies (no CDN)
2. CSS: dark theme, large readable numbers, status color-coded
3. Sections:
   - Connection status indicator (green dot / red dot)
   - Per-second: status badge, heart rate, respiration rate, SDATA, PDATA
   - Per-minute: body movement, snoring, resp disorder, PTHD, TEMP
   - Last updated timestamp
4. JS WebSocket client:
   - Connect to `ws://<host>/ws`
   - Parse JSON, update DOM elements
   - Auto-reconnect with 2s delay on close
5. Keep HTML under ~8KB for PROGMEM comfort

## Todo
- [ ] Create web-server.h/.cpp with AsyncWebServer + WebSocket
- [ ] Create dashboard.h with PROGMEM HTML
- [ ] JSON broadcast functions
- [ ] Verify compilation

## Success Criteria
- Dashboard loads in browser at ESP32 IP
- WebSocket connects and shows connection status
- Data updates live when sleep pad sends frames
