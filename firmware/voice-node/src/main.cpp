// Voice node — ESP32-WROOM-32 (38 chân) + mic INMP441 (I2S)
// Đọc mic liên tục, tính RMS mỗi buffer làm VAD năng lượng ngay trên board:
// có tiếng -> mở stream binary PCM16 qua WebSocket tới backend ASR; im lặng
// một khoảng -> ngừng gửi (không đóng WS) để backend không phải nhận rác lúc
// không ai nói. WROOM-32 không có PSRAM nên không chạy nhận-lệnh offline —
// toàn bộ ASR nằm ở backend, board chỉ có nhiệm vụ stream audio sạch.
//
// Wiring thật (INMP441 -> WROOM-32), xem docs/system-wiring.md:
//   SCK (BCLK) -> GPIO26     WS (LRCL) -> GPIO25     SD (DOUT) -> GPIO34 (input-only)
//   L/R -> GND (chọn kênh trái)     VDD -> 3V3     GND -> GND
//
// Contract stream (đã chốt cùng backend Phase 2):
//   WS binary frame = PCM 16-bit 16kHz mono little-endian, gửi tới
//   ws://<backend>:8080/api/voice/stream — backend tự cắt utterance theo
//   khoảng lặng đọc được (read-deadline), node chỉ cần NGỪNG GỬI khi im lặng.

#include <Arduino.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <WebSocketsClient.h>
#include <MQTT.h>
#include <esp_now.h>
#include <ir_Daikin.h>
#include <driver/i2s.h>
#include <sys/time.h>
#include <math.h>

#include "config.h"

// ---- Phần cứng (WROOM-32) ----
static const uint8_t PIN_I2S_SCK = 26;  // BCLK, output từ ESP
static const uint8_t PIN_I2S_WS  = 25;  // LRCL/WS, output từ ESP
static const uint8_t PIN_I2S_SD  = 34;  // DOUT từ mic, input-only trên WROOM-32

// PIR chuyển từ room-node sang đây (quyết định 2026-07-16): fusion PIR+radar dời
// về backend. Chân GPIO27 an toàn (không strapping, hỗ trợ pulldown + interrupt).
//   IN (OUT tín hiệu PIR) -> GPIO27     5V -> 5V/VIN     GND -> GND
//   ⚠️ Đo áp OUT trước: 3.3V cắm thẳng; 5V phải chia áp trước GPIO27 (max 3.3V).
static const uint8_t PIN_PIR = 27;

// ---- MQTT ----
static const char    *TOPIC_MOTION = "home/door/motion";  // giữ nguyên contract Phase 2
static const uint32_t MOTION_PUBLISH_THROTTLE_MS = 1000;   // chống flood khi PIR kích liên tục

// ---- IR điều hoà Daikin (GPIO4) ----
// KHÔNG dùng GPIO5 như room-node cũ: trên WROOM-32, GPIO5 là chân strapping (phải HIGH
// lúc boot) -> đèn IR kéo xuống LOW là board không boot. GPIO4 không phải strapping.
// (Strapping ESP32 theo tài liệu ESP-IDF: GPIO0, 2, 5, 12, 15.)
static const uint16_t PIN_IR_SEND = 4;

// Daikin gửi TRỌN 35 byte trạng thái mỗi lần (kDaikinStateLength=35) — không có "lệnh bật"
// riêng lẻ. Nên khi tự bật phải set đủ nhiệt/chế độ/quạt, đây là mặc định hợp lý.
static const float   AC_DEFAULT_TEMP = 25.0f;
static const uint8_t AC_DEFAULT_MODE = kDaikinCool;
static const uint8_t AC_DEFAULT_FAN  = kDaikinFanAuto;

static const char *TOPIC_AC_CMD   = "home/room/ac_cmd";
static const char *TOPIC_PRESENCE = "home/room/presence";  // relay hộ room-node

// ---- ESP-NOW nhận radar từ room-node ----
static const uint8_t  MSG_MAGIC = 0xA7;
// Heartbeat bên gửi 5s -> lỡ 3 nhịp thì coi link chết. KHÔNG có timeout này, room-node
// chết lúc đang "có người" sẽ làm điều hoà chạy vĩnh viễn.
static const uint32_t RADAR_LINK_TIMEOUT_MS = 15000;

// Phải GIỐNG HỆT struct bên room-node. packed vì 2 board khác kiến trúc (S2 vs ESP32).
typedef struct __attribute__((packed)) {
  uint8_t  magic;
  uint8_t  present;
  uint32_t seq;
} RadarMsg;

// ---- Fusion tại board (luật copy từ backend/internal/statemachine/machine.go) ----
static const uint32_t ENTER_WINDOW_MS = 15000;  // khớp ENTER_WINDOW_S=15
static const uint32_t EXIT_TIMEOUT_MS = 60000;  // khớp EXIT_TIMEOUT_S=60
static const uint32_t STATUS_HEARTBEAT_MS = 2000;

static const i2s_port_t I2S_PORT     = I2S_NUM_0;
static const uint32_t   SAMPLE_RATE  = 16000;   // đúng contract backend

// Mỗi lần đọc lấy 256 mẫu 32-bit (~16ms @16kHz) — đủ nhỏ để không tràn RAM,
// đủ lớn để không spam quá nhiều gói WS nhỏ.
static const size_t I2S_READ_SAMPLES = 256;

// VAD năng lượng: ngưỡng RMS cố định, CẦN TUNE thực địa (phụ thuộc mic, gain,
// tiếng ồn nền quạt/AC — xem risk trong plan). im lặng SILENCE_MS liên tục
// mới coi là hết câu, tránh cắt giữa câu do ngắt quãng ngắn.
// Sau khi nâng gain (MIC_SHIFT=11), biên độ ~32x so với >>16 cũ -> RMS nền ~160-1200, tiếng nói
// ~4800-8000. Ngưỡng 2500 tách tiếng nói khỏi nhiễu nền + giảm gửi đoạn gần-im (bớt ảo giác ASR).
static const float    VAD_THRESHOLD = 2500.0f;
static const uint32_t SILENCE_MS    = 800;

// MIC_SHIFT: INMP441 để tín hiệu ~2% full-scale khi >>16 -> whisper đoán mò. >>11 đẩy lên ~50-67%
// full-scale (kèm clamp chống tràn int16). Giảm shift = to hơn nhưng dễ clip; tăng = nhỏ hơn.
static const uint8_t  MIC_SHIFT     = 11;

WebSocketsClient webSocket;

WiFiClient  net;              // TCP riêng cho MQTT (WebSocket dùng client nội bộ của lib)
MQTTClient  mqtt(256);        // buffer nhỏ — chỉ publish motion payload ngắn

static int32_t i2sRawBuf[I2S_READ_SAMPLES];  // dữ liệu thô từ I2S (32-bit slot)
static int16_t pcmBuf[I2S_READ_SAMPLES];     // PCM16 sau khi hạ bit, gửi thẳng qua WS

bool     streaming   = false;  // đang trong một utterance -> có gửi frame
uint32_t lastVoiceMs = 0;      // lần cuối RMS vượt ngưỡng
uint32_t lastLogMs   = 0;      // throttle log Serial, tránh spam mỗi ~16ms

volatile bool motionFlag = false;  // set trong ISR PIR, tiêu thụ trong loop() — KHÔNG gọi MQTT trong ISR
uint32_t lastMotionPublishMs   = 0;
bool     firstMotionPublishDone = false;

// ---- Trạng thái ESP-NOW / fusion ----
// Set trong callback ESP-NOW (chạy ở WiFi task, KHÔNG phải ISR) — chỉ ghi biến đơn giản,
// mọi việc nặng (MQTT, IR) làm trong loop().
volatile bool     radarPresent = false;
volatile uint32_t lastRadarMs  = 0;   // millis() lần nhận cuối; 0 = chưa từng nhận
volatile uint32_t lastRadarSeq = 0;

bool     present       = false;  // radar còn sống VÀ đang thấy người
bool     occupied      = false;  // kết luận fusion (radar + PIR)
uint32_t lastMotionMs  = 0;      // lần PIR kích gần nhất
uint32_t falseSinceMs  = 0;      // lúc present chuyển false (đếm EXIT_TIMEOUT)
bool     presencePublished = false;  // đã publish presence lần nào chưa (ghi đè retained cũ)
uint32_t lastHeartbeatMs = 0;

IRDaikin2 ac(PIN_IR_SEND);   // thử biến thể 2 (312-bit) — IRDaikinESP (280-bit) không ăn

// ISR: chỉ set cờ. Client MQTT không interrupt-safe.
void IRAM_ATTR onMotion() {
  motionFlag = true;
}

// ---- Thời gian epoch (ms) cho payload; 0 nếu NTP chưa sync ----
uint64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 100000) return 0;
  return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;
}

// ---- WiFi: kết nối + tự thử lại, không treo loop khi mất mạng ----
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

// ---- MQTT: kết nối broker, tự thử lại (không chặn quá lâu để không nghẽn audio) ----
void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqtt.connected()) return;
  Serial.print("MQTT: nối broker");
  for (uint8_t i = 0; i < 3 && !mqtt.connected(); i++) {
    if (mqtt.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASS)) break;
    Serial.print(".");
    delay(500);
    if (WiFi.status() != WL_CONNECTED) { Serial.println(" mất WiFi"); return; }
  }
  Serial.println(mqtt.connected() ? " OK" : " FAIL (thử lại sau)");
  // Subscribe PHẢI nằm trong hàm connect: subscription mất khi rớt kết nối, đặt ở setup()
  // thì sau reconnect đầu tiên là điếc vĩnh viễn.
  if (mqtt.connected()) {
    mqtt.subscribe(TOPIC_AC_CMD, 1);
    Serial.printf("MQTT: sub %s\n", TOPIC_AC_CMD);
  }
}

// ---- Publish home/door/motion khi PIR có cạnh lên (retain=false, QoS1) ----
// NTP đã có giờ thật chưa. Contract MQTT: ts là epoch MILI-giây; publish khi chưa sync sẽ
// đẩy ts=0 lên broker và backend ghi vĩnh viễn vào lịch sử -> app hiện 1970.
bool ntpReady() { return epochMs() > 0; }

// Callback ESP-NOW: chạy trong ngữ cảnh WiFi task (KHÔNG phải ISR). Chỉ ghi biến đơn giản
// — mọi việc nặng (MQTT, IR, Serial dài) làm trong loop().
// Chữ ký theo API ESP-NOW của core này (const uint8_t *mac). Bản IDF mới hơn đổi tham số
// đầu thành esp_now_recv_info_t* — nếu nâng core mà build gãy ở đây thì là chỗ cần sửa.
void onRadarRecv(const uint8_t *mac, const uint8_t *data, int len) {
  if (len != sizeof(RadarMsg)) return;        // gói lạ trên cùng kênh
  RadarMsg msg;
  memcpy(&msg, data, sizeof(msg));
  if (msg.magic != MSG_MAGIC) return;

  radarPresent = msg.present != 0;
  lastRadarSeq = msg.seq;
  lastRadarMs  = millis();                    // 32-bit -> ghi/đọc nguyên tử trên ESP32
}

void setupEspNow() {
  // Gọi SAU connectWiFi(): ESP-NOW chạy trên kênh mà WiFi STA đã chốt. room-node phải
  // quét SSID để dò tới đúng kênh này — sai kênh thì gói bay vào hư không, không báo lỗi.
  if (esp_now_init() != ESP_OK) {
    Serial.println("[espnow] init LỖI");
    return;
  }
  esp_now_register_recv_cb(onRadarRecv);
  Serial.printf("[espnow] MAC board này: %s  (điền vào ESPNOW_PEER_MAC của room-node)\n",
                WiFi.macAddress().c_str());
  Serial.printf("[espnow] đang ở kênh %d — room-node phải dò tới đúng kênh này\n",
                WiFi.channel());
}

// Relay presence hộ room-node (nó bỏ WiFi, chỉ còn ESP-NOW).
// retain=true: backend restart phải đọc lại được trạng thái hiện tại, không thì nó mù cho
// tới lần đổi tiếp theo (có thể hàng giờ). Đây cũng là thứ GHI ĐÈ retained message cũ mà
// room-node bản trước để lại trên broker.
void publishPresence(bool p) {
  if (!ntpReady()) return;  // thà hoãn còn hơn ghi ts=0 vào lịch sử vĩnh viễn
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%llu,\"present\":%s}",
           (unsigned long long)epochMs(), p ? "true" : "false");
  bool ok = mqtt.connected() &&
            mqtt.publish(TOPIC_PRESENCE, payload, true /*retain*/, 1 /*qos*/);
  Serial.printf("PUB %s %s -> %s\n", TOPIC_PRESENCE, payload, ok ? "ok" : "fail");
  if (ok) presencePublished = true;
}

// Bắn lệnh điều hoà Daikin.
// Daikin gửi TRỌN 35 byte trạng thái mỗi lần (kDaikinStateLength=35) — không có "lệnh bật"
// riêng. Nên bật thì phải set đủ nhiệt/chế độ/quạt, không chỉ power.
void sendAC(bool on) {
  ac.setPower(on);
  if (on) {
    ac.setMode(AC_DEFAULT_MODE);
    ac.setTemp(AC_DEFAULT_TEMP);
    ac.setFan(AC_DEFAULT_FAN);
  }
  ac.send();
  Serial.printf("[ir] Daikin %s (%.0fC)\n", on ? "ON" : "OFF", AC_DEFAULT_TEMP);
}

// Lệnh tay từ app (/api/ac) và voice (whisper -> ParseVietCommand) đều tới qua topic này.
void onMqtt(String &topic, String &payload) {
  if (topic != TOPIC_AC_CMD) return;
  if (payload.indexOf("\"on\"") >= 0) {
    sendAC(true);
  } else if (payload.indexOf("\"off\"") >= 0) {
    sendAC(false);
  } else {
    Serial.printf("[ir] ac_cmd không hiểu: %s\n", payload.c_str());
  }
}

void publishMotion() {
  if (!ntpReady()) return;  // đừng đẩy ts=0 vào lịch sử
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%llu,\"motion\":true}",
           (unsigned long long)epochMs());
  bool ok = mqtt.connected() &&
            mqtt.publish(TOPIC_MOTION, payload, false /*retain*/, 1 /*qos*/);
  Serial.printf("PUB %s %s -> %s\n", TOPIC_MOTION, payload, ok ? "ok" : "fail");
}

// ---- Init I2S RX: 16kHz, slot 32-bit, mono kênh trái (INMP441 L/R->GND) ----
void setupI2S() {
  i2s_config_t i2sConfig = {
      .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
      .sample_rate = SAMPLE_RATE,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,  // INMP441 xuất 24-bit trong khung 32-bit
      .channel_format = I2S_CHANNEL_FMT_ONLY_RIGHT,  // INMP441 L/R->GND đẩy slot trái; driver I2S legacy ESP32 đảo LEFT/RIGHT -> phải chọn ONLY_RIGHT mới đọc đúng (nếu vẫn 0.0 thử lại ONLY_LEFT + kiểm hàn SD/SCK/WS)
      .communication_format = I2S_COMM_FORMAT_STAND_I2S,
      .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
      .dma_buf_count = 8,
      .dma_buf_len = 256,
      .use_apll = false,
      .tx_desc_auto_clear = false,
      .fixed_mclk = 0,
  };
  i2s_pin_config_t pinConfig = {
      .bck_io_num = PIN_I2S_SCK,
      .ws_io_num = PIN_I2S_WS,
      .data_out_num = I2S_PIN_NO_CHANGE,  // chỉ RX, không dùng chân data_out
      .data_in_num = PIN_I2S_SD,
  };

  esp_err_t err = i2s_driver_install(I2S_PORT, &i2sConfig, 0, nullptr);
  if (err != ESP_OK) {
    Serial.printf("I2S: cài driver lỗi (%d)\n", err);
    return;
  }
  err = i2s_set_pin(I2S_PORT, &pinConfig);
  if (err != ESP_OK) {
    Serial.printf("I2S: set pin lỗi (%d)\n", err);
    return;
  }
  i2s_zero_dma_buffer(I2S_PORT);
  Serial.println("I2S: sẵn sàng đọc INMP441 (16kHz, mono trái, slot 32-bit)");
}

// ---- Tính RMS trên buffer PCM16 để làm VAD năng lượng ----
float computeRms(const int16_t *buf, size_t n) {
  if (n == 0) return 0.0f;
  double sumSq = 0.0;
  for (size_t i = 0; i < n; i++) {
    sumSq += (double)buf[i] * (double)buf[i];
  }
  return (float)sqrt(sumSq / (double)n);
}

// ---- Log trạng thái WS (không gọi logic nghiệp vụ ở đây, chỉ debug) ----
void onWsEvent(WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      Serial.println("WS: đã kết nối backend /api/voice/stream");
      break;
    case WStype_DISCONNECTED:
      Serial.println("WS: mất kết nối backend, tự thử lại theo reconnect interval");
      break;
    case WStype_ERROR:
      Serial.println("WS: lỗi kết nối");
      break;
    default:
      break;  // không quan tâm TEXT/PING/PONG — node chỉ gửi BIN
  }
}

// Nạp firmware qua WiFi — bỏ hẳn cảnh usbipd attach + port nhảy + (khi 2 board dùng
// chung nguồn) phải tháo dây 5V mỗi lần nạp. USB vẫn là đường lui: bản nào làm chết
// WiFi thì OTA bó tay.
//
// Dùng partition mặc định (default.csv): đã sẵn otadata + app0/app1 (mỗi slot 1.25MB),
// không phải đổi bảng partition.
void setupOTA() {
  ArduinoOTA.setHostname(OTA_HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASSWORD);  // không để bất kỳ ai cùng LAN nạp firmware vào nhà

  // I2S và WebSocket phải nhả TRƯỚC khi ghi flash: i2s_read đang chạy sẽ tranh CPU với
  // tác vụ ghi, còn WS giữ socket mở dễ làm timeout giữa chừng -> bản nạp hỏng.
  ArduinoOTA.onStart([]() {
    Serial.println("\n[ota] bắt đầu — dừng I2S + WS");
    streaming = false;
    webSocket.disconnect();
    i2s_stop(I2S_PORT);
    i2s_driver_uninstall(I2S_PORT);
  });
  ArduinoOTA.onEnd([]() { Serial.println("\n[ota] xong — khởi động lại"); });
  ArduinoOTA.onProgress([](unsigned int cur, unsigned int total) {
    Serial.printf("[ota] %u%%\r", (cur * 100) / total);
  });
  ArduinoOTA.onError([](ota_error_t err) {
    // Nạp hỏng giữa chừng: bản cũ ở slot kia vẫn nguyên, board reboot về bản cũ.
    Serial.printf("\n[ota] LỖI %u — giữ nguyên firmware cũ, nạp lại qua USB nếu cần\n", err);
  });

  ArduinoOTA.begin();
  Serial.printf("[ota] sẵn sàng: %s @ %s\n", OTA_HOSTNAME, WiFi.localIP().toString().c_str());
}

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(PIN_PIR, INPUT_PULLDOWN);  // PIR đẩy HIGH chủ động; pulldown giữ LOW khi chưa nối
  attachInterrupt(digitalPinToInterrupt(PIN_PIR), onMotion, RISING);

  connectWiFi();
  setupOTA();     // sau connectWiFi (cần IP), trước I2S để lỡ I2S treo vẫn OTA cứu được
  setupEspNow();  // sau connectWiFi: ESP-NOW bám kênh mà WiFi STA đã chốt
  ac.begin();     // IR Daikin (GPIO4)
  configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC epoch cho ts motion/presence
  setupI2S();

  webSocket.begin(BACKEND_WS_HOST, BACKEND_WS_PORT, BACKEND_WS_PATH);
  webSocket.onEvent(onWsEvent);
  webSocket.setReconnectInterval(3000);  // tự thử lại mỗi 3s nếu rớt kết nối

  mqtt.begin(MQTT_HOST, MQTT_PORT, net);
  mqtt.onMessage(onMqtt);
  connectMQTT();
}

// Gộp radar (qua ESP-NOW) + PIR (local) -> occupied -> bắn IR.
// Luật copy nguyên từ backend/internal/statemachine/machine.go để 2 nơi không lệch ngữ nghĩa.
void updateFusion(uint32_t now) {
  // Link chết -> coi như KHÔNG có người. Không có timeout này, room-node chết lúc đang
  // "có người" sẽ làm điều hoà chạy vĩnh viễn.
  uint32_t lastMs = lastRadarMs;
  bool radarAlive = lastMs != 0 && (now - lastMs) < RADAR_LINK_TIMEOUT_MS;
  bool p = radarAlive && radarPresent;

  if (p != present) {
    present = p;
    if (!present) falseSinceMs = now;
    publishPresence(present);
  } else if (!presencePublished && ntpReady()) {
    // Publish lần đầu sau khi NTP sẵn sàng: ghi đè retained message CŨ mà bản room-node
    // trước để lại trên broker (nếu không, backend restart đọc phải trạng thái nhiều giờ trước).
    publishPresence(present);
  }

  bool before = occupied;
  // Vào: radar thấy người VÀ có chuyển động gần đây (chống radar báo giả xuyên tường).
  if (present && !occupied) {
    if (lastMotionMs != 0 && now - lastMotionMs <= ENTER_WINDOW_MS) occupied = true;
  }
  // Ra: radar im đủ lâu.
  if (occupied && !present && falseSinceMs != 0) {
    if (now - falseSinceMs >= EXIT_TIMEOUT_MS) occupied = false;
  }

  if (occupied != before) {
    Serial.printf("[fusion] occupied -> %d\n", occupied);
    sendAC(occupied);
  }
}

void loop() {
  uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  ArduinoOTA.handle();  // rẻ khi rảnh (chỉ ngó gói UDP); chỉ chặn lúc đang nạp thật
  webSocket.loop();  // bơm sự kiện WS + xử lý reconnect nội bộ của lib

  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();  // keepalive MQTT (i2s_read timeout 200ms đảm bảo gọi đủ thường)

  // Tiêu thụ cờ PIR (ISR set) — nơi an toàn duy nhất để gọi MQTT.
  if (motionFlag) {
    motionFlag = false;
    lastMotionMs = now;  // mốc cho fusion (ENTER_WINDOW), độc lập với throttle publish
    bool outsideThrottle = now - lastMotionPublishMs >= MOTION_PUBLISH_THROTTLE_MS;
    if (!firstMotionPublishDone || outsideThrottle) {
      lastMotionPublishMs = now;
      firstMotionPublishDone = true;
      publishMotion();
    }
  }

  updateFusion(now);

  if (STATUS_HEARTBEAT_MS && now - lastHeartbeatMs >= STATUS_HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    uint32_t lastMs = lastRadarMs;
    Serial.printf("[hb] radar=%d link=%s motion=%lus present=%d occupied=%d seq=%lu wifi=%d mqtt=%d\n",
                  radarPresent ? 1 : 0,
                  (lastMs != 0 && now - lastMs < RADAR_LINK_TIMEOUT_MS) ? "up" : "DOWN",
                  lastMotionMs ? (unsigned long)((now - lastMotionMs) / 1000) : 0UL,
                  present, occupied, (unsigned long)lastRadarSeq,
                  WiFi.status() == WL_CONNECTED, mqtt.connected());
  }

  // Đọc I2S có timeout — không dùng portMAX_DELAY để tránh treo loop nếu
  // mic/driver có vấn đề; timeout hết thì bỏ qua vòng này, thử lại vòng sau.
  size_t bytesRead = 0;
  esp_err_t err = i2s_read(I2S_PORT, i2sRawBuf, sizeof(i2sRawBuf), &bytesRead, pdMS_TO_TICKS(200));
  if (err != ESP_OK || bytesRead == 0) return;

  size_t samples = bytesRead / sizeof(int32_t);
  // INMP441 xuất dữ liệu MSB-aligned trong khung 32-bit -> lấy 16-bit cao
  // là cách đơn giản nhất để có PCM16 hợp lệ (tune lại nếu âm lượng sai lệch
  // thực địa — xem risk trong plan).
  for (size_t i = 0; i < samples; i++) {
    int32_t s = i2sRawBuf[i] >> MIC_SHIFT;   // khuếch đại so với >>16 để whisper nghe rõ
    if (s > 32767) s = 32767;                // clamp chống tràn int16 khi tiếng to
    else if (s < -32768) s = -32768;
    pcmBuf[i] = (int16_t)s;
  }

  float rms = computeRms(pcmBuf, samples);

  if (rms > VAD_THRESHOLD) {
    if (!streaming) Serial.println("VAD: phát hiện tiếng nói -> bắt đầu stream");
    streaming = true;
    lastVoiceMs = now;
  }

  if (streaming) {
    if (webSocket.isConnected()) {
      webSocket.sendBIN(reinterpret_cast<uint8_t *>(pcmBuf), samples * sizeof(int16_t));
    }
    if (now - lastVoiceMs > SILENCE_MS) {
      // Kết thúc utterance: NGỪNG gửi frame, KHÔNG đóng WS — giữ kết nối để
      // câu tiếp theo gửi ngay, không tốn thời gian bắt tay lại.
      streaming = false;
      Serial.println("VAD: im lặng -> kết thúc utterance (ngừng gửi, giữ WS mở)");
    }
  }

  // Log định kỳ (không phải mỗi vòng ~16ms) để debug RMS/streaming qua Serial.
  if (now - lastLogMs >= 500) {
    lastLogMs = now;
    Serial.printf("RMS=%.1f streaming=%s ws=%s\n", rms, streaming ? "true" : "false",
                  webSocket.isConnected() ? "up" : "down");
  }
}
