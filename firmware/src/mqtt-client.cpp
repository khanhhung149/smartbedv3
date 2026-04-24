#include "mqtt-client.h"
#include "nvs-config.h"
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// --- Module-level state ---

static WiFiClient     s_wifi_client;
static PubSubClient   s_mqtt(s_wifi_client);

static String s_device_id;
static String s_host;
static uint16_t s_port     = 1883;
static String s_user;
static String s_pass;
static bool   s_scheme_ok  = false; // false → ws/wss not supported, abort

static String s_topic_status;
static String s_topic_sec;
static String s_topic_min;
static String s_topic_cmd;

static unsigned long s_last_reconnect_ms = 0;
static constexpr unsigned long RECONNECT_INTERVAL_MS = 5000;

// --- Helper: parse "host[:port]" into host + port ---

static void parse_host_port(const String& raw, String& out_host, uint16_t& out_port) {
    int colon = raw.lastIndexOf(':');
    if (colon > 0) {
        // Ensure there is something after the colon and it looks numeric
        String port_str = raw.substring(colon + 1);
        if (port_str.length() > 0 && isDigit(port_str[0])) {
            out_host = raw.substring(0, colon);
            out_port = (uint16_t)port_str.toInt();
            return;
        }
    }
    out_host = raw;
    // out_port unchanged (caller initialises to default)
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

    String scheme_str(scheme);
    if (scheme_str != "tcp") {
        // WS/WSS not supported by PubSubClient — deferred to production firmware
        Serial.printf("[MQTT] Scheme \"%s\" not supported in POC (TCP only). "
                      "WS/WSS via PubSubClient requires a WebSocket bridge — deferred.\n",
                      scheme);
        s_scheme_ok = false;
        return;
    }
    s_scheme_ok = true;

    // Default TCP port; overridden if host contains ":port"
    s_port = 1883;
    parse_host_port(String(host), s_host, s_port);

    Serial.printf("[MQTT] Setup: broker=%s:%u client_id=%s user=%s\n",
                  s_host.c_str(), s_port, s_device_id.c_str(),
                  s_user.length() > 0 ? s_user.c_str() : "(anonymous)");

    s_mqtt.setServer(s_host.c_str(), s_port);
    s_mqtt.setKeepAlive(60);
    s_mqtt.setBufferSize(512);
    // Bound the blocking connect()/publish() worst-case wait so an unreachable
    // broker doesn't stall the main loop (and therefore UART draining) for the
    // default 15 s. With 2 s, UART buffer survives comfortably at 115200 baud.
    s_mqtt.setSocketTimeout(2);

    // Subscribe handler: listen for remote factory_reset on `sleeppad/{id}/cmd`.
    // Backend publishes with retain=true so an offline device still receives
    // the reset on next reconnect.
    s_mqtt.setCallback([](char* topic, uint8_t* payload, unsigned int len) {
        String msg;
        msg.reserve(len);
        for (unsigned int i = 0; i < len; ++i) msg += (char)payload[i];
        Serial.printf("[MQTT] cmd received on %s: %s\n", topic, msg.c_str());
        if (msg == "factory_reset") {
            Serial.println("[MQTT] factory_reset — clearing retained cmd + wiping NVS");
            // CRITICAL: clear the retained command on the broker so the next
            // owner who re-pairs this device_id doesn't immediately receive
            // the old factory_reset and bounce into an infinite reset loop.
            s_mqtt.publish(topic, (const uint8_t*)"", 0, /*retain=*/true);
            s_mqtt.loop();          // flush outgoing queue
            delay(200);
            nvs_config_erase_all();
            delay(500);
            ESP.restart();
        }
    });
}

bool mqtt_connect() {
    if (!s_scheme_ok) {
        Serial.println("[MQTT] Cannot connect — unsupported scheme (ws/wss deferred)");
        return false;
    }

    Serial.printf("[MQTT] Connecting to %s:%u as client_id=\"%s\"...\n",
                  s_host.c_str(), s_port, s_device_id.c_str());

    // LWT: retain=true, QoS=0
    const char* lwt_payload = "offline";
    bool ok;
    if (s_user.length() > 0) {
        ok = s_mqtt.connect(s_device_id.c_str(),
                            s_user.c_str(), s_pass.c_str(),
                            s_topic_status.c_str(), 0, true, lwt_payload);
    } else {
        // Anonymous connect (dev environment)
        ok = s_mqtt.connect(s_device_id.c_str(),
                            nullptr, nullptr,
                            s_topic_status.c_str(), 0, true, lwt_payload);
    }

    if (ok) {
        Serial.println("[MQTT] Connected");
        s_mqtt.publish(s_topic_status.c_str(), "online", /*retain=*/true);
        // Subscribe to command topic.  QoS 1 so retained factory_reset is
        // delivered even across brief reconnects.
        s_mqtt.subscribe(s_topic_cmd.c_str(), 1);
        Serial.printf("[MQTT] Subscribed to %s\n", s_topic_cmd.c_str());
    } else {
        Serial.printf("[MQTT] Connect failed, state=%d\n", s_mqtt.state());
    }
    return ok;
}

void mqtt_loop() {
    if (!s_scheme_ok) return;

    if (!s_mqtt.connected()) {
        unsigned long now = millis();
        if (now - s_last_reconnect_ms >= RECONNECT_INTERVAL_MS) {
            s_last_reconnect_ms = now;
            Serial.println("[MQTT] Disconnected — attempting reconnect");
            mqtt_connect();
        }
    }
    s_mqtt.loop();
}

// JSON buffer sized for min frames with headroom. Sec frame ~110 B, min frame
// ~170 B — 384 leaves >2x margin and trips the overflow guard early.
static constexpr size_t JSON_BUF_BYTES = 384;

static bool serialize_or_warn(JsonDocument& doc, char* buf, size_t cap, size_t& out_n) {
    out_n = serializeJson(doc, buf, cap);
    // serializeJson returns 0 if the buffer was too small. Also bail if we
    // used the full capacity (truncation risk) so we never publish half a JSON.
    if (out_n == 0 || out_n >= cap - 1) {
        Serial.printf("[MQTT] JSON serialize overflow (n=%u cap=%u) — dropping publish\n",
                      (unsigned)out_n, (unsigned)cap);
        return false;
    }
    return true;
}

void mqtt_publish_sec(const SleepPadSecData& d) {
    if (!s_mqtt.connected()) return;

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
    s_mqtt.publish(s_topic_sec.c_str(), (const uint8_t*)buf, n, /*retain=*/false);
}

void mqtt_publish_min(const SleepPadMinData& d) {
    if (!s_mqtt.connected()) return;

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
    // Protocol stores temp as C × 10; publish actual °C so backend Pydantic
    // bound (le=60) accepts and the app displays readable numbers.
    doc["temp"]          = serialized(String(d.temp / 10.0, 1));

    char buf[JSON_BUF_BYTES];
    size_t n;
    if (!serialize_or_warn(doc, buf, sizeof(buf), n)) return;
    s_mqtt.publish(s_topic_min.c_str(), (const uint8_t*)buf, n, /*retain=*/false);
}

bool mqtt_connected() {
    return s_mqtt.connected();
}
