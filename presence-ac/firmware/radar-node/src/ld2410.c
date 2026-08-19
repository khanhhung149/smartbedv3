#include "ld2410.h"

#include <inttypes.h>
#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "ld2410";

// Khung dài nhất (engineering) vẫn dưới 64 byte — cùng trần với thư viện gốc.
#define LD2410_MAX_FRAME 64

// Bao lâu không có khung hợp lệ thì coi UART chết. Thư viện Arduino để 100ms, nhưng radar chỉ
// bắn ~10 khung/s nên chỉ cần trượt một khung là isConnected() chớp tắt — mà uart_ok=false làm
// tele/<T>/SENSOR báo Moving/Static = 0, đúng dấu hiệu mà docs/system-wiring.md dạy đọc là
// "mất GND". 500ms = 5 chu kỳ khung: đủ rộng để không báo động giả, vẫn đủ nhanh so với nhịp
// telemetry 3s.
#define LD2410_STALE_MS 500

static portMUX_TYPE  s_lock = portMUX_INITIALIZER_UNLOCKED;
static ld2410_data_t s_data;          // được task đọc ghi, ai cũng đọc được qua snapshot
static int64_t       s_last_frame_us; // mốc khung dữ liệu hợp lệ gần nhất

// Bộ ráp khung: gom byte từ UART, chỉ giao khung khi header + độ dài + footer đều khớp.
typedef struct {
  uint8_t buf[LD2410_MAX_FRAME];
  uint8_t pos;
  bool    ack_frame;  // true = khung ACK lệnh (bỏ qua), false = khung dữ liệu
} frame_asm_t;

static const uint8_t DATA_HDR[4] = {0xF4, 0xF3, 0xF2, 0xF1};
static const uint8_t CMD_HDR[4]  = {0xFD, 0xFC, 0xFB, 0xFA};

// Kiểm footer tại vị trí đã biết (khung đã nhận đủ độ dài khai báo).
static bool footer_ok(const frame_asm_t *f) {
  const uint8_t *tail = &f->buf[f->pos - 4];
  if (f->ack_frame) {
    return tail[0] == 0x04 && tail[1] == 0x03 && tail[2] == 0x02 && tail[3] == 0x01;
  }
  return tail[0] == 0xF8 && tail[1] == 0xF7 && tail[2] == 0xF6 && tail[3] == 0xF5;
}

// Bóc khung dữ liệu đã nhận đủ vào s_data. Trả false nếu khung hỏng.
static bool parse_data_frame(const frame_asm_t *f) {
  const uint16_t intra = (uint16_t)f->buf[4] | ((uint16_t)f->buf[5] << 8);
  if (f->pos != intra + 10) return false;

  const uint8_t data_type = f->buf[6];
  if (data_type != 0x01 && data_type != 0x02) return false;

  // 0x55 0x00 LUÔN là 2 byte cuối của intra-frame; ở khung engineering vị trí khác khung basic
  // nên phải tính theo độ dài, không hằng số hoá.
  if (f->buf[7] != 0xAA || f->buf[intra + 4] != 0x55 || f->buf[intra + 5] != 0x00) return false;

  const uint8_t  state         = f->buf[8];
  uint16_t       moving_dist   = 0;
  uint16_t       still_dist    = 0;
  const uint8_t  moving_energy = f->buf[11];
  const uint8_t  still_energy  = f->buf[14];
  memcpy(&moving_dist, &f->buf[9],  sizeof(uint16_t));   // payload little-endian, trùng endian chip
  memcpy(&still_dist,  &f->buf[12], sizeof(uint16_t));

  portENTER_CRITICAL(&s_lock);
  // Điều kiện "phát hiện" giống hệt thư viện gốc: chỉ cờ trạng thái là chưa đủ, phải có cả cự ly
  // và năng lượng > 0 — luật presence trong main.c dựa trên đúng ngữ nghĩa này.
  s_data.moving         = (state & 0x01) && moving_dist > 0 && moving_energy > 0;
  s_data.still          = (state & 0x02) && still_dist > 0 && still_energy > 0;
  s_data.moving_dist_cm = moving_dist;
  s_data.still_dist_cm  = still_dist;
  s_data.moving_energy  = moving_energy > 100 ? 100 : moving_energy;
  s_data.still_energy   = still_energy;
  s_last_frame_us       = esp_timer_get_time();
  portEXIT_CRITICAL(&s_lock);
  return true;
}

// Nạp một byte vào bộ ráp khung (máy trạng thái: header -> độ dài -> thân -> footer).
static void feed_byte(frame_asm_t *f, uint8_t b) {
  const uint8_t pos = f->pos;

  // Giai đoạn A: dò magic header, chỉ chốt khi đủ 4 byte.
  if (pos == 0) {
    if (b == 0xF4) {
      f->buf[0] = b; f->pos = 1; f->ack_frame = false;
    } else if (b == 0xFD) {
      f->buf[0] = b; f->pos = 1; f->ack_frame = true;
    }
    return;  // byte rác: bỏ, quét tiếp
  }
  if (pos < 4) {
    const uint8_t expected = (f->ack_frame ? CMD_HDR : DATA_HDR)[pos];
    if (b == expected) {
      f->buf[pos] = b; f->pos = pos + 1;
    } else if (b == 0xF4) {          // header mới cắt ngang header dở
      f->buf[0] = b; f->pos = 1; f->ack_frame = false;
    } else if (b == 0xFD) {
      f->buf[0] = b; f->pos = 1; f->ack_frame = true;
    } else {
      f->pos = 0;
    }
    return;
  }

  // Giai đoạn B: 2 byte độ dài rồi tới thân khung.
  f->buf[pos] = b;
  f->pos = pos + 1;

  if (pos == 5) {
    const uint16_t intra = (uint16_t)f->buf[4] | ((uint16_t)f->buf[5] << 8);
    if (intra == 0 || intra + 10 > LD2410_MAX_FRAME) f->pos = 0;  // độ dài vô lý -> bỏ khung
    return;
  }
  if (pos < 6) return;

  const uint16_t intra = (uint16_t)f->buf[4] | ((uint16_t)f->buf[5] << 8);
  if (f->pos < intra + 10) return;   // chưa đủ byte

  if (footer_ok(f) && !f->ack_frame) parse_data_frame(f);  // khung ACK lệnh: bỏ, node chỉ đọc
  f->pos = 0;
}

static void ld2410_task(void *arg) {
  const uart_port_t port = (uart_port_t)(intptr_t)arg;
  frame_asm_t       asmb = {0};
  uint8_t           chunk[128];

  while (true) {
    const int n = uart_read_bytes(port, chunk, sizeof(chunk), pdMS_TO_TICKS(20));
    for (int i = 0; i < n; i++) feed_byte(&asmb, chunk[i]);
  }
}

esp_err_t ld2410_start(uart_port_t port, int rx_pin, int tx_pin, uint32_t baud) {
  const uart_config_t cfg = {
      .baud_rate = (int)baud,
      .data_bits = UART_DATA_8_BITS,
      .parity    = UART_PARITY_DISABLE,
      .stop_bits = UART_STOP_BITS_1,
      .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
      .source_clk = UART_SCLK_DEFAULT,
  };

  // Đệm RX 2KB = ~87 khung basic: task đọc mỗi 20ms nên thừa sức, nhưng rộng tay thì một nhịp
  // trễ (OTA, publish MQTT chậm) không làm mất khung.
  esp_err_t err = uart_driver_install(port, 2048, 0, 0, NULL, 0);
  if (err != ESP_OK) return err;
  err = uart_param_config(port, &cfg);
  if (err != ESP_OK) return err;
  err = uart_set_pin(port, tx_pin, rx_pin, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
  if (err != ESP_OK) return err;

  if (xTaskCreate(ld2410_task, "ld2410", 3072, (void *)(intptr_t)port, 6, NULL) != pdPASS) {
    return ESP_ERR_NO_MEM;
  }
  ESP_LOGI(TAG, "UART%d mở @%" PRIu32 " baud (RX=%d TX=%d), chờ khung dữ liệu", port, baud, rx_pin, tx_pin);
  return ESP_OK;
}

void ld2410_snapshot(ld2410_data_t *out) {
  portENTER_CRITICAL(&s_lock);
  *out = s_data;
  const int64_t last = s_last_frame_us;
  portEXIT_CRITICAL(&s_lock);

  out->uart_ok = last != 0 && (esp_timer_get_time() - last) < (LD2410_STALE_MS * 1000);
  if (!out->uart_ok) {
    // Số liệu cũ quá thì đừng phát tiếp: main.c chỉ tin moving/still khi uart_ok.
    out->moving = false;
    out->still  = false;
  }
}
