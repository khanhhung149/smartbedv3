idf_component_register(
    SRCS "main.cpp" "storage.cpp" "vl53l0x.cpp"
    INCLUDE_DIRS "." "../include"
    REQUIRES esp32-camera nvs_flash esp_wifi esp_netif esp_event lwip driver sdmmc fatfs
)
