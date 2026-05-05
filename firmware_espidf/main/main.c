#include <stdio.h>
#include <string.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include "ble.h"
#include "connect_wifi.h"

void app_main(void)
{
	ble_init();
    wifi_init();
    printf("BLE initialization complete. Waiting for configuration...\n");
    while (1)
    {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    
}
