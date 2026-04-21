---
status: completed
created: 2026-04-20
slug: sleep-pad-full-platform
description: Full IoT platform for LSM-800-TP sleep pad — FastAPI backend, ESP32 BLE+MQTT firmware, Flutter mobile app
blockedBy: []
blocks: []
---

# Sleep Pad Full Platform

## Overview

Three sub-projects built in dependency order:
1. **Backend** (foundation — all other sub-projects depend on it)
2. **ESP32 Firmware** (depends on backend MQTT broker + /devices/pair endpoint)
3. **Flutter App** (depends on both backend API and ESP32 BLE GATT)

Reference: [Brainstorm report](../reports/brainstorm-260420-2039-sleep-pad-full-platform.md)

## Phases

| Phase | File | Sub-Project | Status | Description |
|-------|------|-------------|--------|-------------|
| 01 | [phase-01-backend-infrastructure.md](phase-01-backend-infrastructure.md) | Backend | completed | Docker Compose, PostgreSQL+TimescaleDB, Mosquitto, Redis |
| 02 | [phase-02-backend-auth-devices.md](phase-02-backend-auth-devices.md) | Backend | completed | FastAPI auth (JWT), device pairing API |
| 03 | [phase-03-backend-data-api.md](phase-03-backend-data-api.md) | Backend | completed | MQTT subscriber, TimescaleDB storage, history REST, realtime WebSocket |
| 04 | [phase-04-backend-alerts-sharing.md](phase-04-backend-alerts-sharing.md) | Backend | completed | Alert engine (60s), FCM push, family sharing API |
| 05 | [phase-05-esp32-ble-mqtt.md](phase-05-esp32-ble-mqtt.md) | ESP32 | completed | Replace WiFiManager+WebServer with BLE GATT + MQTT client |
| 06 | [phase-06-flutter-setup-auth-ble.md](phase-06-flutter-setup-auth-ble.md) | Flutter | completed | Project scaffold, auth screens, BLE provisioning flow |
| 07 | [phase-07-flutter-dashboard-history.md](phase-07-flutter-dashboard-history.md) | Flutter | completed | Home realtime charts, History (day/week/month) |
| 08 | [phase-08-flutter-alerts-sharing-fcm.md](phase-08-flutter-alerts-sharing-fcm.md) | Flutter | completed | Alerts thresholds, Sharing/invite, FCM push, Settings |

## Build Order Rationale

```
Phase 01-04 (Backend) must complete before Phase 05-08 begin.
Phase 05 (ESP32) can start after Phase 02 (device pairing endpoint ready).
Phase 06-08 (Flutter) requires Phase 01-04 complete + Phase 05 testable.
```

## Key Constraints

- Dev: LAN direct ports (192.168.x.x:8000, MQTT TCP 1883)
- Prod: VPS + cloudflared tunnel (HTTPS api.domain.com, WSS mqtt.domain.com)
- ESP32 MQTT: TCP 1883 (dev) / WebSocket 443 (prod via cloudflared)
- No nginx — cloudflared handles TLS termination
- Existing firmware files to MODIFY (not replace): `firmware/src/main.cpp`, `firmware/platformio.ini`
- Existing firmware files to DELETE: `firmware/src/web-server.h`, `firmware/src/web-server.cpp`, `firmware/src/dashboard.h`
