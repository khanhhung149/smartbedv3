# Phase 05 ESP32 Firmware — Review

Build SUCCESS (Flash 49.8%, RAM 17.7%). All files <200 LOC. Protocol doc has DeviceId at `...26af` and Unresolved/Resolved sections correct.

## CRITICAL

1. **`ble_stop()` called on uninitialised BLE stack when creds already in NVS** (`main.cpp:133`). On normal reboot path (line 128 branch), `ble_init()` is never called, yet line 133 invokes `ble_stop()` → `BLEDevice::deinit(true)` on an uninitialised stack. High crash risk on every reboot after first provisioning. Fix: guard `ble_stop()` behind an `s_inited` flag, or only call from the provisioning branch.

2. **MQTT reconnect blocks the main loop** (`mqtt-client.cpp:122` inside `mqtt_loop`). `PubSubClient::connect()` is synchronous (up to ~socket-timeout seconds). While blocked, `Serial2.available()` drains into the 128-byte UART FIFO; a dead broker will cause dropped frames and missed 0x87 idle handling. Move reconnect to a dedicated FreeRTOS task, or at minimum cap socket timeout (`s_wifi_client.setTimeout(2)`).

## HIGH

3. **Potential function-name shadow in `nvs_erase_all()`** (`nvs-config.cpp:66-74`). Public `void nvs_erase_all()` internally calls `nvs_erase_all(h)`. Relies entirely on `nvs.h` providing the C-linkage overload; if header include order changes or `nvs.h` gets wrapped, this becomes infinite recursion. Rename the wrapper (e.g. `nvs_wipe()`).

4. **Empty BLE writes accepted as "received"** (`ble-provisioning.cpp:46-52`). A client writing an empty string to SSID satisfies `s_got_ssid=true`; `all_received()` fires, `ble_set_status("connecting")` sent, but `has_wifi_creds()` returns false and reboot loop kicks in. Wastes an NVS erase cycle and confuses Flutter UI. Validate `val.length() > 0` before flipping the flag for SSID and ServerHost at minimum.

5. **JSON publish buffer fixed at 256B with silent truncation** (`mqtt-client.cpp:141,161`). `serializeJson` returns bytes written; when output exceeds 256, publish gets a truncated (invalid) JSON. Min frame (~200 B) is close to the limit. Size up to 384, or check `n < sizeof(buf)` and log on overflow.

6. **`s_prov_done` race** (`ble-provisioning.cpp:21`). Written in BLE callback thread, polled in setup() main thread without atomic/volatile. Works today on ESP32 aligned-bool read but is technically UB. Make it `std::atomic<bool>` or `volatile bool`.

## Suggestions

- Line 175 (`main.cpp`): on first boot `last_heartbeat_ms=0`, so first heartbeat fires 60 s after power-up — intentional but worth a comment.
- `parse_host_port` uses `lastIndexOf(':')`; harmless for IPv4/hostnames, would break IPv6 literals (not in scope).
- LWT, client_id=device_id, retain=true online publish, keepalive 60s all match protocol doc correctly.
- Heartbeat 0x08 every 60 s and 0x04 monitor-mode restart on 0x87 idle are both wired correctly.
- `nvs_get_string` uses `new[]/delete[]`; fine, but `std::unique_ptr<char[]>` would be exception-safe for free.
- Consider logging `WiFi.RSSI()` after connect for field diagnostics.
- ws/wss path logs a clear warning and sets `s_scheme_ok=false`; `mqtt_connect()` returns false and `mqtt_loop()` short-circuits — graceful, no crash. Good.

## Unresolved

- Should `ble_set_status("connecting")` await actual WiFi attempt result? Current code sets it before `ble_stop()`, but BLE is already being torn down — the notify may not reach Flutter.
- No `mqtt_failed` status path is ever written (status char only goes `waiting` → `connecting`). Flutter 60s timeout is the only signal of failure.

Status: DONE_WITH_CONCERNS
Summary: Firmware is functionally close but has one crash-on-reboot bug (ble_stop on uninitialised stack) and one blocking-reconnect issue that can drop UART frames. Both are fix-before-merge.
Concerns/Blockers: CRITICAL #1 and #2 must be fixed before deployment; HIGH items should be addressed in same pass.
