#include "nvs-config.h"
#include <nvs_flash.h>
#include <nvs.h>

bool nvs_init() {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        Serial.println("[NVS] Partition corrupted — erasing and reinitialising");
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        Serial.printf("[NVS] Init failed: %s\n", esp_err_to_name(err));
        return false;
    }
    return true;
}

// Helper: open handle, read one string key, close handle.
static String nvs_get_string(const char* key) {
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &h);
    if (err != ESP_OK) return String();

    size_t len = 0;
    err = nvs_get_str(h, key, nullptr, &len);
    String result;
    if (err == ESP_OK && len > 0) {
        char* buf = new char[len];
        nvs_get_str(h, key, buf, &len);
        result = String(buf);
        delete[] buf;
    }
    nvs_close(h);
    return result;
}

NvsConfig nvs_load() {
    NvsConfig cfg;
    cfg.wifi_ssid   = nvs_get_string(NVS_KEY_SSID);
    cfg.wifi_pass   = nvs_get_string(NVS_KEY_PASS);
    cfg.mqtt_host   = nvs_get_string(NVS_KEY_HOST);
    cfg.mqtt_scheme = nvs_get_string(NVS_KEY_SCHEME);
    cfg.mqtt_user   = nvs_get_string(NVS_KEY_USER);
    cfg.mqtt_pass   = nvs_get_string(NVS_KEY_MPASS);
    return cfg;
}

bool nvs_set(const char* key, const String& value) {
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        Serial.printf("[NVS] Open failed for key %s: %s\n", key, esp_err_to_name(err));
        return false;
    }
    err = nvs_set_str(h, key, value.c_str());
    if (err == ESP_OK) {
        nvs_commit(h);
    } else {
        Serial.printf("[NVS] Write failed for key %s: %s\n", key, esp_err_to_name(err));
    }
    nvs_close(h);
    return err == ESP_OK;
}

void nvs_config_erase_all() {
    nvs_handle_t h;
    // `::nvs_erase_all(h)` disambiguates from the free function at file scope
    // (not strictly needed after the rename, but explicit for future readers).
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h) == ESP_OK) {
        ::nvs_erase_all(h);
        nvs_commit(h);
        nvs_close(h);
        Serial.println("[NVS] All keys erased");
    }
}
