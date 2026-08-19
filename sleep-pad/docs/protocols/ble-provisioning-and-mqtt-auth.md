# Protocol Contract — BLE Provisioning & MQTT Auth

> Authoritative contract for Flutter (Phase 06) ↔ ESP32 (Phase 05) ↔ Backend (Phase 02).
> Any change here must bump the BLE service UUID and update all three implementations.

## Goals

1. Flutter provisions an ESP32 over BLE with: WiFi creds, server URL, MQTT creds.
2. ESP32 connects to WiFi → MQTT broker → publishes telemetry.
3. Production: each ESP32 can only publish to its OWN namespace (`sleeppad/{device_id}/#`) even though all devices share one MQTT password. Enforced by Mosquitto ACL `%c` pattern — the ESP32's MQTT client_id must equal its device_id.

## Flow Overview

```
┌──────────┐  HTTPS  ┌─────────┐
│ Flutter  │ ──────▶ │ Backend │  1. POST /auth/login      → JWT
│          │         │         │  2. POST /devices/pair    → DevicePairOut
│          │ ◀────── │         │     (includes mqtt creds + host + scheme)
└──────────┘         └─────────┘

┌──────────┐   BLE   ┌─────────┐
│ Flutter  │ ──────▶ │ ESP32   │  3. Write 5 GATT characteristics
│          │         │         │  4. Read Status char = "connected"
└──────────┘         └─────────┘

┌──────────┐  MQTT   ┌─────────┐
│ ESP32    │ ──────▶ │ Broker  │  5. Connect with client_id = device_id
│          │         │         │     username/password from BLE
│          │         │         │  6. Publish sleeppad/{device_id}/{sec|min|status}
└──────────┘         └─────────┘
```

## 1. Backend API Contract

### `POST /devices/pair` (Bearer auth)

**Request:**
```json
{ "device_id": "CNU2000001", "name": "Bedroom" }
```

**Response 200** (`DevicePairOut`):
```json
{
  "device_id": "CNU2000001",
  "name": "Bedroom",
  "paired_at": "2026-04-21T05:33:00.711063Z",
  "last_seen": null,
  "online": false,
  "mqtt_username": "sleeppad-device",
  "mqtt_password": "<shared-prod-password>",
  "mqtt_host":     "mqtt.yourdomain.com",
  "mqtt_scheme":   "wss"
}
```

**`mqtt_scheme` values:** `"tcp"` (dev TCP 1883), `"ws"` (dev WebSocket 9001), `"wss"` (prod via cloudflared 443).

**Dev:** `mqtt_username` and `mqtt_password` are empty strings (broker anonymous). Flutter still writes them — ESP32 treats empty as "connect anonymously".

## 2. BLE GATT Service

### Service UUID

```
4fafc201-1fb5-459e-8fcc-c5c9c331914b
```

### Characteristics

| UUID | Name | Direction | Payload (UTF-8 text) |
|------|------|-----------|----------------------|
| `beb5483e-36e1-4688-b7f5-ea07361b26a8` | SSID          | WRITE       | WiFi SSID |
| `beb5483e-36e1-4688-b7f5-ea07361b26a9` | Password      | WRITE       | WiFi password |
| `beb5483e-36e1-4688-b7f5-ea07361b26aa` | ServerHost    | WRITE       | MQTT host (no scheme, e.g. `mqtt.yourdomain.com` or `192.168.1.100:9001`) |
| `beb5483e-36e1-4688-b7f5-ea07361b26ac` | MqttUser      | WRITE       | `mqtt_username` from /devices/pair (may be empty) |
| `beb5483e-36e1-4688-b7f5-ea07361b26ad` | MqttPassword  | WRITE       | `mqtt_password` from /devices/pair (may be empty) |
| `beb5483e-36e1-4688-b7f5-ea07361b26ae` | MqttScheme    | WRITE       | `"tcp"` \| `"ws"` \| `"wss"` |
| `beb5483e-36e1-4688-b7f5-ea07361b26ab` | Status        | READ/NOTIFY | One of: `waiting`, `connecting`, `connected`, `wifi_failed`, `mqtt_failed` |
| `beb5483e-36e1-4688-b7f5-ea07361b26af` | DeviceId      | READ        | Device ID string, e.g. `CNU2000001`. Flutter reads this after GATT connect to confirm which device it paired with. |

### Device name (advertisement)

ESP32 advertises as `SleepPad-{LAST-6-OF-DEVICE-ID}` (e.g. `SleepPad-000001`). Flutter scans by prefix `SleepPad-`.

## 3. Flutter provisioning sequence

```
1. flutter_blue_plus scan → show list of "SleepPad-*" devices
2. User picks one → connect GATT
3. Discover services → find Service UUID
4. Write characteristics SEQUENTIALLY (await each):
     SSID  → password → ServerHost → MqttScheme → MqttUser → MqttPassword
5. Subscribe to Status notify
6. Wait up to 60s for Status == "connected"
7. Disconnect BLE
8. Poll GET /devices/mine every 2s until device appears with online=true
9. Navigate to Home
```

**Write order matters** — ESP32 persists each char to NVS as it arrives but only begins WiFi connect after MqttPassword is written (last-char trigger). Or ESP32 can use a sentinel "Commit" char; current plan uses last-char trigger for simplicity.

## 4. ESP32 connection requirements

- **Device ID source**: ESP32 holds its own device_id (hardcoded at flash time, e.g. `CNU2000001` — 10 ASCII chars from the sleep pad protocol).
- **BLE default state**: If NVS has no WiFi SSID, start BLE GATT server and advertise.
- **Storage**: Write each received characteristic into NVS under namespace `sleeppad`:
  - `wifi_ssid`, `wifi_pass`, `mqtt_host`, `mqtt_user`, `mqtt_pass`, `mqtt_scheme`
- **MQTT connect parameters**:
  - `client_id` = device_id   **← critical for ACL**
  - `username`  = `mqtt_user` (may be empty → anonymous)
  - `password`  = `mqtt_pass`
  - `keep_alive` = 60s
  - **LWT**: topic `sleeppad/{device_id}/status`, payload `offline`, retain=true, QoS 0
- **Publish topics** (ACL only allows these):
  - `sleeppad/{device_id}/sec`
  - `sleeppad/{device_id}/min`
  - `sleeppad/{device_id}/status` (publish `online` after connect, retain=true)

**Never** publish to any other topic — broker will deny and log.

## 5. Production security notes

- **Credentials ARE shared.** All ESP32s use the same `mqtt_username` / `mqtt_password`.
- Security comes from **ACL `%c` pattern** — broker binds publish topic to the client_id at auth time. A compromised ESP32 can only publish fake data **for itself**, not for other devices.
- The backend subscriber uses a **different user** (`sleeppad-subscriber`) with read-only access to `sleeppad/#`.
- If a device is stolen / compromised, the attack radius is limited to that device's own telemetry.
- **Future upgrade** (not yet implemented): switch to Dynamic Security plugin for per-device unique passwords so compromise can be revoked per-device. Contract above unchanged — only the backend's create/revoke logic changes.

## 6. Dev environment behavior

- `mqtt_username` and `mqtt_password` are returned empty strings
- `mqtt_host` = e.g. `192.168.1.100:9001`, `mqtt_scheme` = `ws`
- Broker allows anonymous connect — ACL not enforced
- ESP32 still uses `client_id = device_id` (harmless)

## 7. Migration notes (if BLE UUIDs change)

Bumping any characteristic UUID requires:
1. Flutter `lib/core/constants.dart` — update UUID strings
2. ESP32 `firmware/src/ble-provisioning.cpp` — update UUIDs
3. This doc — update the table
4. Also bump the Service UUID if semantics change, so old Flutter apps don't half-write to new firmware

## Unresolved

- Re-pair flow: if user re-pairs an already-paired device, should /devices/pair rotate passwords? Currently returns same shared creds — acceptable for shared-cred model.

## Resolved

- **Flutter device_id discovery (Phase 05):** Implemented as a READ-only `DeviceId` characteristic at UUID `beb5483e-36e1-4688-b7f5-ea07361b26af`. ESP32 sets its value to the hardcoded `device_id` string on BLE init. Flutter reads this characteristic immediately after GATT connect, before writing any provisioning data, to confirm the target device.
