#include <Arduino.h>
#include <WiFi.h>
#include "config.h"
#include "nvs-config.h"
#if __has_include("dev-config.h")
#include "dev-config.h"
#endif
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

// Device ID — derived per-chip at boot from the ESP32 eFuse MAC.
// Format: "CNU" + 7 hex chars uppercase (10 ASCII total) so the Legact V2 UART
// protocol's fixed-width device_id field still fits. Sleep pad hardware does
// not validate this field (passthrough tag — see protocol PDF §1 + §2.5), so
// any unique 10-char ASCII works.
//
// MQTT client_id MUST equal this value — Mosquitto ACL enforces
// pattern write sleeppad/%c/# so a mismatch causes silent publish drops.
static char DEVICE_ID[11];

static void derive_device_id() {
    uint64_t mac = ESP.getEfuseMac();
    // Lower 28 bits of MAC → 7 hex chars. 256M-id space; birthday-50%
    // at ~16K chips. Sufficient for sleep-pad consumer scale; if product
    // ever exceeds ~100K units, switch to base32 of full MAC hash.
    snprintf(DEVICE_ID, sizeof(DEVICE_ID), "CNU%07llX",
             (unsigned long long)(mac & 0xFFFFFFFULL));
}

static SleepPadParser parser;
static unsigned long  last_heartbeat_ms = 0;

// --- Sleep pad UART command helpers ---

// Format: [0x7D][type][len_lo][len_hi][ID 10B][content...][0x0D]
static void send_command(uint8_t frame_type, const uint8_t* content, size_t len) {
    SLEEPPAD_UART.write(0x7D);
    SLEEPPAD_UART.write(frame_type);
    uint16_t total = 1 + 1 + 2 + 10 + len + 1;
    SLEEPPAD_UART.write((uint8_t)(total & 0xFF));
    SLEEPPAD_UART.write((uint8_t)((total >> 8) & 0xFF));
    SLEEPPAD_UART.write((const uint8_t*)DEVICE_ID, 10);
    if (len > 0) SLEEPPAD_UART.write(content, len);
    SLEEPPAD_UART.write(0x0D);
    SLEEPPAD_UART.flush();
}

// LSM-800-T nhận lệnh ASCII, KHÔNG phải khung 0x7D. Tài liệu mục 4: mỗi lệnh phải
// gửi liền một cụm, không tách. TAOSG = phát 66 byte/giây (đầy đủ áp điện + kết quả).
static void sp_send_taos(const char* cmd) {
    SLEEPPAD_UART.write((const uint8_t*)cmd, strlen(cmd));
    SLEEPPAD_UART.flush();
}

#include "sleep-pad-frame.h"

static unsigned long last_0x85_frame_ms = 0;
static bool fallback_taosg = false;

static void send_time_sync_0x0B() {
    time_t now = time(nullptr);
    uint32_t t = (uint32_t)now;
    uint8_t content[4];
    content[0] = t & 0xFF;
    content[1] = (t >> 8) & 0xFF;
    content[2] = (t >> 16) & 0xFF;
    content[3] = (t >> 24) & 0xFF;
    sp_send_frame(0x0B, content, 4);
    Serial.println("[Mode] Đã gửi 0x0B hiệu chỉnh đồng hồ");
}

static void do_fallback_taosg() {
    if (fallback_taosg) return;
    fallback_taosg = true;
    Serial.println("[Mode] lùi về TAOSG — bat che do phat 66 byte/giay");
    sp_send_taos("TAOSG");
}

static void start_monitor_mode() {
    fallback_taosg = false;
    last_0x85_frame_ms = millis(); // Reset timeout
    Serial.println("[Mode] Yêu cầu chuyển sang chế độ giám sát 0x20 (frame)...");
    sp_send_frame(0x07, nullptr, 0); // Hỏi trạng thái
}

// Không có lệnh heartbeat riêng trong bộ lệnh TAOS. Phát lại TAOSG vừa giữ nhịp
// vừa tự khôi phục nếu pad đã rơi về chế độ chờ.
static void send_heartbeat() {
    if (fallback_taosg) {
        sp_send_taos("TAOSG");
    } else {
        // Trong chế độ frame 0x20, không thấy hãng nói cần heartbeat.
        // Có thể gửi 0x07 để giữ kết nối nếu cần.
        sp_send_frame(0x07, nullptr, 0);
    }
}

// --- Parser callbacks (forward declarations) ---

static void on_sec_data(const SleepPadSecData& d) {
    if (d.timestamp != 0) {
        last_0x85_frame_ms = millis();
    }
    Serial.printf("[0x85/TAOSG] ts=%u status=%u hr=%u rr=%.1f sdata=%u pdata=%u\n",
                  d.timestamp, d.status, d.heart_rate, d.resp_rate, d.sdata, d.pdata);
    mqtt_publish_sec(d);
}

static void on_min_data(const SleepPadMinData& d) {
    Serial.printf("[0x86] ts=%u status=%u hr=%u rr=%.1f mov=%u snore=%u temp=%.1fC\n",
                  d.timestamp, d.status, d.heart_rate, d.resp_rate,
                  d.movement, d.snore_count, d.temp / 10.0);
    mqtt_publish_min(d);
}

static void on_mode_confirmed(uint8_t mode) {
    if (fallback_taosg) return;
    if (mode == 0x20 || mode == 0x21) {
        Serial.printf("[Mode] 0x20 monitoring - OK (mode 0x%02X)\n", mode);
        send_time_sync_0x0B();
    } else {
        Serial.printf("[Mode] pad báo lỗi (mode 0x%02X), lùi về TAOSG\n", mode);
        do_fallback_taosg();
    }
}

static void on_status_query(uint8_t mode) {
    if (fallback_taosg) return;
    if (mode == 0x20) {
        Serial.println("[Mode] Pad đã ở chế độ 0x20 monitoring");
        send_time_sync_0x0B();
    } else {
        Serial.printf("[Mode] Đang ở mode 0x%02X, gửi 0x04 0x20 để vào chế độ giám sát...\n", mode);
        uint8_t content = 0x20;
        sp_send_frame(0x04, &content, 1);
    }
}

// --- SNTP time sync ---
//
// TLS cert validity check (mbedtls) compares notBefore/notAfter against the
// system clock. ESP32 boots with epoch 1970, so the very first TLS handshake
// against any cert valid 2024+ rejects with PK verify error 0x4290 ("Certificate
// matched but signature verification failed" — the actual reason is the
// not-yet-valid date). We must SNTP-sync before the first MQTT connect.
static bool sync_time(unsigned long timeout_ms = 10000) {
    Serial.println("[Time] SNTP sync...");
    configTime(0, 0, "pool.ntp.org", "time.cloudflare.com", "time.google.com");
    unsigned long start = millis();
    time_t now = 0;
    while (millis() - start < timeout_ms) {
        now = time(nullptr);
        if (now > 1700000000) {   // > 2023-11-14 → real time set
            Serial.printf("[Time] Synced: %ld\n", (long)now);
            return true;
        }
        delay(200);
    }
    Serial.printf("[Time] Timeout (current=%ld) — TLS may reject certs\n", (long)now);
    return false;
}

// --- WiFi connect (blocking, ≤ 2 attempts × 20 s) ---
//
// One pass of WiFi.begin() routinely fails with WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT
// (15) on ESP32-C3 even with correct credentials — race between SAE/WPA2 timing
// and the AP. Retrying once after a clean slate (`disconnect(true, true)` flushes
// any cached SSID/PMK from the driver) absorbs that transient without bouncing
// the user back to the BLE app to retype the same password.

static bool wifi_connect_once(const String& ssid, const String& pass,
                              unsigned long timeout_ms) {
    WiFi.disconnect(true, true);   // erase NVS-cached creds + flush driver
    delay(200);
    WiFi.mode(WIFI_STA);
    // Tắt power save. Mặc định Arduino-ESP32 là WIFI_PS_MIN_MODEM: modem ngủ giữa các
    // beacon. Trên link yếu (C3 Super Mini dùng ăng-ten gốm trên bo) nó làm mất beacon,
    // hỏng ARP và TCP không mở nổi — quan sát được là MISSING_ACKS, sock_errno=113
    // (EHOSTUNREACH) rồi tls_err=0x8004 (FAILED_CONNECT_TO_HOST), trong khi cùng lúc
    // broker vẫn nhận được kết nối từ máy khác. Node này cắm nguồn liên tục nên không
    // có lý do tiết kiệm điện.
    WiFi.setSleep(false);
    WiFi.begin(ssid.c_str(), pass.c_str());

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - start >= timeout_ms) return false;
        delay(500);
        Serial.print('.');
    }
    return true;
}

static bool connect_wifi(const String& ssid, const String& pass) {
    Serial.printf("[WiFi] Connecting to \"%s\"...\n", ssid.c_str());
    if (wifi_connect_once(ssid, pass, /*timeout_ms=*/20000)) {
        Serial.printf("\n[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
        return true;
    }
    Serial.println("\n[WiFi] First attempt failed — retrying once after reset");
    if (wifi_connect_once(ssid, pass, /*timeout_ms=*/20000)) {
        Serial.printf("\n[WiFi] Connected on retry — IP: %s\n",
                      WiFi.localIP().toString().c_str());
        return true;
    }
    Serial.println("\n[WiFi] Both attempts failed — giving up");
    return false;
}

// --- BLE provisioning flow (blocks until provisioning complete) ---

static void run_ble_provisioning() {
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
    // USB CDC: ghi KHÔNG chặn khi không có host đọc cổng.
    // Mặc định Serial.write() chờ tới 100ms mỗi lần buffer đầy. Node này in một dòng
    // mỗi khung pad (1Hz), nên chạy độc lập không cắm máy tính thì buffer đầy rồi
    // loop() treo — quan sát được là MQTT chết và sec_data ngừng tăng ĐÚNG lúc đóng
    // cổng serial, còn mở serial ra đo thì mọi thứ chạy. Đặt 0 để log chỉ là log.
    Serial.setTxTimeoutMs(0);
    delay(500);
    derive_device_id();   // populate DEVICE_ID before any subsystem reads it
    Serial.printf("\n[Boot] Sleep Pad ESP32 — device_id=%s\n", DEVICE_ID);

    // UART2 for sleep pad hardware
    SLEEPPAD_UART.begin(UART_BAUD, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);
    Serial.printf("[UART] SLEEPPAD_UART RX=%d TX=%d @ %d baud\n",
                  UART_RX_PIN, UART_TX_PIN, UART_BAUD);

    parser.onSecData = on_sec_data;
    parser.onMinData = on_min_data;
    parser.onModeConfirmed = on_mode_confirmed;
    parser.onStatusQuery = on_status_query;

    if (!nvs_init()) {
        Serial.println("[Boot] NVS init failed — continuing anyway");
    }

    NvsConfig cfg = nvs_load();

    // Cấu hình dựng sẵn lúc biên dịch: có include/dev-config.h thì node bỏ qua BLE
    // provisioning và dùng thẳng giá trị trong file. Không có file thì toàn bộ khối này
    // biến mất và luồng BLE giữ nguyên.
    //
    // Điều kiện là "khác NVS", KHÔNG phải "NVS trống". Bản trước chỉ nạp khi NVS trống,
    // nên một board đã ghép mạng cũ sẽ lờ đi file này mãi mãi: sửa SSID rồi nạp lại vẫn
    // nối vào mạng cũ, không lỗi biên dịch, không log, chỉ im lặng không lên MQTT. Đã mất
    // một vòng nạp vì đúng cái bẫy đó. File có mặt = file là nguồn sự thật.
#if __has_include("dev-config.h")
    if (cfg.wifi_ssid != DEV_WIFI_SSID || cfg.wifi_pass != DEV_WIFI_PASS ||
        cfg.mqtt_host != DEV_MQTT_HOST || cfg.mqtt_scheme != DEV_MQTT_SCHEME ||
        cfg.mqtt_user != DEV_MQTT_USER || cfg.mqtt_pass != DEV_MQTT_PASS) {
        cfg.wifi_ssid   = DEV_WIFI_SSID;
        cfg.wifi_pass   = DEV_WIFI_PASS;
        cfg.mqtt_host   = DEV_MQTT_HOST;
        cfg.mqtt_scheme = DEV_MQTT_SCHEME;
        cfg.mqtt_user   = DEV_MQTT_USER;
        cfg.mqtt_pass   = DEV_MQTT_PASS;
        nvs_set(NVS_KEY_SSID,   cfg.wifi_ssid);
        nvs_set(NVS_KEY_PASS,   cfg.wifi_pass);
        nvs_set(NVS_KEY_HOST,   cfg.mqtt_host);
        nvs_set(NVS_KEY_SCHEME, cfg.mqtt_scheme);
        nvs_set(NVS_KEY_USER,   cfg.mqtt_user);
        nvs_set(NVS_KEY_MPASS,  cfg.mqtt_pass);
        Serial.printf("[Boot] Nạp cấu hình dựng sẵn từ dev-config.h — ssid=\"%s\" broker=%s://%s\n",
                      cfg.wifi_ssid.c_str(), cfg.mqtt_scheme.c_str(), cfg.mqtt_host.c_str());
    }
#endif

    const bool fresh_provisioning = !cfg.has_wifi_creds();

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

            // SNTP time sync — REQUIRED before TLS or cert validity check fails
            // with PK verify error 0x4290 (cert "not yet valid" because RTC=1970).
            sync_time();

            // Prime the DNS cache + ARP path before MQTT connect. Without this,
            // the very first TLS attempt over a freshly-up WiFi link routinely
            // fails with "Host is unreachable" while LwIP is still resolving
            // the broker hostname / building the route entry, costing the user
            // a full retry cycle through the BLE app.
            {
                IPAddress _resolved;
                if (WiFi.hostByName(cfg.mqtt_host.c_str(), _resolved)) {
                    Serial.printf("[Net] Resolved %s -> %s\n",
                                  cfg.mqtt_host.c_str(), _resolved.toString().c_str());
                } else {
                    Serial.printf("[Net] DNS warmup failed for %s (continuing)\n",
                                  cfg.mqtt_host.c_str());
                }
            }

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
        sync_time();   // TLS cert validity needs real time (see helper)
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
    // In mock build, SLEEPPAD_UART is unused so this is a no-op on the wire, but
    // leaving it in keeps the boot sequence identical to production.
    start_monitor_mode();

#ifdef MOCK_SLEEPPAD
    g_mock_parser = &parser;
    mock_init(DEVICE_ID);
    Serial.println("[Mock] SLEEP PAD MOCK ACTIVE — synthesizing telemetry, SLEEPPAD_UART bypassed");
#endif

    Serial.println("[Boot] Ready");
}

void loop() {
    // ── Vòng lặp 10Hz cố định, không jitter (yêu cầu framework Phase 01) ──
    // Bám mốc tuyệt đối thay vì `delay(100)` để tổng thời gian thực hiện không dịch chuyển
    // (delay nhồi vào thời gian THỰC HIỆN, còn mốc tuyệt đối giữ đều nhịp). Trong mỗi tick:
    //  1) rút UART pad (nhịp thật do pad quyết định — pad là master 1Hz, firmware không tự sinh)
    //  2) mqtt_loop(): đẩy mẫu tồn đọng ra broker khi MQTT thông (ring buffer)
    //  3) heartbeat 0x08 60s cho pad
    static uint32_t last_tick_ms = 0;
    static uint32_t next_tick_ms = 0;
    const uint32_t now = millis();

    if (now - last_tick_ms >= 100UL) {   // tick 10Hz
        last_tick_ms = now;
        next_tick_ms = now + 100UL;

#ifndef MOCK_SLEEPPAD
        // Drain UART bytes into parser (production path)
        while (SLEEPPAD_UART.available()) {
            const uint8_t b = static_cast<uint8_t>(SLEEPPAD_UART.read());
            parser.feedTaos(b);   // đường LSM-800-T (tag [Bdata])
#ifdef UART_RAW_DUMP
            // Chan doan tam: parser vut im moi byte khac 0x7D, nen "khong co log"
            // KHONG chung minh "khong co byte". Dump tho de phan biet day cam
            // voi day co tin hieu nhung sai baud/khung.
            Serial.printf("%02X ", b);
#endif
            parser.feed(b);
        }
#else
        // Mock path — generate synthetic frame bytes and feed the parser
        mock_tick(mock_feed_parser);
#endif

        // PubSubClient state machine + auto-reconnect + drain ring buffer
        mqtt_loop();

        // 0x08 heartbeat every 60 s (device restarts WiFi stack if silent for >5 min)
        if (now - last_heartbeat_ms >= 60000UL) {
            last_heartbeat_ms = now;
            send_heartbeat();
        }

        // Lưới an toàn: Nếu không thấy khung 0x85 trong 15s, lùi về TAOSG
        if (!fallback_taosg && now - last_0x85_frame_ms > 15000UL) {
            Serial.println("[Mode] Timeout 15s không nhận được khung 0x85");
            do_fallback_taosg();
        }
    }

    // Giữ nhịp 10Hz: ngủ tới mốc tick kế tiếp (không phải delay(100) trần).
    if (millis() < next_tick_ms) {
        delay(next_tick_ms - millis());
    } else {
        delay(1);   // lỡ mốc (hiếm) — không bù, để mốc tuyệt đối tự bắt kịp nhịp
    }
}
