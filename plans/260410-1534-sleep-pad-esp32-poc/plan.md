---
status: pending
created: 2026-04-10
slug: sleep-pad-esp32-poc
description: ESP32 firmware to read sleep pad UART data and serve realtime web dashboard
---

# Sleep Pad ESP32 POC Dashboard

## Overview
PlatformIO Arduino firmware for ESP32 that reads Legact Pro V2 binary frames from sleep pad via UART, parses 0x85 (per-second) and 0x86 (per-minute) data, and serves a realtime web dashboard via WebSocket.

## Phases

| Phase | File | Status | Description |
|-------|------|--------|-------------|
| 01 | [phase-01-project-setup.md](phase-01-project-setup.md) | pending | PlatformIO project scaffold, dependencies |
| 02 | [phase-02-uart-parser.md](phase-02-uart-parser.md) | pending | UART frame parser state machine |
| 03 | [phase-03-web-server.md](phase-03-web-server.md) | pending | AsyncWebServer + WebSocket + dashboard HTML |
| 04 | [phase-04-integration.md](phase-04-integration.md) | pending | Wire everything together in main.cpp, test |

## Key Dependencies
- PlatformIO + Arduino framework for ESP32
- ESPAsyncWebServer + AsyncTCP libraries
- ArduinoJson for JSON serialization

## Hardware
- ESP32 dev board
- Sleep pad LSM-800-TP connected via UART (RX=GPIO16, TX=GPIO17)
- Baud rate: 115200
