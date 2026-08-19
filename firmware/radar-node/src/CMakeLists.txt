idf_component_register(
    SRCS "main.c" "ld2410.c" "net.c" "ota.c"
    # ../include giữ config.h (WiFi/MQTT/OTA password) — file này .gitignore, không commit.
    INCLUDE_DIRS "." "../include"
    REQUIRES driver esp_wifi esp_netif esp_timer esp_http_server app_update mqtt nvs_flash mdns
)
