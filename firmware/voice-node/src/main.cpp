// Voice node — ESP32-S3 (env esp32s3) hoặc ESP32-WROOM-32 (env esp32dev) + mic INMP441 (I2S)
// Đọc mic liên tục, tính RMS mỗi buffer làm VAD năng lượng ngay trên board:
// có tiếng -> mở stream binary PCM16 qua WebSocket tới backend ASR; im lặng
// một khoảng -> ngừng gửi (không đóng WS) để backend không phải nhận rác lúc
// không ai nói. Toàn bộ ASR nằm ở backend, board chỉ có nhiệm vụ stream audio
// sạch — nên không cần PSRAM và chạy được trên cả hai board.
//
// Wiring thật (INMP441), xem docs/system-wiring.md. Số chân I2S khác nhau giữa
// hai board nên lấy từ build_flags, xem khối CFG_I2S_* bên dưới:
//               SCK (BCLK)   WS (LRCL)   SD (DOUT)
//   WROOM-32      GPIO26       GPIO25      GPIO34 (input-only)
//   ESP32-S3      GPIO5        GPIO6       GPIO7
// Chung cho cả hai:  L/R -> GND     VDD -> 3V3     GND -> GND
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
#include <ir_Daikin.h>
#include <driver/i2s.h>
#include <driver/gpio.h>       // gpio_set_pull_mode() — pulldown chân SD của mic, xem setupI2S()
#include <math.h>
#include <esp_system.h>        // esp_reset_reason() — chẩn đoán lý do reset (9 = BROWNOUT)

#include "config.h"

// ---- Phần cứng ----
// Mặc định là số chân của WROOM-32; env S3 ghi đè qua build_flags. Bản đồ GPIO của
// ESP32-S3 khác hẳn ESP32 gốc: dải 22-25 KHÔNG tồn tại, 26-32 là bus SPI flash,
// 33-37 dành cho PSRAM octal. Cả ba chân I2S mặc định đều rơi vào vùng cấm đó.
#ifndef CFG_I2S_SCK
#define CFG_I2S_SCK 26
#endif
#ifndef CFG_I2S_WS
#define CFG_I2S_WS  25
#endif
#ifndef CFG_I2S_SD
#define CFG_I2S_SD  34
#endif
static const uint8_t PIN_I2S_SCK = CFG_I2S_SCK;  // BCLK, output từ ESP
static const uint8_t PIN_I2S_WS  = CFG_I2S_WS;   // LRCL/WS, output từ ESP
static const uint8_t PIN_I2S_SD  = CFG_I2S_SD;   // DOUT từ mic (trên WROOM-32 là chân input-only)

// ---- IR điều hoà Daikin ----
// KHÔNG dùng chân strapping: nó phải ở mức đúng lúc boot, mà đèn IR kéo chân xuống LOW là
// board không boot. (Strapping ESP32: GPIO0, 2, 5, 12, 15.  ESP32-S3: GPIO0, 3, 45, 46.)
// Mặc định GPIO4 — ngoài cả hai danh sách, dùng được cho cả hai board.
// env esp32s3 ghi đè sang GPIO8: trên board S3-CAM, GPIO4-7 nằm ở header camera với khoảng
// cách chân rất hẹp, hàn tay khó; GPIO8 ở hàng GPIO thường nên thoáng hơn. GPIO8 không phải
// strapping, không thuộc bus flash (26-32) hay PSRAM octal (33-37) của bản N16R8.
#ifndef CFG_IR_PIN
#define CFG_IR_PIN 4
#endif
static const uint16_t PIN_IR_SEND = CFG_IR_PIN;

// Daikin gửi TRỌN 35 byte trạng thái mỗi lần (kDaikinStateLength=35) — không có "lệnh bật"
// riêng lẻ. Nên khi tự bật phải set đủ nhiệt/chế độ/quạt, đây là mặc định hợp lý.
static const float   AC_DEFAULT_TEMP = 25.0f;
static const uint8_t AC_DEFAULT_MODE = kDaikinCool;
static const uint8_t AC_DEFAULT_FAN  = kDaikinFanAuto;

static const char *TOPIC_AC_CMD   = "home/room/ac_cmd";
// SUBSCRIBE (không publish) — nguồn presence duy nhất là radar-node.
static const char *TOPIC_PRESENCE = "home/room/presence";

// ---- Nguồn radar: radar-node publish home/room/presence ----
// voice-node chỉ NGHE topic này ({"ts","present"}); mọi lọc tinh (cự ly/năng lượng,
// chống báo giả xuyên tường) nằm ở radar-node / cấu hình LD2410. Không đọc SENSOR, không poll.
// Không nhận presence quá lâu -> coi link radar-node chết -> coi như KHÔNG có người (đừng
// để điều hoà chạy vĩnh viễn khi radar-node rớt). radar-node heartbeat presence mỗi 30s
// nên 90s là thừa an toàn.
static const uint32_t RADAR_LINK_TIMEOUT_MS = 90000;

// ---- Chính sách AC tại board (ESP32 là bộ não) ----
// Vào: presence giữ LIÊN TỤC đủ lâu -> bật AC. Ra: vắng đủ lâu -> tắt AC.
static const uint32_t ENTER_STABLE_MS = 800;    // thấy người liên tục 0.8s là occupied
static const uint32_t EXIT_TIMEOUT_MS = 60000;  // vắng 60s mới tắt (khớp EXIT_TIMEOUT_S=60)

// Khe hở tối thiểu giữa hai lần bắn IR. Một khung Daikin dài ~150ms và ac.send() CHẶN suốt thời
// gian đó, kéo dòng lên cao liên tục — đo thực địa 30/07: 5V tụt từ 4,6V xuống 4,0V khi bắn, và
// bắn dồn là kịch bản đã làm chết con WROOM. Nhiều nguồn có thể sinh lệnh sát nhau: một câu nói bị
// hai tầng VAD băm thành nhiều utterance giống nhau, trùng lặp do MQTT QoS 1 sau reconnect, nút
// trong app bấm liên tục, và fusion occupancy. Nhịp này là chốt cuối cho MỌI nguồn đó.
static const uint32_t IR_MIN_GAP_MS = 1500;

// Sau khi có lệnh tay (giọng nói / app), fusion occupancy KHÔNG được tự ghi đè trong khoảng này.
// Nếu không có: user nói "tắt điều hòa" trong lúc phòng vẫn có người, rồi presence chớp một nhịp
// là fusion bắn lại "bật" và phủ quyết ý người dùng. Backend statemachine đã có bảo vệ tương đương
// (xem prevOccupied trong internal/statemachine/machine.go); firmware trước đây thiếu.
static const uint32_t MANUAL_OVERRIDE_MS = 300000;  // 5 phút
static const uint32_t STATUS_HEARTBEAT_MS = 2000;

static const i2s_port_t I2S_PORT     = I2S_NUM_0;
static const uint32_t   SAMPLE_RATE  = 16000;   // đúng contract backend

// Kênh I2S để đọc INMP441. LƯU Ý QUAN TRỌNG: chân L/R của mic LUÔN nối GND và không bao giờ đổi —
// theo datasheet, nối GND là cách bảo mic đẩy dữ liệu vào nửa TRÁI của khung I2S. Hằng dưới đây chỉ
// chọn phía DRIVER đọc nửa nào, là chuyện hoàn toàn khác. Đổi cả dây lẫn hằng = đảo hai lần = vẫn sai.
//
// KHÔNG có giá trị đúng cho mọi board — lệch theo target và phiên bản IDF, phải thử. ONLY_RIGHT
// đúng cho CẢ HAI board đang dùng: đã thử ONLY_LEFT trên ESP32-S3 ngày 30/07 và đo RMS = 0.0
// tuyệt đối (mic không lái nửa trái). Kèm pulldown chân SD trong setupI2S(), số 0 đó là kết luận
// đáng tin chứ không phải "chưa có tín hiệu" — đó chính là lý do thêm pulldown.
#ifndef CFG_I2S_CHAN
#define CFG_I2S_CHAN I2S_CHANNEL_FMT_ONLY_RIGHT
#endif

// Mỗi lần đọc lấy 256 mẫu 32-bit (~16ms @16kHz) — đủ nhỏ để không tràn RAM,
// đủ lớn để không spam quá nhiều gói WS nhỏ.
static const size_t I2S_READ_SAMPLES = 256;

// VAD năng lượng, ngưỡng TƯƠNG ĐỐI theo nền nhiễu. Trước đây dùng hằng số tuyệt đối 2500 và nó
// hỏng: nền nhiễu trong phòng đo được nhảy từ ~250-1500 lên ~1500-2500 chỉ trong 40 phút, nên một
// con số cố định lúc thì bỏ sót tiếng nói, lúc thì mở utterance cho nhiễu. Nghiêm trọng hơn: hệ
// này sắp bật điều hòa bằng IR, tức TỰ tạo thêm tiếng ồn nền đúng lúc cần nghe lệnh "tắt điều hòa".
//
// Ngưỡng = max(nền × VAD_NOISE_MULT, VAD_THRESHOLD_MIN). Phòng yên thì ngưỡng tự hạ để bắt được
// câu nói nhỏ; phòng ồn thì tự nâng để khỏi mở cho nhiễu. Đổi MIC_SHIFT về sau KHÔNG cần tinh
// chỉnh lại, vì cả nền lẫn tiếng nói đều scale cùng hệ số — chỉ VAD_THRESHOLD_MIN phải scale theo.
static const float    VAD_NOISE_MULT     = 2.0f;
// Hệ số chỉ 2.0 (không phải 3-4) vì debounce VAD_ONSET_FRAMES đã lo phần gai nhiễu đơn lẻ; hệ số
// này chỉ cần lo mức duy trì. Đo thực địa: gai nhiễu đạt 2-3x nền nhưng gần như không bao giờ
// duy trì 3 frame liền, còn tiếng nói vượt 2x nền rất thoải mái.
// SÀN 150 -> 600 (31/07). Đo trên 66 utterance thu thật: nhiễu phòng RMS 90-250, giọng nói thật
// RMS 1200-3300 — hai dải cách nhau rất xa, mà sàn 150 (ngưỡng thực tế ~200 vì nền ~100) nằm ĐÚNG
// TRONG dải nhiễu. Hậu quả đo được: 45/66 utterance gửi lên whisper là nhiễu thuần, và whisper gặp
// nhiễu thì nhại lại initial_prompt. Một câu nhại THIẾU vế "tắt" ("Lệnh điều khiển điều hòa, bật
// máy lạnh.") chỉ chứa một động từ nên lớp loại-câu-mơ-hồ ở backend không bắt được -> đã publish
// cmd=on thật lúc 03:58:50 dù không ai nói gì.
// 600 nằm giữa hai dải, cách nhiễu ~2.4x và cách tiếng nói ~2x. Con số này gắn với MIC_SHIFT=13;
// đổi MIC_SHIFT thì phải scale sàn theo cùng hệ số.
static const float    VAD_THRESHOLD_MIN  = 600.0f;
static const float    NOISE_EMA_ALPHA    = 0.02f;   // ~50 frame (~0.8s) để nền theo kịp mà không giật
static const uint32_t SILENCE_MS         = 800;     // im đủ lâu mới coi hết câu, tránh cắt giữa câu

// Cần VAD_ONSET_FRAMES frame LIÊN TIẾP vượt ngưỡng mới mở utterance. Nhiễu nền chạm sát ngưỡng nên
// một gai đơn lẻ đủ mở stream -> khoảng 3/4 utterance gửi lên whisper chỉ là nhiễu, mà whisper gặp
// nhiễu thì ảo giác (đã thấy nó phun ra câu chào cuối video YouTube). Tiếng nói thật kéo dài nhiều
// frame liền nhau, gai nhiễu thì không -> debounce tách được hai loại.
static const uint8_t  VAD_ONSET_FRAMES = 3;

// Lọc thông cao một cực (DC blocker) ~80Hz, chạy ngay sau khi hạ bit và TRƯỚC khi clamp.
// INMP441 nhạy hạ tần rất mạnh: đo được clip có dc=-1562 và zcr=0.0028 (tương đương ~45Hz — không
// phải giọng người mà là tiếng ục/va chạm bàn/hơi bật khi nói gần). Năng lượng hạ tần đó gây ba
// tai hại cùng lúc: ăn hết headroom nên tiếng nói đập rìa (peak=32768), bơm phồng RMS nên VAD mở
// utterance cho những thứ whisper không đọc được, và tạo lệch DC. Cắt dưới 80Hz sửa cả ba, mà
// không chạm F0 của giọng người (nam ~100-150Hz, nữ ~200Hz).
//   y[n] = x[n] - x[n-1] + R*y[n-1],  R = 1 - 2*pi*fc/fs = 1 - 2*pi*80/16000
static const float    HPF_R = 0.9686f;

// MIC_SHIFT: INMP441 để tín hiệu ~2% full-scale khi >>16 -> whisper đoán mò, nên phải khuếch đại.
// Nhưng >>11 (~64% full-scale, -4 dBFS) KHÔNG còn headroom: đo được RMS 28954/32767 = 88% full-scale,
// mà sóng sin biên độ tối đa chỉ đạt RMS 70.7% -> dạng sóng đã bị clamp chặt phẳng thành sóng vuông.
// Whisper nghe sóng vuông chỉ thấy tiếng rè và trả về text rỗng: 29/31 utterance rỗng, và đúng những
// câu TO mới rỗng còn câu nhỏ vẫn nhận đúng. >>13 cho ~16% full-scale (-16 dBFS) — mức chuẩn cho ASR,
// còn ~16 dB dự phòng cho đỉnh. Giảm shift = to hơn nhưng clip; tăng = nhỏ hơn, whisper đoán mò.
static const uint8_t  MIC_SHIFT     = 13;

WebSocketsClient webSocket;

WiFiClient  net;              // TCP riêng cho MQTT (WebSocket dùng client nội bộ của lib)
MQTTClient  mqtt(512);        // payload presence/ac_cmd đều nhỏ (<128B)

static int32_t i2sRawBuf[I2S_READ_SAMPLES];  // dữ liệu thô từ I2S (32-bit slot)
static int16_t pcmBuf[I2S_READ_SAMPLES];     // PCM16 sau khi hạ bit, gửi thẳng qua WS

bool     streaming   = false;  // đang trong một utterance -> có gửi frame
uint32_t lastVoiceMs = 0;      // lần cuối RMS vượt ngưỡng
uint32_t lastLogMs   = 0;      // throttle log Serial, tránh spam mỗi ~16ms
uint8_t  onsetFrames = 0;      // số frame liên tiếp đang vượt ngưỡng, chờ đủ VAD_ONSET_FRAMES
float    noiseFloor  = 0.0f;   // EMA nền nhiễu; 0 = chưa học, seed bằng frame đầu tiên đọc được

// Trạng thái bộ lọc thông cao — phải giữ qua các lần gọi, nếu reset mỗi frame thì mỗi ranh giới
// frame thành một bước nhảy và tự sinh ra tiếng tách 62.5Hz (16000/256).
float    hpfPrevX = 0.0f;      // x[n-1] — mẫu VÀO trước đó (chưa lọc)
float    hpfPrevY = 0.0f;      // y[n-1] — mẫu RA trước đó (đã lọc)

// Giữ lại frame trong lúc chờ xác nhận onset rồi gửi bù ngay khi mở stream. Không có đệm này
// thì debounce ăn mất (VAD_ONSET_FRAMES-1)*16ms đầu câu — đúng chỗ có phụ âm bật /b/, /t/ nên
// whisper sẽ nghe "ật điều hòa". Chỉ cần đệm đủ số frame bị giữ, ~1KB.
static int16_t preRoll[(VAD_ONSET_FRAMES - 1) * I2S_READ_SAMPLES];
static uint8_t preRollFrames = 0;

// ---- Trạng thái presence (nhận từ MQTT home/room/presence) ----
// Ghi trong onMqtt (chạy đồng bộ trong mqtt.loop() ở loop()), đọc trong loop().
bool     radarPresent = false;
uint32_t lastRadarMs  = 0;   // millis() lần nhận presence cuối; 0 = chưa từng nhận
uint32_t lastRadarSeq = 0;

bool     present       = false;  // radar-node còn sống VÀ đang báo có người
bool     occupied      = false;  // kết luận chính sách AC (present ổn định đủ lâu)
uint32_t falseSinceMs  = 0;      // lúc present chuyển false (đếm EXIT_TIMEOUT)
uint32_t presenceSinceMs = 0;    // lúc present chuyển true (đếm ENTER_STABLE)

// ---- Hàng chờ IR: MỘT ô trạng thái duy nhất, gửi có nhịp trong loop() ----
// Một ô (không phải queue) là cố ý: khung IR Daikin mang TRỌN 35 byte trạng thái mỗi lần, nên chỉ
// trạng thái CUỐI có ý nghĩa. Ba lệnh dồn dập tự gộp thành một lần bắn — đúng ngữ nghĩa, không phải
// đánh đổi. Đồng thời đưa ac.send() (chặn ~150ms) ra khỏi callback MQTT: callback chạy đồng bộ
// trong mqtt.loop(), nên vài tin xếp hàng sau reconnect sẽ bắn liền nhau không khe hở.
bool     irPendingOn    = false;  // trạng thái mong muốn đang chờ gửi
bool     irHasPending   = false;  // có gì đang chờ hay không
uint32_t lastIrSendMs   = 0;      // lần bắn IR cuối, để ép IR_MIN_GAP_MS
uint32_t lastManualMs   = 0;      // lần lệnh tay cuối (0 = chưa có), để fusion tôn trọng ý user

uint32_t lastHeartbeatMs = 0;

IRDaikin152 ac(PIN_IR_SEND);   // 152-bit: NGẮN NHẤT trong các biến thể còn setPower thật
                               // (64/128 chỉ có setPowerToggle -> không diễn tả được bật/tắt).
                               // Ngắn hơn Daikin2 (312-bit) >2x -> bắn nhanh hơn, chặn CPU ít hơn,
                               // đỡ làm i2s_read lỡ nhịp khi đang stream mic.

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
#ifdef DISABLE_RADAR_FUSION
    // Radar tắt tạm trong env đo wakeword — xem platformio.ini [env:esp32s3_kws].
    // Lệnh tay (TOPIC_AC_CMD) vẫn giữ để còn kiểm được đường IR.
    Serial.printf("MQTT: sub %s (radar TẮT)\n", TOPIC_AC_CMD);
#else
    mqtt.subscribe(TOPIC_PRESENCE, 1);   // presence từ radar-node -> chính sách AC
    Serial.printf("MQTT: sub %s + %s\n", TOPIC_AC_CMD, TOPIC_PRESENCE);
#endif
  }
}

// Nhận home/room/presence từ radar-node: {"ts":..,"present":true|false}. Chạy trong loop()
// (mqtt.loop gọi đồng bộ). Chỉ cần cờ present + mốc thời gian nhận (phát hiện link chết).
// Payload cố định nên dò chuỗi như ac_cmd, khỏi kéo JSON lib.
void onPresence(const String &payload) {
  radarPresent = payload.indexOf("\"present\":true") >= 0;
  lastRadarSeq++;
  lastRadarMs = millis();
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

// requestAC — điểm vào DUY NHẤT để đổi trạng thái điều hoà. Không bắn IR ngay: chỉ ghi vào ô chờ,
// loop() gửi có nhịp. manual=true cho lệnh người dùng (giọng nói / app), false cho fusion tự động.
void requestAC(bool on, bool manual) {
  if (manual) lastManualMs = millis();
  irPendingOn  = on;
  irHasPending = true;
}

// flushIR — bắn ô chờ khi đã đủ khe hở. Gọi từ loop().
void flushIR(uint32_t now) {
  if (!irHasPending) return;
  if (lastIrSendMs != 0 && now - lastIrSendMs < IR_MIN_GAP_MS) return;  // chưa đủ khe, chờ vòng sau
  irHasPending = false;
  lastIrSendMs = now;
  sendAC(irPendingOn);
}

// Lệnh tay từ app (/api/ac) và voice (whisper -> ParseVietCommand) đều tới qua topic này.
void onMqtt(String &topic, String &payload) {
  if (topic == TOPIC_AC_CMD) {
    if (payload.indexOf("\"on\"") >= 0) {
      requestAC(true, true);    // lệnh tay: vào ô chờ, và khoá fusion khỏi ghi đè
    } else if (payload.indexOf("\"off\"") >= 0) {
      requestAC(false, true);
    } else {
      Serial.printf("[ir] ac_cmd không hiểu: %s\n", payload.c_str());
    }
    return;
  }
  if (topic == TOPIC_PRESENCE) {
    onPresence(payload);
  }
}

// ---- Init I2S RX: 16kHz, slot 32-bit, mono kênh trái (INMP441 L/R->GND) ----
void setupI2S() {
  i2s_config_t i2sConfig = {
      .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
      .sample_rate = SAMPLE_RATE,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,  // INMP441 xuất 24-bit trong khung 32-bit
      .channel_format = CFG_I2S_CHAN,                // xem chú thích ở khối CFG_I2S_CHAN
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

  // Pulldown chân SD, BẮT BUỘC sau i2s_set_pin (đặt trước sẽ bị ma trận I2S ghi đè). Không có nó,
  // chân SD hở hoặc đọc sai nửa khung (mic tri-state SD ở đó) sẽ hứng nhiễu/crosstalk và cho RMS
  // khác 0 bám theo giọng nói — trông y như đang chạy đúng, nhưng whisper không nghe ra chữ nào.
  // Có pulldown thì hai lỗi đó ra RMS = 0 và chẩn đoán được ngay. Dây dupont trong vỏ hộp tuột
  // cũng thành im lặng an toàn thay vì mở utterance cho nhiễu.
  gpio_set_pull_mode((gpio_num_t)PIN_I2S_SD, GPIO_PULLDOWN_ONLY);

  Serial.printf("I2S: sẵn sàng đọc INMP441 (16kHz, mono %s, slot 32-bit)\n",
                CFG_I2S_CHAN == I2S_CHANNEL_FMT_ONLY_LEFT ? "trái" : "phải");
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
// Bảng partition có sẵn otadata + app0/app1, không phải tự chế:
//   WROOM-32 (esp32dev)  default.csv        -> mỗi slot 1.25MB
//   ESP32-S3 (esp32s3)   default_16MB.csv   -> mỗi slot 6.5MB
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
  delay(500);
  // Lý do reset lần TRƯỚC: 1=POWERON 3=SW 4=PANIC 5=INT_WDT 6=TASK_WDT 9=BROWNOUT.
  // Giữ dòng này: brownout lặp lại là triệu chứng nguồn yếu, và nó chỉ lộ ra ở đây.
  // Trên WROOM-32 từng brownout ngay tại WiFi.mode() do inrush lúc calibrate radio —
  // hạ CPU/TX power KHÔNG cứu được, fix duy nhất là tụ 470-1000µF ở 5V-GND.
  Serial.printf("\n[boot] reset reason = %d\n", (int)esp_reset_reason());

  connectWiFi();
  setupOTA();     // sau connectWiFi (cần IP), trước I2S để lỡ I2S treo vẫn OTA cứu được
  ac.begin();     // IR Daikin (chân theo CFG_IR_PIN: WROOM=4, S3=8)
  setupI2S();

  webSocket.begin(BACKEND_WS_HOST, BACKEND_WS_PORT, BACKEND_WS_PATH);
  webSocket.onEvent(onWsEvent);
  webSocket.setReconnectInterval(3000);  // tự thử lại mỗi 3s nếu rớt kết nối

  mqtt.begin(MQTT_HOST, MQTT_PORT, net);
  mqtt.onMessage(onMqtt);
  connectMQTT();
}

// Chính sách AC: presence (từ radar-node qua MQTT) ổn định đủ lâu -> bật; vắng đủ lâu -> tắt.
// Lọc tinh (cự ly/năng lượng, chống báo giả xuyên tường) đã nằm ở radar-node/cấu hình LD2410.
void updateFusion(uint32_t now) {
#ifdef DISABLE_RADAR_FUSION
  // Tắt tạm trong env đo wakeword (esp32s3_kws): ac.send() chặn ~150ms, IR bắn xen ngang
  // làm bẩn mọi phép đo audio. Code giữ nguyên bên dưới, chỉ không chạy — cờ biên dịch chứ
  // không phải comment, để không quên bật lại. ⚠️ BẬT LẠI TRƯỚC KHI MERGE.
  (void)now;
  return;
#else
  // Link chết -> coi như KHÔNG có người. Không có timeout này, radar-node chết lúc đang
  // "có người" sẽ làm điều hoà chạy vĩnh viễn.
  uint32_t lastMs = lastRadarMs;
  bool radarAlive = lastMs != 0 && (now - lastMs) < RADAR_LINK_TIMEOUT_MS;
  bool p = radarAlive && radarPresent;

  if (p != present) {
    present = p;
    if (present) presenceSinceMs = now; else falseSinceMs = now;
  }

  bool before = occupied;
  // Vào: presence giữ LIÊN TỤC đủ lâu mới bật (chống báo giả thoáng qua).
  if (present && !occupied) {
    if (presenceSinceMs != 0 && now - presenceSinceMs >= ENTER_STABLE_MS) {
      occupied = true;
    }
  }
  // Ra: vắng đủ lâu.
  if (occupied && !present && falseSinceMs != 0) {
    if (now - falseSinceMs >= EXIT_TIMEOUT_MS) occupied = false;
  }

  if (occupied != before) {
    Serial.printf("[fusion] occupied -> %d\n", occupied);
    // Tôn trọng lệnh tay: người dùng vừa bảo tắt thì presence chớp một nhịp cũng không được bật lại.
    // Trạng thái occupied vẫn cập nhật (heartbeat/app đọc đúng), chỉ bỏ phần tự bắn IR.
    if (lastManualMs != 0 && now - lastManualMs < MANUAL_OVERRIDE_MS) {
      Serial.printf("[fusion] bỏ auto-send: có lệnh tay %lus trước\n",
                    (unsigned long)((now - lastManualMs) / 1000));
    } else {
      requestAC(occupied, false);
    }
  }
#endif  // DISABLE_RADAR_FUSION
}

void loop() {
  uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  ArduinoOTA.handle();  // rẻ khi rảnh (chỉ ngó gói UDP); chỉ chặn lúc đang nạp thật
  webSocket.loop();  // bơm sự kiện WS + xử lý reconnect nội bộ của lib

  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();  // keepalive MQTT (i2s_read timeout 200ms đảm bảo gọi đủ thường)

  updateFusion(now);
  flushIR(now);   // sau updateFusion: gộp được cả lệnh MQTT lẫn quyết định fusion trong cùng vòng

  if (STATUS_HEARTBEAT_MS && now - lastHeartbeatMs >= STATUS_HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    uint32_t lastMs = lastRadarMs;
    Serial.printf("[hb] presence=%d link=%s present=%d occupied=%d seq=%lu wifi=%d mqtt=%d\n",
                  radarPresent ? 1 : 0,
                  (lastMs != 0 && now - lastMs < RADAR_LINK_TIMEOUT_MS) ? "up" : "DOWN",
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
    float x = (float)(i2sRawBuf[i] >> MIC_SHIFT);  // khuếch đại so với >>16 để whisper nghe rõ

    // Thông cao TRƯỚC clamp: mục đích là bỏ hạ tần để nó khỏi chiếm headroom, nên phải lọc lúc
    // giá trị còn ở dải rộng. Lọc sau clamp thì tiếng nói đã bị chặt mất rồi, không cứu lại được.
    float y = x - hpfPrevX + HPF_R * hpfPrevY;
    hpfPrevX = x;
    hpfPrevY = y;

    int32_t s = (int32_t)y;
    if (s > 32767) s = 32767;                // clamp chống tràn int16 khi tiếng to
    else if (s < -32768) s = -32768;
    pcmBuf[i] = (int16_t)s;
  }

  float rms = computeRms(pcmBuf, samples);
  if (noiseFloor <= 0.0f) noiseFloor = rms;  // seed, khỏi chờ EMA bò lên từ 0 mất mấy giây

  // Ngưỡng tính TRƯỚC khi cập nhật nền, để một frame to không tự nâng ngưỡng của chính nó.
  float vadThreshold = noiseFloor * VAD_NOISE_MULT;
  if (vadThreshold < VAD_THRESHOLD_MIN) vadThreshold = VAD_THRESHOLD_MIN;

  if (rms > vadThreshold) {
    lastVoiceMs = now;
    if (!streaming && ++onsetFrames >= VAD_ONSET_FRAMES) {
      streaming   = true;
      onsetFrames = 0;
      Serial.println("VAD: phát hiện tiếng nói -> bắt đầu stream");
      // Gửi bù phần đã giữ TRƯỚC frame hiện tại để chuỗi PCM liền mạch, không mất âm đầu.
      if (webSocket.isConnected() && preRollFrames > 0) {
        webSocket.sendBIN(reinterpret_cast<uint8_t *>(preRoll),
                          preRollFrames * I2S_READ_SAMPLES * sizeof(int16_t));
      }
      preRollFrames = 0;
    }
  } else if (!streaming) {
    // Chuỗi đứt -> gai nhiễu đơn lẻ, quên hẳn. Không tích lũy qua các lần rời rạc.
    onsetFrames   = 0;
    preRollFrames = 0;
  }

  // Học nền nhiễu CHỈ từ frame dưới ngưỡng và CHỈ khi không streaming. Hai điều kiện đều cần:
  // học lúc streaming sẽ để tiếng nói kéo nền lên rồi tự tắt chính nó, còn học frame trên ngưỡng
  // sẽ để một tiếng động dài nâng nền lên và bỏ sót câu nói ngay sau đó.
  if (!streaming && rms <= vadThreshold) {
    noiseFloor += NOISE_EMA_ALPHA * (rms - noiseFloor);
  }

  // Đang chờ xác nhận onset: giữ frame lại. Chỉ giữ frame đủ độ dài để bước nhảy trong preRoll
  // luôn đúng I2S_READ_SAMPLES (i2s_read có thể trả về ít hơn khi timeout dở).
  if (!streaming && onsetFrames > 0 && preRollFrames < VAD_ONSET_FRAMES - 1 &&
      samples == I2S_READ_SAMPLES) {
    memcpy(&preRoll[preRollFrames * I2S_READ_SAMPLES], pcmBuf, samples * sizeof(int16_t));
    preRollFrames++;
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
    // In cả ngưỡng động + nền: không có hai số này thì không cách nào biết VAD đang so với cái gì.
    Serial.printf("RMS=%.1f nen=%.0f nguong=%.0f streaming=%s ws=%s\n", rms, noiseFloor,
                  vadThreshold, streaming ? "true" : "false",
                  webSocket.isConnected() ? "up" : "down");
  }
}
