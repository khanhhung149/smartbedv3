#pragma once
#include <stdbool.h>

// NVS namespace and key names — must match protocol doc (giữ nguyên bản Arduino cũ,
// app Flutter + backend không đọc trực tiếp NVS nên đây không phải contract byte-for-byte,
// nhưng đổi tên vẫn phải đồng bộ với ble-provisioning.c dùng cùng key).
#define NVS_NAMESPACE  "sleeppad"
#define NVS_KEY_SSID   "wifi_ssid"
#define NVS_KEY_PASS   "wifi_pass"
#define NVS_KEY_HOST   "mqtt_host"
#define NVS_KEY_SCHEME "mqtt_scheme"
#define NVS_KEY_USER   "mqtt_user"
#define NVS_KEY_MPASS  "mqtt_pass"

// Độ dài buffer đủ cho SSID (32) / password (64) / host (64, có thể mang ":port") /
// scheme ("wss" ...) / mqtt user-pass. 96 dư an toàn cho mọi trường, tránh cấp phát động.
#define NVS_STR_CAP 96

typedef struct {
    char wifi_ssid[NVS_STR_CAP];
    char wifi_pass[NVS_STR_CAP];
    char mqtt_host[NVS_STR_CAP];    // host[:port], no scheme
    char mqtt_scheme[NVS_STR_CAP];  // "tcp" | "ws" | "wss"
    char mqtt_user[NVS_STR_CAP];    // may be empty
    char mqtt_pass[NVS_STR_CAP];    // may be empty
} NvsConfig;

static inline bool nvs_config_has_wifi_creds(const NvsConfig* cfg) {
    return cfg->wifi_ssid[0] != '\0';
}

// Initialize NVS flash partition. Call once in app_main().
// Returns false if NVS was erased due to corruption.
bool nvs_init(void);

// Load all config keys from NVS. Missing keys yield empty strings.
NvsConfig nvs_load(void);

// Persist a single key. Returns false on write error.
bool nvs_set(const char* key, const char* value);

// Erase all keys in the sleeppad namespace (factory reset).
void nvs_config_erase_all(void);
