#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_log.h>
#include <string.h>
#include <esp_err.h>
#include <mqtt_client.h>
#include <esp_bt.h>
#include <esp_bt_defs.h>
#include <esp_bt_main.h>
#include <esp_gap_ble_api.h>
#include "connect_wifi.h"

#include "mqtt_wifi.h"

static const char *TAG = "MQTT_WIFI";
RTC_DATA_ATTR static esp_mqtt_client_handle_t client;

static esp_err_t mqtt_subscribe(esp_mqtt_client_handle_t client_id, const char *topic, int qos)
{
    int msg_id = esp_mqtt_client_subscribe_single(client_id, topic, qos);
    ESP_LOGI(TAG, "Subscribed to topic %s with message ID: %d", topic, msg_id);
    if (msg_id == -1)
        return ESP_FAIL;
    else
        return ESP_OK;
}

static esp_err_t mqtt_publish(esp_mqtt_client_handle_t client_id, const char *topic, const char *data, int len, int qos, int retain)
{
    int msg_id = esp_mqtt_client_publish(client_id, topic, data, len, qos, retain);
    ESP_LOGI(TAG, "Published message with ID: %d", msg_id);
    if (msg_id == -1)
        return ESP_FAIL;
    else
        return ESP_OK;
}

void mqtt_publish_data(char *data, char *topic)
{
    // snprintf(mqtt_client_id, sizeof(mqtt_client_id), "%s_%s",DEVICE_NAME,device_name);
    if (client == NULL)
    {
        ESP_LOGE(TAG, "MQTT client is not initialized");
        return;
    }
    ESP_LOGI(TAG, "MQTT publish");
    esp_mqtt_client_publish(client, topic, data, strlen(data), 1, 0);
}

static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    esp_mqtt_event_handle_t event = event_data;
    esp_mqtt_client_handle_t client = event->client;
    switch ((esp_mqtt_event_id_t)event_id)
    {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "MQTT_EVENT_CONNECTED");
        esp_ble_gap_stop_advertising();          // Stop BLE advertising when MQTT is connected
        mqtt_subscribe(client, "sleeppad/test", 0);
        break;
    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGI(TAG, "MQTT_EVENT_DISCONNECTED");
        break;
    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGI(TAG, "MQTT_EVENT_SUBSCRIBED, msg_id=%d", event->msg_id);
        break;
    case MQTT_EVENT_UNSUBSCRIBED:
        ESP_LOGI(TAG, "MQTT_EVENT_UNSUBSCRIBED, msg_id=%d", event->msg_id);
        break;
    case MQTT_EVENT_PUBLISHED:
        ESP_LOGI(TAG, "MQTT_EVENT_PUBLISHED, msg_id=%d", event->msg_id);
        break;
    case MQTT_EVENT_DATA:
        ESP_LOGI(TAG, "MQTT_EVENT_DATA");
        printf("Received topic: %.*s\r\n", event->topic_len, event->topic);
        printf("Received data: %.*s\r\n", event->data_len, event->data);
        break;
    case MQTT_EVENT_ERROR:
        ESP_LOGI(TAG, "MQTT_EVENT_ERROR");
        break;
    default:
        ESP_LOGI(TAG, "Other event id:%d", event->event_id);
        break;
    }
}

void mqtt_init(char *mqtt_address, char *client_id, char *username, char *password)
{
    ESP_LOGI(TAG, "MQTT configuration function called");
    const esp_mqtt_client_config_t mqtt_cfg = {
        .broker.address.uri = mqtt_address,
        .credentials.client_id = client_id,
        .credentials.username = username,
        .credentials.authentication.password = password,
        .network.reconnect_timeout_ms = 5000,
        .session.keepalive = 120,
    };
    client = esp_mqtt_client_init(&mqtt_cfg);
    esp_mqtt_client_register_event(client, ESP_EVENT_ANY_ID, mqtt_event_handler, client);
    esp_mqtt_client_start(client);
}
