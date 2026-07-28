// UART self-test cho LD2410 trên S2 Mini — chẩn đoán vì sao Moving=0 dù có cử động.
// KHÔNG đụng firmware chính (build bằng env riêng, xem platformio.ini [env:selftest]).
// Đếm byte THÔ nhận trên GPIO33 ở nhiều baud, rồi thử parser ld2410 chuẩn.
//   Nạp:    pio run -e selftest -t upload --upload-port <cổng>
//   Monitor: pio device monitor -e selftest
//
// Đọc kết quả:
//   - MỌI baud = 0 byte  -> dây LD2410 TX->GPIO33 đứt / mất GND chung / LD2410 TX chết.
//   - Có byte ở 256000   -> dây + module UART sống (lỗi nằm ở firmware chính, ít khả năng).
//   - Có byte ở baud KHÁC -> LD2410 bị đổi baud, sửa RADAR_BAUD cho khớp.
//   - Có byte 256000 nhưng isConnected=0 -> khung hỏng/nhiễu (dây dài, GND yếu).
#include <Arduino.h>
#include <ld2410.h>

static const uint8_t PIN_RX = 33;   // LD2410 TX -> chân này (S2 nhận)
static const uint8_t PIN_TX = 18;   // LD2410 RX <- chân này
ld2410 radar;

// Đếm byte thô nhận được trong 1.5s ở một baud (RX-only, không dùng parser).
void countBaud(uint32_t baud) {
  Serial1.begin(baud, SERIAL_8N1, PIN_RX, -1);
  delay(50);
  while (Serial1.available()) Serial1.read();   // xả đệm cũ
  uint32_t start = millis();
  uint32_t n = 0;
  while (millis() - start < 1500) {
    while (Serial1.available()) { Serial1.read(); n++; }
  }
  Serial.printf("[selftest] baud %-7u -> %lu byte/1.5s\n", baud, (unsigned long)n);
  Serial1.end();
  delay(50);
}

void setup() {
  Serial.begin(115200);
  uint32_t w = millis();
  while (!Serial && millis() - w < 2000) delay(10);
  delay(300);
  Serial.println("\n[selftest] === UART LD2410 (GPIO33 = S2 RX) ===");
  Serial.println("[selftest] Đang quơ tay trước radar trong lúc chạy để có dữ liệu.");
  countBaud(256000);
  countBaud(115200);
  countBaud(9600);

  Serial1.begin(256000, SERIAL_8N1, PIN_RX, PIN_TX);
  radar.begin(Serial1, false);
  Serial.println("[selftest] -> chạy parser ld2410 @256000, in mỗi 1s:");
}

void loop() {
  radar.read();
  static uint32_t t = 0;
  if (millis() - t >= 1000) {
    t = millis();
    Serial.printf("[selftest] isConnected=%d moving=%u/%ucm still=%u/%ucm\n",
                  radar.isConnected() ? 1 : 0,
                  (unsigned)radar.movingTargetEnergy(), (unsigned)radar.movingTargetDistance(),
                  (unsigned)radar.stationaryTargetEnergy(), (unsigned)radar.stationaryTargetDistance());
  }
}
