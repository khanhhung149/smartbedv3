# Brainstorm: Sleep Pad Full Platform

**Date:** 2026-04-20  
**Status:** Approved

## Problem Statement
Build a complete IoT platform for sleep pad LSM-800-TP: mobile app (Flutter) for BLE provisioning + monitoring, backend server (FastAPI + Docker), real-time + historical data, alerts, family sharing, push notifications.

## Sub-Projects (Build Order)

### Sub-1: Backend Server (build first — foundation)
### Sub-2: ESP32 Firmware (depends on backend MQTT)
### Sub-3: Flutter App (depends on both)

---

## Architecture

### Data Flow
```
[Sleep Pad] ──UART──► [ESP32]
                         │
              BLE GATT ◄─┤─► [Flutter App (provisioning)]
                         │
              MQTT publish│
                    dev:  TCP 1883
                    prod: WebSocket 443 (via cloudflared)
                         ▼
                  [Mosquitto Broker]
                         │
                  [FastAPI subscriber]
                         │
              ┌──────────┴───────────┐
         [TimescaleDB]          [Redis pub/sub]
                                     │
                              [WebSocket] ──► [Flutter App (realtime)]
                                     │
                              [Alert Engine] ──► [FCM] ──► Push Notif
```

### MQTT Topics
```
sleeppad/{device_id}/sec     ← 0x85 per-second data
sleeppad/{device_id}/min     ← 0x86 per-minute data
sleeppad/{device_id}/status  ← online/offline LWT
```

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Firmware | ESP32 Arduino + BLE GATT + PubSubClient (MQTT) |
| Backend | Python FastAPI (async) |
| Database | PostgreSQL 16 + TimescaleDB |
| Message broker | Mosquitto (MQTT + WS) |
| Cache/PubSub | Redis |
| Push notifications | Firebase FCM |
| Mobile | Flutter 3+ |
| BLE | flutter_blue_plus |
| Charts | fl_chart |
| Infrastructure | Docker Compose + cloudflared |

---

## Infrastructure (Two Environments)

```
docker-compose.yml          ← base (shared)
docker-compose.dev.yml      ← local LAN, direct ports, no tunnel
docker-compose.prod.yml     ← cloudflared tunnel, VPS

Services:
├── fastapi       (API + WebSocket + Alert engine)
├── mosquitto     (MQTT TCP 1883 + WebSocket 9001)
├── postgresql    (TimescaleDB)
├── redis
└── cloudflared   (prod only)

Dev access:  http://192.168.x.x:8000, mqtt://192.168.x.x:1883
Prod access: https://api.yourdomain.com, wss://mqtt.yourdomain.com
```

---

## Backend API Overview

### Auth
- POST /auth/register
- POST /auth/login → JWT
- GET  /auth/me

### Devices
- POST /devices/pair      ← ESP32 registers after WiFi connect
- GET  /devices/mine
- GET  /devices/{id}/status

### Data
- GET /data/{device_id}/realtime   ← latest reading
- GET /data/{device_id}/history?range=day|week|month
- WS  /ws/{device_id}             ← realtime stream

### Alerts
- GET/PUT /alerts/{device_id}/thresholds
- GET     /alerts/{device_id}/history

### Sharing
- POST /share/invite      ← send invite by email
- GET  /share/my-devices  ← devices shared with me
- DELETE /share/{share_id}

---

## Flutter App Screens

```
Home          ← Realtime charts (HR, RR, status), last 0x85 data
History       ← Day/Week/Month tab, fl_chart line charts
Alerts        ← Threshold settings per metric
Devices       ← BLE scan → provision → pair with server
Sharing       ← Invite by email, manage shared users
Settings      ← Account, notification preferences
```

### BLE Provisioning Flow
```
1. App scans BLE → finds "SleepPad-XXXX"
2. Connect GATT → write WiFi SSID + Password + Server URL
3. ESP32 restarts → connects WiFi → connects MQTT broker
4. ESP32 POSTs to /devices/pair with device_id
5. App polls /devices/mine → confirms paired
```

---

## Alert Engine (Backend)
- Background task runs every 60s
- Query last 1 minute of data per active device
- Compare vs user-set thresholds (HR high/low, RR high/low, resp_disorder count)
- If threshold exceeded: send FCM push to owner + all shared accounts
- Log alert to alerts table

---

## Risks

| Risk | Mitigation |
|------|-----------|
| BLE GATT on iOS needs entitlements | Register Apple developer account, test on real device |
| MQTT over WS through cloudflared latency | Acceptable for 1s data; test prod latency |
| TimescaleDB week/month query perf | Create hypertable + proper indexes up front |
| FCM token management across shared accounts | Store FCM tokens per user-device, refresh on login |

---

## Build Order

1. **Backend** — FastAPI + DB + MQTT subscriber + alert engine + FCM
2. **ESP32** — BLE GATT provisioning + MQTT publish (replace WiFiManager + local WS)
3. **Flutter** — BLE setup flow + all screens
