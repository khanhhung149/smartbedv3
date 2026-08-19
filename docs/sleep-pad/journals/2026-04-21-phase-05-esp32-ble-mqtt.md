# Phase 05: ESP32 BLE GATT + MQTT Client Rewrite

**Date**: 2026-04-21
**Severity**: High
**Component**: ESP32 Firmware (WiFiManager → BLE provisioning, MQTT client)
**Status**: Completed

## What Shipped

Completed ESP32 firmware rewrite replacing WiFiManager web UI with BLE GATT provisioning and MQTT client integration. Build: SUCCESS. Flash 49.8% (1568 KB), RAM 17.7%. Delegated implementation to fullstack-developer subagent, reviewed findings in-line, applied 6 fixes without re-dispatch.

## Key Decisions & Close Calls

**Flash partition overflow** — Initial build failed; BLE + WiFi + PubSubClient hit 1.25 MB app limit. Agent caught it, switched to `huge_app.csv` (3 MB app region). Learning: any ESP32 combining BLE + WiFi + substantial libs needs this upfront.

**WS/WSS deferred** — PubSubClient only supports TCP. Prod deployment needs cloudflared WSS (wss://mqtt.domain.com:443); current firmware logs warning and fails gracefully on ws/wss schemes. TCP path is POC-only. Will block production deploy.

**Name-shadow bug avoided** — Agent exposed `nvs_erase_all()` in module; name-collision with ESP-IDF's `nvs_erase_all(nvs_handle_t)`. Silent compiler win, but wrong call would brick flash. Renamed module function to `nvs_config_erase_all()`, explicit scope `::nvs_erase_all(h)` inside. Small change, catastrophic footgun prevented.

**BLE uninitialized crash** — When WiFi creds exist in NVS, firmware skips BLE provisioning. Old code still called `ble_stop()` on uninitialized stack → crash on reboot. Made idempotent with null checks. Would've been a nightmare without a debugger.

**UART starvation from blocking MQTT** — PubSubClient.connect() defaults to 15s timeout. Unreachable broker stalled main loop 15s, overflowing 768B UART buffer (115200 baud × 15s = 172 KB). Fixed with `setSocketTimeout(2)`. Telemetry stays live through outages.

**Cross-thread volatile volatility** — BLE callbacks run on BLE FreeRTOS task, main loop elsewhere. `while (!s_prov_done) delay(100)` would spin forever without `volatile` on the flag; compiler caches reads. All 7 cross-thread flags marked volatile.

**Empty string provisioning** — Original code accepted empty WiFi SSID/password. Adversary or buggy client could satisfy provisioning with blanks. Fixed with per-char `allow_empty` flag: WiFi/host/scheme required non-empty, mqtt_user/mqtt_pass optional for anonymous dev brokers.

## The Real Problem Avoided

Subagent shipped working code first try. Code review found subtle failures—crashes on edge cases, race conditions, security holes—that would have shipped to device and been unretrievable. This is why we review before merge, every time.

## Next

Phase 06: Flutter scaffold + BLE provisioning UI handshake.
