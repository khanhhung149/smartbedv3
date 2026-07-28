// Radar node — Wemos S2 Mini (ESP32-S2) + radar LD2410C.
//
// VAI TRÒ: đọc LD2410C ngay trên board (chân OUT + UART native), tự nối WiFi + MQTT,
// bắn dữ liệu presence lên broker theo HAI contract đã có trong hệ thống:
//
//   1) home/room/presence  {"ts":<epoch_ms>,"present":bool}   (retain, QoS1)
//        -> backend Go (internal/mqttclient) ăn topic này, chạy fusion + ghi lịch sử
//           rồi đẩy trạng thái vào app qua WebSocket /api/ws. Đây là đường "backend
//           lấy dữ liệu và đẩy vào app".
//
//   2) tele/<DEVICE_TOPIC>/SENSOR  (JSON khuôn tele/stat) + trả lời cmnd/<T>/STATUS 10
//        -> tab "Thiết bị" của app Flutter (MqttService) đọc THẲNG số liệu radar:
//           cự ly/năng lượng mục tiêu cử động & đứng yên. Cùng khuôn topic với con S2
//           dùng firmware cũ trước đây nên app không phải sửa gì.
//
// Wiring thật (xem docs/system-wiring.md):
//   LD2410 OUT -> GPIO16     LD2410 VCC -> 5V     LD2410 GND -> GND
//   LD2410 TX  -> GPIO33 (RX của S2)   LD2410 RX -> GPIO18 (TX của S2, gửi lệnh cấu hình)
//   ⚠️ Nuôi radar bằng 5V và KHÔNG hàn module đè lên cổng USB-C (đã gây chập ở bản trước).
//
// Chân OUT cho 1 bit có/không người; UART cho thêm cự ly (cm) + năng lượng phản xạ của
// mục tiêu cử động/đứng yên. `present` lấy từ OUT (đã nghiệm thu) HOẶC UART thấy mục tiêu,
// qua debounce chống nhiễu; UART hỏng thì vẫn chạy bằng OUT, chỉ mất phần số liệu chi tiết.

#include <Arduino.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <MQTT.h>
#include <ld2410.h>
#include <sys/time.h>

#include "config.h"

// ---- Phần cứng ----
static const uint8_t  PIN_PRESENCE = 16;      // LD2410 OUT (presence digital)
static const uint8_t  PIN_RADAR_RX = 33;      // LD2410 TX -> chân này (S2 nhận)
static const uint8_t  PIN_RADAR_TX = 18;      // LD2410 RX <- chân này (S2 gửi lệnh)
static const uint32_t RADAR_BAUD   = 256000;  // baud mặc định của LD2410

// ---- MQTT topic ----
static const char *TOPIC_PRESENCE = "home/room/presence";  // contract backend Go
static const char *TOPIC_MOTION   = "home/door/motion";    // event cử động -> backend lưu -> app Analytics

// Topic khuôn tele/stat dựng từ DEVICE_TOPIC tại setup().
String teleSensor, teleLwt, statStatus10, cmndStatus;

// ---- Luật presence (nhịp/ngưỡng lấy từ room-node đã nghiệm thu) ----
static const uint32_t PRESENCE_HOLD_MS   = 300;    // OUT phải HIGH liên tục ~0.3s mới báo có người
static const uint32_t RADAR_DEBOUNCE_MS  = 30000;  // giữ "còn người" tới 30s sau khi OUT rớt (chống mất khi ngồi yên)
static const uint32_t POLL_MS            = 100;    // đọc chân OUT dày để bắt cả xung ngắn
static const uint32_t PRESENCE_HEARTBEAT_MS = 30000;  // republish presence định kỳ (link còn sống + ghi đè retained cũ)
static const uint32_t TELE_PERIOD_MS     = 3000;   // nhịp đẩy tele/<T>/SENSOR cho app (giống nhịp tele định kỳ)
static const uint32_t MOTION_THROTTLE_MS = 1000;   // trần 1 event/s khi đang cử động (khớp throttle PIR voice-node cũ, chống flood lịch sử)

ld2410     radar;
WiFiClient net;
MQTTClient mqtt(1024);   // payload SENSOR/STATUS10 có thể >256B

// ---- Trạng thái ----
uint32_t lastPollMs       = 0;
uint32_t lastTeleMs       = 0;
uint32_t lastPresencePubMs = 0;
uint32_t lastMotionPubMs  = 0;
uint32_t lastRadarHighMs  = 0;
uint32_t radarFirstHighMs = 0;
bool     radarEverHigh    = false;
bool     present          = false;
bool     presencePublished = false;  // đã publish presence lần nào chưa (để ghi đè retained cũ sau khi có NTP)

// ---- Thời gian epoch (ms); 0 nếu NTP chưa sync ----
uint64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 100000) return 0;
  return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;
}
bool ntpReady() { return epochMs() > 0; }

// ---- Số liệu radar mới nhất (đọc trong loop, không đa luồng) ----
struct RadarData {
  bool     uartOk = false;
  bool     moving = false;
  bool     still  = false;
  uint16_t movingDist = 0, stillDist = 0;
  uint8_t  movingEnergy = 0, stillEnergy = 0;
};

RadarData readRadar() {
  RadarData d;
  d.uartOk = radar.isConnected();
  if (!d.uartOk) return d;
  if (radar.movingTargetDetected()) {
    d.moving       = true;
    d.movingDist   = radar.movingTargetDistance();
    d.movingEnergy = radar.movingTargetEnergy();
  }
  if (radar.stationaryTargetDetected()) {
    d.still       = true;
    d.stillDist   = radar.stationaryTargetDistance();
    d.stillEnergy = radar.stationaryTargetEnergy();
  }
  return d;
}

// ---- WiFi: nối + tự thử lại, không treo loop khi mất mạng ----
void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("WiFi: nối %s", WIFI_SSID);
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(250);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " OK" : " FAIL (thử lại sau)");
}

// ---- MQTT: nối broker, đặt LWT, subscribe poll STATUS ----
void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED || mqtt.connected()) return;
  // Will = home/room/presence {"present":false} (retain, QoS1). MQTT chỉ cho 1 will/kết nối:
  // ưu tiên presence thay vì tele/LWT vì presence là cái backend+app dựa vào để biết "có người".
  // Khi board rớt TCP (mất điện/mất WiFi) broker tự bắn present:false -> Home thôi "thấy người"
  // ngay, không giữ present:true retained vĩnh viễn. Payload cố định (không có ts động vì will
  // set lúc connect); backend coi ts=0 là hợp lệ cho trạng thái vắng. Tab "Thiết bị" dựa vào
  // staleness bên app, không cần tele/LWT nữa.
  mqtt.setWill(TOPIC_PRESENCE, "{\"present\":false}", true /*retain*/, 1 /*qos*/);
  Serial.print("MQTT: nối broker");
  for (uint8_t i = 0; i < 3 && !mqtt.connected(); i++) {
    if (mqtt.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASS)) break;
    Serial.print(".");
    delay(500);
    if (WiFi.status() != WL_CONNECTED) { Serial.println(" mất WiFi"); return; }
  }
  Serial.println(mqtt.connected() ? " OK" : " FAIL (thử lại sau)");
  if (mqtt.connected()) {
    mqtt.publish(teleLwt, "Online", true, 1);
    // App poll cmnd/<T>/STATUS payload "10" mỗi 2s. Sub trong hàm connect vì
    // subscription mất khi rớt kết nối.
    mqtt.subscribe(cmndStatus, 1);
    presencePublished = false;  // ép publish lại presence hiện tại sau reconnect
  }
}

// Ghép khối JSON LD2410 khuôn tele/stat vào buf. Trả số ký tự đã ghi.
int buildLd2410Json(char *buf, size_t n, const RadarData &d) {
  return snprintf(buf, n,
      "{\"LD2410\":{\"Detect\":%d,"
      "\"Moving\":{\"Distance\":%u,\"Energy\":%u},"
      "\"Static\":{\"Distance\":%u,\"Energy\":%u}}}",
      present ? 1 : 0,
      (unsigned)d.movingDist, (unsigned)d.movingEnergy,
      (unsigned)d.stillDist,  (unsigned)d.stillEnergy);
}

// tele/<T>/SENSOR — app đọc thẳng số liệu radar (tab "Thiết bị").
void publishSensor(const RadarData &d) {
  if (!mqtt.connected()) return;
  char payload[192];
  buildLd2410Json(payload, sizeof(payload), d);
  mqtt.publish(teleSensor, payload, false /*retain*/, 0 /*qos*/);
}

// stat/<T>/STATUS10 — trả lời poll STATUS 10 của app (bọc trong StatusSNS).
void publishStatus10(const RadarData &d) {
  if (!mqtt.connected()) return;
  char inner[192];
  buildLd2410Json(inner, sizeof(inner), d);
  char payload[224];
  snprintf(payload, sizeof(payload), "{\"StatusSNS\":%s}", inner);
  mqtt.publish(statStatus10, payload, false, 0);
}

// home/room/presence — contract backend Go. Retain để backend restart đọc lại được
// trạng thái hiện tại. Hoãn khi NTP chưa sẵn: đừng ghi ts=0 vào lịch sử vĩnh viễn.
void publishPresence() {
  if (!mqtt.connected() || !ntpReady()) return;
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%llu,\"present\":%s}",
           (unsigned long long)epochMs(), present ? "true" : "false");
  bool ok = mqtt.publish(TOPIC_PRESENCE, payload, true /*retain*/, 1 /*qos*/);
  Serial.printf("PUB %s %s -> %s\n", TOPIC_PRESENCE, payload, ok ? "ok" : "fail");
  if (ok) {
    presencePublished = true;
    lastPresencePubMs = millis();
  }
}

// home/door/motion — event cử động cho backend lưu (Event.kindMotion) -> app Analytics
// đếm motionCount/motionByHour. Payload KHỚP contract voice-node/backend cũ.
void publishMotion() {
  if (!mqtt.connected() || !ntpReady()) return;  // ts=0 làm bẩn lịch sử vĩnh viễn
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%llu,\"motion\":true}",
           (unsigned long long)epochMs());
  mqtt.publish(TOPIC_MOTION, payload, false /*retain*/, 1 /*qos*/);
}

// App gửi cmnd/<T>/STATUS "10" -> trả stat/<T>/STATUS10 ngay.
void onMqtt(String &topic, String &payload) {
  if (topic == cmndStatus && payload.indexOf("10") >= 0) {
    publishStatus10(readRadar());
  }
}

// Nạp firmware qua WiFi (nhả radar UART trước khi ghi flash cho chắc).
void setupOTA() {
  ArduinoOTA.setHostname(OTA_HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASSWORD);
  ArduinoOTA.onEnd([]() { Serial.println("\n[ota] xong — khởi động lại"); });
  ArduinoOTA.onError([](ota_error_t err) {
    Serial.printf("\n[ota] LỖI %u — giữ firmware cũ, nạp lại qua USB nếu cần\n", err);
  });
  ArduinoOTA.begin();
  Serial.printf("[ota] sẵn sàng: %s @ %s\n", OTA_HOSTNAME, WiFi.localIP().toString().c_str());
}

void setup() {
  Serial.begin(115200);
  // S2 dùng USB CDC gốc: chờ host mở cổng (tối đa 2s) để không mất log boot.
  uint32_t serialWait = millis();
  while (!Serial && millis() - serialWait < 2000) delay(10);
  delay(200);
  Serial.println("\n[boot] radar-node (S2 Mini + LD2410C) start");

  // INPUT_PULLDOWN: radar hở/chết thì chân OUT thả nổi nhặt nhiễu -> với ngưỡng nhạy
  // 300ms dễ đẻ presence GIẢ. Pulldown ghì về 0 khi radar không driving; OUT là
  // push-pull nên khi phát hiện thật vẫn kéo HIGH thắng.
  pinMode(PIN_PRESENCE, INPUT_PULLDOWN);

  // UART hai chiều tới radar (RX ở GPIO33, TX ở GPIO18 để gửi lệnh cấu hình nếu cần).
  Serial1.begin(RADAR_BAUD, SERIAL_8N1, PIN_RADAR_RX, PIN_RADAR_TX);
  if (radar.begin(Serial1, false)) {
    Serial.println("[radar] UART mở, chờ khung dữ liệu LD2410");
  } else {
    Serial.println("[radar] UART KHÔNG mở được — chạy tiếp bằng chân OUT");
  }

  // Topic khuôn tele/stat cho app.
  teleSensor   = String("tele/") + DEVICE_TOPIC + "/SENSOR";
  teleLwt      = String("tele/") + DEVICE_TOPIC + "/LWT";
  statStatus10 = String("stat/") + DEVICE_TOPIC + "/STATUS10";
  cmndStatus   = String("cmnd/") + DEVICE_TOPIC + "/STATUS";

  connectWiFi();
  setupOTA();
  configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC epoch cho ts presence

  mqtt.begin(MQTT_HOST, MQTT_PORT, net);
  mqtt.onMessage(onMqtt);
  connectMQTT();
}

// Gộp OUT + UART -> present, qua hold/debounce.
void updatePresence(uint32_t now, const RadarData &d) {
  bool raw = digitalRead(PIN_PRESENCE) == HIGH || (d.uartOk && (d.moving || d.still));

  // Mục tiêu CỬ ĐỘNG (UART) -> bắn event motion cho Analytics, throttle 1/s. Chỉ dùng
  // d.moving (không dùng d.still) vì "chuyển động" khác "có người đứng yên".
  if (d.moving && ntpReady() && now - lastMotionPubMs >= MOTION_THROTTLE_MS) {
    lastMotionPubMs = now;
    publishMotion();
  }

  if (raw) {
    lastRadarHighMs = now;
    radarEverHigh = true;
    if (radarFirstHighMs == 0) radarFirstHighMs = now;
  } else {
    radarFirstHighMs = 0;
  }

  bool before = present;
  if (!present) {
    // Vào: radar giữ tín hiệu liên tục đủ lâu (chống nhiễu bật/tắt).
    if (raw && radarFirstHighMs != 0 && now - radarFirstHighMs >= PRESENCE_HOLD_MS) {
      present = true;
    }
  } else {
    // Ra: radar im đủ lâu. Debounce vì LD2410 rớt chớp nhoáng khi người ngồi yên.
    bool recent = raw || (radarEverHigh && now - lastRadarHighMs < RADAR_DEBOUNCE_MS);
    if (!recent) present = false;
  }

  if (present != before) {
    Serial.printf("[radar] present -> %d\n", present);
    publishPresence();
    publishSensor(d);  // đẩy số liệu tươi kèm luôn cho app
  }
}

void loop() {
  uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  ArduinoOTA.handle();
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  radar.read();  // bơm parser UART mỗi vòng, kẻo tràn đệm nối tiếp mất khung

  if (now - lastPollMs >= POLL_MS) {
    lastPollMs = now;
    updatePresence(now, readRadar());
  }

  // Republish presence đúng lần đầu sau khi NTP sẵn sàng (ghi đè retained cũ), và định kỳ
  // để backend biết link còn sống.
  if (mqtt.connected() && ntpReady() &&
      (!presencePublished || now - lastPresencePubMs >= PRESENCE_HEARTBEAT_MS)) {
    publishPresence();
  }

  // Nhịp SENSOR cho app (giống nhịp tele định kỳ) — có số liệu tươi dù không đổi present.
  if (now - lastTeleMs >= TELE_PERIOD_MS) {
    lastTeleMs = now;
    publishSensor(readRadar());
  }
}
