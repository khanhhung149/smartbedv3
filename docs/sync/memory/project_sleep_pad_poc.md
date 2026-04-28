---
name: Sleep Pad Full Platform
description: Complete IoT platform (FastAPI backend + ESP32 firmware + Flutter app) for Legact Pro V2 sleep pad LSM-800-TP
type: project
originSessionId: f8363123-ac47-4985-835d-dc4b0d64f072
---
Full-stack platform shipped across 8 phases on 2026-04-21. Three components:

1. **Backend** at `backend/` — FastAPI + PostgreSQL/TimescaleDB + Mosquitto MQTT + Redis + Firebase FCM (stub). Docker Compose split into dev (LAN ports) and prod (cloudflared tunnel). Auth, device pairing, MQTT ingest, realtime WebSocket, history API, alert engine (60s + Redis dedup), family sharing.

2. **ESP32 firmware** at `firmware/` — PlatformIO/Arduino. BLE GATT provisioning + MQTT client (PubSubClient TCP-only for POC; WSS deferred to prod). Replaces old WiFiManager + local web dashboard. NVS config, LWT, 0x04 monitor mode + 0x08 heartbeat to sleep pad preserved. Build: Flash 49.8%, RAM 17.7%.

3. **Flutter app** at `flutter_app/` — Flutter 3+, 21 screens pixel-matched to Stitch exports at `docs/stitch_sleep_pad_app_design/`. Onboarding, auth, BLE provisioning, Home realtime (WS), History (fl_chart), Alerts, Sharing, Devices, Settings. FCM as dev no-op.

**Why:** Evolved from April 10 POC firmware into a full family monitoring product (invite siblings/caregivers by email, per-user thresholds, push alerts on vital breaches).

**How to apply:**
- Plan dir: `plans/260420-2039-sleep-pad-full-platform/` (status=completed, all 8 phases done)
- Protocol contract (authoritative): `docs/protocols/ble-provisioning-and-mqtt-auth.md` — BLE UUIDs, MQTT connect rules, ACL %c pattern for prod
- 12 journal entries at `docs/journals/2026-04-{10,20,21}-*.md`
- Retrospective: `docs/journals/2026-04-21-platform-complete.md`
- Dev stack: `cd backend && docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d`
- Production TODOs: MQTT WSS via espMqttClient lib, Mosquitto Dynamic Security for per-device creds, NVS encryption, BLE bonding, alembic migrations, real Firebase project, `DELETE /devices/{id}` + `GET /share/pending` endpoints, alembic migrations, contract tests to catch Flutter↔backend schema drift
