# Firmware MQTT — TCP → WSS migration (cách B)

**Status:** ✅ Complete — both envs compile, end-to-end ACL + WS path verified, ready to flash.
**Date:** 2026-05-05
**Trigger:** Production launched with `MQTT_DOMAIN=wss://mqtt.sleeptech.me`, but firmware was still PubSubClient + TCP-only and refused `wss` scheme.

## Why cách B (WSS through Cloudflare tunnel) was chosen

| Aspect | Outcome |
|---|---|
| Keep ports closed on VPS | ✅ — cloudflared still terminates 443; no `8883` exposure |
| Cloudflare DDoS / WAF coverage for MQTT | ✅ |
| Firewall traversal (corporate / hotel WiFi) | ✅ — port 443 only |
| Cert renewal | ✅ — managed by Cloudflare, no certbot |
| Browser MQTT debug (MQTT.js) | ✅ — same wss endpoint |
| Trade-offs accepted | TLS+WS framing overhead (~4× vs raw MQTT), ~10KB extra ESP32 RAM, ~1s extra reconnect latency |

## Implementation summary

### Library swap
- **Removed:** `knolleary/PubSubClient @ ^2.8` (no native WS support)
- **Added:** `mqtt_client.h` + `esp_crt_bundle.h` from arduino-esp32 v3.3.8 (ESP-IDF v5.5.4) — no external lib needed

### Files modified
- `firmware/src/mqtt-client.cpp` — full rewrite with `esp_mqtt_client` + event-driven model
- `firmware/src/mqtt-client.h` — comment update only; public API signatures preserved
- `firmware/platformio.ini` — drop PubSubClient lib_dep
- `backend/mosquitto/acl-prod` — fix pre-existing gap: device cmd subscribe + subscriber cmd publish

### Public API stability
`main.cpp` and `ble-provisioning.cpp` did not need to change. Same signatures:
- `mqtt_setup(device_id, host, scheme, user, pass)` — now accepts `tcp|ws|wss|mqtts`
- `mqtt_connect()` — blocking up to 10s waiting for CONNECTED event
- `mqtt_loop()` — no-op (esp-mqtt has its own driver task)
- `mqtt_publish_sec/min`, `mqtt_connected()` — unchanged

### URI construction
| Backend `mqtt_scheme` | Built URI |
|---|---|
| `tcp` | `mqtt://host:1883` (port appended if not in host) |
| `mqtts` | `mqtts://host` |
| `ws` | `ws://host/mqtt` |
| `wss` | `wss://host/mqtt` |

Path `/mqtt` is required for production: cloudflared forwards path-as-is to mosquitto:9001. Verified that mosquitto's WS listener accepts both `/` and `/mqtt`.

### TLS verification
`cfg.broker.verification.crt_bundle_attach = esp_crt_bundle_attach` — uses Mozilla CA bundle compiled into mbedtls. No per-device cert provisioning needed; Cloudflare's cert chain validates out of the box.

### Behavior preserved
- LWT: `sleeppad/{id}/status` = `"offline"`, retain=true, QoS=0
- On connect: publish `"online"` retain=true; subscribe `sleeppad/{id}/cmd` QoS=1
- On `factory_reset` cmd: clear retained → wipe NVS → `ESP.restart()`
- JSON sec/min publish to `sleeppad/{id}/{sec,min}`, QoS=0, no retain
- Auto-reconnect: now handled by esp-mqtt driver (5s reconnect_timeout_ms)

## Pre-existing prod ACL gap (fixed in same migration)

Mosquitto ACL on prod was rejecting two paths silently:

1. Device subscribing to `sleeppad/{own}/cmd` — no `pattern read` rule
2. Backend (`sleeppad-subscriber` user) publishing to `sleeppad/+/cmd` — only had `topic read`

→ Without firmware ever connecting to prod, this would have surfaced as: `factory_reset` from the Flutter app (DELETE /devices/{id}) would silently fail to wipe the device.

Added rules:
```
pattern read  sleeppad/%c/cmd
pattern write sleeppad/%c/cmd
topic write sleeppad/+/cmd     # under user sleeppad-subscriber
```

Verified end-to-end on prod broker (paho-mqtt over wss): SUBACK QoS 1 granted, factory_reset received by simulated device, backend publish rc=0.

## Verification

| Check | Result |
|---|---|
| `pio run -e esp32dev` | SUCCESS — RAM 19.1%, Flash 59.8% |
| `pio run -e esp32dev-mock` | SUCCESS — RAM 19.1%, Flash 59.9% |
| WS path `/` reaches mosquitto via cloudflared | rc=0 |
| WS path `/mqtt` reaches mosquitto via cloudflared | rc=0 |
| TLS cert chain (Cloudflare) verifies | ✅ via crt_bundle |
| ACL: device subscribe own `cmd` topic | granted QoS 1 |
| ACL: device publish own `cmd` (clear retained) | granted |
| ACL: backend `sleeppad-subscriber` publish `cmd` | rc=0 |

## Remaining work

1. **Flash + smoke test on physical ESP32**: BLE provision with `scheme=wss` from Flutter app on physical device. Confirm sec/min frames land in Postgres + Realtime WS pushes to app. _(Not done in this session — needs hardware on bench.)_
2. **Flutter prod URL fix**: `app_env.dart` ProdEnv still uses `sleeppad.io` — must change to `sleeptech.me`. Tracked separately.

## Unresolved questions

- esp-mqtt's default keepalive (60s set in cfg) — Cloudflare Tunnel WebSocket idle timeout is not officially documented. If Cloudflare drops idle WS at >60s, may need to lower keepalive or add a heartbeat publish. Watch for `MQTT_EVENT_DISCONNECTED` storms in prod logs.
- `mqtt_connect()` returns false after 10s timeout but the driver task keeps reconnecting in background. The BLE provisioning path treats false as `mqtt_failed` and sits in re-provisioning loop — but if the driver eventually connects in the background after we already moved to "failed" state, we may publish `"online"` from a UI state that thinks we're offline. Low risk in practice (10s is generous), but worth monitoring.
