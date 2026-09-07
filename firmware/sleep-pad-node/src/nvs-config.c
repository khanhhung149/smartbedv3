#include "nvs-config.h"
#include <string.h>
#include <nvs_flash.h>
#include <nvs.h>
#include "esp_log.h"

static const char* TAG = "nvs-config";

bool nvs_init(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "Partition corrupted — erasing and reinitialising");
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Init failed: %s", esp_err_to_name(err));
        return false;
    }
    return true;
}

// Helper: open handle, read one string key into a fixed buffer, close handle.
static void nvs_get_string(const char* key, char* out, size_t cap) {
    out[0] = '\0';
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &h) != ESP_OK) return;

    size_t len = cap;
    if (nvs_get_str(h, key, out, &len) != ESP_OK) {
        out[0] = '\0';
    }
    nvs_close(h);
}

NvsConfig nvs_load(void) {
    NvsConfig cfg = {0};
    nvs_get_string(NVS_KEY_SSID,   cfg.wifi_ssid,   sizeof(cfg.wifi_ssid));
    nvs_get_string(NVS_KEY_PASS,   cfg.wifi_pass,   sizeof(cfg.wifi_pass));
    nvs_get_string(NVS_KEY_HOST,   cfg.mqtt_host,   sizeof(cfg.mqtt_host));
    nvs_get_string(NVS_KEY_SCHEME, cfg.mqtt_scheme, sizeof(cfg.mqtt_scheme));
    nvs_get_string(NVS_KEY_USER,   cfg.mqtt_user,   sizeof(cfg.mqtt_user));
    nvs_get_string(NVS_KEY_MPASS,  cfg.mqtt_pass,   sizeof(cfg.mqtt_pass));
    return cfg;
}

bool nvs_set(const char* key, const char* value) {
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Open failed for key %s: %s", key, esp_err_to_name(err));
        return false;
    }
    err = nvs_set_str(h, key, value);
    if (err == ESP_OK) {
        nvs_commit(h);
    } else {
        ESP_LOGE(TAG, "Write failed for key %s: %s", key, esp_err_to_name(err));
    }
    nvs_close(h);
    return err == ESP_OK;
}

void nvs_config_erase_all(void) {
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h) == ESP_OK) {
        nvs_erase_all(h);
        nvs_commit(h);
        nvs_close(h);
        ESP_LOGI(TAG, "All keys erased");
    }
}
