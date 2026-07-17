// Room node — Wemos S2 Mini + radar LD2410.
//
// VAI TRÒ DUY NHẤT: đọc chân presence của radar rồi gửi sang voice-node (ESP32 WROOM-32)
// qua ESP-NOW. Không WiFi, không MQTT, không NTP, không OTA — mọi quyết định (fusion với
// PIR, bắn IR, relay lên MQTT) nằm ở voice-node.
//
// Wiring thật (xem docs/system-wiring.md):
//   LD2410 OUT -> GPIO16     LD2410 VCC -> 5V     LD2410 GND -> GND
//
// ĐÁNH ĐỔI ĐÃ CHẤP NHẬN (user chốt 2026-07-17):
//   - Bỏ WiFi -> MẤT OTA. Board này chỉ nạp được qua USB (giữ BOOT + tap RST).
//   - Bỏ WiFi -> MẤT NTP -> không có giờ thật. voice-node đóng dấu thời gian khi relay.
//
// ESP-NOW dính kênh WiFi: voice-node vẫn nối WiFi (audio + MQTT + OTA) nên radio của nó
// bị khoá vào kênh của router. ESP-NOW không đổi được kênh đó -> board này phải QUÉT SSID
// để dò tới đúng kênh. Sai kênh thì gói bay vào hư không, KHÔNG có lỗi báo về.
//
// Nạp: pio run -t upload -e lolin_s2_mini
// Serial: pio device monitor

#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

#include "config.h"

// ---- Phần cứng ----
static const uint8_t PIN_PRESENCE = 16;  // LD2410 OUT (presence digital)

// ---- Luật radar (giữ nguyên bản đã NGHIỆM THU trên phần cứng thật 2026-07-16) ----
static const uint32_t PRESENCE_HOLD_MS  = 1500;  // radar giữ HIGH liên tục bấy lâu -> có người
static const uint32_t RADAR_DEBOUNCE_MS = 3000;  // radar rớt HIGH trong khoảng này vẫn coi "còn thấy"
static const uint32_t POLL_MS           = 200;   // nhịp đọc radar

// ---- ESP-NOW ----
static const uint32_t HEARTBEAT_MS      = 5000;  // gửi lại dù không đổi -> bên nhận biết link còn sống
static const uint8_t  MAX_SEND_FAIL     = 3;     // FAIL liên tiếp bấy nhiêu -> nghi sai kênh, quét lại
static const uint32_t RESCAN_COOLDOWN_MS = 10000;
static const uint8_t  MSG_MAGIC         = 0xA7;  // lọc gói lạ/rác trên cùng kênh

// Payload phải GIỐNG HỆT bên voice-node. packed để 2 kiến trúc (ESP32-S2 vs ESP32)
// không chèn padding khác nhau làm lệch field.
typedef struct __attribute__((packed)) {
  uint8_t  magic;
  uint8_t  present;
  uint32_t seq;
} RadarMsg;

static const uint8_t PEER_MAC[6] = ESPNOW_PEER_MAC;  // MAC của voice-node, xem config.h

// ---- Trạng thái ----
uint32_t lastPollMs      = 0;
uint32_t lastSendMs      = 0;
uint32_t lastRadarHighMs = 0;
uint32_t radarFirstHighMs = 0;
bool     radarEverHigh   = false;
bool     present         = false;
uint32_t seq             = 0;
uint8_t  channel         = 0;
uint32_t lastScanMs      = 0;
volatile uint8_t sendFailStreak = 0;

// Callback báo kết quả gửi. Chạy trong ngữ cảnh WiFi task -> chỉ đụng biến đơn giản,
// KHÔNG in Serial dài hay gọi hàm nặng ở đây.
void onSent(const uint8_t *mac, esp_now_send_status_t status) {
  if (status == ESP_NOW_SEND_SUCCESS) {
    sendFailStreak = 0;
  } else if (sendFailStreak < 255) {
    sendFailStreak++;
  }
}

// Quét SSID để biết router đang ở kênh nào. voice-node nối WiFi nên nó nằm ở kênh này;
// ESP-NOW bắt buộc cùng kênh mới tới nơi.
bool learnChannel() {
  lastScanMs = millis();
  int n = WiFi.scanNetworks();
  for (int i = 0; i < n; i++) {
    if (WiFi.SSID(i) == String(WIFI_SSID)) {
      channel = WiFi.channel(i);
      WiFi.scanDelete();
      Serial.printf("[espnow] thấy SSID '%s' ở kênh %u\n", WIFI_SSID, channel);
      return true;
    }
  }
  WiFi.scanDelete();
  Serial.printf("[espnow] KHÔNG thấy SSID '%s' -> chưa biết kênh, thử lại sau\n", WIFI_SSID);
  return false;
}

// Đặt kênh + (re)đăng ký peer. Gọi lại được khi kênh đổi.
bool applyChannel() {
  if (channel == 0) return false;
  esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);

  esp_now_del_peer(PEER_MAC);  // bỏ qua lỗi nếu chưa từng add
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, PEER_MAC, 6);
  peer.channel = channel;
  peer.encrypt = false;
  if (esp_now_add_peer(&peer) != ESP_OK) {
    Serial.println("[espnow] add_peer LỖI");
    return false;
  }
  Serial.printf("[espnow] peer %02X:%02X:%02X:%02X:%02X:%02X @ kênh %u\n",
                PEER_MAC[0], PEER_MAC[1], PEER_MAC[2], PEER_MAC[3], PEER_MAC[4], PEER_MAC[5],
                channel);
  return true;
}

void sendPresence() {
  RadarMsg msg = {MSG_MAGIC, (uint8_t)(present ? 1 : 0), ++seq};
  esp_err_t r = esp_now_send(PEER_MAC, (uint8_t *)&msg, sizeof(msg));
  lastSendMs = millis();
  if (r != ESP_OK) {
    if (sendFailStreak < 255) sendFailStreak++;
    Serial.printf("[espnow] send lỗi ngay: %d\n", r);
  }
}

void setup() {
  Serial.begin(115200);
  // S2 dùng USB CDC gốc: chờ host mở cổng (tối đa 2s) để không mất log boot
  uint32_t serialWait = millis();
  while (!Serial && millis() - serialWait < 2000) delay(10);
  delay(200);

  pinMode(PIN_PRESENCE, INPUT);

  // STA nhưng KHÔNG connect: chỉ cần radio bật để quét kênh + chạy ESP-NOW.
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  Serial.printf("[espnow] MAC board này: %s\n", WiFi.macAddress().c_str());

  if (esp_now_init() != ESP_OK) {
    Serial.println("[espnow] init LỖI -> khởi động lại");
    delay(2000);
    ESP.restart();
  }
  esp_now_register_send_cb(onSent);

  if (learnChannel()) applyChannel();
  Serial.println("[espnow] room-node sẵn sàng (radar-only, không WiFi/MQTT/OTA)");
}

void loop() {
  uint32_t now = millis();

  // Chưa biết kênh -> quét lại định kỳ, đừng gửi mù.
  if (channel == 0) {
    if (now - lastScanMs >= RESCAN_COOLDOWN_MS && learnChannel()) applyChannel();
    return;
  }

  // Gửi FAIL liên tiếp -> nghi router đổi kênh -> quét lại.
  if (sendFailStreak >= MAX_SEND_FAIL && now - lastScanMs >= RESCAN_COOLDOWN_MS) {
    Serial.printf("[espnow] %u lần gửi FAIL -> quét lại kênh\n", sendFailStreak);
    sendFailStreak = 0;
    if (learnChannel()) applyChannel();
  }

  if (now - lastPollMs >= POLL_MS) {
    lastPollMs = now;
    bool radar = digitalRead(PIN_PRESENCE) == HIGH;

    if (radar) {
      lastRadarHighMs = now;
      radarEverHigh = true;
      if (radarFirstHighMs == 0) radarFirstHighMs = now;
    } else {
      radarFirstHighMs = 0;
    }

    bool before = present;
    if (!present) {
      // Vào: radar phải giữ HIGH liên tục đủ lâu (chống nhiễu bật/tắt).
      if (radar && radarFirstHighMs != 0 && now - radarFirstHighMs >= PRESENCE_HOLD_MS) {
        present = true;
      }
    } else {
      // Ra: radar im đủ lâu. Debounce vì LD2410 rớt HIGH chớp nhoáng khi người ngồi yên.
      bool radarRecent = radar || (radarEverHigh && now - lastRadarHighMs < RADAR_DEBOUNCE_MS);
      if (!radarRecent) present = false;
    }

    if (present != before) {
      Serial.printf("[radar] present -> %d\n", present);
      sendPresence();
    }
  }

  // Heartbeat: bên nhận dùng nó để phát hiện link chết. Không có nó, voice-node không
  // phân biệt được "phòng vẫn trống" với "board này đã chết".
  if (now - lastSendMs >= HEARTBEAT_MS) sendPresence();
}
