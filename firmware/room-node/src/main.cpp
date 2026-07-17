// Room node — Wemos S2 Mini (ESP32-S2)  [phần cứng thật: LD2410 radar trên S2 Mini]
// (1) Đọc radar presence -> publish home/room/presence (retain). CHỈ radar.
// (2) Học mã IR từ remote điều hòa thật, lưu NVS, phát lại khi có lệnh.
//
// PIR đã DỜI sang voice-node (WROOM-32) — quyết định 2026-07-16: fusion PIR+radar
// chuyển về backend (state machine gộp home/door/motion + home/room/presence).
// Room-node giờ chỉ lo radar -> presence + điều khiển IR. Xem plan
// plans/260716-1433-relocate-pir-to-voice-node-backend-fusion/.
//
// Wiring thật (HLK-LD2410 -> S2 Mini):
//   LD2410 VCC -> S2 Mini VBUS (5V)     LD2410 GND -> S2 Mini GND
//   LD2410 OUT (presence digital) -> S2 Mini GPIO16  (input)  <-- MVP dùng chân này
//   LD2410 TX  -> S2 Mini GPIO33   LD2410 RX -> S2 Mini GPIO18
//     (UART để dành parse frame LD2410 sau — MVP chỉ đọc OUT digital, chưa init UART)
//
//   IR Receiver TSOP: VCC->3V3, GND->GND, OUT->S2 Mini GPIO15 (chỉ dùng lúc học)
//   IR Blaster: S2 Mini GPIO5 -> R220 -> Base transistor (S8050/2N2222),
//               Emitter->GND, Collector->IR LED cathode, LED anode->R68->5V
//
// Topic:
//   publish   home/room/presence  {"ts":<unix_ms>,"present":true|false}  QoS1 retain
//             — "present" là occupied theo RADAR (enter khi radar giữ đủ lâu,
//               exit sau debounce). Backend fuse thêm motion từ voice-node.
//   subscribe home/room/ac_cmd    {"cmd":"on"|"off"}    -> phát IR
//   subscribe home/room/ac_learn  {"button":"on"|"off"} -> vào chế độ học IR
//
// Mã IR lưu LOCAL trên NVS (namespace "ac_codes"). Không publish qua MQTT (quyết định MVP).

#include <Arduino.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <MQTT.h>
#include <Preferences.h>
#include <sys/time.h>

#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <IRutils.h>

#include "config.h"

// ---- Phần cứng (S2 Mini) ----
static const uint8_t  PIN_PRESENCE = 16;   // LD2410 OUT (presence digital)
static const uint16_t PIN_IR_RECV  = 15;   // TSOP OUT (chỉ dùng lúc học)
static const uint16_t PIN_IR_SEND  = 5;    // IR LED driver

// ---- Topic ----
static const char *TOPIC_PRESENCE = "home/room/presence";
static const char *TOPIC_AC_CMD   = "home/room/ac_cmd";
static const char *TOPIC_AC_LEARN = "home/room/ac_learn";

// ---- Presence theo radar: tham số tune sau khi verify thực tế ----
static const uint32_t PRESENCE_HOLD_MS  = 1500;   // radar giữ HIGH liên tục bấy lâu -> vào (occupied)
static const uint32_t RADAR_DEBOUNCE_MS = 3000;   // radar rớt HIGH trong khoảng này vẫn coi "còn thấy" (chống rung) -> ra sau đó
static const uint32_t STATUS_HEARTBEAT_MS = 2000; // nhịp in trạng thái ra Serial để bench-test (đặt 0 để tắt)

// ---- IR ----
static const uint16_t kCaptureBufferSize = 1024;  // đủ cho khung điều hòa dài
static const uint8_t  kIrTimeoutMs       = 50;    // khung AC lớn -> timeout cao (tên tránh trùng IRrecv.h)
static const uint16_t kMinRawLen         = 12;    // bỏ nhiễu quá ngắn
static const uint16_t kIrFreqKhz         = 38;
static const uint32_t LEARN_WINDOW_MS    = 15000; // 15s để bấm remote

IRrecv irrecv(PIN_IR_RECV, kCaptureBufferSize, kIrTimeoutMs, true);
IRsend irsend(PIN_IR_SEND);
decode_results results;
Preferences prefs;

WiFiClient net;
MQTTClient mqtt(512);

static uint16_t rawBuf[kCaptureBufferSize];  // dùng chung cho load & send

// ---- Trạng thái presence (chỉ radar) ----
bool     occupied = false;         // trạng thái hiện đang publish ra MQTT (radar-based)
uint32_t lastPollMs = 0;           // nhịp đọc radar 200ms

uint32_t radarFirstHighMs = 0;     // 0 = radar đang LOW; >0 = mốc bắt đầu chuỗi HIGH hiện tại
uint32_t lastRadarHighMs  = 0;     // lần cuối radar đọc HIGH
bool     radarEverHigh    = false; // false -> chưa từng thấy radar HIGH, không tính "còn mới" cho lastRadarHighMs=0

bool     learning = false;
char     learnKey[4] = {0};   // "on" / "off"
uint32_t learnUntilMs = 0;

// ---- Tiện ích thời gian ----
uint64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 100000) return 0;  // NTP chưa sync
  return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;
}

// ---- Kết nối ----
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

void publishPresence(bool present) {
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%llu,\"present\":%s}",
           (unsigned long long)epochMs(), present ? "true" : "false");
  bool ok = mqtt.connected() &&
            mqtt.publish(TOPIC_PRESENCE, payload, true /*retain*/, 1 /*qos*/);
  Serial.printf("PUB %s %s -> %s\n", TOPIC_PRESENCE, payload, ok ? "ok" : "fail");
}

void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqtt.connected()) return;
  Serial.print("MQTT: nối broker");
  for (uint8_t i = 0; i < 5 && !mqtt.connected(); i++) {
    if (mqtt.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASS)) break;
    Serial.print(".");
    delay(1000);
    if (WiFi.status() != WL_CONNECTED) { Serial.println(" mất WiFi"); return; }
  }
  if (!mqtt.connected()) { Serial.println(" FAIL"); return; }

  // Subscription mất sau reconnect -> đăng ký lại mỗi lần connect
  mqtt.subscribe(TOPIC_AC_CMD, 1);
  mqtt.subscribe(TOPIC_AC_LEARN, 1);
  Serial.println(" OK (subscribed ac_cmd, ac_learn)");

  // Đẩy lại trạng thái presence hiện tại để retain đúng sau reconnect
  publishPresence(occupied);
}

// ---- IR: phát lệnh ----
void sendAC(const char *key) {
  char lenKey[12], rawKey[12];
  snprintf(lenKey, sizeof(lenKey), "%s_len", key);
  snprintf(rawKey, sizeof(rawKey), "%s_raw", key);

  prefs.begin("ac_codes", true /*readonly*/);
  uint16_t len = prefs.getUShort(lenKey, 0);
  if (len == 0 || len > kCaptureBufferSize) {
    prefs.end();
    Serial.printf("AC: chưa học lệnh '%s' -> bỏ qua (không crash)\n", key);
    return;
  }
  size_t got = prefs.getBytes(rawKey, rawBuf, (size_t)len * 2);
  prefs.end();
  if (got != (size_t)len * 2) {
    Serial.printf("AC: đọc mã '%s' lỗi (got=%u byte)\n", key, (unsigned)got);
    return;
  }
  irsend.sendRaw(rawBuf, len, kIrFreqKhz);
  Serial.printf("AC: phát lệnh '%s' (len=%u)\n", key, len);
}

// ---- IR: bật chế độ học ----
void startLearn(const char *key) {
  strncpy(learnKey, key, sizeof(learnKey) - 1);
  learnKey[sizeof(learnKey) - 1] = 0;
  learning = true;
  learnUntilMs = millis() + LEARN_WINDOW_MS;
  irrecv.enableIRIn();
  Serial.printf("LEARN: mở học '%s' %lus — bấm nút remote hướng vào TSOP38238\n",
                key, (unsigned long)(LEARN_WINDOW_MS / 1000));
}

// ---- IR: xử lý trong loop khi đang học ----
void handleLearn() {
  if (!learning) return;

  if (millis() > learnUntilMs) {
    learning = false;
    irrecv.disableIRIn();
    Serial.println("LEARN: hết giờ, không nhận được tín hiệu hợp lệ");
    return;
  }
  if (!irrecv.decode(&results)) return;

  uint16_t len = getCorrectedRawLength(&results);
  if (len < kMinRawLen || len > kCaptureBufferSize) {
    Serial.printf("LEARN: tín hiệu không hợp lệ (len=%u), tiếp tục nghe\n", len);
    irrecv.resume();
    return;
  }

  uint16_t *raw = resultToRawArray(&results);
  if (raw == nullptr) {
    Serial.println("LEARN: cấp phát raw array lỗi");
    irrecv.resume();
    return;
  }

  char lenKey[12], rawKey[12];
  snprintf(lenKey, sizeof(lenKey), "%s_len", learnKey);
  snprintf(rawKey, sizeof(rawKey), "%s_raw", learnKey);
  prefs.begin("ac_codes", false /*read-write*/);
  prefs.putUShort(lenKey, len);
  prefs.putBytes(rawKey, raw, (size_t)len * 2);
  prefs.end();
  free(raw);

  Serial.printf("LEARN: đã lưu '%s' (len=%u) vào NVS\n", learnKey, len);
  learning = false;
  irrecv.disableIRIn();
}

// ---- Phân giải payload {"cmd":"on"} / {"button":"off"} ----
const char *parseOnOff(const String &payload) {
  if (payload.indexOf("\"off\"") >= 0) return "off";
  if (payload.indexOf("\"on\"")  >= 0) return "on";
  return nullptr;
}

void onMqtt(String &topic, String &payload) {
  Serial.printf("RECV %s %s\n", topic.c_str(), payload.c_str());
  const char *v = parseOnOff(payload);
  if (v == nullptr) {
    Serial.println("  -> payload không có on/off, bỏ qua");
    return;
  }
  if (topic == TOPIC_AC_CMD)        sendAC(v);
  else if (topic == TOPIC_AC_LEARN) startLearn(v);
}

// Nạp firmware qua WiFi — S2 Mini là board đau nhất khi nạp USB: phải vào bootloader
// bằng tay (giữ BOOT + tap RST), port lại nhảy ACM0/ACM1. OTA bỏ hẳn khoản đó.
// USB vẫn là đường lui nếu bản nạp làm chết WiFi.
//
// Dùng partition mặc định: đã sẵn otadata + app0/app1, không phải đổi bảng partition.
void setupOTA() {
  ArduinoOTA.setHostname(OTA_HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASSWORD);

  ArduinoOTA.onStart([]() {
    // Nhả IR receiver: nó chạy bằng ngắt timer, để nguyên sẽ chen vào lúc ghi flash.
    irrecv.disableIRIn();
    Serial.println("\n[ota] bắt đầu");
  });
  ArduinoOTA.onEnd([]() { Serial.println("\n[ota] xong — khởi động lại"); });
  ArduinoOTA.onProgress([](unsigned int cur, unsigned int total) {
    Serial.printf("[ota] %u%%\r", (cur * 100) / total);
  });
  ArduinoOTA.onError([](ota_error_t err) {
    // Hỏng giữa chừng: slot kia còn nguyên bản cũ, board reboot về bản cũ.
    Serial.printf("\n[ota] LỖI %u — giữ firmware cũ, nạp USB nếu cần\n", err);
  });

  ArduinoOTA.begin();
  Serial.printf("[ota] sẵn sàng: %s @ %s\n", OTA_HOSTNAME, WiFi.localIP().toString().c_str());
}

void setup() {
  Serial.begin(115200);
  // S2 dùng USB CDC gốc: chờ host mở cổng (tối đa 2s) để không mất log boot
  uint32_t serialWait = millis();
  while (!Serial && millis() - serialWait < 2000) delay(10);
  delay(200);

  pinMode(PIN_PRESENCE, INPUT);
  irsend.begin();  // IR receiver chỉ bật khi học (startLearn)

  connectWiFi();
  setupOTA();  // ngay sau khi có IP — OTA là đường cứu khi phần còn lại lỗi
  configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC epoch
  mqtt.begin(MQTT_HOST, MQTT_PORT, net);
  mqtt.onMessage(onMqtt);
  connectMQTT();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  ArduinoOTA.handle();  // rẻ khi rảnh; chỉ chặn lúc đang nạp thật
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  handleLearn();

  uint32_t now = millis();

  // Poll radar mỗi 200ms + state machine presence theo radar (VÀO khi giữ đủ lâu, RA sau debounce)
  if (now - lastPollMs >= 200) {
    lastPollMs = now;
    bool radar = (digitalRead(PIN_PRESENCE) == HIGH);

    if (radar) {
      lastRadarHighMs = now;
      radarEverHigh = true;
      if (radarFirstHighMs == 0) radarFirstHighMs = now;
    } else {
      radarFirstHighMs = 0;  // chuỗi HIGH bị ngắt, reset mốc bắt đầu
    }

    if (!occupied) {
      // VÀO khi radar giữ HIGH liên tục đủ lâu
      if (radar && radarFirstHighMs != 0 && now - radarFirstHighMs >= PRESENCE_HOLD_MS) {
        occupied = true;
        publishPresence(true);
      }
    } else {
      // RA khi radar không còn thấy (kể cả debounce chống rung)
      bool radarRecent = radar || (radarEverHigh && now - lastRadarHighMs < RADAR_DEBOUNCE_MS);
      if (!radarRecent) {
        occupied = false;
        publishPresence(false);
      }
    }
  }

  // Heartbeat: in trạng thái radar/occupied mỗi STATUS_HEARTBEAT_MS để quan sát live khi bench-test.
  static uint32_t lastHeartbeatMs = 0;
  if (STATUS_HEARTBEAT_MS && now - lastHeartbeatMs >= STATUS_HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    bool radarNow = (digitalRead(PIN_PRESENCE) == HIGH);
    Serial.printf("[hb] radar=%d occupied=%d sinceRadarHigh=%lus wifi=%d mqtt=%d\n",
                  radarNow, occupied,
                  radarEverHigh ? (unsigned long)((now - lastRadarHighMs) / 1000) : 9999UL,
                  WiFi.status() == WL_CONNECTED, mqtt.connected());
  }

  delay(5);
}
