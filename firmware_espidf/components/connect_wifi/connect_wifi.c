#include <string.h>
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "nvs_flash.h"
#include "esp_system.h"
#include "nvs.h"
#include "nvs_flash.h"
#include <ctype.h>
#include <inttypes.h>
#include <esp_log.h>    

#include "ble.h"
#include "connect_wifi.h"
#include "mqtt_wifi.h"

static EventGroupHandle_t s_wifi_event_group;
static const int WIFI_CONNECTED_BIT = BIT0;
static bool s_connected = false;
static int s_retry_num = 0;
static bool got_ip = false;
static const char *TAG = "WIFI";

static char buffer[512];

static void wifi_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT)
    {
        switch (event_id)
        {
        case WIFI_EVENT_STA_START:
            esp_wifi_connect();
            break;
        case WIFI_EVENT_STA_CONNECTED:
            printf("connected to wifi successful\r\n");
            break;
        case WIFI_EVENT_STA_DISCONNECTED:
            ESP_LOGI(TAG, "WiFi disconnected");
            xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);

            wifi_mode_t mode;
            esp_wifi_get_mode(&mode);

            if (mode == WIFI_MODE_AP)
            {
                ESP_LOGI("WIFI", "Đang ở chế độ Access Point");
                // wifi_state = 2;
            }
            else if (mode == WIFI_MODE_STA)
            {
                ESP_LOGI("WIFI", "Đang ở chế độ Station");
                // reopen_network();
            }
            else if (mode == WIFI_MODE_APSTA)
            {
                ESP_LOGI("WIFI", "Đang ở chế độ AP + STA ");
                // wifi_state = 2;
            }
            else
            {
                ESP_LOGI("WIFI", "Wi-Fi đang tắt hoặc không xác định");
            }
            break;
        case WIFI_EVENT_AP_STACONNECTED:
            ESP_LOGI(TAG, "User access to AP");
            // act_handle = true;
            break;
        case WIFI_EVENT_AP_STADISCONNECTED:
            ESP_LOGI(TAG, "Out from setup wifi mode");
            // act_handle = false;
            break;
        default:
            break;
        }
    }
}

static void ip_event_handler(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data) // internet protocol (IP)
{
    if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP)
    {
        got_ip = true;
        ESP_LOGI(TAG, "Got IP address");
        s_connected = true;
        s_retry_num = 0;
        
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
        // stop_my_timer();
        // Disable access point mode after successful station connection
        vTaskDelay(3000 / portTICK_PERIOD_MS);
        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
        ESP_LOGI(TAG, "Connect to WiFi successful > connect MQTT");
        snprintf(buffer, sizeof(buffer), "%s://%s:443", s_config.mqtt_scheme, s_config.mqtt_broker);
        /* MQTT client_id MUST equal device_id — Mosquitto ACL enforces
         * write sleeppad/%c/# so a mismatch silently drops publishes. */
        mqtt_init(buffer, ble_get_device_id(), s_config.mqtt_username, s_config.mqtt_password);
    }
}

void wifi_connect_sta(const char *ssid, const char *pass) // thử kết nối WiFi ở chế độ STA  (station: truy cập vào wifi của người dùng)
{
    wifi_config_t sta_conf = {0};
    strncpy((char *)sta_conf.sta.ssid, ssid, sizeof(sta_conf.sta.ssid) - 1);
    strncpy((char *)sta_conf.sta.password, pass, sizeof(sta_conf.sta.password) - 1);
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    esp_wifi_disconnect();
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &sta_conf));
    ESP_ERROR_CHECK(esp_wifi_start());
    esp_err_t err = esp_wifi_connect();
    if (err != ESP_OK)
    {
        ESP_LOGW(TAG, "esp_wifi_connect failed: %d", err);
    }
    else
    {
        ESP_LOGI(TAG, "Connecting to SSID: %s", ssid);
    }
}

void wifi_init(void)
{
    s_wifi_event_group = xEventGroupCreate();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    esp_event_handler_instance_t instance_any_id;
    esp_event_handler_instance_t instance_got_ip;
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, &instance_any_id));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &ip_event_handler, NULL, &instance_got_ip));
}