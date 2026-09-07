// Sleep Pad ESP32-C3 Super Mini — ESP-IDF thuần (framework = espidf, xem plan
// 260824-1109-dong-bo-sleep-pad-node-esp-idf/plan.md).
//
// Trình tự boot GIỮ NGUYÊN bản Arduino cũ: NVS -> (BLE provisioning nếu chưa có creds)
// -> WiFi -> SNTP -> MQTT -> vào chế độ giám sát pad -> vòng chính 10Hz.
//
// SỬA BUG PROTOCOL (lý do chính của lần port này — xác nhận thật trên board 4 lần
// 24/08): bản cũ gửi [0x04][0x20] rồi CHỦ ĐỘNG hỏi [0x07] và chờ [0x87] làm ACK trong
// 15s — pad KHÔNG bao giờ trả lời kiểu request/reply đó, timeout luôn cháy, rơi lại
// TAOSG. Đối chiếu state machine thật ở Sleep-Tech-AI/sleep-pad-ai: họ không hỏi 0x07,
// chỉ gửi [0x04][0x20] một lần lúc boot, heartbeat [0x08] mỗi 60s giữ pad sống, và khi
// nhận [0x87] (pad TỰ PHÁT báo idle, không phải reply) thì gửi lại [0x04][0x20]. Toàn bộ
// cơ chế [0x07]/chờ ACK/timeout 15s/fallback TAOSG đã BỎ HẲN trong bản này.

#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_sntp.h"
#include "esp_event.h"
#include "esp_wifi.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "driver/uart.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "config.h"
#include "nvs-config.h"
#if __has_include("dev-config.h")
#include "dev-config.h"
#endif
#include "ble-provisioning.h"
#include "mqtt-client.h"
#include "uart-parser.h"
#include "sleep-pad-frame.h"

#ifdef MOCK_SLEEPPAD
#include "mock-sleeppad.h"
// Mock build forwards synthetic frame bytes into the real parser so the state
// machine is still exercised end-to-end — nothing is bypassed except the UART.
static SleepPadParser* g_mock_parser = NULL;
static void mock_feed_parser(uint8_t b) { sleeppad_parser_feed(g_mock_parser, b); }
#endif

static const char* TAG = "main";

// Device ID — derived per-chip at boot from the ESP32 eFuse MAC.
// Format: "CNU" + 7 hex chars uppercase (10 ASCII total) so the Legact V2 UART
// protocol's fixed-width device_id field still fits. Sleep pad hardware does
// not validate this field (passthrough tag), so any unique 10-char ASCII works.
//
// MQTT client_id MUST equal this value — Mosquitto ACL enforces
// pattern write sleeppad/%c/# so a mismatch causes silent publish drops.
static char DEVICE_ID[11];

static void derive_device_id(void) {
    uint8_t mac[6];
    esp_efuse_mac_get_default(mac);
    uint32_t low28 = ((uint32_t)mac[3] << 24 | (uint32_t)mac[4] << 16 | (uint32_t)mac[5] << 8 |
                       (uint32_t)mac[2]) & 0xFFFFFFFUL;
    snprintf(DEVICE_ID, sizeof(DEVICE_ID), "CNU%07lX", (unsigned long)low28);
}

static SleepPadParser parser;
static uint32_t last_heartbeat_ms = 0;
static bool     monitor_mode_active = false;

static uint32_t millis(void) {
    return (uint32_t)(esp_timer_get_time() / 1000);
}

// --- Sleep pad UART command helpers ---

// --- State machine giám sát mới (thay hẳn 0x07/ACK/TAOSG fallback) ---

static void send_time_sync_0x0B(void) {
    time_t now = time(NULL);
    uint32_t t = (uint32_t)now;
    uint8_t content[4] = {
        (uint8_t)(t & 0xFF), (uint8_t)((t >> 8) & 0xFF),
        (uint8_t)((t >> 16) & 0xFF), (uint8_t)((t >> 24) & 0xFF),
    };
    sp_send_frame(0x0B, content, 4);
    ESP_LOGI(TAG, "[Mode] Da gui 0x0B hieu chinh dong ho");
}

// Gửi [0x04][0x20] MỘT LẦN lúc boot để vào chế độ giám sát — KHÔNG chờ ACK (pad không
// trả lời kiểu request/reply, xem lời giải ở đầu file).
static void enter_monitor_mode(void) {
    uint8_t content = 0x20;
    sp_send_frame(0x04, &content, 1);
    monitor_mode_active = true;
    last_heartbeat_ms = millis();
    ESP_LOGI(TAG, "[Mode] Da gui 0x04 0x20 vao che do giam sat (khong cho ACK)");
}

// Heartbeat [0x08] mỗi 60s giữ pad sống — không phải request/reply, chỉ là tín hiệu
// "còn kết nối" theo đúng state machine tham khảo Sleep-Tech-AI/sleep-pad-ai.
static void send_heartbeat(void) {
    sp_send_frame(0x08, NULL, 0);
    ESP_LOGD(TAG, "[Mode] Heartbeat 0x08");
}

// --- Parser callbacks ---

static void on_sec_data(const SleepPadSecData* d) {
    ESP_LOGI(TAG, "[0x85/TAOSG] ts=%u status=%u hr=%u rr=%.1f sdata=%u pdata=%u",
             (unsigned)d->timestamp, d->status, d->heart_rate, d->resp_rate, d->sdata, d->pdata);
    mqtt_publish_sec(d);
}

static void on_min_data(const SleepPadMinData* d) {
    ESP_LOGI(TAG, "[0x86] ts=%u status=%u hr=%u rr=%.1f mov=%u snore=%u temp=%.1fC",
             (unsigned)d->timestamp, d->status, d->heart_rate, d->resp_rate,
             d->movement, d->snore_count, d->temp / 10.0);
    mqtt_publish_min(d);
}

static void on_mode_confirmed(uint8_t mode) {
    if (mode == 0x20 || mode == 0x21) {
        ESP_LOGI(TAG, "[Mode] 0x20 monitoring - OK (mode 0x%02X)", mode);
        send_time_sync_0x0B();
    } else {
        ESP_LOGW(TAG, "[Mode] pad bao loi (mode 0x%02X)", mode);
    }
}

// Khung [0x87] — pad TỰ PHÁT báo idle/trạng thái (async, KHÔNG phải reply cho lệnh
// [0x07] — cơ chế 0x07 đã bỏ hẳn). Nhận khung này thì gửi lại [0x04][0x20].
static void on_status_query(uint8_t mode) {
    ESP_LOGI(TAG, "[Mode] Pad tu phat 0x87 (mode bao cao=0x%02X) — gui lai 0x04 0x20", mode);
    uint8_t content = 0x20;
    sp_send_frame(0x04, &content, 1);
    last_heartbeat_ms = millis();
}

// --- SNTP time sync ---
//
// TLS cert validity check (mbedtls) so notBefore/notAfter với đồng hồ hệ thống. ESP32
// boot ở epoch 1970, nên lần TLS handshake đầu với cert 2024+ sẽ bị từ chối (lỗi PK
// verify — thực chất do "cert chưa hợp lệ theo ngày"). Phải SNTP-sync trước MQTT connect.
static bool sync_time(uint32_t timeout_ms) {
    ESP_LOGI(TAG, "[Time] SNTP sync...");
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    esp_netif_sntp_init(&cfg);
    esp_sntp_setservername(1, "time.cloudflare.com");
    esp_sntp_setservername(2, "time.google.com");

    uint32_t start = millis();
    time_t now = 0;
    while (millis() - start < timeout_ms) {
        now = time(NULL);
        if (now > 1700000000) {   // > 2023-11-14 → real time set
            ESP_LOGI(TAG, "[Time] Synced: %ld", (long)now);
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(200));
    }
    ESP_LOGW(TAG, "[Time] Timeout (current=%ld) - TLS may reject certs", (long)now);
    return false;
}

// --- WiFi connect (blocking, ≤ 2 attempts × 20 s) ---

static volatile bool s_wifi_got_ip = false;

static void on_wifi_event(void* arg, esp_event_base_t base, int32_t id, void* data) {
    (void)arg; (void)base; (void)data;
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        s_wifi_got_ip = false;
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        s_wifi_got_ip = true;
    }
}

static bool s_wifi_stack_started = false;

static void wifi_stack_init_once(void) {
    if (s_wifi_stack_started) return;
    esp_netif_init();
    esp_event_loop_create_default();
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    esp_wifi_init(&init);
    esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL);
    esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_wifi_event, NULL);
    esp_wifi_set_mode(WIFI_MODE_STA);
    // Tắt power save — modem ngủ giữa các beacon làm mất beacon trên link yếu (C3 Super
    // Mini dùng ăng-ten gốm trên bo), hỏng ARP/TCP. Node này cắm nguồn liên tục, không có
    // lý do tiết kiệm điện. Xem lý do gốc trong bản Arduino cũ.
    esp_wifi_set_ps(WIFI_PS_NONE);
    esp_wifi_start();
    s_wifi_stack_started = true;
}

static bool wifi_connect_once(const char* ssid, const char* pass, uint32_t timeout_ms) {
    s_wifi_got_ip = false;
    esp_wifi_disconnect();
    vTaskDelay(pdMS_TO_TICKS(200));

    wifi_config_t cfg = {0};
    strncpy((char*)cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid) - 1);
    strncpy((char*)cfg.sta.password, pass, sizeof(cfg.sta.password) - 1);
    esp_wifi_set_config(WIFI_IF_STA, &cfg);
    esp_wifi_connect();

    uint32_t start = millis();
    while (!s_wifi_got_ip) {
        if (millis() - start >= timeout_ms) return false;
        vTaskDelay(pdMS_TO_TICKS(500));
    }
    return true;
}

static bool connect_wifi(const char* ssid, const char* pass) {
    wifi_stack_init_once();
    ESP_LOGI(TAG, "[WiFi] Connecting to \"%s\"...", ssid);
    if (wifi_connect_once(ssid, pass, 20000)) {
        esp_netif_ip_info_t ip;
        esp_netif_get_ip_info(esp_netif_get_handle_from_ifkey("WIFI_STA_DEF"), &ip);
        ESP_LOGI(TAG, "[WiFi] Connected - IP: " IPSTR, IP2STR(&ip.ip));
        return true;
    }
    ESP_LOGW(TAG, "[WiFi] First attempt failed - retrying once");
    if (wifi_connect_once(ssid, pass, 20000)) {
        ESP_LOGI(TAG, "[WiFi] Connected on retry");
        return true;
    }
    ESP_LOGE(TAG, "[WiFi] Both attempts failed - giving up");
    return false;
}

// --- BLE provisioning flow (blocks until provisioning complete) ---

static void run_ble_provisioning(void) {
    ble_init(DEVICE_ID);
    ble_set_status("waiting");

    ESP_LOGI(TAG, "[Boot] Waiting for BLE provisioning...");
    while (!ble_provisioning_complete()) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void app_main(void) {
    derive_device_id();
    ESP_LOGI(TAG, "[Boot] Sleep Pad ESP32-C3 - device_id=%s", DEVICE_ID);

    // UART cho sleep pad hardware
    uart_config_t uart_cfg = {
        .baud_rate = UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    uart_param_config(SLEEPPAD_UART_NUM, &uart_cfg);
    uart_set_pin(SLEEPPAD_UART_NUM, UART_TX_PIN, UART_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    uart_driver_install(SLEEPPAD_UART_NUM, 1024, 1024, 0, NULL, 0);
    ESP_LOGI(TAG, "[UART] SLEEPPAD_UART RX=%d TX=%d @ %d baud", UART_RX_PIN, UART_TX_PIN, UART_BAUD);

    sleeppad_parser_init(&parser);
    parser.onSecData       = on_sec_data;
    parser.onMinData       = on_min_data;
    parser.onModeConfirmed = on_mode_confirmed;
    parser.onStatusQuery   = on_status_query;

    if (!nvs_init()) {
        ESP_LOGW(TAG, "[Boot] NVS init failed - continuing anyway");
    }

    NvsConfig cfg = nvs_load();

    // Cấu hình dựng sẵn lúc biên dịch (include/dev-config.h): có file thì node bỏ qua BLE
    // provisioning và dùng thẳng giá trị trong file. Điều kiện là "khác NVS", KHÔNG phải
    // "NVS trống" — xem lý do trong bản Arduino cũ (bẫy: board đã ghép mạng cũ lờ đi file
    // này mãi mãi nếu chỉ kiểm tra NVS trống).
#if __has_include("dev-config.h")
    if (strcmp(cfg.wifi_ssid, DEV_WIFI_SSID) != 0 || strcmp(cfg.wifi_pass, DEV_WIFI_PASS) != 0 ||
        strcmp(cfg.mqtt_host, DEV_MQTT_HOST) != 0 || strcmp(cfg.mqtt_scheme, DEV_MQTT_SCHEME) != 0 ||
        strcmp(cfg.mqtt_user, DEV_MQTT_USER) != 0 || strcmp(cfg.mqtt_pass, DEV_MQTT_PASS) != 0) {
        snprintf(cfg.wifi_ssid,   sizeof(cfg.wifi_ssid),   "%s", DEV_WIFI_SSID);
        snprintf(cfg.wifi_pass,   sizeof(cfg.wifi_pass),   "%s", DEV_WIFI_PASS);
        snprintf(cfg.mqtt_host,   sizeof(cfg.mqtt_host),   "%s", DEV_MQTT_HOST);
        snprintf(cfg.mqtt_scheme, sizeof(cfg.mqtt_scheme), "%s", DEV_MQTT_SCHEME);
        snprintf(cfg.mqtt_user,   sizeof(cfg.mqtt_user),   "%s", DEV_MQTT_USER);
        snprintf(cfg.mqtt_pass,   sizeof(cfg.mqtt_pass),   "%s", DEV_MQTT_PASS);
        nvs_set(NVS_KEY_SSID,   cfg.wifi_ssid);
        nvs_set(NVS_KEY_PASS,   cfg.wifi_pass);
        nvs_set(NVS_KEY_HOST,   cfg.mqtt_host);
        nvs_set(NVS_KEY_SCHEME, cfg.mqtt_scheme);
        nvs_set(NVS_KEY_USER,   cfg.mqtt_user);
        nvs_set(NVS_KEY_MPASS,  cfg.mqtt_pass);
        ESP_LOGI(TAG, "[Boot] Nap cau hinh dung san tu dev-config.h - ssid=\"%s\" broker=%s://%s",
                 cfg.wifi_ssid, cfg.mqtt_scheme, cfg.mqtt_host);
    }
#endif

    const bool fresh_provisioning = !nvs_config_has_wifi_creds(&cfg);

    if (fresh_provisioning) {
        ESP_LOGI(TAG, "[Boot] No WiFi credentials - starting BLE provisioning");
        run_ble_provisioning();

        while (true) {
            if (ble_user_cancelled()) {
                ESP_LOGW(TAG, "[Boot] User cancelled during provisioning");
                nvs_config_erase_all();
                vTaskDelay(pdMS_TO_TICKS(500));
                esp_restart();
            }

            cfg = nvs_load();

            ble_set_status("wifi_connecting");
            if (!connect_wifi(cfg.wifi_ssid, cfg.wifi_pass)) {
                ble_set_status("wifi_failed");
                ble_reset_pending_writes();
                ESP_LOGW(TAG, "[Boot] WiFi failed - awaiting new credentials from app");
                while (!ble_provisioning_complete() && !ble_user_cancelled()) {
                    vTaskDelay(pdMS_TO_TICKS(200));
                }
                continue;
            }
            ble_set_status("wifi_connected");

            sync_time(10000);

            ble_set_status("mqtt_connecting");
            mqtt_setup(DEVICE_ID, cfg.mqtt_host, cfg.mqtt_scheme, cfg.mqtt_user, cfg.mqtt_pass);
            if (!mqtt_connect()) {
                ble_set_status("mqtt_failed");
                esp_wifi_disconnect();
                ble_reset_pending_writes();
                ESP_LOGW(TAG, "[Boot] MQTT failed - awaiting new credentials from app");
                while (!ble_provisioning_complete() && !ble_user_cancelled()) {
                    vTaskDelay(pdMS_TO_TICKS(200));
                }
                continue;
            }

            ble_set_status("connected");
            vTaskDelay(pdMS_TO_TICKS(2000));
            ble_stop();
            break;
        }
    } else {
        ESP_LOGI(TAG, "[Boot] WiFi credentials found - skipping BLE");
        if (!connect_wifi(cfg.wifi_ssid, cfg.wifi_pass)) {
            ESP_LOGE(TAG, "[Boot] WiFi failed on normal boot - erasing + restart");
            nvs_config_erase_all();
            vTaskDelay(pdMS_TO_TICKS(1000));
            esp_restart();
        }
        sync_time(10000);
        mqtt_setup(DEVICE_ID, cfg.mqtt_host, cfg.mqtt_scheme, cfg.mqtt_user, cfg.mqtt_pass);
        if (!mqtt_connect()) {
            ESP_LOGW(TAG, "[Boot] MQTT failed on normal boot - will retry in loop");
        }
    }

    // Vào chế độ giám sát pad — bug fix chính của lần port này (xem lời giải đầu file).
    enter_monitor_mode();

#ifdef MOCK_SLEEPPAD
    g_mock_parser = &parser;
    mock_init(DEVICE_ID);
    ESP_LOGI(TAG, "[Mock] SLEEP PAD MOCK ACTIVE - synthesizing telemetry, UART bypassed");
#endif

    ESP_LOGI(TAG, "[Boot] Ready");

    // ── Vòng lặp chính 10Hz cố định, không jitter ──
    uint32_t last_tick_ms = 0;
    uint32_t next_tick_ms = 0;
    while (true) {
        const uint32_t now = millis();

        if (now - last_tick_ms >= 100UL) {
            last_tick_ms = now;
            next_tick_ms = now + 100UL;

#ifndef MOCK_SLEEPPAD
            uint8_t rx_buf[128];
            int n = uart_read_bytes(SLEEPPAD_UART_NUM, rx_buf, sizeof(rx_buf), 0);
            for (int i = 0; i < n; i++) {
                sleeppad_parser_feed_taos(&parser, rx_buf[i]);   // đường LSM-800-T (tag [Bdata])
                sleeppad_parser_feed(&parser, rx_buf[i]);        // đường khung 0x7D
            }
#else
            mock_tick(mock_feed_parser);
#endif

            mqtt_loop();   // đẩy mẫu tồn đọng ra broker khi MQTT thông (ring buffer)

            // Heartbeat 0x08 mỗi 60s giữ pad sống — KHÔNG còn timeout 15s / fallback TAOSG.
            if (monitor_mode_active && now - last_heartbeat_ms >= 60000UL) {
                last_heartbeat_ms = now;
                send_heartbeat();
            }
        }

        if (millis() < next_tick_ms) {
            vTaskDelay(pdMS_TO_TICKS(next_tick_ms - millis()));
        } else {
            vTaskDelay(1);
        }
    }
}
