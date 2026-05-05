#ifndef BLE_H
#define BLE_H

/* Maximum payload sizes for configuration written over BLE. */
#define BLE_WIFI_SSID_MAX_LEN        32
#define BLE_WIFI_PASSWORD_MAX_LEN    64
#define BLE_MQTT_BROKER_MAX_LEN      128
#define BLE_MQTT_USERNAME_MAX_LEN    64
#define BLE_MQTT_PASSWORD_MAX_LEN    64
#define BLE_MQTT_SCHEME_MAX_LEN      16

typedef struct {
	char wifi_ssid[BLE_WIFI_SSID_MAX_LEN + 1];
	char wifi_password[BLE_WIFI_PASSWORD_MAX_LEN + 1];
	char mqtt_broker[BLE_MQTT_BROKER_MAX_LEN + 1];
	char mqtt_username[BLE_MQTT_USERNAME_MAX_LEN + 1];
	char mqtt_password[BLE_MQTT_PASSWORD_MAX_LEN + 1];
	char mqtt_scheme[BLE_MQTT_SCHEME_MAX_LEN + 1];
} ble_config_data_t;

extern ble_config_data_t s_config;

void ble_init(void);
const ble_config_data_t *ble_get_config(void);

#endif