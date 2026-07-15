// Door node — Wemos S2 Mini (ESP32-S2)
// Đọc PIR mini, publish event chuyển động lên MQTT.
//
// Wiring (XÁC NHẬN pinout board thật trước khi hàn — GPIO7 không trùng chân strapping boot):
//   PIR VCC -> S2 Mini 3V3
//   PIR OUT -> S2 Mini GPIO7
//   PIR GND -> S2 Mini GND
//   Nguồn:     USB-C 5V
//
// Publish: home/door/motion  {"ts":<unix_ms>,"motion":true}  QoS 1, retain=false

#include <Arduino.h>
#include <WiFi.h>
#include <MQTT.h>
#include <sys/time.h>
#include "config.h"

// ---- Phần cứng ----
static const uint8_t PIN_PIR = 7;   // GPIO7 <- PIR OUT

// ---- Topic ----
static const char *TOPIC_MOTION = "home/door/motion";

// ---- Debounce: bỏ qua trigger lặp trong 2s (PIR giữ HIGH vài giây) ----
static const uint32_t DEBOUNCE_MS = 2000;

WiFiClient net;
MQTTClient mqtt(256);              // buffer 256B đủ cho payload nhỏ

volatile bool motionFlag = false;  // set trong ISR, xử lý trong loop
uint32_t lastPublishMs = 0;
bool firstPublishDone = false;

// ISR: chỉ set cờ. KHÔNG gọi MQTT trong ISR (client không interrupt-safe).
void IRAM_ATTR onMotion() {
  motionFlag = true;
}

// Unix epoch mili-giây. Trả 0 nếu NTP chưa sync (backend bỏ qua ts=0).
uint64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 100000) return 0;
  return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("WiFi: nối tới %s", WIFI_SSID);
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(250);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " OK" : " FAIL (thử lại sau)");
}

void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqtt.connected()) return;
  Serial.print("MQTT: nối broker");
  // Thử vài lần rồi trả về để loop() còn kịp lo lại WiFi nếu rớt
  for (uint8_t i = 0; i < 5 && !mqtt.connected(); i++) {
    if (mqtt.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASS)) break;
    Serial.print(".");
    delay(1000);
    if (WiFi.status() != WL_CONNECTED) { Serial.println(" mất WiFi"); return; }
  }
  Serial.println(mqtt.connected() ? " OK" : " FAIL");
}

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(PIN_PIR, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_PIR), onMotion, RISING);

  connectWiFi();
  configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC epoch qua NTP
  mqtt.begin(MQTT_HOST, MQTT_PORT, net);
  connectMQTT();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  if (motionFlag) {
    motionFlag = false;
    uint32_t now = millis();
    bool outsideDebounce = (now - lastPublishMs) >= DEBOUNCE_MS;
    if (!firstPublishDone || outsideDebounce) {
      lastPublishMs = now;
      firstPublishDone = true;

      char payload[64];
      snprintf(payload, sizeof(payload),
               "{\"ts\":%llu,\"motion\":true}",
               (unsigned long long)epochMs());

      bool ok = mqtt.connected() &&
                mqtt.publish(TOPIC_MOTION, payload, false /*retain*/, 1 /*qos*/);
      Serial.printf("PUB %s %s -> %s\n", TOPIC_MOTION, payload, ok ? "ok" : "fail");
    }
  }

  delay(10);
}
