#pragma once
#include <Arduino.h>

// NVS namespace and key names — must match protocol doc
#define NVS_NAMESPACE  "sleeppad"
#define NVS_KEY_SSID   "wifi_ssid"
#define NVS_KEY_PASS   "wifi_pass"
#define NVS_KEY_HOST   "mqtt_host"
#define NVS_KEY_SCHEME "mqtt_scheme"
#define NVS_KEY_USER   "mqtt_user"
#define NVS_KEY_MPASS  "mqtt_pass"

struct NvsConfig {
    String wifi_ssid;
    String wifi_pass;
    String mqtt_host;    // host[:port], no scheme
    String mqtt_scheme;  // "tcp" | "ws" | "wss"
    String mqtt_user;    // may be empty
    String mqtt_pass;    // may be empty

    bool has_wifi_creds() const { return wifi_ssid.length() > 0; }
};

// Initialize NVS flash partition. Call once in setup().
// Returns false if NVS was erased due to corruption.
bool nvs_init();

// Load all config keys from NVS. Missing keys yield empty strings.
NvsConfig nvs_load();

// Persist a single key. Returns false on write error.
bool nvs_set(const char* key, const String& value);

// Erase all keys in the sleeppad namespace (factory reset).
// Renamed from `nvs_erase_all` to avoid shadowing the ESP-IDF C API
// `nvs_erase_all(nvs_handle_t)` declared in <nvs.h>.
void nvs_config_erase_all();
