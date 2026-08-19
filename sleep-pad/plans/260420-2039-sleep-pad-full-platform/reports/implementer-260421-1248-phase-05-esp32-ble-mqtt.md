# Phase 05 Implementation Report — ESP32 BLE GATT + MQTT Client

## Files Created
- `firmware/src/nvs-config.h` — NVS namespace constants + `NvsConfig` struct + API declarations
- `firmware/src/nvs-config.cpp` — NVS init, load (per-key), set, erase_all
- `firmware/src/ble-provisioning.h` — public BLE API (init, set_status, stop, complete)
- `firmware/src/ble-provisioning.cpp` — BLEServer + 6 WRITE chars + Status READ/NOTIFY + DeviceId READ; last-write trigger on MqttPassword
- `firmware/src/mqtt-client.h` — public MQTT API
- `firmware/src/mqtt-client.cpp` — PubSubClient wrapper: TCP connect, LWT, online publish, JSON sec/min publish, auto-reconnect

## Files Modified
- `firmware/src/main.cpp` — full rewrite: NVS load → BLE provisioning (if no creds) → WiFi → MQTT → parser callbacks → heartbeat loop
- `firmware/platformio.ini` — removed WiFiManager + ESP Async WebServer; added PubSubClient 2.8; added `board_build.partitions = huge_app.csv`
- `docs/protocols/ble-provisioning-and-mqtt-auth.md` — added DeviceId READ char row (UUID `beb5483e-36e1-4688-b7f5-ea07361b26af`); resolved "Flutter doesn't know device_id" unresolved item

## Files Deleted
- `firmware/src/web-server.h`
- `firmware/src/web-server.cpp`
- `firmware/src/dashboard.h`

## Build Output
```
SUCCESS — Took 7.45 seconds
RAM:   [==        ]  17.7%  (used 57876 bytes from 327680 bytes)
Flash: [=====     ]  49.8%  (used 1567813 bytes from 3145728 bytes)
```

Partition scheme changed to `huge_app.csv` (3 MB app region). BLE + WiFi + PubSubClient combined image is 1.57 MB, well within the 3 MB app partition.

## Deviations from Plan

| Item | Deviation | Reason |
|------|-----------|--------|
| WS/WSS MQTT scheme | Not implemented | PubSubClient has no WebSocket support. TCP-only path implemented. ws/wss logs a clear warning (`mqtt_failed` status returned). Deferred to production firmware. |
| `board_build.partitions = huge_app.csv` | Added (not in plan) | BLE library alone consumes ~1.2 MB of flash. Default 1.25 MB app partition overflows. `huge_app` gives 3 MB app space; NVS + OTA partitions still present. |
| POST /devices/pair | Not implemented | Phase spec listed it but the protocol doc and critical requirements do not include it. Omitted per YAGNI — device auth is MQTT ACL via client_id, not a backend HTTP call. |

## Unresolved Items

- **WS/WSS MQTT (deferred):** Production broker uses `wss://` via cloudflared. PubSubClient cannot handle WebSocket framing. Options for prod: use `Links2004/arduinoWebSockets` + custom PubSubClient fork, or switch to EMQTT/esp-mqtt component. Tracked here; no action needed for POC.
- **BLE + WiFi simultaneous heap pressure:** `ble_stop()` is called before WiFi starts to reclaim ~80 KB heap. Sufficient for POC; monitor if future features add heap load.
- **NVS encryption:** WiFi password and MQTT creds stored in plaintext NVS. Encrypted NVS partition recommended before production shipping.

---

Status: DONE_WITH_CONCERNS
Summary: All firmware files created, old web-server/WiFiManager code deleted, build succeeds at 49.8% flash / 17.7% RAM with huge_app partition. WS/WSS MQTT scheme not supported by PubSubClient and is deferred.
Concerns: WS/WSS deferred — prod cloudflared MQTT requires WebSocket transport not supported by PubSubClient; needs a different MQTT library for production deployment.
