# Phase 01: Project Setup

## Priority: High
## Status: Pending

## Overview
Scaffold PlatformIO project with Arduino framework for ESP32, add library dependencies, create WiFi connection logic.

## Requirements
- PlatformIO project targeting esp32dev board
- Arduino framework
- Libraries: ESPAsyncWebServer, AsyncTCP, ArduinoJson
- WiFi STA mode with hardcoded credentials

## Related Code Files
- Create: `platformio.ini`
- Create: `src/main.cpp` (skeleton)
- Create: `include/config.h` (WiFi credentials, UART pins)

## Implementation Steps
1. Create `platformio.ini` with esp32dev board, Arduino framework, library deps
2. Create `include/config.h` with WiFi SSID/password placeholders, GPIO pin defines (RX=16, TX=17), baud rate 115200
3. Create `src/main.cpp` skeleton with WiFi connect in setup(), empty loop()
4. Verify build compiles with `pio run`

## Todo
- [ ] Create platformio.ini
- [ ] Create config.h with pin/WiFi defines
- [ ] Create main.cpp skeleton with WiFi init
- [ ] Verify compilation

## Success Criteria
- `pio run` compiles without errors
- WiFi connects on boot (verify via Serial Monitor)
