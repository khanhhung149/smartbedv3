---
phase: 05
status: completed
priority: critical
effort: medium
sub_project: esp32
blockedBy: [phase-02]
---

# Phase 05: ESP32 BLE GATT + MQTT Client

## Overview

Remove WiFiManager + local web server from firmware. Add BLE GATT server to receive WiFi credentials + server URL from Flutter app. Store config in NVS. Connect MQTT broker and publish 0x85/0x86 frames as JSON. POST to /devices/pair on backend.

## Requirements

- BLE GATT server with custom service + 3 characteristics (SSID, password, server URL)
- NVS storage for WiFi credentials + server URL + device JWT token
- MQTT client: TCP 1883 (dev) / WebSocket 443 (prod) via PubSubClient
- Publish `sleeppad/{device_id}/sec` and `sleeppad/{device_id}/min` as JSON
- POST `/devices/pair` to backend with device_id + JWT after MQTT connect
- LWT: `sleeppad/{device_id}/status` = `offline`
- Keep-alive commands: 0x04 on boot, 0x08 heartbeat every 60s (unchanged)

## BLE GATT Design

**Authoritative contract:** [`docs/protocols/ble-provisioning-and-mqtt-auth.md`](../../docs/protocols/ble-provisioning-and-mqtt-auth.md). Any mismatch — treat that doc as source of truth.

```
Service UUID:       4fafc201-1fb5-459e-8fcc-c5c9c331914b
Characteristics (all WRITE unless noted):
  SSID             beb5483e-36e1-4688-b7f5-ea07361b26a8
  Password         beb5483e-36e1-4688-b7f5-ea07361b26a9
  ServerHost       beb5483e-36e1-4688-b7f5-ea07361b26aa   (host only, no scheme)
  Status           beb5483e-36e1-4688-b7f5-ea07361b26ab   (READ/NOTIFY)
  MqttUser         beb5483e-36e1-4688-b7f5-ea07361b26ac
  MqttPassword     beb5483e-36e1-4688-b7f5-ea07361b26ad
  MqttScheme       beb5483e-36e1-4688-b7f5-ea07361b26ae   ("tcp"|"ws"|"wss")
```

Flutter writes all 6 WRITE chars sequentially. ESP32 persists each to NVS. On last-write (MqttPassword), ESP32 triggers WiFi+MQTT connect → notifies Status.

**Status values:** `waiting`, `connecting`, `connected`, `wifi_failed`, `mqtt_failed`.

### MQTT connection rules (CRITICAL for prod ACL)

- `client_id` **MUST** equal `device_id` (hardcoded at flash, e.g. `CNU2000001`) — Mosquitto prod ACL enforces `pattern write sleeppad/%c/{sec,min,status}`. Wrong client_id → publishes silently dropped by broker.
- `username` = MqttUser (empty → connect anonymously; valid in dev)
- `password` = MqttPassword
- **LWT**: `sleeppad/{device_id}/status` = `"offline"` retain=true QoS 0
- Publish `"online"` to same topic after connect, retain=true

## NVS Keys

```
namespace: "sleeppad"
keys:
  wifi_ssid      TEXT
  wifi_pass      TEXT
  mqtt_host      TEXT   (host[:port], no scheme — e.g. "192.168.1.100:9001" or "mqtt.domain.com")
  mqtt_scheme    TEXT   ("tcp" | "ws" | "wss")
  mqtt_user      TEXT   (may be empty)
  mqtt_pass      TEXT   (may be empty)
```

`device_id` is compiled into firmware (not in NVS).

## MQTT Publish Format

```json
// sleeppad/CNU2000001/sec
{
  "device_id": "CNU2000001",
  "ts": 1713600000,
  "status": 4,
  "heart_rate": 68,
  "resp_rate": 14.5,
  "sdata": 12,
  "pdata": 8
}

// sleeppad/CNU2000001/min
{
  "device_id": "CNU2000001",
  "ts": 1713600060,
  "status": 4,
  "heart_rate": 68,
  "resp_rate": 14.0,
  "movement": 2,
  "snore_count": 0,
  "resp_disorder": 0,
  "pthd": 5,
  "temp": 36.5
}
```

## Files to Modify/Delete

- **DELETE**: `firmware/src/web-server.h`
- **DELETE**: `firmware/src/web-server.cpp`
- **DELETE**: `firmware/src/dashboard.h`
- **MODIFY**: `firmware/platformio.ini` — remove WiFiManager + ESPAsyncWebServer, add BLE + PubSubClient + ArduinoHttpClient
- **MODIFY**: `firmware/src/main.cpp` — full rewrite of WiFi/BLE/MQTT logic
- **CREATE**: `firmware/src/ble-provisioning.h`
- **CREATE**: `firmware/src/ble-provisioning.cpp`
- **CREATE**: `firmware/src/nvs-config.h`
- **CREATE**: `firmware/src/nvs-config.cpp`
- **CREATE**: `firmware/src/mqtt-client.h`
- **CREATE**: `firmware/src/mqtt-client.cpp`

## Updated platformio.ini Dependencies

```ini
lib_deps =
  bblanchon/ArduinoJson @ ^7.4.1
  knolleary/PubSubClient @ ^2.8
  arduino-libraries/ArduinoHttpClient @ ^0.6.0
  ; ESP32 BLE is built-in Arduino framework — no extra lib needed
```

Remove: `mathieucarbou/ESP Async WebServer`, `https://github.com/tzapu/WiFiManager.git`

## Main Flow (main.cpp)

```
setup():
  1. Init Serial2 (UART to sleep pad)
  2. Init NVS
  3. Read NVS → has WiFi credentials?
     NO → start BLE GATT server, advertise "SleepPad-XXXX", wait for provisioning
     YES → skip BLE, go to WiFi connect
  4. Connect WiFi (blocking, 30s timeout)
     FAIL → restart BLE provisioning
  5. Connect MQTT broker
  6. POST /devices/pair → backend
  7. Send 0x04 monitor command to sleep pad
  8. Register UART parser callbacks → MQTT publish

loop():
  1. Feed UART bytes to parser
  2. MQTT loop (PubSubClient.loop())
  3. Heartbeat (0x08) every 60s
  4. MQTT reconnect if disconnected
```

## Implementation Steps

1. Write `nvs-config.h/.cpp` — read/write NVS keys, `NvsConfig::load()`, `NvsConfig::save()`
2. Write `ble-provisioning.h/.cpp`:
   - BLEServer + BLEService + 4 characteristics
   - On all 3 write chars received → save NVS → notify Status="connecting" → restart
3. Update `firmware/platformio.ini` — swap libraries
4. Write `mqtt-client.h/.cpp`:
   - `MqttClient::connect(host, port, proto)` — TCP or WS
   - `MqttClient::publishSec(const SleepPadSecData&)` → JSON → publish
   - `MqttClient::publishMin(const SleepPadMinData&)` → JSON → publish
   - LWT setup: `sleeppad/{id}/status` = `"offline"` retain=true
   - Auto-reconnect in loop()
5. Rewrite `main.cpp` — new flow without WiFiManager/WebServer
6. Build: `python3 -m platformio run` — verify 0 errors
7. Flash + test: BLE scan from phone → provision → MQTT messages appear in broker

## Todo

- [x] nvs-config.h/.cpp
- [x] ble-provisioning.h/.cpp
- [x] mqtt-client.h/.cpp
- [x] Update platformio.ini (swap libs)
- [x] Rewrite main.cpp
- [x] Delete web-server.h/.cpp and dashboard.h
- [x] Build verify (0 errors)
- [x] Flash + BLE provisioning test
- [x] Verify MQTT messages arriving at broker

## Success Criteria

- BLE advertises "SleepPad-XXXX" when no WiFi credentials in NVS
- After provisioning: WiFi connects, MQTT connects, LED/serial confirms
- `mosquitto_sub -t 'sleeppad/#'` receives JSON every second
- LWT `sleeppad/{id}/status` = `"offline"` when ESP32 disconnects
- Backend `/devices/pair` called → device appears in DB

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| PubSubClient WS support limited | Use `PubSubClientWs` fork or WebSocketsClient bridge for prod WS 443 |
| BLE + WiFi simultaneous (memory) | Init BLE first, stop BLE before WiFi connect (ESP32 supports both but not simultaneously well) |
| NVS corruption on power loss | Use `nvs_flash_erase` fallback on read failure |
| Flash size with new libs | Monitor — remove debug logging if tight |

## Security

- BLE GATT: no pairing/bonding required (MVP); add bonding post-MVP
- WiFi password stored in NVS (encrypted flash partition recommended)
- JWT token stored in NVS for device identity
