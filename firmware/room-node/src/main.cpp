// Room node — Wemos S2 Mini + radar LD2410.
//
// VAI TRÒ DUY NHẤT: đọc chân presence của radar rồi gửi sang voice-node (ESP32 WROOM-32)
// qua ESP-NOW. Không WiFi, không MQTT, không NTP, không OTA — mọi quyết định (fusion với
// PIR, bắn IR, relay lên MQTT) nằm ở voice-node.
//
// Wiring thật (xem docs/system-wiring.md):
//   LD2410 OUT -> GPIO16     LD2410 VCC -> 5V     LD2410 GND -> GND
//   LD2410 TX  -> GPIO33 (RX của S2)   LD2410 RX -> GPIO18 (TX của S2)
//
// Chân OUT chỉ cho 1 bit có/không người. UART cho thêm: mục tiêu đang cử động hay
// đứng yên, cự ly từng loại (cm), và NĂNG LƯỢNG phản xạ. Năng lượng + cự ly là thứ
// thay thế PIR trong việc chống báo giả xuyên tường: sóng 24GHz qua được tường mỏng
// nhưng suy hao mạnh, nên người ở phòng bên cho năng lượng thấp và cự ly xa.
//
// Luật trên chân OUT giữ NGUYÊN (đã nghiệm thu 2026-07-16) và vẫn là nguồn `present`.
// UART chỉ BỔ SUNG dữ liệu; UART hỏng thì gói vẫn hợp lệ, chỉ mất phần lọc tinh.
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
#include <ld2410.h>

#include "config.h"

// Bật/tắt đọc radar qua UART. Đặt 0 = CHỈ dùng chân OUT (hành vi đã chạy hôm qua)
// để test độc lập: nếu OUT sống lại khi tắt UART thì thủ phạm là việc init Serial1,
// không phải radar hư. Đặt 1 = đọc thêm năng lượng/cự ly qua UART.
#define RADAR_UART_ENABLED 0

// SELF-TEST GPIO16: đặt 1 để bỏ qua toàn bộ radar/ESP-NOW, chỉ kiểm chân 16 có sống
// không. Bật pull-up rồi pull-down nội, đọc lại: chân theo điện trở (up=1,down=0) =
// pin TỐT và không có gì ngoài kéo (radar không đẩy tín hiệu tới). Kẹt cùng giá trị
// bất kể pull = pin hư hoặc chập cứng ra GND/VCC.
// KẾT QUẢ 2026-07-21: pullup=1 pulldown=0 → GPIO16 TỐT, radar KHÔNG driving (mất nguồn
// radar hoặc OUT module chết). Lỗi nằm ở phần cứng radar, không phải S2.
#define PIN16_SELFTEST 0

// FACTORY-RESET radar qua UART (chạy 1 lần): đặt 1 để trả radar về mặc định, khôi phục
// chân OUT nếu bị cấu hình sai ghi vào flash. Cần UART HAI CHIỀU (S2 TX GPIO18 → radar
// RX). Nạp bản này, đọc serial thấy ack=1, rồi nạp lại bản thường (define này =0).
#define RADAR_FACTORY_RESET 0

// DIAG: test S2+radar riêng, KHÔNG ESP-NOW (khỏi nhiễu serial). Đọc CẢ chân OUT lẫn
// UART radar, in liên tục. OUT đổi theo người HOẶC uart=1 = radar SỐNG; cả hai câm
// khi radar chắc chắn có điện = module chết.
#define RADAR_DIAG 1

// ĐẨY GPIO16 = OUTPUT HIGH cố định (3.3V) để user đo tại chân OUT radar. An toàn vì
// self-test đã xác nhận chân OUT radar cao trở (pullup=1, không driving) → không tranh chấp.
#define PIN16_DRIVE_HIGH 0

// ---- Phần cứng ----
static const uint8_t PIN_PRESENCE = 16;  // LD2410 OUT (presence digital)
static const uint8_t PIN_RADAR_RX = 33;  // LD2410 TX -> chân này (S2 nhận)
static const uint8_t PIN_RADAR_TX = 18;  // LD2410 RX <- chân này (S2 gửi lệnh cấu hình)
static const uint32_t RADAR_BAUD  = 256000;  // tốc độ mặc định của LD2410

ld2410 radar;

// ---- Luật radar — CHỈNH CỰC NHẠY (2026-07-21) ----
// Đánh đổi: nhạy hơn = bắt người nhanh + giữ dai (không mất khi ngồi yên/tín hiệu chập),
// NHƯNG dễ báo giả hơn (nhiễu/người phòng bên có thể kích). Muốn bớt nhạy thì tăng
// PRESENCE_HOLD_MS lên lại, giảm RADAR_DEBOUNCE_MS. Bản nghiệm thu cũ: 1500/3000/200.
static const uint32_t PRESENCE_HOLD_MS  = 300;    // chỉ cần OUT HIGH ~0.3s là báo có người
static const uint32_t RADAR_DEBOUNCE_MS = 30000;  // giữ "còn người" tới 30s sau khi OUT rớt (chống mất khi ngồi yên)
static const uint32_t POLL_MS           = 100;    // đọc dày hơn để bắt cả xung ngắn
static const uint32_t RICH_SEND_MS      = 1000;  // nhịp gửi khi đang thấy mục tiêu

// ---- ESP-NOW ----
static const uint32_t HEARTBEAT_MS      = 5000;  // gửi lại dù không đổi -> bên nhận biết link còn sống
static const uint8_t  MAX_SEND_FAIL     = 3;     // FAIL liên tiếp bấy nhiêu -> nghi sai kênh, quét lại
static const uint32_t RESCAN_COOLDOWN_MS = 10000;
static const uint8_t  MSG_MAGIC         = 0xA7;  // lọc gói lạ/rác trên cùng kênh

// Payload phải GIỐNG HỆT bên voice-node. packed để 2 kiến trúc (ESP32-S2 vs ESP32)
// không chèn padding khác nhau làm lệch field.
// flags
static const uint8_t RF_UART_OK    = 1 << 0;  // UART radar đang trả dữ liệu hợp lệ
static const uint8_t RF_MOVING     = 1 << 1;  // có mục tiêu đang cử động
static const uint8_t RF_STATIONARY = 1 << 2;  // có mục tiêu đứng yên

typedef struct __attribute__((packed)) {
  uint8_t  magic;
  uint8_t  present;       // kết luận từ chân OUT — luật cũ, đã nghiệm thu
  uint32_t seq;
  uint8_t  flags;         // RF_*
  uint16_t movingDist;    // cm, chỉ có nghĩa khi RF_MOVING
  uint8_t  movingEnergy;  // 0-100
  uint16_t stillDist;     // cm, chỉ có nghĩa khi RF_STATIONARY
  uint8_t  stillEnergy;   // 0-100
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

// Danh sách kênh có SSID mục tiêu, sắp giảm dần theo RSSI. Nhà có nhiều phát cùng
// tên ở kênh khác nhau (đã gặp 'mp' ở kênh 1 VÀ 11); voice-node có thể bám cái yếu
// hơn. Chọn "mạnh nhất" rồi kẹt ở đó là gói bay vào hư không mãi. Nên khi gửi FAIL
// thì XOAY sang kênh ứng viên kế tiếp cho tới khi trúng kênh voice-node đang ở.
uint8_t  candCh[12];
int      candRssi[12];
uint8_t  candCount     = 0;
uint8_t  channelTryIdx = 0;

// Kết quả factory reset (chế độ RADAR_FACTORY_RESET) — in lặp trong loop để đọc được.
bool frAck = false, rsAck = false;

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

  // Gom MỌI kênh có SSID mục tiêu (khử trùng theo kênh, giữ RSSI mạnh nhất mỗi kênh).
  candCount = 0;
  for (int i = 0; i < n; i++) {
    if (WiFi.SSID(i) != String(WIFI_SSID)) continue;
    uint8_t ch = WiFi.channel(i);
    int rssi = WiFi.RSSI(i);
    int at = -1;
    for (int j = 0; j < candCount; j++) if (candCh[j] == ch) { at = j; break; }
    if (at >= 0) { if (rssi > candRssi[at]) candRssi[at] = rssi; }
    else if (candCount < 12) { candCh[candCount] = ch; candRssi[candCount] = rssi; candCount++; }
  }
  WiFi.scanDelete();

  if (candCount == 0) {
    Serial.printf("[espnow] KHÔNG thấy SSID '%s' -> chưa biết kênh, thử lại sau\n", WIFI_SSID);
    return false;
  }

  // Sắp giảm dần theo RSSI (nổi bọt, mảng tối đa 12 phần tử).
  for (int a = 0; a < candCount - 1; a++)
    for (int b = a + 1; b < candCount; b++)
      if (candRssi[b] > candRssi[a]) {
        uint8_t tc = candCh[a]; candCh[a] = candCh[b]; candCh[b] = tc;
        int tr = candRssi[a]; candRssi[a] = candRssi[b]; candRssi[b] = tr;
      }

  // channelTryIdx bắt đầu 0 (kênh mạnh nhất — đúng cho trường hợp thường); mỗi lần
  // gửi FAIL nó tăng lên để thử kênh ứng viên kế tiếp.
  uint8_t pick = channelTryIdx % candCount;
  channel = candCh[pick];
  Serial.printf("[espnow] %u kênh ứng viên, thử #%u -> kênh %u (rssi %d)\n",
                candCount, pick, channel, candRssi[pick]);
  for (int j = 0; j < candCount; j++)
    Serial.printf("[espnow]   ứng viên kênh %u rssi %d\n", candCh[j], candRssi[j]);
  return true;
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
  RadarMsg msg = {};
  msg.magic   = MSG_MAGIC;
  msg.present = present ? 1 : 0;
  msg.seq     = ++seq;

#if RADAR_UART_ENABLED
  if (radar.isConnected()) {
    msg.flags |= RF_UART_OK;
    if (radar.movingTargetDetected()) {
      msg.flags       |= RF_MOVING;
      msg.movingDist   = radar.movingTargetDistance();
      msg.movingEnergy = radar.movingTargetEnergy();
    }
    if (radar.stationaryTargetDetected()) {
      msg.flags      |= RF_STATIONARY;
      msg.stillDist   = radar.stationaryTargetDistance();
      msg.stillEnergy = radar.stationaryTargetEnergy();
    }
  }
#endif

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

#if PIN16_SELFTEST
  Serial.println("[pintest] SELF-TEST GPIO16 — bỏ qua radar/ESP-NOW");
  return;  // không init WiFi/ESP-NOW; loop() chỉ chạy bài test
#endif

#if PIN16_DRIVE_HIGH
  pinMode(PIN_PRESENCE, OUTPUT);
  digitalWrite(PIN_PRESENCE, HIGH);
  Serial.println("[drive] GPIO16 = OUTPUT HIGH 3.3V — đo tại chân OUT radar");
  return;
#endif

#if RADAR_DIAG
  pinMode(PIN_PRESENCE, INPUT);
  pinMode(PIN_RADAR_TX, INPUT);                               // không driving RX radar
  Serial1.begin(RADAR_BAUD, SERIAL_8N1, PIN_RADAR_RX, -1);    // RX-only
  radar.begin(Serial1, false);
  Serial.println("[diag] S2+radar riêng, không ESP-NOW");
  return;
#endif

#if RADAR_FACTORY_RESET
  // UART HAI CHIỀU để gửi lệnh vào radar (RX của radar ở GPIO18).
  Serial1.begin(RADAR_BAUD, SERIAL_8N1, PIN_RADAR_RX, PIN_RADAR_TX);
  radar.begin(Serial1, false);
  delay(700);                       // chờ radar khởi động xong mới nhận lệnh
  Serial.println("[reset] gửi factory reset + restart...");
  frAck = radar.requestFactoryReset();
  delay(200);
  rsAck = radar.requestRestart();
  Serial.printf("[reset] factory=%d restart=%d\n", frAck, rsAck);
  return;                           // loop() in lặp kết quả để đọc được
#endif

  // INPUT_PULLDOWN (không phải INPUT trần): khi radar hở/chết, chân OUT thả nổi sẽ
  // nhặt nhiễu → với ngưỡng nhạy 300ms dễ đẻ presence GIẢ. Pulldown ghì chân về 0 khi
  // radar không driving; radar OUT là push-pull nên khi phát hiện thật vẫn kéo HIGH thắng.
  pinMode(PIN_PRESENCE, INPUT_PULLDOWN);

#if RADAR_UART_ENABLED
  // UART radar RX-only: nghe chân TX radar ở GPIO33, KHÔNG driving RX radar.
  // TX=-1: Serial1 không chiếm GPIO18; ép input cao trở để không phát nhiễu.
  pinMode(PIN_RADAR_TX, INPUT);
  Serial1.begin(RADAR_BAUD, SERIAL_8N1, PIN_RADAR_RX, -1);
  if (radar.begin(Serial1, false)) {
    Serial.println("[radar] UART RX-only mở, chờ khung dữ liệu");
  } else {
    Serial.println("[radar] UART KHÔNG mở được — chạy tiếp bằng chân OUT");
  }
#else
  // TEST ĐỘC LẬP: KHÔNG init UART. Hai chân UART để cao trở, không đụng radar.
  pinMode(PIN_RADAR_TX, INPUT);
  pinMode(PIN_RADAR_RX, INPUT);
  Serial.println("[radar] UART TẮT — chỉ dùng chân OUT (test độc lập)");
#endif

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

#if PIN16_DRIVE_HIGH
  digitalWrite(PIN_PRESENCE, HIGH);   // giữ mức cao
  return;
#endif

#if RADAR_DIAG
  radar.read();
  // Quét OUT MỖI VÒNG (không chờ) và CHỐT: có từng lên HIGH trong 500ms qua không.
  // Bắt được cả xung ngắn < POLL_MS mà bản in mỗi 500ms sẽ trượt.
  static bool seenHigh = false;
  if (digitalRead(PIN_PRESENCE) == HIGH) seenHigh = true;
  static uint32_t lastD = 0;
  if (now - lastD >= 500) {
    lastD = now;
    Serial.printf("[diag] OUT_now=%d OUT_seenHigh500ms=%d  uart=%d  moving=%u/%ucm  still=%u/%ucm\n",
                  digitalRead(PIN_PRESENCE), seenHigh ? 1 : 0, radar.isConnected() ? 1 : 0,
                  (unsigned)radar.movingTargetEnergy(), (unsigned)radar.movingTargetDistance(),
                  (unsigned)radar.stationaryTargetEnergy(), (unsigned)radar.stationaryTargetDistance());
    seenHigh = false;
  }
  return;
#endif

#if RADAR_FACTORY_RESET
  static uint32_t lastR = 0;
  if (now - lastR >= 1000) {
    lastR = now;
    Serial.printf("[reset] factory=%d restart=%d — XONG, nạp lại bản thường\n", frAck, rsAck);
  }
  return;
#endif

#if PIN16_SELFTEST
  static uint32_t lastTest = 0;
  if (now - lastTest >= 1000) {
    lastTest = now;
    pinMode(PIN_PRESENCE, INPUT_PULLUP);   delay(5); int up = digitalRead(PIN_PRESENCE);
    pinMode(PIN_PRESENCE, INPUT_PULLDOWN); delay(5); int dn = digitalRead(PIN_PRESENCE);
    pinMode(PIN_PRESENCE, INPUT);          // trả về input thường
    int fl = digitalRead(PIN_PRESENCE);
    Serial.printf("[pintest] GPIO16  pullup=%d  pulldown=%d  float=%d\n", up, dn, fl);
  }
  return;
#endif

  // Bơm parser UART mỗi vòng. Khung LD2410 tới ~10 lần/giây ở 256000 baud; đọc thưa
  // là tràn bộ đệm nối tiếp và mất khung.
#if RADAR_UART_ENABLED
  radar.read();
#endif

  // Chưa biết kênh -> quét lại định kỳ, đừng gửi mù.
  if (channel == 0) {
    if (now - lastScanMs >= RESCAN_COOLDOWN_MS && learnChannel()) applyChannel();
    return;
  }

  // Gửi FAIL liên tiếp -> voice-node đang ở kênh khác -> XOAY sang kênh ứng viên kế
  // tiếp. Nếu đã có danh sách kênh thì đổi NGAY (không quét lại, không chờ cooldown)
  // để hội tụ nhanh; chỉ quét lại khi đã vòng hết danh sách (môi trường có thể đổi).
  if (sendFailStreak >= MAX_SEND_FAIL) {
    sendFailStreak = 0;
    channelTryIdx++;
    bool cycledAll = (candCount == 0) || (channelTryIdx % candCount == 0);
    if (!cycledAll) {
      channel = candCh[channelTryIdx % candCount];
      Serial.printf("[espnow] FAIL -> đổi sang kênh ứng viên %u (#%u)\n",
                    channel, channelTryIdx % candCount);
      applyChannel();
    } else if (now - lastScanMs >= RESCAN_COOLDOWN_MS) {
      Serial.println("[espnow] đã thử hết kênh ứng viên -> quét lại");
      if (learnChannel()) applyChannel();
    }
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

#if RADAR_UART_ENABLED
  // Đang thấy mục tiêu -> gửi dày hơn để voice-node có số liệu năng lượng/cự ly tươi.
  bool anyTarget = radar.isConnected() &&
                   (radar.movingTargetDetected() || radar.stationaryTargetDetected());
  if (anyTarget && now - lastSendMs >= RICH_SEND_MS) sendPresence();
#endif

  // Heartbeat: bên nhận dùng nó để phát hiện link chết. Không có nó, voice-node không
  // phân biệt được "phòng vẫn trống" với "board này đã chết".
  if (now - lastSendMs >= HEARTBEAT_MS) sendPresence();
}
