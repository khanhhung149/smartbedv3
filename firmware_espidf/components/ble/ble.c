#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_log.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <esp_bt.h>
#include <esp_bt_defs.h>
#include <esp_bt_main.h>
#include <esp_gap_ble_api.h>
#include <esp_gatts_api.h>
#include <esp_gatt_common_api.h>
#include <esp_err.h>
#include <nvs_flash.h>

#include "ble.h"
#include "connect_wifi.h"
#include "mqtt_wifi.h"

static const char *TAG = "BLE";

#define DEVICE_NAME                "SLEEP_PAD_SETUP"
#define GATTS_APP_ID               0
#define GATTS_SERVICE_UUID         0x00FF
#define GATTS_CHAR_UUID_SSID       0xFF01
#define GATTS_CHAR_UUID_WIFI_PASS  0xFF02
#define GATTS_CHAR_UUID_BROKER     0xFF03
#define GATTS_CHAR_UUID_USERNAME   0xFF04
#define GATTS_CHAR_UUID_MQTT_PASS  0xFF05
#define GATTS_CHAR_UUID_SCHEME     0xFF06
#define GATTS_NUM_HANDLE           19
#define GATTS_SERVICE_INSTANCE_ID  0

enum {
    IDX_SVC,

    IDX_CHAR_SSID_DECL,
    IDX_CHAR_SSID_VALUE,
    IDX_CHAR_SSID_DESC,

    IDX_CHAR_WIFI_PASS_DECL,
    IDX_CHAR_WIFI_PASS_VALUE,
    IDX_CHAR_WIFI_PASS_DESC,

    IDX_CHAR_BROKER_DECL,
    IDX_CHAR_BROKER_VALUE,
    IDX_CHAR_BROKER_DESC,

    IDX_CHAR_USERNAME_DECL,
    IDX_CHAR_USERNAME_VALUE,
    IDX_CHAR_USERNAME_DESC,

    IDX_CHAR_MQTT_PASS_DECL,
    IDX_CHAR_MQTT_PASS_VALUE,
    IDX_CHAR_MQTT_PASS_DESC,

    IDX_CHAR_SCHEME_DECL,
    IDX_CHAR_SCHEME_VALUE,
    IDX_CHAR_SCHEME_DESC,

    IDX_NB
};

ble_config_data_t s_config;
static bool s_ble_started;
static esp_gatt_if_t s_gatts_if = ESP_GATT_IF_NONE;
static uint16_t s_handle_table[IDX_NB];

static uint16_t s_service_uuid = GATTS_SERVICE_UUID;
static uint16_t s_char_uuid_ssid = GATTS_CHAR_UUID_SSID;
static uint16_t s_char_uuid_wifi_pass = GATTS_CHAR_UUID_WIFI_PASS;
static uint16_t s_char_uuid_broker = GATTS_CHAR_UUID_BROKER;
static uint16_t s_char_uuid_username = GATTS_CHAR_UUID_USERNAME;
static uint16_t s_char_uuid_mqtt_pass = GATTS_CHAR_UUID_MQTT_PASS;
static uint16_t s_char_uuid_scheme = GATTS_CHAR_UUID_SCHEME;

static uint16_t s_primary_service_uuid = ESP_GATT_UUID_PRI_SERVICE;
static uint16_t s_character_declaration_uuid = ESP_GATT_UUID_CHAR_DECLARE;
static uint16_t s_character_user_description_uuid = ESP_GATT_UUID_CHAR_DESCRIPTION;
static uint8_t s_char_prop_write = ESP_GATT_CHAR_PROP_BIT_WRITE;

static const uint8_t s_desc_ssid[] = "WiFi SSID";
static const uint8_t s_desc_wifi_password[] = "WiFi Password";
static const uint8_t s_desc_mqtt_broker[] = "MQTT Broker";
static const uint8_t s_desc_mqtt_username[] = "MQTT Username";
static const uint8_t s_desc_mqtt_password[] = "MQTT Password";
static const uint8_t s_desc_mqtt_scheme[] = "MQTT Scheme";

static bool flag_data_written[6] = {0}; // Track if each characteristic has been written

static uint8_t s_adv_service_uuid128[16] = {
    0xfb, 0x34, 0x9b, 0x5f,
    0x80, 0x00,
    0x00, 0x80,
    0x00, 0x10,
    0x00, 0x00,
    0xff, 0x00,
    0x00, 0x00,
};

static esp_ble_adv_data_t s_adv_data = {
    .set_scan_rsp = false,
    .include_name = true,
    .include_txpower = false,
    .min_interval = 0x20,
    .max_interval = 0x40,
    .appearance = 0x00,
    .manufacturer_len = 0,
    .p_manufacturer_data = NULL,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = sizeof(s_adv_service_uuid128),
    .p_service_uuid = s_adv_service_uuid128,
    .flag = ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT,
};

static esp_ble_adv_params_t s_adv_params = {
    .adv_int_min = 0x20,
    .adv_int_max = 0x40,
    .adv_type = ADV_TYPE_IND,
    .own_addr_type = BLE_ADDR_TYPE_PUBLIC,
    .channel_map = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

static const esp_gatts_attr_db_t s_gatt_db[IDX_NB] = {
    [IDX_SVC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_primary_service_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint16_t),
            sizeof(s_service_uuid),
            (uint8_t *)&s_service_uuid,
        },
    },

    [IDX_CHAR_SSID_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_declaration_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t),
            sizeof(s_char_prop_write),
            (uint8_t *)&s_char_prop_write,
        },
    },
    [IDX_CHAR_SSID_VALUE] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_char_uuid_ssid,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            BLE_WIFI_SSID_MAX_LEN,
            0,
            NULL,
        },
    },
    [IDX_CHAR_SSID_DESC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_user_description_uuid,
            ESP_GATT_PERM_READ,
            sizeof(s_desc_ssid),
            sizeof(s_desc_ssid),
            (uint8_t *)s_desc_ssid,
        },
    },

    [IDX_CHAR_WIFI_PASS_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_declaration_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t),
            sizeof(s_char_prop_write),
            (uint8_t *)&s_char_prop_write,
        },
    },
    [IDX_CHAR_WIFI_PASS_VALUE] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_char_uuid_wifi_pass,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            BLE_WIFI_PASSWORD_MAX_LEN,
            0,
            NULL,
        },
    },
    [IDX_CHAR_WIFI_PASS_DESC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_user_description_uuid,
            ESP_GATT_PERM_READ,
            sizeof(s_desc_wifi_password),
            sizeof(s_desc_wifi_password),
            (uint8_t *)s_desc_wifi_password,
        },
    },

    [IDX_CHAR_BROKER_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_declaration_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t),
            sizeof(s_char_prop_write),
            (uint8_t *)&s_char_prop_write,
        },
    },
    [IDX_CHAR_BROKER_VALUE] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_char_uuid_broker,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            BLE_MQTT_BROKER_MAX_LEN,
            0,
            NULL,
        },
    },
    [IDX_CHAR_BROKER_DESC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_user_description_uuid,
            ESP_GATT_PERM_READ,
            sizeof(s_desc_mqtt_broker),
            sizeof(s_desc_mqtt_broker),
            (uint8_t *)s_desc_mqtt_broker,
        },
    },

    [IDX_CHAR_USERNAME_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_declaration_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t),
            sizeof(s_char_prop_write),
            (uint8_t *)&s_char_prop_write,
        },
    },
    [IDX_CHAR_USERNAME_VALUE] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_char_uuid_username,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            BLE_MQTT_USERNAME_MAX_LEN,
            0,
            NULL,
        },
    },
    [IDX_CHAR_USERNAME_DESC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_user_description_uuid,
            ESP_GATT_PERM_READ,
            sizeof(s_desc_mqtt_username),
            sizeof(s_desc_mqtt_username),
            (uint8_t *)s_desc_mqtt_username,
        },
    },

    [IDX_CHAR_MQTT_PASS_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_declaration_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t),
            sizeof(s_char_prop_write),
            (uint8_t *)&s_char_prop_write,
        },
    },
    [IDX_CHAR_MQTT_PASS_VALUE] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_char_uuid_mqtt_pass,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            BLE_MQTT_PASSWORD_MAX_LEN,
            0,
            NULL,
        },
    },
    [IDX_CHAR_MQTT_PASS_DESC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_user_description_uuid,
            ESP_GATT_PERM_READ,
            sizeof(s_desc_mqtt_password),
            sizeof(s_desc_mqtt_password),
            (uint8_t *)s_desc_mqtt_password,
        },
    },

    [IDX_CHAR_SCHEME_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_declaration_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t),
            sizeof(s_char_prop_write),
            (uint8_t *)&s_char_prop_write,
        },
    },
    [IDX_CHAR_SCHEME_VALUE] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_char_uuid_scheme,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            BLE_MQTT_SCHEME_MAX_LEN,
            0,
            NULL,
        },
    },
    [IDX_CHAR_SCHEME_DESC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&s_character_user_description_uuid,
            ESP_GATT_PERM_READ,
            sizeof(s_desc_mqtt_scheme),
            sizeof(s_desc_mqtt_scheme),
            (uint8_t *)s_desc_mqtt_scheme,
        },
    },
};

static void copy_ble_value(char *dst, size_t dst_size, const uint8_t *src, uint16_t len)
{
    size_t copy_len = len;

    if (copy_len >= dst_size) {
        copy_len = dst_size - 1;
    }

    if (copy_len > 0) {
        memcpy(dst, src, copy_len);
    }
    dst[copy_len] = '\0';
}

static void handle_write_value(uint16_t handle, const uint8_t *value, uint16_t len)
{
    if (handle == s_handle_table[IDX_CHAR_SSID_VALUE]) {
        copy_ble_value(s_config.wifi_ssid, sizeof(s_config.wifi_ssid), value, len);
        printf("Received WiFi SSID: %s\n", s_config.wifi_ssid);
        flag_data_written[0] = true; // Mark SSID as written
        ESP_LOGI(TAG, "Updated WiFi SSID");
    } else if (handle == s_handle_table[IDX_CHAR_WIFI_PASS_VALUE]) {
        copy_ble_value(s_config.wifi_password, sizeof(s_config.wifi_password), value, len);
        printf("Received WiFi password: %s\n", s_config.wifi_password);
        flag_data_written[1] = true; // Mark WiFi password as written
        ESP_LOGI(TAG, "Updated WiFi password");
    } else if (handle == s_handle_table[IDX_CHAR_BROKER_VALUE]) {
        copy_ble_value(s_config.mqtt_broker, sizeof(s_config.mqtt_broker), value, len);
        printf("Received MQTT broker: %s\n", s_config.mqtt_broker);
        flag_data_written[2] = true; // Mark MQTT broker as written
        ESP_LOGI(TAG, "Updated MQTT broker");
    } else if (handle == s_handle_table[IDX_CHAR_USERNAME_VALUE]) {
        copy_ble_value(s_config.mqtt_username, sizeof(s_config.mqtt_username), value, len);
        printf("Received MQTT username: %s\n", s_config.mqtt_username);
        flag_data_written[3] = true; // Mark MQTT username as written
        ESP_LOGI(TAG, "Updated MQTT username");
    } else if (handle == s_handle_table[IDX_CHAR_MQTT_PASS_VALUE]) {
        copy_ble_value(s_config.mqtt_password, sizeof(s_config.mqtt_password), value, len);
        printf("Received MQTT password: %s\n", s_config.mqtt_password);
        flag_data_written[4] = true; // Mark MQTT password as written
        ESP_LOGI(TAG, "Updated MQTT password");
    } else if (handle == s_handle_table[IDX_CHAR_SCHEME_VALUE]) {
        copy_ble_value(s_config.mqtt_scheme, sizeof(s_config.mqtt_scheme), value, len);
        printf("Received MQTT scheme: %s\n", s_config.mqtt_scheme);
        flag_data_written[5] = true; // Mark MQTT scheme as written
        ESP_LOGI(TAG, "Updated MQTT scheme");
    }
    if (flag_data_written[0] && flag_data_written[1] && flag_data_written[2] &&
        flag_data_written[3] && flag_data_written[4] && flag_data_written[5]) {
        ESP_LOGI(TAG, "All configuration data received, attempting to connect to WiFi and MQTT");
        wifi_connect_sta(s_config.wifi_ssid, s_config.wifi_password);
    }
}

static void ble_gap_cb(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
        esp_ble_gap_start_advertising(&s_adv_params);
        break;
    case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
        if (param->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
            ESP_LOGI(TAG, "BLE advertising started");
        } else {
            ESP_LOGE(TAG, "Failed to start advertising, status=0x%x", param->adv_start_cmpl.status);
        }
        break;
    default:
        break;
    }
}

static void ble_gatts_cb(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if,
                         esp_ble_gatts_cb_param_t *param)
{
    switch (event) {
    case ESP_GATTS_REG_EVT:
        s_gatts_if = gatts_if;
        esp_ble_gap_set_device_name(DEVICE_NAME);
        esp_ble_gap_config_adv_data(&s_adv_data);
        esp_ble_gatts_create_attr_tab(s_gatt_db, gatts_if, IDX_NB, GATTS_SERVICE_INSTANCE_ID);
        break;

    case ESP_GATTS_CREAT_ATTR_TAB_EVT:
        if (param->add_attr_tab.status != ESP_GATT_OK) {
            ESP_LOGE(TAG, "Create attribute table failed, status=0x%x", param->add_attr_tab.status);
            break;
        }

        if (param->add_attr_tab.num_handle != IDX_NB) {
            ESP_LOGE(TAG, "Unexpected handle count: %d", param->add_attr_tab.num_handle);
            break;
        }

        memcpy(s_handle_table, param->add_attr_tab.handles, sizeof(s_handle_table));
        esp_ble_gatts_start_service(s_handle_table[IDX_SVC]);
        ESP_LOGI(TAG, "GATT service started");
        break;

    case ESP_GATTS_CONNECT_EVT:
        ESP_LOGI(TAG, "Client connected");
        break;

    case ESP_GATTS_DISCONNECT_EVT:
        ESP_LOGI(TAG, "Client disconnected, restarting advertising");
        esp_ble_gap_start_advertising(&s_adv_params);
        break;

    case ESP_GATTS_WRITE_EVT:
        if (!param->write.is_prep) {
            handle_write_value(param->write.handle, param->write.value, param->write.len);
        }

        if (param->write.need_rsp && s_gatts_if != ESP_GATT_IF_NONE) {
            esp_gatt_rsp_t rsp;
            memset(&rsp, 0, sizeof(rsp));
            rsp.attr_value.handle = param->write.handle;
            rsp.attr_value.len = 0;
            esp_ble_gatts_send_response(s_gatts_if, param->write.conn_id, param->write.trans_id,
                                        ESP_GATT_OK, &rsp);
        }
        break;

    default:
        break;
    }
}

void ble_init(void) {
    if (s_ble_started) {
        ESP_LOGI(TAG, "BLE already initialized");
        return;
    }

    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&bt_cfg));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_BLE));
    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());

    ESP_ERROR_CHECK(esp_ble_gap_register_callback(ble_gap_cb));
    ESP_ERROR_CHECK(esp_ble_gatts_register_callback(ble_gatts_cb));
    ESP_ERROR_CHECK(esp_ble_gatts_app_register(GATTS_APP_ID));

    s_ble_started = true;
    ESP_LOGI(TAG, "BLE init complete");
}

const ble_config_data_t *ble_get_config(void)
{
    return &s_config;
}
