// Parser giao thức UART LD2410C cho ESP-IDF.
//
// Port 1:1 từ thư viện Arduino ncmreynolds/ld2410 (bản dùng tới 2026-08) — datasheet LD2410
// là ảnh scan nên KHÔNG viết lại theo trí nhớ: mọi offset, điều kiện và ngưỡng dưới đây lấy
// đúng từ read_frame_()/parse_data_frame_() của thư viện đó.
//
// Khung dữ liệu cơ bản (data_type 0x02, intra-frame length = 13, tổng 23 byte):
//   [0..3]   F4 F3 F2 F1        magic header
//   [4..5]   độ dài intra-frame (uint16 little-endian)
//   [6]      data_type: 0x02 basic | 0x01 engineering
//   [7]      0xAA
//   [8]      target state: bit0 = đang cử động, bit1 = đứng yên
//   [9..10]  cự ly mục tiêu cử động (cm, LE)
//   [11]     năng lượng mục tiêu cử động
//   [12..13] cự ly mục tiêu đứng yên (cm, LE)
//   [14]     năng lượng mục tiêu đứng yên
//   [15..16] cự ly phát hiện (cm, LE)
//   [17]     0x55        (luôn là 2 byte cuối của intra-frame, tính theo độ dài)
//   [18]     0x00
//   [19..22] F8 F7 F6 F5        footer
//
// Khung ACK lệnh (FD FC FB FA … 04 03 02 01) bị bỏ qua: node này chỉ đọc, không cấu hình radar.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "driver/uart.h"
#include "esp_err.h"

// Ảnh chụp số liệu radar mới nhất.
typedef struct {
  bool     uart_ok;        // có khung dữ liệu hợp lệ trong LD2410_STALE_MS gần nhất
  bool     moving;         // mục tiêu cử động (state bit0 + cự ly > 0 + năng lượng > 0)
  bool     still;          // mục tiêu đứng yên (state bit1 + cự ly > 0 + năng lượng > 0)
  uint16_t moving_dist_cm;
  uint16_t still_dist_cm;
  uint8_t  moving_energy;  // chặn trần 100 như thư viện gốc (thang LD2410 vốn 0..100)
  uint8_t  still_energy;
} ld2410_data_t;

// Mở UART tới radar rồi chạy task đọc khung nền. Gọi một lần lúc khởi động.
esp_err_t ld2410_start(uart_port_t port, int rx_pin, int tx_pin, uint32_t baud);

// Chép số liệu mới nhất ra ngoài (an toàn khi gọi từ task khác task đọc).
void ld2410_snapshot(ld2410_data_t *out);
