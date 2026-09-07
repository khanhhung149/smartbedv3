#include "ble-provisioning.h"
#include "nvs-config.h"
#include <string.h>
#include <stdio.h>
#include "esp_log.h"
#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_gatt_common_api.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char* TAG = "ble-provisioning";

// --- UUIDs (from docs/protocols/ble-provisioning-and-mqtt-auth.md) — GIỮ NGUYÊN,
// contract app Flutter. Bluedroid lưu UUID 128-bit little-endian (đảo byte so với
// chuỗi hex viết big-endian thông thường) — xem plan 260824-1109 phần đối chiếu.
#define UUID128(FIRST_BYTE) \
    { FIRST_BYTE, 0x26, 0x1b, 0x36, 0x07, 0xea, 0xf5, 0xb7, \
      0x88, 0x46, 0xe1, 0x36, 0x3e, 0x48, 0xb5, 0xbe }

static const uint8_t SVC_UUID128[16] = {
    0x4b, 0x91, 0x31, 0xc3, 0xc9, 0xc5, 0xcc, 0x8f,
    0x9e, 0x45, 0xb5, 0x1f, 0x01, 0xc2, 0xaf, 0x4f
};
static const uint8_t UUID_SSID[16]          = UUID128(0xa8);
static const uint8_t UUID_PASSWORD[16]      = UUID128(0xa9);
static const uint8_t UUID_SERVER_HOST[16]   = UUID128(0xaa);
static const uint8_t UUID_STATUS[16]        = UUID128(0xab);
static const uint8_t UUID_MQTT_USER[16]     = UUID128(0xac);
static const uint8_t UUID_MQTT_PASSWORD[16] = UUID128(0xad);
static const uint8_t UUID_MQTT_SCHEME[16]   = UUID128(0xae);
static const uint8_t UUID_DEVICE_ID[16]     = UUID128(0xaf);

// 6 WRITE (WiFi + MQTT creds) + Status (READ/NOTIFY) + DeviceId (READ) = 8 characteristics.
#define NUM_WRITE_CHARS 6
#define NUM_CHARS       8
#define IDX_STATUS      6
#define IDX_DEVICE_ID   7

typedef struct {
    const uint8_t*  uuid128;
    esp_gatt_perm_t perm;
    esp_gatt_char_prop_t prop;
    bool            needs_cccd;
    uint16_t        handle;
    uint16_t        cccd_handle;
} CharDef;

static CharDef s_chars[NUM_CHARS] = {
    { UUID_SSID,          ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE, false, 0, 0 },
    { UUID_PASSWORD,      ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE, false, 0, 0 },
    { UUID_SERVER_HOST,   ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE, false, 0, 0 },
    { UUID_MQTT_USER,     ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE, false, 0, 0 },
    { UUID_MQTT_PASSWORD, ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE, false, 0, 0 },
    { UUID_MQTT_SCHEME,   ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE, false, 0, 0 },
    { UUID_STATUS,        ESP_GATT_PERM_READ,
      ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_NOTIFY, true, 0, 0 },
    { UUID_DEVICE_ID,     ESP_GATT_PERM_READ,  ESP_GATT_CHAR_PROP_BIT_READ, false, 0, 0 },
};

// NVS key mỗi WRITE characteristic ghi vào — cùng thứ tự s_chars[0..5].
static const char* s_write_keys[NUM_WRITE_CHARS] = {
    NVS_KEY_SSID, NVS_KEY_PASS, NVS_KEY_HOST, NVS_KEY_USER, NVS_KEY_MPASS, NVS_KEY_SCHEME,
};
// mqtt_user / mqtt_pass được phép rỗng (broker dev anonymous). Bốn cái còn lại rỗng thì
// coi như "chưa ghi" — chặn provisioning giả với SSID/host trống.
static const bool s_write_allow_empty[NUM_WRITE_CHARS] = {
    false, false, false, true, true, false,
};
static volatile bool s_write_received[NUM_WRITE_CHARS];

#define APP_ID 0

static esp_gatt_if_t s_gatts_if      = ESP_GATT_IF_NONE;
static uint16_t      s_conn_id       = 0xFFFF;
static bool           s_connected_client = false;
static uint16_t      s_service_handle = 0;
static int            s_add_idx       = 0;

static char s_device_id[11];
static char s_adv_name[24];
static char s_status_value[24] = "waiting";
static bool s_status_notify_enabled = false;

// `volatile` — ghi từ task sự kiện BLE (Bluedroid), đọc (poll) từ task main.cpp.
static volatile bool s_prov_done   = false;
static volatile bool s_user_cancel = false;

static bool all_received(void) {
    for (int i = 0; i < NUM_WRITE_CHARS; i++) {
        if (!s_write_received[i]) return false;
    }
    return true;
}

static void add_next_char(void) {
    if (s_add_idx >= NUM_CHARS) {
        ESP_LOGI(TAG, "All characteristics registered");
        return;
    }
    CharDef* c = &s_chars[s_add_idx];
    esp_bt_uuid_t uuid = { .len = ESP_UUID_LEN_128 };
    memcpy(uuid.uuid.uuid128, c->uuid128, 16);

    esp_attr_value_t val = {0};
    uint8_t init_val[24];
    if (s_add_idx == IDX_STATUS) {
        val.attr_max_len = sizeof(s_status_value);
        val.attr_len = (uint16_t)strlen(s_status_value);
        val.attr_value = (uint8_t*)s_status_value;
    } else if (s_add_idx == IDX_DEVICE_ID) {
        val.attr_max_len = sizeof(init_val);
        val.attr_len = (uint16_t)strlen(s_device_id);
        memcpy(init_val, s_device_id, val.attr_len);
        val.attr_value = init_val;
    } else {
        val.attr_max_len = NVS_STR_CAP;
        val.attr_len = 0;
        val.attr_value = NULL;
    }

    esp_err_t err = esp_ble_gatts_add_char(s_service_handle, &uuid, c->perm, c->prop, &val, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "add_char[%d] failed: %s", s_add_idx, esp_err_to_name(err));
    }
}

static void start_advertising(void) {
    static esp_ble_adv_params_t adv_params = {
        .adv_int_min       = 0x20,
        .adv_int_max       = 0x40,
        .adv_type          = ADV_TYPE_IND,
        .own_addr_type     = BLE_ADDR_TYPE_PUBLIC,
        .channel_map       = ADV_CHNL_ALL,
        .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
    };
    esp_ble_gap_start_advertising(&adv_params);
}

static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t* param) {
    switch (event) {
        case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
            start_advertising();
            break;
        case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
            if (param->adv_start_cmpl.status != ESP_BT_STATUS_SUCCESS) {
                ESP_LOGE(TAG, "Advertising start failed");
            } else {
                ESP_LOGI(TAG, "Advertising started — waiting for provisioning");
            }
            break;
        default:
            break;
    }
}

static void gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if,
                                esp_ble_gatts_cb_param_t* param) {
    switch (event) {
        case ESP_GATTS_REG_EVT: {
            s_gatts_if = gatts_if;
            esp_ble_gap_set_device_name(s_adv_name);

            esp_ble_adv_data_t adv_data = {
                .set_scan_rsp        = false,
                .include_name        = true,
                .include_txpower     = false,
                .min_interval        = 0x06,
                .max_interval        = 0x12,
                .appearance          = 0x00,
                .manufacturer_len    = 0,
                .p_manufacturer_data = NULL,
                .service_data_len    = 0,
                .p_service_data      = NULL,
                .service_uuid_len    = sizeof(SVC_UUID128),
                .p_service_uuid      = (uint8_t*)SVC_UUID128,
                .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
            };
            esp_ble_gap_config_adv_data(&adv_data);

            esp_gatt_srvc_id_t service_id = {
                .is_primary = true,
                .id.inst_id = 0,
                .id.uuid.len = ESP_UUID_LEN_128,
            };
            memcpy(service_id.id.uuid.uuid.uuid128, SVC_UUID128, 16);
            // Handle budget: 8 char × 2 (decl+value) + 1 CCCD (Status) + 1 service decl = 18.
            esp_ble_gatts_create_service(gatts_if, &service_id, 24);
            break;
        }
        case ESP_GATTS_CREATE_EVT:
            s_service_handle = param->create.service_handle;
            esp_ble_gatts_start_service(s_service_handle);
            s_add_idx = 0;
            add_next_char();
            break;

        case ESP_GATTS_ADD_CHAR_EVT: {
            if (param->add_char.status != ESP_GATT_OK) {
                ESP_LOGE(TAG, "add_char failed idx=%d status=%d", s_add_idx, param->add_char.status);
                break;
            }
            s_chars[s_add_idx].handle = param->add_char.attr_handle;
            if (s_chars[s_add_idx].needs_cccd) {
                esp_bt_uuid_t cccd_uuid = {
                    .len = ESP_UUID_LEN_16,
                    .uuid.uuid16 = ESP_GATT_UUID_CHAR_CLIENT_CONFIG,
                };
                esp_ble_gatts_add_char_descr(s_service_handle, &cccd_uuid,
                    ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE, NULL, NULL);
            } else {
                s_add_idx++;
                add_next_char();
            }
            break;
        }

        case ESP_GATTS_ADD_CHAR_DESCR_EVT:
            s_chars[s_add_idx].cccd_handle = param->add_char_descr.attr_handle;
            s_add_idx++;
            add_next_char();
            break;

        case ESP_GATTS_CONNECT_EVT:
            s_conn_id = param->connect.conn_id;
            s_connected_client = true;
            ESP_LOGI(TAG, "Client connected");
            break;

        case ESP_GATTS_DISCONNECT_EVT:
            s_connected_client = false;
            ESP_LOGI(TAG, "Client disconnected");
            if (!s_prov_done) {
                // Disconnect before provisioning completed — just re-advertise.
                start_advertising();
            } else {
                // Disconnect after initial writes — main retry loop treats as user cancel.
                s_user_cancel = true;
                ESP_LOGI(TAG, "Treating disconnect as user cancel");
            }
            break;

        case ESP_GATTS_READ_EVT: {
            esp_gatt_rsp_t rsp = {0};
            rsp.attr_value.handle = param->read.handle;
            if (param->read.handle == s_chars[IDX_STATUS].handle) {
                rsp.attr_value.len = (uint16_t)strlen(s_status_value);
                memcpy(rsp.attr_value.value, s_status_value, rsp.attr_value.len);
            } else if (param->read.handle == s_chars[IDX_DEVICE_ID].handle) {
                rsp.attr_value.len = (uint16_t)strlen(s_device_id);
                memcpy(rsp.attr_value.value, s_device_id, rsp.attr_value.len);
            }
            esp_ble_gatts_send_response(gatts_if, param->read.conn_id, param->read.trans_id,
                                        ESP_GATT_OK, &rsp);
            break;
        }

        case ESP_GATTS_WRITE_EVT: {
            const uint16_t handle = param->write.handle;

            // CCCD write cho Status characteristic (bật/tắt notify).
            if (handle == s_chars[IDX_STATUS].cccd_handle) {
                if (param->write.len == 2) {
                    uint16_t v = param->write.value[0] | (param->write.value[1] << 8);
                    s_status_notify_enabled = (v == 0x0001);
                }
                if (param->write.need_rsp) {
                    esp_ble_gatts_send_response(gatts_if, param->write.conn_id,
                        param->write.trans_id, ESP_GATT_OK, NULL);
                }
                break;
            }

            // Ghi vào 1 trong 6 WRITE characteristic (WiFi/MQTT creds).
            int idx = -1;
            for (int i = 0; i < NUM_WRITE_CHARS; i++) {
                if (handle == s_chars[i].handle) { idx = i; break; }
            }
            if (idx >= 0) {
                char val[NVS_STR_CAP];
                size_t len = param->write.len;
                if (len >= sizeof(val)) len = sizeof(val) - 1;
                memcpy(val, param->write.value, len);
                val[len] = '\0';

                if (len == 0 && !s_write_allow_empty[idx]) {
                    ESP_LOGW(TAG, "Ignoring empty write for %s", s_write_keys[idx]);
                } else {
                    ESP_LOGI(TAG, "Received %s = \"%s\"", s_write_keys[idx], val);
                    nvs_set(s_write_keys[idx], val);
                    s_write_received[idx] = true;

                    if (all_received() && !s_prov_done) {
                        s_prov_done = true;
                        ESP_LOGI(TAG, "All characteristics received — provisioning complete");
                        ble_set_status("connecting");
                    }
                }
            }

            if (param->write.need_rsp) {
                esp_ble_gatts_send_response(gatts_if, param->write.conn_id,
                    param->write.trans_id, ESP_GATT_OK, NULL);
            }
            break;
        }

        default:
            break;
    }
}

// --- Public API ---

void ble_init(const char* device_id) {
    snprintf(s_device_id, sizeof(s_device_id), "%s", device_id);

    // Advertisement name from last 6 chars of device_id.
    size_t idlen = strlen(device_id);
    const char* tail = idlen >= 6 ? device_id + (idlen - 6) : device_id;
    snprintf(s_adv_name, sizeof(s_adv_name), "SleepPad-%s", tail);

    ESP_LOGI(TAG, "Initialising — advertising as \"%s\"", s_adv_name);

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    esp_bt_controller_init(&bt_cfg);
    esp_bt_controller_enable(ESP_BT_MODE_BLE);
    esp_bluedroid_init();
    esp_bluedroid_enable();

    esp_ble_gap_register_callback(gap_event_handler);
    esp_ble_gatts_register_callback(gatts_event_handler);
    esp_ble_gatts_app_register(APP_ID);
    esp_ble_gatt_set_local_mtu(200);

    memset((void*)s_write_received, 0, sizeof(s_write_received));
    s_prov_done = false;
    s_user_cancel = false;
    snprintf(s_status_value, sizeof(s_status_value), "waiting");
}

void ble_set_status(const char* status) {
    snprintf(s_status_value, sizeof(s_status_value), "%s", status);
    ESP_LOGI(TAG, "Status -> %s", status);
    if (s_gatts_if == ESP_GATT_IF_NONE || s_chars[IDX_STATUS].handle == 0) return;
    if (s_connected_client && s_status_notify_enabled) {
        esp_ble_gatts_send_indicate(s_gatts_if, s_conn_id, s_chars[IDX_STATUS].handle,
            (uint16_t)strlen(s_status_value), (uint8_t*)s_status_value, false);
    }
}

void ble_stop(void) {
    // Idempotent — safe to call when BLE was never initialised (e.g. NVS already has WiFi
    // credentials and provisioning was skipped). Without this guard, deinit on an
    // uninitialised stack fails/crashes on reboot.
    if (s_gatts_if == ESP_GATT_IF_NONE) return;

    ESP_LOGI(TAG, "Stopping BLE stack");
    esp_ble_gap_stop_advertising();
    esp_bluedroid_disable();
    esp_bluedroid_deinit();
    esp_bt_controller_disable();
    esp_bt_controller_deinit();

    s_gatts_if = ESP_GATT_IF_NONE;
    // Xoá handle cũ để nếu ble_init() được gọi lại (không xảy ra trong flow hiện tại,
    // nhưng an toàn nếu sau này thêm retry-provisioning-sau-connected) không đọc rác.
    for (int i = 0; i < NUM_CHARS; i++) { s_chars[i].handle = 0; s_chars[i].cccd_handle = 0; }
    s_connected_client = false;
    s_service_handle = 0;
}

bool ble_provisioning_complete(void) {
    return s_prov_done;
}

void ble_reset_pending_writes(void) {
    // Clear per-char flags + overall flag so main retry loop waits for a fresh
    // SSID/PASSWORD write from the app. NVS values stay intact — overwritten on next write.
    memset((void*)s_write_received, 0, sizeof(s_write_received));
    s_prov_done = false;
    ESP_LOGI(TAG, "Pending writes reset — awaiting new credentials");
}

bool ble_user_cancelled(void) {
    return s_user_cancel;
}
