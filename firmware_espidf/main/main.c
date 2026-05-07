#include <stdio.h>
#include <string.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include "ble.h"
#include "connect_wifi.h"
#include "sleep_pad_reader.h"
#include "config_parameter.h"

// Define to enable mock mode, comment out for real UART reading

void app_main(void)
{
    ble_init();
    wifi_init();

    /* Per protocol spec: sleep pad publishes use device_id derived from
     * efuse MAC inside ble_init() — mqtt topic must match ACL pattern. */
    const char *device_id = ble_get_device_id();

#ifdef MOCK_SLEEPPAD
    sleep_pad_reader_init(device_id, true);
    ESP_LOGI("MAIN", "Mock Sleep Pad mode active (device_id=%s)", device_id);
#else
    sleep_pad_reader_init(device_id, false);
    ESP_LOGI("MAIN", "Real UART Sleep Pad mode active (device_id=%s)", device_id);
#endif

    ESP_LOGI("MAIN", "BLE initialization complete. Waiting for configuration...");
    xTaskCreate(sleep_pad_task, "sleep_pad_task", 4096, NULL, 5, NULL);
    while (1)
    {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
