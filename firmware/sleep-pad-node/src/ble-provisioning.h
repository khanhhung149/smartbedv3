#pragma once
#include <stdbool.h>

// BLE GATT provisioning server (ESP-IDF Bluedroid, esp_gap_ble_api/esp_gatts_api).
// Advertises as "SleepPad-{last6}" and exposes a custom GATT service with 6 WRITE
// characteristics (WiFi + MQTT creds) and 1 READ/NOTIFY Status characteristic plus
// 1 READ DeviceId characteristic.
//
// CONTRACT KHÔNG ĐƯỢC ĐỔI (app Flutter phụ thuộc trực tiếp): UUID service + 6
// characteristic WRITE + Status (READ/NOTIFY) + DeviceId (READ) phải giữ nguyên UUID,
// thứ tự, kiểu dữ liệu byte — xem plan 260824-1109.
//
// Usage:
//   ble_init(device_id);        // call once in app_main()
//   ble_set_status("waiting");  // update status visible to Flutter
//   ble_stop();                 // call before starting WiFi

// Initialise BLE stack (controller + Bluedroid), create GATT server, start advertising.
// device_id: null-terminated string, e.g. "CNU2000001"
void ble_init(const char* device_id);

// Update the Status characteristic value and notify connected client (if subscribed).
// Valid values per protocol:
//   Progress:  "waiting" → "wifi_connecting" → "wifi_connected" →
//              "mqtt_connecting" → "connected"
//   Terminal failures (retry loop): "wifi_failed", "mqtt_failed"
void ble_set_status(const char* status);

// Stop BLE stack to free memory (call after "connected" emitted + delay).
void ble_stop(void);

// Returns true once all 6 WRITE characteristics have been received
// since the last reset (or initial boot). Polled by main retry loop.
bool ble_provisioning_complete(void);

// Clear the "all 6 received" flag so main can wait for a fresh re-write
// after a wifi_failed / mqtt_failed status. NVS values stay in place
// until overwritten by new BLE writes.
void ble_reset_pending_writes(void);

// Returns true if the BLE client disconnected *after* initial provisioning —
// used by main retry loop to treat disconnect as user cancel.
bool ble_user_cancelled(void);
