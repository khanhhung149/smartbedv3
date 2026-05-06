#include "mqtt-client.h"
#include "nvs-config.h"
#include <WiFi.h>
#include <ArduinoJson.h>

// ESP-IDF MQTT client (built into arduino-esp32 2.x/3.x). Supports tcp / mqtts / ws / wss
// out of the box, with auto-reconnect, last-will, and TLS via the bundled CA store.
#include "mqtt_client.h"
#include "esp_crt_bundle.h"

// arduino-esp32 2.x wraps esp_crt_bundle_attach under this name.
extern "C" esp_err_t arduino_esp_crt_bundle_attach(void* conf);

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

    // ESP-IDF 4.4.x flat struct (arduino-esp32 2.x).
    // ESP-IDF 5.x renamed these to nested broker/credentials/session/network.
    esp_mqtt_client_config_t cfg = {};
    cfg.uri = s_uri.c_str();
    // Mozilla CA bundle — verifies Cloudflare-issued certs for wss://*.sleeptech.me
    // out of the box. No-op for plain `mqtt://` URIs.
    cfg.crt_bundle_attach = arduino_esp_crt_bundle_attach;

    cfg.client_id = s_device_id.c_str();
    if (s_user.length() > 0) {
        cfg.username = s_user.c_str();
        cfg.password = s_pass.c_str();
    }

    cfg.keepalive = 60;
    cfg.lwt_topic = s_topic_status.c_str();
    cfg.lwt_msg   = LWT_OFFLINE;
    cfg.lwt_msg_len = (int)strlen(LWT_OFFLINE);
    cfg.lwt_qos    = 0;
    cfg.lwt_retain = 1;

    cfg.network_timeout_ms     = 5000;
    cfg.reconnect_timeout_ms   = 5000;

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

void mqtt_loop() {
    // No-op: esp-mqtt has its own driver task. Function kept for caller
    // ABI compatibility (main.cpp calls this every loop()).
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

void mqtt_publish_sec(const SleepPadSecData& d) {
    if (!s_connected || !s_client) return;

    JsonDocument doc;
    doc["device_id"]  = s_device_id;
    doc["ts"]         = d.timestamp;
    doc["status"]     = d.status;
    doc["heart_rate"] = d.heart_rate;
    doc["resp_rate"]  = serialized(String(d.resp_rate, 1));
    doc["sdata"]      = d.sdata;
    doc["pdata"]      = d.pdata;

    char buf[JSON_BUF_BYTES];
    size_t n;
    if (!serialize_or_warn(doc, buf, sizeof(buf), n)) return;
    esp_mqtt_client_publish(s_client, s_topic_sec.c_str(), buf, (int)n,
                            /*qos=*/0, /*retain=*/0);
}

void mqtt_publish_min(const SleepPadMinData& d) {
    if (!s_connected || !s_client) return;

    JsonDocument doc;
    doc["device_id"]     = s_device_id;
    doc["ts"]            = d.timestamp;
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

    char buf[JSON_BUF_BYTES];
    size_t n;
    if (!serialize_or_warn(doc, buf, sizeof(buf), n)) return;
    esp_mqtt_client_publish(s_client, s_topic_min.c_str(), buf, (int)n,
                            /*qos=*/0, /*retain=*/0);
}

bool mqtt_connected() {
    return s_connected;
}
