#include "mqtt-client.h"
#include "nvs-config.h"
#include <string.h>
#include <stdio.h>
#include <time.h>
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mqtt_client.h"

static const char* TAG = "mqtt-client";

// ISRG Root X1 — Let's Encrypt's RSA root, valid until 2035-06-04. Ghim đúng 1 root thay
// vì gắn cả bundle Mozilla (esp_crt_bundle_attach) — xem lý do gốc trong bản Arduino cũ:
// bundle attach từng gãy trên vài bản platform ("Failed to attach bundle" rồi mbedtls
// -0x7680). Một PEM chạy ổn định trên mọi bản framework, an toàn miễn Cloudflare còn
// cấp cert *.sleeptech.me từ Let's Encrypt.
static const char* ISRG_ROOT_X1_PEM =
    "-----BEGIN CERTIFICATE-----\n"
    "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\n"
    "-----END CERTIFICATE-----\n";

// --- Module-level state ---
//
// Chuỗi cấu hình giữ trong buffer tĩnh module-scope để con trỏ const char* trao cho
// esp_mqtt_client_config_t sống hết vòng đời client (lib không deep-copy uri/topic/creds).

static esp_mqtt_client_handle_t s_client = NULL;
static volatile bool s_connected = false;
static bool s_started = false;

static char s_device_id[NVS_STR_CAP];
static char s_user[NVS_STR_CAP];
static char s_pass[NVS_STR_CAP];
static char s_uri[NVS_STR_CAP + 16];
static char s_topic_status[64];
static char s_topic_sec[64];
static char s_topic_min[64];
static char s_topic_cmd[64];

static const char* LWT_OFFLINE = "offline";

// Bound how long mqtt_connect() waits for the driver task to land MQTT_EVENT_CONNECTED
// before returning false. 30s: đủ cho lần TLS handshake đầu tiên qua mạng chậm (xem
// lý do gốc trong bản Arduino cũ) — driver vẫn tự retry nền dù hàm này timeout.
static const uint32_t CONNECT_WAIT_MS = 30000;

// --- Helpers ---

// Build an esp-mqtt URI from the (scheme, host) pair the backend sends.
// scheme: "tcp" | "ws" | "wss" | "mqtts". host may already carry ":port".
static void build_uri(char* out, size_t cap, const char* scheme, const char* host) {
    if (strcmp(scheme, "wss") == 0) {
        snprintf(out, cap, "wss://%s/mqtt", host);
    } else if (strcmp(scheme, "ws") == 0) {
        snprintf(out, cap, "ws://%s/mqtt", host);
    } else if (strcmp(scheme, "mqtts") == 0) {
        snprintf(out, cap, "mqtts://%s", host);
    } else if (strchr(host, ':') != NULL) {
        snprintf(out, cap, "mqtt://%s", host);
    } else {
        snprintf(out, cap, "mqtt://%s:1883", host);
    }
}

// Handle remote `factory_reset` published to sleeppad/{id}/cmd.
static void handle_data(esp_mqtt_event_handle_t e) {
    ESP_LOGI(TAG, "cmd received on %.*s: %.*s", e->topic_len, e->topic, e->data_len, e->data);
    if (e->data_len == (int)strlen("factory_reset") &&
        strncmp(e->data, "factory_reset", e->data_len) == 0) {
        ESP_LOGW(TAG, "factory_reset — clearing retained cmd + wiping NVS");
        char topic[64];
        snprintf(topic, sizeof(topic), "%.*s", e->topic_len, e->topic);
        esp_mqtt_client_publish(s_client, topic, "", 0, /*qos=*/1, /*retain=*/1);
        vTaskDelay(pdMS_TO_TICKS(500));   // give the publish a chance to flush before reset
        nvs_config_erase_all();
        vTaskDelay(pdMS_TO_TICKS(500));
        esp_restart();
    }
}

static void event_cb(void* arg, esp_event_base_t base, int32_t event_id, void* event_data) {
    (void)arg; (void)base;
    esp_mqtt_event_handle_t e = (esp_mqtt_event_handle_t)event_data;
    switch ((esp_mqtt_event_id_t)event_id) {
        case MQTT_EVENT_CONNECTED:
            s_connected = true;
            ESP_LOGI(TAG, "Connected");
            esp_mqtt_client_publish(s_client, s_topic_status, "online", 0, /*qos=*/0, /*retain=*/1);
            esp_mqtt_client_subscribe(s_client, s_topic_cmd, 1);
            ESP_LOGI(TAG, "Subscribed to %s", s_topic_cmd);
            break;
        case MQTT_EVENT_DISCONNECTED:
            s_connected = false;
            ESP_LOGW(TAG, "Disconnected");
            break;
        case MQTT_EVENT_DATA:
            handle_data(e);
            break;
        case MQTT_EVENT_ERROR:
            if (e->error_handle) {
                ESP_LOGE(TAG, "Error type=%d tls_err=0x%x sock_errno=%d",
                         e->error_handle->error_type,
                         e->error_handle->esp_tls_last_esp_err,
                         e->error_handle->esp_transport_sock_errno);
            } else {
                ESP_LOGE(TAG, "Error (no detail)");
            }
            break;
        default:
            break;
    }
}

// --- Public API ---

void mqtt_setup(const char* device_id, const char* host, const char* scheme,
                const char* user, const char* pass) {
    snprintf(s_device_id, sizeof(s_device_id), "%s", device_id);
    snprintf(s_user, sizeof(s_user), "%s", user);
    snprintf(s_pass, sizeof(s_pass), "%s", pass);

    snprintf(s_topic_status, sizeof(s_topic_status), "sleeppad/%s/status", s_device_id);
    snprintf(s_topic_sec,    sizeof(s_topic_sec),    "sleeppad/%s/sec",    s_device_id);
    snprintf(s_topic_min,    sizeof(s_topic_min),    "sleeppad/%s/min",    s_device_id);
    snprintf(s_topic_cmd,    sizeof(s_topic_cmd),    "sleeppad/%s/cmd",    s_device_id);

    build_uri(s_uri, sizeof(s_uri), scheme, host);

    ESP_LOGI(TAG, "Setup: uri=%s client_id=%s user=%s",
             s_uri, s_device_id, s_user[0] ? s_user : "(anonymous)");

    // Tear down any previous client (re-provisioning path calls mqtt_setup again).
    if (s_client) {
        esp_mqtt_client_stop(s_client);
        esp_mqtt_client_destroy(s_client);
        s_client = NULL;
        s_started = false;
        s_connected = false;
    }

    // Chỉ gắn chứng chỉ khi transport THẬT SỰ là TLS — esp_mqtt_client_init trả NULL nếu
    // có certificate trên URI mqtt:// hoặc ws:// (broker LAN thuần tcp thì không dựng nổi
    // client dù URI hợp lệ).
    const bool tls = strncmp(s_uri, "wss://", 6) == 0 || strncmp(s_uri, "mqtts://", 8) == 0;

    esp_mqtt_client_config_t cfg = {0};
    cfg.broker.address.uri = s_uri;
    if (tls) cfg.broker.verification.certificate = ISRG_ROOT_X1_PEM;
    cfg.credentials.client_id = s_device_id;
    if (s_user[0] != '\0') {
        cfg.credentials.username = s_user;
        cfg.credentials.authentication.password = s_pass;
    }
    cfg.session.keepalive = 60;
    cfg.session.last_will.topic = s_topic_status;
    cfg.session.last_will.msg = LWT_OFFLINE;
    cfg.session.last_will.msg_len = (int)strlen(LWT_OFFLINE);
    cfg.session.last_will.qos = 0;
    cfg.session.last_will.retain = 1;
    // 15s handshake timeout / 10s reconnect gap — xem lý do gốc (mạng dân dụng chậm) trong
    // bản Arduino cũ.
    cfg.network.timeout_ms = 15000;
    cfg.network.reconnect_timeout_ms = 10000;

    s_client = esp_mqtt_client_init(&cfg);
    if (!s_client) {
        ESP_LOGE(TAG, "esp_mqtt_client_init failed");
        return;
    }
    esp_mqtt_client_register_event(s_client, ESP_EVENT_ANY_ID, event_cb, NULL);
}

bool mqtt_connect(void) {
    if (!s_client) {
        ESP_LOGE(TAG, "mqtt_connect called before mqtt_setup");
        return false;
    }
    if (!s_started) {
        if (esp_mqtt_client_start(s_client) != ESP_OK) {
            ESP_LOGE(TAG, "esp_mqtt_client_start failed");
            return false;
        }
        s_started = true;
    }
    ESP_LOGI(TAG, "Connecting to %s as client_id=\"%s\"...", s_uri, s_device_id);

    uint32_t waited = 0;
    while (!s_connected && waited < CONNECT_WAIT_MS) {
        vTaskDelay(pdMS_TO_TICKS(100));
        waited += 100;
    }
    if (!s_connected) {
        ESP_LOGW(TAG, "Connect wait timed out (driver keeps retrying)");
        return false;
    }
    return true;
}

// --- Publish helpers ---

#define JSON_BUF_BYTES 384

// --- Ring buffer chống mất mẫu (yêu cầu framework Phase 01) ---
//
// MQTT chưa nối/bận → mẫu KHÔNG bị drop im lặng: xếp vào vòng đệm rồi đẩy lại khi thông.
// Pad là master đẩy 1Hz (0x85) + 1/min (0x86) nên 64 ô = hơn 1 phút đệm. Đầy thì bỏ CŨ
// nhất (giữ mẫu mới — dữ liệu gần hiện tại quan trọng hơn).
#define PUB_RB_CAP 64
#define PUB_RB_TOPIC 64
#define PUB_RB_PAYLOAD (JSON_BUF_BYTES)

typedef struct {
    char   topic[PUB_RB_TOPIC];
    char   payload[PUB_RB_PAYLOAD];
    size_t len;
} PendingMsg;

static PendingMsg s_pending[PUB_RB_CAP];
static int        s_pending_head = 0;
static int        s_pending_count = 0;

static bool pending_full(void) { return s_pending_count == PUB_RB_CAP; }

static void pending_push(const char* topic, const char* payload, size_t len) {
    if (len >= PUB_RB_PAYLOAD) len = PUB_RB_PAYLOAD - 1;
    if (pending_full()) {
        s_pending_head = (s_pending_head + 1) % PUB_RB_CAP;
        s_pending_count--;
    }
    const int idx = (s_pending_head + s_pending_count) % PUB_RB_CAP;
    snprintf(s_pending[idx].topic, PUB_RB_TOPIC, "%s", topic);
    memcpy(s_pending[idx].payload, payload, len);
    s_pending[idx].payload[len] = '\0';
    s_pending[idx].len = len;
    s_pending_count++;
}

static void pending_drain(void) {
    while (s_pending_count > 0 && s_connected && s_client) {
        const PendingMsg* m = &s_pending[s_pending_head];
        const int rc = esp_mqtt_client_publish(s_client, m->topic, m->payload, (int)m->len, 0, 0);
        if (rc < 0) {
            ESP_LOGW(TAG, "publish loi rc=%d topic=%s len=%u", rc, m->topic, (unsigned)m->len);
        }
        s_pending_head = (s_pending_head + 1) % PUB_RB_CAP;
        s_pending_count--;
    }
}

void mqtt_loop(void) {
    pending_drain();
}

void mqtt_publish_sec(const SleepPadSecData* d) {
    if (!s_client) return;

    char buf[JSON_BUF_BYTES];
    int n = snprintf(buf, sizeof(buf),
        "{\"device_id\":\"%s\",\"ts\":%lld,\"ts_pad\":%u,\"status\":%u,"
        "\"heart_rate\":%u,\"resp_rate\":%.1f,\"sdata\":%u,\"pdata\":%u,\"uart_ok\":true}",
        s_device_id, (long long)time(NULL), (unsigned)d->timestamp, (unsigned)d->status,
        (unsigned)d->heart_rate, d->resp_rate, (unsigned)d->sdata, (unsigned)d->pdata);
    if (n <= 0 || (size_t)n >= sizeof(buf)) {
        ESP_LOGW(TAG, "JSON serialize overflow (sec) — dropping publish");
        return;
    }
    pending_push(s_topic_sec, buf, (size_t)n);
}

void mqtt_publish_min(const SleepPadMinData* d) {
    if (!s_client) return;

    char buf[JSON_BUF_BYTES];
    int n = snprintf(buf, sizeof(buf),
        "{\"device_id\":\"%s\",\"ts\":%lld,\"ts_pad\":%u,\"status\":%u,"
        "\"heart_rate\":%u,\"resp_rate\":%.1f,\"movement\":%u,\"snore_count\":%u,"
        "\"resp_disorder\":%u,\"pthd\":%u,\"temp\":%.1f,\"uart_ok\":true}",
        s_device_id, (long long)time(NULL), (unsigned)d->timestamp, (unsigned)d->status,
        (unsigned)d->heart_rate, d->resp_rate, (unsigned)d->movement, (unsigned)d->snore_count,
        (unsigned)d->resp_disorder, (unsigned)d->pthd, d->temp / 10.0);
    if (n <= 0 || (size_t)n >= sizeof(buf)) {
        ESP_LOGW(TAG, "JSON serialize overflow (min) — dropping publish");
        return;
    }
    pending_push(s_topic_min, buf, (size_t)n);
}

bool mqtt_connected(void) {
    return s_connected;
}
