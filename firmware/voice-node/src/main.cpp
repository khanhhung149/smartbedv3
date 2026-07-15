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
#include <WebSocketsClient.h>
#include <driver/i2s.h>
#include <math.h>

#include "config.h"

// ---- Phần cứng (WROOM-32) ----
static const uint8_t PIN_I2S_SCK = 26;  // BCLK, output từ ESP
static const uint8_t PIN_I2S_WS  = 25;  // LRCL/WS, output từ ESP
static const uint8_t PIN_I2S_SD  = 34;  // DOUT từ mic, input-only trên WROOM-32

static const i2s_port_t I2S_PORT     = I2S_NUM_0;
static const uint32_t   SAMPLE_RATE  = 16000;   // đúng contract backend

// Mỗi lần đọc lấy 256 mẫu 32-bit (~16ms @16kHz) — đủ nhỏ để không tràn RAM,
// đủ lớn để không spam quá nhiều gói WS nhỏ.
static const size_t I2S_READ_SAMPLES = 256;

// VAD năng lượng: ngưỡng RMS cố định, CẦN TUNE thực địa (phụ thuộc mic, gain,
// tiếng ồn nền quạt/AC — xem risk trong plan). im lặng SILENCE_MS liên tục
// mới coi là hết câu, tránh cắt giữa câu do ngắt quãng ngắn.
static const float    VAD_THRESHOLD = 800.0f;
static const uint32_t SILENCE_MS    = 800;

WebSocketsClient webSocket;

static int32_t i2sRawBuf[I2S_READ_SAMPLES];  // dữ liệu thô từ I2S (32-bit slot)
static int16_t pcmBuf[I2S_READ_SAMPLES];     // PCM16 sau khi hạ bit, gửi thẳng qua WS

bool     streaming   = false;  // đang trong một utterance -> có gửi frame
uint32_t lastVoiceMs = 0;      // lần cuối RMS vượt ngưỡng
uint32_t lastLogMs   = 0;      // throttle log Serial, tránh spam mỗi ~16ms

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

// ---- Init I2S RX: 16kHz, slot 32-bit, mono kênh trái (INMP441 L/R->GND) ----
void setupI2S() {
  i2s_config_t i2sConfig = {
      .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
      .sample_rate = SAMPLE_RATE,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,  // INMP441 xuất 24-bit trong khung 32-bit
      .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,   // mono, đúng kênh trái đã chọn qua L/R->GND
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

void setup() {
  Serial.begin(115200);
  delay(200);

  connectWiFi();
  setupI2S();

  webSocket.begin(BACKEND_WS_HOST, BACKEND_WS_PORT, BACKEND_WS_PATH);
  webSocket.onEvent(onWsEvent);
  webSocket.setReconnectInterval(3000);  // tự thử lại mỗi 3s nếu rớt kết nối
}

void loop() {
  uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  webSocket.loop();  // bơm sự kiện WS + xử lý reconnect nội bộ của lib

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
    pcmBuf[i] = (int16_t)(i2sRawBuf[i] >> 16);
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
