#include "mqtt-client.h"
#include "nvs-config.h"
#include <WiFi.h>
#include <ArduinoJson.h>

// ESP-IDF MQTT client (built into arduino-esp32 2.x/3.x). Supports tcp / mqtts / ws / wss
// out of the box, with auto-reconnect, last-will, and TLS via the bundled CA store.
#include "mqtt_client.h"
#include "esp_crt_bundle.h"

// ISRG Root X1 — Let's Encrypt's RSA root, valid until 2035-06-04.
// We pin this single root cert instead of attaching the Mozilla CA bundle
// (`esp_crt_bundle_attach`) because the bundle attach path is broken on
// arduino-esp32 2.x in some PIO platform versions ("Failed to attach bundle"
// log followed by mbedtls handshake -0x7680). Using a single PEM works on
// every framework version and is safe as long as Cloudflare keeps issuing
// `*.sleeptech.me` certs from Let's Encrypt — verified via:
//   echo | openssl s_client -connect mqtt.sleeptech.me:443 \
//      -showcerts | openssl x509 -issuer -noout
static const char* ISRG_ROOT_X1_PEM =
    "-----BEGIN CERTIFICATE-----\n"
    "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\n"
    "-----END CERTIFICATE-----\n";

// --- Module-level state ---
//
// All config strings are kept in module-scope String/buffers so that the
// `const char*` pointers handed to esp_mqtt_client_config_t stay valid for the
// lifetime of the client (the lib does not deep-copy URI/topics/creds).

static esp_mqtt_client_handle_t s_client = nullptr;
static volatile bool s_connected = false;
static bool s_started = false;

static String s_device_id;
static String s_user;
static String s_pass;
static String s_uri;            // "mqtt://host:1883" or "wss://host/mqtt"
static String s_topic_status;
static String s_topic_sec;
static String s_topic_min;
static String s_topic_cmd;

// LWT payload kept as a literal so we can pass a stable pointer to the lib.
static const char* LWT_OFFLINE = "offline";

// Bound how long mqtt_connect() waits for the driver task to land
// MQTT_EVENT_CONNECTED before returning false. The driver keeps reconnecting
// in the background regardless, so this only gates the boot-time UX.
//
// First connection over WSS = DNS resolve + TLS handshake + MQTT CONNECT.
// Over a slow phone hotspot or first-boot network the route/ARP table is cold
// and the very first TLS connect attempt often surfaces "Host is unreachable"
// before LwIP has established a working path; the driver then waits its
// reconnect_timeout (5 s) before retrying. Two such cycles + handshake easily
// exceeds 20 s. 30 s leaves headroom so BLE provisioning doesn't surface a
// false "mqtt_failed" while the driver is still working in the background.
static constexpr unsigned long CONNECT_WAIT_MS = 30000;

// --- Helpers ---

// Build an esp-mqtt URI from the (scheme, host) pair the backend sends.
// Backend `_mqtt_scheme_from_domain` returns one of: "tcp" | "ws" | "wss".
// Host may already carry a ":port" suffix (e.g. dev: "192.168.1.11:1883").
//
// For `wss` we append `/mqtt` because that's the path mosquitto's WS listener
// is reached at through cloudflared (see mosquitto-prod.conf + tunnel ingress).
static String build_uri(const String& scheme, const String& host) {
    if (scheme == "wss") return String("wss://") + host + "/mqtt";
    if (scheme == "ws")  return String("ws://")  + host + "/mqtt";
    if (scheme == "mqtts") return String("mqtts://") + host;
    // Default: plain TCP. Embed default port if caller did not specify one.
    if (host.indexOf(':') >= 0) return String("mqtt://") + host;
    return String("mqtt://") + host + ":1883";
}

// Handle remote `factory_reset` published to sleeppad/{id}/cmd.
// Backend publishes with retain=true so an offline device receives it on
// next reconnect. After reset we must clear the retained message — otherwise
// a re-paired device with the same ID would reset itself indefinitely.
static void handle_data(esp_mqtt_event_handle_t e) {
    String topic(e->topic, e->topic_len);
    String msg(e->data, e->data_len);
    Serial.printf("[MQTT] cmd received on %s: %s\n", topic.c_str(), msg.c_str());
    if (msg == "factory_reset") {
        Serial.println("[MQTT] factory_reset — clearing retained cmd + wiping NVS");
        esp_mqtt_client_publish(s_client, topic.c_str(), "", 0, /*qos=*/1, /*retain=*/1);
        delay(500);   // give the publish a chance to flush before reset
        nvs_config_erase_all();
        delay(500);
        ESP.restart();
    }
}

static void event_cb(void* /*arg*/, esp_event_base_t /*base*/,
                     int32_t event_id, void* event_data) {
    auto* e = static_cast<esp_mqtt_event_handle_t>(event_data);
    switch (static_cast<esp_mqtt_event_id_t>(event_id)) {
        case MQTT_EVENT_CONNECTED:
            s_connected = true;
            Serial.println("[MQTT] Connected");
            // Replace the retained "offline" LWT with "online" now that we're up.
            esp_mqtt_client_publish(s_client, s_topic_status.c_str(),
                                    "online", 0, /*qos=*/0, /*retain=*/1);
            // QoS 1 so retained factory_reset is delivered across brief reconnects.
            esp_mqtt_client_subscribe(s_client, s_topic_cmd.c_str(), 1);
            Serial.printf("[MQTT] Subscribed to %s\n", s_topic_cmd.c_str());
            break;
        case MQTT_EVENT_DISCONNECTED:
            s_connected = false;
            Serial.println("[MQTT] Disconnected");
            break;
        case MQTT_EVENT_DATA:
            handle_data(e);
            break;
        case MQTT_EVENT_ERROR:
            if (e->error_handle) {
                Serial.printf("[MQTT] Error type=%d tls_err=0x%x sock_errno=%d\n",
                              e->error_handle->error_type,
                              e->error_handle->esp_tls_last_esp_err,
                              e->error_handle->esp_transport_sock_errno);
            } else {
                Serial.println("[MQTT] Error (no detail)");
            }
            break;
        default:
            break;
    }
}

// --- Public API ---

void mqtt_setup(const char* device_id,
                const char* host,
                const char* scheme,
                const char* user,
                const char* pass) {
    s_device_id = String(device_id);
    s_user      = String(user);
    s_pass      = String(pass);

    s_topic_status = "sleeppad/" + s_device_id + "/status";
    s_topic_sec    = "sleeppad/" + s_device_id + "/sec";
    s_topic_min    = "sleeppad/" + s_device_id + "/min";
    s_topic_cmd    = "sleeppad/" + s_device_id + "/cmd";

    s_uri = build_uri(String(scheme), String(host));

    Serial.printf("[MQTT] Setup: uri=%s client_id=%s user=%s\n",
                  s_uri.c_str(), s_device_id.c_str(),
                  s_user.length() > 0 ? s_user.c_str() : "(anonymous)");

    // Tear down any previous client (re-provisioning path calls mqtt_setup again).
    if (s_client) {
        esp_mqtt_client_stop(s_client);
        esp_mqtt_client_destroy(s_client);
        s_client = nullptr;
        s_started = false;
        s_connected = false;
    }

    // ESP-IDF 4.4.x uses a flat config struct (arduino-esp32 2.x).
    // ESP-IDF 5.x renamed these to nested broker/credentials/session/network.
    // Toolchain detection via ESP_IDF_VERSION_MAJOR keeps this source compiling
    // on both arduino-esp32 2.x machines (anh thời's HN setup) and 3.x machines.
    esp_mqtt_client_config_t cfg = {};
#if defined(ESP_IDF_VERSION_MAJOR) && ESP_IDF_VERSION_MAJOR >= 5
    cfg.broker.address.uri = s_uri.c_str();
    cfg.broker.verification.certificate = ISRG_ROOT_X1_PEM;
    cfg.credentials.client_id = s_device_id.c_str();
    if (s_user.length() > 0) {
        cfg.credentials.username = s_user.c_str();
        cfg.credentials.authentication.password = s_pass.c_str();
    }
    cfg.session.keepalive = 60;
    cfg.session.last_will.topic = s_topic_status.c_str();
    cfg.session.last_will.msg = LWT_OFFLINE;
    cfg.session.last_will.msg_len = (int)strlen(LWT_OFFLINE);
    cfg.session.last_will.qos = 0;
    cfg.session.last_will.retain = 1;
    // 5 s was too short over flaky residential WiFi (HoangHanPro/HN) — TLS
    // handshake to Cloudflare 443 routinely timed out (mbedtls 0x8006). 15 s
    // gives slow networks a chance; 10 s reconnect gap avoids hammering the
    // broker if WiFi is bouncing.
    cfg.network.timeout_ms = 15000;
    cfg.network.reconnect_timeout_ms = 10000;
#else
    cfg.uri = s_uri.c_str();
    cfg.cert_pem = ISRG_ROOT_X1_PEM;
    cfg.client_id = s_device_id.c_str();
    if (s_user.length() > 0) {
        cfg.username = s_user.c_str();
        cfg.password = s_pass.c_str();
    }
    cfg.keepalive = 60;
    cfg.lwt_topic = s_topic_status.c_str();
    cfg.lwt_msg = LWT_OFFLINE;
    cfg.lwt_msg_len = (int)strlen(LWT_OFFLINE);
    cfg.lwt_qos = 0;
    cfg.lwt_retain = 1;
    cfg.network_timeout_ms = 15000;       // see ESP-IDF 5.x branch above
    cfg.reconnect_timeout_ms = 10000;
#endif

    s_client = esp_mqtt_client_init(&cfg);
    if (!s_client) {
        Serial.println("[MQTT] esp_mqtt_client_init failed");
        return;
    }
    esp_mqtt_client_register_event(s_client,
                                   static_cast<esp_mqtt_event_id_t>(MQTT_EVENT_ANY),
                                   event_cb, nullptr);
}

bool mqtt_connect() {
    if (!s_client) {
        Serial.println("[MQTT] mqtt_connect called before mqtt_setup");
        return false;
    }
    if (!s_started) {
        if (esp_mqtt_client_start(s_client) != ESP_OK) {
            Serial.println("[MQTT] esp_mqtt_client_start failed");
            return false;
        }
        s_started = true;
    }
    Serial.printf("[MQTT] Connecting to %s as client_id=\"%s\"...\n",
                  s_uri.c_str(), s_device_id.c_str());

    // Block briefly for the driver task to surface MQTT_EVENT_CONNECTED.
    // If we time out, the driver still keeps trying — the BLE provisioning
    // path uses a false return to surface a "mqtt_failed" status to the app.
    unsigned long start = millis();
    while (!s_connected && (millis() - start) < CONNECT_WAIT_MS) {
        delay(100);
    }
    if (!s_connected) {
        Serial.println("[MQTT] Connect wait timed out (driver keeps retrying)");
        return false;
    }
    return true;
}

// --- Publish helpers ---

static constexpr size_t JSON_BUF_BYTES = 384;

static bool serialize_or_warn(JsonDocument& doc, char* buf, size_t cap, size_t& out_n) {
    out_n = serializeJson(doc, buf, cap);
    if (out_n == 0 || out_n >= cap - 1) {
        Serial.printf("[MQTT] JSON serialize overflow (n=%u cap=%u) — dropping publish\n",
                      (unsigned)out_n, (unsigned)cap);
        return false;
    }
    return true;
}

// --- Ring buffer chống mất mẫu (yêu cầu framework Phase 01) ---
//
// MQTT chưa nối/bận → mẫu KHÔNG bị drop im lặng: xếp vào vòng đệm rồi đẩy lại khi thông.
// Pad là master đẩy 1Hz (0x85) + 1/min (0x86) nên 64 ô = hơn 1 phút đệm, dư sức cho một
// lần mất kết nối ngắn. Đầy thì bỏ CŨ nhất (giữ mẫu mới — dữ liệu gần hiện tại quan trọng hơn).
#define PUB_RB_CAP 64
#define PUB_RB_TOPIC 64
#define PUB_RB_PAYLOAD (JSON_BUF_BYTES)

struct PendingMsg {
    char   topic[PUB_RB_TOPIC];
    char   payload[PUB_RB_PAYLOAD];
    size_t len;
};

static PendingMsg s_pending[PUB_RB_CAP];
static int        s_pending_head = 0;   // ô ghi kế tiếp
static int        s_pending_count = 0;

static bool pending_full() { return s_pending_count == PUB_RB_CAP; }

// Đẩy 1 mẩu tin vào hàng đợi. Đầy thì đẩy head (bỏ cũ nhất) rồi ghi vào cuối.
static void pending_push(const char* topic, const char* payload, size_t len) {
    if (len >= PUB_RB_PAYLOAD) len = PUB_RB_PAYLOAD - 1;
    if (pending_full()) {
        s_pending_head = (s_pending_head + 1) % PUB_RB_CAP;
        s_pending_count--;
    }
    const int idx = (s_pending_head + s_pending_count) % PUB_RB_CAP;
    strncpy(s_pending[idx].topic, topic, PUB_RB_TOPIC - 1);
    s_pending[idx].topic[PUB_RB_TOPIC - 1] = '\0';
    memcpy(s_pending[idx].payload, payload, len);
    s_pending[idx].payload[len] = '\0';
    s_pending[idx].len = len;
    s_pending_count++;
}

// Đẩy hết hàng đợi ra broker khi đã nối. Rớt kết nối giữa chừng → dừng, mẫu còn lại giữ cho lần sau.
static void pending_drain() {
    while (s_pending_count > 0 && s_connected && s_client) {
        const PendingMsg& m = s_pending[s_pending_head];
        esp_mqtt_client_publish(s_client, m.topic, m.payload, (int)m.len, /*qos=*/0, /*retain=*/0);
        s_pending_head = (s_pending_head + 1) % PUB_RB_CAP;
        s_pending_count--;
    }
}

void mqtt_loop() {
    // Đẩy mẫu tồn đọng khi MQTT đã thông (esp-mqtt chạy task riêng; publish là không-block).
    pending_drain();
}

void mqtt_publish_sec(const SleepPadSecData& d) {
    if (!s_client) return;

    JsonDocument doc;
    doc["device_id"]  = s_device_id;
    // ts = epoch giây do chính MCU gắn (NTP sync lúc boot) — timestamp tại thiết bị, không phải
    // ở Linux. Pad tự đẩy 1Hz (master) nên firmware KHÔNG tự sinh nhịp; ts_pad là mốc pad báo.
    doc["ts"]         = (int64_t)time(nullptr);
    doc["ts_pad"]     = d.timestamp;
    doc["status"]     = d.status;
    doc["heart_rate"] = d.heart_rate;   // 0 = sensor dropout (pad báo) — đánh dấu lỗi tường minh
    doc["resp_rate"]  = serialized(String(d.resp_rate, 1));
    doc["sdata"]      = d.sdata;
    doc["pdata"]      = d.pdata;
    // Cờ lỗi: uart_ok = nhận được khung hợp lệ từ pad; heartbeat mất sẽ tự dừng callback.
    doc["uart_ok"]    = true;

    char buf[JSON_BUF_BYTES];
    size_t n;
    if (!serialize_or_warn(doc, buf, sizeof(buf), n)) return;
    pending_push(s_topic_sec.c_str(), buf, n);
}

void mqtt_publish_min(const SleepPadMinData& d) {
    if (!s_client) return;

    JsonDocument doc;
    doc["device_id"]     = s_device_id;
    doc["ts"]            = (int64_t)time(nullptr);
    doc["ts_pad"]        = d.timestamp;
    doc["status"]        = d.status;
    doc["heart_rate"]    = d.heart_rate;
    doc["resp_rate"]     = serialized(String(d.resp_rate, 1));
    doc["movement"]      = d.movement;
    doc["snore_count"]   = d.snore_count;
    doc["resp_disorder"] = d.resp_disorder;
    doc["pthd"]          = d.pthd;
    // Protocol stores temp as °C × 10; publish actual °C so backend Pydantic
    // bound (le=60) accepts and the app displays readable numbers.
    doc["temp"]          = serialized(String(d.temp / 10.0, 1));
    doc["uart_ok"]       = true;

    char buf[JSON_BUF_BYTES];
    size_t n;
    if (!serialize_or_warn(doc, buf, sizeof(buf), n)) return;
    pending_push(s_topic_min.c_str(), buf, n);
}

bool mqtt_connected() {
    return s_connected;
}
