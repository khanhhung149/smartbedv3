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
#include "nvs_config.h"

// Define MOCK_SLEEPPAD in config_parameter.h to enable mock mode

static const char *TAG = "MAIN";

void app_main(void)
{
    /* NVS init early — both the boot-resume path and ble_init() require it.
     * Erase + retry on partition format mismatch (covers first flash and
     * the rare bump in NVS layout version). */
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    /* device_id is MAC-derived — the call below also primes ble_get_device_id()
     * for downstream consumers (sleep_pad reader, mqtt client). */
    const char *device_id = ble_get_device_id();

    /* Always init the WiFi stack so wifi_connect_sta works regardless of
     * whether we go through BLE pairing or boot-resume from NVS. */
    wifi_init();

    /* Try resume: if NVS already holds WiFi creds (i.e. user paired this
     * device previously and we're just rebooting), skip BLE entirely and
     * connect directly. wifi_connect_sta → IP_GOT_IP → mqtt_init.
     * Otherwise advertise over BLE so the app can provision us. */
    if (nvs_config_load(&s_config)) {
        ESP_LOGI(TAG, "Resuming with NVS creds (ssid=%s, scheme=%s, host=%s) device_id=%s",
                 s_config.wifi_ssid, s_config.mqtt_scheme, s_config.mqtt_broker, device_id);
        wifi_connect_sta(s_config.wifi_ssid, s_config.wifi_password);
    } else {
        ESP_LOGI(TAG, "No NVS creds — starting BLE provisioning (device_id=%s)", device_id);
        ble_init();
    }

#ifdef MOCK_SLEEPPAD
    sleep_pad_reader_init(device_id, true);
    ESP_LOGI(TAG, "Mock Sleep Pad mode active");
#else
    sleep_pad_reader_init(device_id, false);
    ESP_LOGI(TAG, "Real UART Sleep Pad mode active");
#endif

    xTaskCreate(sleep_pad_task, "sleep_pad_task", 4096, NULL, 5, NULL);
    while (1)
    {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
