#include <Arduino.h>
#include <WiFi.h>
#include "config.h"
#include "nvs-config.h"
#include "ble-provisioning.h"
#include "mqtt-client.h"
#include "uart-parser.h"

#ifdef MOCK_SLEEPPAD
#include "mock-sleeppad.h"
// Mock build forwards synthetic frame bytes into the real parser so the state
// machine is still exercised end-to-end — nothing is bypassed except the UART.
static SleepPadParser* g_mock_parser = nullptr;
static void mock_feed_parser(uint8_t b) { g_mock_parser->feed(b); }
#endif

// Device ID — hardcoded at flash time (10 ASCII chars from sleep pad protocol).
// MQTT client_id MUST equal this value — Mosquitto ACL enforces
// pattern write sleeppad/%c/# so a mismatch causes silent publish drops.
static const char* DEVICE_ID = "CNU2000001";

static SleepPadParser parser;
static unsigned long  last_heartbeat_ms = 0;

// --- Sleep pad UART command helpers ---

// Format: [0x7D][type][len_lo][len_hi][ID 10B][content...][0x0D]
static void send_command(uint8_t frame_type, const uint8_t* content, size_t len) {
    Serial1.write(0x7D);
    Serial1.write(frame_type);
    uint16_t total = 1 + 1 + 2 + 10 + len + 1;
    Serial1.write((uint8_t)(total & 0xFF));
    Serial1.write((uint8_t)((total >> 8) & 0xFF));
    Serial1.write((const uint8_t*)DEVICE_ID, 10);
    if (len > 0) Serial1.write(content, len);
    Serial1.write(0x0D);
    Serial1.flush();
}

static void start_monitor_mode() {
    Serial.println("[CMD] 0x04 — start server monitor mode");
    uint8_t mode = 0x20;
    send_command(0x04, &mode, 1);
}

static void send_heartbeat() {
    send_command(0x08, nullptr, 0);
}

// --- Parser callbacks (forward declarations) ---

static void on_sec_data(const SleepPadSecData& d) {
    Serial.printf("[0x85] ts=%u status=%u hr=%u rr=%.1f sdata=%u pdata=%u\n",
                  d.timestamp, d.status, d.heart_rate, d.resp_rate, d.sdata, d.pdata);
    mqtt_publish_sec(d);
}

static void on_min_data(const SleepPadMinData& d) {
    Serial.printf("[0x86] ts=%u status=%u hr=%u rr=%.1f mov=%u snore=%u temp=%.1fC\n",
                  d.timestamp, d.status, d.heart_rate, d.resp_rate,
                  d.movement, d.snore_count, d.temp / 10.0);
    mqtt_publish_min(d);
}

static void on_idle() {
    // 0x87 frame: device entered standby, requesting commands — restart monitor mode
    Serial.println("[UART] 0x87 idle — restarting monitor mode");
    start_monitor_mode();
}

// --- WiFi connect (blocking, 30 s timeout) ---

static String normalize_ble_text(String s) {
    s.trim();
    // Some mobile BLE clients may send quoted JSON-like strings.
    if (s.length() >= 2 && s[0] == '"' && s[s.length() - 1] == '"') {
        s = s.substring(1, s.length() - 1);
    }
    return s;
}

static void dump_wifi_scan_for(const String& expected_ssid) {
    Serial.println("\n[WiFi] Scanning nearby APs...");
    int n = WiFi.scanNetworks(/*async=*/false, /*show_hidden=*/true);
    if (n <= 0) {
        Serial.println("[WiFi] Scan result: no AP found");
        return;
    }
    bool found_exact = false;
    for (int i = 0; i < n; ++i) {
        String s = WiFi.SSID(i);
        int32_t rssi = WiFi.RSSI(i);
        uint8_t ch = WiFi.channel(i);
        Serial.printf("[WiFi] AP[%d] SSID=\"%s\" RSSI=%d CH=%u ENC=%d\n",
                      i, s.c_str(), (int)rssi, (unsigned)ch, (int)WiFi.encryptionType(i));
        if (s == expected_ssid) found_exact = true;
    }
    Serial.printf("[WiFi] Target SSID %s in scan list\n", found_exact ? "FOUND" : "NOT FOUND");
}

static bool connect_wifi(const String& ssid, const String& pass) {
    String clean_ssid = normalize_ble_text(ssid);
    String clean_pass = normalize_ble_text(pass);

    Serial.printf("[WiFi] Connecting to \"%s\" (len=%u)...\n",
                  clean_ssid.c_str(), (unsigned)clean_ssid.length());
    if (clean_ssid.length() > 0) {
        char last = clean_ssid[clean_ssid.length() - 1];
        Serial.printf("[WiFi] SSID last-char=0x%02X\n", (unsigned char)last);
    }

    WiFi.mode(WIFI_STA);
    WiFi.begin(clean_ssid.c_str(), clean_pass.c_str());

    const unsigned long timeout_ms = 60000;
    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - start >= timeout_ms) {
            wl_status_t st = WiFi.status();
            Serial.printf("[WiFi] Timeout, status=%d\n", (int)st);
            dump_wifi_scan_for(clean_ssid);
            return false;
        }
        delay(500);
        Serial.print('.');
    }
    Serial.printf("\n[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
    return true;
}

// --- BLE provisioning flow (blocks until provisioning complete) ---

static void run_ble_provisioning() {
    Serial.printf("[BLE] Init — free heap before: %u\n", ESP.getFreeHeap());
    ble_init(DEVICE_ID);
    ble_set_status("waiting");

    Serial.println("[Boot] Waiting for BLE provisioning...");
    while (!ble_provisioning_complete()) {
        delay(100);
    }
    // Status already set to "connecting" by ble-provisioning.cpp on last write
}

// --- Arduino entry points ---

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.printf("\n[Boot] Sleep Pad ESP32 — device_id=%s\n", DEVICE_ID);    Serial.printf("[Boot] Free heap: %u bytes\n", ESP.getFreeHeap());
    // UART1 for sleep pad hardware
    Serial.println("[Boot] Starting Serial1...");
    Serial.flush();
    Serial1.begin(UART_BAUD, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);
    Serial.printf("[UART] Serial1 RX=%d TX=%d @ %d baud\n",
                  UART_RX_PIN, UART_TX_PIN, UART_BAUD);
    Serial.flush();

    parser.onSecData = on_sec_data;
    parser.onMinData = on_min_data;
    parser.onIdle    = on_idle;

    Serial.println("[Boot] NVS init...");
    Serial.flush();
    if (!nvs_init()) {
        Serial.println("[Boot] NVS init failed — continuing anyway");
    }

    Serial.println("[Boot] NVS load...");
    Serial.flush();
    NvsConfig cfg = nvs_load();
    const bool fresh_provisioning = !cfg.has_wifi_creds();
    Serial.printf("[Boot] fresh_provisioning=%d\n", fresh_provisioning);
    Serial.flush();

    if (fresh_provisioning) {
        // ── Provisioning path with in-place retry ─────────────────────────
        // BLE stays alive for the whole attempt→fail→retry→success loop.
        // Trigger to retry: app rewrites SSID + PASSWORD chars (plus the
        // others — firmware waits for all 6 again via ble_reset_pending_writes).
        // Cancel: client disconnects BLE → erase NVS + restart so next boot
        // re-enters provisioning mode.
        Serial.println("[Boot] No WiFi credentials — starting BLE provisioning");
        run_ble_provisioning();

        while (true) {
            if (ble_user_cancelled()) {
                Serial.println("[Boot] User cancelled during provisioning");
                nvs_config_erase_all();
                delay(500);
                ESP.restart();
            }

            cfg = nvs_load();

            // Step 1: WiFi
            ble_set_status("wifi_connecting");
            if (!connect_wifi(cfg.wifi_ssid, cfg.wifi_pass)) {
                ble_set_status("wifi_failed");
                ble_reset_pending_writes();
                Serial.println("[Boot] WiFi failed — awaiting new credentials from app");
                // Block until the app rewrites creds or user cancels.
                while (!ble_provisioning_complete() && !ble_user_cancelled()) {
                    delay(200);
                }
                continue;   // retry from top (cancel caught at loop head)
            }
            ble_set_status("wifi_connected");

            // Step 2: MQTT
            ble_set_status("mqtt_connecting");
            mqtt_setup(DEVICE_ID,
                       cfg.mqtt_host.c_str(),
                       cfg.mqtt_scheme.c_str(),
                       cfg.mqtt_user.c_str(),
                       cfg.mqtt_pass.c_str());
            if (!mqtt_connect()) {
                ble_set_status("mqtt_failed");
                WiFi.disconnect(true);    // release STA before retry
                ble_reset_pending_writes();
                Serial.println("[Boot] MQTT failed — awaiting new credentials from app");
                while (!ble_provisioning_complete() && !ble_user_cancelled()) {
                    delay(200);
                }
                continue;
            }

            // Step 3: Success — notify, let client observe, then stop BLE
            ble_set_status("connected");
            delay(2000);
            ble_stop();
            break;
        }
    } else {
        // ── Normal boot path (creds already persisted) ────────────────────
        Serial.println("[Boot] WiFi credentials found — skipping BLE");
        ble_stop();                    // no BLE init happened, but call is idempotent
        if (!connect_wifi(cfg.wifi_ssid, cfg.wifi_pass)) {
            Serial.println("[Boot] WiFi failed on normal boot — erasing + restart");
            nvs_config_erase_all();
            delay(1000);
            ESP.restart();
        }
        mqtt_setup(DEVICE_ID,
                   cfg.mqtt_host.c_str(),
                   cfg.mqtt_scheme.c_str(),
                   cfg.mqtt_user.c_str(),
                   cfg.mqtt_pass.c_str());
        if (!mqtt_connect()) {
            Serial.println("[Boot] MQTT failed on normal boot — will retry in loop()");
            // Non-fatal: mqtt_loop() handles reconnect.
        }
    }

    // Enter sleep pad monitor mode so it streams data.
    // In mock build, Serial1 is unused so this is a no-op on the wire, but
    // leaving it in keeps the boot sequence identical to production.
    start_monitor_mode();

#ifdef MOCK_SLEEPPAD
    g_mock_parser = &parser;
    mock_init(DEVICE_ID);
    Serial.println("[Mock] SLEEP PAD MOCK ACTIVE — synthesizing telemetry, Serial1 bypassed");
#endif

    Serial.println("[Boot] Ready");
}

void loop() {
#ifndef MOCK_SLEEPPAD
    // Drain UART bytes into parser (production path)
    while (Serial1.available()) {
        parser.feed(static_cast<uint8_t>(Serial1.read()));
    }
#else
    // Mock path — generate synthetic frame bytes and feed the parser
    mock_tick(mock_feed_parser);
#endif

    // PubSubClient state machine + auto-reconnect
    mqtt_loop();

    // 0x08 heartbeat every 60 s (device restarts WiFi stack if silent for >5 min)
    unsigned long now = millis();
    if (now - last_heartbeat_ms >= 60000UL) {
        last_heartbeat_ms = now;
        send_heartbeat();
    }

    delay(1); // yield to FreeRTOS / WiFi stack
}
