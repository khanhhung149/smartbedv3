# Phase 04: Integration

## Priority: High
## Status: Pending

## Overview
Wire UART parser callbacks to WebSocket broadcast in main.cpp. Final build, flash, and test with real sleep pad.

## Related Code Files
- Modify: `src/main.cpp`

## Implementation Steps
1. In `setup()`:
   - Init Serial (debug, 115200)
   - Init Serial2 (sleep pad UART, GPIO16 RX, GPIO17 TX, 115200)
   - Connect WiFi, print IP
   - Init parser with callbacks
   - Init web server
2. In `loop()`:
   - Read all available Serial2 bytes, feed to parser
   - AsyncWebServer handles itself (non-blocking)
3. Parser callbacks:
   - `onSecData` → log to Serial + `broadcastSecData()`
   - `onMinData` → log to Serial + `broadcastMinData()`
4. Build: `pio run`
5. Flash: `pio run -t upload`
6. Test: open browser to ESP32 IP, verify live data

## Todo
- [ ] Wire parser callbacks to web server broadcast
- [ ] Complete main.cpp setup/loop
- [ ] Build and verify no errors
- [ ] Flash and test with real hardware (manual)

## Success Criteria
- Firmware compiles and flashes successfully
- ESP32 connects to WiFi, prints IP on Serial
- Browser dashboard shows realtime sleep pad data
- Both per-second and per-minute data displayed correctly
