#pragma once
#include <Arduino.h>

// BLE GATT provisioning server.
// Advertises as "SleepPad-{last6}" and exposes a custom GATT service
// with 6 WRITE characteristics (WiFi + MQTT creds) and 1 READ/NOTIFY
// Status characteristic plus 1 READ DeviceId characteristic.
//
// Usage:
//   ble_init(device_id);        // call once in setup()
//   ble_set_status("waiting");  // update status visible to Flutter
//   ble_stop();                 // call before starting WiFi

// Initialise BLE server and begin advertising.
// device_id: null-terminated string, e.g. "CNU2000001"
void ble_init(const char* device_id);

// Update the Status characteristic value and notify connected client.
// Valid values: "waiting", "connecting", "connected", "wifi_failed", "mqtt_failed"
void ble_set_status(const char* status);

// Stop BLE stack to free memory before WiFi+MQTT start.
void ble_stop();

// Returns true once all 6 WRITE characteristics have been received
// and NVS has been updated. main.cpp polls this before proceeding.
bool ble_provisioning_complete();
