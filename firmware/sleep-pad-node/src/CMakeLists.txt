idf_component_register(
    SRCS "main.c" "ble-provisioning.c" "mqtt-client.c" "nvs-config.c"
         "uart-parser.c" "sleep-pad-frame.c" "mock-sleeppad.c"
    # ../include giữ config.h (chân UART) + dev-config.h (WiFi/MQTT máy này) — cả hai
    # .gitignore, không commit. Xem firmware/sleep-pad-node/.gitignore ở repo root.
    INCLUDE_DIRS "." "../include"
    REQUIRES driver esp_wifi esp_netif esp_timer mqtt nvs_flash bt esp_event esp_hw_support
)
